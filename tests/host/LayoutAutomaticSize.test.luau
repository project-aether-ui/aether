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

--- THE BUTTON SHAPE, and the case D1 exists for -- REWRITTEN against the engine.
---
--- This asserted that measurement passes THROUGH a scale-sized child: that the
--- Filler contributes nothing itself and the Outer frame measures the 90 of
--- Inner behind it. Two Studio-verified conformance cases say otherwise.
---
--- `automatic_size_with_a_scale_sized_child` put a `{1,0, 0.5,20}` child in an
--- AutomaticSize.Y frame on a 200-tall surface. Pass-through predicts 20, and
--- excluding the child predicts 0. The engine returned 120, which is
--- `0.5 x 200 + 20` -- the child IS measured, with its scale resolved against the
--- space available to the parent.
--- `automatic_size_scale_child_under_a_small_parent` then separated "available
--- space" from "the surface" with a smaller grandparent, and confirmed the
--- former.
---
--- So the Filler resolves to the full 400 offered to Outer, and Outer fits it.
--- The suite could not run for months, so nothing flagged that it had been
--- asserting a third behaviour -- one matching neither the engine nor the
--- implementation it was written against.
---
--- WHAT THIS MEANS FOR BUTTON IS AN OPEN QUESTION, and it is a real one: a
--- `fromScale(1, 1)` face inside an AutomaticSize.X parent can no longer hug its
--- label, because the face always measures to the space on offer. If Button
--- still has that shape it fills its container in Roblox too, and always has.
--- `automatic_size_full_scale_child` is the case that settles it; it is
--- `asserted` until a Studio pass.
local function testAScaleSizedChildMeasuresAgainstAvailableSpace()
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
	assert(r.Outer.Width == 400,
		`the scale-sized child resolves against the 400 on offer, got {r.Outer.Width}`)
	--- THE RE-PLACE STILL MATTERS, and is the half of this case that survives
	--- unchanged. Filler must end up filling the grown parent rather than the
	--- floor width it was first solved against -- the failure where the button is
	--- the right size and its only visible part is empty.
	assert(r.Filler.Width == 400,
		`the scale-sized child must be re-placed against the grown parent, got {r.Filler.Width}`)
	assert(r.Inner.Width == 90, `and its own child keeps its size, got {r.Inner.Width}`)
end

--- PADDING ON A SCALE-SIZED CHILD -- and why this case lost its original point.
---
--- It used to assert that Outer measured 74: the 50 of Inner plus 12 of inset
--- either side, carried up from a Face that measurement had skipped. That
--- mattered because a skipped node's trailing padding was otherwise dropped, and
--- the button drew 12px on the left and none on the right -- visibly lopsided,
--- and invisible to an ink check.
---
--- Nothing is skipped now, so there is nothing to carry: the Face measures to the
--- space on offer and Outer fits that. The lopsided-button failure is gone by
--- construction rather than by the fix this case was pinning.
---
--- What is still worth asserting is that the padding INSETS ITS CONTENT, which is
--- the part that would silently regress.
local function testPaddingOnAScaleSizedChildInsetsItsContent()
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
	assert(r.Outer.Width == 400, `the face resolves against the space on offer, got {r.Outer.Width}`)
	assert(r.Inner.X == 12, `and the content sits after the left inset, got {r.Inner.X}`)
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

--- THIS SHAPE IS NO LONGER UNMEASURABLE, though the reporting stays.
---
--- This asserted that a frame whose every descendant is scale-sized keeps its
--- authored width, and that `Layout.Warnings()` names it -- the "collapsed to its
--- padding" symptom that ms-43 M93 spent a session on, and whose silence let D1
--- live for a milestone.
---
--- The conformance fix removed the condition FOR THIS TREE: a scale-sized child
--- resolves against the space available to its parent, so there is something to
--- measure and the axis resolves. The warning is therefore correct to stay quiet
--- here, and it is the assertion that had to change rather than the diagnostic.
---
--- `Layout.Warnings()` is KEPT. A first pass at this deleted it, on a grep that
--- found `warnings` cleared each solve and seemingly appended to from nowhere --
--- the pattern missed `table.insert(warnings, text)` inside the emit helper. The
--- guard still fires for an axis that genuinely measures nothing, which is the
--- next tree rather than no tree.
local function testAnAutoAxisAlwaysResolves()
	local host, V, create = fixture()
	local root = create("Frame")({
		Name = "Auto",
		Size = V.UDim2.new(0, 30, 0, 40),
		AutomaticSize = "X",
		create("Frame")({ Name = "Scaled", Size = V.UDim2.fromScale(1, 1) }),
	})
	local r = solveNamed(host, root)
	assert(r.Auto.Width == 400,
		`the scale child resolves against the space on offer, and the authored 30 is a floor, `
			.. `got {r.Auto.Width}`)
	assert(r.Scaled.Width == 400, `and it fills the grown parent, got {r.Scaled.Width}`)
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
T.test("a scale-sized child measures against the available space", testAScaleSizedChildMeasuresAgainstAvailableSpace, "math")
T.test("padding on a scale-sized child insets its content", testPaddingOnAScaleSizedChildInsetsItsContent, "math")
T.test("text still measures", testTextStillMeasures, "math")
T.test("a container grows to a list layout", testGrowsToAListLayout, "math")
T.test("an auto axis always resolves", testAnAutoAxisAlwaysResolves, "math")
T.test("a text leaf is not reported", testALeafIsNotReported, "math")

return T.run("LayoutAutomaticSize")
