--!strict
--[[
	Aether · host/Live — a RUNNING host that is not Roblox.

	WHY (ms-51 M22)
	The SVG host proved the seam and nothing more: it draws one frame, once, from a
	tree that never changes. es9: "we need to find an actual suitable host to mount
	other things like interactivity and motion in a luau runtime, the same way
	roblox does."

	The phrase "the same way roblox does" is the design. Roblox splits a UI into
	two halves:

	    ENGINE (C++)              renders Instances, reports input, drives Heartbeat
	    APPLICATION (Luau)        holds every decision

	Nothing in the first half is interesting, and everything in the second is. This
	host reproduces exactly that split with a BROWSER standing in for the engine:
	it paints rectangles it is told to paint and reports pointer events it did not
	interpret. Layout, arbitration, hover, press and motion all stay in Luau —
	which is the claim being tested, because if any of them had quietly stayed in
	Roblox they would be missing here.

	    Luau (Lune)                                   Browser
	    ─────────────────────────                     ────────────────────
	    Aether tree via Host.create
	      -> Layout.Solve                    frame -> paints rectangles
	      -> Clock.Step drives Flux springs
	      <- PointerRouter.Input             input <- reports x/y and buttons

	WHAT THIS PROVES THAT THE SVG HOST COULD NOT: that motion runs (a spring needs
	a clock and successive frames), and that arbitration runs (hover and press need
	a pointer that moves). Both were already portable in principle; neither had
	ever been DEMONSTRATED outside the engine.

	WHAT IT IS NOT: a production renderer. There is no text measurement, no
	gradients or images, and the transport is one JSON frame per tick with no
	diffing. It is an instrument, and its honesty matters more than its throughput.
]]

local Layout = require("./Layout")
--- The focused-field authority. Required directly rather than injected: there is
--- exactly one per process, the same way there is one PointerRouter.
local TextInputManager = require("../TextInputManager")

local Live = {}

export type Frame = {
	Width: number,
	Height: number,
	Nodes: { any },
	--- Is a text field focused? The display needs this to decide whether to
	--- swallow a keystroke's browser default -- it cannot wait to be told whether
	--- Luau consumed the key, because that answer is a round trip away and by
	--- then the page has already scrolled on Space or navigated on Backspace.
	Focused: boolean,
}

--- STABLE IDS, so a display can key a node across frames (ms-52 M4).
---
--- The frame is an ARRAY, so before this a node's only identity was its index --
--- which shifts the moment anything is added or removed, making every node after
--- it look changed. Keyed by the node itself, weakly, so a discarded subtree does
--- not pin its ids forever.
local NODE_IDS: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
local nextNodeId = 0

local function idOf(node: any): number
	local existing = NODE_IDS[node]
	if existing then
		return existing
	end
	nextNodeId += 1
	NODE_IDS[node] = nextNodeId
	return nextNodeId
end

--- Serialise one solved frame into the flattest thing a display can consume.
---
--- Deliberately NOT the node tree: the display should not be able to make layout
--- decisions, because then layout would live half in Luau and half in the host
--- and this would stop being a test of anything. It receives rectangles in paint
--- order and paints them.
function Live.Snapshot(host: any, root: any, width: number, height: number): Frame
	--- `host` is passed so AutomaticSize resolves (ms-52 M1).
	local solved = Layout.Solve(host.Scene, root, { X = 0, Y = 0, Width = width, Height = height }, host)
	return Live.SnapshotSolved(host, solved, width, height)
end

--- Serialise an ALREADY-SOLVED frame. Split out so a session can solve once and
--- both arbitrate and paint against the same answer.
--- Find a modifier child by class. `FindFirstChildOfClass` is part of both hosts'
--- instance surface, which is why `RenderedCorner` already uses it.
local function modifierOf(Scene: any, node: any, class: string): any
	local find = (node :: any).FindFirstChildOfClass
	if type(find) ~= "function" then
		return nil
	end
	local ok, found = pcall(find, node, class)
	return if ok then found else nil
end

local function rgb(c: any): { number }?
	if c == nil then
		return nil
	end
	return {
		math.floor((c.R or 0) * 255 + 0.5),
		math.floor((c.G or 0) * 255 + 0.5),
		math.floor((c.B or 0) * 255 + 0.5),
	}
end

--- A ColorSequence as ordered stops. Roblox exposes `Keypoints`; a host that
--- lacks the type answers nil and the display simply draws the flat fill, which
--- is the pre-M2 behaviour rather than a wrong guess.
---
--- A COLOUR ramp only. A UIGradient may instead carry just a `Transparency`
--- NumberSequence -- MenuWindow's does, for the fade down a window body -- and
--- that is an ALPHA ramp with no colour to interpolate. Those return nil here and
--- the node draws its flat fill, which is honest: 1 of ShopUI's 2 gradients is
--- expressed, and the missing one is a named limitation rather than a silent
--- approximation. Recorded in inventory.md.
local function gradientStops(g: any): { any }?
	local seq = (g :: any).Color
	if seq == nil then
		return nil
	end
	local kps = (seq :: any).Keypoints
	if type(kps) ~= "table" then
		return nil
	end
	local out = {}
	for _, kp in ipairs(kps) do
		local c = rgb((kp :: any).Value)
		if c then
			table.insert(out, { t = (kp :: any).Time or 0, c = c })
		end
	end
	return if #out > 0 then out else nil
end

--- A NumberSequence of TRANSPARENCY as alpha stops (1 - transparency), ordered.
--- Same nil-rather-than-guess rule as the colour ramp: a host without the type
--- answers nil and the node draws its flat fill.
local function alphaRamp(g: any): { any }?
	local seq = (g :: any).Transparency
	if seq == nil then
		return nil
	end
	local kps = (seq :: any).Keypoints
	if type(kps) ~= "table" then
		return nil
	end
	local out = {}
	local varies = false
	local first: number? = nil
	for _, kp in ipairs(kps) do
		local v = (kp :: any).Value
		if type(v) == "number" then
			if first == nil then
				first = v
			elseif math.abs(v - first) > 0.001 then
				varies = true
			end
			table.insert(out, { t = (kp :: any).Time or 0, a = 1 - v })
		end
	end
	--- A CONSTANT ramp is not a gradient -- it is just this node's transparency,
	--- which the `alpha` field already carries. Emitting it would make every
	--- uniformly-transparent element claim a gradient it does not have.
	if not varies or #out < 2 then
		return nil
	end
	return out
end

--- ALIGNMENT, RESOLVED ONCE PER DISTINCT VALUE RATHER THAN ONCE PER NODE.
---
--- `tostring` plus up to four `string.find` ran twice for every text node --- 164
--- times a frame on shop --- to answer a question with five possible answers. The
--- memo is keyed on the property VALUE, which is an enum singleton on both hosts,
--- so it is bounded by the number of alignments that exist; weak keys keep that
--- true even for a host that answers with a fresh table.
---
--- Kept as a free function taking `node` rather than a closure over it: as a
--- closure it was allocated once per node, and three per-node closures (this, the
--- stroke reader and the gradient reader) were 0.11 ms of a 0.84 ms pass.
local ALIGN_NAMES: { [any]: string } = setmetatable({}, { __mode = "k" }) :: any

local function alignOf(Scene: any, node: any, prop: string, fallback: string): string
	local value = Scene.Raw(node, prop)
	if value == nil then
		return fallback
	end
	local cached = ALIGN_NAMES[value]
	if cached ~= nil then
		return cached
	end
	local name = tostring(value)
	local resolved = "center"
	if string.find(name, "Right", 1, true) then
		resolved = "right"
	elseif string.find(name, "Bottom", 1, true) then
		resolved = "bottom"
	elseif string.find(name, "Left", 1, true) then
		resolved = "left"
	elseif string.find(name, "Top", 1, true) then
		resolved = "top"
	end
	ALIGN_NAMES[value] = resolved
	return resolved
end

--- STROKES AND GRADIENTS (ms-52 M2).
---
--- These are what make a card read as a card: ShopUI carries 17 UIStroke and 2
--- UIGradient, and without them a panel whose fill is nearly transparent is drawn
--- as very nearly nothing --- which is a large part of why a fully-present screen
--- looked half-missing.
---
--- Emitted as nil when absent rather than as a default, so "nothing set a stroke"
--- stays distinguishable from "a stroke of zero", the same rule the fill follows.
local function strokeOf(Scene: any, node: any): any
	local st = modifierOf(Scene, node, "UIStroke")
	if not st or Scene.Raw(st, "Enabled") == false then
		return nil
	end
	local thickness = (st :: any).Thickness or 1
	local transparency = (st :: any).Transparency or 0
	if thickness <= 0 or transparency >= 1 then
		return nil
	end
	return {
		colour = rgb((st :: any).Color),
		thickness = thickness,
		alpha = 1 - transparency,
	}
end

local function gradientOf(Scene: any, node: any): any
	local g = modifierOf(Scene, node, "UIGradient")
	if not g or Scene.Raw(g, "Enabled") == false then
		return nil
	end
	local stops = gradientStops(g)
	--- An ALPHA ramp is a gradient too (ms-52 M2).
	---
	--- A UIGradient may carry only a `Transparency` NumberSequence and no Color ---
	--- MenuWindow's does, for the fade down a window body. That was emitted as
	--- nil, so 1 of ShopUI's 2 gradients was expressed and the window read flat.
	---
	--- It is still a gradient; the thing being interpolated is the node's OWN fill
	--- at varying alpha rather than a colour ramp, so the display needs the stops
	--- and nothing else changes.
	local alphaStops = alphaRamp(g)
	if not stops and not alphaStops then
		return nil
	end
	return {
		stops = stops,
		alphaStops = alphaStops,
		rotation = (g :: any).Rotation or 0,
	}
end

--- BUILD ONE DISPLAY NODE. Every allocation in the snapshot happens here: the
--- node table, and one sub-table each for fill, textColour and clip.
local function buildNode(Scene: any, item: Solved): any
	local node, rect = item.Node, item.Rect
	local fill = Scene.Raw(node, "BackgroundColor3")
	local scale, offset = Scene.RenderedCorner(node)
	local text = Scene.Raw(node, "Text")
	local textColour = Scene.Raw(node, "TextColor3")
	local hasText = type(text) == "string" and text ~= ""
	--- TEXT ALIGNMENT, WITH ROBLOX'S DEFAULTS (ms-52 M12).
	---
	--- The frame carried no alignment at all, so every painter invented the same
	--- left inset -- `n.x + 10` in the GDI, vello and browser painters alike --
	--- and es9 saw it as "none of our external renderers centre the icons".
	---
	--- THE DEFAULT IS THE HALF THAT MATTERS. Of shop's 84 text nodes, 38 set
	--- `Left` explicitly and 46 set NOTHING -- and an unset `TextXAlignment` is
	--- CENTRE in Roblox, not left. So reading the property alone would still have
	--- left-aligned 46 nodes that the engine centres; the default has to be
	--- supplied here, once, rather than guessed at by three painters.
	return {
		--- A stable identity across frames, so a display can patch this node
		--- rather than rebuild the screen (ms-52 M4).
		id = idOf(node),
		name = Scene.Name(node) or Scene.ClassOf(node) or "?",
		x = rect.X,
		y = rect.Y,
		w = rect.Width,
		h = rect.Height,
		--- nil rather than a default: "nothing set a colour" is a finding, and a
		--- default would erase it.
		fill = rgb(fill),
		alpha = 1 - (Scene.Raw(node, "BackgroundTransparency") or 0),
		radius = (scale or 0) * math.min(rect.Width, rect.Height) + (offset or 0),
		clip = if item.Clip
			then { item.Clip.X, item.Clip.Y, item.Clip.Width, item.Clip.Height }
			else nil,
		stroke = strokeOf(Scene, node),
		gradient = gradientOf(Scene, node),
		text = if hasText then text else nil,
		textSize = Scene.Raw(node, "TextSize") or 14,
		--- Emitted only for nodes that HAVE text, so an idle frame does not grow
		--- two fields per node for nothing.
		textAlignX = if hasText then alignOf(Scene, node, "TextXAlignment", "center") else nil,
		textAlignY = if hasText then alignOf(Scene, node, "TextYAlignment", "center") else nil,
		textColour = rgb(textColour),
	}
end

function Live.SnapshotSolved(host: any, solved: { Solved }, width: number, height: number): Frame
	local Scene = host.Scene

	local nodes = {}
	local count = 0
	for _, item in ipairs(solved) do
		if item.Rect.Width > 0 and item.Rect.Height > 0 then
			count += 1
			nodes[count] = buildNode(Scene, item)
		end
	end

	return {
		Width = width,
		Height = height,
		Nodes = nodes,
		Focused = TextInputManager.GetActiveField() ~= nil,
	}
end

--- IS THIS NODE STILL WHAT IT WAS, BY VALUE? (ms-52 M4, rewritten M15.3)
---
--- BY VALUE, and the plan flagged why before the sprint started: the host
--- rebuilds property values through effects, so an unchanged node is frequently a
--- NEW TABLE each frame. An identity comparison would report every node as
--- changed every frame and the diff would be a no-op wearing a diff's clothes --
--- passing its own tests while sending everything.
---
--- AGAINST THE SOURCE, NOT AGAINST A BUILT TABLE. The original compared last
--- frame's node to this frame's node, which meant building this frame's node
--- first -- so an unchanged node cost a table and four sub-tables to discover it
--- had not changed. These read the scene directly and allocate nothing, so a node
--- that survives the comparison is REUSED whole and the frame never allocates for
--- it at all.
---
--- THE ORDER IS THE OPTIMISATION. `item.Rect` needs no scene call and is the
--- field most likely to differ -- on shop, 128 of 185 painted rects move every
--- frame -- so a moved node bails after four number comparisons and falls
--- straight through to `buildNode`. The expensive reads are last.
---
--- Only the fields a display actually consumes are compared. Anything not
--- compared is, by definition, something no display can render, and adding a
--- field to `buildNode` without adding it here would make that field NEVER
--- UPDATE -- the failure is silent, which is why `testDeltaTracksEveryField`
--- mutates each one in turn and asserts the delta notices.
local function sameColour(a: { number }?, b: { number }?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

--- Compare a built triple against a RAW Color3 without building a second one.
local function sameColourSource(a: { number }?, c: any): boolean
	if c == nil then
		return a == nil
	end
	if a == nil then
		return false
	end
	return a[1] == math.floor((c.R or 0) * 255 + 0.5)
		and a[2] == math.floor((c.G or 0) * 255 + 0.5)
		and a[3] == math.floor((c.B or 0) * 255 + 0.5)
end

local function sameStroke(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a.thickness == b.thickness and a.alpha == b.alpha and sameColour(a.colour, b.colour)
end

local function sameGradient(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == b
	end
	if a.rotation ~= b.rotation then
		return false
	end
	local as, bs = a.stops or a.alphaStops, b.stops or b.alphaStops
	if as == nil or bs == nil then
		return as == bs
	end
	if #as ~= #bs then
		return false
	end
	for i = 1, #as do
		if as[i].t ~= bs[i].t or as[i].a ~= bs[i].a or not sameColour(as[i].c, bs[i].c) then
			return false
		end
	end
	return true
end

local function unchanged(Scene: any, item: Solved, was: any): boolean
	local rect = item.Rect
	if was.x ~= rect.X or was.y ~= rect.Y or was.w ~= rect.Width or was.h ~= rect.Height then
		return false
	end

	local clip = item.Clip
	local wasClip = was.clip
	if clip == nil then
		if wasClip ~= nil then
			return false
		end
	elseif wasClip == nil
		or wasClip[1] ~= clip.X
		or wasClip[2] ~= clip.Y
		or wasClip[3] ~= clip.Width
		or wasClip[4] ~= clip.Height
	then
		return false
	end

	local node = item.Node
	local text = Scene.Raw(node, "Text")
	local hasText = type(text) == "string" and text ~= ""
	if was.text ~= (if hasText then text else nil) then
		return false
	end
	if was.alpha ~= 1 - (Scene.Raw(node, "BackgroundTransparency") or 0) then
		return false
	end
	if was.textSize ~= (Scene.Raw(node, "TextSize") or 14) then
		return false
	end
	if was.name ~= (Scene.Name(node) or Scene.ClassOf(node) or "?") then
		return false
	end
	if not sameColourSource(was.fill, Scene.Raw(node, "BackgroundColor3")) then
		return false
	end
	if not sameColourSource(was.textColour, Scene.Raw(node, "TextColor3")) then
		return false
	end

	local scale, offset = Scene.RenderedCorner(node)
	if was.radius ~= (scale or 0) * math.min(rect.Width, rect.Height) + (offset or 0) then
		return false
	end

	if hasText then
		if was.textAlignX ~= alignOf(Scene, node, "TextXAlignment", "center")
			or was.textAlignY ~= alignOf(Scene, node, "TextYAlignment", "center")
		then
			return false
		end
	elseif was.textAlignX ~= nil or was.textAlignY ~= nil then
		return false
	end

	--- Strokes and gradients go through the SAME readers `buildNode` uses, so
	--- there is one definition of what a stroke is rather than two that can
	--- drift. They allocate -- but only for a node that HAS one (17 and 2 of
	--- shop's 185), and only after every cheaper field has already matched.
	return sameStroke(was.stroke, strokeOf(Scene, node))
		and sameGradient(was.gradient, gradientOf(Scene, node))
end

--- What changed between two frames.
---
--- `Order` is sent only when the paint order itself changed: it is a list of
--- integers and cheap, but sending it every frame would mean an idle screen still
--- produced traffic, and "idle sends nothing" is the property this exists for.
export type Delta = {
	Width: number,
	Height: number,
	Focused: boolean,
	Changed: { any },
	Removed: { number },
	Order: { number }?,
	--- The dirty rectangle, in frame coordinates, or nil when nothing moved. A
	--- retained display ignores this; an immediate-mode one (GDI) uses it to
	--- repaint a region instead of a screen.
	Dirty: { number }?,
	--- THE FRAME THIS DELTA WAS COMPUTED FROM (ms-52 M14).
	---
	--- Handed back because computing the delta already built it. Every host was
	--- calling `SnapshotDelta()` and then `Snapshot()`, and both walk all 185
	--- nodes constructing a table each -- so the display list was built TWICE per
	--- frame, 0.70 ms of it, for two results that are identical by construction.
	---
	--- Callers that only want the frame should still call `Snapshot()`; this is
	--- for the ones that need both and would otherwise ask twice.
	Frame: Frame,
}

export type Session = {
	--- Advance one frame: step the clock, then let the router settle.
	Step: (dt: number) -> (),
	--- Feed one pointer event in. `kind` is "move", "down" or "up".
	Pointer: (kind: string, x: number, y: number) -> (),
	--- Feed wheel input, in scroll steps; positive scrolls the content up.
	Wheel: (x: number, y: number, delta: number) -> (),
	--- Feed one key to whatever field is focused. Returns whether it was used.
	Key: (key: string, modifiers: { Shift: boolean?, Ctrl: boolean? }?) -> boolean,
	Snapshot: () -> Frame,
	--- What changed since the last call. See Delta, and ms-52 M4.
	--- Pass `true` to force a FULL delta: every node and the paint order, as
	--- though the display had never been sent anything.
	SnapshotDelta: (full: boolean?) -> Delta,
	Stats: () -> { Frames: number, Events: number, Sent: number, Skipped: number },
}

--- Drive a tree as a running application.
---
--- The two halves of a frame are deliberately separate and in this order. The
--- CLOCK moves first, because motion changes geometry; then the router SETTLES,
--- because an element that moved under a stationary pointer has changed what is
--- hovered. Roblox never reports that second case — it is the reason the router
--- polls at all — so a host that drives frames has to pump it or hover silently
--- goes stale the moment anything animates.
function Live.Session(host: any, root: any, router: any, width: number, height: number): Session
	--- A LAYER ROOT, because hit-testing requires one and only Roblox supplies it
	--- for free.
	---
	--- `HitTest.ContainsVisible` walks from a pressable up through its ancestors
	--- and must terminate at an ENABLED layer root — a ScreenGui — or the element
	--- is not on screen and cannot be hit. In Roblox an entry point mounts into
	--- one (`host.mount(app, screenGui)`) and the walk ends there.
	---
	--- Off-engine nothing does. A host hands `Live.Session` a bare tree, the walk
	--- runs off the top into nil, and EVERY hit test returns false — so pressables
	--- render perfectly and no click, hover or drag ever lands. Nothing else
	--- misbehaves, which is what makes it so hard to see: layout is right, the
	--- display list is right, and the router is simply never told that anything is
	--- under the pointer.
	---
	--- Done HERE rather than in each host because every host needs it identically,
	--- and the one that forgets does not fail — it silently loses all input.
	if root ~= nil and host.Scene.Parent(root) == nil then
		local screen = host.create("ScreenGui")({
			Name = "AetherScreen",
			--- Explicit: `IsEnabled` reads this, and a mock instance has no Roblox
			--- default to fall back on.
			Enabled = true,
		})
		root.Parent = screen
	end

	local frames, events = 0, 0
	--- Delta bookkeeping (ms-52 M4). `Sent` counts frames that carried a change,
	--- `Skipped` counts frames where nothing did -- which is the number the exit
	--- gate is about.
	local sent, skipped = 0, 0
	local previousNodes: { [number]: any } = {}
	local previousOrder: { number } = {}
	local px, py = -1, -1
	local lastSolve: { Solved }? = nil

	--- SOLVE, THEN WRITE THE ANSWER BACK ONTO THE TREE (ms-52 M2).
	---
	--- This is what makes a real primitive interactive off-engine, and its absence
	--- is why the first live demo had to hand-build its rows. In Roblox the engine
	--- writes `AbsolutePosition`/`AbsoluteSize` after it lays out, and everything
	--- downstream — hit-testing, scope arbitration, floating placement — reads them
	--- back. Off-engine the solver computed the same rectangles and told nobody, so
	--- `Scene.Bounds` answered 0x0 for every node and `PointerRouter.Resolve` found
	--- nothing even with four pressables registered.
	---
	--- Every frame, because layout is not static: a spring moving a face changes
	--- what is under the pointer, and a hit test against last frame's rectangle is
	--- the stale-geometry bug ms-43 M20 was about.
	local function commitLayout(): { Solved }
		local solved = Layout.Solve(host.Scene, root, { X = 0, Y = 0, Width = width, Height = height }, host)
		for _, item in ipairs(solved) do
			host.SetBounds(item.Node, item.Rect.X, item.Rect.Y, item.Rect.Width, item.Rect.Height)
		end
		lastSolve = solved
		return solved
	end

	--- Scroll the topmost native ScrollingFrame under the pointer.
	---
	--- TOPMOST, by walking the solve backwards: `lastSolve` is in paint order, so
	--- the last match is the one drawn on top and therefore the one a user aimed
	--- at. Nested scrollers both being eligible is Roblox's behaviour too.
	---
	--- Clamped against the MEASURED canvas rather than an authored CanvasSize,
	--- because these screens use AutomaticCanvasSize -- there is no authored number
	--- to clamp to, and an unclamped offset scrolls the content clean out of the
	--- viewport with no way back.
	local function scrollNativeUnder(x: number, y: number, delta: number)
		local solved = lastSolve
		if not solved then
			return
		end
		local STEP = 40
		for i = #solved, 1, -1 do
			local item = solved[i]
			if host.Scene.ClassOf(item.Node) == "ScrollingFrame" then
				local r = item.Rect
				local inside = x >= r.X and x <= r.X + r.Width and y >= r.Y and y <= r.Y + r.Height
				local c = item.Clip
				if inside and c then
					inside = x >= c.X and x <= c.X + c.Width and y >= c.Y and y <= c.Y + c.Height
				end
				if inside then
					local _, extentY = Layout.CanvasExtent(item.Node)
					local maxScroll = math.max(extentY - r.Height, 0)
					if maxScroll <= 0 then
						return
					end
					local pos = host.Scene.Raw(item.Node, "CanvasPosition")
					local cy = if pos then (pos.Y or 0) else 0
					local cx = if pos then (pos.X or 0) else 0
					local next = math.clamp(cy + delta * STEP, 0, maxScroll)
					if next ~= cy then
						--- Written by assignment, and with the HOST's Vector2: the
						--- Scene contract is deliberately read-only (it answers
						--- questions about a tree, it does not own one), and this is
						--- the engine's property in engine terms. A bare table would
						--- be accepted by a mock and rejected by Roblox.
						local V2 = host.Vocabulary and host.Vocabulary.Vector2
						;(item.Node :: any).CanvasPosition = if V2 then V2.new(cx, next) else { X = cx, Y = next }
					end
					return
				end
			end
		end
	end

	--- Commit once up front, so a pointer event arriving before the first frame
	--- still resolves against real geometry.
	commitLayout()

	return {
		Step = function(dt: number)
			frames += 1
			--- ORDER IS LOAD-BEARING, and this is the third rule in it.
			---   1. CLOCK, because motion changes authored values.
			---   2. LAYOUT, because those values decide geometry.
			---   3. SETTLE, because an element that moved under a stationary
			---      pointer changed what is hovered — the case Roblox never
			---      reports, which is why the router polls at all.
			host.Clock.Step(dt)
			commitLayout()
			if router and router.Input and px >= 0 then
				router.Input.Settle(px, py)
			end
			if router and router.Input then
				router.Input.Frame()
			end
		end,

		--- KEYBOARD (ms-52 M3).
		---
		--- Routed straight to TextInputManager rather than through the pointer
		--- router, because focus -- not position -- decides who receives a key.
		--- The router's job is answering "what is under this coordinate", and a
		--- keystroke has no coordinate.
		---
		--- Returns whether the key was consumed, so a host can decide whether to let
		--- the browser keep its default (a focused field must swallow Backspace;
		--- nothing focused must not).
		Key = function(key: string, modifiers: any): boolean
			events += 1
			local manager = TextInputManager
			if not (manager and manager.HandleKey) then
				return false
			end
			local ok, consumed = pcall(manager.HandleKey, key, modifiers)
			return ok and consumed == true
		end,

		--- Wheel arrives resolved against CURRENT geometry, because the session
		--- commits layout every frame. Handling it against a stale solve would
		--- scroll whatever used to be under the pointer.
		Wheel = function(x: number, y: number, delta: number)
			events += 1
			px, py = x, y
			if router and router.Input and router.Input.Wheel then
				router.Input.Wheel(x, y, delta)
			end
			--- A NATIVE ScrollingFrame IS SCROLLED BY THE ENGINE, so here it is
			--- scrolled by the host (ms-52 M5).
			---
			--- The router's wheel seam reaches Aether's own ScrollArea, which keeps
			--- its own offset. It cannot reach a raw `ScrollingFrame`, because that
			--- class's behaviour was never Aether's to implement -- and real screens
			--- use it directly. ShopUI's whole body is one, which is why half that
			--- screen was unreachable and looked like UI that had not been ported.
			scrollNativeUnder(x, y, delta)
		end,

		Pointer = function(kind: string, x: number, y: number)
			events += 1
			px, py = x, y
			if not (router and router.Input) then
				return
			end
			if kind == "move" then
				router.Input.Move(x, y)
			elseif kind == "down" then
				--- Move first: a press at a position the router has not seen would
				--- resolve against a stale hover set. The browser reports both, but
				--- a synthetic click (or a very fast one) may not.
				router.Input.Move(x, y)
				router.Input.Press(x, y)
			elseif kind == "up" then
				router.Input.Release(x, y)
			end
		end,

		--- Serialises the solve the frame already did rather than solving again.
		--- Two solves per frame would be waste, and worse, they could disagree —
		--- the router would have arbitrated against one and the display painted the
		--- other.
		Snapshot = function(): Frame
			return Live.SnapshotSolved(host, lastSolve or commitLayout(), width, height)
		end,

		--- WHAT CHANGED SINCE LAST TIME (ms-52 M4).
		---
		--- Every host re-serialised and re-sent all 185 nodes at 60Hz whether or
		--- not anything moved. This answers the narrower question, and keeps the
		--- previous frame keyed by node id so a display can patch rather than
		--- rebuild.
		---
		--- The comparison is BY VALUE -- see `unchanged`. An identity comparison
		--- would report everything changed every frame, because the host rebuilds
		--- property values through effects, and the diff would pass its own tests
		--- while sending the whole screen.
		SnapshotDelta = function(full: boolean?): Delta
			--- RESYNC. Forgetting the previous frame makes every node "changed",
			--- which is exactly what a display that has just connected -- or
			--- reconnected, or asked because it lost track -- needs.
			---
			--- Needed the moment deltas shipped: an idle screen sends nothing, so
			--- a client with no scene and no traffic has no way to obtain one. The
			--- selftest found this by blocking forever on a static screen.
			if full then
				previousNodes = {}
				previousOrder = {}
			end
			--- BUILT AND DIFFED IN ONE PASS (ms-52 M15.3).
			---
			--- This used to call `SnapshotSolved` and then compare its 185 fresh
			--- tables against last frame's -- so an unchanged node cost five
			--- allocations to establish that it had not changed. `unchanged` reads
			--- the scene directly and allocates nothing, so a surviving node is
			--- REUSED: the same table goes into this frame's display list, and the
			--- diff is a by-product of building rather than a second walk.
			---
			--- REUSED MEANS READ-ONLY. The table handed forward IS last frame's
			--- record of it, so mutating one in place would make the next
			--- comparison a self-comparison -- always equal, nothing ever sent,
			--- and every test still green. Anything that differs gets a WHOLE new
			--- table from `buildNode`; nothing is ever patched.
			local solved = lastSolve or commitLayout()
			local Scene = host.Scene

			local nodes: { any } = {}
			local count = 0
			local changed: { any } = {}
			local removed: { number } = {}
			local order: { number } = {}
			--- NOT named `next`: that shadows the Luau builtin, and `pairs` below
			--- would then be walking a table with a local of the same name in
			--- scope -- confusing to read and a trap for the next edit.
			local current: { [number]: any } = {}

			local dirtyL, dirtyT, dirtyR, dirtyB = math.huge, math.huge, -math.huge, -math.huge
			local function markDirty(n: any)
				dirtyL = math.min(dirtyL, n.x)
				dirtyT = math.min(dirtyT, n.y)
				dirtyR = math.max(dirtyR, n.x + n.w)
				dirtyB = math.max(dirtyB, n.y + n.h)
			end

			local orderChanged = false
			for _, item in ipairs(solved) do
				if item.Rect.Width > 0 and item.Rect.Height > 0 then
					local was = previousNodes[idOf(item.Node)]
					local n, isSame
					if was ~= nil and unchanged(Scene, item, was) then
						n, isSame = was, true
					else
						n, isSame = buildNode(Scene, item), false
					end

					count += 1
					nodes[count] = n
					current[n.id] = n
					order[count] = n.id
					if not orderChanged and previousOrder[count] ~= n.id then
						orderChanged = true
					end

					if not isSame then
						table.insert(changed, n)
						markDirty(n)
						if was then
							--- The rectangle it VACATED is dirty too, or a node
							--- that moved leaves its old pixels behind on an
							--- immediate-mode display.
							markDirty(was)
						end
					end
				end
			end
			if count ~= #previousOrder then
				orderChanged = true
			end

			local frame: Frame = {
				Width = width,
				Height = height,
				Nodes = nodes,
				Focused = TextInputManager.GetActiveField() ~= nil,
			}

			for id, was in pairs(previousNodes) do
				if current[id] == nil then
					table.insert(removed, id)
					markDirty(was)
				end
			end

			previousNodes = current
			previousOrder = order

			if #changed > 0 or #removed > 0 then
				sent += 1
			else
				skipped += 1
			end

			return {
				Width = frame.Width,
				Height = frame.Height,
				Focused = frame.Focused,
				Frame = frame,
				Changed = changed,
				Removed = removed,
				Order = if orderChanged then order else nil,
				Dirty = if dirtyR > dirtyL
					then { dirtyL, dirtyT, dirtyR - dirtyL, dirtyB - dirtyT }
					else nil,
			}
		end,

		Stats = function()
			return { Frames = frames, Events = events, Sent = sent, Skipped = skipped }
		end,
	}
end

return Live
