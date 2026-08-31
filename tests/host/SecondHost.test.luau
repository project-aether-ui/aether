--!strict
--!tier math
--[=[
	The SECOND host — layout solved and drawn without an engine.

	WHY THIS SUITE EXISTS (ms-51 M21)
	es9, after the first Studio playtest: it is hard to know which of what you see
	in Studio actually flows through Aether, and which comes from packages still
	coupled to the engine or hand-rolled elsewhere. A manual audit answers that
	once and rots. A second host answers it by construction and keeps answering it:
	whatever can be drawn here reached the page through `Host.create` and the Scene
	contract, and whatever cannot, did not.

	The instrument is only worth anything if it cannot flatter the architecture, so
	what is asserted below is the arithmetic — that layout produces the RIGHT
	rectangles, not merely some. A solver that quietly returned zeroes would still
	"render", and would make every future audit a lie.
]=]
local T = require("@testkit")
local Aether = require("../../src/api")
local Layout = require("../../src/host/Layout")
local Svg = require("../../src/host/Svg")

local host = Aether.Host.Headless.new()
local V = host.Vocabulary
local Scene = host.Scene

local VIEWPORT = { X = 0, Y = 0, Width = 400, Height = 200 }

local function byName(solved: { any }): { [string]: any }
	local out = {}
	for _, item in ipairs(solved) do
		out[Scene.Name(item.Node) or "?"] = item
	end
	return out
end

--- Scale-and-offset, both axes, plus AnchorPoint.
local function testScaleOffsetAndAnchor()
	local root = host.create("Frame")({
		Name = "Root",
		Size = V.UDim2.fromScale(1, 1),
		host.create("Frame")({
			Name = "Half",
			Size = V.UDim2.new(0.5, -20, 0, 60),
			Position = V.UDim2.fromOffset(10, 10),
		}),
		host.create("Frame")({
			Name = "Centred",
			Size = V.UDim2.fromOffset(100, 40),
			Position = V.UDim2.fromScale(0.5, 0.5),
			AnchorPoint = V.Vector2.new(0.5, 0.5),
		}),
	})

	local at = byName(Layout.Solve(Scene, root, VIEWPORT))

	assert(at.Root.Rect.Width == 400 and at.Root.Rect.Height == 200, "a full-scale root fills the viewport")

	--- 0.5 of 400 is 200, minus the 20px offset.
	assert(at.Half.Rect.Width == 180, `scale and offset combine on X, got {at.Half.Rect.Width}`)
	assert(at.Half.Rect.Height == 60, "pure offset on Y")
	assert(at.Half.Rect.X == 10 and at.Half.Rect.Y == 10, "position is offset from the parent origin")

	--- AnchorPoint is a fraction of the element's OWN size, applied after the
	--- position resolves — which is what makes 0.5 mean "centre" rather than
	--- "start at the middle".
	assert(at.Centred.Rect.X == 200 - 50, `anchor 0.5 centres on X, got {at.Centred.Rect.X}`)
	assert(at.Centred.Rect.Y == 100 - 20, `anchor 0.5 centres on Y, got {at.Centred.Rect.Y}`)
end

--- UIPadding insets the box children resolve against; UIListLayout stacks them
--- in LayoutOrder, then declaration order.
local function testPaddingAndListLayout()
	local root = host.create("Frame")({
		Name = "Root",
		Size = V.UDim2.fromScale(1, 1),
		host.create("UIPadding")({ PaddingLeft = V.UDim.new(0, 16), PaddingTop = V.UDim.new(0, 16) }),
		host.create("UIListLayout")({ Padding = V.UDim.new(0, 8) }),
		host.create("Frame")({ Name = "Second", Size = V.UDim2.new(1, 0, 0, 40), LayoutOrder = 2 }),
		host.create("Frame")({ Name = "First", Size = V.UDim2.new(1, 0, 0, 60), LayoutOrder = 1 }),
	})

	local at = byName(Layout.Solve(Scene, root, VIEWPORT))

	assert(at.First.Rect.X == 16 and at.First.Rect.Y == 16, "padding insets the content box")
	assert(at.First.Rect.Width == 384, `and narrows it, got {at.First.Rect.Width}`)

	--- LayoutOrder wins over declaration order: `First` is declared SECOND.
	assert(at.First.Rect.Y < at.Second.Rect.Y, "LayoutOrder decides the stack, not declaration order")

	--- Advanced by what the previous child actually resolved to, so a stack of
	--- differently-sized rows lays out correctly: 16 + 60 + 8.
	assert(at.Second.Rect.Y == 84, `stacked after the taller row plus padding, got {at.Second.Rect.Y}`)
end

--- Clipping is tracked SEPARATELY from the rectangle, because an element clipped
--- away still has one. That distinction is the whole of ms-43 M20.
local function testClipping()
	local root = host.create("Frame")({
		Name = "Root",
		Size = V.UDim2.fromScale(1, 1),
		host.create("Frame")({
			Name = "Clip",
			Size = V.UDim2.fromOffset(100, 100),
			ClipsDescendants = true,
			host.create("Frame")({ Name = "Overflow", Size = V.UDim2.fromOffset(300, 300) }),
		}),
	})

	local at = byName(Layout.Solve(Scene, root, VIEWPORT))

	assert(at.Overflow.Rect.Width == 300, "the child keeps its own rectangle")
	assert(at.Overflow.Clip ~= nil, "and inherits a clip")
	assert(at.Overflow.Clip.Width == 100, `clipped to the ancestor, got {at.Overflow.Clip.Width}`)
	assert(at.Root.Clip == nil, "an unclipped element has none")
end

--- A REAL Aether primitive, not a hand-built tree. This is the claim the whole
--- instrument rests on: a compound primitive built through the host resolves to
--- real geometry off-engine.
local function testRealPrimitiveRenders()
	local controller = Aether.ScrollController.new({
		Orientation = "Vertical",
		ViewportSize = 300,
		ContentSize = 900,
	})
	local frame = Aether.ScrollingFrame({
		Controller = controller,
		Presentation = "Inset",
		ScrollBarWidth = 10,
		AutoHide = false,
	})

	local solved = Layout.Solve(Scene, frame, { X = 0, Y = 0, Width = 360, Height = 300 })
	local at = byName(solved)

	assert(#solved >= 5, `the compound primitive resolves its parts, got {#solved}`)
	assert(at.ScrollbarThumb ~= nil, "including the thumb")

	--- THE SCROLL MATH CROSSED THE HOST BOUNDARY. Viewport 300 of content 900 is a
	--- third, so the thumb is a third of its track. Asserting the RATIO rather than
	--- a pixel count is what makes this about the controller rather than about the
	--- renderer's arithmetic.
	local ratio = at.ScrollbarThumb.Rect.Height / at.ScrollbarTrack.Rect.Height
	assert(math.abs(ratio - 1 / 3) < 0.05, `thumb is a third of the track, got {ratio}`)

	--- Inset presentation reserves a gutter, so the scroll area is NARROWER than
	--- the frame. A renderer that ignored Presentation would make these equal.
	assert(at.ScrollArea.Rect.Width < at.ScrollingFrame.Rect.Width, "Inset reserves a gutter")
end

--- The SVG output is a document, and it carries what the tree actually had.
local function testSvgOutput()
	local root = host.create("Frame")({
		Name = "Root",
		Size = V.UDim2.fromScale(1, 1),
		BackgroundColor3 = V.Color3.fromRGB(255, 0, 0),
		BackgroundTransparency = 0,
		host.create("TextLabel")({
			Name = "Label",
			Text = "hello & <world>",
			Size = V.UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}),
	})

	local doc = Svg.Render(host, root, { Width = 100, Height = 50 })

	assert(string.find(doc, "<svg", 1, true) == 1, "it is an SVG document")
	assert(string.find(doc, "#ff0000", 1, true) ~= nil, "a Color3 became a fill")
	assert(string.find(doc, "hello &amp; &lt;world&gt;", 1, true) ~= nil, "text is carried, and escaped")

	--- An element with NO colour still appears, as an outline. That is the audit
	--- working rather than a rendering failure: structure crossed the boundary and
	--- paint did not, and the difference has to be visible.
	local bare = host.create("Frame")({ Name = "Bare", Size = V.UDim2.fromScale(1, 1) })
	local bareDoc = Svg.Render(host, bare, { Width = 50, Height = 50 })
	assert(string.find(bareDoc, "stroke-dasharray", 1, true) ~= nil, "an unpainted element is drawn as an outline")
	assert(string.find(bareDoc, "fill=\"none\"", 1, true) ~= nil, "with no fill")
end

--- THE LIVE HOST (ms-51 M22): interactivity and motion, off-engine.
---
--- The SVG host draws one frame from a tree that never changes, which proves the
--- seam and nothing about BEHAVIOUR. These two are what a running host adds, and
--- neither had ever been demonstrated outside Roblox — only argued for.
local function testLiveArbitration()
	local Live = require("../../src/host/Live")
	local PointerRouter = Aether.PointerRouter

	local hovered = host.source(false)
	local pressed = host.source(false)
	local activated = 0

	local press = PointerRouter.Pressable({
		OnHoverChanged = function(h: boolean)
			hovered(h)
		end,
		OnPressed = function()
			pressed(true)
		end,
		OnReleased = function()
			pressed(false)
		end,
		OnActivated = function()
			activated += 1
		end,
	})

	--- A LAYER ROOT is required, and its absence is not a quirk: HitTest must
	--- terminate at an enabled LayerCollector to consider anything on screen —
	--- the rule that stops a detached subtree claiming clicks. Roblox supplies a
	--- ScreenGui; here the host does.
	local screen = host.create("ScreenGui")({ Name = "Screen", Enabled = true })
	local face = host.create("Frame")({ Name = "Face", Size = V.UDim2.fromOffset(100, 40) })
	local root = host.create("Frame")({
		Name = "Root",
		Parent = screen,
		Size = V.UDim2.fromScale(1, 1),
		face,
	})

	--- Bind after a solve, because the router hit-tests against whatever geometry
	--- the Scene contract reports and an unsolved element correctly has none.
	for _, item in ipairs(Layout.Solve(Scene, root, { X = 0, Y = 0, Width = 200, Height = 100 })) do
		if Scene.Name(item.Node) == "Face" then
			host.SetBounds(item.Node, item.Rect.X, item.Rect.Y, item.Rect.Width, item.Rect.Height)
		end
	end
	press.Bind(face)

	local session = Live.Session(host, root, PointerRouter, 200, 100)

	assert(hovered() == false, "nothing is hovered before the pointer arrives")

	session.Pointer("move", 50, 20)
	assert(hovered() == true, "the pointer entering the surface hovers it")

	session.Pointer("down", 50, 20)
	assert(pressed() == true, "and pressing presses it")

	session.Pointer("up", 50, 20)
	assert(pressed() == false, "release clears the press")
	assert(activated == 1, "and press-then-release on the same element activates once")

	session.Pointer("move", 190, 90)
	assert(hovered() == false, "leaving the surface un-hovers it")

	--- The snapshot is what a display consumes: flat rectangles in paint order,
	--- carrying no tree. A display that received the tree could make layout
	--- decisions, and layout would then live half here and half there.
	local snap = session.Snapshot()
	assert(snap.Width == 200 and snap.Height == 100, "the frame carries its viewport")
	assert(#snap.Nodes >= 1, "and the nodes that resolved")
	assert(snap.Nodes[1].x ~= nil and snap.Nodes[1].w ~= nil, "as plain numbers, not UDim2")
end

--- Motion needs a CLOCK and successive frames. This is the half the SVG host
--- structurally could not show.
local function testLiveMotion()
	local Live = require("../../src/host/Live")
	local target = 0
	local value, velocity = 0, 0

	host.Clock.OnFrame(function(dt: number)
		local omega = 2 * math.pi / 0.18
		velocity += ((target - value) * omega * omega - velocity * 2 * omega) * dt
		value += velocity * dt
	end)

	local root = host.create("Frame")({ Name = "Root", Size = V.UDim2.fromScale(1, 1) })
	local session = Live.Session(host, root, nil, 100, 100)

	assert(value == 0, "at rest before any frame")

	target = 6
	session.Step(1 / 60)
	local afterOne = value
	assert(afterOne > 0, "one frame moves it")
	assert(afterOne < 6, "but does not teleport — this is interpolation, not assignment")

	for _ = 1, 30 do
		session.Step(1 / 60)
	end
	assert(math.abs(value - 6) < 0.1, `it settles on the target, got {value}`)
	assert(session.Stats().Frames == 31, "and every frame was counted")
end

--- TEXT MEASUREMENT (ms-52 M1).
---
--- THE TRAP THIS SUITE EXISTS TO AVOID, named in the sprint before a line was
--- written: a metrics provider that returns a plausible CONSTANT. Every assertion
--- about "is there a width" passes, every rectangle is wrong, and nothing says so.
--- That is the vacuous-test shape ms-51 spent a session removing.
---
--- So none of these assert that a width exists. They assert that the width VARIES
--- with the thing it is supposed to vary with.
local function testTextMeasurement()
	local Text = require("../../src/host/Text")
	Text._reset()

	local shortW = Text.Measure("Hi", 14)
	local longW = Text.Measure("A considerably longer label", 14)
	local bigW = Text.Measure("Hi", 28)

	assert(shortW > 0, "a measured string has width")
	assert(longW > shortW, `a longer string is wider: {longW} vs {shortW}`)
	assert(bigW > shortW, `a larger size is wider: {bigW} vs {shortW}`)

	--- Twice the size is twice the width, because advances scale with the em.
	assert(math.abs(bigW - shortW * 2) < 0.01, `28pt is exactly twice 14pt, got {bigW} vs {shortW * 2}`)

	--- NOT a uniform per-character factor. Same character COUNT, different shapes,
	--- different width — the property a monospace approximation cannot have, and
	--- the reason that option was rejected in D-text_metrics_provider.
	local narrow = Text.Measure("iiii", 14)
	local wide = Text.Measure("MMMM", 14)
	assert(wide > narrow * 2, `glyph shapes differ, not just counts: {wide} vs {narrow}`)

	--- Height follows line count, so a wrapped label can grow downward.
	local _, oneLine = Text.Measure("one", 14)
	local _, twoLines = Text.Measure("one\ntwo", 14)
	assert(math.abs(twoLines - oneLine * 2) < 0.01, "two lines is twice the height")

	local _, emptyH = Text.Measure("", 14)
	assert(Text.Measure("", 14) == 0, "an empty string has no width")
	assert(emptyH > 0, "but still occupies a line")
end

--- The seam, and the reason it exists: a host with exact metrics must be able to
--- replace the bundled table without layout ever awaiting.
local function testTextProviderSeam()
	local Text = require("../../src/host/Text")
	Text._reset()

	local asked = 0
	assert(Text.SetProvider(function(text: string, size: number): (number, number)
		asked += 1
		return #text * size, size
	end, "test") == true, "a provider registers")

	local w = Text.Measure("abcd", 10)
	assert(asked == 1, "and is consulted")
	assert(w == 40, `its answer is used, got {w}`)

	--- Never clobber, matching Aether.Motion and Aether.Cursor.
	assert(Text.SetProvider(function()
		return 0, 0
	end, "second") == false, "a second provider does not displace the first")

	--- A provider that ERRORS falls back rather than propagating: a layout solve
	--- that threw because a font was unavailable would take down the frame, and a
	--- slightly wrong rectangle is recoverable where no rectangle is not.
	Text._reset()
	Text.SetProvider(function(): (number, number)
		error("no font")
	end, "broken")
	local fallback = Text.Measure("Hi", 14)
	assert(fallback > 0, "a broken provider falls back to the table instead of throwing")

	Text._reset()
end

--- AutomaticSize resolves through the host, in the solver.
local function testAutomaticSize()
	local function label(name: string, text: string, size: number, auto: any)
		return host.create("TextLabel")({
			Name = name,
			Text = text,
			TextSize = size,
			AutomaticSize = auto,
			Size = V.UDim2.fromOffset(0, 0),
		})
	end

	local root = host.create("Frame")({
		Name = "Root",
		Size = V.UDim2.fromScale(1, 1),
		label("Short", "Hi", 14, "XY"),
		label("Long", "A considerably longer label", 14, "XY"),
		label("OnlyX", "Hi", 14, "X"),
		--- No AutomaticSize: must be untouched. A solver that auto-sized
		--- everything would pass every assertion above and be badly wrong.
		host.create("TextLabel")({
			Name = "Fixed",
			Text = "Hi",
			TextSize = 14,
			Size = V.UDim2.fromOffset(50, 20),
		}),
	})

	local at = byName(Layout.Solve(Scene, root, VIEWPORT, host))

	assert(at.Short.Rect.Width > 0, "an XY label sizes to its text")
	assert(at.Short.Rect.Height > 0, "on both axes")
	assert(at.Long.Rect.Width > at.Short.Rect.Width, "and a longer string is wider")

	assert(at.OnlyX.Rect.Width > 0, "an X-only label sizes horizontally")
	assert(at.OnlyX.Rect.Height == 0, "and leaves height alone")

	assert(at.Fixed.Rect.Width == 50 and at.Fixed.Rect.Height == 20,
		"a label WITHOUT AutomaticSize keeps its authored size")

	--- Without a host there is no measurement, and the behaviour is exactly what
	--- it was before M1 rather than a silent wrong answer.
	local without = byName(Layout.Solve(Scene, root, VIEWPORT))
	assert(without.Short.Rect.Width == 0, "no host means no measurement, not a guess")
end

--- THE POINT OF THE WHOLE INSTRUMENT (ms-52 M2).
---
--- Not "a primitive draws" -- M21 already showed that -- but "a primitive is
--- OPERABLE off-engine". This is a real ScrollingFrame with a real
--- ScrollController, driven only by pointer coordinates, and the assertion is on
--- the resulting scroll offset in studs of content.
---
--- It found two Roblox-only leaks that no suite and no Studio playtest could
--- have: the thumb's drag loop was a private UserInputService connection, and
--- InputScope reported (-1, -1) for the pointer whenever there was no engine to
--- ask. Both are fixed; this is what holds them fixed.
local function testRealPrimitiveIsDraggable()
	local Live = require("../../src/host/Live")

	local controller = Aether.ScrollController.new({
		Orientation = "Vertical",
		ViewportSize = 300,
		ContentSize = 900,
	})
	local frame = Aether.ScrollingFrame({
		Controller = controller,
		Presentation = "Inset",
		ScrollBarWidth = 10,
		AutoHide = false,
	})

	--- Parented to an ENABLED ScreenGui, because the router refuses to resolve
	--- anything that is not on a live screen -- correctly, and it is the same rule
	--- in Roblox. An unparented tree lays out fine and hit-tests nothing.
	local screen = host.create("ScreenGui")({ Name = "Screen", Enabled = true })
	frame.Parent = screen

	local session = Live.Session(host, frame, Aether.PointerRouter, 360, 300)

	--- Layout must have been written BACK onto the tree, or nothing below can
	--- resolve. Asserted separately so a regression here reads as itself rather
	--- than as a mysteriously dead drag.
	local thumb
	local function find(node: any, want: string): any
		if Scene.Name(node) == want then return node end
		for _, child in ipairs(Scene.Children(node)) do
			local hit = find(child, want)
			if hit then return hit end
		end
		return nil
	end
	thumb = find(frame, "ScrollbarThumb")
	assert(thumb ~= nil, "the scrollbar thumb should exist in the tree")

	local tx, ty, tw, th = Scene.Bounds(thumb)
	assert(tw > 0 and th > 0, `the thumb should have real bounds off-engine, got {tw}x{th}`)

	--- It must be reachable by the ROUTER, not merely present in the tree.
	local cx, cy = tx + tw / 2, ty + th / 2
	assert(Aether.PointerRouter.Resolve(cx, cy) ~= nil, "the thumb should hit-test")

	--- Drag it, and check the arithmetic rather than "it changed". The thumb
	--- travels (track - thumb) pixels across the full scroll range, so a 100px
	--- drag is a known fraction of 600 studs of scrollable content.
	assert(controller.GetOffset() == 0, "should start at the top")
	session.Pointer("down", cx, cy)
	session.Pointer("move", cx, cy + 100)
	session.Step(1 / 60)

	local travel = 296 - th
	local expected = (100 / travel) * 600
	local actual = controller.GetOffset()
	assert(
		math.abs(actual - expected) < 2,
		`a 100px thumb drag should scroll {string.format("%.0f", expected)}, got {string.format("%.0f", actual)}`
	)

	--- And it must STOP when released, or a drag would capture the pointer
	--- forever -- the failure mode the old global InputEnded handler existed for.
	session.Pointer("up", cx, cy + 100)
	local atRelease = controller.GetOffset()
	session.Pointer("move", cx, cy + 200)
	session.Step(1 / 60)
	assert(controller.GetOffset() == atRelease, "movement after release should not scroll")
end


--- WHEEL INPUT, OFF-ENGINE (ms-52 M3).
---
--- es9, after the drag landed: "I cannot use my scroll wheel on the scroll area."
--- Same shape as the drag defect and found the same way -- ScrollArea opened its
--- own UserInputService connection, so the wheel existed only in Roblox while the
--- target resolution around it was already portable.
---
--- Aimed INSIDE the content and clear of the scrollbar, so a pass here cannot be
--- the drag path firing under another name.
local function testWheelScrollsOffEngine()
	local Live = require("../../src/host/Live")

	local controller = Aether.ScrollController.new({
		Orientation = "Vertical",
		ViewportSize = 300,
		ContentSize = 900,
	})
	local frame = Aether.ScrollingFrame({
		Controller = controller,
		Presentation = "Inset",
		ScrollBarWidth = 10,
		AutoHide = false,
		Size = V.UDim2.new(0, 360, 0, 300),
	})
	--- OFFSET TO x=400, deliberately.
	---
	--- ScrollArea keeps a process-global list of scroll owners and resolves the
	--- wheel against whichever is under the pointer. The suite's earlier scroller
	--- still sits at the origin and is still parented, so a wheel event at (80,
	--- 150) is genuinely ambiguous between the two -- and this test would have
	--- passed or failed on which one the list happened to return.
	---
	--- Placing this one where nothing else is makes the assertion about the wheel
	--- rather than about iteration order.
	local screen = host.create("ScreenGui")({ Name = "WheelScreen", Enabled = true })
	local holder = host.create("Frame")({
		Name = "WheelHolder",
		Parent = screen,
		Position = V.UDim2.new(0, 400, 0, 0),
		Size = V.UDim2.new(0, 360, 0, 300),
		BackgroundTransparency = 1,
		frame,
	})

	local session = Live.Session(host, holder, Aether.PointerRouter, 800, 300)

	assert(controller.GetOffset() == 0, "should start at the top")
	session.Wheel(480, 150, 3)
	session.Step(1 / 60)
	local after = controller.GetOffset()
	assert(after > 0, `the wheel should scroll the content, offset stayed {after}`)

	--- Both directions, because a wheel that only travels one way is a stuck axis.
	session.Wheel(480, 150, -3)
	session.Step(1 / 60)
	assert(controller.GetOffset() < after, "the wheel should scroll back up")

	--- And it must not run past the ends.
	for _ = 1, 60 do
		session.Wheel(480, 150, -5)
	end
	session.Step(1 / 60)
	assert(controller.GetOffset() == 0, "scrolling up at the top should clamp, not go negative")
end


--- TYPING INTO A REAL TextInput, OFF-ENGINE (ms-52 M3).
---
--- The milestone plan flagged this as the risky half: "if the caret needs
--- TextService it is a bigger sprint than it looks." It does not -- the caret is
--- Aether's own, which is what makes this tractable -- but two things had to
--- change before a key could reach it.
---
--- FOCUS was already portable, and I had this wrong before checking: clicking a
--- field runs through the Pressable's OnActivated, which is the router path.
--- Only drag-selection and double-click-word sit behind `isRoblox`.
---
--- What was NOT portable is that there was no editing model at all -- Roblox's
--- TextBox did it. See TextEditing.test.luau for the model's own arithmetic;
--- this asserts the whole chain, pointer through caret.
local function testTypingIntoARealField()
	local Live = require("../../src/host/Live")
	local TextInput = require("../../src/TextInput")
	local TextInputManager = require("../../src/TextInputManager")

	TextInputManager.Blur(false)

	local changed: string? = nil
	local field = TextInput({
		Value = "ab",
		Size = V.UDim2.new(0, 200, 0, 32),
		TextSize = 14,
		OnChanged = function(next: string)
			changed = next
		end,
	})

	local screen = host.create("ScreenGui")({ Name = "TypingScreen", Enabled = true })
	local holder = host.create("Frame")({
		Name = "TypingHolder",
		Parent = screen,
		Position = V.UDim2.new(0, 0, 0, 400),
		Size = V.UDim2.new(0, 200, 0, 32),
		BackgroundTransparency = 1,
		field,
	})

	local session = Live.Session(host, holder, Aether.PointerRouter, 400, 500)

	--- A key with nothing focused must be refused, or a stray keystroke would
	--- edit whichever field happened to be last touched.
	assert(session.Key("z") == false, "a key with no focused field is not consumed")

	--- CLICK TO FOCUS, through the router, at a real coordinate.
	session.Pointer("down", 100, 416)
	session.Pointer("up", 100, 416)
	session.Step(1 / 60)
	assert(TextInputManager.GetActiveField() ~= nil, "clicking the field should focus it off-engine")

	--- TYPE. The assertion is on the resulting string and caret index, not on
	--- "something changed".
	assert(session.Key("c") == true, "a key with a focused field is consumed")
	session.Step(1 / 60)
	assert(changed ~= nil, "the field should report its change")
	--- EXACTLY "abc", caret at 4. Clicking at x=100 in a 200-wide field holding
	--- the two-character "ab" lands past the end of the text, so the caret goes to
	--- the end and the character appends. That is deterministic, not a
	--- coincidence, and worth pinning rather than accepting any 3-character result.
	assert(changed == "abc", `expected "abc", got "{tostring(changed)}"`)
	local caret = TextInputManager.GetSelection()
	assert(caret == 4, `the caret should follow the inserted character, got {caret}`)

	--- Backspace removes it again, which rules out an append-only path that
	--- would satisfy the assertion above.
	local afterInsert = changed :: string
	assert(session.Key("Backspace") == true, "Backspace is consumed by a focused field")
	session.Step(1 / 60)
	assert(#(changed :: string) == 2, `Backspace should shorten "{afterInsert}", got "{tostring(changed)}"`)

	--- CLICK-TO-CARET, which is what the text-measurement fix was for. Clicking
	--- the LEFT edge must put the caret before the first character, not at the
	--- end. This is the assertion that fails if TextInput goes back to measuring
	--- with a uniform advance: the mapping from x to character index is only as
	--- good as the widths it is built on.
	session.Pointer("down", 2, 416)
	session.Pointer("up", 2, 416)
	session.Step(1 / 60)
	local leftCaret = TextInputManager.GetSelection()
	assert(leftCaret == 1, `clicking the left edge should put the caret first, got {leftCaret}`)

	--- Enter commits and releases focus, so the next keystroke goes nowhere.
	assert(session.Key("Enter") == true, "Enter is consumed")
	assert(TextInputManager.GetActiveField() == nil, "and releases focus")
	assert(session.Key("q") == false, "after committing, keys are no longer consumed")
end


--- A NATIVE ScrollingFrame SCROLLS (ms-52 M5).
---
--- Not Aether's ScrollingFrame primitive -- the raw engine class, which real
--- screens use directly. ShopUI's entire body is one, and off-engine it behaved
--- as a plain clipping Frame: content past its edge was cut off with no way to
--- reach it, so roughly half that screen was unreachable. `--audit` is what told
--- that apart from UI that had simply not been ported, and the giveaway was that
--- scrolling recovered nothing.
---
--- Scrolling a ScrollingFrame is the ENGINE's behaviour in Roblox, so the host
--- owns it here: the solve displaces children by -CanvasPosition and measures the
--- canvas for AutomaticCanvasSize; the session moves CanvasPosition on a wheel.
local function testNativeScrollingFrameScrolls()
	local Live = require("../../src/host/Live")
	local Layout = require("../../src/host/Layout")

	local rows = {}
	for i = 1, 12 do
		table.insert(rows, host.create("Frame")({
			Name = `NativeRow{i}`,
			Size = V.UDim2.new(1, 0, 0, 50),
			LayoutOrder = i,
			BackgroundColor3 = V.Color3.fromRGB(40, 40, 40),
			BackgroundTransparency = 0,
		}))
	end

	local scroller = host.create("ScrollingFrame")({
		Name = "NativeScroller",
		Size = V.UDim2.new(0, 200, 0, 200),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = "Y",
		host.create("UIListLayout")({}),
		table.unpack(rows),
	})
	local screen = host.create("ScreenGui")({ Name = "NativeScreen", Enabled = true })
	scroller.Parent = screen

	local session = Live.Session(host, scroller, Aether.PointerRouter, 200, 200)

	--- The canvas must MEASURE, or there is nothing to scroll and a pass here
	--- would mean only that nothing errored. 12 rows of 50 = 600.
	local _, extent = Layout.CanvasExtent(scroller)
	assert(extent > 500, `AutomaticCanvasSize should measure the content, got {extent}`)

	local function topRowY(): number?
		local solved = Layout.Solve(host.Scene, scroller, { X = 0, Y = 0, Width = 200, Height = 200 }, host)
		for _, it in ipairs(solved) do
			if Scene.Name(it.Node) == "NativeRow1" then
				return it.Rect.Y
			end
		end
		return nil
	end

	local before = topRowY()
	assert(before ~= nil, "the first row should be placed")
	session.Wheel(100, 100, 3)
	session.Step(1 / 60)
	local after = topRowY()
	assert(after ~= nil and after < (before :: number) - 10,
		`the wheel should displace the content upward, {before} -> {tostring(after)}`)

	--- CLAMPED AT BOTH ENDS. An unclamped canvas scrolls the content clean out of
	--- the viewport with no way back, which is worse than not scrolling at all.
	for _ = 1, 40 do
		session.Wheel(100, 100, 5)
	end
	session.Step(1 / 60)
	local pos = Scene.Raw(scroller, "CanvasPosition")
	assert(pos and pos.Y <= extent - 200 + 0.01, `bottom clamp: {pos and pos.Y} exceeds {extent - 200}`)

	for _ = 1, 60 do
		session.Wheel(100, 100, -5)
	end
	session.Step(1 / 60)
	local back = Scene.Raw(scroller, "CanvasPosition")
	assert(back and back.Y == 0, `top clamp: expected 0, got {back and back.Y}`)
	assert(topRowY() == before, "and the content returns to where it started")
end


--- STROKES AND GRADIENTS REACH THE DISPLAY (ms-52 M2).
---
--- These are what make a card read as a card. ShopUI carries 17 UIStroke, and
--- without them a panel whose fill is nearly transparent draws as very nearly
--- nothing -- a large part of why a screen that was fully PRESENT looked
--- half-missing.
local function testStrokeAndGradientAreEmitted()
	local Live = require("../../src/host/Live")

	local panel = host.create("Frame")({
		Name = "StrokedPanel",
		Size = V.UDim2.new(0, 100, 0, 60),
		BackgroundColor3 = V.Color3.fromRGB(20, 20, 20),
		BackgroundTransparency = 0,
		host.create("UIStroke")({
			Thickness = 2,
			Color = V.Color3.fromRGB(255, 0, 0),
			Transparency = 0.25,
		}),
	})
	local plain = host.create("Frame")({
		Name = "PlainPanel",
		Size = V.UDim2.new(0, 100, 0, 60),
		Position = V.UDim2.new(0, 0, 0, 60),
		BackgroundColor3 = V.Color3.fromRGB(20, 20, 20),
		BackgroundTransparency = 0,
	})
	local holder = host.create("Frame")({
		Name = "PaintHolder",
		Size = V.UDim2.new(0, 100, 0, 120),
		BackgroundTransparency = 1,
		panel,
		plain,
	})

	local frame = Live.Snapshot(host, holder, 200, 200)
	local byName: { [string]: any } = {}
	for _, n in ipairs(frame.Nodes) do
		byName[n.name] = n
	end

	local stroked = byName.StrokedPanel
	assert(stroked ~= nil, "the stroked panel should be delivered")
	assert(stroked.stroke ~= nil, "and should carry its stroke")
	assert(stroked.stroke.thickness == 2, `thickness should survive, got {stroked.stroke.thickness}`)
	assert(stroked.stroke.colour[1] == 255 and stroked.stroke.colour[2] == 0,
		"and its colour, as 0-255 channels")
	assert(math.abs(stroked.stroke.alpha - 0.75) < 0.001,
		`Transparency 0.25 becomes alpha 0.75, got {stroked.stroke.alpha}`)

	--- ABSENT means nil, not a default. "Nothing set a stroke" has to stay
	--- distinguishable from "a stroke of zero", the same rule the fill follows --
	--- otherwise every node on screen grows an outline.
	assert(byName.PlainPanel ~= nil and byName.PlainPanel.stroke == nil,
		"a panel with no UIStroke carries no stroke")

	--- A disabled stroke is not drawn, and neither is a fully transparent one.
	local off = host.create("Frame")({
		Name = "OffPanel",
		Size = V.UDim2.new(0, 50, 0, 50),
		BackgroundColor3 = V.Color3.fromRGB(9, 9, 9),
		BackgroundTransparency = 0,
		host.create("UIStroke")({ Thickness = 3, Enabled = false }),
	})
	local off2 = Live.Snapshot(host, off, 100, 100)
	assert(off2.Nodes[1].stroke == nil, "a disabled UIStroke is not emitted")
end


--- UISCALE SCALES THE SUBTREE, NOT JUST THE NODE (ms-52 M2).
---
--- spektr/button uses one for press and hover feedback. Scaling the button
--- without its label would look worse than not scaling at all, so what is
--- asserted is that a CHILD moved and grew too, and about the right fixed point.
local function testUIScaleTransformsTheSubtree()
	local Layout = require("../../src/host/Layout")

	local function build(scale: number, anchorX: number)
		local label = host.create("TextLabel")({
			Name = "ScaledChild",
			Size = V.UDim2.new(0, 50, 0, 20),
			Position = V.UDim2.new(0, 10, 0, 10),
			Text = "x",
		})
		local box = host.create("Frame")({
			Name = "ScaledBox",
			Size = V.UDim2.new(0, 100, 0, 100),
			Position = V.UDim2.new(0, 100, 0, 0),
			AnchorPoint = V.Vector2.new(anchorX, 0),
			host.create("UIScale")({ Scale = scale }),
			label,
		})
		local solved = Layout.Solve(host.Scene, box, { X = 0, Y = 0, Width = 400, Height = 200 }, host)
		local out: { [string]: any } = {}
		for _, it in ipairs(solved) do
			out[Scene.Name(it.Node) or "?"] = it.Rect
		end
		return out
	end

	local plain = build(1, 0)
	local doubled = build(2, 0)

	assert(doubled.ScaledBox.Width == plain.ScaledBox.Width * 2,
		`the box should double, {plain.ScaledBox.Width} -> {doubled.ScaledBox.Width}`)

	--- THE CHILD IS THE POINT. A node-only implementation passes the line above
	--- and fails here.
	assert(doubled.ScaledChild.Width == plain.ScaledChild.Width * 2,
		`the child should double too, {plain.ScaledChild.Width} -> {doubled.ScaledChild.Width}`)
	--- Its OFFSET from the box grows as well, or the child scales in place and
	--- drifts out of its parent.
	local plainGap = plain.ScaledChild.X - plain.ScaledBox.X
	local scaledGap = doubled.ScaledChild.X - doubled.ScaledBox.X
	assert(math.abs(scaledGap - plainGap * 2) < 0.001,
		`the child's offset should scale: {plainGap} -> {scaledGap}`)

	--- ABOUT THE ANCHOR. With AnchorPoint.X = 0 the left edge is fixed; with 0.5
	--- the centre is. Getting this wrong makes a hover-scaled button jump sideways.
	assert(doubled.ScaledBox.X == plain.ScaledBox.X,
		`anchor 0 pins the left edge, {plain.ScaledBox.X} -> {doubled.ScaledBox.X}`)

	local centred = build(2, 0.5)
	local plainCentred = build(1, 0.5)
	local centreBefore = plainCentred.ScaledBox.X + plainCentred.ScaledBox.Width / 2
	local centreAfter = centred.ScaledBox.X + centred.ScaledBox.Width / 2
	assert(math.abs(centreAfter - centreBefore) < 0.001,
		`anchor 0.5 pins the centre, {centreBefore} -> {centreAfter}`)

	--- A scale of 1 must be a no-op, not a rebuild that drifts by rounding.
	local identity = build(1, 0)
	assert(identity.ScaledChild.X == plain.ScaledChild.X, "scale 1 changes nothing")
end

--- AN ALPHA-RAMP GRADIENT IS STILL A GRADIENT (ms-52 M2).
---
--- A UIGradient may carry only a Transparency NumberSequence and no Color --
--- MenuWindow's does, for the fade down a window body. That emitted nil, so 1 of
--- ShopUI's 2 gradients was expressed and the window read flat.
local function testAlphaRampGradient()
	local Live = require("../../src/host/Live")

	local faded = host.create("Frame")({
		Name = "FadedPanel",
		Size = V.UDim2.new(0, 80, 0, 80),
		BackgroundColor3 = V.Color3.fromRGB(10, 20, 30),
		BackgroundTransparency = 0,
		host.create("UIGradient")({
			Rotation = 90,
			Transparency = V.NumberSequence.new({
				V.NumberSequenceKeypoint.new(0, 0),
				V.NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local frame = Live.Snapshot(host, faded, 100, 100)
	local node = frame.Nodes[1]
	assert(node.gradient ~= nil, "a transparency-only UIGradient should still be delivered")
	assert(node.gradient.stops == nil, "with no colour stops, because it has no Color")
	assert(node.gradient.alphaStops ~= nil and #node.gradient.alphaStops == 2,
		"and two alpha stops")
	assert(math.abs(node.gradient.alphaStops[1].a - 1) < 0.001, "transparency 0 is alpha 1")
	assert(math.abs(node.gradient.alphaStops[2].a - 0) < 0.001, "transparency 1 is alpha 0")

	--- AND THE NODE STILL CARRIES ITS FILL, which the painters need.
	---
	--- An alpha ramp MODULATES the fill rather than sitting on top of it: the
	--- element is drawn once with a per-pixel alpha, the way Roblox draws it. Both
	--- painters were filling flat and then compositing the ramp over it in the
	--- same colour, which composites to opaque -- MenuWindow's window rendered
	--- solid while its gradient ramped 0.1 to 0.3 in this very data.
	---
	--- So the FRAME must keep both: the colour to modulate, and the ramp to
	--- modulate it by. A protocol that dropped either would make the correct
	--- rendering impossible rather than merely absent.
	assert(node.fill ~= nil, "a node with an alpha ramp must still carry its fill colour")
	assert(node.alpha ~= nil, "and its base alpha, which the ramp multiplies")

	--- A CONSTANT transparency is NOT a gradient -- it is the node's own alpha,
	--- which `alpha` already carries. Emitting it would make every uniformly
	--- transparent element claim a gradient it does not have.
	local flat = host.create("Frame")({
		Name = "FlatPanel",
		Size = V.UDim2.new(0, 80, 0, 80),
		BackgroundColor3 = V.Color3.fromRGB(10, 20, 30),
		BackgroundTransparency = 0,
		host.create("UIGradient")({
			Transparency = V.NumberSequence.new({
				V.NumberSequenceKeypoint.new(0, 0.5),
				V.NumberSequenceKeypoint.new(1, 0.5),
			}),
		}),
	})
	assert(Live.Snapshot(host, flat, 100, 100).Nodes[1].gradient == nil,
		"a constant transparency ramp is not emitted as a gradient")
end


--- PAINT ORDER IS HIERARCHICAL, AND MATCHES HitTest (ms-52 M5).
---
--- The solve used to sort by ZIndex globally -- Roblox's LEGACY
--- `ZIndexBehavior.Global`. Modern Roblox defaults to SIBLING: a child always
--- renders above its parent, and ZIndex only orders siblings.
---
--- With a global sort, SettingsUI's `Window` -- opaque, 600x480, and carrying a
--- higher ZIndex than the rows inside it -- painted AFTER 25 of its own
--- descendants and covered every one. Both real screens showed chrome around an
--- empty interior, which read as content that had never been ported.
---
--- `--audit` could not catch it: every one of those nodes WAS delivered and WAS
--- visible by every test it applies. They were painted over, which is a property
--- of the ORDER and of nothing else. Hence this test.
local function testPaintOrderIsHierarchical()
	local Layout = require("../../src/host/Layout")

	local inner = host.create("TextLabel")({
		Name = "Inner",
		Size = V.UDim2.new(0, 40, 0, 20),
		Position = V.UDim2.new(0, 10, 0, 10),
		ZIndex = 1,
		Text = "inside",
	})
	--- A parent with a HIGHER ZIndex than its child. Under a global sort this is
	--- painted last and hides the child; under Sibling the child is always above.
	local window = host.create("Frame")({
		Name = "OpaqueWindow",
		Size = V.UDim2.new(0, 200, 0, 100),
		ZIndex = 5,
		BackgroundColor3 = V.Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0,
		inner,
	})

	local solved = Layout.Solve(host.Scene, window, { X = 0, Y = 0, Width = 300, Height = 300 }, host)
	local windowAt, innerAt
	for i, it in ipairs(solved) do
		local name = Scene.Name(it.Node)
		if name == "OpaqueWindow" then
			windowAt = i
		elseif name == "Inner" then
			innerAt = i
		end
	end
	assert(windowAt and innerAt, "both nodes should be solved")
	assert(innerAt > windowAt,
		`a child paints AFTER its parent whatever their ZIndex, got parent at {windowAt} and child at {innerAt}`)

	--- SIBLINGS still order by ZIndex -- the half that must keep working.
	local lo = host.create("Frame")({
		Name = "LowSibling",
		Size = V.UDim2.new(0, 50, 0, 50),
		ZIndex = 1,
		BackgroundColor3 = V.Color3.fromRGB(1, 1, 1),
		BackgroundTransparency = 0,
	})
	local hi = host.create("Frame")({
		Name = "HighSibling",
		Size = V.UDim2.new(0, 50, 0, 50),
		ZIndex = 9,
		BackgroundColor3 = V.Color3.fromRGB(2, 2, 2),
		BackgroundTransparency = 0,
	})
	--- Declared with the HIGH one first, so declaration order alone cannot
	--- produce the expected answer.
	local holder = host.create("Frame")({
		Name = "SiblingHolder",
		Size = V.UDim2.new(0, 200, 0, 200),
		BackgroundTransparency = 1,
		hi,
		lo,
	})
	local sibSolved = Layout.Solve(host.Scene, holder, { X = 0, Y = 0, Width = 300, Height = 300 }, host)
	local loAt, hiAt
	for i, it in ipairs(sibSolved) do
		local name = Scene.Name(it.Node)
		if name == "LowSibling" then
			loAt = i
		elseif name == "HighSibling" then
			hiAt = i
		end
	end
	assert(loAt and hiAt, "both siblings should be solved")
	assert(hiAt > loAt, `the higher ZIndex sibling paints later, got low at {loAt} and high at {hiAt}`)

	--- AND IT AGREES WITH HIT-TESTING. These disagreed until now: RendersAbove
	--- always implemented Sibling, so what could be clicked and what could be seen
	--- were ordered by different rules.
	local HitTest = require("../../src/HitTest")
	assert(HitTest.RendersAbove(inner, window),
		"HitTest agrees the child is above its parent")
	assert(HitTest.RendersAbove(hi, lo), "and that the higher sibling is above")
end


--- FRAME DIFFING (ms-52 M4).
---
--- Every host re-serialised and re-sent all 185 nodes at 60Hz whether or not
--- anything moved. The exit gate for this sprint is two properties: an idle
--- screen produces nothing, and a screen where ONE thing changes produces one
--- thing.
---
--- THE TRAP THE PLAN NAMED BEFORE THE SPRINT: comparing tables by identity. The
--- host rebuilds property values through effects, so an unchanged node is often a
--- new table each frame -- an identity comparison reports everything changed
--- every frame, and the diff passes its own tests while sending the whole screen.
--- The idle assertion below is precisely what catches that.
local function testFrameDiffing()
	local Live = require("../../src/host/Live")

	local colour = host.source(V.Color3.fromRGB(10, 20, 30))
	local moving = host.source(0)

	local a = host.create("Frame")({
		Name = "DiffStatic",
		Size = V.UDim2.new(0, 50, 0, 50),
		BackgroundColor3 = V.Color3.fromRGB(1, 2, 3),
		BackgroundTransparency = 0,
	})
	local b = host.create("Frame")({
		Name = "DiffColoured",
		Size = V.UDim2.new(0, 50, 0, 50),
		Position = V.UDim2.new(0, 60, 0, 0),
		BackgroundColor3 = function()
			return colour()
		end,
		BackgroundTransparency = 0,
	})
	local c = host.create("Frame")({
		Name = "DiffMoving",
		Size = V.UDim2.new(0, 50, 0, 50),
		Position = function()
			return V.UDim2.new(0, 120, 0, moving())
		end,
		BackgroundColor3 = V.Color3.fromRGB(9, 9, 9),
		BackgroundTransparency = 0,
	})
	local holder = host.create("Frame")({
		Name = "DiffHolder",
		Size = V.UDim2.new(0, 300, 0, 200),
		BackgroundTransparency = 1,
		a, b, c,
	})

	local session = Live.Session(host, holder, Aether.PointerRouter, 300, 200)

	--- The first delta is everything: nothing has been sent before.
	local first = session.SnapshotDelta()
	assert(#first.Changed >= 4, `the first delta carries the whole screen, got {#first.Changed}`)
	assert(first.Order ~= nil, "and the paint order, since the display has none yet")

	--- IDLE PRODUCES NOTHING. This is the assertion an identity-based comparison
	--- cannot pass, because the host rebuilds these tables every frame.
	for _ = 1, 5 do
		local idle = session.SnapshotDelta()
		assert(#idle.Changed == 0,
			`an idle screen must change nothing, got {#idle.Changed} node(s)`)
		assert(#idle.Removed == 0, "and remove nothing")
		assert(idle.Order == nil, "and not resend the paint order")
		assert(idle.Dirty == nil, "and report no dirty region")
	end

	--- ONE CHANGE PRODUCES ONE NODE.
	colour(V.Color3.fromRGB(200, 100, 50))
	session.Step(1 / 60)
	local one = session.SnapshotDelta()
	assert(#one.Changed == 1, `one recoloured node should produce one change, got {#one.Changed}`)
	assert(one.Changed[1].name == "DiffColoured", `and it should be the one that changed, got {one.Changed[1].name}`)
	assert(one.Order == nil, "paint order did not change, so it is not resent")

	--- A MOVE DIRTIES BOTH RECTANGLES. An immediate-mode display repaints a
	--- region, so the area a node VACATED has to be included or it leaves its old
	--- pixels behind.
	moving(80)
	session.Step(1 / 60)
	local moved = session.SnapshotDelta()
	assert(#moved.Changed == 1, `moving one node changes one node, got {#moved.Changed}`)
	assert(moved.Dirty ~= nil, "a move must report a dirty region")
	local d = moved.Dirty :: { number }
	assert(d[4] >= 80, `the dirty region must span both old and new position, got height {d[4]}`)

	--- And it settles back to silence.
	session.Step(1 / 60)
	assert(#session.SnapshotDelta().Changed == 0, "after settling, nothing changes again")

	local stats = session.Stats()
	assert(stats.Skipped > stats.Sent,
		`most frames should carry nothing: sent {stats.Sent}, skipped {stats.Skipped}`)
end


--- RELEASING A THUMB DRAG DOES NOT SNAP THE CONTENT BACKWARDS (ms-52).
---
--- es9: "the spring motion taking effect on the thumb just after a thumb drag
--- had ended". Real, and it has a precise mechanism.
---
--- While the thumb is held, `ScrollArea` renders the RAW offset so the content
--- tracks the finger exactly. The spring is chasing that offset and lags it by
--- roughly its period. The instant the drag ends, rendering switches to the
--- spring -- which is still behind -- so the content jumps BACKWARDS to where the
--- spring got to, then eases forward again.
---
--- Asserted on the frame the release produces: it must not be further from the
--- destination than the frame before it. A backwards jump is exactly that and
--- nothing else is.
local function testDragReleaseDoesNotSnapBack()
	--- BUILT INSIDE A REACTIVE ROOT. vide refuses `spring()` outside one, and
	--- this test registers a real spring driver -- so without a root it fails
	--- with "cannot use spring() outside a stable or reactive scope" before it
	--- can assert anything.
	local destroy = host.root(function()
		local Live = require("../../src/host/Live")
		local Layout = require("../../src/host/Layout")

		--- A MOTION RUNTIME IS THE PRECONDITION, not decoration.
		---
		--- `Motion.Smooth` returns its target unchanged when no spring driver is
		--- registered, so with no driver there is no lag, no handover, and nothing
		--- to snap back from. Without this the test was vacuous and a poison proved
		--- it: removing the fix changed nothing because the fix had nothing to do.
		---
		--- THE DRIVER IS BUILT HERE rather than required from Flux, which is what
		--- this line used to do. Flux did not graduate with Aether, so the require
		--- resolved into a monorepo four directories up and this suite could not run
		--- at all. Reaching for it was incidental coupling in the first place: what
		--- the test needs is A spring, and Motion is a seam precisely so that any
		--- runtime satisfying the contract will do.
		---
		--- `host.spring` IS vide's real spring, and `Clock.Step` already drives it
		--- through `update_springs`. So this is not a stand-in that might lag
		--- differently from the real thing -- it is the same arithmetic Flux wraps,
		--- on a simulated clock, which makes the trajectory exact and repeatable
		--- where a Heartbeat-driven one would be a race.
		Aether.Motion._reset()
		Aether.Motion.SetSpringDriver(function(target, options)
			local get = host.spring(
				target,
				if options then options.Period else nil,
				if options then options.DampingRatio else nil
			)
			return get
		end, "SecondHost.test")
		assert((Aether.Motion :: any).HasSpringDriver(),
			"this test is meaningless without a spring driver")

		local controller = Aether.ScrollController.new({
			Orientation = "Vertical",
			ViewportSize = 300,
			ContentSize = 900,
		})
		local frame = Aether.ScrollingFrame({
			Controller = controller,
			Presentation = "Inset",
			ScrollBarWidth = 10,
			AutoHide = false,
			--- Smoothing ON and slow, which is what makes the gap visible at all. With
			--- no spring there is nothing to hand over to and the bug cannot occur.
			--- Deliberately NOT setting Size: the drag test that already works does
			--- not, and a scroller sized here laid out with a zero-height thumb.
			Motion = { Period = 0.35, DampingRatio = 1 },
			--- REAL CONTENT, because the observable is where a row ends up.
			---
			--- Without it this test was vacuous and a poison proved it: an empty
			--- scroller has no `ScrollContent`, the reader returned 0 both times, and
			--- the assertion compared 0 with 0. `ScrollContent` also only moves when
			--- the canvas is not stationary; with a controller the rows are positioned
			--- individually, so a ROW is the thing to watch.
			Content = function()
				local rows = {}
				for i = 1, 14 do
					table.insert(rows, host.create("TextLabel")({
						Name = `SnapRow{i}`,
						Size = V.UDim2.new(1, 0, 0, 44),
						LayoutOrder = i,
						Text = `row {i}`,
					}))
				end
				return rows
			end,
		})
		--- PLACED WHERE NOTHING ELSE IS, for the same reason the wheel test is.
		---
		--- PointerRouter is a process singleton and ScrollArea keeps a global list of
		--- scroll owners, so earlier suites in this file leave live scrollers at the
		--- ORIGIN. A thumb here overlapped one of them and the drag resolved to
		--- whichever the list returned -- the test passed on one run and failed on the
		--- next. A flaky assertion is worse than an absent one.
		local screen = host.create("ScreenGui")({ Name = "SnapBackScreen", Enabled = true })
		local holder = host.create("Frame")({
			Name = "SnapBackHolder",
			Parent = screen,
			Position = V.UDim2.new(0, 900, 0, 0),
			Size = V.UDim2.new(0, 360, 0, 300),
			BackgroundTransparency = 1,
			frame,
		})

		local session = Live.Session(host, holder, Aether.PointerRouter, 1400, 300)

		local function find(node: any, want: string): any
			if Scene.Name(node) == want then
				return node
			end
			for _, child in ipairs(Scene.Children(node)) do
				local hit = find(child, want)
				if hit then
					return hit
				end
			end
			return nil
		end
		local thumb = find(frame, "ScrollbarThumb")
		assert(thumb ~= nil, "the thumb should exist")
		local tx, ty, tw, th = Scene.Bounds(thumb)
		local cx, cy = tx + tw / 2, ty + th / 2

		--- Drag a long way, so the spring has plenty to lag behind.
		session.Pointer("down", cx, cy)
		session.Pointer("move", cx, cy + 120)
		session.Step(1 / 60)

		local heldOffset = controller.GetOffset()
		assert(heldOffset > 50, `the drag should have scrolled, got {heldOffset}`)

		--- What the SCREEN shows while held: the raw offset, tracking the thumb.
		local function contentTop(): number?
			local solved = Layout.Solve(Scene, holder, { X = 0, Y = 0, Width = 1400, Height = 300 }, host)
			for _, it in ipairs(solved) do
				if Scene.Name(it.Node) == "SnapRow1" then
					return it.Rect.Y
				end
			end
			return nil
		end

		local whileHeld = contentTop()
		assert(whileHeld ~= nil, "the first row must be placed, or this measures nothing")

		--- Release, then look at the very next frame.
		session.Pointer("up", cx, cy + 120)
		session.Step(1 / 60)
		local justAfter = contentTop()
		assert(justAfter ~= nil, "the first row must still be placed after release")

		--- A BACKWARDS JUMP is the content moving back toward where it started. The
		--- drag scrolled DOWN, so the content top moved UP (more negative); snapping
		--- back means it moved down again by more than a frame of easing could.
		assert((justAfter :: number) <= (whileHeld :: number) + 2,
			`releasing a drag must not snap the content back: {string.format("%.1f", whileHeld)} `
				.. `-> {string.format("%.1f", justAfter)}`)
	end)
	destroy()
end

T.test("text measurement varies with string and size", testTextMeasurement, "math")
T.test("the metrics seam registers, never clobbers, and survives a bad provider", testTextProviderSeam, "math")
T.test("AutomaticSize resolves through the host", testAutomaticSize, "math")
T.test("live host: hover, press and activate run off-engine", testLiveArbitration, "math")
T.test("live host: the clock drives real interpolation", testLiveMotion, "math")
T.test("scale, offset and anchor resolve to real rectangles", testScaleOffsetAndAnchor, "math")
T.test("padding insets and list layout stacks in order", testPaddingAndListLayout, "math")
T.test("clipping is tracked apart from the rectangle", testClipping, "math")
T.test("a real Aether primitive resolves off-engine", testRealPrimitiveRenders, "math")
T.test("the SVG carries colour, text and unpainted structure", testSvgOutput, "math")

T.test("a real Aether primitive is DRAGGABLE off-engine", testRealPrimitiveIsDraggable, "math")

T.test("the wheel scrolls a real primitive off-engine", testWheelScrollsOffEngine, "math")

T.test("typing into a real TextInput works off-engine", testTypingIntoARealField, "math")

T.test("a native ScrollingFrame scrolls and clamps", testNativeScrollingFrameScrolls, "math")

T.test("strokes reach the display, and absence stays absent", testStrokeAndGradientAreEmitted, "math")

T.test("UIScale transforms the whole subtree about its anchor", testUIScaleTransformsTheSubtree, "math")
T.test("a transparency-only gradient is delivered as an alpha ramp", testAlphaRampGradient, "math")

T.test("paint order is hierarchical and agrees with HitTest", testPaintOrderIsHierarchical, "math")

T.test("frame diffing: idle sends nothing, one change sends one node", testFrameDiffing, "math")
--- EVERY FIELD A DISPLAY CONSUMES MUST REACH THE DELTA (ms-52 M15.3).
---
--- `SnapshotDelta` no longer builds a node and then compares it. It asks
--- `unchanged` whether the scene still matches last frame's table, and REUSES
--- that table when it does -- so the frame allocates nothing for a node that did
--- not move, and the idle delta halved.
---
--- The price is that `buildNode` and `unchanged` are two lists of the same
--- fields, and they can drift. A field emitted by one and forgotten by the other
--- does not fail loudly: the node is judged unchanged forever, the display keeps
--- painting a stale value, and every existing assertion still passes because the
--- snapshot itself is correct -- only the DELTA is blind.
---
--- So this drives each field in turn and asserts the delta notices. It is the
--- gate for that class of silence, and adding a field to `buildNode` without
--- adding it here leaves the same hole open.
local function testDeltaTracksEveryField()
	local Live = require("../../src/host/Live")

	local px, sizeY = host.source(0), host.source(40)
	local text, textSize = host.source("hello"), host.source(14)
	local alpha, name = host.source(0), host.source("Tracked")
	local fill = host.source(V.Color3.fromRGB(10, 10, 10))
	local textColour = host.source(V.Color3.fromRGB(200, 200, 200))
	local radius, alignX = host.source(4), host.source("Left")
	local strokeThickness = host.source(2)
	local gradientRotation = host.source(0)
	local clipping = host.source(false)

	local target = host.create("TextLabel")({
		Name = function() return name() end,
		Position = function() return V.UDim2.new(0, px(), 0, 0) end,
		Size = function() return V.UDim2.new(0, 120, 0, sizeY()) end,
		BackgroundColor3 = function() return fill() end,
		BackgroundTransparency = function() return alpha() end,
		Text = function() return text() end,
		TextSize = function() return textSize() end,
		TextColor3 = function() return textColour() end,
		TextXAlignment = function() return alignX() end,
		host.create("UICorner")({
			CornerRadius = function() return V.UDim.new(0, radius()) end,
		}),
		host.create("UIStroke")({
			Thickness = function() return strokeThickness() end,
			Color = V.Color3.fromRGB(255, 0, 0),
		}),
		host.create("UIGradient")({
			Color = V.ColorSequence.new(V.Color3.fromRGB(0, 0, 0), V.Color3.fromRGB(255, 255, 255)),
			Rotation = function() return gradientRotation() end,
		}),
	})
	local holder = host.create("Frame")({
		Name = "TrackHolder",
		Size = V.UDim2.new(0, 300, 0, 200),
		BackgroundTransparency = 1,
		ClipsDescendants = function() return clipping() end,
		target,
	})

	local session = Live.Session(host, holder, Aether.PointerRouter, 300, 200)
	session.SnapshotDelta(true)

	--- SETTLE FIRST, and assert it settled. If the screen never goes quiet the
	--- rest of this test passes for the wrong reason -- every mutation would
	--- "change something" because something always changes.
	for _ = 1, 4 do
		session.Step(1 / 60)
		session.SnapshotDelta()
	end
	assert(#session.SnapshotDelta().Changed == 0,
		"the screen must go quiet before a mutation can be attributed to the mutation")

	local function mutate(label: string, apply: () -> ())
		apply()
		session.Step(1 / 60)
		local delta = session.SnapshotDelta()
		assert(#delta.Changed > 0, `changing {label} must reach the delta, and it did not`)
		--- SETTLE AGAIN, so the next field starts from silence rather than
		--- inheriting this one's change.
		session.Step(1 / 60)
		assert(#session.SnapshotDelta().Changed == 0,
			`after changing {label} the screen must settle again`)
	end

	mutate("x", function() px(30) end)
	mutate("h", function() sizeY(55) end)
	mutate("clip", function() clipping(true) end)
	mutate("text", function() text("goodbye") end)
	mutate("alpha", function() alpha(0.5) end)
	mutate("textSize", function() textSize(22) end)
	mutate("name", function() name("Renamed") end)
	mutate("fill", function() fill(V.Color3.fromRGB(200, 30, 30)) end)
	mutate("textColour", function() textColour(V.Color3.fromRGB(0, 255, 0)) end)
	mutate("radius", function() radius(12) end)
	mutate("textAlignX", function() alignX("Right") end)
	mutate("stroke", function() strokeThickness(6) end)
	mutate("gradient", function() gradientRotation(90) end)
end

T.test("the delta notices a change to every field a display consumes", testDeltaTracksEveryField, "math")

T.test("releasing a thumb drag does not snap the content backwards", testDragReleaseDoesNotSnapBack, "math")

return T.run("SecondHost")
