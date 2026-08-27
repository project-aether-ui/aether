--!strict
--[[
	spektr/zune_host · Native — the framework running AS the client (ms-52 M7).

	    zune run pkgs/ui/hosts/zune/src/Native.luau --screen shop
	    zune run pkgs/ui/hosts/zune/src/Native.luau --screen settings
	    zune run pkgs/ui/hosts/zune/src/Native.luau --check     (headless parity)

	WHAT MAKES THIS DIFFERENT FROM Server.luau
	es9, on that one: "this is a direct port of the webcanvas server-sided
	rendering host we prototyped -- I wanted to also use another runtime
	specifically to take advantage of rendering in a different environment that
	would allow us to run the ui framework on the client."

	Server.luau is the same server-driven shape with a different socket: Luau
	computes, a browser paints, frames cross a transport. This has NO TRANSPORT.
	The Luau process owns a window and issues the draw calls itself:

	    App + Session -> Live.Frame -> GDI -> a window
	                  <- Session <- window procedure <- OS input

	Both hosts stay. They are fed byte-identical frames, so a disagreement between
	them is a painter bug by construction and an agreement that is wrong is a
	framework bug. Neither conclusion is available with one display.

	HOW IT IS VERIFIED WITHOUT EYES: `--check` paints a real screen off-screen and
	reads pixels back with `GetPixel`, asserting the colour at a node's centre is
	the colour that node declared. That is the parity instrument -- the same role
	`--audit` plays for the browser -- and it is why this could be built without
	watching it.
]]

local App = require("../../web/src/App")
local Win32 = require("./Win32")
local NativePainter = require("./NativePainter")
local RasterPainter = require("./RasterPainter")
--- The DIB present, split out of the rasteriser so the rasteriser is
--- platform-neutral (ms-53 P2). This host owns a window, so requiring it here
--- is correct; the headless CLI must never reach it.
local WindowsPresenter = require("./WindowsPresenter")
local WindowedPainter = require("./WindowedPainter")

local user32 = Win32.user32
local gdi = Win32.gdi32
local task = (zune :: any).task

local ARGS: { string } = (zune :: any).process.args :: any

--- `--switch-mode sync|wait` for the switcher scene (ms-53 D6).
local switchMode: string? = nil
for i, a in ipairs((zune :: any).process.args) do
	if a == "--switch-mode" then
		switchMode = (zune :: any).process.args[i + 1]
	end
end

local screenChoice: string? = nil
for i, a in ipairs(ARGS) do
	if a == "--screen" then
		screenChoice = ARGS[i + 1]
	end
end

--- GDI metrics, so layout measures the font the painter draws with. Without
--- this the two disagreed by up to 21% on narrow glyphs.
--- `--raster` selects the Rust backend. OPT-IN, not default, and that is a
--- deliberate product decision rather than caution: the library is a build
--- artifact, and a clone with no Rust toolchain must still run. GDI stays the
--- fallback so `zune run Native.luau` works with nothing installed.
local useRaster = table.find(ARGS, "--raster") ~= nil
--- `--vello` selects the vello_cpu backend and implies `--raster`. Both live
--- behind the same C ABI, so this picks a rasteriser, not a code path.
--- VELLO_CPU IS THE DEFAULT RUST BACKEND (ms-52 M10).
---
--- It rasterises shop's frame in 1.70 ms against tiny-skia's 7.41 ms and takes
--- the screen from 61 to 119 fps, while agreeing with tiny-skia on 100% of
--- sampled pixels -- 80% of them bit-identical, the rest within two channels of
--- premultiplied rounding.
---
--- tiny-skia STAYS, selectable with `--tiny-skia`, and is not dead weight: it is
--- the second opinion. Two backends behind one ABI fed byte-identical frames
--- mean a disagreement is a backend bug by construction, and `--compare-raster`
--- is the only cheap way to tell one from a display-list bug.
--- `--gpu` presents through a wgpu swapchain instead of blitting pixels.
---
--- OPT-IN, and it must stay so: it needs a library built with the `gpu` feature
--- and a GPU that can present to this window, neither of which a fresh clone has.
--- GDI remains the zero-dependency floor and vello_cpu the default upgrade.
--- `--gpu-check` is its OWN flag, not `--gpu --check`.
---
--- The checks in this file are a chain of early returns, and the GDI `--check`
--- block returns long before the window exists -- so `--gpu --check` silently ran
--- the GDI check and reported OK about a painter it never touched. That is the
--- second time a gate has done this (`--vello --check` did it too), so this one
--- cannot be reached by accident.
--- `--poison=<name>` ARMS A DELIBERATE DEFECT.
---
--- Not a debugging aid: it is how `scripts/poison_matrix.luau` asks each gate to
--- prove it can still fail. Every gate here is a set of assertions someone
--- believed would catch a wrong picture, and four of them turned out to be
--- satisfiable by a backend that drew NOTHING -- the vello_cpu port rendered
--- black over the whole screen and this file reported 100% pixel parity and OK.
---
--- Arming a poison and requiring RED is the only way to know a gate still bites.
local poisonName: string? = nil
for _, a in ipairs(ARGS) do
	local name = string.match(a, "^%-%-poison=(.+)$")
	if name then
		poisonName = name
	end
end

local gpuCheck = table.find(ARGS, "--gpu-check") ~= nil
local useGpu = table.find(ARGS, "--gpu") ~= nil or gpuCheck
local useTinySkia = table.find(ARGS, "--tiny-skia") ~= nil
local useVello = table.find(ARGS, "--vello") ~= nil
if useVello or useTinySkia then
	useRaster = true
end
local rasterBackend = if useTinySkia then 0 else 1
--- `--backdrop` paints loud bars behind the screen, so translucency is judgeable
--- by eye. Without something behind them, a 90%-opaque panel and a 100%-opaque
--- one look identical on a flat background.
local useBackdrop = table.find(ARGS, "--backdrop") ~= nil

--- MEASURE WITH WHATEVER WILL PAINT.
---
--- The vello backend draws its own glyphs, so layout must measure with vello's
--- font -- not GDI's. Handing the wrong provider here is precisely the M7 defect
--- (measured with one font, painted with another: 21% out on a narrow run, and
--- `AutomaticSize` sizing to a width nothing would draw), just with the two
--- swapped over.
---
--- Resolved BEFORE `App.create` because the text provider cannot be replaced
--- afterwards -- `Text.SetProvider` never clobbers an installed one.
local metricsProvider = NativePainter.Metrics
local metricsOwner = "GDI"
if (useRaster or useGpu) and not useTinySkia then
	local ok = RasterPainter.Available()
	if ok and RasterPainter.LoadFont() ~= nil then
		metricsProvider = RasterPainter.Metrics
		metricsOwner = "vello"
	end
end

if poisonName then
	NativePainter.SetPoison(poisonName)
	local armed = RasterPainter.SetPoison(poisonName)
	--- REPORTED, because "the gate did not notice" and "the sabotage never
	--- happened" look identical from outside and mean opposite things. A library
	--- built without `--features poison` has no `ar_poison` symbol at all.
	print(`  poison: {poisonName} (rust: {if armed then "armed" else "UNAVAILABLE -- build with --features poison"})`)
end

--- `--reload`: rebuild the tree when its source changes, without restarting.
---
--- OPT-IN, because it swaps `require` for `Reload.Load` on the application
--- module and that is a different loader with different failure modes. A run
--- that is not iterating should not pay for one.
---
--- The HOT ROOT is the application's own source. Everything beneath it --
--- Aether, vide, the vendored packages -- comes from the normal cached require
--- and does NOT reload. That boundary is the design, not a limitation: editing a
--- screen should not rebuild the framework. `--reload-root <path>` widens it,
--- and widening it to `pkgs/ui` does make Aether itself hot, at a measured cost.
local useReload = table.find(ARGS, "--reload") ~= nil
--- THE DEFAULT DEPENDS ON WHAT IS MOUNTED, because "the application's own
--- source" is a different directory in each case.
---
--- A screen is a kit, so `pkgs/ui/kits` covers it and leaves the framework
--- cached -- 17.8-26.5 ms a reload. A STORY may live under any package, and its
--- subject is usually a component rather than a kit, so nothing narrower than
--- `pkgs/ui` covers the file being edited. That makes Aether hot too and costs
--- 120-145 ms, which is still five times cheaper than a restart and is the right
--- trade when the thing being iterated on is a component.
---
--- `--reload-root <path>` overrides either.
local reloadRoot: (string | { string }) = if table.find(ARGS, "--story")
	then { "pkgs/ui/kits", "pkgs/ui/components", "pkgs/ui/tokens", "pkgs/ui/motion" }
	else "pkgs/ui/kits"
for i, a in ipairs(ARGS) do
	if a == "--reload-root" then
		reloadRoot = ARGS[i + 1] or reloadRoot
	end
end

local APP_PATH = "pkgs/ui/hosts/web/src/App.luau"
local Reload = require("./Reload")
local Stories = require("./Stories")

--- `--story <id>` mounts ONE isolated state instead of a screen; `--stories`
--- lists what there is. See `Stories.luau` for the file format.
local storyQuery: string? = nil
for i, a in ipairs(ARGS) do
	if a == "--story" then
		storyQuery = ARGS[i + 1]
	end
end
local listStories = table.find(ARGS, "--stories") ~= nil

if listStories then
	local all = Stories.Discover("pkgs/ui")
	print(`{#all} story/stories in {#Stories.Files(all)} file(s):`)
	local lastTitle: string? = nil
	for _, st in ipairs(all) do
		if st.Title ~= lastTitle then
			print(`  {st.Title}`)
			lastTitle = st.Title
		end
		print(`    {st.Name}`)
	end
	return
end

--- REDISCOVERED ON EVERY BUILD, not looked up once.
---
--- A story is only hot if its FILE is re-read, and `Discover` is what re-reads
--- it. Resolving the story once at startup and reusing the thunk would keep the
--- first version alive forever -- the reload would fire, rebuild the tree, and
--- mount the same closure it mounted before. The screen would change only when
--- something OTHER than the story file did, which is the worst kind of
--- half-working.
--- `--browse` opens the picker: every story in a sidebar, click to mount.
local browse = table.find(ARGS, "--browse") ~= nil
local Browser = require("./Browser")
--- The SELECTED story, and the one a click has asked for. Two variables because
--- a click happens inside the tree and the rebuild has to happen outside it --
--- destroying a tree from inside a handler that tree owns is how a use-after-free
--- looks in a reactive system.
local selectedStory: string? = nil
local pendingStory: string? = nil
--- The browse window is a normal size. It used to be sized to the whole story
--- list, because P1 believed the list could not scroll; ms-53 D2 found that it
--- always could and that what was broken was the CLAMP. The workaround is gone.

local function resolveStory(): (() -> any)?
	if browse then
		local all = Stories.Discover("pkgs/ui", if useReload then Reload.Load else nil)
		if selectedStory == nil and #all > 0 then
			selectedStory = all[1].Id
		end
		return Browser.Build({
			Stories = all,
			Selected = selectedStory,
			OnSelect = function(id: string)
				pendingStory = id
			end,
		})
	end
	if storyQuery == nil then
		return nil
	end
	local all = Stories.Discover("pkgs/ui", if useReload then Reload.Load else nil)
	local found = Stories.Find(all, storyQuery)
	if found == nil then
		error(`no story matches "{storyQuery}". Run --stories to see what there is.`, 0)
	end
	return found.Build
end

local function buildApp(): any
	if not useReload then
		local st = resolveStory()
		return App.create({
			Screen = screenChoice,
			Story = st,
			Metrics = metricsProvider,
			SwitchMode = switchMode,
		})
	end
	Reload.SetHotRoot(reloadRoot)
	--- ONE `BeginBuild` FOR THE WHOLE REBUILD, then every load inside it adds to
	--- the watch set: the story files discovered here AND the app module below.
	--- Without the explicit boundary each load cleared the previous one's files
	--- and only the app stayed watched, so editing a story changed nothing.
	Reload.BeginBuild()
	local story = resolveStory()
	return Reload.Load(APP_PATH).create({
		Screen = screenChoice,
		Story = story,
		Metrics = metricsProvider,
		SwitchMode = switchMode,
	})
end

local app = buildApp()
local session = app.Session
local WIDTH, HEIGHT = app.Width, app.Height

--------------------------------------------------------------------------------
-- `--check`: paint off-screen, read the pixels back, assert parity.
--------------------------------------------------------------------------------

--- `--raster --check`: does the Rust backend actually BLEND on a real screen?
---
--- The GDI check asserts geometry -- which node owns which pixel. It cannot
--- assert alpha, because GDI has none: every translucent node draws opaque and
--- the grid still agrees with itself.
---
--- This asserts the thing that made the backend worth building. On ShopUI 49 of
--- 85 filled rects are translucent; for one of them, the pixel must be a BLEND of
--- its colour and what lies beneath, which means matching NEITHER exactly.
--- `--compare`: the same frame, both painters, quantified.
---
--- The question es9 could not answer by eye -- "is the translucency actually
--- happening?" -- has a numeric answer, because both painters consume BYTE
--- IDENTICAL frames. Where they disagree is exactly what the Rust backend does
--- that GDI cannot, and a translucent node is the only place they should.
if table.find(ARGS, "--compare") then
	local ok, why = RasterPainter.Available()
	assert(ok, why)

	local frame = session.Snapshot()

	--- GDI into a memory bitmap.
	local screenDC = user32.GetDC(Win32.null)
	local gdiDC = gdi.CreateCompatibleDC(screenDC)
	gdi.SelectObject(gdiDC, gdi.CreateCompatibleBitmap(screenDC, WIDTH, HEIGHT))
	NativePainter.Paint(gdiDC, frame)

	--- Rust into its own surface.
	local surface = RasterPainter.NewSurface(WIDTH, HEIGHT, rasterBackend)
	assert(surface, "the raster surface should allocate")
	RasterPainter.Paint(surface :: any, frame)

	--- COLORREF is BGR and the raster surface answers RGB, so one has to be
	--- flipped before they can be compared at all. Comparing them raw would
	--- report every pixel as differing and prove nothing.
	local function gdiAsRgb(x: number, y: number): number
		local bgr = gdi.GetPixel(gdiDC, x, y)
		if bgr == 0xFFFFFFFF then
			return bgr
		end
		local b = bit32.band(bit32.rshift(bgr, 16), 0xFF)
		local g = bit32.band(bit32.rshift(bgr, 8), 0xFF)
		local r = bit32.band(bgr, 0xFF)
		return r * 65536 + g * 256 + b
	end

	local STEP = 8
	local sampled, differing = 0, 0
	for py = STEP, HEIGHT - STEP, STEP do
		for px = STEP, WIDTH - STEP, STEP do
			local a = gdiAsRgb(px, py)
			local b = RasterPainter.Pixel(surface :: any, px, py)
			if a ~= 0xFFFFFFFF then
				sampled += 1
				if a ~= b then
					differing += 1
				end
			end
		end
	end

	--- And name a node where the difference is specifically ALPHA.
	local example: string? = nil
	local bestDistance = 0
	for _, n in ipairs(frame.Nodes) do
		local alpha = n.alpha or 1
		if n.fill == nil or n.gradient ~= nil or alpha >= 0.98 or alpha < 0.05 then
			continue
		end
		local px = math.floor(n.x + n.w * 0.06)
		local py = math.floor(n.y + n.h * 0.5)
		if px < 0 or py < 0 or px >= WIDTH or py >= HEIGHT then
			continue
		end
		local g = gdiAsRgb(px, py)
		local r = RasterPainter.Pixel(surface :: any, px, py)
		if g ~= r then
			--- THE BIGGEST difference, not the first.
			---
			--- The first translucent node found was `Tab_general` at alpha 0.20,
			--- sitting on a panel of its OWN colour -- so blending it changed the
			--- pixel by one unit, which is indistinguishable from rounding. True,
			--- and useless as evidence.
			---
			--- A node whose colour differs from what is beneath it shows the blend
			--- unmistakably, so the example is chosen by channel-wise distance.
			local function channels(v: number): (number, number, number)
				return bit32.band(bit32.rshift(v, 16), 0xFF),
					bit32.band(bit32.rshift(v, 8), 0xFF),
					bit32.band(v, 0xFF)
			end
			local gr, gg, gb = channels(g)
			local rr, rg, rb = channels(r)
			local distance = math.abs(gr - rr) + math.abs(gg - rg) + math.abs(gb - rb)
			if distance > bestDistance then
				bestDistance = distance
				example = string.format(
					"%s (alpha %.2f) GDI 0x%06X vs Rust 0x%06X -- %d levels apart",
					tostring(n.name), alpha, g, r, distance
				)
			end
		end
	end

	local pct = if sampled > 0 then differing / sampled * 100 else 0
	print(`screen "{screenChoice or "(demo)"}": {#frame.Nodes} nodes`)
	print(`  {differing}/{sampled} sampled pixels differ between the painters `
		.. `({string.format("%.1f", pct)}%)`)
	if example then
		print(`  e.g. {example}`)
	end

	--- WHERE TO LOOK ON SCREEN.
	---
	--- Knowing that 31% of pixels differ does not tell anyone which part of the
	--- picture to examine, and the outermost panel is opaque, so the difference is
	--- never where the eye goes first. These are the nodes to actually look at.
	local ranked: { any } = {}
	for _, n in ipairs(frame.Nodes) do
		local alpha = n.alpha or 1
		if n.fill ~= nil and alpha < 0.98 and alpha >= 0.05 and n.w >= 4 and n.h >= 4 then
			table.insert(ranked, n)
		end
	end
	table.sort(ranked, function(a, b)
		return a.w * a.h > b.w * b.h
	end)
	if #ranked > 0 then
		print(`  translucent nodes to look at (largest first):`)
		for i = 1, math.min(5, #ranked) do
			local n = ranked[i]
			print(string.format("     %-24s alpha %.2f  at %.0f,%.0f  %.0fx%.0f",
				tostring(n.name), n.alpha or 1, n.x, n.y, n.w, n.h))
		end
	end
	assert(sampled > 500, `only {sampled} pixels sampled; the comparison would be weak`)
	assert(differing > 0,
		"the two painters produced IDENTICAL output -- either the Rust backend is not "
			.. "blending, or it is not being used")
	assert(example ~= nil,
		"no translucent node differs between the painters, so nothing proves alpha is "
			.. "being applied rather than some other difference")

	RasterPainter.FreeSurface(surface :: any)
	user32.ReleaseDC(Win32.null, screenDC)
	print("OK -- the painters differ, and a translucent node is one of the places they do.")
	return
end

--- `useRaster`, not the raw flag: `--vello` also selects a Rust backend, and
--- keying this on "--raster" meant `--vello --check` silently ran the GDI check
--- instead -- a gate that reports OK while testing a different painter.
if useRaster and table.find(ARGS, "--check") then
	local ok, why = RasterPainter.Available()
	assert(ok, why)

	local surface = RasterPainter.NewSurface(WIDTH, HEIGHT, rasterBackend)
	assert(surface, "the raster surface should allocate")

	local frame = session.Snapshot()
	local drawn = RasterPainter.Paint(surface :: any, frame)
	print(`screen "{screenChoice or "(demo)"}": {#frame.Nodes} nodes, {drawn} draw calls`)
	assert(drawn > 0, "the rasterizer must draw something")

	--- DOES ALPHA CHANGE THE PICTURE? Asked by rendering the frame TWICE.
	---
	--- The previous form picked one translucent node and asserted its pixel was
	--- neither its own colour nor the background. Two things were wrong with it,
	--- and `--poison=opaque` found both.
	---
	--- It sampled 6% in from the edge -- 1.32 px on a 22x22 checkbox whose corner
	--- radius is 5 -- so the sample sat inside the ANTI-ALIASED corner, where
	--- coverage is below 1 and the pixel blends with the background whatever its
	--- alpha. It passed for a reason that had nothing to do with alpha.
	---
	--- And moving the sample inward did not fix it: that checkbox sits on a parent
	--- almost exactly its own colour, so 80% of it over that parent IS its own
	--- colour. The node cannot demonstrate alpha at any sample point, and no
	--- choice of pixel could have made it.
	---
	--- So the question is asked directly instead: paint the same frame with every
	--- alpha forced to 1 and require the result to DIFFER. A backend that honours
	--- alpha cannot produce the same image twice; one that ignores it cannot
	--- produce a different one. It needs no assumption about what lies beneath any
	--- particular node.
	local opaqueFrame = { Width = frame.Width, Height = frame.Height, Nodes = {} }
	local translucent = 0
	for i, n in ipairs(frame.Nodes) do
		local copy = table.clone(n)
		--- FLAT FILLS ONLY. A gradient's per-stop alpha is computed here in Luau
		--- from `n.alpha`, so forcing that field changes the gradient through a
		--- path that has nothing to do with whether the RASTERISER blends -- and
		--- the comparison would then report a difference on a backend that ignores
		--- alpha completely.
		--- A LOWER BOUND TOO. `RasterPainter` skips a node whose alpha is below
		--- 0.004 before it ever reaches the rasteriser, so forcing such a node to 1
		--- makes it appear in one render and not the other -- a difference produced
		--- in Luau, above the thing being tested, and present even on a backend
		--- that ignores alpha entirely. Only nodes that DRAW in both renders can
		--- say anything about blending.
		if n.gradient == nil and n.fill ~= nil
			and (n.alpha or 1) < 0.98 and (n.alpha or 1) > 0.05
		then
			translucent += 1
			copy.alpha = 1
		end
		opaqueFrame.Nodes[i] = copy
	end
	assert(translucent > 0,
		`"{screenChoice or "(demo)"}" has no translucent filled node, so alpha cannot be tested here`)

	local opaqueSurface = RasterPainter.NewSurface(WIDTH, HEIGHT, rasterBackend) :: any
	RasterPainter.SetTextEnabled(false)
	RasterPainter.Paint(opaqueSurface, opaqueFrame)
	local plain = RasterPainter.NewSurface(WIDTH, HEIGHT, rasterBackend) :: any
	RasterPainter.Paint(plain, frame)
	RasterPainter.SetTextEnabled(true)

	local differing, sampledPx = 0, 0
	for py = 2, HEIGHT - 2, 3 do
		for px = 2, WIDTH - 2, 3 do
			sampledPx += 1
			if RasterPainter.Pixel(plain, px, py) ~= RasterPainter.Pixel(opaqueSurface, px, py) then
				differing += 1
			end
		end
	end
	print(`{translucent} translucent nodes: forcing them opaque changes `
		.. `{differing} of {sampledPx} sampled pixels`)
	assert(differing > sampledPx / 100,
		`forcing every alpha to 1 changed only {differing} of {sampledPx} pixels, so this `
		.. `backend is not blending -- which is what GDI does and what this backend exists to fix`)

	--- AND THE SURFACE MUST ACTUALLY CONTAIN A PICTURE.
	---
	--- Every assertion above is NEGATIVE -- the pixel is not the node's colour,
	--- not the background -- and a backend that draws NOTHING AT ALL satisfies all
	--- of them: an untouched pixmap reads as transparent black, which is neither.
	--- The vello_cpu backend did exactly that on its first run and this check
	--- reported 100% parity and OK.
	---
	--- Counting distinct colours is the cheapest property that absence cannot
	--- satisfy. A blank surface has exactly one; a painted screen has hundreds.
	--- It does not care what the colours ARE, which is deliberate -- that is the
	--- grid check's job, and this one only has to be impossible to pass by
	--- omission.
	local seen: { [number]: boolean } = {}
	local distinct = 0
	for py = 4, HEIGHT - 4, 11 do
		for px = 4, WIDTH - 4, 11 do
			local v = RasterPainter.Pixel(surface :: any, px, py)
			if not seen[v] then
				seen[v] = true
				distinct += 1
			end
		end
	end
	print(`surface carries {distinct} distinct colours`)
	assert(distinct > 8,
		`the rasterised surface has only {distinct} distinct colour(s), so this backend `
		.. `drew essentially nothing -- every other assertion here can be passed by omission`)

	--- DOES THE TEXT LAND WHERE THE FRAME PUT IT?
	---
	--- The Rust tests prove the run measures per glyph and that its ink fits the
	--- measured width. Neither says it reaches the SCREEN at the node's position,
	--- and "text renders, in the wrong place" is a failure this host has already
	--- had once: a run laid out from zero, drawn without its node's left edge
	--- added, stacking every label in the corner.
	---
	--- ISOLATED BY DIFFERENCE, not by guessing at a background. The first version
	--- of this sampled one pixel as "the node's colour" and counted everything
	--- unlike it as ink -- which counted siblings, borders and children too, and
	--- reported 210 stray pixels that were never glyphs. Painting the SAME frame
	--- twice with text as the only variable makes the difference exactly the
	--- glyphs and nothing else.
	if RasterPainter.OwnsText(surface :: any) then
		local without = RasterPainter.NewSurface(WIDTH, HEIGHT, rasterBackend) :: any
		RasterPainter.SetTextEnabled(false)
		RasterPainter.Paint(without, frame)
		RasterPainter.SetTextEnabled(true)

		--- A CENTRED node whose text is meaningfully narrower than its box: the
		--- only shape where centring is distinguishable from left-alignment at
		--- all. Picking any text node would pass on a label that fills its box.
		local probe: any = nil
		for _, n in ipairs(frame.Nodes) do
			if type(n.text) == "string" and #n.text >= 3 and n.h > 10
				and (n.textAlignX or "center") == "center"
			then
				local tw = RasterPainter.Metrics(n.text, n.textSize or 14, nil)
				if n.w - tw > 24 then
					probe = n
					break
				end
			end
		end
		assert(probe, "no centred text node with slack in its box, so centring cannot be verified here")

		local total = 0
		local minX, maxX = math.huge, -math.huge
		local inBox = 0
		for py = 0, HEIGHT - 1 do
			for px = 0, WIDTH - 1 do
				if RasterPainter.Pixel(surface :: any, px, py)
					~= RasterPainter.Pixel(without, px, py)
				then
					total += 1
					if px >= probe.x and px < probe.x + probe.w
						and py >= probe.y and py < probe.y + probe.h
					then
						inBox += 1
						minX = math.min(minX, px)
						maxX = math.max(maxX, px)
					end
				end
			end
		end
		assert(total > 500,
			`only {total} pixels differ with text on; glyphs are not reaching the surface`)
		assert(inBox > 12, `the node "{probe.text}" produced only {inBox} glyph pixels`)

		--- IS THE INK CENTRED IN ITS BOX?
		---
		--- This is es9's report stated as a measurement: "none of our external
		--- renderers centre the icons". Every painter drew at `n.x + 10`, so the
		--- ink sat hard against the left edge of a box it should have been
		--- centred in. Comparing the ink's midpoint to the box's midpoint fails
		--- loudly for that and cannot be satisfied by a left-aligned run.
		local inkMid = (minX + maxX) / 2
		local boxMid = probe.x + probe.w / 2
		local slack = probe.w / 2
		print(`centring: "{probe.text}" box {math.floor(probe.x)}..{math.floor(probe.x + probe.w)} `
			.. `(mid {string.format("%.0f", boxMid)}), ink {minX}..{maxX} (mid {string.format("%.0f", inkMid)})`)
		assert(math.abs(inkMid - boxMid) < math.max(6, slack * 0.12),
			`a centred label's ink is not centred: box mid {string.format("%.0f", boxMid)}, `
			.. `ink mid {string.format("%.0f", inkMid)} -- this is the "+10 inset" bug`)
	end

	--- The old vacuity guard lived here and required "a gradient-free, uncovered
	--- translucent node", which shop does not have -- so `--screen shop
	--- --raster --check` refused to run at all. The two-render comparison needs no
	--- such node and carries its own guard, so both screens can be checked now.
	--- WHAT REACHES THE WINDOW, WHICH NOTHING HERE HAD EVER CHECKED.
	---
	--- Every assertion above reads `RasterPainter.Pixel`, which is `ar_pixel` --
	--- the RASTERISED surface, straight out of vello. That is the right oracle
	--- for the painter and it is blind to everything after it: `ar_bgra`
	--- swizzles RGBA into the BGRA a Windows DIB wants, and
	--- `SetDIBitsToDevice` uploads it. Swap two channels in either and every
	--- check on this screen still passes while the window shows blue for red.
	---
	--- So this presents into a memory DC and reads it back with `GetPixel`,
	--- which is GDI's own view of the uploaded bits, and requires it to agree
	--- with the surface. It is the only assertion in this file that spans the
	--- swizzle and the upload, and it is what makes changing either of them
	--- something other than an act of faith.
	do
		local screenDC = user32.GetDC(Win32.null)
		local checkDC = gdi.CreateCompatibleDC(screenDC)
		gdi.SelectObject(checkDC, gdi.CreateCompatibleBitmap(screenDC, WIDTH, HEIGHT))
		WindowsPresenter.Present(RasterPainter, surface :: any, checkDC)

		--- SAMPLED ON A GRID rather than at node centres: a channel swap is a
		--- property of every pixel, and a grid cannot be satisfied by one lucky
		--- node. Grey pixels are counted but cannot discriminate -- R, G and B
		--- are equal, so every permutation of them agrees -- and a surface that
		--- is mostly chrome has a lot of those, which is exactly how a swap
		--- would slip through a weaker sample.
		local checked, mismatched, coloured = 0, 0, 0
		local worst: string? = nil
		for py = 0, HEIGHT - 1, 7 do
			for px = 0, WIDTH - 1, 7 do
				local want = RasterPainter.Pixel(surface :: any, px, py)
				--- GetPixel answers 0x00BBGGRR; the surface answers 0x00RRGGBB.
				--- That difference is GDI's API convention, not the DIB's byte
				--- order, and conflating the two is how this check would end up
				--- asserting the bug it exists to catch.
				local got = gdi.GetPixel(checkDC, px, py)
				local gr, gg, gb = got % 256, math.floor(got / 256) % 256, math.floor(got / 65536) % 256
				local wr, wg, wb = math.floor(want / 65536) % 256, math.floor(want / 256) % 256, want % 256
				checked += 1
				if not (wr == wg and wg == wb) then
					coloured += 1
				end
				if gr ~= wr or gg ~= wg or gb ~= wb then
					mismatched += 1
					if worst == nil then
						worst = `({px},{py}) surface rgb({wr},{wg},{wb}) but the DIB reads rgb({gr},{gg},{gb})`
					end
				end
			end
		end
		user32.ReleaseDC(Win32.null, screenDC)
		print(`presented: {checked} pixels sampled, {coloured} of them not grey, {mismatched} disagree`)
		--- THE GREY GUARD. A surface that came back all-grey would make the
		--- comparison pass without being able to see a channel swap at all --
		--- the same vacuity that let a black frame score 100% parity here.
		assert(coloured > checked / 20,
			`only {coloured} of {checked} sampled pixels carry colour; this check cannot see a channel swap`)
		assert(mismatched == 0,
			`the window does not show what was rasterised -- {mismatched} of {checked} pixels differ. {worst}`)
	end

	print("OK -- the Rust backend blends what GDI could only paint opaque,")
	print("     and the bits that reach the window are the bits that were drawn.")
	RasterPainter.FreeSurface(surface :: any)
	return
end

if table.find(ARGS, "--check") then
	--- OFF-SCREEN, deliberately: a memory DC needs no window, no message pump and
	--- no compositor, so this runs in CI and cannot be defeated by another window
	--- covering ours -- which `GetPixel` on a visible DC absolutely can be.
	local screenDC = user32.GetDC(Win32.null)
	local memDC = gdi.CreateCompatibleDC(screenDC)
	local bmp = gdi.CreateCompatibleBitmap(screenDC, WIDTH, HEIGHT)
	gdi.SelectObject(memDC, bmp)

	local frame = session.Snapshot()
	local drawn = NativePainter.Paint(memDC, frame)
	print(`screen "{screenChoice or "(demo)"}": {#frame.Nodes} nodes delivered, {drawn} drawn by GDI`)
	assert(drawn > 0, "the painter must draw something")

	--- SAMPLE THE SURFACE, NOT THE NODES.
	---
	--- Per-node sampling was the obvious design and could not get coverage: these
	--- trees are nested, so a panel is covered by its own children nearly
	--- everywhere, and after excluding every point some later node paints, the
	--- check shrank to two samples. A check that passes on two nodes out of 185 is
	--- not measuring the painter.
	---
	--- A GRID asks the right question instead: at this pixel, which node does the
	--- FRAME say is on top, and is that the colour on the surface? It samples
	--- hundreds of points, it exercises paint order, clipping and z-order together,
	--- and it fails loudly if the painter and the frame ever disagree about who
	--- owns a pixel.
	--- The helper, pinned against known values before anything trusts it.
	--- COLORREF is 0x00BBGGRR: pure red is 0x0000FF, pure blue is 0xFF0000. If
	--- this is backwards, every colour on screen is backwards and the grid check
	--- alone would never say so.
	assert(Win32.colorref(255, 0, 0) == 0x0000FF, "COLORREF: red must live in the LOW byte")
	assert(Win32.colorref(0, 0, 255) == 0xFF0000, "COLORREF: blue must live in the HIGH byte")
	assert(Win32.colorref(0, 255, 0) == 0x00FF00, "COLORREF: green in the middle")

	local ALPHA_FLOOR = 0.15
	local STEP = 20

	local function inside(c: any, x: number, y: number): boolean
		return c == nil
			or (x >= c[1] and x < c[1] + c[3] and y >= c[2] and y < c[2] + c[4])
	end

	local checked, matched = 0, 0
	local firstMismatch: string? = nil

	for py = STEP, HEIGHT - STEP, STEP do
		for px = STEP, WIDTH - STEP, STEP do
			--- The topmost node that FILLS here, and whether any text lands on the
			--- point. Text is excluded rather than modelled: glyph coverage is a
			--- font question, and a pixel inside a label may or may not be ink.
			local top: any = nil
			local hasText = false
			local cornerSkip = false
			local edgeSkip = false
			for _, n in ipairs(frame.Nodes) do
				if px < n.x or px >= n.x + n.w or py < n.y or py >= n.y + n.h then
					continue
				end
				if not inside(n.clip, px, py) then
					continue
				end
				if type(n.text) == "string" and n.text ~= "" then
					hasText = true
				end

				--- EDGES BELONG TO THE STROKE, not to the fill.
				---
				--- A sample landing on a node's 1-2px border reads the stroke colour,
				--- which the expected-colour model has no way to attribute -- it
				--- knows who FILLS a pixel, not who outlines it. Both remaining
				--- mismatches read the same slate 0x554133, which is a border.
				---
				--- The band is skipped for any painting node, not just the topmost:
				--- a small node's outline crosses a large node's interior, and the
				--- pixel belongs to whichever drew last.
				local paints = (n.fill ~= nil and (n.alpha or 1) >= ALPHA_FLOOR)
					or (n.stroke ~= nil)
				if paints then
					local band = 1 + math.ceil(if n.stroke then (n.stroke.thickness or 1) else 0)
					if px < n.x + band or px > n.x + n.w - band - 1
						or py < n.y + band or py > n.y + n.h - band - 1 then
						edgeSkip = true
					end
				end
				if n.fill ~= nil and (n.alpha or 1) >= ALPHA_FLOOR then
					--- ROUNDED CORNERS ARE NOT RECTANGLES.
					---
					--- The expected-colour model treated every node as a sharp box,
					--- so a point in the arc of a `UICorner` was attributed to the
					--- node while the painter correctly let the background through.
					--- All twelve initial mismatches were exactly that -- the check
					--- was wrong and the picture was right.
					---
					--- Rather than model the arc, points inside a corner's bounding
					--- square are skipped. Cheaper, and it cannot accidentally
					--- excuse a real error anywhere else on the node.
					local r = n.radius or 0
					if r > 0 then
						local nearL = px < n.x + r
						local nearR = px > n.x + n.w - r
						local nearT = py < n.y + r
						local nearB = py > n.y + n.h - r
						if (nearL or nearR) and (nearT or nearB) then
							cornerSkip = true
						end
					end
					top = n
				end
			end
			if hasText or cornerSkip or edgeSkip then
				continue
			end

			--- No node fills here: the background must be showing.
			--- EXPECTED VALUE COMPUTED INDEPENDENTLY, not via Win32.colorref.
			---
			--- Using the helper here made this check VACUOUS and it passed two
			--- deliberate poisons before that was noticed: the painter and the
			--- expectation both went through the same function, so swapping its
			--- channel order moved both sides identically and the comparison
			--- compared the painter to itself.
			---
			--- This is the shape ".artifacts" already records as
			--- "borrowed scratch makes gates vacuous", met again from the other
			--- direction. The literal arithmetic below is deliberate duplication:
			--- an independent statement of BGR, so a change to the helper shows up
			--- as a disagreement instead of cancelling out. `verifyColorref` below
			--- pins the helper itself.
			local want = if top
				then top.fill[1] + top.fill[2] * 256 + top.fill[3] * 65536
				else 11 + 13 * 256 + 18 * 65536

			checked += 1
			local got = gdi.GetPixel(memDC, px, py)
			if got == want then
				matched += 1
			elseif firstMismatch == nil then
				firstMismatch = string.format("(%d,%d) owned by %s: wanted 0x%06X, read 0x%08X%s",
					px, py, if top then tostring(top.name) else "(background)", want, got,
					if got == 0xFFFFFFFF then "  (CLR_INVALID)" else "")
			end
		end
	end

	gdi.DeleteObject(bmp)
	user32.ReleaseDC(Win32.null, screenDC)

	local pct = if checked > 0 then matched / checked * 100 else 0
	print(`pixel parity: {matched}/{checked} sampled points ({string.format("%.1f", pct)}%) match the frame`)
	if firstMismatch then
		print(`  first mismatch -- {firstMismatch}`)
	end
	--- A floor, so this cannot pass by sampling almost nothing. 185 nodes over a
	--- 1280x720 surface at a 20px grid is on the order of 2000 points.
	assert(checked > 500, `only {checked} points sampled; the check would be vacuous`)
	assert(matched == checked, "every sampled point must show the colour the frame declares")

	--- CORNER RADIUS, asserted separately.
	---
	--- The grid SKIPS corner regions, so it cannot see a painter that ignores
	--- `radius` -- proven by a poison that disabled RoundRect entirely and passed.
	--- This draws one node twice, with and without a radius, and asserts the
	--- corner pixel differs. It is the only thing here that can fail on that.
	local probe = {
		name = "RadiusProbe", x = 10, y = 10, w = 120, h = 120,
		fill = { 250, 250, 250 }, alpha = 1, radius = 30,
	}
	local sharp = table.clone(probe)
	sharp.radius = 0

	NativePainter.Paint(memDC, { Width = WIDTH, Height = HEIGHT, Nodes = { sharp } })
	local sharpCorner = gdi.GetPixel(memDC, 13, 13)
	NativePainter.Paint(memDC, { Width = WIDTH, Height = HEIGHT, Nodes = { probe } })
	local roundedCorner = gdi.GetPixel(memDC, 13, 13)
	local roundedCentre = gdi.GetPixel(memDC, 70, 70)

	local white = 250 + 250 * 256 + 250 * 65536
	assert(sharpCorner == white, `a square node must fill its corner, read 0x{string.format("%06X", sharpCorner)}`)
	assert(roundedCentre == white, "a rounded node must still fill its centre")
	assert(roundedCorner ~= white, "a rounded node must NOT fill its corner -- radius is being ignored")
	print("corner radius: a rounded node leaves its corner unpainted, a square one does not")

	--- UNICODE GLYPHS ACTUALLY DRAW.
	---
	--- The grid check deliberately SKIPS any point a label covers, so it cannot
	--- see whether text rendered at all -- and for a while it did not. The icons
	--- in these screens are TEXT, and `TextOutA` drew their UTF-8 bytes as ANSI
	--- codepage, which is nothing recognisable. Every ASCII label looked fine
	--- throughout, so the failure read as "icons are broken" rather than "text is
	--- ANSI".
	---
	--- Ink is COUNTED rather than compared to a reference: which pixels a glyph
	--- lights depends on the font, but that it lights SOME does not.
	local function inkCount(text: string, size: number?): number
		NativePainter.Paint(memDC, {
			Width = WIDTH,
			Height = HEIGHT,
			Nodes = { {
				name = "InkProbe", x = 40, y = 40, w = 200, h = 60,
				fill = { 0, 0, 0 }, alpha = 1, radius = 0,
				text = text, textSize = size or 28, textColour = { 255, 255, 255 },
			} },
		})
		--- The RIGHTMOST inked column, not the ink count. Count cannot tell correct
		--- glyphs from mojibake -- the ANSI path draws garbage codepage characters
		--- and produced MORE ink than the correct one, so a count-based assertion
		--- passed the exact bug it was written for.
		---
		--- Width can tell them apart, and for a structural reason: five codepoints
		--- are thirteen UTF-8 BYTES, so the ANSI path lays out thirteen characters
		--- where the wide path lays out five. That ratio is not a matter of taste
		--- in fonts.
		--- THE INK'S OWN WIDTH, not its distance from a fixed origin.
		---
		--- This returned the rightmost inked column, which is a width only while
		--- text is pinned to the left edge -- and it was, by the `n.x + 10` inset
		--- every painter had. Once alignment came from the frame the probe node
		--- centred (Roblox's default for an unset `TextXAlignment`) and the same
		--- string reported a larger "span" at a smaller size: 12px "spanned" 118px
		--- against 32px's 152px, and a correct painter failed the check.
		---
		--- Measuring left AND right edges is alignment-independent, which is what
		--- a test of glyph WIDTH should have been all along.
		local leftmost, rightmost = math.huge, -1
		for py = 42, 98, 2 do
			for px = 42, 238, 2 do
				if gdi.GetPixel(memDC, px, py) ~= 0 then
					if px < leftmost then leftmost = px end
					if px > rightmost then rightmost = px end
				end
			end
		end
		if rightmost < 0 then
			return 0
		end
		return rightmost - leftmost
	end

	local blank = inkCount("")
	local five = inkCount("HHHHH")
	local glyphs = inkCount(utf8.char(0x25C0, 0x25B6, 0x2B50, 0x2713, 0x2715))

	print(`glyph extent: blank={blank}  5 ascii={five}  5 unicode={glyphs}`)
	assert(blank == 0, `an empty label must leave no ink, found {blank}`)
	assert(five > 0, "ASCII text must draw")
	assert(glyphs > 0, "UNICODE glyphs must draw at all")

	--- FIVE GLYPHS, not thirteen bytes. Measured on this machine: the wide path
	--- spans 54px against ASCII's 56px (ratio 0.96), the ANSI path 90px (1.6).
	--- 1.35 sits between them with room for a font whose symbols are wider than
	--- 'H', and well under a byte-wise layout.
	---
	--- The first version of this used 1.9 and passed the poison -- a threshold
	--- chosen before seeing both numbers, which is how a check ends up shaped to
	--- accept whatever it was first shown.
	local budget = math.floor(five * 1.35)
	assert(glyphs <= budget,
		`five glyphs span {glyphs}px where five ASCII chars span {five}px -- `
			.. `that is byte-wise ANSI layout, not wide-character output`)

	--- TEXT SIZE IS HONOURED.
	---
	--- Nothing asserted this, and nothing could: with no font selected GDI used
	--- the default STOCK face, which draws every string at one small fixed size
	--- whatever the frame asked for. Every other check passed throughout -- the
	--- pixel grid skips text, and the extent test compared two strings at the SAME
	--- size, so a host that ignored size entirely satisfied both.
	---
	--- es9 saw it as "the emojis are super tiny".
	local small = inkCount("HHHHH", 12)
	local large = inkCount("HHHHH", 32)
	print(`text size: 12px spans {small}px, 32px spans {large}px`)
	assert(large > small * 1.8,
		`text must scale with TextSize: 12px spans {small}px and 32px spans {large}px`)
	--- LAYOUT MEASURES THE FONT THE PAINTER DRAWS WITH.
	---
	--- Asserted through a property rather than by comparing the provider to
	--- itself, which would be vacuous: ten narrow glyphs and ten wide ones are the
	--- SAME LENGTH, so any uniform-factor fallback returns the same width for
	--- both. Real metrics cannot.
	---
	--- This is what the bundled advance table was doing here before the host
	--- supplied its own provider -- 21% out on the narrow run, which is
	--- `AutomaticSize` sizing to a width nothing would draw.
	local narrow = app.Host.Text.Measure(string.rep("i", 10), 14, nil)
	local wide = app.Host.Text.Measure(string.rep("W", 10), 14, nil)
	print(`text metrics: 10 narrow glyphs {string.format("%.0f", narrow)}px, 10 wide {string.format("%.0f", wide)}px`)
	assert(app.Host.Text.ProviderOwner() == "host-supplied",
		`the host must supply its own metrics, not inherit the display's; owner is {tostring(app.Host.Text.ProviderOwner())}`)
	assert(wide > narrow * 2,
		`metrics must be per-glyph: 10 narrow measured {narrow} and 10 wide {wide}`)

	print("OK -- the native painter agrees with the frame it was given.")
	return
end

--------------------------------------------------------------------------------
-- `--compare-raster`: tiny-skia against vello_cpu, on one frame.
--------------------------------------------------------------------------------

--- THE REASON FOR KEEPING TWO BACKENDS.
---
--- They consume the SAME `Live.Frame` through the SAME C ABI, so a disagreement
--- between them is a backend bug by construction -- there is no framework path
--- that can reach one and not the other. That is the only cheap way to tell a
--- rasteriser bug from a display-list bug, and it is why vello_cpu was added
--- ALONGSIDE tiny-skia rather than replacing it.
---
--- Exact equality is NOT the bar and would be the wrong bar: the two build
--- rounded corners differently (kurbo's arc against a four-cubic approximation)
--- and round premultiplied arithmetic differently. What matters is whether they
--- agree about the PICTURE, so this reports the distribution and fails only on
--- gross divergence.
if table.find(ARGS, "--compare-raster") then
	local ok, why = RasterPainter.Available()
	assert(ok, why)

	local frame = session.Snapshot()
	local ts = RasterPainter.NewSurface(WIDTH, HEIGHT, RasterPainter.TINY_SKIA)
	local vc = RasterPainter.NewSurface(WIDTH, HEIGHT, RasterPainter.VELLO_CPU)
	assert(ts and vc, "both surfaces should allocate")
	assert((ts :: any).Backend == "tiny-skia" and (vc :: any).Backend == "vello_cpu",
		`the library handed back {(ts :: any).Backend} and {(vc :: any).Backend}; `
		.. `comparing a backend with itself would agree perfectly and prove nothing`)

	--- SHAPES ONLY. tiny-skia has no text and never will here, so leaving vello's
	--- glyphs on would compare "does this backend draw text" rather than "do these
	--- two rasterisers agree", and every text pixel would count as a divergence.
	RasterPainter.SetTextEnabled(false)
	local a = RasterPainter.Paint(ts :: any, frame)
	local b = RasterPainter.Paint(vc :: any, frame)
	RasterPainter.SetTextEnabled(true)
	print(`draw calls: tiny-skia {a}, vello_cpu {b}`)
	assert(a == b, `the two backends were given different work: {a} vs {b} draw calls`)

	local function channels(v: number): (number, number, number)
		return math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256
	end

	local sampled, identical, close, gross = 0, 0, 0, 0
	local worst, worstAt = 0, ""
	local histogram = { 0, 0, 0, 0 }
	for py = 2, HEIGHT - 2, 3 do
		for px = 2, WIDTH - 2, 3 do
			local pa = RasterPainter.Pixel(ts :: any, px, py)
			local pb = RasterPainter.Pixel(vc :: any, px, py)
			sampled += 1
			if pa == pb then
				identical += 1
				histogram[1] += 1
			else
				local ar, ag, ab = channels(pa)
				local br, bg, bb = channels(pb)
				local d = math.max(math.abs(ar - br), math.abs(ag - bg), math.abs(ab - bb))
				if d > worst then
					worst = d
					worstAt = string.format("(%d,%d) 0x%06X vs 0x%06X", px, py, pa, pb)
				end
				if d <= 2 then
					close += 1
					histogram[2] += 1
				elseif d <= 16 then
					histogram[3] += 1
				else
					gross += 1
					histogram[4] += 1
				end
			end
		end
	end

	print(`sampled {sampled} points`)
	print(string.format("  identical            %6d  (%.1f%%)", histogram[1], histogram[1] / sampled * 100))
	print(string.format("  within 2 channels    %6d  (%.1f%%)", histogram[2], histogram[2] / sampled * 100))
	print(string.format("  within 16 channels   %6d  (%.1f%%)", histogram[3], histogram[3] / sampled * 100))
	print(string.format("  beyond 16 channels   %6d  (%.1f%%)", histogram[4], histogram[4] / sampled * 100))
	print(`  worst: {worstAt}`)

	--- Both must have drawn a picture, or "they agree" is two blank surfaces
	--- agreeing -- the vacuity this file has met more than once.
	local seenA, seenB = {}, {}
	local dA, dB = 0, 0
	for py = 4, HEIGHT - 4, 11 do
		for px = 4, WIDTH - 4, 11 do
			local va = RasterPainter.Pixel(ts :: any, px, py)
			local vb = RasterPainter.Pixel(vc :: any, px, py)
			if not seenA[va] then seenA[va] = true; dA += 1 end
			if not seenB[vb] then seenB[vb] = true; dB += 1 end
		end
	end
	assert(dA > 8 and dB > 8,
		`one backend drew nothing: tiny-skia {dA} distinct colours, vello_cpu {dB}`)

	--- The bar: the two must agree about the picture almost everywhere. Anti-
	--- aliased edges legitimately differ, and they are a small fraction of a
	--- screen made of axis-aligned rectangles.
	local agree = (histogram[1] + histogram[2] + histogram[3]) / sampled
	assert(agree > 0.97,
		string.format("the backends agree on only %.1f%% of pixels; that is a divergence, not rounding", agree * 100))
	print(string.format("OK -- the two rasterisers agree on %.1f%% of sampled pixels.", agree * 100))
	return
end

--------------------------------------------------------------------------------
-- `--damage-check`: does a clipped repaint match a full one, pixel for pixel?
--------------------------------------------------------------------------------

--- THE GATE FOR THE OPTIMISATION THAT MOST EASILY SHIPS A WRONG PICTURE.
---
--- Clipping the paint to a damage rect is only safe if the rect really covers
--- everything that changed. When it does not, the surface keeps stale pixels --
--- and the failure is silent, intermittent, and looks like a framework bug rather
--- than a painter one. `--check` cannot see it: it paints one frame from scratch,
--- which is the case that always works.
---
--- So: paint a frame FULLY, step the session so something moves, then paint the
--- new frame two ways -- fully, and clipped to the reported damage -- and require
--- the two surfaces to agree everywhere. Any node the damage rect failed to cover
--- shows up as a disagreeing pixel.
if table.find(ARGS, "--damage-check") and useRaster then
	--- THE RASTER BACKENDS HAVE THEIR OWN DAMAGE PATH, and it was unverified.
	---
	--- vello in particular has a trap the GDI painter does not: its composite mode
	--- decides whether rendering CLEARS the destination first. `Replace` -- the
	--- default, and right for a full frame -- would wipe every pixel the damage
	--- rect does not cover, which are precisely the pixels a damaged repaint is
	--- trusting to still be there. This is what says whether the choice was right.
	local ok, why = RasterPainter.Available()
	assert(ok, why)
	local full = RasterPainter.NewSurface(WIDTH, HEIGHT, rasterBackend) :: any
	local clipped = RasterPainter.NewSurface(WIDTH, HEIGHT, rasterBackend) :: any
	assert(full and clipped, "both surfaces should allocate")
	print(`backend: {clipped.Backend}`)

	session.SnapshotDelta(true)
	local first = session.Snapshot()
	RasterPainter.Paint(full, first)
	RasterPainter.Paint(clipped, first)

	local moved = false
	local sampled, differing = 0, 0
	local worst, worstAt = 0, ""
	local probeX, probeY = 40, math.floor(HEIGHT / 2)
	local function channels(v: number): (number, number, number)
		return math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256
	end
	for step = 1, 12 do
		probeX += math.floor(WIDTH / 14)
		session.Pointer("move", probeX, probeY)
		session.Step(1 / 60)
		local delta = session.SnapshotDelta()
		local snap = session.Snapshot()
		if #delta.Changed == 0 and #delta.Removed == 0 then
			continue
		end
		moved = true
		RasterPainter.Paint(full, snap)
		RasterPainter.Paint(clipped, snap, false, delta.Dirty)
		for py = 3, HEIGHT - 3, 7 do
			for px = 3, WIDTH - 3, 7 do
				local a = RasterPainter.Pixel(full, px, py)
				local b = RasterPainter.Pixel(clipped, px, py)
				sampled += 1
				if a ~= b then
					local ar, ag, ab = channels(a)
					local br, bg, bb = channels(b)
					local d = math.max(math.abs(ar - br), math.abs(ag - bg), math.abs(ab - bb))
					--- A one-unit difference is the rounding of a pixel blended in
					--- two passes rather than one, not a stale pixel. A stale pixel
					--- is a whole node's colour out.
					if d > 2 then
						differing += 1
						if d > worst then
							worst = d
							worstAt = string.format("(%d,%d) full 0x%06X vs clipped 0x%06X", px, py, a, b)
						end
					end
				end
			end
		end
	end
	assert(moved, "nothing changed across 12 steps, so this compared a frame with itself")
	print(`damage-clipped vs full: {sampled} sampled, {differing} differ by more than 2 channels`)
	if worst > 0 then
		print(`  worst: {worstAt}`)
	end

	--- POISON: a deliberately tiny damage rect on a STALE surface must leave the
	--- rest wrong, or this comparison cannot see a missed region at all.
	local stale = session.Snapshot()
	session.Pointer("move", math.floor(WIDTH / 2), math.floor(HEIGHT / 2))
	for _ = 1, 20 do
		session.Step(1 / 60)
	end
	local fresh = session.Snapshot()
	RasterPainter.Paint(full, fresh)
	RasterPainter.Paint(clipped, stale)
	RasterPainter.Paint(clipped, fresh, false, { 0, 0, 8, 8 })
	local caught = 0
	for py = 3, HEIGHT - 3, 7 do
		for px = 3, WIDTH - 3, 7 do
			if RasterPainter.Pixel(full, px, py) ~= RasterPainter.Pixel(clipped, px, py) then
				caught += 1
			end
		end
	end
	assert(caught > 0,
		"an 8x8 repair of a stale surface produced no disagreement, so this check is blind")
	print(`poison: an 8x8 repair leaves {caught} pixels wrong, as it must`)

	assert(differing == 0,
		`{differing} pixels differ between a clipped repaint and a full one; worst {worstAt}`)
	print(`OK -- {clipped.Backend} repaints a damage rect identically to a full frame.`)
	return
end

if table.find(ARGS, "--damage-check") then
	local screenDC = user32.GetDC(Win32.null)

	local function newDC()
		local dc = gdi.CreateCompatibleDC(screenDC)
		gdi.SelectObject(dc, gdi.CreateCompatibleBitmap(screenDC, WIDTH, HEIGHT))
		return dc
	end

	local full, clipped = newDC(), newDC()

	--- Both surfaces start from the SAME fully-painted frame, which is what makes
	--- the comparison meaningful: the clipped painter is allowed to leave pixels
	--- alone precisely because they are already correct.
	session.SnapshotDelta(true)
	local first = session.Snapshot()
	NativePainter.Paint(full, first)
	NativePainter.Paint(clipped, first)

	--- IS THE PAINTER IDEMPOTENT? Painting the same frame twice must give the
	--- same pixels, or nothing downstream of it can be reasoned about.
	do
		local a, b = newDC(), newDC()
		NativePainter.Paint(a, first)
		NativePainter.Paint(b, first)
		local d1 = 0
		for py = 4, HEIGHT - 4, 7 do
			for px = 4, WIDTH - 4, 7 do
				if gdi.GetPixel(a, px, py) ~= gdi.GetPixel(b, px, py) then d1 += 1 end
			end
		end
		NativePainter.Paint(a, first)
		local d2 = 0
		for py = 4, HEIGHT - 4, 7 do
			for px = 4, WIDTH - 4, 7 do
				if gdi.GetPixel(a, px, py) ~= gdi.GetPixel(b, px, py) then d2 += 1 end
			end
		end
		print(`idempotence: one paint vs one paint -> {d1} differ; twice vs once -> {d2} differ`)
		--- Asserted, not merely printed. Everything below reasons about surfaces
		--- that were painted at different times; if the painter itself were not
		--- deterministic, none of those comparisons would mean anything.
		assert(d1 == 0, `two paints of the same frame differ in {d1} pixels`)
		assert(d2 == 0, `repainting a frame over itself changed {d2} pixels`)
	end

	--- Something has to MOVE, or this compares two identical frames and passes
	--- while testing nothing -- the failure mode this repo keeps meeting.
	local moved = false
	local totalPixels, differing = 0, 0
	local insideDamage, outsideDamage = 0, 0
	--- STATIC SCREENS STILL HAVE TO BE EXERCISED. `settings` animates nothing on
	--- its own, so stepping alone left the comparison with two identical frames
	--- and the vacuity guard -- correctly -- refused it. Driving the pointer
	--- across the screen produces hover changes, which is a real damage pattern
	--- and the one a mostly-still UI actually spends its life in.
	local probeX, probeY = 40, math.floor(HEIGHT / 2)
	--- The widest-damage step is kept for the poison below: it needs a pair of
	--- frames that genuinely differ, and on a mostly-static screen most pairs do
	--- not.
	local poisonStale: any, poisonFresh: any, poisonArea = nil, nil, -1
	local prevSnap = first
	for step = 1, 12 do
		probeX += math.floor(WIDTH / 14)
		session.Pointer("move", probeX, probeY)
		session.Step(1 / 60)
		local delta = session.SnapshotDelta()
		local snap = session.Snapshot()
		if #delta.Changed == 0 and #delta.Removed == 0 then
			continue
		end
		moved = true
		local dd = delta.Dirty
		if dd and dd[3] * dd[4] > poisonArea then
			poisonArea = dd[3] * dd[4]
			poisonStale, poisonFresh = prevSnap, snap
		end
		prevSnap = snap
		NativePainter.Paint(full, snap)
		NativePainter.Paint(clipped, snap, nil, delta.Dirty)

		for py = 4, HEIGHT - 4, 7 do
			for px = 4, WIDTH - 4, 7 do
				local a = gdi.GetPixel(full, px, py)
				local b = gdi.GetPixel(clipped, px, py)
				if a ~= 0xFFFFFFFF then
					totalPixels += 1
					if a ~= b then
						differing += 1
						local dd = delta.Dirty
						local within = dd ~= nil and px >= dd[1] - 2 and px <= dd[1] + dd[3] + 2
							and py >= dd[2] - 2 and py <= dd[2] + dd[4] + 2
						if within then insideDamage += 1 else outsideDamage += 1 end
						if differing <= 4 then
							print(string.format(
								"  step %d: (%d,%d) full %06X vs clipped %06X  inside=%s  damage=%s",
								step, px, py, a, b, tostring(within),
								if dd then string.format("%.0f,%.0f %.0fx%.0f", dd[1], dd[2], dd[3], dd[4]) else "nil"))
						end
					end
				end
			end
		end
	end

	assert(moved, "nothing changed across 12 steps, so this check compared a frame with itself")
	print(`damage-clipped vs full: {totalPixels} pixels compared, {differing} differ`)
	print(`  {insideDamage} inside the damage rect, {outsideDamage} outside it`)

	--- POISON CHECK, and the first version of it was vacuous.
	---
	--- It patched a surface that was ALREADY correct, so a deliberately tiny
	--- damage rect repaired nothing and disagreed with nothing -- the check
	--- reported "no difference" and would have done so however broken the
	--- clipping was. A poison has to start from a surface that is genuinely
	--- stale.
	---
	--- So: put the OLD frame on one surface, then repair it toward the new frame
	--- through an 8x8 window. Everything the window does not cover must still
	--- disagree, or this comparison cannot see a missed region at all.
	assert(poisonStale ~= nil and poisonFresh ~= nil,
		"no step produced a damage rect, so there is no frame pair to poison with")
	NativePainter.Paint(full, poisonFresh)
	NativePainter.Paint(clipped, poisonStale)
	--- The two frames must actually differ, or "an 8x8 repair leaves pixels
	--- wrong" is trivially unprovable and the guard below would be testing the
	--- frames rather than the clipping.
	local stalePixels = 0
	for py = 4, HEIGHT - 4, 7 do
		for px = 4, WIDTH - 4, 7 do
			if gdi.GetPixel(full, px, py) ~= gdi.GetPixel(clipped, px, py) then
				stalePixels += 1
			end
		end
	end
	assert(stalePixels > 0,
		"the widest-damage step painted identically to its predecessor, so nothing can be poisoned")

	NativePainter.Paint(clipped, poisonFresh, nil, { 0, 0, 8, 8 })
	local caught = 0
	for py = 4, HEIGHT - 4, 7 do
		for px = 4, WIDTH - 4, 7 do
			local a = gdi.GetPixel(full, px, py)
			if a ~= 0xFFFFFFFF and a ~= gdi.GetPixel(clipped, px, py) then
				caught += 1
			end
		end
	end
	assert(caught > 0,
		"an 8x8 repair of a stale surface produced no disagreement, so this check is blind")
	print(`poison: {stalePixels} pixels stale, and an 8x8 repair leaves {caught} of them wrong, as it must`)

	assert(differing == 0,
		`{differing} pixels differ between a clipped repaint and a full one`)
	print("OK -- clipping the paint to the damage rect changes no pixel.")
	return
end

--------------------------------------------------------------------------------
-- `--profile`: where the frame actually goes.
--------------------------------------------------------------------------------

--- WHY THIS EXISTS BEFORE ANY OPTIMISATION.
---
--- The fps answer named three candidate wins -- cache text runs, cache corner
--- masks, clip the paint -- and every one of them was a GUESS about where the
--- milliseconds are. This repo has an expensive history of rewriting the thing
--- that turned out not to be the cost, so the rule is that two instruments agree
--- on a target before anything is rewritten.
---
--- It reports the paint split INTO ITS PARTS rather than as one number, because
--- "GDI text is 2.9ms" does not say whether that is glyph rasterisation, the
--- UTF-16 conversion, or DC state changes -- and those have three completely
--- different fixes.
if table.find(ARGS, "--profile") then
	local screenDC = user32.GetDC(Win32.null)
	local memDC = gdi.CreateCompatibleDC(screenDC)
	gdi.SelectObject(memDC, gdi.CreateCompatibleBitmap(screenDC, WIDTH, HEIGHT))

	local ITERS = 60

	--- Timed over many iterations and reported as a MEAN, because a single frame
	--- at this scale is a few milliseconds and the clock's own granularity is a
	--- meaningful fraction of that.
	local function timed(label: string, n: number, fn: (() -> ()))
		--- One untimed pass first: the first call populates every cache in the
		--- system, and averaging it in measures the warm-up rather than the
		--- steady state the loop actually runs in.
		fn()
		local t0 = os.clock()
		for _ = 1, n do
			fn()
		end
		local ms = (os.clock() - t0) / n * 1000
		print(string.format("  %-34s %7.3f ms", label, ms))
		return ms
	end

	local frame = session.Snapshot()
	local textNodes, shapeNodes = 0, 0
	for _, n in ipairs(frame.Nodes) do
		if type(n.text) == "string" and n.text ~= "" then
			textNodes += 1
		end
		if n.fill or n.stroke or n.gradient then
			shapeNodes += 1
		end
	end

	print(`=== profile: {screenChoice or "(demo)"}, {#frame.Nodes} nodes `
		.. `({shapeNodes} shape, {textNodes} text), {WIDTH}x{HEIGHT} ===`)
	print(``)
	print(`  FRAME PRODUCTION`)
	local stepOnly = timed("session.Step", ITERS, function() session.Step(1 / 60) end)
	timed("session.Snapshot", ITERS, function() session.Snapshot() end)

	--- THIS NUMBER HAS TWO REGIMES, AND THE COST DEPENDS ON WHICH ONE YOU ARE IN.
	---
	--- `SnapshotDelta` reuses the node table of anything that did not change
	--- (ms-52 M15.3), so what it costs is a function of how many nodes DID. Timed
	--- 60 times in a row without stepping, the screen goes idle after the first
	--- call and every node is reused -- so the mean is the reuse path almost
	--- neat, and the churn figure printed beside it says so.
	---
	--- Reported as "n of m rebuilt" rather than as a second timing, because
	--- separating the delta from the step means subtracting two ~3 ms numbers and
	--- the difference is smaller than their noise.
	local _ = stepOnly
	timed("session.SnapshotDelta", ITERS, function() session.SnapshotDelta() end)
	do
		local idle = session.SnapshotDelta()
		session.Step(1 / 60)
		local stepped = session.SnapshotDelta()
		print(string.format("  %-34s %3d of %d idle, %d of %d after a step",
			"-> nodes rebuilt", #idle.Changed, #idle.Frame.Nodes,
			#stepped.Changed, #stepped.Frame.Nodes))
	end

	--- THE SNAPSHOT PASS, BROKEN INTO ITS SUSPECTS -- the same rule as the text
	--- breakdown below: each item is isolated by running the same walk with the
	--- others removed, so the numbers are attributable rather than plausible.
	---
	--- This exists because "SnapshotDelta is 0.77 ms" was read as one lever and
	--- is not: `session.Snapshot` reuses the session's solve, so that number is
	--- `SnapshotSolved` alone, and it splits into six items of 0.06-0.13 ms.
	--- There is no dominant term to remove -- which is the finding.
	do
		local Layout = require("../../../src/host/Layout")
		local Live = require("../../../src/host/Live")
		local host, root = app.Host, app.Root
		local Scene = host.Scene
		local box = { X = 0, Y = 0, Width = WIDTH, Height = HEIGHT }
		local solved = Layout.Solve(Scene, root, box, host)
		timed("  Layout.Solve alone", ITERS, function()
			Layout.Solve(Scene, root, box, host)
		end)
		timed("  SnapshotSolved (solve reused)", ITERS, function()
			Live.SnapshotSolved(host, solved, WIDTH, HEIGHT)
		end)
		local KEYS = { "BackgroundColor3", "Text", "TextColor3", "BackgroundTransparency", "TextSize" }
		timed("    Scene.Raw reads", ITERS, function()
			for _, item in ipairs(solved) do
				for _, k in ipairs(KEYS) do
					Scene.Raw(item.Node, k)
				end
			end
		end)
		timed("    Scene.RenderedCorner", ITERS, function()
			for _, item in ipairs(solved) do
				Scene.RenderedCorner(item.Node)
			end
		end)
		timed("    modifier lookups (2/node)", ITERS, function()
			for _, item in ipairs(solved) do
				local node = item.Node
				local find = (node :: any).FindFirstChildOfClass
				if type(find) == "function" then
					pcall(find, node, "UIStroke")
					pcall(find, node, "UIGradient")
				end
			end
		end)
		timed("    alignment resolution", ITERS, function()
			for _, item in ipairs(solved) do
				local node = item.Node
				local text = Scene.Raw(node, "Text")
				if type(text) == "string" and text ~= "" then
					for _, prop in ipairs({ "TextXAlignment", "TextYAlignment" }) do
						local value = Scene.Raw(node, prop)
						if value ~= nil then
							local name = tostring(value)
							local _ = string.find(name, "Right", 1, true)
								or string.find(name, "Bottom", 1, true)
								or string.find(name, "Left", 1, true)
								or string.find(name, "Top", 1, true)
						end
					end
				end
			end
		end)
	end

	print(``)
	print(`  GDI`)
	local gdiAll = timed("Paint (shapes + text)", ITERS, function()
		NativePainter.Paint(memDC, frame)
	end)
	local gdiText = timed("PaintTextOnly", ITERS, function()
		NativePainter.PaintTextOnly(memDC, frame)
	end)
	print(string.format("  %-34s %7.3f ms", "-> shapes alone", gdiAll - gdiText))

	--- THE TEXT PASS, BROKEN INTO ITS THREE SUSPECTS. Each one is isolated by
	--- running the same loop with the other two removed, so the numbers are
	--- attributable rather than merely plausible.
	timed("  text: wstr conversion only", ITERS, function()
		for _, n in ipairs(frame.Nodes) do
			if type(n.text) == "string" and n.text ~= "" then
				Win32.wstr(n.text)
			end
		end
	end)
	timed("  text: DC state only", ITERS, function()
		for _, n in ipairs(frame.Nodes) do
			if type(n.text) == "string" and n.text ~= "" then
				local saved = gdi.SaveDC(memDC)
				gdi.SetBkMode(memDC, Win32.TRANSPARENT)
				gdi.SetTextColor(memDC, 0xE8E8E8)
				gdi.SelectObject(memDC, NativePainter.FontFor(n.textSize or 14))
				if saved ~= 0 then gdi.RestoreDC(memDC, -1) end
			end
		end
	end)

	if useRaster then
		local ok, why = RasterPainter.Available()
		if ok then
			local surface = RasterPainter.NewSurface(WIDTH, HEIGHT, rasterBackend) :: any
			print(``)
			print(`  {string.upper(surface.Backend)}`)

			--- READ THESE WITH `--account`, NOT INSTEAD OF IT.
			---
			--- For vello `ar_fill_rect` only RECORDS -- the pixels are produced
			--- by `vello_render`. But `ar_begin` FLUSHES first, so timing `Paint`
			--- in a loop rasterises the previous iteration's scene on every call:
			--- the number below is record-plus-render wearing the label "Paint",
			--- and dividing it by the node count produced "26 us per rounded
			--- rect" for a cost that is mostly not per-rect at all.
			---
			--- `Present` here is also measured with NO DAMAGE RECT, so it
			--- swizzles all 3.7 MB where the loop touches only the damaged rows.
			---
			--- Neither is a wrong measurement; both are wrong models of the
			--- frame. `--account` measures the loop that runs and its shares add
			--- up to the frame by construction. Use this to compare backends and
			--- that to decide what to fix.
			local all = timed("Paint (shapes + text)", ITERS, function()
				RasterPainter.Paint(surface, frame)
			end)
			RasterPainter.SetTextEnabled(false)
			local shapes = timed("Paint (shapes only)", ITERS, function()
				RasterPainter.Paint(surface, frame)
			end)
			RasterPainter.SetTextEnabled(true)
			print(string.format("  %-34s %7.3f ms", "-> text alone", all - shapes))
			timed("Present (render + swizzle + blit)", ITERS, function()
				WindowsPresenter.Present(RasterPainter, surface, memDC)
			end)

			--- WHICH SIDE OF THE ABI IS THE SHAPE PASS ON?
			---
			--- The same walk with the same branching and the same argument
			--- arithmetic, issuing NO ffi calls. What it costs is Luau; what the
			--- shapes pass costs above it is the crossing plus Rust. Neither
			--- number is available from the other, and the fix for each is
			--- completely different -- which is the lesson from M9, where two of
			--- three named optimisations turned out to be aimed at the wrong
			--- half.
			local shapeNodeCount = 0
			timed("  the same walk, no ffi calls", ITERS, function()
				for _, n in ipairs(frame.Nodes) do
					local hasStroke = n.stroke ~= nil and n.stroke.colour ~= nil
					local hasGradient = n.gradient ~= nil
					local hasFill = n.fill ~= nil and (n.alpha or 1) > 0.004 and n.gradient == nil
					if hasFill or hasStroke or hasGradient then
						if n.clip ~= nil then
							local _ = math.floor(n.clip[1]), math.floor(n.clip[2]),
								math.ceil(n.clip[3]), math.ceil(n.clip[4])
						end
						if hasFill then
							local _ = n.x, n.y, n.w, n.h, n.radius or 0,
								n.fill[1], n.fill[2], n.fill[3],
								math.floor((n.alpha or 1) * 255 + 0.5)
						end
						if hasStroke then
							local _ = n.stroke.thickness, n.stroke.colour[1],
								math.floor((n.stroke.alpha or 1) * 255 + 0.5)
						end
					end
				end
			end)

			--- HOW MANY CROSSINGS, so the per-call cost is a division rather than
			--- a guess. A ten-argument ffi call was measured at 0.58 us in M14.
			local fills, strokes, gradients, clips = 0, 0, 0, 0
			for _, n in ipairs(frame.Nodes) do
				local hasGradient = n.gradient ~= nil
				if n.fill ~= nil and (n.alpha or 1) > 0.004 and not hasGradient then
					fills += 1
				end
				if hasGradient then gradients += 1 end
				if n.stroke ~= nil and n.stroke.colour ~= nil then strokes += 1 end
				if n.clip ~= nil then clips += 2 end
			end
			shapeNodeCount = fills + strokes + gradients
			print(string.format("  %-34s %d fill + %d stroke + %d gradient + %d clip = %d calls",
				"-> ffi calls in the shape pass",
				fills, strokes, gradients, clips, shapeNodeCount + clips))
			local _ = shapeNodeCount
		else
			print(`  raster backend unavailable: {why}`)
		end
	end

	print(``)
	return
end

--------------------------------------------------------------------------------
-- The window.
--------------------------------------------------------------------------------

--- Input arrives HERE, in Luau, from the OS. There is no transport and nothing
--- interprets these before we do -- which is the difference this host exists to
--- demonstrate.
local closing = false

--- What the window procedure last decoded. Kept so `--input-check` can assert on
--- the DECODE rather than merely on "nothing raised" -- the crash this replaced
--- was a decode error, and an error-free run proves nothing about correctness.
local lastPointerX, lastPointerY = -1, -1
--- EVERY pointer position the procedure decoded, not just the last one.
---
--- `--input-check` posts a message at a known point and then pumps for a second.
--- A REAL mouse crossing the window during that second also delivers
--- WM_MOUSEMOVE, overwriting the last value -- so asserting on "the last one"
--- passed or failed depending on where the physical cursor happened to be. It
--- failed with (750,103), which was simply es9's cursor.
local decodedPoints: { { number } } = {}
local sawWheel = false
local sawChar: string? = nil

local wndProc = Win32.closure({
	returns = (zune :: any).ffi.types.i64,
	args = {
		(zune :: any).ffi.types.pointer,
		(zune :: any).ffi.types.u32,
		(zune :: any).ffi.types.u64,
		(zune :: any).ffi.types.i64,
	},
}, function(hwnd: any, msg: number, wpRaw: any, lp: any): number
	if msg == Win32.WM_MOUSEMOVE then
		local x, y = Win32.unpackXY(lp)
		lastPointerX, lastPointerY = x, y
		table.insert(decodedPoints, { x, y })
		session.Pointer("move", x, y)
	elseif msg == Win32.WM_LBUTTONDOWN then
		local x, y = Win32.unpackXY(lp)
		session.Pointer("down", x, y)
	elseif msg == Win32.WM_LBUTTONUP then
		local x, y = Win32.unpackXY(lp)
		session.Pointer("up", x, y)
	elseif msg == Win32.WM_MOUSEWHEEL then
		--- WM_MOUSEWHEEL carries SCREEN coordinates, unlike every other mouse
		--- message, so its lParam cannot be used as a client point. The last
		--- position WM_MOUSEMOVE reported is the right one -- and this comment
		--- said exactly that while the code below passed (-1, -1).
		---
		--- The consequence was visible and asymmetric: the primitive demo scrolled
		--- and the real screens did not. Aether's ScrollArea falls back to
		--- `owner.IsHovered()` when the coordinate misses, so a hovered one still
		--- got the event; ShopUI and SettingsUI scroll a NATIVE ScrollingFrame,
		--- which `Live.Session` resolves purely geometrically and which therefore
		--- matched nothing at (-1, -1).
		sawWheel = true
		session.Wheel(lastPointerX, lastPointerY, -Win32.wheelDelta(wpRaw))
	elseif msg == Win32.WM_CHAR then
		--- wParam is 64-bit and therefore a BUFFER here; see Win32.low32.
		local wp = Win32.low32(wpRaw)
		if wp >= 32 and wp < 127 then
			sawChar = string.char(wp)
			session.Key(string.char(wp))
		elseif wp == 8 then
			session.Key("Backspace")
		elseif wp == 13 then
			session.Key("Enter")
		elseif wp == 27 then
			session.Key("Escape")
		end
	elseif msg == Win32.WM_KEYDOWN then
		local named = ({ [37] = "Left", [39] = "Right", [36] = "Home", [35] = "End", [46] = "Delete" })[Win32.low32(wpRaw)]
		if named then
			session.Key(named)
		end
	elseif msg == Win32.WM_PAINT then
		--- Validated rather than BeginPaint/EndPaint: the loop below repaints
		--- every frame anyway, and an unvalidated WM_PAINT is re-posted forever.
		user32.ValidateRect(hwnd, Win32.null)
		return 0
	elseif msg == Win32.WM_CLOSE or msg == Win32.WM_DESTROY then
		closing = true
		return 0
	end
	return user32.DefWindowProcA(hwnd, msg, wpRaw, lp)
end)

--- The built-in STATIC class, then subclassed. See Win32.luau for why this
--- avoids WNDCLASSEXA entirely.
local title = `Aether -- native, {screenChoice or "demo"} ({WIDTH}x{HEIGHT})`
local hwnd = user32.CreateWindowExA(
	0,
	Win32.cstr("STATIC"),
	Win32.cstr(title),
	Win32.WS_OVERLAPPEDWINDOW + Win32.WS_VISIBLE,
	120, 120,
	--- Client area is smaller than the window; a little slack so the whole frame
	--- is visible without computing the non-client size.
	WIDTH + 16, HEIGHT + 39,
	Win32.null, Win32.null, Win32.null, Win32.null
)
assert(user32.IsWindow(hwnd) ~= 0, "the window should exist")
user32.SetWindowLongPtrA(hwnd, Win32.GWLP_WNDPROC, wndProc)
user32.ShowWindow(hwnd, Win32.SW_SHOW)
user32.UpdateWindow(hwnd)

--- `--input-check`: drive the REAL window procedure with REAL messages.
---
--- This is the check that was missing, and its absence shipped a crash. `--check`
--- exercises the painter and never touches input; `--frames N` proved the loop
--- turns, which it does perfectly well with nobody moving a mouse. The first real
--- WM_MOUSEMOVE panicked on decoding lParam.
---
--- So: post genuine messages to the window and let the OS dispatch them through
--- the same closure a human's mouse would, then assert the SESSION saw the
--- coordinates. Nothing here is simulated except the hand that moves the mouse.
--------------------------------------------------------------------------------
-- `--reload-check`: does an edit reach the screen, and does nothing else?
--------------------------------------------------------------------------------

--- BOTH DIRECTIONS, OR IT PASSES ON ANY REPAINT.
---
--- "The frame changed after I saved" is satisfied by a reload that rebuilds on
--- every poll whether or not anything was edited -- which is a busy loop wearing
--- a feature's clothes. So this asserts the negative too: a file OUTSIDE the hot
--- root must not trigger a reload, and an unedited screen must report no change.
---
--- The signature is total node height, not node count. A count is insensitive to
--- the edit this makes (a resize moves geometry and adds no nodes), and a gate
--- that cannot see its own probe is the failure this repo keeps finding.
--------------------------------------------------------------------------------
-- `--stories-check`: does every story mount, and does it paint anything?
--------------------------------------------------------------------------------

--- WHY THIS IS NOT `--raster --check`.
---
--- That gate asserts a SCREEN's properties -- that translucent nodes blend, that
--- a label's ink is centred in its box -- and a story is usually one small
--- component with no translucency at all. Pointed at a Slider it fails with "no
--- translucent filled node", which says nothing about the Slider.
---
--- What a story must satisfy is weaker and universal: it MOUNTS, and it PAINTS
--- SOMETHING. Both halves matter and the second is the one that catches things.
--- A story that mounts and renders an empty frame is the failure mode this
--- milestone keeps finding -- ms-52 M5's settings audit measured a screen whose
--- content never arrived, and the node count was healthy the whole time.
---
--- INK, therefore, not node count: pixels that differ from the cleared
--- background. A tree of correctly-built invisible frames has plenty of nodes
--- and no ink.
--------------------------------------------------------------------------------
-- `--browse-check`: is the picker a list you can actually click?
--------------------------------------------------------------------------------

--- A SIDEBAR THAT RENDERS IS NOT A BROWSER. It has to list every story, and a
--- click on a row has to select THAT row's story -- and the second half is where
--- a picker goes wrong: rows built in a loop that all close over the last one
--- look perfect and open the same story every time.
---
--- So this presses each row by hitting its solved rectangle through the real
--- PointerRouter, and requires the id that comes back to be the id that row
--- names. Nothing here simulates a callback directly; the press goes through the
--- same arbitration a mouse does.
if table.find(ARGS, "--browse-check") then
	local all = Stories.Discover("pkgs/ui")
	assert(#all >= 12, `the browser needs stories to browse; found {#all}`)

	--- The sidebar's own width, so "is this node in the list" is one constant
	--- rather than a magic number repeated at three call sites.
	local SIDEBAR_EDGE = 300
	--- One row plus its gap: the most a correct clamp can be off by, given the
	--- list's own padding and rounding.
	local ROW_SLACK = 30

	local picked: { string } = {}
	local a = App.create({
		Story = Browser.Build({
			Stories = all,
			Selected = all[1].Id,
			OnSelect = function(id: string)
				table.insert(picked, id)
			end,
		}),
		Metrics = metricsProvider,
	})
	local frame = a.Session.SnapshotDelta(true).Frame

	--- EVERY STORY IS LISTED, IN ORDER, and matched BY POSITION rather than by
	--- text.
	---
	--- Two stories are both called "Disabled" -- Button's and Toggle's -- so a
	--- text-keyed lookup silently collapses them and then reports that a row is
	--- bound to the wrong story. That was this check's own bug, found by its own
	--- assertion, and the fix is the stricter one: sidebar rows are collected top
	--- to bottom and required to spell out the story list in order. It cannot be
	--- fooled by duplicate names and it asserts the ordering the format promises.
	local sidebarRows: { any } = {}
	for _, n in ipairs(frame.Nodes) do
		if type(n.text) == "string" and n.text ~= "" and n.x < SIDEBAR_EDGE then
			table.insert(sidebarRows, n)
		end
	end
	table.sort(sidebarRows, function(p, q)
		return p.y < q.y
	end)

	--- Headers carry a Title and rows carry a Name, interleaved. Walk both lists
	--- once: a header is expected wherever the title changes, and a row
	--- everywhere else.
	local expected: { { text: string, story: any? } } = {}
	local lastTitle: string? = nil
	for _, st in ipairs(all) do
		if st.Title ~= lastTitle then
			lastTitle = st.Title
			table.insert(expected, { text = st.Title, story = nil })
		end
		table.insert(expected, { text = st.Name, story = st })
	end

	assert(#sidebarRows == #expected,
		`the sidebar shows {#sidebarRows} text rows; the story list wants {#expected}`)
	for i, want in ipairs(expected) do
		assert(sidebarRows[i].text == want.text,
			`sidebar row {i} reads "{sidebarRows[i].text}", expected "{want.text}" -- `
				.. `the list is out of order or incomplete`)
	end
	print(`listed: all {#all} stories, in order, under {#expected - #all} heading(s)`)

	--- AND THE STORY ITSELF IS ON THE STAGE. The first story is selected, so its
	--- content must be to the right of the sidebar. Without this the browser
	--- could list everything and mount nothing.
	--- CONTENT on the stage, not the stage itself.
	---
	--- Counting every node at x >= the sidebar edge counts `StoryStage`, which is
	--- always there -- so the check passed with the mounted story dropped
	--- entirely. Found by poisoning it: removing the story from the stage left
	--- this GREEN. The container is excluded by name and the bar is content.
	local onStage = 0
	for _, n in ipairs(frame.Nodes) do
		if n.x >= SIDEBAR_EDGE and n.name ~= "StoryStage" and n.name ~= "StoryBrowser" then
			onStage += 1
		end
	end
	assert(onStage > 0, `nothing is mounted on the stage for {all[1].Id}`)
	print(`mounted: {onStage} node(s) on the stage for "{all[1].Id}"`)

	--- CLICK EVERY ROW, SCROLLING TO REACH THE ONES BELOW THE FOLD.
	---
	--- The list is taller than the window and always was -- 19 rows against 420 px.
	--- P1 asserted instead that the list must FIT, because it had concluded the
	--- list could not scroll; D2 found that it always could and that what was
	--- broken was the clamp. So the honest requirement is the one that was
	--- unreachable then: every story is REACHABLE, and getting there exercises the
	--- wheel through the picker's own ScrollingFrame.
	--- AND IT STOPS IN THE RIGHT PLACE (ms-53 D2).
	---
	--- Reaching every row does not prove the scroll extent is right: an area that
	--- over-scrolls reaches them too, and then keeps going past the end into empty
	--- space. That is what off-engine did -- the viewport and content heights were
	--- measured only in Roblox, so the controller clamped against numbers nobody
	--- had given it, and the list ran 292 px past its own bottom.
	---
	--- Stated as the property a reader can check: scrolled to the end, the LAST
	--- thing in the list sits at the BOTTOM of the viewport. Not above it (the
	--- list stopped early), not below (it went too far).
	local function contentBottom(): number
		local f = a.Session.SnapshotDelta(true).Frame
		local b = -math.huge
		for _, n in ipairs(f.Nodes) do
			if n.x < SIDEBAR_EDGE and type(n.text) == "string" and n.text ~= "" then
				b = math.max(b, n.y + n.h)
			end
		end
		return b
	end

	local startBottom = contentBottom()
	assert(startBottom > a.Height,
		`this check needs a list taller than the window; it is {startBottom} in {a.Height}`)
	for _ = 1, 60 do
		a.Session.Wheel(SIDEBAR_EDGE / 2, a.Height / 2, 3)
		for _ = 1, 4 do
			a.Session.Step(1 / 60)
		end
	end
	local endBottom = contentBottom()
	local overscroll = a.Height - endBottom
	print(string.format("clamped: content bottom lands at %.0f in a %d window (overscroll %.0f)",
		endBottom, a.Height, overscroll))
	--- A row of slack for padding and rounding; 292 px is the defect.
	assert(math.abs(overscroll) <= ROW_SLACK,
		`the list stops {math.floor(overscroll)} px from the bottom of the window -- `
			.. "the scroll extent does not match the content")

	--- BACK TO THE TOP before clicking. The clamp check above scrolled to the end,
	--- and a loop that only ever scrolls DOWN from there reaches nothing -- which
	--- it did, silently, reporting 14 of 22 rows as unreachable when the real
	--- cause was the check before it leaving the list where it found the bottom.
	for _ = 1, 60 do
		a.Session.Wheel(SIDEBAR_EDGE / 2, a.Height / 2, -3)
		for _ = 1, 2 do
			a.Session.Step(1 / 60)
		end
	end

	local PointerRouter = a.PointerRouter
	local hit: { [number]: boolean } = {}
	local checked = 0

	--- MATCHED BY INDEX, not by text, for the second time in this gate's life.
	---
	--- Keying on the row's text skipped the second story sharing a name -- and
	--- there are several ("Disabled" is both Button's and Toggle's, "Clean" and
	--- "Label" recur). Every pass rebuilds the FULL ordered row list, clipped rows
	--- included, so `sidebarRows[i]` is `expected[i]` no matter where the list is
	--- scrolled to. Position is the only identity here that duplicates cannot
	--- confuse.
	for pass = 1, 30 do
		local f = a.Session.SnapshotDelta(true).Frame
		local rows: { any } = {}
		for _, n in ipairs(f.Nodes) do
			if type(n.text) == "string" and n.text ~= "" and n.x < SIDEBAR_EDGE then
				table.insert(rows, n)
			end
		end
		table.sort(rows, function(p, q)
			return p.y < q.y
		end)
		assert(#rows == #expected,
			`the sidebar shows {#rows} rows on pass {pass}; the story list wants {#expected}`)

		for i, want in ipairs(expected) do
			if want.story ~= nil and not hit[i] then
				local n = rows[i]
				local cy = n.y + n.h / 2
				--- Only a row whose CENTRE is in view: a row half scrolled off is
				--- not something a user can click either.
				if cy > 0 and cy < a.Height then
					local before = #picked
					local cx = n.x + n.w / 2
					PointerRouter._SimulateHover(cx, cy)
					PointerRouter._SimulatePress(cx, cy)
					PointerRouter._SimulateRelease(cx, cy)
					assert(#picked == before + 1,
						`pressing "{want.text}" at ({math.floor(cx)},{math.floor(cy)}) selected nothing`)
					assert(picked[#picked] == want.story.Id,
						`pressing "{want.text}" selected "{picked[#picked]}", not "{want.story.Id}" -- `
							.. "rows are not bound to their own story")
					hit[i] = true
					checked += 1
				end
			end
		end

		if checked >= #all then
			break
		end
		--- SCROLL. POSITIVE moves content up, which reveals what is below --
		--- getting that backwards is what made P1 believe the wheel was dead.
		a.Session.Wheel(SIDEBAR_EDGE / 2, a.Height / 2, 3)
		for _ = 1, 6 do
			a.Session.Step(1 / 60)
		end
	end

	assert(checked == #all,
		`{checked} of {#all} rows were reachable and clickable -- the rest could not be scrolled to`)
	print(`scrolled: every one of the {#all} rows was reached`)
	a.Destroy()
	print(`clicked: {checked} rows, each selected its own story`)
	print("OK -- the picker lists every story, mounts the selected one, and each row selects itself.")
	return
end

--------------------------------------------------------------------------------
-- `--screens-check`: are the shipped screens actually driven by the framework?
--------------------------------------------------------------------------------

--- THE MACHINERY EXISTED WITH NO DRIVERS, and that is what this stops recurring.
---
--- `ScreenStack` and `TransitionOrchestrator` were 549 lines with ZERO callers:
--- the kits took `Visible` as a prop and the app passed `true`. Nothing was
--- registered, nothing was bound, and so `ProgressIsDriven` was false everywhere
--- -- which meant a menu told to hide consulted a constant-1 stand-in and never
--- hid at all (ms-53 D3). The defect was a symptom of the machinery being unused.
---
--- So this asserts USE, not just correctness: each shipped screen is registered,
--- has a bound transition, and -- the part that only works when both are true --
--- keeps rendering while it animates out before it stops.


---------------------------------------------------------------------------------
-- `--stagger-check`: do the rows actually arrive at DIFFERENT times?
---------------------------------------------------------------------------------

--- THE ONE ASSERTION THREE IMPLEMENTATIONS NEVER HAD.
---
--- `PropertyTransforms.Stagger`, `MotionPackManager.Stagger` and
--- `TransitionOrchestrator.StaggerOffset` all had suites, and every one of them
--- asserted that a number MOVED. A stagger that returns the parent's progress
--- unchanged for every index passes all of that -- and that is exactly what
--- shipped, because no preset set `StaggerDelay`, so every child's start was
--- `index * 0`.
---
--- So this gate asserts DIVERGENCE: two rows whose entrances are offset must be
--- in different places at some point during the window's entrance. It cannot be
--- satisfied by uniform progress, and it cannot be satisfied by a stagger that is
--- never reached -- which is the other half, since `Stagger.use()` answers nil
--- outside a provider and a row then simply sits still.
if table.find(ARGS, "--stagger-check") then
	local a = App.create({ Screen = "settings", Metrics = metricsProvider })

	--- Where a row's label sits right now, or nil if it is not on screen.
	local function labelX(text: string): number?
		local frame = a.Session.SnapshotDelta(true).Frame
		local needle = string.upper(text)
		for _, n in ipairs(frame.Nodes) do
			if type(n.text) == "string" and string.upper(n.text) == needle then
				return n.x
			end
		end
		return nil
	end

	--- SAMPLED FRAME BY FRAME through the entrance. The divergence exists only
	--- while the window is animating in; by the time it has settled every row has
	--- arrived, and a check that only looked at the end state would be blind to
	--- the whole feature.
	--- The WIDEST gap over the whole entrance, not the first non-zero one. A gap
	--- of a pixel is satisfiable by rounding; the assertion should be that the
	--- rows are visibly apart at some point, which is what the feature is.
	local sawBoth = false
	local maxGap = 0
	local atFirst, atSecond = 0, 0
	for _ = 1, 90 do
		a.Session.Step(1 / 60)
		local first = labelX("Show FPS")
		local second = labelX("Interface scale")
		if first and second then
			sawBoth = true
			local gap = math.abs(first - second)
			if gap > maxGap then
				maxGap, atFirst, atSecond = gap, first, second
			end
		end
	end

	assert(sawBoth, "both General rows should be on screen during the entrance")
	--- 4px is above rounding and below what a correct stagger produces here:
	--- MEASURED at 6px with the shipped 0.08 delay and 0.3 item duration, and at
	--- 2.6px with the first values tried -- which is why the threshold sits
	--- between the two rather than at "greater than zero".
	assert(maxGap > 4,
		`the rows never diverged -- every row entered together, which is what an inert `
			.. `stagger looks like (widest gap was {maxGap}px)`)

	--- AND THEY CONVERGE. A stagger that permanently left later rows offset would
	--- satisfy the assertion above and leave the menu visibly crooked.
	for _ = 1, 240 do
		a.Session.Step(1 / 60)
	end
	local restFirst = labelX("Show FPS")
	local restSecond = labelX("Interface scale")
	assert(restFirst ~= nil and restSecond ~= nil, "both rows should still be on screen at rest")
	assert(math.abs((restFirst :: number) - (restSecond :: number)) < 0.5,
		`at rest the rows must line up; got {restFirst} vs {restSecond}`)

	a.Destroy()
	print(string.format("stagger: rows %.0f px apart at the widest (%.0f vs %.0f), aligned at %.0f at rest",
		maxGap, atFirst, atSecond, restFirst))
	print("OK -- staggered rows arrive at different times, and line up when they land.")
	return
end
---------------------------------------------------------------------------------
-- `--tabs-check`: does clicking a TAB change the panel, or only the highlight?
---------------------------------------------------------------------------------

--- es9, 2026-08-23: "clicking the tabs hasn't been changing the actual settings
--- view, it stays stuck on the first one it had selected [...] worth noting
--- though that the tab highlights for the buttons themselves are responsive."
---
--- Exactly right, and there was never any panel switching to break: `ActiveTab`
--- reached `TabNav` and nothing else, so the highlight WAS the whole feature.
---
--- WHY THIS IS A GATE AND NOT ONLY A SUITE. `TabPanels.test.luau` asserts the
--- same thing against a hand-built menu; this presses the REAL tab at its solved
--- rectangle in the shipped fixture, so it covers pointer, pressable, callback,
--- selection group, context, presence and layout in the arrangement a person
--- actually meets.
---
--- IT ASSERTS THE LABELS, NOT THE COUNT. A node total moves for all sorts of
--- reasons -- a different row height, one extra divider -- and "the number
--- changed" is satisfiable by a menu that swapped nothing and re-laid itself.
--- The rows carry their setting names, so the gate can say which panel is up.
if table.find(ARGS, "--tabs-check") then
	local a = App.create({ Screen = "settings", Metrics = metricsProvider })
	local PointerRouter = a.PointerRouter

	local function settle()
		for _ = 1, 120 do
			a.Session.Step(1 / 60)
		end
	end
	settle()

	local function frame()
		return a.Session.SnapshotDelta(true).Frame
	end

	--- Is a row with this label on screen right now? Compared UPPERCASED, because
	--- `SettingsRow` renders its label that way and a case-sensitive match here
	--- would report every panel missing -- which looks exactly like the defect
	--- this gate exists to catch.
	local function showing(label: string): boolean
		local needle = string.upper(label)
		for _, n in ipairs(frame().Nodes) do
			if type(n.text) == "string" and string.upper(n.text) == needle then
				return true
			end
		end
		return false
	end

	--- The tab strip sits directly under the window header. Matched by the
	--- UPPERCASED label `TabNav` renders, and by nothing else -- a section header
	--- is uppercase too, so the y band is what separates them.
	local function pressTab(label: string)
		local target: any = nil
		for _, n in ipairs(frame().Nodes) do
			if n.text == string.upper(label) and n.h < 44 then
				if target == nil or n.y < target.y then
					target = n
				end
			end
		end
		assert(target ~= nil, `no tab labelled "{label}" was found`)
		local cx, cy = target.x + target.w / 2, target.y + target.h / 2
		PointerRouter._SimulateHover(cx, cy)
		PointerRouter._SimulatePress(cx, cy)
		PointerRouter._SimulateRelease(cx, cy)
		settle()
	end

	--- GENERAL is the default panel, and the two others must NOT be on screen.
	--- The second half is the actual defect: every panel used to render at once.
	assert(showing("Show FPS"), "the default General panel should be on screen")
	assert(not showing("Master volume"), "the Audio panel must not be on screen at the same time")
	assert(not showing("Look sensitivity"), "nor the Controls panel")

	pressTab("Audio")
	assert(showing("Master volume"), "clicking Audio must bring the Audio panel up")
	assert(not showing("Show FPS"), "and General must leave -- this is the bug es9 reported")

	pressTab("Controls")
	assert(showing("Look sensitivity"), "clicking Controls must bring its panel up")
	assert(not showing("Master volume"), "and Audio must leave")

	--- AND BACK. Stuck-on-the-second-tab passes everything above.
	pressTab("General")
	assert(showing("Show FPS"), "clicking General again must bring it back")
	assert(not showing("Look sensitivity"), "and Controls must leave")

	a.Destroy()
	print("tabs: General -> Audio -> Controls -> General, one panel at a time")
	print("OK -- clicking a tab changes the panel, not just the highlight.")
	return
end
--------------------------------------------------------------------------------
-- `--switcher-check`: does clicking a button actually switch the menu?
--------------------------------------------------------------------------------

--- THE SCENE, DRIVEN THROUGH THE ROUTER rather than through the stack directly.
---
--- `--screens-check` calls `Open` and `Close` itself, which proves the wiring
--- but not the bar. This presses the real buttons at their solved rectangles and
--- requires the MENU to follow -- so it covers the whole path a person takes:
--- pointer, pressable, handler, stack, exclusivity, presence, layout.
---
--- Exclusivity is the assertion worth having. Nothing in the scene tracks which
--- menu is up; opening one must close the other because they share a category,
--- and a switcher that got that wrong would show both at once and still look
--- like it worked from a node count.
if table.find(ARGS, "--switcher-check") then
	local Aether = require("../../../src")
	local a = App.create({ Screen = "switcher", Metrics = metricsProvider })
	local Stack = Aether.ScreenStack
	local PointerRouter = a.PointerRouter

	local function settle()
		for _ = 1, 120 do
			a.Session.Step(1 / 60)
		end
	end
	local function nodes(): number
		return #a.Session.SnapshotDelta(true).Frame.Nodes
	end

	--- Find a bar button by its label, in the CURRENT frame. Looked up fresh each
	--- time because the bar's own labels change colour with the open screen, and
	--- a rect captured once would be stale after the first press.
	local function press(label: string)
		local frame = a.Session.SnapshotDelta(true).Frame
		local target: any = nil
		for _, n in ipairs(frame.Nodes) do
			if n.text == label and n.y < 44 then
				target = n
			end
		end
		assert(target ~= nil, `no bar button labelled "{label}" was found`)
		local cx, cy = target.x + target.w / 2, target.y + target.h / 2
		PointerRouter._SimulateHover(cx, cy)
		PointerRouter._SimulatePress(cx, cy)
		PointerRouter._SimulateRelease(cx, cy)
		settle()
	end

	local bare = nodes()
	assert(bare > 4, `the bar should render; got {bare} nodes`)
	assert(not Stack.IsOpen("Shop")() and not Stack.IsOpen("Settings")(),
		"nothing should be open before anything is clicked")

	press("Shop")
	assert(Stack.IsOpen("Shop")(), "clicking Shop opens it")
	local withShop = nodes()
	assert(withShop > bare + 20, `the shop should have mounted; {bare} -> {withShop} nodes`)

	--- THE ONE THAT MATTERS. Nothing closes Shop here; the stack does, because
	--- both are Window and exclusive.
	press("Settings")
	assert(Stack.IsOpen("Settings")(), "clicking Settings opens it")
	assert(not Stack.IsOpen("Shop")(), "and exclusivity closes the shop -- nothing else does")
	local withSettings = nodes()
	assert(withSettings > bare, `settings should have mounted; got {withSettings} nodes`)
	assert(withSettings < withShop, `and the shop should be gone; {withShop} -> {withSettings} nodes`)

	--- Toggling the current one closes it, which is the half a switcher that only
	--- ever opens would never exercise.
	--- CLOSING ANIMATES, and this is the only thing that makes `Bind` load-bearing
	--- here: an UNBOUND menu still opens and closes, just instantly, and a node
	--- count taken after settling cannot tell the difference. Pressed and read
	--- BEFORE settling, a bound menu is still on screen.
	local frameBefore = a.Session.SnapshotDelta(true).Frame
	local settingsLabel: any = nil
	for _, n in ipairs(frameBefore.Nodes) do
		if n.text == "Settings" and n.y < 44 then
			settingsLabel = n
		end
	end
	assert(settingsLabel ~= nil, "the Settings button should still be there")
	PointerRouter._SimulateHover(settingsLabel.x + settingsLabel.w / 2, settingsLabel.y + settingsLabel.h / 2)
	PointerRouter._SimulatePress(settingsLabel.x + settingsLabel.w / 2, settingsLabel.y + settingsLabel.h / 2)
	PointerRouter._SimulateRelease(settingsLabel.x + settingsLabel.w / 2, settingsLabel.y + settingsLabel.h / 2)
	assert(not Stack.IsOpen("Settings")(), "clicking the open menu closes it")
	--- ONE FRAME, so the reactive `Visible` actually propagates. Reading straight
	--- after the press measures reactive LAG rather than an animation -- the menu
	--- is still there because the effect has not run, bound or not, which is why
	--- this assertion was blind to a missing `Bind` until it stepped.
	a.Session.Step(1 / 60)
	local duringExit = nodes()
	assert(duringExit > bare,
		`a bound menu must still be on screen while it animates out; it dropped to {duringExit} at once`)

	settle()
	local closed = nodes()
	assert(closed == bare, `back to the bar alone; expected {bare} nodes, got {closed}`)

	a.Destroy()
	print(string.format("switcher: bar %d -> shop %d -> settings %d -> bar %d",
		bare, withShop, withSettings, closed))
	print("OK -- clicking a button switches the menu, and exclusivity closes the other one.")
	return
end

if table.find(ARGS, "--screens-check") then
	local Aether = require("../../../src")
	local failures = 0

	for _, case in ipairs({ { "shop", "Shop" }, { "settings", "Settings" } }) do
		local flag, screenId = case[1], case[2]
		local a = App.create({ Screen = flag, Metrics = metricsProvider })

		local bound = Aether.TransitionOrchestrator.HasBinding(screenId)
		local open = Aether.ScreenStack.IsOpen(screenId)()
		--- The CATEGORY, not merely registration: `Open` auto-registers, so
		--- "is it known" is satisfied by opening it at all. What the config
		--- actually buys is the category exclusivity and modal depth arbitrate on,
		--- and that is the thing worth asserting.
		local entry = Aether.ScreenStack.GetEntry(screenId)
		--- `Enter` is what marks the screen PRESENT to the orchestrator, and
		--- without asserting it the call is invisible: the exit still behaves,
		--- because the spring is already at rest. The poison matrix found that --
		--- removing `Enter` changed nothing this gate could see.
		local present = Aether.TransitionOrchestrator.IsPresent(screenId)
		local mounted = #a.Session.SnapshotDelta(true).Frame.Nodes

		--- Closing must NOT empty it on the same frame. That is the whole point of
		--- a bound transition, and an unbound screen fails here by vanishing
		--- instantly -- which is correct behaviour for an unbound screen and wrong
		--- for a shipped one.
		--- CLOSED THROUGH THE STACK ALONE. The orchestrator subscribes to it, so
		--- an explicit `Exit` here would hide whether that wiring works -- and the
		--- wiring is the thing this gate exists to prove.
		Aether.ScreenStack.Close(screenId)
		local during = #a.Session.SnapshotDelta(true).Frame.Nodes

		for _ = 1, 240 do
			a.Session.Step(1 / 60)
		end
		local after = #a.Session.SnapshotDelta(true).Frame.Nodes
		--- AND THE STACK AGREES IT IS GONE. `Present` is cleared by a settle pass
		--- that ran ONLY on Roblox's Heartbeat until ms-53 D6 -- so off-engine a
		--- closed screen stayed "present" for the rest of the process, and anything
		--- sequencing behind it under `SwitchMode = "wait"` would have waited
		--- forever. Nothing asserted it, which is why it survived.
		local finalPhase = Aether.ScreenStack.Phase(screenId)()
		a.Destroy()

		local problems: { string } = {}
		if not bound then
			table.insert(problems, "no bound transition")
		end
		if not open then
			table.insert(problems, "not registered as open")
		end
		if not present then
			table.insert(problems, "the orchestrator does not consider it present -- Enter was never called")
		end
		if not entry or entry.Category ~= "Window" then
			table.insert(problems, `category is {if entry then tostring(entry.Category) else "nil"}, not Window`)
		end
		if mounted < 10 then
			table.insert(problems, `only {mounted} nodes while open`)
		end
		if during < 10 then
			table.insert(problems, `emptied to {during} nodes the instant it closed -- nothing animates out`)
		end
		if after ~= 0 then
			table.insert(problems, `still drew {after} nodes four seconds after closing`)
		end
		if finalPhase ~= "closed" then
			table.insert(problems, `the stack still reads "{finalPhase}" after the exit settled`)
		end

		if #problems > 0 then
			failures += 1
			print(string.format("  FAIL  %-10s %s", flag, table.concat(problems, "; ")))
		else
			print(string.format("  ok    %-10s bound, open, %d nodes -> %d while closing -> 0",
				flag, mounted, during))
		end
	end

	assert(failures == 0, `{failures} shipped screen(s) are not driven by the framework`)
	print("OK -- both shipped screens are registered, bound, and animate out before they stop.")
	return
end

if table.find(ARGS, "--stories-check") then
	local ok, why = RasterPainter.Available()
	assert(ok, `--stories-check needs the Rust backend: {tostring(why)}`)
	RasterPainter.LoadFont()

	local all = Stories.Discover("pkgs/ui")
	assert(#all > 0, "no stories were discovered at all -- the walk found nothing")

	local surface = RasterPainter.NewSurface(WIDTH, HEIGHT, RasterPainter.VELLO_CPU) :: any
	local BG = { 11, 13, 18 }

	local titles: { [string]: boolean } = {}
	local failures = 0
	for _, st in ipairs(all) do
		titles[st.Title] = true
		local built, err = pcall(function()
			local a = App.create({ Story = st.Build, Metrics = metricsProvider })
			local frame = a.Session.SnapshotDelta(true).Frame
			RasterPainter.Paint(surface, frame)

			--- Sampled on a grid rather than every pixel: a story that painted
			--- one stray pixel is not what this is looking for, and a coarse grid
			--- over a whole viewport still lands hundreds of samples inside any
			--- component big enough to see.
			local ink = 0
			for py = 0, HEIGHT - 1, 3 do
				for px = 0, WIDTH - 1, 3 do
					local v = RasterPainter.Pixel(surface, px, py)
					local r, g, b = math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256
					if r ~= BG[1] or g ~= BG[2] or b ~= BG[3] then
						ink += 1
					end
				end
			end
			a.Destroy()
			return { nodes = #frame.Nodes, ink = ink }
		end)

		if not built then
			failures += 1
			print(string.format("  FAIL  %-46s %s", st.Id, tostring(err)))
		else
			local r = err :: any
			if st.Empty then
				--- ASSERTED, NOT EXEMPTED. A story that declares itself empty must
				--- BE empty; one that starts painting again is a regression the
				--- flag catches rather than hides.
				if r.ink > 0 then
					failures += 1
					print(string.format("  FAIL  %-46s %d nodes, %d ink -- declared Empty, but it painted",
						st.Id, r.nodes, r.ink))
				else
					print(string.format("  ok    %-46s empty, as declared", st.Id))
				end
			elseif r.nodes <= 0 or r.ink <= 0 then
				failures += 1
				print(string.format("  FAIL  %-46s %d nodes, %d ink -- mounted and painted nothing",
					st.Id, r.nodes, r.ink))
			else
				print(string.format("  ok    %-46s %3d nodes, %5d ink", st.Id, r.nodes, r.ink))
			end
		end
	end

	local titleCount = 0
	for _ in pairs(titles) do
		titleCount += 1
	end
	RasterPainter.FreeSurface(surface)

	print(`{#all} stories across {titleCount} title(s), {#Stories.Files(all)} file(s)`)
	assert(failures == 0, `{failures} of {#all} stories did not mount and paint`)
	--- The sprint's exit gate, asserted rather than eyeballed. A story browser
	--- with three stories in one package proves the plumbing and nothing about
	--- whether the format survives contact with real components.
	assert(#all >= 12, `the exit gate wants at least 12 stories; there are {#all}`)
	assert(titleCount >= 4, `and across at least 4 components/kits; there are {titleCount}`)
	print("OK -- every story mounts and paints.")
	return
end

if table.find(ARGS, "--reload-check") then
	local fsz = (zune :: any).fs
	local KIT = "pkgs/ui/kits/ShopUI/src/ShopMenu.luau"
	local COLD = "src/host/Live.luau"

	Reload.SetHotRoot("pkgs/ui/kits")

	local function signature(): (number, number)
		Reload.BeginBuild()
		local a = Reload.Load(APP_PATH).create({ Screen = "shop", Metrics = metricsProvider })
		local f = a.Session.SnapshotDelta(true).Frame
		local h = 0
		for _, n in ipairs(f.Nodes) do
			h += n.h
		end
		a.Destroy()
		return #f.Nodes, math.floor(h)
	end

	local original = fsz.readFile(KIT)
	local coldOriginal = fsz.readFile(COLD)

	--- Restored in one place, on every exit. A gate that leaves an edited source
	--- behind when it fails has done more damage than the bug it was looking for.
	local function restore()
		fsz.writeFile(KIT, original)
		fsz.writeFile(COLD, coldOriginal)
	end

	local ok, err = pcall(function()
		local n0, h0 = signature()
		print(`baseline: {n0} nodes, total height {h0}`)
		assert(n0 > 100, `the shop screen should have built; got {n0} nodes`)

		--- The watch set is DISCOVERED, and must contain what was loaded.
		local watched = Reload.Watched()
		assert(#watched >= 5, `watch set should cover the kit; got {#watched} file(s)`)
		assert(not Reload.Changed(), "an untouched tree must report no change")

		--- 1. AN EDIT REACHES THE SCREEN.
		local edited = string.gsub(original, "0, 680, 0, 560", "0, 520, 0, 420", 1)
		assert(edited ~= original, "the probe edit did not apply -- this gate is testing nothing")
		fsz.writeFile(KIT, edited)
		assert(Reload.Changed(), "an edited file in the hot root must be seen")
		local n1, h1 = signature()
		print(`after edit: {n1} nodes, total height {h1}`)
		assert(h1 ~= h0, `the edit did not reach the screen: height stayed {h0}`)

		--- 2. AND IT GOES BACK. A reload that only ever moves one way would pass
		--- the assertion above while being unable to return to a known state.
		fsz.writeFile(KIT, original)
		local n2, h2 = signature()
		assert(h2 == h0, `restoring the source must restore the screen: {h0} -> {h2}`)
		assert(n2 == n0, `and the node count: {n0} -> {n2}`)

		--- 3. A FILE OUTSIDE THE HOT ROOT MUST NOT TRIGGER. Touching a framework
		--- file is the control: it proves the poll is reading the watch set
		--- rather than reloading on a timer.
		local NL = string.char(10)
		fsz.writeFile(COLD, coldOriginal .. NL .. "-- reload-check touch" .. NL)
		assert(not Reload.Changed(),
			"a file OUTSIDE the hot root triggered a reload -- the boundary is not being applied")
		fsz.writeFile(COLD, coldOriginal)

		--- 3b. THE WATCH SET IS REBUILT, NOT ACCUMULATED.
		---
		--- `Load` clears the set before walking, so a file that stops being
		--- reached stops being watched. Without that, deleting a require leaves a
		--- phantom entry behind and every later edit to that orphan triggers a
		--- reload of a screen that no longer depends on it -- a reload loop with
		--- no visible cause.
		---
		--- Asserted by NARROWING the hot root: with nothing hot, only the entry
		--- module is loaded fresh, so the set must shrink to one. An accumulated
		--- set stays at its previous size, which is exactly the poison.
		---
		--- The wide case must go through `signature()`, not a bare `Load`: App
		--- requires the kit modules INSIDE `create`, not at module scope, so
		--- loading without building leaves the set at one legitimately.
		local wideCount = #Reload.Watched()
		Reload.SetHotRoot("pkgs/this_path_does_not_exist")
		Reload.BeginBuild()
		Reload.Load(APP_PATH)
		local narrowCount = #Reload.Watched()
		Reload.SetHotRoot("pkgs/ui/kits")
		signature()
		assert(narrowCount == 1,
			`narrowing the hot root must shrink the watch set to the entry module alone; `
				.. `it was {wideCount} and is now {narrowCount} -- the set is being accumulated, not rebuilt`)
		assert(#Reload.Watched() == wideCount,
			`and widening it again must restore it: {wideCount} -> {#Reload.Watched()}`)

		--- 4. IT DOES NOT LEAK, and the FIRST version of this check could not see
		--- a leak at all.
		---
		--- Node count and total height were the obvious signature and they are
		--- vacuous here: each reload builds a NEW session over a NEW tree, and a
		--- session only ever walks its own root. A leaked tree is invisible to it
		--- by construction. Poisoning the gate by deleting `a.Destroy()` left it
		--- GREEN, which is how this was found.
		---
		--- The router is where a leak is actually observable. It is a module-level
		--- singleton, so every Pressable and every observer from every tree that
		--- was never destroyed is still registered in it -- still resolving, still
		--- being polled. That count is the leak, stated directly.
		local PointerRouter = app.PointerRouter
		local function registrations(): number
			return PointerRouter._Count()
				+ PointerRouter._ObserverCount()
				+ PointerRouter._PointerObserverCount()
				+ PointerRouter._ReleaseObserverCount()
				+ PointerRouter._WheelObserverCount()
		end

		local before = Reload.Generation()
		local nLast, hLast = n0, h0
		local regBase = registrations()
		for i = 1, 20 do
			local n, h = signature()
			assert(n == nLast and h == hLast,
				`reload {i} drifted: {nLast} nodes/{hLast} height -> {n}/{h}`)
			nLast, hLast = n, h
			local reg = registrations()
			assert(reg <= regBase,
				`reload {i} LEAKED: the router held {regBase} registrations before and {reg} after. `
					.. `The old tree was not destroyed.`)
		end
		assert(Reload.Generation() - before >= 20,
			"twenty reloads should have advanced the generation twenty times")
		print(`20 reloads: {nLast} nodes, height {hLast}, router steady at {registrations()} registrations`)

		--- 5. AND IT IS FAST. The number this whole design exists for: a process
		--- restart costs 580-676 ms, so anything near that means the reload has
		--- quietly become one.
		local t0 = os.clock()
		signature()
		local ms = (os.clock() - t0) * 1000
		print(string.format("reload cost: %.1f ms  (a process restart is 580-676 ms)", ms))
		assert(ms < 250, `a reload should be far cheaper than a restart; got {ms} ms`)
	end)

	restore()
	assert(fsz.readFile(KIT) == original, "the gate must leave the source as it found it")
	assert(fsz.readFile(COLD) == coldOriginal, "including the file outside the hot root")
	if not ok then
		error(err, 0)
	end
	print("OK -- an edit reaches the screen, an unrelated file does not, and 20 reloads do not drift.")
	return
end

if table.find(ARGS, "--input-check") then
	local hits = 0
	local resolved = nil

	--- A pointer move at a known point, dispatched by the OS.
	local X, Y = 417, 184
	user32.PostMessageA(hwnd, Win32.WM_MOUSEMOVE, 0, X + Y * 65536)
	user32.PostMessageA(hwnd, Win32.WM_LBUTTONDOWN, 1, X + Y * 65536)
	user32.PostMessageA(hwnd, Win32.WM_LBUTTONUP, 0, X + Y * 65536)
	--- One wheel notch: delta 120 in the HIGH word of wParam.
	user32.PostMessageA(hwnd, Win32.WM_MOUSEWHEEL, 120 * 65536, 0)
	--- One character.
	user32.PostMessageA(hwnd, Win32.WM_CHAR, 65, 0)

	local pump = Win32.alloc(64)
	local t0 = os.clock()
	while os.clock() - t0 < 1.0 do
		while user32.PeekMessageA(pump, Win32.null, 0, 0, 1) ~= 0 do
			user32.TranslateMessage(pump)
			user32.DispatchMessageA(pump)
			hits += 1
		end
	end

	--- Did the pointer actually land where the message said? The router is the
	--- authority, so ask IT rather than trusting that no error was raised.
	session.Step(1 / 60)
	resolved = app.PointerRouter.Resolve(X, Y)

	print(`messages dispatched through the real window procedure: {hits}`)
	print(`router resolves ({X},{Y}): {tostring(resolved ~= nil)}`)
	assert(hits > 0, "no message reached the window procedure")
	--- Was OUR point among the decoded ones? Robust to a real cursor crossing the
	--- window mid-test, which the "last position" form was not.
	local sawPosted = false
	for _, pt in ipairs(decodedPoints) do
		if pt[1] == X and pt[2] == Y then
			sawPosted = true
			break
		end
	end
	assert(sawPosted,
		`the procedure never decoded ({X},{Y}); it saw {#decodedPoints} point(s), last ({lastPointerX},{lastPointerY})`)
	assert(sawWheel, "WM_MOUSEWHEEL was not decoded")

	--- DID THE WHEEL ACTUALLY SCROLL SOMETHING? Decoding it is not the same as
	--- delivering it, and the two came apart here: the delta decoded perfectly
	--- while the coordinate was (-1, -1), so nothing geometric could receive it.
	--- Asserted against the painted content, which is the only thing that proves
	--- delivery end to end.
	local function contentY(): number?
		local f = session.Snapshot()
		for _, n in ipairs(f.Nodes) do
			if n.name == "Item1" or n.name == "ItemCard_Spectre GT" or n.name == "SettingsRow_Music" then
				return n.y
			end
		end
		return nil
	end

	local beforeWheel = contentY()
	if beforeWheel then
		--- Aimed at the middle of the window, where every one of these screens has
		--- its scroll region.
		local wx, wy = math.floor(WIDTH / 2), math.floor(HEIGHT / 2)
		user32.PostMessageA(hwnd, Win32.WM_MOUSEMOVE, 0, wx + wy * 65536)
		--- DOWN, not up. Win32's WHEEL_DELTA is +120 for a scroll AWAY from the
		--- user (up), and these screens start at the top -- so four notches up
		--- correctly clamp to zero and move nothing. The first version of this
		--- assertion posted +120 and failed, which read as "the wheel is broken"
		--- when the wheel was right and the test was pushing against the end stop.
		--- -120 as an unsigned 16-bit high word is 0xFF88.
		for _ = 1, 4 do
			user32.PostMessageA(hwnd, Win32.WM_MOUSEWHEEL, 0xFF88 * 65536, 0)
		end
		local t1 = os.clock()
		while os.clock() - t1 < 0.6 do
			while user32.PeekMessageA(pump, Win32.null, 0, 0, 1) ~= 0 do
				user32.TranslateMessage(pump)
				user32.DispatchMessageA(pump)
			end
		end
		for _ = 1, 30 do
			session.Step(1 / 60)
		end
		local afterWheel = contentY()

		--- IS THERE ANYTHING TO SCROLL? A screen whose content fits its viewport
		--- correctly does not move, and demanding movement there would report the
		--- API working as a failure. SettingsUI is exactly that case with the
		--- current fixture: 218px of content in a 386px viewport, maxScroll 0.
		---
		--- So the assertion follows the geometry: scrollable screens must move,
		--- unscrollable ones must NOT -- which is the stronger pair, because it
		--- also catches a wheel that scrolls something it should not.
		local Layout = require("../../../src/host/Layout")
		local maxScroll = 0
		local function findScrollers(node: any)
			if app.Host.Scene.ClassOf(node) == "ScrollingFrame" then
				local _, _, _, vh = app.Host.Scene.Bounds(node)
				local _, extent = Layout.CanvasExtent(node)
				maxScroll = math.max(maxScroll, extent - vh)
			end
			for _, c in ipairs(app.Host.Scene.Children(node)) do
				findScrollers(c)
			end
		end
		findScrollers(app.Root)

		local moved = afterWheel ~= nil and math.abs(afterWheel - beforeWheel) > 1
		print(`content y on wheel: {string.format("%.1f", beforeWheel)} -> `
			.. `{string.format("%.1f", afterWheel or beforeWheel)}  (maxScroll {string.format("%.0f", maxScroll)})`)
		if maxScroll > 1 then
			assert(moved, `the wheel must move scrollable content; it stayed at {beforeWheel}`)
		else
			assert(not moved, `nothing is scrollable here, yet the content moved from {beforeWheel}`)
			print("  nothing to scroll on this screen -- content fits the viewport")
		end
	end
	assert(sawChar == "A", `WM_CHAR should decode to "A", got {tostring(sawChar)}`)
	print("OK -- real OS messages decode and reach the session.")
	user32.DestroyWindow(hwnd)
	return
end

print(`=== Aether, native, on zune ===`)
print(``)
print(`  screen : {screenChoice or "(primitive demo)"}`)
print(`  window : {WIDTH}x{HEIGHT}`)
print(``)
print(`  No transport. Layout, arbitration, motion and painting all happen in`)
print(`  THIS process; the OS delivers input straight into Luau.`)
print(``)
print(`  Close the window to exit.`)

--------------------------------------------------------------------------------
-- The loop.
--------------------------------------------------------------------------------

local msgBuf = Win32.alloc(64)
local hdc = user32.GetDC(hwnd)

--- DOUBLE BUFFERED. Painting ~185 nodes straight to the window DC flickers
--- badly, because each Rectangle is a separate blit to a surface the compositor
--- is reading. Everything is drawn into a memory bitmap and copied once.
local memDC = gdi.CreateCompatibleDC(hdc)
local bmp = gdi.CreateCompatibleBitmap(hdc, WIDTH, HEIGHT)
gdi.SelectObject(memDC, bmp)

--- THE GPU TARGET, attached to the window this host already created.
---
--- Attached BEFORE the CPU surfaces so a failure can fall through to them. Every
--- failure here is recoverable and none is fatal: no GPU, no adapter able to
--- present to this window, or -- the likeliest -- a library built without the
--- opt-in `gpu` feature.
local gpuTarget = nil
if useGpu then
	local target, why = WindowedPainter.Attach(hwnd, WIDTH, HEIGHT)
	if target then
		gpuTarget = target
		print(`  painter: GPU (vello_hybrid) -- presenting through a wgpu swapchain`)
		print(`  text   : vello -- the only text here; GDI cannot draw on this window`)
	else
		print(`  WARNING: --gpu requested but unavailable, falling back`)
		print(`  {why}`)
		--- Fall back to the CPU rasteriser rather than to GDI: it is the closer
		--- picture, and the user asked for the Rust stack either way.
		useRaster = true
	end
end

--------------------------------------------------------------------------------
-- `--gpu --check`: does the GPU draw the same picture as the CPU backend?
--------------------------------------------------------------------------------

--- THE GPU PATH'S ONLY AUTOMATED GATE, and it needs a window to exist at all --
--- a wgpu surface is created FROM one -- so this runs after the window is made
--- and before the loop starts.
---
--- It compares vello_hybrid against vello_cpu on ONE frame. Both consume the same
--- `Live.Frame` through the same display list and lay text out with the same
--- `FontStore`, so a disagreement is a rasteriser bug by construction. Exact
--- equality is NOT the bar: a GPU rasteriser and a CPU one legitimately differ on
--- anti-aliased edges and in the last bit of a blend.
if gpuCheck then
	assert(gpuTarget, "the GPU target must attach before it can be checked")
	local ok, why = RasterPainter.Available()
	assert(ok, why)
	local cpu = RasterPainter.NewSurface(WIDTH, HEIGHT, RasterPainter.VELLO_CPU) :: any
	assert(cpu and cpu.Backend == "vello_cpu",
		`expected a vello_cpu surface to compare against, got {cpu and cpu.Backend}`)

	local frame = session.Snapshot()
	local gpuCalls = WindowedPainter.Paint(gpuTarget :: any, frame)
	local cpuCalls = RasterPainter.Paint(cpu, frame)
	print(`draw calls: GPU {gpuCalls}, vello_cpu {cpuCalls}`)
	assert(gpuCalls == cpuCalls,
		`the two backends were given different work: {gpuCalls} vs {cpuCalls} draw calls`)

	assert(WindowedPainter.Capture(gpuTarget :: any),
		"the GPU could not render off-screen for verification")

	local function channels(v: number): (number, number, number)
		return math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256
	end

	local sampled, identical, gross = 0, 0, 0
	local worst, worstAt = 0, ""
	local within2, within16 = 0, 0
	local seenGpu, seenCpu = {}, {}
	local dG, dC = 0, 0
	for py = 2, HEIGHT - 2, 3 do
		for px = 2, WIDTH - 2, 3 do
			local a = WindowedPainter.Pixel(gpuTarget :: any, px, py)
			local b = RasterPainter.Pixel(cpu, px, py)
			if not seenGpu[a] then seenGpu[a] = true; dG += 1 end
			if not seenCpu[b] then seenCpu[b] = true; dC += 1 end
			sampled += 1
			if a == b then
				identical += 1
			else
				local ar, ag, ab = channels(a)
				local br, bg, bb = channels(b)
				local d = math.max(math.abs(ar - br), math.abs(ag - bg), math.abs(ab - bb))
				if d <= 2 then
					within2 += 1
				elseif d <= 16 then
					within16 += 1
				else
					gross += 1
				end
				if d > worst then
					worst = d
					worstAt = string.format("(%d,%d) GPU 0x%06X vs CPU 0x%06X", px, py, a, b)
				end
			end
		end
	end

	print(`sampled {sampled} points`)
	print(string.format("  identical            %6d  (%.1f%%)", identical, identical / sampled * 100))
	print(string.format("  within 2 channels    %6d  (%.1f%%)", within2, within2 / sampled * 100))
	print(string.format("  within 16 channels   %6d  (%.1f%%)", within16, within16 / sampled * 100))
	print(string.format("  beyond 16 channels   %6d  (%.1f%%)", gross, gross / sampled * 100))
	print(`  worst: {worstAt}`)

	--- BOTH must have drawn a picture, or "they agree" is two blank surfaces
	--- agreeing -- the vacuity this file has met more than once, and which the
	--- vello_cpu port hit for real when it rendered black and scored 100%.
	assert(dG > 8 and dC > 8,
		`one backend drew nothing: GPU {dG} distinct colours, vello_cpu {dC}`)

	--- WHERE THE GPU FRAME ACTUALLY GOES.
	---
	--- Reported here because the fps figures alone cannot separate "the GPU is no
	--- faster" from "the GPU is faster at something that is no longer the cost".
	--- Both backends RECORD a scene on the CPU and only then diverge, so if
	--- recording dominates, a faster rasteriser cannot show up in a frame time.
	local ITER = 30
	local function timed(label: string, fn: () -> ())
		fn()
		local t0 = os.clock()
		for _ = 1, ITER do
			fn()
		end
		local ms = (os.clock() - t0) / ITER * 1000
		print(string.format("  %-30s %7.3f ms", label, ms))
		return ms
	end
	print(``)
	print(`  FRAME COST`)
	timed("session.Step", function() session.Step(1 / 60) end)
	timed("session.Snapshot", function() session.Snapshot() end)
	local gpuRecord = timed("GPU record (scene)", function()
		WindowedPainter.Paint(gpuTarget :: any, frame)
	end)
	local gpuPresent = timed("GPU render + present", function()
		WindowedPainter.Present(gpuTarget :: any)
	end)
	local cpuPaint = timed("vello_cpu paint (record+raster)", function()
		RasterPainter.Paint(cpu, frame)
	end)
	print(string.format("  -> GPU %.2f ms vs CPU %.2f ms for the same frame",
		gpuRecord + gpuPresent, cpuPaint))
	print(``)

	local agree = (identical + within2 + within16) / sampled
	assert(agree > 0.97,
		string.format("GPU and CPU agree on only %.1f%% of pixels; that is a divergence, not rounding",
			agree * 100))
	print(string.format("OK -- the GPU and CPU rasterisers agree on %.1f%% of sampled pixels.", agree * 100))
	user32.DestroyWindow(hwnd)
	return
end

--- The Rust surface, when asked for and when the library is actually there.
--- A missing build is reported and falls back rather than failing the run.
local rasterSurface = nil
if useRaster and not gpuTarget then
	local ok, why = RasterPainter.Available()
	if ok then
		rasterSurface = RasterPainter.NewSurface(WIDTH, HEIGHT, rasterBackend)
		--- Reported from what the LIBRARY says it made, not from what was asked
		--- for. A request that quietly fell back would otherwise be invisible.
		print(`  painter: RUST ({(rasterSurface :: any).Backend}) -- alpha, gradients`
			.. ` and anti-aliased corners`)
		print(`  text   : {metricsOwner}`
			.. (if RasterPainter.OwnsText(rasterSurface :: any)
				then " -- glyphs rasterised in the scene, in paint order"
				else " -- drawn over the blit"))
	else
		--- `print`, not `warn`: zune has no `warn` global. Both uses of it in this
		--- host were on ERROR paths, so neither ever ran until one did -- and then
		--- the error handler was itself the error.
		print(`  WARNING: --raster requested but unavailable, falling back to GDI`)
		print(`  {why}`)
	end
elseif not gpuTarget then
	print(`  painter: GDI -- no alpha, no gradients. Pass --raster for the Rust backend.`)
end

--- `--frames N` exits after N frames instead of waiting to be closed. Without it
--- the only way to know the window loop runs is to watch it, which is not a
--- check -- and is not available in CI.
local frameLimit: number? = nil
for i, a in ipairs(ARGS) do
	if a == "--frames" then
		frameLimit = tonumber(ARGS[i + 1])
	end
end

--- ONE MILLISECOND SCHEDULER GRANULARITY.
---
--- Windows' default is ~15.6ms, so `task.wait(1/60)` -- 16.67ms -- actually
--- sleeps ~31ms and this loop ran at 32fps while believing it ran at 60.
--- Measured: wait(1/60) -> 31.06ms, wait(1/120) -> 15.57ms, wait(1/240) ->
--- 15.55ms. Without this, 64fps is the ceiling whatever the painter costs.
Win32.winmm.timeBeginPeriod(1)

--- The TARGET frame time. `--fps N` raises or lowers it; the default stays 60
--- because that is what the content is authored against.
local targetFps = 60
for i, a in ipairs(ARGS) do
	if a == "--fps" then
		targetFps = tonumber(ARGS[i + 1]) or 60
	end
end
local targetFrame = 1 / targetFps

--- MEASURED dt, not an assumed one.
---
--- The loop stepped a fixed 1/60 regardless of how long a frame actually took, so
--- when frames ran at 32fps every spring and carousel advanced at HALF SPEED --
--- correct-looking motion, running slow, with nothing to indicate it. Clamped
--- because a stall must not teleport the simulation.
local lastTick = os.clock()
local startedAt = lastTick
local frames = 0

--- `--account`: WHERE THE REAL FRAME GOES, measured in the loop that runs.
---
--- `--profile` measures each stage on a bench, and three times this milestone
--- that turned out to answer a different question than the one asked. It timed
--- `SnapshotDelta` 60 times with no step between, so the screen went idle after
--- the first call. It calls `Paint` in a loop, and `ar_begin` FLUSHES -- so each
--- iteration rasterises the previous scene and the number is record-plus-render
--- wearing the label "Paint". It times `Present` with no damage rect, so it
--- swizzles 3.7 MB the real loop never touches.
---
--- None of those are wrong as measurements. They are wrong as a model of the
--- frame, and the fix is not a better bench -- it is to stop extrapolating from
--- one. This accumulates the real loop's own phases and prints them beside the
--- fps, so the shares add up to the frame by construction.
local accounting = table.find(ARGS, "--account") ~= nil
--- POLLED ON AN INTERVAL, NOT PER FRAME, and the interval is a measurement.
---
--- `Reload.Changed()` stats every file the last load touched -- 10 for the shop
--- screen -- and costs 0.93 ms. That is 12% of a 7.7 ms frame, so per-frame
--- polling would spend more on watching for an edit than on drawing the result.
--- At 250 ms it is 0.93 ms every ~30 frames and disappears into the noise, while
--- still being far below the point a human notices a reload was not instant.
local RELOAD_POLL = 0.25
local lastReloadCheck = 0
local reloads = 0
local acct = { step = 0, delta = 0, paint = 0, render = 0, present = 0, blit = 0, pump = 0, wait = 0, poll = 0, rebuild = 0 }
local acctFrames = 0
local presentAcct = { swizzle = 0, upload = 0 }
if accounting then WindowsPresenter.Account = presentAcct end

while not closing and user32.IsWindow(hwnd) ~= 0 do
	local tPump = os.clock()
	while user32.PeekMessageA(msgBuf, Win32.null, 0, 0, 1) ~= 0 do
		user32.TranslateMessage(msgBuf)
		user32.DispatchMessageA(msgBuf)
	end
	if accounting then acct.pump += os.clock() - tPump end
	if closing then
		break
	end

	local now = os.clock()
	local dt = math.clamp(now - lastTick, 1 / 1000, 1 / 15)
	lastTick = now

	--- REBUILD THE TREE, KEEP EVERYTHING ELSE. The window, the surface, the
	--- painter and this loop all survive a reload; only the tree is thrown away
	--- and rebuilt. That is what makes it 27 ms instead of the 580-676 ms a
	--- process restart costs.
	---
	--- `app.Destroy()` is not optional. The old tree's effects, springs and
	--- router registrations outlive it otherwise, and twenty reloads later the
	--- frame is carrying twenty screens.
	--- A CLICK REBUILDS, through exactly the reload path. Handled here rather
	--- than in the click handler because that handler belongs to the tree the
	--- rebuild destroys.
	if pendingStory ~= nil and pendingStory ~= selectedStory then
		selectedStory = pendingStory
		pendingStory = nil
		app.Destroy()
		local ok, rebuilt = pcall(buildApp)
		if ok then
			app = rebuilt
			session = app.Session
			print(`  showing {selectedStory}`)
		else
			print(`  could not mount {selectedStory}:`)
			print(`    {tostring(rebuilt)}`)
		end
	end

	if useReload and (now - lastReloadCheck) >= RELOAD_POLL then
		lastReloadCheck = now
		local tPoll = os.clock()
		local dirty = Reload.Changed()
		if accounting then acct.poll += os.clock() - tPoll end
		if dirty then
			local t0 = os.clock()
			app.Destroy()
			local ok, rebuilt = pcall(buildApp)
			if ok then
				app = rebuilt
				session = app.Session
				reloads += 1
				--- NOT followed by `SnapshotDelta(true)`. A fresh session has no
				--- previous frame, so its first delta is already the whole
				--- screen -- consuming one here would leave the loop's own call
				--- reporting nothing changed, and the reload would paint on the
				--- frame AFTER the next input.
				local ms = (os.clock() - t0) * 1000
				if accounting then acct.rebuild += ms / 1000 end
				print(string.format("  reload #%d in %.1f ms", reloads, ms))
			else
				--- A SYNTAX ERROR MUST NOT KILL THE WINDOW. Editing is how this
				--- mode is used, and a half-typed file is the normal state of a
				--- file being edited. The old tree is already destroyed, so the
				--- screen is blank until the next good save -- honest, and
				--- recoverable, which a crashed process is not.
				print("  reload FAILED, waiting for the next save:")
				print(`    {tostring(rebuilt)}`)
			end
		end
	end

	local tStep = os.clock()
	if app then
		app.StepMotion(dt)
		session.Step(dt)
	end
	if accounting then acct.step += os.clock() - tStep end

	--- DAMAGE-DRIVEN REPAINT (ms-52 M4).
	---
	--- GDI is immediate-mode: it has no retained scene, so "only send what
	--- changed" saves nothing here by itself -- the painter still has to redraw.
	--- What the delta gives an immediate-mode display is the DIRTY RECTANGLE, and
	--- with it two savings: a frame where nothing moved is not painted at all,
	--- and a frame where something did is blitted back one region instead of a
	--- whole screen.
	---
	--- The full frame is still painted into the memory DC when anything changed.
	--- Clipping the PAINT as well is possible and deliberately not done yet: it
	--- needs every node intersecting the dirty rect redrawn in order, and getting
	--- that subtly wrong leaves stale pixels that look like a framework bug.
	--- Painting is 6.43ms of a 10ms frame, so that is where the next win is.
	local tDelta = os.clock()
	local delta = session.SnapshotDelta()
	if accounting then acct.delta += os.clock() - tDelta end
	--- THE GPU PATH DRAWS WHOLE FRAMES, and the damage rect has no role in it.
	---
	--- Swapchain buffers ROTATE: the texture handed back this frame is not the one
	--- presented last frame, so "everything outside the damage rect is still
	--- correct" -- the assumption the entire clipped-repaint path rests on -- is
	--- false here. Repairing a region would leave the rest of a RECYCLED buffer on
	--- screen, which reads as the UI flickering between two old frames.
	---
	--- The delta still decides WHETHER to draw, so an idle screen costs a present
	--- and no work. That much survives; only the clipping does not.
	--- `delta.Frame`, NOT another `Snapshot()`. Computing the delta already built
	--- the display list; asking again rebuilt all 185 node tables for a result
	--- identical by construction.
	if gpuTarget then
		if #delta.Changed > 0 or #delta.Removed > 0 then
			WindowedPainter.Paint(gpuTarget, delta.Frame)
			WindowedPainter.Present(gpuTarget)
		end
	elseif #delta.Changed > 0 or #delta.Removed > 0 then
		local d = delta.Dirty
		--- THE PAINT IS CLIPPED TOO, not just the blit.
		---
		--- This used to repaint every node and merely blit the damaged rectangle,
		--- which saved the copy and none of the drawing. That is backwards for
		--- these screens: they stack large translucent panels, so the cost is FILL
		--- RATE -- a full-window rounded rect is ~920k pixels of alpha blending on
		--- a CPU, and several overlap. Clipping the paint shrinks all of them at
		--- once, which no amount of per-node caching can do.
		---
		--- The backdrop is the exception: it is painted edge to edge and has no
		--- node behind it to repair a partial repaint, so a backdrop frame paints
		--- whole.
		local damage = if useBackdrop then nil else d
		if rasterSurface then
			--- SHAPES IN RUST, TEXT IN GDI, in that order. The blit covers the
			--- painted region, so text drawn before it would be erased.
			local snap = delta.Frame
			local tPaint = os.clock()
			RasterPainter.Paint(rasterSurface, snap, useBackdrop, damage)
			local tPresent = os.clock()
			--- PRESENT IS TWO THINGS, AND THEY SPLIT WITHOUT A NEW ABI.
			---
			--- vello RECORDS; the pixels appear when something reads them, which
			--- for this path is `ar_bgra` inside Present. So "Present" is
			--- rasterisation AND the BGRA swizzle AND the blit, three costs with
			--- three different fixes, reported as one.
			---
			--- `ar_pixel` already forces the render -- it has to, or the parity
			--- instrument reads an untouched pixmap -- so reading ONE PIXEL
			--- rasterises the scene and nothing else. Present then finds it
			--- rendered and does only the swizzle and the blit. The extra work is
			--- one pixel read, and this runs under `--account` alone.
			local tSwizzle = tPresent
			if accounting then
				RasterPainter.Pixel(rasterSurface, 0, 0)
				tSwizzle = os.clock()
				acct.render += tSwizzle - tPresent
			end
			WindowsPresenter.Present(RasterPainter, rasterSurface, memDC, damage)
			if accounting then
				acct.paint += tPresent - tPaint
				acct.present += os.clock() - tSwizzle
			end
			--- ONLY WHEN THE BACKEND DOES NOT OWN ITS TEXT. vello draws glyphs
			--- inside the scene, in paint order; drawing them again with GDI would
			--- double every label and put the copy above nodes meant to cover it.
			if not RasterPainter.OwnsText(rasterSurface) then
				NativePainter.PaintTextOnly(memDC, snap, damage)
			end
		else
			NativePainter.Paint(memDC, delta.Frame, nil, damage)
		end
		if d then
			--- Blit only the region that moved, padded to MATCH THE PAINT.
			---
			--- The pad was 1 here and 2 in the painter, which repaints a ring the
			--- blit then does not copy -- a one-pixel band of stale window pixels
			--- around everything that moves. Harmless-looking and exactly the kind
			--- of artefact that reads as a framework bug, so the two paddings are
			--- the same constant now.
			local PAD = 2
			local bx = math.max(0, math.floor(d[1]) - PAD)
			local by = math.max(0, math.floor(d[2]) - PAD)
			local bw = math.min(WIDTH - bx, math.ceil(d[3]) + PAD * 2 + 1)
			local bh = math.min(HEIGHT - by, math.ceil(d[4]) + PAD * 2 + 1)
			local tBlit = os.clock()
			gdi.BitBlt(hdc, bx, by, bw, bh, memDC, bx, by, Win32.SRCCOPY)
			if accounting then acct.blit += os.clock() - tBlit end
		else
			local tBlit = os.clock()
			gdi.BitBlt(hdc, 0, 0, WIDTH, HEIGHT, memDC, 0, 0, Win32.SRCCOPY)
			if accounting then acct.blit += os.clock() - tBlit end
		end
		if accounting then acctFrames += 1 end
	end

	frames += 1
	if frameLimit and frames >= frameLimit then
		break
	end

	--- Sleep the REMAINDER, not a fixed interval: a frame that took 12ms should
	--- wait 4, not 16. Sleeping a constant made the real rate the sum of the work
	--- and the wait rather than the target.
	local spent = os.clock() - now
	local remaining = targetFrame - spent
	if remaining > 0 then
		local tWait = os.clock()
		task.wait(remaining)
		if accounting then acct.wait += os.clock() - tWait end
	else
		--- Behind schedule. Yield so messages are still pumped rather than
		--- starving input to catch up on painting.
		task.wait(0)
	end
end

gdi.DeleteObject(bmp)
user32.ReleaseDC(hwnd, hdc)
user32.DestroyWindow(hwnd)
Win32.winmm.timeEndPeriod(1)
local st = session.Stats()
local elapsed = os.clock() - startedAt
--- `Sent`/`Skipped` BELONG TO THE CURRENT SESSION, and a reload builds a new one.
---
--- So after a reload these count frames since the LAST reload, not since launch,
--- and `Sent + Skipped` stops equalling the frame count. Said out loud rather
--- than silently reported, because "1000 frames, 407 painted, 0 skipped" reads
--- like 593 frames went missing.
print(`closed after {frames} frames in {string.format("%.1f", elapsed)}s `
	.. `({string.format("%.0f", frames / math.max(elapsed, 0.001))} fps) -- `
	.. `{st.Sent} painted, {st.Skipped} skipped`
	.. (if reloads > 0
		then ` (since reload #{reloads}; each reload starts a new session's counters)`
		else ""))

if accounting then
	--- PER PAINTED FRAME for the painting phases, per LOOP frame for the rest.
	--- Dividing a phase that only runs when something changed by every frame of
	--- the run would report a screen that idled half the time as half as
	--- expensive to paint, which is how `settings` -- 599 of 600 frames skipped --
	--- would look almost free while saying nothing about the frames it did paint.
	local painted = math.max(acctFrames, 1)
	local loop = math.max(frames, 1)
	print(``)
	print(`  ACCOUNTING -- {acctFrames} painted of {frames} loop frames`)
	local function row(label: string, total: number, over: number, note: string?)
		print(string.format("  %-26s %7.3f ms  %s", label, total / over * 1000, note or ""))
	end
	row("message pump", acct.pump, loop)
	--- SPREAD OVER EVERY LOOP FRAME, not over the polls, because the question the
	--- interval was chosen to answer is what watching costs the frame -- and the
	--- rebuild is amortised the same way, since a reload every few seconds that
	--- costs 30 ms is a different thing from one that costs 30 ms every frame.
	if useReload then
		row("reload poll (stat the set)", acct.poll, loop)
		row("reload rebuild", acct.rebuild, loop, `{reloads} reload(s)`)
	end
	row("Step (motion + layout)", acct.step, loop)
	row("SnapshotDelta", acct.delta, loop)
	--- A MEAN OF ONE FRAME IS THE WARM-UP, NOT THE STEADY STATE.
	---
	--- `settings` paints once and then idles -- 1 of 900 frames -- and that one
	--- frame is cold: every glyph unrasterised, every cache empty. Divided by a
	--- painted count of 1 it reported 24 ms for a rasterise that costs 1.4, which
	--- is not a slow screen but an instrument describing a warm-up as a rate.
	---
	--- Suppressed rather than printed with a caveat, because a number on the page
	--- gets quoted and the caveat does not.
	if acctFrames >= 30 then
		row("Paint (record the scene)", acct.paint, painted, "per painted frame")
		row("rasterise (vello_render)", acct.render, painted, "per painted frame")
		row("  swizzle to BGRA", presentAcct.swizzle, painted, "per painted frame")
		row("  SetDIBitsToDevice", presentAcct.upload, painted, "per painted frame")
		row("BitBlt to window", acct.blit, painted, "per painted frame")
	else
		print(`  painting                   {acctFrames} frame(s) -- too few to average;`)
		print(`                             this screen idles, so the paint phases`)
		print(`                             would report the cold first frame as a rate`)
	end
	local work = acct.pump + acct.step + acct.delta + acct.paint + acct.render + acct.present + acct.blit
		+ acct.poll + acct.rebuild
	row("-> accounted", work, loop)
	print(string.format("  %-26s %7.3f ms  %s", "-> frame, measured",
		elapsed / loop * 1000, `of which {string.format("%.3f", acct.wait / loop * 1000)} ms slept`))
end
