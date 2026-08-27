--!strict
--!tier math
local FloatingMath = require("../src/FloatingMath")
local T = require("@testkit")

local function testStandardBottomPlacements()
	local anchor = { X = 100, Y = 100, Width = 100, Height = 40 }
	local floating = { X = 0, Y = 0, Width = 120, Height = 80 }
	local viewport = { X = 0, Y = 0, Width = 1920, Height = 1080 }

	-- 1. bottom-start
	local res1 = FloatingMath.ComputePosition(anchor, floating, viewport, {
		Placement = "bottom-start",
		Offset = 8,
		AutoFlip = false,
	} :: any)
	assert(res1.X == 100, "bottom-start X is anchor.X")
	assert(res1.Y == 148, "bottom-start Y is anchor.Y + height + offset")
	assert(res1.Placement == "bottom-start", "placement is bottom-start")

	-- 2. bottom (centered)
	local res2 = FloatingMath.ComputePosition(anchor, floating, viewport, {
		Placement = "bottom",
		Offset = 8,
		AutoFlip = false,
	} :: any)
	assert(res2.X == 90, "bottom X is centered")
	assert(res2.Y == 148, "bottom Y is anchor.Y + height + offset")
	assert(res2.Placement == "bottom", "placement is bottom")

	-- 3. bottom-end
	local res3 = FloatingMath.ComputePosition(anchor, floating, viewport, {
		Placement = "bottom-end",
		Offset = 8,
		AutoFlip = false,
	} :: any)
	assert(res3.X == 80, "bottom-end X aligns right edges")
	assert(res3.Y == 148, "bottom-end Y is anchor.Y + height + offset")
	assert(res3.Placement == "bottom-end", "placement is bottom-end")
end

local function testCardinalPlacements()
	local anchor = { X = 200, Y = 200, Width = 100, Height = 50 }
	local floating = { X = 0, Y = 0, Width = 80, Height = 60 }
	local viewport = { X = 0, Y = 0, Width = 1920, Height = 1080 }

	-- 1. top-start
	local resTop = FloatingMath.ComputePosition(anchor, floating, viewport, {
		Placement = "top-start",
		Offset = 10,
		AutoFlip = false,
	} :: any)
	assert(resTop.X == 200, "top-start X is 200")
	assert(resTop.Y == 130, "top-start Y is 200 - 60 - 10 = 130")
	assert(resTop.Placement == "top-start", "placement is top-start")

	-- 2. right-start
	local resRight = FloatingMath.ComputePosition(anchor, floating, viewport, {
		Placement = "right-start",
		Offset = 10,
		AutoFlip = false,
	} :: any)
	assert(resRight.X == 310, "right-start X is 200 + 100 + 10 = 310")
	assert(resRight.Y == 200, "right-start Y is 200")
	assert(resRight.Placement == "right-start", "placement is right-start")

	-- 3. left-start
	local resLeft = FloatingMath.ComputePosition(anchor, floating, viewport, {
		Placement = "left-start",
		Offset = 10,
		AutoFlip = false,
	} :: any)
	assert(resLeft.X == 110, "left-start X is 200 - 80 - 10 = 110")
	assert(resLeft.Y == 200, "left-start Y is 200")
	assert(resLeft.Placement == "left-start", "placement is left-start")
end

local function testAutoFlipBehavior()
	local viewport = { X = 0, Y = 0, Width = 800, Height = 600 }
	local anchor = { X = 100, Y = 550, Width = 100, Height = 40 } -- Near bottom
	local floating = { X = 0, Y = 0, Width = 100, Height = 80 }

	local res = FloatingMath.ComputePosition(anchor, floating, viewport, {
		Placement = "bottom-start",
		Offset = 5,
		AutoFlip = true,
		ViewportPadding = 8,
	} :: any)

	assert(res.DidFlip == true, "auto-flip was triggered")
	assert(res.Side == "top", "side flipped to top")
	assert(res.Placement == "top-start", "placement is top-start")
	assert(res.Y == 465, "Y is flipped to above anchor (550 - 80 - 5 = 465)")
end

local function testViewportClamping()
	local viewport = { X = 0, Y = 0, Width = 500, Height = 500 }
	local anchor = { X = 480, Y = 100, Width = 50, Height = 30 } -- Near right edge
	local floating = { X = 0, Y = 0, Width = 100, Height = 50 }

	local res = FloatingMath.ComputePosition(anchor, floating, viewport, {
		Placement = "bottom-start",
		Offset = 5,
		AutoFlip = false,
		ClampToViewport = true,
		ViewportPadding = 10,
	} :: any)

	assert(res.X == 390, "X is clamped within viewport - padding (500 - 100 - 10 = 390)")
	assert(res.Y == 135, "Y is 100 + 30 + 5 = 135")
end

T.test("standard bottom placements", testStandardBottomPlacements, "math")
T.test("cardinal placements (top, left, right)", testCardinalPlacements, "math")
T.test("auto-flip behavior near boundary", testAutoFlipBehavior, "math")
T.test("viewport boundary clamping", testViewportClamping, "math")

return T.run("FloatingMath")
