--!strict
-- tests/run.luau — the FAST lune suite runner (ms-37 M4.4k).
--
-- WHY: the verify_37mN chain re-runs every earlier milestone's gates, and each gate spawns
-- a subprocess that boots the whole prism stack — roughly 15 minutes end to end. That is the
-- right cost for a pre-commit gate and completely the wrong cost for iterating on one
-- solver. This runs the leaf suites directly, in-process order, and lets you name the one
-- you care about.
--
-- THE THREE TIERS (ms-37 M4.5). Every suite — and inside a tiered suite, every test —
-- declares what it costs, so the edit loop can ask for only what it needs:
--
--   math      pure functions. No stack boot, no ticks. The whole tier is ~10s.
--   scenario  one stack boot, a bounded tick sweep. Seconds per suite.
--   e2e       full vehicle runs and the real 362-shape arena. Minutes.
--
-- USAGE
--   lune run tests/run.luau                    -- math + scenario (the default loop)
--   lune run tests/run.luau --tier=math        -- just the pure math, seconds
--   lune run tests/run.luau --tier=math,scenario
--   lune run tests/run.luau --all              -- every tier, including e2e
--   lune run tests/run.luau ManifoldHull       -- only suites whose name matches
--   lune run tests/run.luau Manifold Compound  -- several filters (OR)
--   lune run tests/run.luau --list             -- show suites + tiers and exit
--
-- Matching is case-insensitive substring, so `manifold` runs Manifold AND ManifoldHull.
-- Naming a suite runs it regardless of tier. Timings print per suite.
--
-- FLAGS ARE STRICT: an unrecognised `-`-prefixed argument is an error, never a no-op. The
-- above list is the whole vocabulary. Pinned by tests/lune/RunnerArgs.test.luau.
--
-- Suites marked `tiered` understand `--tier=` themselves, so asking for `math` from a suite
-- that also holds e2e tests runs just its math tests rather than skipping the suite.
--
-- THIS IS NOT THE PRE-COMMIT GATE. It deliberately does NOT run the verify_* chain or the
-- cross-process determinism hash. Run `lune run tests/gates/verify_37m3.luau` (and 37m4)
-- before committing — the fast runner is for the edit/measure loop only.
local fs = require("@lune/fs")
local process = require("@lune/process")
local Parallel = require("./support/runner/parallel")
local SuiteResults = require("./support/runner/suite_results")
local Engine = require("@testkit_env")

type Tier = "math" | "scenario" | "e2e"
-- `tier` is the HEAVIEST tier a suite contains — it decides whether the suite is spawned.
-- `tiered` means the suite reads `--tier=` itself, so a narrower request runs its cheap
-- tests instead of skipping it wholesale.
type Suite = { name: string, path: string, tier: Tier, tiered: boolean? }

-- Leaf lune suites, cheapest first so a failure surfaces fast. Tiers come from MEASURED
-- wall time (ms-37 M4.5 baseline run), not from guesses.
-- ms-44 M3: DISCOVERED, not listed.
--
-- This was a hand-written table of 57 rows. Every entry was a chance to forget one, and a
-- forgotten suite is invisible: it never runs, reads as coverage in review, and gets cited
-- as evidence in sprint files. ms-44 M1 found TEN files in exactly that state — including
-- all eight `theme_core` suites, which ARE ms-43 M3-M10's own cited exit-gate evidence —
-- and then fixed it by adding ten more rows BY HAND, which is the same burden one turn on.
-- ms-43 M84 is the identical lesson one layer up (a hardcoded 7-directory list that
-- predated the component tier, so five packages went unscanned).
--
-- Tier now lives in the FILE, as `--!tier <name>` / `--!tiered`, so it travels with the
-- suite it describes and cannot drift from a central table. The values were transcribed
-- from this table, i.e. from ms-37 M4.5's MEASURED baseline, not re-guessed.
local Discover = Engine.Discover
local SUITES: { Suite } = {}
local SuiteConfig = require("./suites")
for _, s in ipairs(Discover.suites(SuiteConfig)) do
	-- `perf` must be carried through: this hand-listed copy silently dropped it, so --!perf
	-- parsed correctly in Discover and then vanished one line later. A field list is the
	-- thing that goes stale — every new Suite field has to be added here too.
	table.insert(SUITES, { name = s.name, path = s.path, tier = s.tier :: Tier, tiered = s.tiered, perf = s.perf })
end

local TIER_RANK: { [string]: number } = { math = 1, scenario = 2, e2e = 3 }

local args = process.args
local filters: { string } = {}
local listOnly = false
-- Default loop = math + scenario. e2e is opt-in via --all / --tier=e2e / naming the suite,
-- because it is the 10-minute tier.
local wanted: { [string]: boolean } = { math = true, scenario = true }
local tierExplicit = false
-- ms-42 M3: concurrency control. `--jobs=N` overrides; absent ⇒ Parallel.defaultJobs()
-- (env PRISM_TEST_JOBS, else CPU count, else 4). `--jobs=1` is exact serial — the escape hatch
-- for debugging a suite that misbehaves only under a peer. `-u`/`--update-snapshots` FORCES serial
-- and forwards the flag: snapshot WRITES would race across peers, so updates must be one-at-a-time.
local jobsOverride: number? = nil
local updateSnapshots = false
local emitResultsPath: string? = nil
for _, a in ipairs(args) do
	local list = string.match(a, "^%-%-tier=(.+)$")
	local jobsArg = string.match(a, "^%-%-jobs=(%d+)$")
	local emitArg = string.match(a, "^%-%-emit%-results=(.+)$")
	if a == "--list" then
		listOnly = true
	elseif emitArg then
		emitResultsPath = emitArg
	elseif jobsArg then
		jobsOverride = math.max(1, tonumber(jobsArg) :: number)
	elseif a == "-u" or a == "--update-snapshots" then
		updateSnapshots = true
	elseif list then
		if not tierExplicit then
			wanted = {}
			tierExplicit = true
		end
		for t in string.gmatch(list, "[^,]+") do
			if not TIER_RANK[t] then
				error(`unknown tier "{t}" — expected math | scenario | e2e`, 0)
			end
			wanted[t] = true
		end
	elseif a == "--all" or a == "--slow" then
		wanted = { math = true, scenario = true, e2e = true }
		tierExplicit = true
	elseif a == "--fast" then
		wanted = { math = true }
		tierExplicit = true
	elseif string.match(a, "^%-%-env=") or string.match(a, "^%-%-transport=") then
		-- Parsed by the engine-tier loop below; named here so this loop can be STRICT.
	elseif string.sub(a, 1, 1) == "-" then
		-- ms-44: an unrecognised flag is FATAL, not ignored.
		--
		-- This branch used to be `string.sub(a, 1, 2) ~= "--"`, so anything starting with
		-- `--` that matched nothing above fell off the end of the loop in silence. The
		-- runner then ran its DEFAULT selection and exited 0, so `--only=SpringDesign`
		-- reported "all selected suites passed" after running 23 unrelated suites — and
		-- two different `--only=` values produced byte-identical output. A typo in a tier
		-- VALUE was already fatal (`--tier=mth` errors); a typo in the flag NAME was not.
		-- That asymmetry is this milestone's own defect class: a command that reads as
		-- narrow coverage while silently doing something else.
		--
		-- Single-dash args are caught too. `-u` is the only one that means anything, and
		-- the old test (`sub(a, 1, 2) ~= "--"`) sent `-x` to the NAME filters, where it
		-- matched no suite — which at least exited 1, but blamed the wrong thing.
		error(
			`unknown flag "{a}" — expected --list | --all | --slow | --fast | --tier=<t> | `
				.. `--jobs=<n> | -u/--update-snapshots | --env=<e> | --transport=<t>, `
				.. `or a bare suite name`,
			0
		)
	else
		table.insert(filters, string.lower(a))
	end
end

-- ms-44 M6: the ENGINE tier, invoked exactly like the lune tier.
--
--   lune run tests/run.luau --env=engine
--   lune run tests/run.luau --env=engine --transport=cloud
--
-- CI GETS NO PRIVILEGED PATH (es9): CI runs these same commands and adds nothing. A
-- failure a developer cannot reproduce locally is the most expensive property a test
-- setup can have, so there is no cloud-only-in-CI mode to rot unobserved.
--
-- Transport is auto-selected — and the Studio check matters: run-in-roblox panics while
-- Studio is open, which is why this tier was run by hand in scheduled windows and drifted
-- red for nine days. With Studio open it now falls through to cloud instead of failing.
local envArg: string? = nil
local transportArg: string? = nil
for _, a in ipairs(args) do
	envArg = string.match(a, "^%-%-env=(.+)$") or envArg
	transportArg = string.match(a, "^%-%-transport=(.+)$") or transportArg
end

-- ENGINE SUITES. This table is repo shape, and it lives HERE rather than in testkit on
-- purpose (spec D-3): testkit must not know a package, a domain, or a path of this repo,
-- or `git filter-repo --path pkgs/testkit` stops being a viable graduation. A suite
-- DECLARES what its place needs; `Compose` turns that into a Rojo project.
--
-- `project` names a hand-written project instead, for the prism suite whose place is more
-- than a list of mounts (it carries roblox_packages). Migrating that to `mounts` is
-- follow-up work, not a prerequisite.
type EngineSuite = {
	name: string,
	project: string?,
	mounts: { { name: string, path: string } }?,
	server: { name: string, path: string }?,
	entry: string,
}

local TESTKIT_MOUNT = { name = "testkit", path = "pkgs/testkit/core/src" }

local ENGINE_SUITES: { EngineSuite } = {
	{
		name = "prism",
		project = "tests/engine/default.project.json",
		entry = [[
			local ok, suite = pcall(function()
				return require(game:GetService("ServerScriptService").PrismTest)
			end)
			if not ok then
				return { bootError = tostring(suite) }
			end
			return suite
		]],
	},
	{
		-- ms-44 M5b: the SAME conformance suite the lune tier runs, against REAL vide.
		--
		-- `vendor` mounts a package's roblox_packages wholesale. pesde's generated
		-- `vide.luau` inside it resolves `.pesde/centau_vide@<version>/vide` by
		-- FindFirstChild at runtime, so no version is hardcoded here and none can go stale —
		-- which is what made this sprint possible at all (the blocker was that a committed
		-- file must not hard-path into a gitignored .pesde tree).
		--
		-- sheen is chosen because it is the smallest vide consumer: its roblox_packages
		-- holds vide and nothing else.
		name = "shim",
		mounts = {
			TESTKIT_MOUNT,
			{ name = "vendor", path = "pkgs/ui/components/sheen/roblox_packages" },
		},
		server = { name = "EngineTests", path = "pkgs/ui/framework/Aether/tests/host/HostConformance.test.luau" },
		entry = [[
			local ok, suite = pcall(function()
				return require(game:GetService("ServerScriptService").EngineTests)
			end)
			if not ok then
				return { bootError = tostring(suite) }
			end
			return suite
		]],
	},
	{
		-- ms-44 M8: the defects three STATIC GATES only infer, observed instead.
		--
		-- The host DECLARES its capabilities via `_G.TESTKIT_ARGV`, which is what finally
		-- gives the capability axis (spec D-2) a real consumer: a test needing `layout` is
		-- SKIPPED with a reason on a host that does not claim it, rather than failing or
		-- being quietly omitted. A server does provide layout and text measurement —
		-- measured 2026-08-04, not assumed.
		name = "ui",
		mounts = {
			TESTKIT_MOUNT,
			{ name = "vendor", path = "pkgs/ui/components/sheen/roblox_packages" },
		},
		server = { name = "EngineTests", path = "tests/engine/uibehaviour" },
		entry = [[
			_G.TESTKIT_ARGV = { "--provides=reflection,layout,vide-scopes" }
			local ok, suite = pcall(function()
				return require(game:GetService("ServerScriptService").EngineTests)
			end)
			if not ok then
				return { bootError = tostring(suite) }
			end
			return suite
		]],
	},
	{
		-- ms-44 M6c: the first engine suite that is NOT prism, and the proof the composer
		-- works. Needs nothing but testkit, which is what makes it a clean demonstration.
		name = "reflection",
		mounts = { TESTKIT_MOUNT },
		server = { name = "EngineTests", path = "tests/engine/reflection" },
		entry = [[
			local ok, suite = pcall(function()
				return require(game:GetService("ServerScriptService").EngineTests)
			end)
			if not ok then
				return { bootError = tostring(suite) }
			end
			return suite
		]],
	},
}

if envArg == "engine" then
	if transportArg and transportArg ~= "local" and transportArg ~= "cloud" then
		print(`unknown transport "{transportArg}" — expected local | cloud`)
		process.exit(1)
	end
	local Compose = Engine.Compose
	local selected: { EngineSuite } = {}
	for _, s in ipairs(ENGINE_SUITES) do
		if #filters == 0 then
			table.insert(selected, s)
		else
			for _, f in ipairs(filters) do
				if string.find(string.lower(s.name), f, 1, true) then
					table.insert(selected, s)
					break
				end
			end
		end
	end
	if #selected == 0 then
		print(`no engine suite matched {table.concat(filters, ", ")}`)
		process.exit(1)
	end

	-- ms-44: `--list` is honoured HERE too, and the omission was not cosmetic.
	--
	-- This branch sits ABOVE the lune tier's `listOnly` handler, so `--list --env=engine`
	-- used to fall straight through into execution: it UPLOADED A NEW PLACE VERSION to the
	-- live universe and ran the full engine suite — ~16s and a real side effect — from a
	-- flag whose entire contract is "print and exit". Found by a test that asked for a
	-- listing and got place version 55.
	--
	-- Listing the ENGINE suites rather than deferring to the lune list: the answer to
	-- "what would this command run" has to describe THIS command.
	if listOnly then
		print(`engine suites (transport: {transportArg or "auto"}):`)
		for _, s in ipairs(selected) do
			print(string.format("  %-18s %s", s.name, s.project or "(composed)"))
		end
		return
	end

	local anyFailed = false
	for _, suiteSpec in ipairs(selected) do
		print("")
		print(`--- engine suite: {suiteSpec.name} ---`)

		-- A composed suite generates its project; a hand-written one names it. Generated
		-- projects go to a gitignored directory: a generated file in review is noise, and a
		-- stale one is a lie.
		local projectPath = suiteSpec.project
		if not projectPath then
			local spec = {
				name = suiteSpec.name,
				mounts = suiteSpec.mounts or {},
				server = suiteSpec.server,
			}
			local okSpec, whySpec = Compose.validate(spec)
			if not okSpec then
				print(`ENGINE ({suiteSpec.name}): FAILED — {whySpec}`)
				anyFailed = true
				continue
			end
			projectPath = Compose.write(spec, `tests/.generated/{suiteSpec.name}.project.json`)
		end

		local result = Engine.run({
			project = projectPath :: string,
			output = `tests/.generated/{suiteSpec.name}.rbxl`,
			localEntry = "tests/support/runner/entry.server.luau",
			entry = suiteSpec.entry,
			transport = transportArg :: any,
		})

		for _, line in ipairs(result.logs) do
			print(line)
		end

		-- The cloud transport carries a STRUCTURED verdict (`output.results`); the local one
		-- has only an exit code. Trust the structured one when present — a suite whose tests
		-- failed still leaves the TASK complete, so `result.ok` alone would call that a pass.
		local ok = result.ok
		local suite: any = if result.results then result.results[1] else nil
		if type(suite) == "table" then
			if suite.bootError then
				print(`engine host failed to BOOT: {tostring(suite.bootError)}`)
				ok = false
			elseif suite.failed ~= nil then
				ok = ok and suite.failed == 0 and suite.vacuous ~= true
				print(`  {suite.passed} passed, {suite.failed} failed, {suite.skipped or 0} skipped ({suite.declared} declared)`)
				for _, t in ipairs(suite.tests or {}) do
					if t.ok == false then
						print(`  FAIL  {t.path}`)
					print(`        {tostring(t.err)}`)
					end
				end
			end
		end

		if ok then
			print(`ENGINE {suiteSpec.name} ({result.transport}): PASS`)
		else
			print(`ENGINE {suiteSpec.name} ({result.transport}): FAILED — {tostring(result.err or "suite reported failure")}`)
			anyFailed = true
		end
	end

	print("")
	if anyFailed then
		process.exit(1)
	end
	print(`ENGINE: all {#selected} suite(s) passed`)
	return
elseif envArg and envArg ~= "lune" then
	print(`unknown env "{envArg}" — expected lune | engine`)
	process.exit(1)
end

if listOnly then
	print("suites (default runs math + scenario; e2e needs --all or --tier=e2e):")
	for _, s in ipairs(SUITES) do
		print(
			string.format("  %-18s [%-8s]%s %s", s.name, s.tier, if s.tiered then " tiered" else "       ", s.path)
		)
	end
	return
end

-- Which tiers should this suite be asked to run? Only meaningful for `tiered` suites.
local function tiersFor(s: Suite): { string }
	local out: { string } = {}
	for t in pairs(wanted) do
		table.insert(out, t)
	end
	table.sort(out, function(a, b)
		return TIER_RANK[a] < TIER_RANK[b]
	end)
	return out
end

local function matches(s: Suite): boolean
	if #filters > 0 then
		local lower = string.lower(s.name)
		for _, f in ipairs(filters) do
			if string.find(lower, f, 1, true) then
				return true -- naming a suite always runs it, whatever its tier
			end
		end
		return false
	end
	-- A tiered suite is spawned whenever ANY requested tier is at or below its own — it
	-- will filter internally. An untiered suite runs only if its whole cost was asked for.
	if s.tiered then
		for t in pairs(wanted) do
			if TIER_RANK[t] <= TIER_RANK[s.tier] then
				return true
			end
		end
		return false
	end
	return wanted[s.tier] == true
end

assert((process :: any).create, "the parallel fast runner needs lune's process.create (0.8+); upgrade lune")

local selected: { Suite } = {}
for _, s in ipairs(SUITES) do
	if matches(s) then
		if fs.isFile(s.path) then
			table.insert(selected, s)
		else
			print(string.format("skip  %-18s (missing: %s)", s.name, s.path))
		end
	end
end

if #selected == 0 then
	print(`no suites matched {table.concat(filters, ", ")} — try --list`)
	process.exit(1)
end

-- ms-42 M3: build one job per selected suite and run the fanout through the bounded-concurrency
-- executor. A tiered suite gets the tier request forwarded; spawned BARE it runs everything — which
-- is exactly how verify_37mN spawns it, so the gates keep their full coverage. `-u` is forwarded so
-- `run.luau -u` still updates snapshots (serially — see the --jobs guard below).
local function buildArgv(s: Suite): { string }
	local argv = { "run", s.path }
	local scriptArgs: { string } = {}
	if s.tiered then
		local ts = tiersFor(s)
		if #ts > 0 and #ts < 3 then
			table.insert(scriptArgs, `--tier={table.concat(ts, ",")}`)
		end
	end
	if updateSnapshots then
		table.insert(scriptArgs, "--update-snapshots")
	end
	if #scriptArgs > 0 then
		table.insert(argv, "--")
		for _, x in ipairs(scriptArgs) do
			table.insert(argv, x)
		end
	end
	return argv
end

local jobsN = if updateSnapshots then 1 else (jobsOverride or Parallel.defaultJobs())
jobsN = math.clamp(jobsN, 1, #selected)

-- `--!perf` suites NEVER share the pool. Measured ms-47: sharding CompoundFeel changed the
-- pool's composition and CompoundPerf began FAILING at jobs=16 while passing 6/6 standalone —
-- its fixed-dt budget was reading the other fifteen workers. Left in the pool it is a coin
-- flip in BOTH directions: it can also pass on a quiet machine while the code has regressed.
-- They run alone, after the pool has drained.
local jobs: { Parallel.Job } = {}
local perfSuites: { any } = {}
for _, s in ipairs(selected) do
	if (s :: any).perf then
		table.insert(perfSuites, s)
	else
		table.insert(jobs, { name = s.name, argv = buildArgv(s), meta = s })
	end
end

local serialNote = if updateSnapshots then " (serial: -u writes snapshots)" elseif jobsN == 1 then " (serial)" else ""
print(string.format("--- fast runner: %d suite(s), jobs=%d%s ---", #selected, jobsN, serialNote))

local total0 = os.clock()
local results = Parallel.run(jobs, jobsN, {
	onDone = function(k, total, r)
		-- Live progress in finish order so a long parallel run never looks hung. The
		-- AUTHORITATIVE per-suite table below prints in deterministic suite order.
		print(string.format("  · %2d/%2d  %-18s %6.1fs  %s", k, total, r.name, r.secs, if r.ok then "ok" else "FAIL"))
	end,
})

-- Perf suites, alone, after the pool has drained — so a timing budget measures the code.
if #perfSuites > 0 then
	print(string.format("--- %d perf-sensitive suite(s), run ALONE (jobs=1) so budgets measure the code ---", #perfSuites))
	local perfJobs: { Parallel.Job } = {}
	for _, s in ipairs(perfSuites) do
		table.insert(perfJobs, { name = s.name, argv = buildArgv(s), meta = s })
	end
	for _, r in ipairs(Parallel.run(perfJobs, 1, {
		onDone = function(k, total, r)
			print(string.format("  · %2d/%2d  %-18s %6.1fs  %s", k, total, r.name, r.secs, if r.ok then "ok" else "FAIL"))
		end,
	})) do
		table.insert(results, r)
	end
end

-- Authoritative results, in SELECTED (declaration) order — deterministic regardless of finish order.
print("---")
local failed: { string } = {}
local timings: { { name: string, tier: string, secs: number } } = {}
for _, r in ipairs(results) do
	local meta: any = r.meta
	table.insert(timings, { name = r.name, tier = meta.tier, secs = r.secs })
	if r.ok then
		-- Echo the suite's own RESULTS line so counts stay visible without the full noise.
		local resultsLine = string.match(r.stdout, "RESULTS: [^\n]*")
		print(string.format("PASS  %-18s %6.1fs   %s", r.name, r.secs, resultsLine or ""))
	else
		table.insert(failed, r.name)
		print(string.format("FAIL  %-18s %6.1fs", r.name, r.secs))
		-- On failure show the detail — that is the whole point of the fast loop.
		for line in string.gmatch(r.stdout, "[^\n]+") do
			if string.find(line, "FAIL", 1, true) or string.find(line, "RESULTS:", 1, true) then
				print("        " .. line)
			end
		end
		if r.stderr and #r.stderr > 0 then
			print("        stderr: " .. string.sub(r.stderr, 1, 600))
		end
	end
end

-- ms-47: publish this run's verdicts so the gates that assert on these same suites
-- (verify_37m4, verify_37m5) can reuse them instead of spawning them all over again.
-- --emit-results is OPT-IN and inert unless tests/gates/run.luau --with-suites passes it,
-- and what it writes is only honoured by a gate holding the matching sweep token — see
-- suite_results.luau for why a durable cache would turn a gate into a claim about history.
if emitResultsPath then
	local records: { SuiteResults.SuiteRecord } = {}
	for _, r in ipairs(results) do
		local meta: any = r.meta
		table.insert(records, { name = r.name, path = meta.path, ok = r.ok })
	end
	local token = process.env[SuiteResults.TOKEN_ENV]
	if token and token ~= "" then
		SuiteResults.write(emitResultsPath, token, records)
		print(`--- wrote {#records} suite verdict(s) to {emitResultsPath} ---`)
	else
		-- Refuse to write an untokened manifest: it could only ever be read by something
		-- that skipped the token check, which is the staleness hole itself.
		print(`--- --emit-results ignored: no {SuiteResults.TOKEN_ENV} in the environment ---`)
	end
end

-- ms-44 M3: TIER HONESTY. ms-37's tier table came from a measured baseline and then
-- drifted, because nothing ever re-measured it. Every run now compares MEASURED wall time
-- against the tier each suite declares, so a mis-tag or a regression is reported rather
-- than silently making the "fast" loop slow.
local drift = Discover.tierDrift(timings)
if #drift > 0 then
	print("")
	print(`tier drift ({#drift}):`)
	for _, d in ipairs(drift) do
		print("  " .. d)
	end
end

print(string.format("--- %.1fs total (jobs=%d) ---", os.clock() - total0, jobsN))
if #failed > 0 then
	print(`FAILED: {table.concat(failed, ", ")}`)
	process.exit(1)
end
print("all selected suites passed (NOT a pre-commit gate — run verify_37m3/37m4 before committing)")
