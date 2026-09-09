--!strict
--!tier math
--[=[
	spektr/aether · core/TooltipMachine (milestone 7 step D).

	NO VIDE, NO HOST, NO WAITING. This file requires the machine and testkit and
	nothing else, which is the whole claim of the split: the rule "hover, wait,
	show; leave, hide, and cancel anything pending" can be interrogated without
	mounting a component or opening a reactive scope.

	That is enforced rather than promised -- `verify_core_has_no_framework` fails
	if anything under `src/core/` reaches for `Deps` or names an engine type, so a
	require sneaking back into the machine breaks the gate rather than quietly
	making this suite depend on a framework.

	TIME IS DRIVEN BY HAND. The machine takes `Schedule` as a port, so these cases
	fire the delay when they choose. A test that slept would be slow AND would be
	asserting the scheduler rather than the rule.

	THE CASE THAT MATTERS is the second one: leaving during the delay must not
	open later. A scheduler that has already queued its callback cannot always be
	cancelled, so the machine re-checks its own state when the timer lands.
]=]
local T = require("@testkit")
local TooltipMachine = require("../../src/core/TooltipMachine")

--- A scheduler this file controls. `fire()` runs whatever is pending, `pending()`
--- reports whether a timer is still armed -- which is how "the delay was
--- cancelled" gets asserted rather than inferred from the state that follows.
local function clock()
	local queued: (() -> ())? = nil
	local lastDelay: number? = nil
	return {
		Schedule = function(seconds: number, fn: () -> ()): () -> ()
			lastDelay = seconds
			queued = fn
			return function()
				queued = nil
			end
		end,
		fire = function()
			local fn = queued
			queued = nil
			if fn then
				fn()
			end
		end,
		pending = function(): boolean
			return queued ~= nil
		end,
		delay = function(): number?
			return lastDelay
		end,
	}
end

local function testItWaitsBeforeOpening()
	local c = clock()
	local m = TooltipMachine.new({ Delay = 0.35, Schedule = c.Schedule })

	m.Enter()
	assert(m.GetState() == "waiting", `entering should arm the delay, got {m.GetState()}`)
	assert(not m.IsOpen(), "a tooltip must not be open during its dwell delay")
	assert(c.delay() == 0.35, `the machine should schedule its own delay, got {tostring(c.delay())}`)

	c.fire()
	assert(m.IsOpen(), "the tooltip should open once the delay elapses")
end

local function testLeavingDuringTheDelayCancelsIt()
	local c = clock()
	local m = TooltipMachine.new({ Delay = 1, Schedule = c.Schedule })

	m.Enter()
	m.Leave()

	assert(not c.pending(), "leaving should cancel the pending timer, not merely ignore it")
	assert(m.GetState() == "closed", `leaving should close, got {m.GetState()}`)

	c.fire()
	assert(not m.IsOpen(), "a cancelled timer that fires late must not open the tooltip")
end


--- A SCHEDULER WHOSE CANCEL DOES NOTHING, which is how a queue that has already
--- dispatched behaves. The case above cancels successfully and therefore never
--- reaches the machine's own re-check; breaking that guard left this suite green
--- until this case existed.
local function testATimerThatOutlivesItsCancelCannotOpen()
	local queued: (() -> ())? = nil
	local m = TooltipMachine.new({
		Delay = 1,
		Schedule = function(_seconds: number, fn: () -> ()): () -> ()
			queued = fn
			return function() end
		end,
	})

	m.Enter()
	m.Leave()
	assert(m.GetState() == "closed", "precondition: leaving closed it")

	;(queued :: any)()

	assert(not m.IsOpen(), "a timer that survived its cancel must not open a closed tooltip")
end

local function testEnteringWhileOpenIsNotARestart()
	local c = clock()
	local m = TooltipMachine.new({ Delay = 0.2, Schedule = c.Schedule })

	m.Enter()
	c.fire()
	assert(m.IsOpen(), "precondition: open")

	m.Enter()
	assert(m.IsOpen(), "a second enter while open must not close or re-arm")
	assert(not c.pending(), "a second enter while open must not schedule anything")
end

local function testSubscribersSeeEveryTransition()
	local c = clock()
	local m = TooltipMachine.new({ Delay = 0.1, Schedule = c.Schedule })

	local seen: { string } = {}
	local unsubscribe = m.Subscribe(function(state)
		table.insert(seen, state)
	end)

	m.Enter()
	c.fire()
	m.Leave()

	assert(#seen == 3, `expected waiting, open, closed; got {#seen} notification(s)`)
	assert(
		seen[1] == "waiting" and seen[2] == "open" and seen[3] == "closed",
		`transitions arrived as {table.concat(seen, ", ")}`
	)

	unsubscribe()
	m.Enter()
	assert(#seen == 3, "an unsubscribed listener must stop being called")
end

local function testWithNoSchedulerItOpensAtOnce()
	local m = TooltipMachine.new({ Delay = 5 })
	m.Enter()
	assert(m.IsOpen(), "with no way to wait, opening beats never opening")
end

local function testDestroyStopsEverything()
	local c = clock()
	local m = TooltipMachine.new({ Delay = 0.3, Schedule = c.Schedule })

	local calls = 0
	m.Subscribe(function()
		calls += 1
	end)

	m.Enter()
	m.Destroy()

	assert(not c.pending(), "destroy should cancel a pending timer")
	local before = calls
	c.fire()
	m.Enter()
	assert(calls == before, "a destroyed machine must not notify anyone")
	assert(not m.IsOpen(), "a destroyed machine must not open")
end

T.test("it waits before opening", testItWaitsBeforeOpening, "math")
T.test("leaving during the delay cancels it", testLeavingDuringTheDelayCancelsIt, "math")
T.test("a timer that outlives its cancel cannot open", testATimerThatOutlivesItsCancelCannotOpen, "math")
T.test("entering while open is not a restart", testEnteringWhileOpenIsNotARestart, "math")
T.test("subscribers see every transition", testSubscribersSeeEveryTransition, "math")
T.test("with no scheduler it opens at once", testWithNoSchedulerItOpensAtOnce, "math")
T.test("destroy stops everything", testDestroyStopsEverything, "math")

return T.run("TooltipMachine")
