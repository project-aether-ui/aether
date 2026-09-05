--!strict
--!tier math
local T = require("@testkit")
local Aether = require("../../src/api")
local host = Aether.Host.detect()
local ScrollController = require("../../src/controllers/ScrollController")
local ScrollArea = require("../../src/primitives/ScrollArea")
local ScrollBar = require("../../src/primitives/Scrollbar")
local ScrollingFrame = require("../../src/primitives/ScrollingFrame")

local function testScrollingFrameConstruction()
	local controller = ScrollController.new({
		ViewportSize = 300,
		ContentSize = 900,
	})

	local destroy = host.root(function()
		local frame = ScrollingFrame({
			Controller = controller,
			Presentation = "Inset",
			ScrollBarWidth = 8,
			AutoHide = true,
			Content = function()
				return {}
			end,
		})

		assert(frame ~= nil, "ScrollingFrame constructed")
		assert(controller.GetMaxScroll() == 600, "controller maintains max scroll")
	end)
	destroy()
end

local function testScrollingFrameOverlay()
	local destroy = host.root(function()
		local frame = ScrollingFrame({
			Presentation = "Overlay",
			ScrollBarWidth = 10,
			ThumbColor = { R = 1, G = 1, B = 1 },
		})

		assert(frame ~= nil, "Overlay ScrollingFrame constructed")
	end)
	destroy()
end

local function testScrollingFrameVirtualize()
	local items = { "Row 1", "Row 2", "Row 3" }
	local controller = ScrollController.new({
		ViewportSize = 300,
	})

	local destroy = host.root(function()
		local frame = ScrollingFrame({
			Controller = controller,
			Virtualize = {
				Items = items,
				Estimate = 40,
				RenderItem = function(item, idx)
					return { Name = item }
				end,
			},
		})

		assert(frame ~= nil, "Virtualized ScrollingFrame constructed")
		assert(controller.GetContentSize() == 120, "content size set by virtualization index (3 * 40)")
	end)
	destroy()
end

T.test("scrolling frame compound assembly construction", testScrollingFrameConstruction, "math")
T.test("scrolling frame overlay construction", testScrollingFrameOverlay, "math")
T.test("scrolling frame with virtualize prop", testScrollingFrameVirtualize, "math")

return T.run("ScrollingFrame")
