--!strict
--!tier math
local T = require("@testkit")
local Aether = require("../../src/api")
local host = Aether.Host.detect()
local ScrollController = require("../../src/controllers/ScrollController")
local ScrollArea = require("../../src/primitives/ScrollArea")
local Scrollbar = require("../../src/primitives/Scrollbar")

local function testScrollAreaConstruction()
	local controller = ScrollController.new({
		ViewportSize = 300,
		ContentSize = 900,
	})

	local scrolledCount = 0
	local lastPosY = 0

	local destroy = host.root(function()
		local area = ScrollArea({
			Controller = controller,
			OnScrolled = function(pos: any)
				scrolledCount += 1
				lastPosY = if type(pos) == "table" and pos.Y then pos.Y elseif typeof(pos) == "Vector2" then pos.Y else 0
			end,
		})

		assert(area ~= nil, "ScrollArea constructed")
		assert(controller.GetMaxScroll() == 600, "max scroll is 600")

		controller.ScrollBy(150)
		assert(scrolledCount == 1, "OnScrolled triggered")
		assert(lastPosY == 150, "lastPosY is 150")
	end)
	destroy()
end

local function testScrollbarPrimitive()
	local destroy = host.root(function()
		local bar = Scrollbar({
			Axis = "Vertical",
			TrackLength = 200,
			ThumbSize = 40,
			ThumbOffset = 80,
		})

		assert(bar ~= nil, "Scrollbar constructed")
	end)
	destroy()
end

T.test("scroll area construction and controller sync", testScrollAreaConstruction, "math")
T.test("scrollbar primitive construction", testScrollbarPrimitive, "math")

return T.run("ScrollArea")
