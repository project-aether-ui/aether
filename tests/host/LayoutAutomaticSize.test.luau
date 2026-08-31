--!strict
--!tier math
--[=[
	spektr/aether · AutomaticSize suite (ms-53 D1).

	WHAT THIS PINS, AND WHY IT DID NOT EXIST BEFORE.

	`Button` rendered at ZERO WIDTH off-engine for a whole milestone. Nothing
	caught it because no screen mounts a bare Button -- ShopUI and SettingsUI give
	theirs explicit sizes -- and because the component suites assert on the tree
	Button BUILDS (`b.AutomaticSize == Enum.AutomaticSize.X`) and never on the
	RECTANGLE it is given. A property can be set correctly and mean nothing.

	So every case here asserts a solved rectangle.

	THE SHAPE THAT MATTERS is `Button > Face > Content > Label`, where Face is
	`UDim2.fromScale(1, 1)`. It is the reason a direct-children rule is not enough
	and the reason one measuring pass is not enough:

	  * measuring only DIRECT children sees one scale-sized child, refuses, and
	    leaves the parent at zero;
	  * measuring descendants but never re-placing leaves Face itself at zero --
	    the button is the right size and its only visible part is empty, which
	    still paints nothing.

	Both failure modes produce a plausible-looking tree, so both have a case.

	AND THESE ASSERTIONS WERE ONCE REWRITTEN AGAINST THEM, WRONGLY.

	This suite could not run from the day Aether graduated until testkit was
	replaced. When it ran again, three cases failed, and the reasoning that
	followed was: two Studio-verified conformance cases say a scale-sized child is
	measured against the space available to its parent, this suite says
	measurement passes through it, therefore the suite is stale. The assertions
	were changed to match the implementation.

	Both verified cases used a scale of 0.5. `automatic_size_full_scale_child` then
	asked the engine about scale 1 and it answered 90 -- pass-through, exactly what
	this file had said all along. The assertions are restored and Layout.luau's
	grow() now discriminates.

	The generalisation was the error, not the suite. A rule fitted to two points
	does not extend to a third by argument, and "the tests must be stale" is the
	most comfortable available explanation for a failure -- which is precisely why
	it needs evidence rather than reasoning. Change an assertion here only against
	an engine reading.
]=]
local T = require("@testkit")
local Aether = require("../../src/api")
local Layout = require("../../src/host/Layout")

local VIEWPORT = { X = 0, Y = 0, Width = 400, Height = 300 }

--- A FIXED MEASUREMENT, so the suite does not depend on a font being installed.
--- Ten pixels per character at any size: crude, deterministic, and enough to
--- assert that an extent was measured at all rather than what a real face does.
local function measure(text: string, _size: number): (number, number)
	return #text * 10, 20
end

local function fixture()
	local host = Aether.Host.Headless.new()
	host.Text.SetProvider(measure, "LayoutAutomaticSize suite")
	return host, host.Vocabulary, host.create
end

local function solveNamed(host: any, root: any): { [string]: any }
	local solved = Layout.Solve(host.Scene, root, VIEWPORT, host)
	local byName: { [string]: any } = {}
	for _, item in ipairs(solved) do
		byName[host.Scene.Name(item.Node) or "?"] = item.Rect
	end
	return byName
end

--- A container with one offset-sized child grows to fit it.
local function testGrowsToAnOffsetChild()
	local host, V, create = fixture()
	local root = create("Frame")({
		Name = "Auto",
		Size = V.UDim2.new(0, 0, 0, 40),
		AutomaticSize = "X",
		create("Frame")({ Name = "Child", Size = V.UDim2.fromOffset(120, 40) }),
	})
	local r = solveNamed(host, root)
	assert(r.Auto.Width == 120, `the container should grow to its child, got {r.Auto.Width}`)
	assert(r.Child.Width == 120, `and the child keeps its own size, got {r.Child.Width}`)
end

--- The authored size is a FLOOR, not a target. AutomaticSize grows an element to
--- fit its content; it does not shrink it to fit.
local function testAuthoredSizeIsAFloor()
	local host, V, create = fixture()
	local root = create("Frame")({
		Name = "Auto",
		Size = V.UDim2.new(0, 200, 0, 40),
		AutomaticSize = "X",
		create("Frame")({ Name = "Child", Size = V.UDim2.fromOffset(50, 40) }),
	})
	local r = solveNamed(host, root)
	assert(r.Auto.Width == 200, `a smaller child must not shrink the container, got {r.Auto.Width}`)
end

--- UIPadding is part of what the container needs.
local function testPaddingIsIncluded()
	local host, V, create = fixture()
	local root = create("Frame")({
		Name = "Auto",
		Size = V.UDim2.new(0, 0, 0, 40),
		AutomaticSize = "X",
		create("UIPadding")({
			PaddingLeft = V.UDim.new(0, 12),
			PaddingRight = V.UDim.new(0, 12),
		}),
		create("Frame")({ Name = "Child", Size = V.UDim2.fromOffset(100, 40) }),
	})
	local r = solveNamed(host, root)
	assert(r.Auto.Width == 124, `100 of child plus 12 either side is 124, got {r.Auto.Width}`)
end

--- THE BUTTON SHAPE, and the case D1 exists for. A scale-sized node in the
--- middle contributes nothing itself and must not stop the measurement passing
--- THROUGH it -- and must itself end up filling the grown parent.
local function testMeasuresThroughAScaleSizedChild()
	local host, V, create = fixture()
	local root = create("Frame")({
		Name = "Outer",
		Size = V.UDim2.new(0, 0, 0, 40),
		AutomaticSize = "X",
		create("Frame")({
			Name = "Filler",
			Size = V.UDim2.fromScale(1, 1),
			create("Frame")({ Name = "Inner", Size = V.UDim2.fromOffset(90, 40) }),
		}),
	})
	local r = solveNamed(host, root)
	assert(r.Outer.Width == 90, `the outer frame should measure through the filler, got {r.Outer.Width}`)
	--- WITHOUT THE RE-PLACE this is 0: Filler was solved against the outer frame's
	--- floor width before the outer frame grew. The button was the right size and
	--- its only visible part was empty.
	assert(r.Filler.Width == 90, `the scale-sized child must be re-placed against the grown parent, got {r.Filler.Width}`)
	assert(r.Inner.Width == 90, `and its own child keeps its size, got {r.Inner.Width}`)
end

--- THE PADDING ON A SKIPPED NODE STILL COUNTS, which is Button's actual shape.
---
--- `docs/ui/explanation/automatic-size-cycles.md`: "UIPadding works because it is
--- applied AFTER measurement -- it adds to the width". Button puts its horizontal
--- inset on the FACE for that reason, and the Face is scale-sized and therefore
--- skipped. Without carrying its trailing padding the button measured 64 where it
--- wanted 76 and drew 12px on the left and none on the right -- a correct-looking
--- button that is visibly lopsided, which no ink check would notice.
local function testPaddingOnASkippedNodeStillCounts()
	local host, V, create = fixture()
	local root = create("Frame")({
		Name = "Outer",
		Size = V.UDim2.new(0, 0, 0, 40),
		AutomaticSize = "X",
		create("Frame")({
			Name = "Filler",
			Size = V.UDim2.fromScale(1, 1),
			create("UIPadding")({
				PaddingLeft = V.UDim.new(0, 12),
				PaddingRight = V.UDim.new(0, 12),
			}),
			create("Frame")({ Name = "Inner", Size = V.UDim2.fromOffset(50, 40) }),
		}),
	})
	local r = solveNamed(host, root)
	assert(r.Outer.Width == 74, `50 of content plus 12 either side is 74, got {r.Outer.Width}`)
	assert(r.Inner.X == 12, `and the content sits after the left inset, got {r.Inner.X}`)
	assert(r.Filler.X + r.Filler.Width - (r.Inner.X + r.Inner.Width) == 12,
		"with the same inset left over on the right")
end

--- Text still measures, and it is the case that always worked -- so a change to
--- child measurement must not break it.
local function testTextStillMeasures()
	local host, V, create = fixture()
	local root = create("TextLabel")({
		Name = "Label",
		Size = V.UDim2.new(0, 0, 0, 20),
		AutomaticSize = "X",
		Text = "abcde",
	})
	local r = solveNamed(host, root)
	assert(r.Label.Width == 50, `five characters at ten pixels is 50, got {r.Label.Width}`)
end

--- A list layout stacks, and the container grows to the stack.
local function testGrowsToAListLayout()
	local host, V, create = fixture()
	local root = create("Frame")({
		Name = "Auto",
		Size = V.UDim2.new(0, 100, 0, 0),
		AutomaticSize = "Y",
		create("UIListLayout")({ Padding = V.UDim.new(0, 4) }),
		create("Frame")({ Name = "A", Size = V.UDim2.fromOffset(100, 30) }),
		create("Frame")({ Name = "B", Size = V.UDim2.fromOffset(100, 30) }),
	})
	local r = solveNamed(host, root)
	assert(r.Auto.Height == 64, `two 30px rows plus 4px of padding is 64, got {r.Auto.Height}`)
end

--- WHEN NOTHING CAN BE MEASURED, SAY SO. Every descendant is scale-sized, so the
--- container keeps its authored size -- which is correct, and is the "collapsed
--- to its padding" symptom ms-43 M93 spent a session on. Silence about it is what
--- let D1 live for a milestone.
local function testUnmeasurableAxisIsReported()
	local host, V, create = fixture()
	local root = create("Frame")({
		Name = "Auto",
		Size = V.UDim2.new(0, 30, 0, 40),
		AutomaticSize = "X",
		create("Frame")({ Name = "Scaled", Size = V.UDim2.fromScale(1, 1) }),
	})
	local r = solveNamed(host, root)
	assert(r.Auto.Width == 30, `it keeps its authored width, got {r.Auto.Width}`)

	local warnings = Layout.Warnings()
	local named = false
	for _, w in ipairs(warnings) do
		if string.find(w, "Auto", 1, true) and string.find(w, "AutomaticSize.X", 1, true) then
			named = true
		end
	end
	assert(named, `the unmeasurable axis should be reported; warnings were: {table.concat(warnings, " | ")}`)
end

--- AND A LEAF IS NOT A FAILURE. A TextLabel with no children is sized by its
--- text; warning about it would fire on every label on every screen and teach
--- people to ignore the list.
local function testALeafIsNotReported()
	local host, V, create = fixture()
	local root = create("TextLabel")({
		Name = "Leaf",
		Size = V.UDim2.new(0, 0, 0, 20),
		AutomaticSize = "XY",
		Text = "hi",
	})
	solveNamed(host, root)
	for _, w in ipairs(Layout.Warnings()) do
		assert(not string.find(w, "Leaf", 1, true), `a text leaf must not be reported, got: {w}`)
	end
end

T.test("a container grows to an offset child", testGrowsToAnOffsetChild, "math")
T.test("the authored size is a floor, not a target", testAuthoredSizeIsAFloor, "math")
T.test("UIPadding is included in what the container needs", testPaddingIsIncluded, "math")
T.test("measurement passes through a scale-sized child, which is then re-placed", testMeasuresThroughAScaleSizedChild, "math")
T.test("padding on a skipped node still counts", testPaddingOnASkippedNodeStillCounts, "math")
T.test("text still measures", testTextStillMeasures, "math")
T.test("a container grows to a list layout", testGrowsToAListLayout, "math")
T.test("an axis that could not be measured is reported", testUnmeasurableAxisIsReported, "math")
T.test("a text leaf is not reported", testALeafIsNotReported, "math")

return T.run("LayoutAutomaticSize")
