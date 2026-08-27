--!strict
--!tier math
local ScrollController = require("../../src/controllers/ScrollController")
local T = require("@testkit")

local function testMathCalculations()
	-- computeThumbRatio
	assert(ScrollController.computeThumbRatio(100, 200) == 0.5, "viewport 100 on content 200 is 0.5")
	assert(ScrollController.computeThumbRatio(300, 200) == 1.0, "viewport >= content is 1.0")
	assert(ScrollController.computeThumbRatio(10, 1000, 0.1) == 0.1, "clamps to minRatio 0.1")

	-- computeThumbOffset
	assert(ScrollController.computeThumbOffset(50, 100, 200, 40) == 80, "50% scroll on 160 track is 80")
	assert(ScrollController.computeThumbOffset(0, 100, 200, 40) == 0, "0 scroll is 0 offset")
	assert(ScrollController.computeThumbOffset(100, 100, 200, 40) == 160, "100% scroll is max track travel 160")

	-- computeScrollFromThumb
	assert(ScrollController.computeScrollFromThumb(80, 200, 40, 100) == 50, "80 thumb on 160 travel is 50 scroll")
	assert(ScrollController.computeScrollFromThumb(0, 200, 40, 100) == 0, "0 thumb is 0 scroll")
	assert(ScrollController.computeScrollFromThumb(160, 200, 40, 100) == 100, "160 thumb is 100 max scroll")
end

local function testControllerStateAndClamping()
	local controller = ScrollController.new({
		ViewportSize = 200,
		ContentSize = 600,
		StepSize = 50,
	})

	assert(controller.GetOffset() == 0, "initial offset is 0")
	assert(controller.GetMaxScroll() == 400, "max scroll is 400")

	controller.ScrollBy(100)
	assert(controller.GetOffset() == 100, "offset is 100 after scrollBy")

	controller.ScrollTo(500)
	assert(controller.GetOffset() == 400, "clamped to maxScroll 400")

	controller.ScrollTo(-50)
	assert(controller.GetOffset() == 0, "clamped to min 0")

	controller.ScrollToEnd()
	assert(controller.GetOffset() == 400, "scrollToEnd is 400")

	controller.ScrollToStart()
	assert(controller.GetOffset() == 0, "scrollToStart is 0")
end

local function testPagingAndStepping()
	local controller = ScrollController.new({
		ViewportSize = 200,
		ContentSize = 1000,
		StepSize = 40,
		PageStepRatio = 0.8,
	})

	controller.PageDown()
	assert(controller.GetOffset() == 160, "pageDown is 200 * 0.8 = 160")

	controller.PageDown()
	assert(controller.GetOffset() == 320, "pageDown twice is 320")

	controller.PageUp()
	assert(controller.GetOffset() == 160, "pageUp returns to 160")
end

local function testDynamicDimensionUpdates()
	local controller = ScrollController.new({
		ViewportSize = 200,
		ContentSize = 500,
		InitialOffset = 250,
	})

	assert(controller.GetOffset() == 250, "offset is 250")

	-- Content shrinks to 300 (max scroll is now 100)
	controller.SetDimensions(200, 300)
	assert(controller.GetMaxScroll() == 100, "max scroll is 100")
	assert(controller.GetOffset() == 100, "offset auto-clamped to new max 100")
end

local function testSubscription()
	local controller = ScrollController.new({
		ViewportSize = 200,
		ContentSize = 600,
	})

	local lastOffset = 0
	local calls = 0

	local unsub = controller.Subscribe(function(offset)
		lastOffset = offset
		calls += 1
	end)

	controller.ScrollTo(150)
	assert(calls == 1, "listener fired")
	assert(lastOffset == 150, "received offset 150")

	unsub()
	controller.ScrollTo(200)
	assert(calls == 1, "listener unsubscribed")
end

T.test("math calculations", testMathCalculations, "math")
T.test("controller state and clamping", testControllerStateAndClamping, "math")
T.test("paging and stepping", testPagingAndStepping, "math")
T.test("dynamic dimension updates", testDynamicDimensionUpdates, "math")
T.test("subscription notification", testSubscription, "math")

return T.run("ScrollController")
