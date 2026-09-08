--!strict
--[[
	Aether · Presence — should this element be rendered right now? (ms-53 D4)

	    local presence = Presence.new({
	        Present = function() return isOpen() end,
	        StillAnimating = function() return motion.Progress() > 0.01 end,
	    })

	    Visible = presence.ShouldRender

	THE PROBLEM IT REPLACES. An element that animates out must stay rendered until
	the animation finishes, so "should I draw?" is not "am I open?". Both shipped
	menus hand-rolled that latch, identically, and both got it wrong in the same
	way: they asked a motion whose progress falls back to a constant 1 when no
	transition is bound, read that as a close permanently in flight, and never
	hid. `ShopMenu:Hidden` rendered byte-identical to `:Default` for a whole
	milestone (ms-53 D3).

	`TransitionOrchestrator` already said this should not be copy-pasted -- ms-43
	M15 removed exactly this pattern as blueprint B-4 and moved it "into the place
	that owns the lifecycle rather than copy-pasted into each menu". Two copies
	survived that. This is the place.

	MODELLED ON ZAG'S `presence` MACHINE, and deliberately not on Mantine's
	`<Transition>`. Both web libraries solve this; the difference that decides it
	is that BOTH ARE DRIVEN BY DOM ANIMATION EVENTS -- `animationend` tells them an
	exit is over. Aether has no such event: Flux is a sampled spring, read per
	frame. So the machine takes a PREDICATE it can poll rather than a callback it
	subscribes to, which is the one change that re-hosts the idea here.

	IT OWNS THE MACHINE AND NOT THE TIMING. `StillAnimating` is supplied by the
	caller, so this needs no clock, no Flux and no host to test -- and Flux stays
	optional, which the host layer already requires of everything at this layer.

	    unmounted ──Present()──> entering ──settled──> present
	        ▲                                             │
	        └────── exit finished ── exiting <──not Present
]]

local Presence = {}

export type Phase = "unmounted" | "entering" | "present" | "exiting"

export type Options = {
	--- Is the element wanted on screen? Read every evaluation.
	Present: () -> boolean,
	--- Is an EXIT animation still running? Omit when nothing animates, and the
	--- element disappears the moment it is no longer present -- which is correct,
	--- and is the case both kits got wrong by consulting a stand-in instead.
	StillAnimating: (() -> boolean)?,
	--- Is an ENTER animation still running? Optional and rarely needed: an
	--- entering element is rendered either way, so this only distinguishes
	--- `entering` from `present` for a caller that cares.
	StillEntering: (() -> boolean)?,
	--- The presence this one lives INSIDE (ms-53 D7). A tab panel is inside a
	--- settings window; when the window leaves, the panel leaves with it no
	--- matter what its own `Present` says.
	---
	--- WHY A HANDLE AND NOT A PHASE GETTER. The relationship is typed, so a
	--- caller cannot pass something that merely looks like a phase -- and reading
	--- the parent through its own machine means the child inherits the parent's
	--- hysteresis rather than re-deriving it and disagreeing.
	---
	--- It does NOT collapse to `Present = function() return parent() and mine() end`.
	--- While the parent is EXITING the child must keep rendering: the window is
	--- still on screen, sliding out, and a panel that vanished the instant the
	--- close was requested would leave an empty window animating away.
	Inherit: Handle?,
}

export type Handle = {
	--- The answer. Bind this to `Visible`.
	ShouldRender: () -> boolean,
	Phase: () -> Phase,
}

function Presence.new(options: Options): Handle
	local present = options.Present
	local stillAnimating = options.StillAnimating
	local stillEntering = options.StillEntering
	local inherit = options.Inherit

	--- The only retained state, and it exists for one reason: to tell "never
	--- shown" apart from "was shown and is now leaving". Without it an element
	--- that mounts un-present cannot know whether it owes an exit animation, and
	--- guessing wrong is a menu that draws when told not to.
	local hasEntered = false
	--- Latched when an exit completes, cleared when the element becomes present
	--- again. Hysteresis: without it a predicate that flickers around its
	--- threshold flickers the element with it, which is the reason ms-43 M15's
	--- replacement of the latch with a bare threshold was a regression.
	local exitFinished = false

	local function phase(): Phase
		--- THE PARENT DECIDES FIRST (ms-53 D7). Read before this element's own
		--- `Present`, because a child of a departed parent has no say -- and
		--- reading `Present` first would let it re-enter inside a window that is
		--- already gone.
		if inherit then
			local parent = inherit.Phase()
			if parent == "unmounted" then
				--- Gone with it, and the latch goes with it too, so that when the
				--- parent returns this child re-enters rather than staying dead --
				--- the bug `testItCanBeShownAgain` exists to catch, one level up.
				exitFinished = true
				hasEntered = false
				return "unmounted"
			end
			if parent == "exiting" then
				--- Still on screen, leaving together. Not `present`: nothing should
				--- start an ENTER animation inside a window that is closing.
				return if hasEntered then "exiting" else "unmounted"
			end
		end

		if present() then
			hasEntered = true
			exitFinished = false
			if stillEntering and stillEntering() then
				return "entering"
			end
			return "present"
		end

		--- Never shown. There is nothing to animate out, and consulting an
		--- animation here is what produced the D3 defect.
		if not hasEntered then
			return "unmounted"
		end

		if exitFinished then
			return "unmounted"
		end

		--- No exit animation supplied means the exit is instantaneous. This is the
		--- honest default: an element that does not say how it leaves, leaves.
		if not stillAnimating then
			exitFinished = true
			return "unmounted"
		end

		if stillAnimating() then
			return "exiting"
		end

		exitFinished = true
		return "unmounted"
	end

	return {
		Phase = phase,
		ShouldRender = function(): boolean
			return phase() ~= "unmounted"
		end,
	}
end

return Presence
