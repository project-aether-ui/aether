--!strict
-- tests/runner/fuzz.luau — seeded, replayable fuzzing on the clock/driver seam (ms-42 M4).
--
-- WHY THIS IS POSSIBLE: ADR-004 made the scheduler steppable by a manual driver (Scheduler:Advance)
-- with no wall clock, and ADR-004/M2 proved the sim is a pure function of (initial state, input
-- trace, step count). So thousands of virtual seconds of RANDOMISED input cost only CPU, and any
-- interesting behaviour a random trace finds is perfectly REPLAYABLE from its seed — the two
-- properties fuzzing lives on. This harness is scenario-agnostic: the caller supplies how to build a
-- fresh world, how to turn a PRNG into a per-tick input, how to step, and what invariant to check.
--
-- WHAT IT GIVES YOU: a deterministic PRNG (seed ⇒ identical trace), a seed sweep that collects every
-- invariant violation, replay (re-run a seed to reproduce exactly), and SHRINK (delta-debug a failing
-- trace down to a minimal repro), so a failure is reported as the shortest input sequence that still
-- breaks the invariant, not a 10,000-tick haystack.
local Fuzz = {}

-- Deterministic, replayable xorshift32. Same seed ⇒ same stream, on every machine and every run.
export type Rng = { u32: () -> number, float: () -> number, range: (number, number) -> number, int: (number) -> number }
function Fuzz.newRng(seed: number): Rng
	local s = bit32.band(math.floor(seed), 0xffffffff)
	if s == 0 then
		s = 0x9e3779b9 -- xorshift must not start at 0
	end
	local function u32(): number
		s = bit32.band(bit32.bxor(s, bit32.lshift(s, 13)), 0xffffffff)
		s = bit32.bxor(s, bit32.rshift(s, 17))
		s = bit32.band(bit32.bxor(s, bit32.lshift(s, 5)), 0xffffffff)
		return s
	end
	return {
		u32 = u32,
		float = function(): number
			return u32() / 4294967296
		end,
		range = function(lo: number, hi: number): number
			return lo + (u32() / 4294967296) * (hi - lo)
		end,
		int = function(n: number): number
			return (u32() % n) + 1
		end,
	}
end

-- A scenario the harness knows how to fuzz. C = ctx type (a fresh world+state), I = input type.
export type Scenario<C, I> = {
	build: () -> C, -- fresh, isolated scenario (its own Scheduler + state); compiled, ready to step
	genInput: (rng: Rng, tick: number) -> I, -- one tick's input from the seeded PRNG
	applyInput: (ctx: C, input: I) -> (), -- stash the input where the systems will read it
	step: (ctx: C) -> (), -- advance exactly one tick (ctx.sched:Advance(1))
	check: (ctx: C, tick: number) -> (boolean, string?), -- invariant after the tick
	hash: (ctx: C) -> number, -- final state fingerprint (for replay-determinism checks)
	neutral: I, -- an input known safe — used to delta-debug during shrink
}

export type RunResult = { ok: boolean, failTick: number?, msg: string?, hash: number }

-- Regenerate the deterministic input trace for a seed. Pure function of (seed, ticks).
function Fuzz.trace<C, I>(scn: Scenario<C, I>, seed: number, ticks: number): { I }
	local rng = Fuzz.newRng(seed)
	local t: { I } = {}
	for i = 1, ticks do
		t[i] = scn.genInput(rng, i)
	end
	return t
end

-- Run one EXPLICIT trace to completion (or first invariant break). Fresh world each call.
function Fuzz.runTrace<C, I>(scn: Scenario<C, I>, trace: { I }): RunResult
	local ctx = scn.build()
	for i = 1, #trace do
		scn.applyInput(ctx, trace[i])
		scn.step(ctx)
		local ok, msg = scn.check(ctx, i)
		if not ok then
			return { ok = false, failTick = i, msg = msg or "invariant failed", hash = scn.hash(ctx) }
		end
	end
	return { ok = true, failTick = nil, msg = nil, hash = scn.hash(ctx) }
end

export type Failure<I> = { seed: number, failTick: number, msg: string, trace: { I } }
export type SweepResult<I> = { failures: { Failure<I> }, hashes: { [number]: number }, seeds: { number } }

-- Sweep a set of seeds (explicit `seeds`, or `count` from `baseSeed`). Collects every violation and
-- a seed→final-hash map (a cross-run determinism ledger). Never stops early — one bad seed does not
-- hide the rest.
function Fuzz.sweep<C, I>(scn: Scenario<C, I>, opts: { seeds: { number }?, count: number?, baseSeed: number?, ticks: number }): SweepResult<I>
	local seeds = opts.seeds
	if not seeds then
		seeds = {}
		local base = opts.baseSeed or 1
		for i = 0, (opts.count or 100) - 1 do
			seeds[i + 1] = base + i
		end
	end
	local failures: { Failure<I> } = {}
	local hashes: { [number]: number } = {}
	for _, seed in ipairs(seeds) do
		local trace = Fuzz.trace(scn, seed, opts.ticks)
		local r = Fuzz.runTrace(scn, trace)
		hashes[seed] = r.hash
		if not r.ok then
			failures[#failures + 1] = { seed = seed, failTick = r.failTick :: number, msg = r.msg :: string, trace = trace }
		end
	end
	return { failures = failures, hashes = hashes, seeds = seeds }
end

-- Delta-debug a failing trace to a minimal repro: (1) truncate to the failing prefix, then
-- (2) replace each remaining input with `neutral` and keep the replacement whenever the trace STILL
-- fails — so only the inputs actually needed to break the invariant survive.
function Fuzz.shrink<C, I>(scn: Scenario<C, I>, trace: { I }): { I }
	local r0 = Fuzz.runTrace(scn, trace)
	assert(not r0.ok, "shrink called on a trace that does not fail")
	-- 1. truncate to the failing prefix (everything after the break is irrelevant)
	local cur: { I } = {}
	for i = 1, r0.failTick :: number do
		cur[i] = trace[i]
	end
	-- 2. neutralise inputs that are not needed
	for i = 1, #cur do
		local saved = cur[i]
		if saved ~= scn.neutral then
			cur[i] = scn.neutral
			if Fuzz.runTrace(scn, cur).ok then
				cur[i] = saved -- that input was load-bearing; put it back
			end
		end
	end
	return cur
end

-- Count the non-neutral inputs left in a (shrunk) trace — the size of the minimal repro.
function Fuzz.activeCount<C, I>(scn: Scenario<C, I>, trace: { I }): number
	local n = 0
	for _, v in ipairs(trace) do
		if v ~= scn.neutral then
			n += 1
		end
	end
	return n
end

return Fuzz
