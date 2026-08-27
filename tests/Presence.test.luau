--!strict
--!tier math
--[=[
	spektr/aether · Presence (ms-53 D4).

	NO CLOCK, NO FLUX, NO HOST. The machine takes "is the exit still animating?"
	as a predicate, so every case here drives it by hand -- which is the point of
	taking that as a parameter rather than reaching for a motion.

	THE CASES THAT MATTER are the two the shipped kits got wrong:

	  * un-present at birth must render NOTHING. Consulting an animation there is
	    what made a hidden menu draw for a whole milestone.
	  * present, then not, WITH a live animation must keep rendering. A fix that
	    simply returns false when not present passes the first case and deletes
	    every exit animation in the framework.

	Either one alone is satisfiable by a wrong implementation. Both together are
	not, which is why they are written as a cycle rather than as states.
]=]
local T = require("@testkit")
local Presence = require("../src/Presence")

--- A hand-driven fixture: two booleans and a machine over them.
local function fixture(withAnimation: boolean)
	local open = false
	local animating = false
	local p = Presence.new({
		Present = function()
			return open
		end,
		StillAnimating = if withAnimation
			then function()
				return animating
			end
			else nil,
	})
	--- EVERY MUTATION READS. `Presence` is PULL-BASED -- its state advances only
	--- when something evaluates it -- so a test that sets `open = true` and never
	--- reads has not shown the element at all. Two poisons stayed GREEN against
	--- an earlier version of this file for exactly that reason: "shown, then
	--- hidden" was really "never shown, then hidden", and the never-shown guard
	--- answered before the latch was ever reached.
	---
	--- Reading here also matches how it is consumed: `ShouldRender` is bound to
	--- `Visible` and evaluated every frame.
	return {
		Open = function(v: boolean)
			open = v
			p.ShouldRender()
		end,
		Animating = function(v: boolean)
			animating = v
			p.ShouldRender()
		end,
		Render = p.ShouldRender,
		Phase = p.Phase,
	}
end

local function testUnPresentAtBirthRendersNothing()
	local f = fixture(true)
	--- The animation predicate is FALSE here, but the point is that it is not
	--- consulted at all: an element that has never entered owes no exit.
	f.Animating(true)
	assert(f.Render() == false, `never shown, it should not render; phase was {f.Phase()}`)
	assert(f.Phase() == "unmounted", `phase should be unmounted, got {f.Phase()}`)
end

local function testPresentRenders()
	local f = fixture(true)
	f.Open(true)
	assert(f.Render() == true, "present, it renders")
	assert(f.Phase() == "present", `phase should be present, got {f.Phase()}`)
end

--- THE CYCLE. Shown, then hidden with an animation still running, then finished.
local function testExitIsWaitedFor()
	local f = fixture(true)
	f.Open(true)
	assert(f.Render() == true, "shown")

	--- THE ANIMATION IS ALREADY RUNNING WHEN THE CLOSE IS REQUESTED, which is how
	--- the kits actually drive this: `StillAnimating` is `progress > 0.01`, and
	--- progress is high while the menu is open. Setting it AFTER the close would
	--- let the exit complete in the gap -- and once this fixture reads on every
	--- mutation, that gap is real.
	f.Animating(true)
	f.Open(false)
	assert(f.Render() == true, "hidden but still animating out, it must keep rendering")
	assert(f.Phase() == "exiting", `phase should be exiting, got {f.Phase()}`)

	f.Animating(false)
	assert(f.Render() == false, "the animation finished, so it stops")
	assert(f.Phase() == "unmounted", `phase should be unmounted, got {f.Phase()}`)
end

--- WITH NO ANIMATION SUPPLIED, leaving is instant. This is the case both kits
--- had backwards: they consulted a motion that answered a constant "still
--- going" and so never left at all.
local function testNoAnimationLeavesImmediately()
	local f = fixture(false)
	f.Open(true)
	assert(f.Render() == true, "shown")
	f.Open(false)
	assert(f.Render() == false, "with no exit animation it leaves at once")
end

--- HYSTERESIS. Once an exit has completed the element stays gone, even if the
--- predicate flickers back to true -- a spring settling can cross its threshold
--- more than once, and ms-43 M15 regressed exactly this by replacing a latch
--- with a bare threshold.
local function testAFinishedExitStaysFinished()
	local f = fixture(true)
	f.Animating(true)
	f.Open(true)
	f.Open(false)
	assert(f.Render() == true, "still animating out")
	f.Animating(false)
	assert(f.Render() == false, "the exit completed")
	f.Animating(true)
	assert(f.Render() == false, "a flickering predicate must not bring it back")
end

--- AND IT CAN COME BACK. The latch above must clear on re-entry, or an element
--- can be shown exactly once per lifetime -- which would pass every case before
--- this one.
local function testItCanBeShownAgain()
	local f = fixture(true)
	f.Animating(true)
	f.Open(true)
	f.Open(false)
	f.Animating(false)
	assert(f.Render() == false, "gone")
	f.Animating(true)
	f.Open(true)
	assert(f.Render() == true, "shown again")
	assert(f.Phase() == "present", `phase should be present, got {f.Phase()}`)
	f.Open(false)
	assert(f.Render() == true, "and it animates out a second time")
end

--- `entering` is reported only when a caller asks for it. Nothing depends on the
--- distinction for rendering -- an entering element renders either way -- so it
--- is opt-in rather than a fourth thing every consumer must handle.
local function testEnteringIsOptional()
	local entering = true
	local p = Presence.new({
		Present = function()
			return true
		end,
		StillEntering = function()
			return entering
		end,
	})
	assert(p.Phase() == "entering", `phase should be entering, got {p.Phase()}`)
	assert(p.ShouldRender() == true, "an entering element renders")
	entering = false
	assert(p.Phase() == "present", `phase should be present, got {p.Phase()}`)
end

T.test("never shown renders nothing, and does not consult the animation", testUnPresentAtBirthRendersNothing, "math")
T.test("present renders", testPresentRenders, "math")
T.test("an exit animation is waited for", testExitIsWaitedFor, "math")
T.test("with no exit animation, leaving is immediate", testNoAnimationLeavesImmediately, "math")
T.test("a finished exit stays finished", testAFinishedExitStaysFinished, "math")
T.test("it can be shown again", testItCanBeShownAgain, "math")
T.test("entering is reported only when asked for", testEnteringIsOptional, "math")

return T.run("Presence")
