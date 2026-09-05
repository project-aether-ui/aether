--!strict
--!tier math
local T = require("@testkit")
local Aether = require("../../src/api")
local host = Aether.Host.detect()
local ScrollController = require("../../src/controllers/ScrollController")
local VirtualList = require("../../src/primitives/VirtualList")

local function testVirtualListMountWindow()
	local items = {}
	for i = 1, 500 do
		table.insert(items, { Id = `item_{i}`, Name = `Row {i}` })
	end

	local controller = ScrollController.new({
		Orientation = "Vertical",
		ViewportSize = 300,
	})

	local destroy = host.root(function()
		local mountedTable = {}
		local renderCount = 0

		local list = VirtualList({
			Controller = controller,
			Items = items,
			Estimate = 30,
			Overscan = 2,
			_MountedForTest = function(m)
				mountedTable = m
			end,
			RenderItem = function(item, index)
				renderCount += 1
				return {
					Name = item.Name,
					Position = nil,
					Destroy = function() end,
				}
			end,
		})

		assert(list ~= nil, "VirtualList created")
		assert(controller.GetContentSize() == 500 * 30, "total content height calculated correctly")

		-- Viewport is 300px, item height is 30px => 10 items visible + 2 overscan = ~12-14 items mounted
		local count = 0
		for _ in pairs(mountedTable) do
			count += 1
		end

		assert(count >= 10 and count <= 16, `expected between 10 and 16 mounted items, got {count}`)
		assert(mountedTable[1] ~= nil, "item 1 is mounted")

		-- Scroll down to 600px (item 21)
		controller.ScrollTo(600)

		local countAfter = 0
		for _ in pairs(mountedTable) do
			countAfter += 1
		end
		assert(countAfter >= 10 and countAfter <= 16, `expected ~14 mounted items after scroll, got {countAfter}`)
		assert(mountedTable[1] == nil, "item 1 unmounted when scrolled out of range")
		assert(mountedTable[21] ~= nil, "item 21 mounted when scrolled into range")
	end)
	destroy()
end

local function testVirtualListRepositioning()
	local items = {
		{ Id = "A" }, { Id = "B" }, { Id = "C" }, { Id = "D" }, { Id = "E" },
	}

	local controller = ScrollController.new({
		Orientation = "Vertical",
		ViewportSize = 100,
	})

	local destroy = host.root(function()
		local mountedTable = {}
		VirtualList({
			Controller = controller,
			Items = items,
			Estimate = 20,
			Overscan = 1,
			_MountedForTest = function(m)
				mountedTable = m
			end,
			RenderItem = function(item, index)
				return {
					Id = item.Id,
					Position = nil,
					Destroy = function() end,
				}
			end,
		})

		assert(mountedTable[1] ~= nil, "item 1 mounted")
		local inst1 = mountedTable[1]

		-- Scroll by 10px
		controller.ScrollBy(10)

		-- Verify instance was reused and not recreated
		assert(mountedTable[1] == inst1, "same instance reused on small scroll")
	end)
	destroy()
end

T.test("virtual list mounts only visible window", testVirtualListMountWindow, "math")
T.test("virtual list repositions existing instances on scroll", testVirtualListRepositioning, "math")

return T.run("VirtualList")
