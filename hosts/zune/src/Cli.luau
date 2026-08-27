--!strict
--[[
	aether-cli — render stories to PNG, headless, on any platform (ms-53 P2).

	    zune run pkgs/ui/hosts/zune/src/Cli.luau snapshot --out .artifacts/shots
	    zune run pkgs/ui/hosts/zune/src/Cli.luau snapshot --story "Kits/ShopUI/ShopMenu:Default"
	    zune run pkgs/ui/hosts/zune/src/Cli.luau list

	WHAT MAKES THIS DIFFERENT FROM `Native.luau`

	No window, no message pump, no DC -- and, structurally, NO `Win32`. That is
	the whole point and it is an invariant rather than a happy accident:
	`verify_headless_is_portable` walks this file's require graph and fails if
	`Win32` or `WindowsPresenter` appears anywhere in it.

	The rasteriser was five Win32 references away from portable and only two were
	real, both inside `Present`. They live in `WindowsPresenter.luau` now. The Rust
	crate has no platform `cfg` outside optional features and `vello_cpu` is pure
	Rust, so a Linux container needs the `.so` and nothing else.

	WHY IT MATTERS: every CI and cloud claim in the ms-53 roadmap runs through
	here. A snapshot pipeline that only works on the maintainer's Windows box is
	not a pipeline.

	DETERMINISM IS A PRODUCT CONSTRAINT, NOT A DETAIL. ms-52 measured that this
	renderer is not bit-stable across backends -- 76% between its own two vello
	paths -- and that one upstream flag moved 1% of the glyph pixels. So this pins
	`vello_cpu` and refuses `--gpu` outright: a snapshot set that silently changes
	backend is a baseline that cries wolf on its first `cargo update`.
]]

local Checks = require("../../../src/host/Checks")
local Stories = require("./Stories")
local RasterPainter = require("./RasterPainter")
local App = require("../../web/src/App")

local z = (zune :: any)
local fs = z.fs
local ARGS: { string } = z.process.args

local function flag(name: string): string?
	for i, a in ipairs(ARGS) do
		if a == name then
			return ARGS[i + 1]
		end
	end
	return nil
end

local function has(name: string): boolean
	return table.find(ARGS, name) ~= nil
end

--- THE VERB IS THE FIRST NON-FLAG AFTER THE SCRIPT.
---
--- `zune.process.args[1]` is the SCRIPT PATH, not the first argument -- so
--- `ARGS[1]` is never the verb and the usage text prints for every valid
--- command. Searched for rather than indexed, so a future `zune` that stops
--- including the script path does not break this again.
local verb: string? = nil
for i, a in ipairs(ARGS) do
	if i > 1 and string.sub(a, 1, 2) ~= "--" and not string.match(a, "%.luau$") then
		verb = a
		break
	end
end

--- A story id as a filename, and it has to be reversible enough to read.
---
--- Ids carry `/` and `:` and spaces -- "Kits/ShopUI/ShopMenu:Default" -- none of
--- which belong in a filename, and two of which are path separators on one
--- platform or the other. Replaced rather than stripped, so two different stories
--- cannot collapse onto one file and silently overwrite each other's snapshot.
local function fileNameFor(id: string): string
	local name = string.gsub(id, "[/\\:]", "__")
	name = string.gsub(name, "%s+", "_")
	return name .. ".png"
end

if verb == "list" or has("--list") then
	local all = Stories.Discover("pkgs/ui")
	for _, st in ipairs(all) do
		print(st.Id)
	end
	print(`{#all} story/stories in {#Stories.Files(all)} file(s)`)
	return
end

--- `check` -- assert PROPERTIES of the frame, with no baseline.
---
--- The differentiated half of this tool. Pixel diffing needs a baseline that is
--- per-backend, per-upstream-version AND per-platform (ms-52, and P2's font
--- finding); these need none of that, because "this label is wider than its box"
--- is true regardless of which rasteriser drew it. See `host/Checks.luau` for
--- what is deliberately NOT checked and the numbers behind that.
if verb == "check" then
	local expand = tonumber(flag("--expand") or "") or 1
	local minContrast = tonumber(flag("--min-contrast") or "") or 4.5
	local only = flag("--story")

	assert(RasterPainter.LoadFont() ~= nil, "no font could be loaded; every string would measure zero")
	local Aether = require("../../../src")
	local host = Aether.Host.detect()

	local all = Stories.Discover("pkgs/ui")
	local skipped = 0
	if only ~= nil then
		local one = Stories.Find(all, only)
		assert(one ~= nil, `no story matches "{only}"`)
		--- NAMED EXPLICITLY, so a fixture can still be checked on purpose -- which
		--- is exactly what `verify_frame_checks` does to prove each rule bites.
		all = { one :: any }
	else
		--- FIXTURES ARE SKIPPED on a normal run. They exist to break a rule, so
		--- including them makes `check` red forever, and a command that is always
		--- red is one nobody reads.
		local kept: { any } = {}
		for _, st in ipairs(all) do
			if st.Fixture then
				skipped += 1
			else
				table.insert(kept, st)
			end
		end
		all = kept
	end

	local total, judged, textTotal = 0, 0, 0
	for _, st in ipairs(all) do
		local ok, result = pcall(function()
			local a = App.create({ Story = st.Build, Metrics = RasterPainter.Metrics, Width = 1280, Height = 720 })
			local frame = a.Session.SnapshotDelta(true).Frame
			--- MEASURED THROUGH THE HOST, which is the same path layout used. A
			--- second measurement source would compare a box laid out with one
			--- font against text measured with another -- the ms-52 M7 drift,
			--- restated as a false positive.
			local findings, coverage = Checks.Run(frame, host.Text.Measure, {
				Expand = expand,
				MinContrast = minContrast,
				Allow = st.Allow,
			})
			a.Destroy()
			return { findings = findings, coverage = coverage }
		end)
		if not ok then
			print(string.format("  ERROR %-44s %s", st.Id, tostring(result)))
			total += 1
		else
			local r = result :: any
			textTotal += r.coverage.Text
			judged += r.coverage.ContrastJudged
			if #r.findings > 0 then
				print(`  {st.Id}`)
				for _, f in ipairs(r.findings) do
					print(string.format("    %-9s %-22s %s", f.Check, string.sub(f.Text or f.Node, 1, 22), f.Detail))
				end
				total += #r.findings
			end
		end
	end

	--- COVERAGE, PRINTED EVERY RUN. `contrast` can only judge a node whose
	--- background it can resolve; on shop that is under half of them. A checker
	--- that skips half its subjects and reports "no problems" is the vacuous gate
	--- this repo keeps finding, so the gap is stated rather than implied.
	print(string.format("%d finding(s) across %d story/stories -- %d text node(s), %d judged for contrast",
		total, #all, textTotal, judged))
	if skipped > 0 then
		print(`({skipped} fixture(s) skipped -- stories that break a rule on purpose; name one with --story to check it)`)
	end
	if expand ~= 1 then
		print(`(strings measured at {expand}x, the localisation stress test)`)
	end
	if total > 0 then
		z.process.exit(1)
	end
	return
end

if verb ~= "snapshot" then
	print("usage:")
	print("  zune run pkgs/ui/hosts/zune/src/Cli.luau list")
	print("  zune run pkgs/ui/hosts/zune/src/Cli.luau snapshot [--out DIR] [--story ID]")
	print("  zune run pkgs/ui/hosts/zune/src/Cli.luau check [--expand 1.5] [--min-contrast 4.5] [--story ID]")
	z.process.exit(if verb == nil then 1 else 2)
	return
end

--- REFUSED, NOT IGNORED. A flag that is silently dropped is worse than one that
--- errors: the run succeeds, the snapshots are produced by a different backend
--- than the baseline, and the diff blames the component.
assert(not has("--gpu"), "--gpu is refused: CI snapshots pin vello_cpu, the deterministic backend (see the header)")

local outDir = flag("--out") or ".artifacts/snapshots"
local only = flag("--story")

local ok, why = RasterPainter.Available()
assert(ok, `the Rust backend is required for snapshots: {tostring(why)}`)
assert(RasterPainter.LoadFont() ~= nil, "no font could be loaded; text would render as nothing")

local all = Stories.Discover("pkgs/ui")
assert(#all > 0, "no stories were discovered")
if only ~= nil then
	local one = Stories.Find(all, only)
	assert(one ~= nil, `no story matches "{only}"`)
	all = { one :: any }
end

--- Created, not assumed. `writeFile` into a missing directory fails per file, so
--- the run would report every story as broken and none of them would be.
pcall(fs.makeDir, outDir)

local W, H = 1280, 720
local surface = RasterPainter.NewSurface(W, H, RasterPainter.VELLO_CPU) :: any
assert(surface ~= nil, "could not create a surface")

local started = os.clock()
local failures = 0
for _, st in ipairs(all) do
	local built, err = pcall(function()
		local a = App.create({
			Story = st.Build,
			Metrics = RasterPainter.Metrics,
			Width = W,
			Height = H,
		})
		local frame = a.Session.SnapshotDelta(true).Frame
		RasterPainter.Paint(surface, frame)
		local path = `{outDir}/{fileNameFor(st.Id)}`
		local wrote = RasterPainter.WritePNG(surface, path)
		a.Destroy()
		assert(wrote == nil, tostring(wrote))
		--- ASSERTED, not trusted. `save` reporting success and producing a
		--- zero-byte file is a real failure mode of a wrong buffer length, and a
		--- CI job that ships empty PNGs is worse than one that fails.
		local meta = fs.metadata(path)
		assert(meta and meta.size > 0, `{path} was written but is empty`)
		return { nodes = #frame.Nodes, bytes = meta.size }
	end)
	if not built then
		failures += 1
		print(string.format("  FAIL  %-46s %s", st.Id, tostring(err)))
	else
		local r = err :: any
		print(string.format("  ok    %-46s %3d nodes  %6d bytes", st.Id, r.nodes, r.bytes))
	end
end

local seconds = os.clock() - started
RasterPainter.FreeSurface(surface)
print(string.format("%d snapshot(s) to %s in %.2fs (%.0f ms each)",
	#all - failures, outDir, seconds, seconds / math.max(#all, 1) * 1000))
if failures > 0 then
	print(`{failures} of {#all} failed`)
	z.process.exit(1)
end
