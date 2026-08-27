--!strict
--!tier math
--[[
	InterestSet suite.

	Pure bookkeeping over a keyed table, so headless testing covers it COMPLETELY —
	no Instances, no engine, no stand-ins that accept anything.

	The gate (tests/gates/verify_interest_bounded.luau) asserts the property that
	matters at scale: the live set is bounded independent of N. This suite covers
	what a bound cannot see — WHICH keys, the rescue path, the pin/epoch
	interaction, and that Dematerialize is handed the value it must free. A bounded
	set that releases the wrong key passes the gate and is still broken.

	CALLS ARE DOT-STYLE, matching ItemIndex next door: these are closure tables, and
	the exported types declare no self parameter. `set:Want(k)` would pass the set
	itself as the key and quietly interest the wrong thing.
]]

local InterestSet = require("../src/InterestSet")

type Rec = { Key: number }

--- A recording harness. Every test needs the same three questions answered — what
--- was built, what was torn down, in what order — and hand-rolling that per test is
--- how a suite ends up asserting counts whose contents it never checks.
local function harness(graceFrames: number?)
	local built: { number } = {}
	local freed: { number } = {}
	local set = InterestSet.new({
		Materialize = function(key: number): Rec
			table.insert(built, key)
			return { Key = key }
		end,
		Dematerialize = function(key: number, value: Rec)
			-- Asserting the VALUE, not just the key: handing Dematerialize the wrong
			-- value is a leak that every count-based assertion passes.
			assert(value.Key == key, `Dematerialize got value for {value.Key} under key {key}`)
			table.insert(freed, key)
		end,
		GraceFrames = graceFrames,
	})
	return set, built, freed
end

local function pass(set: InterestSet.InterestSet<number, Rec>, keys: { number })
	set.Begin()
	for _, k in keys do
		set.Want(k)
	end
	set.Commit()
end

local function run()
	-- ── 1. The diff releases what you stop declaring ─────────────────────────
	print("[TEST] InterestSet: forgetting to Want is what releases...")
	do
		local set, built, freed = harness(0)
		pass(set, { 1, 2, 3 })
		assert(set.Count() == 3, `three wanted, three live, got {set.Count()}`)
		assert(#built == 3, "each wanted key materialised once")

		-- 2 is simply not declared. There is no Release call anywhere in this test.
		pass(set, { 1, 3 })
		assert(set.Count() == 2, `dropping one leaves two, got {set.Count()}`)
		assert(#freed == 1 and freed[1] == 2, "the undeclared key is the one released")
		assert(set.Get(2) == nil, "a released key reads back nil")
		assert((set.Get(1) :: Rec).Key == 1, "surviving keys keep their value")
	end
	print("  ✓ release is derived from the diff, never called")

	-- ── 2. A key still wanted is never rebuilt ───────────────────────────────
	print("[TEST] InterestSet: re-declaring does not re-materialise...")
	do
		local set, built = harness(0)
		pass(set, { 1, 2 })
		pass(set, { 1, 2 })
		pass(set, { 1, 2 })
		-- Three passes, two constructions. If this reads 6, the diff has become a
		-- rebuild and every consumer pays construction every frame.
		assert(#built == 2, `steady state builds nothing new, got {#built}`)
		assert(set.Stats().Materialized == 2, "Stats agrees with the harness")
	end
	print("  ✓ a steady interest set costs nothing per epoch")

	-- ── 3. Grace, and the rescue that justifies it ───────────────────────────
	print("[TEST] InterestSet: grace defers release by exactly N commits...")
	do
		local set, _, freed = harness(2)
		pass(set, { 1 })
		pass(set, {}) -- epoch 2: countdown starts, dies at 4
		assert(set.Count() == 1, "still alive one commit after being dropped")
		pass(set, {}) -- epoch 3
		assert(set.Count() == 1, "still alive two commits after")
		pass(set, {}) -- epoch 4
		assert(set.Count() == 0, "released on the third")
		assert(#freed == 1 and freed[1] == 1, "and released exactly once")
	end

	print("[TEST] InterestSet: a key that comes back mid-grace is rescued, not rebuilt...")
	do
		-- THE POINT OF HYSTERESIS. A scroll that reverses must not pay construction
		-- twice; without this rescue the primitive is worse than the leak it replaces.
		local set, built, freed = harness(2)
		pass(set, { 1 })
		pass(set, {}) -- counting down
		pass(set, { 1 }) -- back in view
		assert(#built == 1, `rescued, not rebuilt — got {#built} constructions`)
		assert(#freed == 0, "and never released")

		-- The countdown must be CLEARED, not paused: dropped again, it gets a full
		-- grace period rather than the one commit it had left.
		pass(set, {})
		pass(set, {})
		assert(set.Count() == 1, "a rescued key gets a fresh full grace period")
		pass(set, {})
		assert(set.Count() == 0, "and then dies on schedule")
	end

	print("[TEST] InterestSet: grace does not reset itself every commit...")
	do
		-- The bug: assigning expiry unconditionally means an unwanted key pushes its
		-- own deadline forward forever and is never released. Count stays bounded
		-- throughout, so only elapsed commits can find this.
		local set, _, freed = harness(1)
		pass(set, { 1 })
		for _ = 1, 5 do
			pass(set, {})
		end
		assert(#freed == 1 and freed[1] == 1, "an unwanted key dies once its grace elapses")
		assert(set.Count() == 0, "and does not linger forever")
	end
	print("  ✓ hysteresis defers release without preventing it")

	-- ── 4. Pin — interest that outlives the viewport ─────────────────────────
	print("[TEST] InterestSet: a pinned key survives never being wanted...")
	do
		local set, built, freed = harness(0)
		set.Pin(7)
		assert(set.Count() == 1, "Pin materialises immediately")
		assert(#built == 1 and built[1] == 7, "and builds the pinned key")
		for _ = 1, 10 do
			pass(set, { 1 })
		end
		assert(set.Get(7) ~= nil, "ten epochs that never wanted it, still alive")
		assert(#freed == 0, "nothing released")
		assert(set.IsPinned(7), "and it reports as pinned")
	end

	print("[TEST] InterestSet: unpinning something still in view does not release it...")
	do
		local set, _, freed = harness(0)
		pass(set, { 1 })
		set.Pin(1)
		set.Unpin(1)
		pass(set, { 1 })
		-- Unpin must not schedule a release: at the moment it is called it does not
		-- know whether the key is still wanted. The next Commit does.
		assert(#freed == 0, "unpinning a visible key keeps it")
		assert(set.Count() == 1, "and it stays live")
		pass(set, {})
		assert(set.Count() == 0, "it rejoins the epoch machinery and dies when dropped")
	end

	print("[TEST] InterestSet: pinning a key already counting down cancels its release...")
	do
		local set, built, freed = harness(1)
		pass(set, { 1 })
		pass(set, {}) -- counting down
		set.Pin(1)
		pass(set, {})
		pass(set, {})
		assert(set.Count() == 1, "Pin cancels an in-flight countdown")
		assert(#built == 1, "rescued rather than rebuilt")
		assert(#freed == 0, "and never released")
	end
	print("  ✓ pinned interest is independent of the viewport in both directions")

	-- ── 5. Teardown ──────────────────────────────────────────────────────────
	print("[TEST] InterestSet: Clear releases everything, pinned included...")
	do
		-- Without this the leak moves to world shutdown, which is the same defect
		-- one scope out.
		local set, _, freed = harness(5)
		pass(set, { 1, 2, 3 })
		set.Pin(9)
		set.Clear()
		assert(set.Count() == 0, "Clear empties the set")
		assert(#freed == 4, `everything is torn down, including pins — got {#freed}`)
		assert(not set.IsPinned(9), "pins are dropped too")

		-- Usable afterwards rather than poisoned.
		pass(set, { 1 })
		assert(set.Count() == 1, "the set still works after Clear")
	end
	print("  ✓ teardown does not leave the leak one scope out")

	-- ── 6. Misuse is loud ────────────────────────────────────────────────────
	print("[TEST] InterestSet: epoch misuse raises rather than coping...")
	do
		local set = InterestSet.new({
			Materialize = function(k: number): number
				return k
			end,
		})
		assert(not (pcall(function() set.Want(1) end)), "Want outside an epoch raises")
		set.Begin()
		assert(not (pcall(function() set.Begin() end)), "a nested Begin raises")
		set.Commit()
		assert(not (pcall(function() set.Commit() end)), "Commit without Begin raises")
	end

	print("[TEST] InterestSet: Dematerialize is optional...")
	do
		local set = InterestSet.new({
			Materialize = function(k: number): number
				return k
			end,
			GraceFrames = 0,
		})
		set.Begin()
		set.Want(1)
		set.Commit()
		set.Begin()
		set.Commit()
		assert(set.Count() == 0, "a set with no teardown callback still releases")
	end
	print("  ✓ misuse raises; the optional callback stays optional")

	print("[TEST] InterestSet tests passed successfully!")
end

local T = require("@testkit")
T.test("InterestSet", run, "math")

return T.run("InterestSet")
