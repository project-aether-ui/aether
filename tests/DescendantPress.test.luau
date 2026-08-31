--!strict
--!tier math
--[=[
	A region receives presses that land on its children (ms-53 D8).

	es9, on the carousel in the native window:

	  "it only works if I click and drag from the gaps between the hover cards,
	   whereas in roblox, I can click anywhere on the carousel to drag. why is the
	   behavior different? things really need to be written in such a way that
	   behavior is guaranteed to be the same in both hosts, otherwise it shouldn't
	   exist in either application at all."

	WHY THEY DIFFERED. The router resolves ONE record -- the topmost thing under
	the pointer -- which is correct for a click and wrong for a gesture that owns
	a REGION. Pressing a card resolved the card, so the carousel beneath it never
	heard about it and could only be dragged from the gaps. Roblox's `InputBegan`
	propagates to every Active ancestor, so the identical code behaved differently
	in each host and neither looked wrong from inside itself.

	THE FIX IS OPT-IN, and that matters as much as the fix. Automatic bubbling
	would hand every button's press to every panel containing it. A region SAYS it
	owns its descendants' presses, once, and no child has to remember anything --
	a child that must remember is a rule the next child does not inherit, which is
	how the two hosts drifted apart to begin with.
]=]
local T = require("@testkit")
local Aether = require("../src/api")

local host = Aether.Host.detect()
host.InstallVocabulary()

local Layout = require("../src/host/Layout")
local PointerRouter = Aether.PointerRouter

local VIEWPORT = { X = 0, Y = 0, Width = 400, Height = 300 }

--- A region with a child on top of it, both pressable. `regionOpts` decides
--- whether the region claims its descendants' presses.
local function fixture(receives: boolean)
	local log: { string } = {}
	local root, child
	local destroy = host.root(function()
		--- A LAYER ROOT, or `ContainsVisible` walks to nil and every press misses.
		local screen = host.create("ScreenGui")({ Name = "Screen", Enabled = true })

		local regionPress = PointerRouter.Pressable({
			ReceivesDescendantPress = receives,
			OnPressed = function()
				table.insert(log, "region")
			end,
		})
		local childPress = PointerRouter.Pressable({
			OnPressed = function()
				table.insert(log, "child")
			end,
		})

		child = host.create("Frame")({
			Name = "Child",
			Size = host.Vocabulary.UDim2.fromOffset(80, 40),
			Position = host.Vocabulary.UDim2.fromOffset(40, 40),
			BackgroundTransparency = 0,
			ZIndex = 5,
			host.action(function(rbx: any)
				childPress.Bind(rbx)
			end),
		})

		root = host.create("Frame")({
			Name = "Region",
			Size = host.Vocabulary.UDim2.fromOffset(300, 200),
			Position = host.Vocabulary.UDim2.fromOffset(10, 10),
			BackgroundTransparency = 0,
			host.action(function(rbx: any)
				regionPress.Bind(rbx)
			end),
			child,
		})
		root.Parent = screen
	end)

	local byName: { [string]: any } = {}
	for _, item in ipairs(Layout.Solve(host.Scene, root, VIEWPORT, host)) do
		host.SetBounds(item.Node, item.Rect.X, item.Rect.Y, item.Rect.Width, item.Rect.Height)
		byName[host.Scene.Name(item.Node) or "?"] = item
	end
	return { Log = log, Rects = byName }, destroy
end

local function pressAt(r: any)
	local cx, cy = r.Rect.X + r.Rect.Width / 2, r.Rect.Y + r.Rect.Height / 2
	PointerRouter.Input.Move(cx, cy)
	PointerRouter.Input.Press(cx, cy)
	PointerRouter.Input.Release(cx, cy)
end

--- THE CASE es9 REPORTED. A press on the child must reach the region too.
local function testAPressOnAChildReachesTheRegion()
	local f, destroy = fixture(true)
	pressAt(f.Rects.Child)

	assert(table.find(f.Log, "child") ~= nil, "the child itself must still be pressed")
	assert(table.find(f.Log, "region") ~= nil,
		`the region claimed descendant presses and did not receive one; log was [{table.concat(f.Log, ", ")}]`)

	destroy()
end

--- AND WITHOUT THE OPT-IN IT MUST NOT. Bubbling everything would hand every
--- button's press to every panel above it, which is a different bug with the
--- same symptom -- a control that fires two handlers.
local function testItDoesNotBubbleByDefault()
	local f, destroy = fixture(false)
	pressAt(f.Rects.Child)

	assert(table.find(f.Log, "child") ~= nil, "the child is pressed")
	assert(table.find(f.Log, "region") == nil,
		`a region that did NOT opt in received a descendant press; log was [{table.concat(f.Log, ", ")}]`)

	destroy()
end

--- The region still receives its OWN presses, which is the case that worked
--- before and must not regress: those are the gaps between the cards.
local function testTheRegionStillReceivesItsOwnPresses()
	local f, destroy = fixture(true)
	--- Bottom-left of the region, clear of the child.
	local r = f.Rects.Region.Rect
	local cx, cy = r.X + 10, r.Y + r.Height - 10
	PointerRouter.Input.Move(cx, cy)
	PointerRouter.Input.Press(cx, cy)

	assert(table.find(f.Log, "region") ~= nil, "a press on the region itself must reach it")
	assert(table.find(f.Log, "child") == nil, "and must not reach the child it missed")

	destroy()
end

T.test("a press on a child reaches a region that claims it", testAPressOnAChildReachesTheRegion, "math")
T.test("it does not bubble without the opt-in", testItDoesNotBubbleByDefault, "math")
T.test("the region still receives its own presses", testTheRegionStillReceivesItsOwnPresses, "math")

return T.run("DescendantPress")
