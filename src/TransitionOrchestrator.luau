--!strict
--[[
	TransitionOrchestrator: Spring-driven transition lifecycle management.

	Manages enter/exit animation phases for screens registered with ScreenStack.
	The application layer binds transition presets to screen IDs. Components consume
	reactive Phase and Progress signals to drive their own visual animations.

	Phases: Unmounted → Entering → Mounted → Exiting → Unmounted
	Progress: 0.0 → 1.0 (enter), 1.0 → 0.0 (exit), spring-driven.
]]

local Deps = require("./Deps")
local PointerRouter = require("./PointerRouter")

local source = Deps.source
local spring = Deps.spring
local root = Deps.root
local isRoblox = Deps.isRoblox
local RunService = if isRoblox then (game :: any):GetService("RunService") else nil

local ScreenStack = require("./ScreenStack")

--- ms-53 D7: the one stagger window, shared with Flux's `PropertyTransforms`.
local Stagger = require("./Stagger")

export type TransitionPhase = "Unmounted" | "Entering" | "Mounted" | "Exiting"

export type TransitionPreset = {
	Name: string,
	Duration: number,         -- seconds (used as spring period)
	DampingRatio: number?,    -- defaults to 1.0 (critically damped)
	StaggerDelay: number?,    -- per-child stagger offset (seconds)
	--- How long each child takes once it starts (ms-53 D7). Previously derived
	--- from the progress remaining after the child's own start, which made the
	--- last child in a list the fastest.
	StaggerItemDuration: number?,
}

export type TransitionHandle = {
	Phase: () -> TransitionPhase,
	Progress: () -> number,
	StaggerOffset: (index: number) -> () -> number,
}

local TransitionOrchestrator = {}

-- Built-in presets
TransitionOrchestrator.Presets = {
	--- ms-53 D7: EVERY PRESET NOW STAGGERS. All three had `StaggerDelay` unset,
	--- so `StaggerOffset(i)` returned the parent's progress unchanged for every
	--- child -- a stagger that was inert through the only path `Bind` offers, with
	--- nothing to distinguish it from a stagger deliberately set to zero.
	---
	--- The values track each preset's own duration: a 0.2s Pop cannot spend 0.06
	--- of its progress before its second child starts and still feel like one
	--- gesture.
	SlideUp   = { Name = "SlideUp",   Duration = 0.3, DampingRatio = 0.85, StaggerDelay = 0.06, StaggerItemDuration = 0.6 } :: TransitionPreset,
	FadeScale = { Name = "FadeScale", Duration = 0.25, DampingRatio = 1.0, StaggerDelay = 0.05, StaggerItemDuration = 0.6 } :: TransitionPreset,
	Pop       = { Name = "Pop",       Duration = 0.2, DampingRatio = 0.6, StaggerDelay = 0.04, StaggerItemDuration = 0.5 } :: TransitionPreset,
}

-- Internal state per screen
type ScreenTransition = {
	Preset: TransitionPreset,
	Phase: any,          -- () -> TransitionPhase, DERIVED from Target + Progress
	Target: any,         -- source<number> (0 or 1)
	Progress: any,       -- spring-driven reactive number
	Present: any,        -- source<boolean>, LATCHED (see Bind)
	ReadProgress: () -> number,
}

local bindings: { [string]: ScreenTransition } = {}

--- Distance from a settled spring at which a transition counts as complete.
local SETTLE_EPSILON = 0.01

--- Bind a transition preset to a screen ID. Must be called before UseTransition.
---
--- PHASE IS DERIVED, NOT POKED (ms-43 blueprint F-8). M11 shipped Phase as a
--- source that only advanced to Mounted/Unmounted when the application called
--- MarkMounted/MarkUnmounted — and nothing ever did, in this repo or the demo. So
--- every screen sat in "Entering" forever and the four-phase lifecycle the sprint
--- claimed was really two. Phase now reads the spring it already has.
function TransitionOrchestrator.Bind(screenId: string, preset: TransitionPreset)
	local target = source(0)

	local period = preset.Duration or 0.25
	local dampingRatio = preset.DampingRatio or 1.0

	-- The spring is created inside a reactive root so it owns a scope it can be
	-- torn down with; headless, Deps.spring reads the target straight through.
	local progress: any
	root(function()
		progress = spring(target, period, dampingRatio)
	end)

	-- CLAMPED. An underdamped preset overshoots — the Pop preset (DampingRatio
	-- 0.6) undershoots below 0 on the way out and above 1 on the way in — and a
	-- raw value outside [0, 1] is a footgun for every consumer: transparency,
	-- scale, position and visibility gates all read this.
	local function readProgress(): number
		local raw = if type(progress) == "function" then progress() else target()
		return math.clamp(raw, 0, 1)
	end

	local phase = function(): TransitionPhase
		local p = readProgress()
		if target() >= 1 then
			return if p >= 1 - SETTLE_EPSILON then "Mounted" else "Entering"
		end
		return if p <= SETTLE_EPSILON then "Unmounted" else "Exiting"
	end

	-- PRESENCE IS LATCHED, and that latch is the point.
	--
	-- A screen must stay mounted through its exit animation, so the obvious gate
	-- is "target is 1, or progress has not reached zero yet". With a critically
	-- damped spring that is fine. With an UNDERDAMPED one it is not: progress
	-- crosses the threshold, the screen hides, the spring bounces back above the
	-- threshold, and the screen FLASHES VISIBLE AGAIN.
	--
	-- That is what made closing the Showcase chirp a hover sound from anywhere on
	-- screen: the flash re-registered every control for a frame, and whichever sat
	-- under the pointer fired a hover-enter. It is the only screen on the Pop
	-- preset, which is why it was the only one affected.
	--
	-- ms-43 M15 removed a hand-rolled `hasReachedRest` latch from that menu as
	-- blueprint B-4 — correctly, since it mutated a non-reactive upvalue from
	-- inside a reactive getter — but replaced it with a bare threshold, missing
	-- that the latch was also providing hysteresis. This puts it back, once, in
	-- the place that owns the lifecycle rather than copy-pasted into each menu.
	local present = source(false)

	bindings[screenId] = {
		Preset = preset,
		Phase = phase,
		Target = target,
		Progress = progress,
		Present = present,
		ReadProgress = readProgress,
	}
end

--- Signal that a screen is entering (should be called when ScreenStack opens the screen).
function TransitionOrchestrator.Enter(screenId: string)
	local binding = bindings[screenId]
	if not binding then
		-- Unbound screens animate instantly; that is a valid configuration, not
		-- an error worth spamming the output for on every open.
		return
	end

	-- Present immediately: the screen must exist to animate in.
	binding.Present(true)
	binding.Target(1)
end

--- Signal that a screen is exiting (should be called when ScreenStack closes the screen).
--- Returns a function that fires when the exit transition completes (progress reaches ~0).
function TransitionOrchestrator.Exit(screenId: string): () -> boolean
	local binding = bindings[screenId]
	if not binding then
		return function() return true end
	end

	binding.Target(0)
	-- Present stays true until the exit actually settles; the Heartbeat below
	-- clears it, ONCE, and a spring bounce cannot set it back.

	return function(): boolean
		return binding.ReadProgress() < SETTLE_EPSILON
	end
end

-- Settle the presence latch. A frame loop rather than a check inside the getter:
-- writing a source from inside a reactive read is what made the original
-- hand-rolled latch a defect (ms-43 blueprint B-4), and repeating that here would
-- reintroduce it one layer down.
--- ONE SETTLE PASS. Extracted so both hosts can drive it (ms-53 D6): the loop
--- below used to be Heartbeat-only, so OFF-ENGINE `Present` never cleared and a
--- closed screen stayed "present" for the rest of the process. That is the fourth
--- engine-gated lifecycle this milestone has found -- after the scroll extent
--- (D2) and the progress stand-in (D3) -- and the shape is always the same: a
--- branch that only runs in Roblox, and nothing off-engine to notice.
function TransitionOrchestrator.Settle()
	for screenId, binding in pairs(bindings) do
		if binding.Target() < 1 and binding.Present() and binding.ReadProgress() < SETTLE_EPSILON then
			binding.Present(false)
			--- PUSHED to the stack rather than pulled from it. The orchestrator
			--- already requires ScreenStack for its open/close subscription, so
			--- telling it beats it asking -- which would be a circular require.
			ScreenStack._ExitSettled(screenId)
		end
	end
end

if isRoblox and RunService then
	RunService.Heartbeat:Connect(TransitionOrchestrator.Settle)
elseif PointerRouter and PointerRouter.OnFrame then
	--- Off-engine the frame bus is what a host pumps -- `Live.Session.Step` calls
	--- `router.Input.Frame()` every frame, which is the same seam ScrollArea uses
	--- to measure its viewport.
	PointerRouter.OnFrame(TransitionOrchestrator.Settle)
end

--- Should this screen be rendered at all? True from Enter until its exit has
--- actually settled — and NOT re-raised by an underdamped spring bouncing back
--- over the threshold. Use this for a menu's Visible gate rather than comparing
--- Progress to an epsilon by hand.
function TransitionOrchestrator.IsPresent(screenId: string): boolean
	local binding = bindings[screenId]
	if not binding then return true end
	return binding.Present() == true
end

-- MarkMounted / MarkUnmounted are gone. They were the manual half of a lifecycle
-- that now derives itself from the spring (see Bind), and nothing in this repo or
-- the demo ever called them — which is precisely why no screen ever reached the
-- Mounted phase. ms-43 blueprint F-8.

--- Is the screen at rest — neither entering nor exiting?
---
--- ms-43 M31. Every menu that wanted this wrote `motion.Progress() > 0.99` by
--- hand: a magic number in the wrong place. The settle epsilon belongs to the
--- module that owns the spring, and a menu should not have to know that 0.99 is
--- what stops its own entrance animation from firing hover feedback as it flies
--- past a stationary cursor.
---
--- An unbound screen is always settled: nothing is animating it.
function TransitionOrchestrator.IsSettled(screenId: string): boolean
	local binding = bindings[screenId]
	if not binding then
		return true
	end
	return binding.Phase() == "Mounted"
end

--- Reactive "should this screen be in the tree?" — open, OR still animating out.
---
--- ms-43 M31. IsOpen alone is the wrong question for rendering: a screen that has
--- just closed must survive its own exit animation, and one whose exit spring is
--- UNDERDAMPED must not be un-rendered the instant progress dips below the settle
--- threshold, because the bounce brings it back. IsPresent is the latch that
--- handles both; this is the pairing every screen needs, and four of the five in
--- the demo did not have it.
---
--- IT LIVES HERE, NOT ON ScreenStack, WHERE IT READS BETTER. This module
--- already requires ScreenStack (for the open/close subscription), so the
--- reverse edge would be a CYCLE — and lune does not error on one, it DEADLOCKS:
--- the require blocks forever at zero CPU. I wrote that cycle, spent a while
--- bisecting a "flaky hang", and only found it because the block used no CPU.
function TransitionOrchestrator.IsVisible(screenId: string): () -> boolean
	local isOpen = ScreenStack.IsOpen(screenId)
	return function(): boolean
		return isOpen() or TransitionOrchestrator.IsPresent(screenId)
	end
end

--- Get the current phase for a screen (non-reactive).
function TransitionOrchestrator.GetPhase(screenId: string): TransitionPhase
	local binding = bindings[screenId]
	if binding then
		return binding.Phase()
	end
	return "Unmounted"
end

--- Get a transition handle for a screen. Components call this to consume transition state.
function TransitionOrchestrator.UseTransition(screenId: string): TransitionHandle
	return {
		Phase = function(): TransitionPhase
			local binding = bindings[screenId]
			return if binding then binding.Phase() else "Mounted"
		end,
		Progress = function(): number
			local binding = bindings[screenId]
			if not binding then return 1 end
			return if type(binding.Progress) == "function" then binding.Progress() else binding.Target()
		end,
		--- ms-53 D7: DELEGATES to `Stagger.window`, which is now the only copy of
		--- this curve. The one replaced here derived each item's window from the
		--- progress REMAINING after its own start, so the last item in a list was
		--- always the fastest; `ItemDuration` gives every item the same one.
		---
		--- INDEX IS 0-BASED HERE and 1-based there. Converted rather than changed,
		--- because this module's suite asserts `StaggerOffset(0)` is the first item
		--- and rewriting the callers of a stagger nobody calls is not worth a
		--- breaking change.
		StaggerOffset = function(index: number)
			return function(): number
				local binding = bindings[screenId]
				if not binding then return 0 end
				local progress = function(): number
					return if type(binding.Progress) == "function" then binding.Progress() else binding.Target()
				end
				return Stagger.window({
					BaseProgress = progress,
					Index = index + 1,
					DelayPerItem = binding.Preset.StaggerDelay,
					ItemDuration = binding.Preset.StaggerItemDuration,
				})()
			end
		end,
	}
end

--- Progress getter for a screen, or nil when the screen has no binding.
---
--- This is the shape `Flux.SetProgressResolver` expects, so an application wires
--- the two packages together in one line at boot:
---
---     Flux.SetProgressResolver(Aether.TransitionOrchestrator.UseTransitionProgress)
---
--- Flux previously required Aether and reached for UseTransition itself, which
--- inverted the package stack (ms-43 blueprint B-1). Returning nil rather than a
--- constant lets Flux distinguish "no such screen" from "screen fully mounted".
function TransitionOrchestrator.UseTransitionProgress(screenId: string): (() -> number)?
	local binding = bindings[screenId]
	if not binding then return nil end
	return binding.ReadProgress
end

--- Check if a screen has a bound transition preset.
function TransitionOrchestrator.HasBinding(screenId: string): boolean
	return bindings[screenId] ~= nil
end

--- Remove a transition binding for a screen.
function TransitionOrchestrator.Unbind(screenId: string)
	bindings[screenId] = nil
end

do
	ScreenStack.OnScreenOpened(function(screenId: string)
		TransitionOrchestrator.Enter(screenId)
	end)
	ScreenStack.OnScreenClosing(function(screenId: string)
		TransitionOrchestrator.Exit(screenId)
		--- NOTHING TO WAIT FOR. A screen with no bound transition has no exit to
		--- animate, so it settles on this frame -- otherwise it sits in `closing`
		--- for the rest of the process, and anything waiting on it under
		--- `SwitchMode = "wait"` never opens at all.
		if not bindings[screenId] then
			ScreenStack._ExitSettled(screenId)
		end
	end)
end

return TransitionOrchestrator
