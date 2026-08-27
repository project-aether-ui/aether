--!strict
--!tier math
local T = require("@testkit")
local FloatingMath = require("../../src/FloatingMath")

local function testTooltipTopPlacement()
	local targetAnchor = { X = 500, Y = 300, Width = 100, Height = 40 }
	local tooltipSize = { X = 0, Y = 0, Width = 120, Height = 28 }
	local viewport = { X = 0, Y = 0, Width = 1920, Height = 1080 }

	local res = FloatingMath.ComputePosition(targetAnchor, tooltipSize, viewport, {
		Placement = "top",
		Offset = 6,
		AutoFlip = true,
	} :: any)

	assert(res.Y == 300 - 28 - 6, "positioned 6px above anchor top")
	assert(res.Side == "top", "side is top")
	-- Target center X = 500 + 50 = 550. Tooltip X = 550 - 60 = 490.
	assert(res.X == 490, "centered horizontally on target")
end

local function testTooltipFlipAtTopEdge()
	local targetAnchor = { X = 500, Y = 10, Width = 100, Height = 40 }
	local tooltipSize = { X = 0, Y = 0, Width = 120, Height = 28 }
	local viewport = { X = 0, Y = 0, Width = 1920, Height = 1080 }

	local res = FloatingMath.ComputePosition(targetAnchor, tooltipSize, viewport, {
		Placement = "top",
		Offset = 6,
		AutoFlip = true,
	} :: any)

	assert(res.DidFlip == true, "flipped to bottom when top clips")
	assert(res.Side == "bottom", "side is bottom")
	assert(res.Y == 10 + 40 + 6, "positioned below target")
end

T.test("tooltip top placement", testTooltipTopPlacement, "math")
T.test("tooltip auto-flip at top edge", testTooltipFlipAtTopEdge, "math")

return T.run("Tooltip")

