--!strict
--!tier math
local T = require("@testkit")
local FloatingMath = require("../../src/FloatingMath")

local function testContextMenuCursorPlacement()
	local cursorAnchor = { X = 450, Y = 300, Width = 0, Height = 0 }
	local menuSize = { X = 0, Y = 0, Width = 180, Height = 220 }
	local viewport = { X = 0, Y = 0, Width = 1920, Height = 1080 }

	local res = FloatingMath.ComputePosition(cursorAnchor, menuSize, viewport, {
		Placement = "bottom-start",
		Offset = 2,
		AutoFlip = true,
	} :: any)

	assert(res.X == 450, "positioned at cursor X")
	assert(res.Y == 302, "positioned 2px below cursor Y")
	assert(res.Placement == "bottom-start", "placement is bottom-start")
end

local function testContextMenuBoundaryFlip()
	-- Cursor right near bottom-right screen corner
	local cursorAnchor = { X = 1900, Y = 1050, Width = 0, Height = 0 }
	local menuSize = { X = 0, Y = 0, Width = 180, Height = 200 }
	local viewport = { X = 0, Y = 0, Width = 1920, Height = 1080 }

	local res = FloatingMath.ComputePosition(cursorAnchor, menuSize, viewport, {
		Placement = "bottom-start",
		Offset = 2,
		AutoFlip = true,
		ClampToViewport = true,
		ViewportPadding = 8,
	} :: any)

	assert(res.DidFlip == true, "menu flipped because bottom clipped")
	assert(res.Side == "top", "side flipped to top")
	assert(res.X == 1732, "X clamped inside viewport padding (1920 - 180 - 8 = 1732)")
end

T.test("context menu cursor placement", testContextMenuCursorPlacement, "math")
T.test("context menu boundary flip & clamp", testContextMenuBoundaryFlip, "math")

return T.run("ContextMenu")
