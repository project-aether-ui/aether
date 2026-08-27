--!strict
-- tests/runner/parallel.luau — reusable bounded-concurrency subprocess executor (ms-42 M3).
--
-- WHY: the headless suites and the verify fanout each spawn `lune run <suite>` as a blocking
-- subprocess, SERIALLY — so a chain of independent suites costs the SUM of their wall times even
-- though they share nothing. lune 0.10's `process.create` returns a non-blocking child handle, so N
-- independent suites can run at once. This module is the ONE place that concurrency lives, so the
-- fast runner, a verify orchestrator, and (M4) a fuzzing sweep all get the same pool, the same
-- `--jobs` control, and the same guarantee.
--
-- THE GUARANTEE (why parallel does not weaken a gate): every job runs exactly once; a job's result
-- is captured whether it passes, fails, or crashes (a crash becomes a failed Result, never a silent
-- omission); results are returned in JOB ORDER regardless of finish order, so callers print a
-- deterministic table. Concurrency changes only WHEN a suite runs, never WHETHER its pass/fail is
-- seen. Scheduling order never feeds a suite's result — each runs in its own OS process, isolated.
local process = require("@lune/process")
local task = require("@lune/task")

--- `env` is EXPLICIT because lune does not inherit runtime mutations. Setting
--- `process.env.X` in a parent and spawning a child leaves the child seeing nil — measured
--- 2026-08-08:
---     inherit  -> SET_AT_RUNTIME=nil
---     explicit -> SET_AT_RUNTIME=child-should-see-this
--- That cost a full 20-minute sweep: the suite-reuse token never reached the gates, so every
--- gate re-ran its suites while the run still reported PASS. A silent no-op, which is the
--- worst failure mode available to an optimisation. Pass what the child must see.
export type Job = { name: string, argv: { string }, meta: any?, env: { [string]: string }? }
export type Result = {
	name: string,
	ok: boolean,
	code: number,
	stdout: string,
	stderr: string,
	secs: number,
	meta: any?,
}

local Parallel = {}

-- A sensible default width: explicit env override, else the machine's logical CPU count, else 4.
-- Clamped to [1, 32]. Callers pass an explicit --jobs to override; --jobs=1 is exact serial.
function Parallel.defaultJobs(): number
	local override = process.env.PRISM_TEST_JOBS
	if override and tonumber(override) then
		return math.max(1, math.floor(tonumber(override) :: number))
	end
	-- NUMBER_OF_PROCESSORS is set on Windows; many Linux CI images (e.g. GitHub Actions ubuntu) do
	-- NOT export it, so there we fall back to 4 rather than the true core count (ms-42 R-review). On
	-- such hosts pass --jobs=N or set PRISM_TEST_JOBS to use all cores.
	local cpu = process.env.NUMBER_OF_PROCESSORS
	local n = if cpu then tonumber(cpu) else nil
	if not n then n = 4 end
	return math.clamp(math.floor(n :: number), 1, 32)
end

export type RunOpts = {
	-- Called (in FINISH order) as each job completes — for live progress on a long run.
	onDone: ((finishedCount: number, total: number, r: Result) -> ())?,
}

-- Run `jobs` with at most `concurrency` children in flight. Blocks (cooperatively) until all are
-- done. Returns results indexed by the ORIGINAL job order.
function Parallel.run(jobs: { Job }, concurrency: number, opts: RunOpts?): { Result }
	local n = #jobs
	local results: { Result } = {}
	if n == 0 then
		return results
	end
	local cc = math.clamp(math.floor(concurrency), 1, n)
	local nextIdx = 1
	local finished = 0
	local liveWorkers = 0

	local function runOne(i: number)
		local job = jobs[i]
		local t0 = os.clock()
		local child = if job.env
			then process.create("lune", job.argv, { env = job.env })
			else process.create("lune", job.argv)
		-- Drain both pipes CONCURRENTLY with the exit wait: a child that fills its stdout pipe
		-- buffer would otherwise block on write forever while we block on status() — classic
		-- pipe deadlock. readToEnd yields until EOF (child exit), draining as it goes.
		local out, err = "", ""
		local outDone, errDone = false, false
		task.spawn(function()
			out = child.stdout:readToEnd()
			outDone = true
		end)
		task.spawn(function()
			err = child.stderr:readToEnd()
			errDone = true
		end)
		local status = child:status()
		while not (outDone and errDone) do
			task.wait()
		end
		local r: Result = {
			name = job.name,
			ok = status.ok,
			code = status.code,
			stdout = out,
			stderr = err,
			secs = os.clock() - t0,
			meta = job.meta,
		}
		results[i] = r
		finished += 1
		if opts and opts.onDone then
			opts.onDone(finished, n, r)
		end
	end

	local function worker()
		liveWorkers += 1
		while true do
			local i = nextIdx
			nextIdx += 1
			if i > n then
				break
			end
			runOne(i)
		end
		liveWorkers -= 1
	end

	for _ = 1, cc do
		task.spawn(worker)
	end
	-- Cooperatively wait for the pool to drain. task.wait yields to the workers (and to the
	-- concurrent pipe drains) each tick.
	while liveWorkers > 0 or nextIdx <= n do
		task.wait()
	end

	-- Defensive: no job may be missing from the table (would otherwise hide a crash).
	for i = 1, n do
		if results[i] == nil then
			results[i] = {
				name = jobs[i].name,
				ok = false,
				code = -1,
				stdout = "",
				stderr = "executor: job produced no result (did not run)",
				secs = 0,
				meta = jobs[i].meta,
			}
		end
	end
	return results
end

return Parallel
