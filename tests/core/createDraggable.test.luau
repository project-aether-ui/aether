--!strict
--!tier math
--[=[
	aether · core/createDraggable.

	NO VIDE, NO ROUTER, NO TREE, matching createPressable.test.luau's own
	shape: the shared `tests/support/fakeRouter` fixture's `OnPointerMove`
	records what it was given and fires pointer moves on demand, and
	`unsubscribed()` is how a destroy is asserted rather than inferred.
	`Start`/`Stop` are called directly, the way a caller's own press
	handler would call them -- this machine never creates a press itself.
]=]
local T = require("@testkit")
local createDraggable = require("../../src/core/createDraggable").createDraggable
local router = require("../support/fakeRouter").router

local function testItRefusesToRunWithoutARouter()
	local ok = pcall(function()
		createDraggable({ Router = nil :: any, Axis = "Vertical" })
	end)
	assert(not ok, "a machine with no router must say so rather than doing nothing quietly")
end

local function testNoDragBeforeStart()
	local r = router()
	local d = createDraggable({ Router = r, Axis = "Vertical" })

	assert(not d.IsDragging(), "nothing is dragging before Start")
	r.move(0, 50)
	assert(not d.IsDragging(), "a move with no Start should not begin a drag")
end

local function testVerticalDeltaTracksY()
	local r = router()
	local seen: { number } = {}
	local d = createDraggable({
		Router = r,
		Axis = "Vertical",
		OnDrag = function(delta: number, _startValue: number)
			table.insert(seen, delta)
		end,
	})

	d.Start(0, 10, 100)
	r.move(10, 130)
	r.move(10, 90)

	assert(seen[1] == 30, `a downward move of 30 should report delta 30, got {seen[1]}`)
	assert(seen[2] == -10, `a move back past the start should report a negative delta, got {seen[2]}`)
end

local function testHorizontalDeltaTracksX()
	local r = router()
	local seen: { number } = {}
	local d = createDraggable({
		Router = r,
		Axis = "Horizontal",
		OnDrag = function(delta: number, _startValue: number)
			table.insert(seen, delta)
		end,
	})

	d.Start(0, 200, 0)
	r.move(260, 0)

	assert(seen[1] == 60, `a horizontal move should read X, not Y, got {seen[1]}`)
end

local function testStartValueSurvivesUnchanged()
	local r = router()
	local pairs_: { { number } } = {}
	local d = createDraggable({
		Router = r,
		Axis = "Vertical",
		OnDrag = function(delta: number, startValue: number)
			table.insert(pairs_, { delta, startValue })
		end,
	})

	d.Start(42, 0, 0)
	r.move(0, 5)

	assert(pairs_[1][2] == 42, `startValue must be handed back unchanged, got {pairs_[1][2]}`)
end

local function testStopEndsTheDragAndFiresOnDragEnd()
	local r = router()
	local ended = 0
	local d = createDraggable({
		Router = r,
		Axis = "Vertical",
		OnDragEnd = function()
			ended += 1
		end,
	})

	d.Start(0, 0, 0)
	assert(d.IsDragging(), "a started drag should read as dragging")

	d.Stop()
	assert(not d.IsDragging(), "a stopped drag should no longer read as dragging")
	assert(ended == 1, "OnDragEnd should fire exactly once")

	local movedAfterStop = false
	local d2 = createDraggable({
		Router = r,
		Axis = "Vertical",
		OnDrag = function()
			movedAfterStop = true
		end,
	})
	d2.Start(0, 0, 0)
	d2.Stop()
	r.move(0, 999)
	assert(not movedAfterStop, "a move after Stop should not fire OnDrag")
end

local function testStopIsIdempotent()
	local r = router()
	local ended = 0
	local d = createDraggable({
		Router = r,
		Axis = "Vertical",
		OnDragEnd = function()
			ended += 1
		end,
	})

	d.Start(0, 0, 0)
	d.Stop()
	d.Stop()

	assert(ended == 1, `Stop called twice should fire OnDragEnd once, got {ended}`)
end

local function testOnDragStartFiresOnStart()
	local r = router()
	local started = 0
	local d = createDraggable({
		Router = r,
		Axis = "Vertical",
		OnDragStart = function()
			started += 1
		end,
	})

	d.Start(0, 0, 0)
	assert(started == 1, "OnDragStart should fire when Start is called")
end

local function testDestroyReleasesTheRegistrationAndStopsDragging()
	local r = router()
	local d = createDraggable({ Router = r, Axis = "Vertical" })

	d.Start(0, 0, 0)
	d.Destroy()

	assert(r.unsubscribed(), "destroy should release the OnPointerMove registration")
	assert(not d.IsDragging(), "a destroyed draggable is not dragging")
end

local function testWritesGoThroughTheSuppliedSource()
	local writes = 0
	local r = router()
	local d = createDraggable({
		Router = r,
		Axis = "Vertical",
		Source = function<T>(initial: T)
			local value = initial
			return function(...): T
				if select("#", ...) > 0 then
					writes += 1
					value = (select(1, ...) :: any) :: T
				end
				return value
			end :: any
		end,
	})

	d.Start(0, 0, 0)
	d.Stop()

	assert(writes == 2, `every IsDragging change should go through the supplied source, got {writes}`)
end

T.test("it refuses to run without a router", testItRefusesToRunWithoutARouter, "math")
T.test("no drag before Start", testNoDragBeforeStart, "math")
T.test("vertical delta tracks Y", testVerticalDeltaTracksY, "math")
T.test("horizontal delta tracks X", testHorizontalDeltaTracksX, "math")
T.test("startValue survives unchanged", testStartValueSurvivesUnchanged, "math")
T.test("Stop ends the drag and fires OnDragEnd", testStopEndsTheDragAndFiresOnDragEnd, "math")
T.test("Stop is idempotent", testStopIsIdempotent, "math")
T.test("OnDragStart fires on Start", testOnDragStartFiresOnStart, "math")
T.test("destroy releases the registration and stops dragging", testDestroyReleasesTheRegistrationAndStopsDragging, "math")
T.test("writes go through the supplied source", testWritesGoThroughTheSuppliedSource, "math")

return T.run("createDraggable")
