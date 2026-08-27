--!strict
--[[
	tests/gates/run.luau — the ONE way to run the verify gates.

	    lune run tests/gates/run.luau              COMPLETE verification: suites once, then every gate
	    lune run tests/gates/run.luau --gates-only skip the suite pass (leaves suite-backed gates unverified — announced)
	    lune run tests/gates/run.luau --all        also dispatch gates that a head already covers
	    lune run tests/gates/run.luau --list       show the plan and the coverage graph, run nothing

	THERE IS NO FAST/SLOW TIER, AND THAT IS DELIBERATE (es9, 2026-08-08). A cost threshold
	was tried and removed. It was a tuned number — 100 s, then 300 s, neither defensible —
	standing in for a structural problem: two gates were expensive because they RAN TEST
	SUITES, which is the test runner's job, not a gate's. Once the suites run once up front
	and the gates read those verdicts, nothing is expensive enough to need a tier, and the
	number, the flag and the "which gates got held back" bookkeeping all delete themselves.
	Prefer removing the reason over tuning the workaround.

	The inner dev loop is `lune run tests/run.luau` (~40 s, tier-filtered). THIS is the
	before-you-push command, and it checks everything.

	WHY THIS EXISTS (ms-47, 2026-08-08)

	Running the gates by hand — a shell loop over tests/gates/verify_*.luau — was slow for a
	reason nobody had looked at and wrong in a way nobody had noticed.

	1. SERIAL, AND REDUNDANT. The gates re-run their own prefix as subprocesses:

	       37m3 → 37m2 → 37m1 → 36m4 → 36m3 → 36m2 → 36m1 → 35m5
	       35m2 → 35m1
	       35m4 → m1

	   A full sweep therefore executes 35m5 EIGHT times — once directly, then again inside
	   each descendant. The measured per-gate costs in onboard.luau's SLOW_GATES table are
	   cumulative for exactly this reason: 36m2 costs 33s because it contains 36m1's 31s.
	   Deduplication is not an optimisation here, it is removing repeated work: running only
	   the chain HEADS covers every gate, because the head runs the rest itself.

	2. JUDGED BY STDOUT, WHICH LIES IN BOTH DIRECTIONS. Matching `": PASS"` marks 37m1/37m2/
	   37m3 green — they print `verify_36m4 re-run: PASS` while re-running sub-gates — and
	   that hid three real failures through an entire sweep. Matching `"FAIL"` condemns
	   verify_35m2 on prose inside its own PASSING output. Gates `process.exit(1)` when they
	   fail; the exit code is the only signal that means what it says. `Parallel.Result.ok`
	   is that code, so this path cannot regress into grepping.

	THE COVERAGE GRAPH IS DERIVED, NEVER HARDCODED. A hardcoded head list would rot the
	first time a gate adds or drops a sub-gate re-run, and it would rot SILENTLY — the sweep
	would keep passing while quietly skipping a gate nothing else covers. So we read it out
	of the sources every run. Comments are stripped first: every gate's header carries
	`Run from repo root: lune run tests/gates/verify_X.luau`, which is a self-reference in
	prose, not an invocation.

	GATES RUN SERIALLY, AND THAT IS A CORRECTNESS DECISION. Measured on one 45-gate plan:
	--jobs=1 → 0 failed; --jobs=4 → 8 failed, every one of which passes standalone. A gate is
	not one cheap process like a test suite — it re-runs a whole chain, and links spawn
	suites — so a handful of workers becomes dozens of concurrent processes and children
	start returning non-zero. A gate that fails because the machine was busy trains you to
	re-run and shrug, which is how a suite stops being believed. Parallelism belongs where
	the children are independent and bounded: the SUITE pass below, and inside verify_37m4.

	CONCURRENCY IS tests/support/runner/parallel.luau — the same bounded pool the test runner
	uses, and the "verify orchestrator" its own header anticipated in ms-42 M3: every job runs
	exactly once, a crash becomes a failed Result rather than a silent omission, results come
	back in job order.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local Parallel = require("../support/runner/parallel")
local SuiteResults = require("../support/runner/suite_results")

local GATE_DIR = "tests/gates"

--- Without this, every gate's own header ("Run from repo root: lune run
--- tests/gates/verify_X.luau") reads as a self-invocation, and a gate that "covers itself"
--- would be dropped from the plan entirely.
local stripComments = require("./source_scan").stripComments

-- ─── Plan ────────────────────────────────────────────────────────────────────────
local runAll, listOnly, gatesOnly = false, false, false
local jobsOverride: number? = nil
for _, a in ipairs(process.args) do
	if a == "--all" then
		runAll = true
	elseif a == "--gates-only" then
		gatesOnly = true
	elseif a == "--list" then
		listOnly = true
	else
		local j = string.match(a, "^%-%-jobs=(%d+)$")
		if j then
			jobsOverride = math.max(1, tonumber(j) :: number)
		elseif string.sub(a, 1, 2) == "--" then
			print(`run.luau: unknown flag {a} (want --all | --gates-only | --list | --jobs=N)`)
			process.exit(1)
		end
	end
end

local gates: { string } = {}
for _, name in ipairs(fs.readDir(GATE_DIR)) do
	-- `verify_` prefix only: tests/gates/ also holds the shared registers the gates import
	-- (shared_state_register, theme_scope_conformance, reflection_overlay) and the
	-- all_gates aggregator. Those print no verdict and are not gates.
	if string.match(name, "^verify_.*%.luau$") then
		table.insert(gates, name)
	end
end
table.sort(gates)

-- coveredBy[X] = a gate that re-runs X, so X need not be dispatched directly.
local coveredBy: { [string]: string } = {}
for _, name in ipairs(gates) do
	local body = stripComments(fs.readFile(`{GATE_DIR}/{name}`))
	for sub in string.gmatch(body, "tests/gates/(verify_[%w_]+%.luau)") do
		if sub ~= name then
			coveredBy[sub] = name
		end
	end
end

local plan: { string } = {}
for _, name in ipairs(gates) do
	if runAll or coveredBy[name] == nil then
		table.insert(plan, name)
	end
end

--- PERF-SENSITIVE gates are the ONE classification left, and unlike a cost tier it is a real
--- property rather than a tuned number: their verdict depends on how fast the machine was,
--- not only on what the code says. verify_37m5 runs CompoundPerf ("4 swept wheel probes/tick
--- fit the fixed-dt budget"). Measured beside other work, that budget reads contention, and
--- can flip in either direction. So these run ALONE, after everything else has drained — and
--- they never reuse a shared suite verdict either, since the shared pass is itself parallel.
local PERF_SENSITIVE: { [string]: boolean } = {
	["verify_37m5.luau"] = true,
}

if listOnly then
	local dispatched: { [string]: boolean } = {}
	for _, n in ipairs(plan) do
		dispatched[n] = true
	end
	print(`gates: {#gates} total, {#plan} dispatched, {#gates - #plan} covered transitively\n`)
	for _, name in ipairs(gates) do
		if dispatched[name] then
			print(if PERF_SENSITIVE[name] then `  RUN  {name}  (perf-sensitive: runs alone, last)` else `  RUN  {name}`)
		else
			print(`       {name}  ← covered by {coveredBy[name]}`)
		end
	end
	return
end

-- ─── Run ─────────────────────────────────────────────────────────────────────────
local jobs: { Parallel.Job } = {}
local perfJobs: { Parallel.Job } = {}
for _, name in ipairs(plan) do
	local job: Parallel.Job = { name = name, argv = { "run", `{GATE_DIR}/{name}` } }
	if PERF_SENSITIVE[name] then
		table.insert(perfJobs, job)
	else
		table.insert(jobs, job)
	end
end

--- GATES RUN SERIALLY BY DEFAULT, AND THAT IS A CORRECTNESS DECISION, NOT A TODO.
---
--- Measured 2026-08-08 on this plan: `--jobs=1` → 45 dispatched, 0 failed. `--jobs=4` → the
--- SAME 45, 8 failed. Every one of those 8 passes standalone. Parallelism was manufacturing
--- failures, not finding them.
---
--- The cause is what these gates ARE. A gate is not one cheap process like a test suite: it
--- re-runs its whole prefix chain (37m2→37m1→36m4→…), and several links spawn e2e suites of
--- their own. Four workers therefore means dozens of concurrent processes, deep trees of
--- them, and the spawned children start returning non-zero. A gate that fails because the
--- machine was busy is worse than a slow gate — it trains you to re-run and shrug, which is
--- how a suite stops being believed.
---
--- Speed came from NOT DOING REDUNDANT WORK, not from doing it at once. `--jobs=N` is
--- available for experimenting; treat any failure it produces as suspect until reproduced
--- at --jobs=1.
local jobsN = math.clamp(jobsOverride or 1, 1, math.max(1, #jobs))

local scope = if runAll then `ALL {#plan}` else `{#plan} dispatched, {#gates - #plan} covered transitively`
print(`--- gate runner: {scope}; jobs={jobsN} ---`)

local t0 = os.clock()

-- ─── The suite pass: run them ONCE, up front, at full width ──────────────────────────────
--
-- This is the DEFAULT, not a flag, and it is what removed the need for a fast/slow tier.
-- verify_37m4 and verify_37m5 spawn e2e suites that tests/run.luau also runs, so verifying
-- everything did the heavy physics twice — and the gates' copy was serial, ~1200s of a
-- ~1340s sweep. Suites are exactly the workload that DOES parallelise safely: one process
-- each, independent, no nesting. So they run here at jobs=16 and the gates read the verdicts.
--
-- Two things make reuse safe rather than a cache:
--   * the token lives only in this sweep, so a stale manifest is refused (suite_results.luau)
--   * env is passed EXPLICITLY to every child — lune does not inherit runtime mutations, and
--     the first version of this silently reused nothing while still reporting PASS.
local gateEnv: { [string]: string } = {
	-- Nested runners must not each open their own pool: parallelism belongs at ONE level.
	PRISM_TEST_JOBS = "1",
}

if gatesOnly then
	print("    --gates-only: SKIPPING the suite pass. Gates that assert on suites will run")
	print("    them themselves (slow), and no suite verdict is shared. Not the push bar.")
else
	local manifest = ".artifacts/sweep_suite_results.json"
	if not fs.isDir(".artifacts") then
		fs.writeDir(".artifacts")
	end
	local token = SuiteResults.mintToken()
	gateEnv[SuiteResults.TOKEN_ENV] = token
	gateEnv[SuiteResults.PATH_ENV] = manifest

	print("--- suites (once, at full width; gates below reuse these verdicts) ---")
	local r = process.create("lune", { "run", "tests/run.luau", "--all", `--emit-results={manifest}` }, {
		env = { [SuiteResults.TOKEN_ENV] = token },
	})
	local out = r.stdout:readToEnd()
	local status = r:status()
	local summary = string.match(out, "%-%-%- [%d%.]+s total %(jobs=%d+%) %-%-%-") or "(no summary line)"
	print(`    suites: {if status.ok then "PASS" else "FAIL"}  {summary}`)

	-- The reuse path must PROVE it worked. Its first version was a silent no-op — the token
	-- never reached the child, no manifest was written, every gate re-ran its suites, and the
	-- sweep still said PASS. An optimisation that cannot report its own failure is a liability.
	if status.ok and not fs.isFile(manifest) then
		print(`\nEXPECTED {manifest} after the suite pass and it is not there.`)
		print("Suite verdicts will NOT be reused; gates will re-run their suites. Investigate")
		print("before trusting the timings — this is the silent-no-op shape.")
		gateEnv[SuiteResults.TOKEN_ENV] = nil :: any
		gateEnv[SuiteResults.PATH_ENV] = nil :: any
	end

	if not status.ok then
		-- Do NOT continue into the gates. They would reuse failing verdicts and report the
		-- same failure again, burying which suite actually broke.
		print("\nSUITES FAILED — fix them before the gates; `lune run tests/run.luau --all` for detail.")
		for line in string.gmatch(out, "[^\n]+") do
			if string.match(line, "^FAIL") or string.match(line, "^FAILED:") then
				print(`   {line}`)
			end
		end
		process.exit(1)
	end
end

for _, j in ipairs(jobs) do
	j.env = gateEnv
end
for _, j in ipairs(perfJobs) do
	j.env = gateEnv
end

local function report(done: number, total: number, r: Parallel.Result)
	print(string.format("  [%d/%d] %-42s %s  %.1fs", done, total, r.name, if r.ok then "PASS" else "FAIL", r.secs))
end

local results = Parallel.run(jobs, jobsN, { onDone = report })

-- Perf-sensitive gates run ALONE and LAST — after the pool has drained, so nothing else is
-- competing for CPU when a timing budget is measured.
if #perfJobs > 0 then
	print(`--- {#perfJobs} perf-sensitive gate(s), run alone (jobs=1) so timing budgets measure the code, not the pool ---`)
	for _, r in ipairs(Parallel.run(perfJobs, 1, { onDone = report })) do
		table.insert(results, r)
	end
end

-- ─── Report ──────────────────────────────────────────────────────────────────────
local failed: { Parallel.Result } = {}
local retiredTotal = 0
local retiredBy: { string } = {}
for _, r in ipairs(results) do
	if not r.ok then
		table.insert(failed, r)
	end
	-- Surface retired rules in ONE place. A gate can pass while enforcing less than its name
	-- suggests; that gap belongs in the summary, not only in the gate's own scrollback.
	local n = tonumber(string.match(r.stdout, "%((%d+) rule%(s%) RETIRED"))
	if n then
		retiredTotal += n
		table.insert(retiredBy, `{r.name}: {n}`)
	end
end

print(string.format("\n--- %.1fs wall, %d dispatched, %d failed ---", os.clock() - t0, #results, #failed))

if retiredTotal > 0 then
	print(`\nRETIRED RULES ({retiredTotal} total) — these gates pass while NOT enforcing:`)
	for _, line in ipairs(retiredBy) do
		print(`   {line}`)
	end
end

if #failed > 0 then
	print("")
	for _, r in ipairs(failed) do
		print(`===== {r.name} (exit {r.code}) =====`)
		for line in string.gmatch(r.stdout, "[^\n]+") do
			if string.match(line, "^FAIL") or string.match(line, "VERIFY") then
				print(`   {line}`)
			end
		end
		if r.stderr ~= "" then
			print(`   stderr: {string.sub(r.stderr, 1, 400)}`)
		end
	end
	process.exit(1)
end

print("\nALL GATES PASS")
