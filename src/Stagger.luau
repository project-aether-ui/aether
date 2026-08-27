--!strict
--[[
	Aether · Stagger — the ONE per-item transition window (ms-53 D7)

	    local p = Stagger.window({
	        BaseProgress = motion.Progress,
	        Index = 3,              -- 1-based; item 1 starts immediately
	        DelayPerItem = 0.06,
	        ItemDuration = 0.6,
	    })

	WHAT IT IS. Framer Motion calls this ORCHESTRATION: a parent's transition
	drives its children, each starting a little after the last. Angular spells the
	same idea `query(':enter', stagger(100, [...]))`. Vue has no built-in.

	WHY IT MOVED HERE. This maths existed in TWO places with THREE entry points —
	`Flux/PropertyTransforms.Stagger`, `Flux/MotionPackManager`'s `Stagger(index)`
	(which already delegated to it), and `Aether/TransitionOrchestrator`'s
	`StaggerOffset(index)`, which had a curve of its own. Between them: ZERO call
	sites outside their own suites.

	IT LIVES IN AETHER RATHER THAN IN FLUX because Flux DEPENDS ON AETHER. The
	sprint spec recommended the opposite — Flux as the home, since motion maths
	belongs with motion — and the dependency graph refutes it: `TransitionOrchestrator`
	is inside Aether and cannot call up into Flux without a cycle. Flux's
	`PropertyTransforms.Stagger` now delegates down to this.

	THE CURVE IS THE EXPLICIT-DURATION ONE. `TransitionOrchestrator` derived each
	item's window from the progress REMAINING after its own start
	(`(p - start) / (1 - start)`), which couples an item's duration to its start
	time: the last item in a list is always the fastest. An explicit `ItemDuration`
	says what it means and gives every item the same one.

	THE DEFECT TO KNOW ABOUT. Every shipped preset had `StaggerDelay` unset, so
	`start = index * 0 = 0` and every child got IDENTICAL progress. A stagger that
	silently degrades to uniform is invisible: nothing errors, nothing warns, and
	the animation merely looks like it has no stagger — which is also what a
	correctly-configured stagger of zero looks like. `Stagger.diverges` exists so a
	test can assert the difference rather than assert that a number moved.
]]

local Stagger = {}

export type Props = {
	--- The parent's transition progress, 0-1.
	BaseProgress: () -> number,
	--- 1-BASED. Item 1 starts immediately; item N starts at `(N-1) * DelayPerItem`.
	Index: number,
	--- NIL DEFAULTS, IT DOES NOT DISABLE. Omitting this gives the default delay,
	--- not a stagger of zero -- which is deliberate, and is the change that makes
	--- the inert path unreachable: the shipped presets went a whole milestone with
	--- this unset, and got uniform progress with nothing to indicate it. Pass 0
	--- explicitly to say "no stagger", so that saying it is a decision on the
	--- record rather than an omission.
	DelayPerItem: number?,
	ItemDuration: number?,
}

local DEFAULT_DELAY = 0.08
local DEFAULT_DURATION = 0.6

--- This item's own 0-1 progress, given the parent's.
function Stagger.window(props: Props): () -> number
	local delayPerItem = props.DelayPerItem or DEFAULT_DELAY
	local itemDuration = props.ItemDuration or DEFAULT_DURATION
	local idx = math.max(0, props.Index - 1)
	local startAt = idx * delayPerItem

	return function(): number
		local base = props.BaseProgress()
		--- AT REST, EVERY ITEM IS AT REST. Not a shortcut: without it the last
		--- item in a long list would never quite reach 1, because its window ends
		--- past where the parent's progress stops.
		if base <= 0 then
			return 0
		end
		if base >= 1 then
			return 1
		end

		local elapsed = base - startAt
		if elapsed <= 0 then
			--- Not started yet. This is the whole of the stagger.
			return 0
		end
		return math.clamp(elapsed / itemDuration, 0, 1)
	end
end

--- Do two indices actually differ somewhere in the middle of the parent's
--- transition? The honest question to ask of a stagger, and the one nothing
--- asked for three implementations: a suite that checks a number MOVED passes
--- against a stagger that gives every item the same number.
function Stagger.diverges(a: Props, b: Props, samples: number?): boolean
	local n = samples or 32
	local base = 0
	local aw = Stagger.window({
		BaseProgress = function()
			return base
		end,
		Index = a.Index,
		DelayPerItem = a.DelayPerItem,
		ItemDuration = a.ItemDuration,
	})
	local bw = Stagger.window({
		BaseProgress = function()
			return base
		end,
		Index = b.Index,
		DelayPerItem = b.DelayPerItem,
		ItemDuration = b.ItemDuration,
	})
	for i = 1, n - 1 do
		base = i / n
		if math.abs(aw() - bw()) > 1e-6 then
			return true
		end
	end
	return false
end

--[[
	THE CONTEXT — why three implementations went unused.

	The maths was never the missing piece. Framer's orchestration works because a
	child inherits its parent's animation state implicitly; here every consumer
	would have had to thread `StaggerOffset(i)` into every child by hand, and so
	none did. `ThemeProvider` already establishes the context idiom in this repo.

	INDEX ORDER IS CONSTRUCTION ORDER, which is what Framer uses too (DOM order).
	It means a child's place in the sequence follows from where it is built, and
	nothing has to name a number.
]]

local Deps = require("./Deps")
local vide = Deps.vide

local StaggerContext = if vide and vide.context then vide.context(nil :: any) else nil

export type GroupOptions = {
	Progress: () -> number,
	DelayPerItem: number?,
	ItemDuration: number?,
}

--- Build `fn`'s children as a staggered group. Each `use()` inside takes the
--- next index.
function Stagger.Provide(options: GroupOptions, fn: () -> any): any
	if not StaggerContext then
		return fn()
	end
	local nextIndex = 0
	local group = {
		Options = options,
		Take = function(): number
			nextIndex += 1
			return nextIndex
		end,
	}
	return (StaggerContext :: any)(group, fn)
end

--- This element's own progress within the enclosing group, or nil when there is
--- no group — in which case a caller should use the parent progress unstaggered
--- rather than refuse to animate.
function Stagger.use(): (() -> number)?
	if not StaggerContext then
		return nil
	end
	local group = (StaggerContext :: any)()
	if not group then
		return nil
	end
	return Stagger.window({
		BaseProgress = group.Options.Progress,
		Index = group.Take(),
		DelayPerItem = group.Options.DelayPerItem,
		ItemDuration = group.Options.ItemDuration,
	})
end

return Stagger
