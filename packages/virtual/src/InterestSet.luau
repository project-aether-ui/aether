--!strict
--[[
	InterestSet — which keys are worth keeping state alive for, bounded independent
	of how many keys exist.

	THE DEFECT THIS EXISTS TO MAKE IMPOSSIBLE (ms-47, 2026-08-10)
	PrismStudio cost 1160 KB per entity against a 28 KB baseline with it off — a 30x
	gap, and the hitching went with it, because Luau's GC is allocation-driven and
	the bill lands wherever the next allocation happens. The explorer's rows
	unmounted correctly. Their reactive scopes, ECS subscriptions and cached
	snapshots did not. A heap walk could not name it: the devtools root priced at
	0.00 MB / 3 tables, because the memory was in closures and a graph walk cannot
	reach upvalues.

	So the thing that leaked was invisible to the mounted-set AND to the walker.
	That is the argument for a primitive rather than a fix: the bug is not visible
	at the site where it happens.

	RELEASE IS DERIVED, NOT REMEMBERED — the one decision everything else follows
	from. Manual Acquire/Release is exactly where these leaks come from: the acquire
	gets wired up, and the release is forgotten on ONE path — an early return, an
	error, a reorder. You cannot review your way out of that, because the missing
	call is not written anywhere to be reviewed.

	An epoch/diff makes it structural. You declare what you want THIS pass; anything
	you do not declare is released for you:

	    set:Begin()
	    for _, key in visibleKeys do set:Want(key) end
	    set:Commit()          -- materialises the new, releases the dropped

	There is no spelling of "forgot to release". Forgetting to `Want` releases.

	HYSTERESIS IS LOAD-BEARING, NOT A NICETY. Without it a fast scroll
	materialises and dematerialises on every frame, and you have made things WORSE
	than the leak: you now pay construction repeatedly instead of once. That
	regression is invisible to the retention measurement that motivated this whole
	exercise — it shows up only in a phase timer. `GraceFrames` keeps a dropped key
	alive for a few commits; `VirtualList.Overscan` is the render-side analogue.

	GRACE IS COUNTED IN COMMITS, NOT SECONDS. A wall-clock grace period makes the
	same input produce different teardown depending on frame rate, which is
	untestable and un-reproducible. One commit is one tick of whoever drives this.

	PIN IS WHAT MAKES THIS MORE THAN A VIEWPORT CACHE. Interest and viewport are
	genuinely different sets: interest can EXCEED the viewport (a pinned watch on an
	offscreen entity, a graph sampling a value you scrolled past) and can be
	NARROWER than it (a collapsed tree row is visible and mounted but needs no
	per-property subscription). A primitive that could only track the viewport would
	not survive its second consumer.

	WHAT THIS DELIBERATELY IS NOT (plan section 9). Not a scheduler, not a priority
	queue, and it does not know what vide is. Materialize/Dematerialize are opaque
	callbacks, which is precisely what lets a profiler surface with no UI use it. If
	this file ever imports a reactive library, the abstraction has gone wrong.

	NOTE ON `Count`. The plan called it "reactive, for readouts and for the gate".
	It is a plain getter here, because a reactive Count would mean a dependency on
	a signal library and this package has none by design. A consumer that wants to
	observe it samples it; the gate reads it directly.
]]

export type Config<K, V> = {
	--- Build the expensive thing. Called once per key per materialisation.
	Materialize: (key: K) -> V,
	--- Tear it down. Called with the value Materialize returned.
	Dematerialize: ((key: K, value: V) -> ())?,
	--- Commits a dropped key survives before release. 0 = release immediately.
	--- Defaults to 2; see the note on choosing this at the bottom of the file.
	GraceFrames: number?,
}

export type InterestSet<K, V> = {
	--- Open an epoch. Everything you still want must be declared before Commit.
	Begin: () -> (),
	--- Declare interest in `key` for this epoch.
	Want: (key: K) -> (),
	--- Close the epoch: materialise the newly wanted, release what aged out.
	Commit: () -> (),

	--- The materialised value, or nil.
	Get: (key: K) -> V?,
	--- Keep `key` alive regardless of epochs. Materialises immediately.
	Pin: (key: K) -> (),
	--- Stop pinning. The key rejoins the epoch/grace machinery at the next Commit.
	Unpin: (key: K) -> (),
	--- Whether `key` is pinned.
	IsPinned: (key: K) -> boolean,

	--- How many keys are materialised right now. This is the number the gate
	--- asserts is bounded independent of the collection size.
	Count: () -> number,
	--- Cumulative Materialize / Dematerialize calls. Thrash is invisible to Count
	--- (it stays flat while churning), so bounding construction needs its own
	--- counter — this is what catches a hysteresis regression.
	Stats: () -> { Materialized: number, Dematerialized: number },

	--- Release everything. Teardown; without it the leak simply moves to world
	--- shutdown, which is the same defect one scope out.
	Clear: () -> (),
}

local InterestSet = {}

function InterestSet.new<K, V>(config: Config<K, V>): InterestSet<K, V>
	local materialize = config.Materialize
	local dematerialize = config.Dematerialize
	local graceFrames = config.GraceFrames or 2
	assert(graceFrames >= 0, "GraceFrames must be >= 0")

	--- key -> materialised value. `Count` is the size of this.
	local live: { [K]: V } = {}
	--- key -> true, for keys held independently of epochs.
	local pinned: { [K]: boolean } = {}
	--- key -> the epoch at which it gets released. Present ONLY for keys that are
	--- live, unwanted and unpinned — i.e. keys currently serving out their grace.
	local expiry: { [K]: number } = {}
	--- Declarations made since Begin. Rebuilt each epoch rather than diffed in
	--- place: the diff IS the release mechanism, so it must not be able to
	--- accumulate stale membership.
	local wanted: { [K]: boolean } = {}

	local epoch = 0
	local open = false
	local liveCount = 0
	local materializedTotal = 0
	local dematerializedTotal = 0

	local function release(key: K)
		local value = live[key]
		live[key] = nil
		expiry[key] = nil
		liveCount -= 1
		dematerializedTotal += 1
		if dematerialize then
			dematerialize(key, value)
		end
	end

	local function acquire(key: K)
		live[key] = materialize(key)
		liveCount += 1
		materializedTotal += 1
	end

	local self: InterestSet<K, V>
	self = {
		Begin = function()
			-- Loud rather than tolerant. A nested or forgotten Begin means the
			-- caller's mental model of the epoch is wrong, and silently coping
			-- would hide it until it showed up as a leak — the failure this
			-- module exists to prevent.
			assert(not open, "InterestSet: Begin called while an epoch is already open")
			open = true
			table.clear(wanted :: any)
		end,

		Want = function(key: K)
			assert(open, "InterestSet: Want called outside an epoch (missing Begin)")
			wanted[key] = true
		end,

		Commit = function()
			assert(open, "InterestSet: Commit called without a matching Begin")
			open = false
			epoch += 1

			-- 1. Everything wanted is alive and NOT expiring. Clearing expiry
			--    unconditionally is the rescue path: a key that was counting down
			--    and came back into interest must not be released, and must not be
			--    rebuilt either. That rescue is the entire value of hysteresis —
			--    without it a scroll that reverses pays construction twice.
			for key in wanted do
				expiry[key] = nil
				if live[key] == nil then
					acquire(key)
				end
			end

			-- 2. Anything live, unwanted and unpinned starts its countdown. Only
			--    if it has not already started one, or a key would reset its own
			--    grace every commit and never die.
			for key in live do
				if not wanted[key] and not pinned[key] and expiry[key] == nil then
					expiry[key] = epoch + graceFrames
				end
			end

			-- 3. Sweep. Collected first because releasing mutates `live` and
			--    `expiry` while we walk them.
			local doomed: { K } = {}
			for key, at in expiry do
				if at <= epoch then
					table.insert(doomed, key)
				end
			end
			for _, key in doomed do
				release(key)
			end
		end,

		Get = function(key: K): V?
			return live[key]
		end,

		Pin = function(key: K)
			pinned[key] = true
			expiry[key] = nil
			if live[key] == nil then
				acquire(key)
			end
		end,

		Unpin = function(key: K)
			pinned[key] = nil
			-- No expiry assigned here on purpose: the next Commit decides, and it
			-- has the information this call does not — whether the key is wanted.
			-- Unpinning something still in view must not schedule its release.
		end,

		IsPinned = function(key: K): boolean
			return pinned[key] == true
		end,

		Count = function(): number
			return liveCount
		end,

		Stats = function()
			return { Materialized = materializedTotal, Dematerialized = dematerializedTotal }
		end,

		Clear = function()
			local all: { K } = {}
			for key in live do
				table.insert(all, key)
			end
			for _, key in all do
				release(key)
			end
			table.clear(pinned :: any)
			table.clear(wanted :: any)
			table.clear(expiry :: any)
			open = false
		end,
	}
	return self
end

--[[
	CHOOSING GraceFrames. The default of 2 is a starting point, NOT a measured
	value, and the plan says so: it wants choosing against a real fast-scroll,
	because the quantity it trades is construction cost against retained bytes and
	both are consumer-specific. Too low and a reversing scroll rebuilds; too high
	and the bound the gate asserts grows by the overshoot.

	The instrument for tuning it is `Stats().Materialized` across a scripted
	scroll, not `Count` — Count stays flat while thrashing.
]]

return InterestSet
