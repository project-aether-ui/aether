--!strict
--!tier math
--[=[
	spektr/aether · Stagger (ms-53 D7).

	THE ONE PROPERTY THREE IMPLEMENTATIONS SHIPPED WITHOUT. `PropertyTransforms.Stagger`,
	`MotionPackManager.Stagger` and `TransitionOrchestrator.StaggerOffset` all had
	suites, and every one of them asserted that a number MOVED -- which a stagger
	returning the parent's progress unchanged for every index satisfies perfectly.
	That is what shipped: no preset set `StaggerDelay`, so every child's start was
	`index * 0`, and nothing anywhere could tell the difference between that and a
	stagger deliberately configured to zero.

	So every case here is about DIVERGENCE between indices, not about the shape of
	one index's curve.
]=]
local T = require("@testkit")
local Stagger = require("../src/Stagger")

local function at(base: number, index: number, delay: number?, duration: number?): number
	return Stagger.window({
		BaseProgress = function()
			return base
		end,
		Index = index,
		DelayPerItem = delay,
		ItemDuration = duration,
	})()
end

local function testTheFirstItemStartsImmediately()
	assert(at(0.1, 1, 0.1, 0.5) > 0, "item 1 has no delay")
	assert(at(0.05, 2, 0.1, 0.5) == 0, "item 2 waits for its delay")
end

--- THE CASE THAT MATTERS. Two indices must actually differ somewhere.
local function testIndicesDiverge()
	local props = { DelayPerItem = 0.1, ItemDuration = 0.5 }
	assert(Stagger.diverges(
		{ BaseProgress = function() return 0 end, Index = 1, DelayPerItem = props.DelayPerItem, ItemDuration = props.ItemDuration },
		{ BaseProgress = function() return 0 end, Index = 4, DelayPerItem = props.DelayPerItem, ItemDuration = props.ItemDuration }
	), "items 1 and 4 must not move together")
end

--- AND THE DETECTOR ITSELF MUST BE ABLE TO SAY NO, or it is a function that
--- returns true and a suite that proves nothing. This is the exact configuration
--- that shipped: a delay of zero.
local function testZeroDelayDoesNotDiverge()
	assert(not Stagger.diverges(
		{ BaseProgress = function() return 0 end, Index = 1, DelayPerItem = 0, ItemDuration = 0.5 },
		{ BaseProgress = function() return 0 end, Index = 4, DelayPerItem = 0, ItemDuration = 0.5 }
	), "with no delay every index moves together -- and that must be DETECTED, not tolerated")
end

--- EVERY ITEM GETS THE SAME DURATION. This is the change from the orchestrator's
--- old curve, which derived each item's window from the progress remaining after
--- its own start and so made the last item the fastest.
local function testEveryItemTakesTheSameTime()
	local delay, duration = 0.1, 0.4
	--- Item 1 travels from 0 to 0.4; item 3 from 0.2 to 0.6. Sampled at the same
	--- offset into each one's own window, they must read the same.
	local first = at(0.2, 1, delay, duration)
	local third = at(0.4, 3, delay, duration)
	assert(math.abs(first - third) < 1e-9,
		`the same offset into each window should read the same; got {first} and {third}`)
end

--- AT REST, EVERYTHING IS AT REST. Without this the last item in a long list
--- never quite reaches 1, because its window ends past where progress stops.
local function testEveryItemCompletes()
	assert(at(1, 12, 0.1, 0.3) == 1, "at full progress even a late item is finished")
	assert(at(0, 1, 0.1, 0.3) == 0, "and at zero even the first has not started")
end

--- ORDERING. A later index is never AHEAD of an earlier one.
local function testLaterItemsNeverLead()
	for i = 1, 19 do
		local base = i / 20
		local a, b = at(base, 1, 0.05, 0.4), at(base, 5, 0.05, 0.4)
		assert(a >= b - 1e-9, `item 5 led item 1 at base {base}: {b} > {a}`)
	end
end

--- EVERY SHIPPED PRESET ACTUALLY STAGGERS.
---
--- This is the case whose absence WAS the defect. The maths had suites; the
--- configuration did not, and all three presets left `StaggerDelay` unset, so the
--- only path `Bind` offers produced uniform progress. A preset is not a value
--- nobody checks -- it is the value every consumer gets by default.
---
--- WHAT THIS CAN AND CANNOT CATCH. `Stagger.window` now DEFAULTS a nil delay
--- rather than treating it as zero, so the original defect -- an unset field --
--- can no longer reproduce, and poisoning one back to nil leaves this green. It
--- catches an explicit `StaggerDelay = 0`, which is the only way left to ship a
--- preset that does not stagger. Said here because a case whose obvious poison
--- does not go red is otherwise indistinguishable from a case that is vacuous.
local function testEveryShippedPresetStaggers()
	local Orchestrator = require("../src/TransitionOrchestrator")
	for name, preset in pairs(Orchestrator.Presets) do
		local a = {
			BaseProgress = function()
				return 0
			end,
			Index = 1,
			DelayPerItem = (preset :: any).StaggerDelay,
			ItemDuration = (preset :: any).StaggerItemDuration,
		}
		local b = {
			BaseProgress = function()
				return 0
			end,
			Index = 4,
			DelayPerItem = (preset :: any).StaggerDelay,
			ItemDuration = (preset :: any).StaggerItemDuration,
		}
		assert(Stagger.diverges(a, b), `preset {name} does not stagger its children at all`)
	end
end

T.test("the first item starts immediately, later ones wait", testTheFirstItemStartsImmediately, "math")
T.test("every shipped preset actually staggers", testEveryShippedPresetStaggers, "math")
T.test("indices diverge", testIndicesDiverge, "math")
T.test("a zero delay is DETECTED as non-divergent", testZeroDelayDoesNotDiverge, "math")
T.test("every item takes the same time", testEveryItemTakesTheSameTime, "math")
T.test("every item completes, and none starts early", testEveryItemCompletes, "math")
T.test("later items never lead", testLaterItemsNeverLead, "math")

return T.run("Stagger")
