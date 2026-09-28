--!strict
--!tier math
--[=[
	aether · core/createSlider.

	NO VIDE, NO ROUTER, NO TREE, matching createDraggable.test.luau's own
	shape: the shared `tests/support/fakeRouter` fixture's `OnPointerMove`
	records what it was given and fires pointer moves on demand.
	`GetThumbProps().OnPressed`/`OnReleased` are called directly, the way a
	caller's own press handle would call them -- this machine never creates
	a press itself, and this suite never binds an element.
]=]
local T = require("@testkit")
local createSlider = require("../../src/core/createSlider").createSlider
local router = require("../support/fakeRouter").router

local function testDraggingPastMaxClamps()
	local r = router()
	local seen: { number } = {}
	local slider = createSlider({
		Router = r,
		Min = 0,
		Max = 10,
		TrackLength = 100,
		OnChange = function(v: number)
			table.insert(seen, v)
		end,
	})

	local thumb = slider.GetThumbProps()
	thumb.OnPressed(0, 0)
	-- delta 200 over a 100-length track spanning a 10-wide range is 20 raw --
	-- twice past Max.
	r.move(200, 0)

	assert(seen[1] == 10, `dragging past Max should clamp to Max, got {seen[1]}`)
	assert(slider.Value() == 10, `Value() should agree with the clamped OnChange, got {slider.Value()}`)
end

local function testDraggingBeforeMinClamps()
	local r = router()
	local seen: { number } = {}
	local slider = createSlider({
		Router = r,
		Min = 0,
		Max = 10,
		TrackLength = 100,
		InitialValue = 5,
		OnChange = function(v: number)
			table.insert(seen, v)
		end,
	})

	local thumb = slider.GetThumbProps()
	thumb.OnPressed(0, 0)
	-- starting at 5, a delta of -200 (raw -15) is well before Min.
	r.move(-200, 0)

	assert(seen[1] == 0, `dragging before Min should clamp to Min, got {seen[1]}`)
end

local function testStepSnapsToNearestValidValue()
	local r = router()
	local seen: { number } = {}
	local slider = createSlider({
		Router = r,
		Min = 0,
		Max = 100,
		Step = 10,
		TrackLength = 100,
		OnChange = function(v: number)
			table.insert(seen, v)
		end,
	})

	local thumb = slider.GetThumbProps()
	thumb.OnPressed(0, 0)
	-- delta 37 over a 100-length track spanning a 100-wide range is raw 37,
	-- which should snap to the nearest multiple of 10 from Min (0): 40.
	r.move(37, 0)

	assert(seen[1] == 40, `raw 37 with Step 10 should snap to 40, got {seen[1]}`)
end

--- THE BOUNDARY EDGE CASE named in this sprint's own brief: snapping a value
--- near the edge of the range can push it back OUT of range, and the second
--- clamp (after stepping) is what catches that. `Min = 0, Max = 10, Step = 3`
--- dragged to the clamped edge, raw 9.5, must settle on 9 -- not on 12, which
--- would be an unclamped snap past Max.
local function testSnapNearBoundaryStaysInRange()
	local r = router()
	local seen: { number } = {}
	local slider = createSlider({
		Router = r,
		Min = 0,
		Max = 10,
		Step = 3,
		TrackLength = 1,
		OnChange = function(v: number)
			table.insert(seen, v)
		end,
	})

	local thumb = slider.GetThumbProps()
	thumb.OnPressed(0, 0)
	-- TrackLength 1 and a range of 10 means delta IS the raw value: 9.5.
	r.move(9.5, 0)

	assert(seen[1] == 9, `raw 9.5 with Min=0 Max=10 Step=3 should snap to 9 and stay in range, got {seen[1]}`)
	assert(seen[1] <= 10 and seen[1] >= 0, `the resolved value must never leave [Min, Max], got {seen[1]}`)
end

--- A second, sharper version of the same trap: snapping from an already
--- clamped-to-Max value can overshoot Max by a whole step, and only the
--- clamp AFTER stepping catches it. `Min = 0, Max = 9, Step = 5` dragged past
--- Max clamps the raw value to 9 first; `round(9 / 5) = 2`, `0 + 2*5 = 10`,
--- one whole step past Max -- the second clamp must bring it back to 9.
local function testSnapAfterClampToMaxStaysInRange()
	local r = router()
	local seen: { number } = {}
	local slider = createSlider({
		Router = r,
		Min = 0,
		Max = 9,
		Step = 5,
		TrackLength = 1,
		OnChange = function(v: number)
			table.insert(seen, v)
		end,
	})

	local thumb = slider.GetThumbProps()
	thumb.OnPressed(0, 0)
	r.move(999, 0)

	assert(seen[1] == 9, `a raw drag far past Max should clamp to Max (9) even after stepping, got {seen[1]}`)
end

local function testOnChangeNeverFiresWithARawDelta()
	local r = router()
	local seen: { number } = {}
	local slider = createSlider({
		Router = r,
		Min = 0,
		Max = 10,
		TrackLength = 100,
		OnChange = function(v: number)
			table.insert(seen, v)
		end,
	})

	local thumb = slider.GetThumbProps()
	thumb.OnPressed(0, 0)
	r.move(1000, 0)
	r.move(-1000, 0)
	r.move(50, 0)

	for _, v in ipairs(seen) do
		assert(v >= 0 and v <= 10, `OnChange must never see a value outside [Min, Max], got {v}`)
	end
	assert(seen[1] == 10 and seen[2] == 0 and seen[3] == 5, "OnChange should report the resolved value, not the raw delta")
end

local function testUncontrolledValueStartsAtInitialValueResolved()
	local r = router()
	local slider = createSlider({
		Router = r,
		Min = 0,
		Max = 10,
		Step = 3,
		InitialValue = 4,
	})

	assert(slider.Value() == 3, `InitialValue 4 with Step 3 should resolve to 3 before any drag, got {slider.Value()}`)
end

local function testControlledNeverWritesItsOwnValue()
	local r = router()
	local external = 5
	local seen: { number } = {}
	local slider = createSlider({
		Router = r,
		Min = 0,
		Max = 10,
		TrackLength = 100,
		Value = function()
			return external
		end,
		OnChange = function(v: number)
			table.insert(seen, v)
		end,
	})

	local thumb = slider.GetThumbProps()
	thumb.OnPressed(0, 0)
	r.move(20, 0)

	assert(slider.Value() == 5, `a controlled slider must read through Value and never write it, got {slider.Value()}`)
	assert(seen[1] == 7, `OnChange should still fire with the resolved value even though nothing here owns it, got {seen[1]}`)
end

local function testStopEndsTheDrag()
	local r = router()
	local slider = createSlider({
		Router = r,
		Min = 0,
		Max = 10,
		TrackLength = 100,
	})

	local thumb = slider.GetThumbProps()
	assert(not slider.IsDragging(), "nothing is dragging before a press")
	thumb.OnPressed(0, 0)
	assert(slider.IsDragging(), "a pressed thumb should read as dragging")
	thumb.OnReleased()
	assert(not slider.IsDragging(), "a released thumb should no longer read as dragging")
end

local function testGetRootPropsExposesTheRange()
	local r = router()
	local slider = createSlider({
		Router = r,
		Min = 2,
		Max = 8,
		Step = 2,
	})

	local root = slider.GetRootProps()
	assert(root.Min == 2, "GetRootProps should expose Min")
	assert(root.Max == 8, "GetRootProps should expose Max")
	assert(root.Step == 2, "GetRootProps should expose Step")
	assert(root.Value() == slider.Value(), "GetRootProps' Value should agree with the machine's own Value")
end

local function testItRefusesToRunWithoutARouter()
	local ok = pcall(function()
		createSlider({ Router = nil :: any, Min = 0, Max = 10 })
	end)
	assert(not ok, "a machine with no router must say so rather than doing nothing quietly")
end

local function testItRefusesAnInvertedRange()
	local r = router()
	local ok = pcall(function()
		createSlider({ Router = r, Min = 10, Max = 0 })
	end)
	assert(not ok, "a machine with Min > Max must say so rather than doing nothing quietly")
end

T.test("dragging past Max clamps", testDraggingPastMaxClamps, "math")
T.test("dragging before Min clamps", testDraggingBeforeMinClamps, "math")
T.test("Step snaps to the nearest valid value", testStepSnapsToNearestValidValue, "math")
T.test("snap near a boundary stays in range", testSnapNearBoundaryStaysInRange, "math")
T.test("snap after a clamp to Max stays in range", testSnapAfterClampToMaxStaysInRange, "math")
T.test("OnChange never fires with a raw delta", testOnChangeNeverFiresWithARawDelta, "math")
T.test("uncontrolled Value starts at InitialValue, resolved", testUncontrolledValueStartsAtInitialValueResolved, "math")
T.test("controlled never writes its own Value", testControlledNeverWritesItsOwnValue, "math")
T.test("Stop ends the drag", testStopEndsTheDrag, "math")
T.test("GetRootProps exposes the range", testGetRootPropsExposesTheRange, "math")
T.test("it refuses to run without a router", testItRefusesToRunWithoutARouter, "math")
T.test("it refuses an inverted range", testItRefusesAnInvertedRange, "math")

return T.run("createSlider")
