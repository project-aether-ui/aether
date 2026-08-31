--!strict
--!tier math
-- ms-43 M25 additions live at the bottom of this file: presence latching and
-- progress clamping, both driven by the underdamped Pop preset.
local TransitionOrchestrator = require("../src/TransitionOrchestrator")
--- The clock the springs are stepped by; `detect` is memoised, so this is the
--- same host the orchestrator resolved.
local host = require("../src/api").Host.detect()

-- Self-executing: the runner spawns `lune run <suite>` and judges by EXIT CODE
-- alone, so a suite that merely RETURNS a function passes without running a
-- single assertion (ms-43 M30).
local function run()
	-- Test: module exists
	assert(TransitionOrchestrator ~= nil, "TransitionOrchestrator module exists")

	-- Test: Presets exist
	assert(TransitionOrchestrator.Presets.SlideUp ~= nil, "SlideUp preset exists")
	assert(TransitionOrchestrator.Presets.FadeScale ~= nil, "FadeScale preset exists")
	assert(TransitionOrchestrator.Presets.Pop ~= nil, "Pop preset exists")

	-- Test: Bind + HasBinding
	assert(TransitionOrchestrator.HasBinding("TestScreen") == false, "no binding initially")
	TransitionOrchestrator.Bind("TestScreen", TransitionOrchestrator.Presets.SlideUp)
	assert(TransitionOrchestrator.HasBinding("TestScreen") == true, "binding exists after Bind")

	-- Test: GetPhase starts Unmounted
	assert(TransitionOrchestrator.GetPhase("TestScreen") == "Unmounted", "starts unmounted")

	-- Test: UseTransition returns handle
	local handle = TransitionOrchestrator.UseTransition("TestScreen")
	assert(handle ~= nil, "handle returned")
	assert(handle.Phase() == "Unmounted", "handle phase is unmounted")
	assert(handle.Progress() == 0, "handle progress starts at 0")

	-- PHASE IS DERIVED FROM THE SPRING, NOT POKED (ms-43 M15/M30).
	--
	-- This block used to assert an Entering -> MarkMounted -> Mounted -> Exiting
	-- -> MarkUnmounted -> Unmounted march. MarkMounted and MarkUnmounted were
	-- DELETED in M15, when phase became a function of target and progress — and
	-- these assertions kept calling them for fifteen commits without failing,
	-- because the suite returned an uninvoked function and the runner judges by
	-- exit code alone (M30). Calls to a nil field in a never-executed body cost
	-- nothing.
	--
	-- THE TRANSITION IS NOW OBSERVABLE HEADLESSLY (ms-52 M3).
	--
	-- This block used to assert that Enter lands DIRECTLY on Mounted, on the
	-- grounds that the headless spring settled instantly and "a headless suite
	-- that claimed to observe [Entering] would only be asserting the shim's
	-- timing". That reasoning was right about the shim and is now obsolete: the
	-- host loads vide's real spring and steps it from a SIMULATED clock, so the
	-- timing here is deterministic arithmetic rather than an engine's frame rate.
	--
	-- So the phase march is asserted for real, which is what M15 made derivable in
	-- the first place. A transition that snapped straight to Mounted would now
	-- fail, and that is the point.
	local function stepUntil(predicate: () -> boolean, budget: number): boolean
		for _ = 1, budget do
			if predicate() then
				return true
			end
			host.Clock.Step(1 / 60)
		end
		return predicate()
	end

	TransitionOrchestrator.Enter("TestScreen")
	assert(TransitionOrchestrator.GetPhase("TestScreen") == "Entering",
		`a real spring passes through Entering, got {TransitionOrchestrator.GetPhase("TestScreen")}`)
	assert(handle.Progress() < 1, "and progress has not arrived yet")

	assert(stepUntil(function()
		return TransitionOrchestrator.GetPhase("TestScreen") == "Mounted"
	end, 600), `the entrance should complete, stalled at {TransitionOrchestrator.GetPhase("TestScreen")}`)
	--- NEAR 1, not exactly 1: a spring asymptotes toward its target and the phase
	--- flips when it is close enough. Demanding equality would be asserting that
	--- the value snapped, which is the behaviour this test now exists to rule out.
	assert(handle.Progress() > 0.99, `progress should have arrived, got {handle.Progress()}`)

	local isComplete = TransitionOrchestrator.Exit("TestScreen")
	assert(type(isComplete) == "function", "Exit returns a polling function")
	assert(TransitionOrchestrator.GetPhase("TestScreen") == "Exiting",
		`and passes through Exiting, got {TransitionOrchestrator.GetPhase("TestScreen")}`)

	assert(stepUntil(function()
		return TransitionOrchestrator.GetPhase("TestScreen") == "Unmounted"
	end, 600), `the exit should complete, stalled at {TransitionOrchestrator.GetPhase("TestScreen")}`)
	assert(isComplete(), "the exit reports complete once progress reaches zero")

	-- The removed API stays removed. Restoring it would put the manual half of
	-- the lifecycle back alongside the derived half, which is the state M15 found.
	assert((TransitionOrchestrator :: any).MarkMounted == nil, "MarkMounted is gone")
	assert((TransitionOrchestrator :: any).MarkUnmounted == nil, "MarkUnmounted is gone")

	-- Test: UseTransition with no binding returns static handles
	local staticHandle = TransitionOrchestrator.UseTransition("UnboundScreen")
	assert(staticHandle.Phase() == "Mounted", "unbound screen phase is Mounted")
	assert(staticHandle.Progress() == 1, "unbound screen progress is 1")
	assert(staticHandle.StaggerOffset(5)() == 0, "unbound screen stagger is 0")

	-- Test: StaggerOffset
	TransitionOrchestrator.Bind("StaggerTest", {
		Name = "StaggerTest",
		Duration = 0.3,
		DampingRatio = 1.0,
		StaggerDelay = 0.05,
	})
	local staggerHandle = TransitionOrchestrator.UseTransition("StaggerTest")

	-- StaggerOffset returns a per-item 0-1 PROGRESS, not the item's delay. The
	-- old assertion (`index 3 is 0.15`) read the delay back out, which the API
	-- stopped returning; like the phase march above, it never failed because the
	-- suite never ran (M30).
	--
	-- Before the screen enters, every item sits at 0 — including one whose delay
	-- has not been reached.
	assert(staggerHandle.StaggerOffset(0)() == 0, "index 0 is 0 while the screen is closed")
	assert(staggerHandle.StaggerOffset(3)() == 0, "so is index 3, whose delay is 0.15")

	-- Fully entered, every item has finished regardless of its delay — that is
	-- what makes the offset safe to multiply into a transform.
	--- ONCE the entrance has actually run. With a real spring this takes frames,
	--- and a stagger that reported 1 on the frame Enter was called would mean the
	--- delays were not being applied at all.
	TransitionOrchestrator.Enter("StaggerTest")
	assert(staggerHandle.StaggerOffset(3)() < 1, "the last-starting item has not finished immediately")

	--- THE LAG IS OBSERVED MID-TRANSITION, and ms-53 D7 moved it here on purpose.
	---
	--- The old curve gave each item the progress REMAINING after its own start
	--- (`(p - start) / (1 - start)`), so every item finished exactly as the parent
	--- did and the last one was always the fastest -- which meant the lag was still
	--- measurable at the instant the screen reported Mounted, where this assertion
	--- used to sit. The shared `Stagger.window` gives every item the SAME duration
	--- and staggers only the starts, which is Framer's model and Angular's, so the
	--- children finish BEFORE the parent's spring settles and by 0.99 they are all
	--- at 1.
	---
	--- That is a deliberate behaviour change, not a test bent to fit: asserting at
	--- the old point would now require re-introducing the coupling D7 removed.
	--- What must remain true is that the indices DIVERGE at all, which is the one
	--- property three implementations shipped without.
	assert(stepUntil(function()
		return staggerHandle.Progress() > 0.2
	end, 600), "the entrance should get under way")
	assert(staggerHandle.StaggerOffset(3)() < staggerHandle.StaggerOffset(0)(),
		`the last-starting item trails the first: got {staggerHandle.StaggerOffset(3)()} vs {staggerHandle.StaggerOffset(0)()}`)

	assert(stepUntil(function()
		return TransitionOrchestrator.GetPhase("StaggerTest") == "Mounted"
	end, 600), "the staggered screen should finish entering")
	assert(staggerHandle.StaggerOffset(0)() > 0.99, `index 0 completes, got {staggerHandle.StaggerOffset(0)()}`)

	--- And it converges: a stagger that permanently stranded its last item short
	--- of 1 would leave that element visibly unfinished.
	assert(stepUntil(function()
		return staggerHandle.StaggerOffset(3)() > 0.99
	end, 600), `the last-starting item should arrive, got {staggerHandle.StaggerOffset(3)()}`)
	TransitionOrchestrator.Exit("StaggerTest")

	-- Test: Unbind
	TransitionOrchestrator.Unbind("TestScreen")
	assert(TransitionOrchestrator.HasBinding("TestScreen") == false, "binding removed after Unbind")
	TransitionOrchestrator.Unbind("StaggerTest")

	-- ms-43 M25: presence must LATCH, and progress must never leave [0, 1].
	--
	-- The Showcase runs the Pop preset (DampingRatio 0.6) — underdamped, so it
	-- overshoots. Without hysteresis its exit crossed the settle threshold, hid
	-- the window, then bounced back over it and flashed the window visible again,
	-- re-registering every control and chirping a hover sound from anywhere on
	-- screen.
	TransitionOrchestrator.Bind("LatchTest", TransitionOrchestrator.Presets.Pop)
	assert(not TransitionOrchestrator.IsPresent("LatchTest"), "not present before Enter")

	TransitionOrchestrator.Enter("LatchTest")
	assert(TransitionOrchestrator.IsPresent("LatchTest"), "present immediately on Enter, so it can animate in")

	-- Exit does NOT clear presence: the screen has to survive its own exit
	-- animation. The frame loop clears it once, when the spring settles, and a
	-- bounce cannot raise it again.
	TransitionOrchestrator.Exit("LatchTest")

	TransitionOrchestrator.Enter("LatchTest")
	assert(TransitionOrchestrator.IsPresent("LatchTest"), "Enter raises presence again")
	TransitionOrchestrator.Unbind("LatchTest")

	-- Progress is clamped: an underdamped spring reports outside [0, 1], and
	-- every consumer (transparency, scale, position, visibility) reads it.
	TransitionOrchestrator.Bind("ClampTest", TransitionOrchestrator.Presets.Pop)
	local clampHandle = TransitionOrchestrator.UseTransition("ClampTest")
	TransitionOrchestrator.Enter("ClampTest")
	local pIn = clampHandle.Progress()
	assert(pIn >= 0 and pIn <= 1, `progress must stay in [0, 1] entering, got {pIn}`)
	TransitionOrchestrator.Exit("ClampTest")
	local pOut = clampHandle.Progress()
	assert(pOut >= 0 and pOut <= 1, `progress must stay in [0, 1] exiting, got {pOut}`)
	TransitionOrchestrator.Unbind("ClampTest")

	-- An unbound screen reads as present and mounted rather than erroring.
	assert(TransitionOrchestrator.IsPresent("NoSuchScreen"), "an unbound screen is present")
	assert(TransitionOrchestrator.UseTransition("NoSuchScreen").Progress() == 1, "unbound reads as mounted")
end

-- ms-44: migrated onto testkit. This suite had no harness — bare asserts inside named
-- functions, invoked at the bottom of the file. That is the ms-43 M30 shape: delete an
-- invocation and the file still exits 0 and still reads as coverage. Registered tests
-- make that a VACUOUS failure instead, and give each one a name, a time and a tier in
-- the ##testkit JSON.
local T = require("@testkit")
T.test("TransitionOrchestrator", run, "math")

return T.run("TransitionOrchestrator")
