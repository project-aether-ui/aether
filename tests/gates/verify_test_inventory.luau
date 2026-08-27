--!strict
--[[
	verify_test_inventory — every test file on disk is REACHABLE by something
	that actually runs it.

	WHY (ms-44 M1)
	A test nobody runs is worse than no test: it reads as coverage in a review,
	it is cited as evidence in a sprint file, and it is silently dark. This repo
	has paid for that lesson twice already, in two different shapes:

	  * **ms-43 M30** — eight suites RETURNED an uninvoked function. The runner
	    judges by exit code, so they passed without executing a single assertion.
	    One of them had been calling functions M15 deleted, and ms-43 cited it as
	    evidence for the M25 fix. The fix was real; the test had never run.
	  * **ms-44 M1** — the entire run-in-roblox tier (24 specs) died in its
	    bootstrap from 7937d2e (2026-07-25) until this milestone, because ms-41
	    O2 made unclaimed-namespace registration fatal and no gate spawns
	    `tests/support/runner/run_tests.luau`. Nine days dark, invisible to every
	    automated path.

	Both are the same class: REACHABILITY IS UNCHECKED. M30 fixed its eight
	instances by hand and left the class open. This closes the class.

	WHAT COUNTS AS REACHED
	A test file is reached if some runner or gate names its path, or if a host
	loads it by discovery:

	  runner      tests/run.luau's SUITES table names the path
	  gate        a tests/gates/*.luau or scripts/*.luau names the path
	  engine      tests/engine/prism/specs/*.spec.luau — init.luau requires every
	              `.spec` ModuleScript under itself, and
	              tests/engine/default.project.json mounts that host, so discovery
	              reaches them

	WHAT THIS DOES NOT CATCH, stated because a gate whose limits are unstated
	gets trusted past them:

	  * Reachable is not RUN. A gate that names a path but is itself never
	    invoked still counts as a reference here. Chasing that fully means
	    executing the graph, which is the runner's job, not a static gate's.
	  * Reached is not RUN, as above. Reached is, however, no longer "might be
	    vacuous": every suite in the repo runs on testkit as of ms-44, and testkit
	    fails a run whose declared tests all went unexecuted with no filter to
	    explain it. Non-vacuity is enforced AT RUNTIME, by the thing that runs the
	    tests, which is where it belongs — a static gate can only ever guess at it.
	    The census below is now a weak second opinion, kept because it is free.
]]

local fs = require("@lune/fs")

local failures = 0
local function fail(msg: string)
	failures += 1
	print("FAIL  " .. msg)
end

--- Directories that are vendored, generated, or otherwise not ours.
local function isVendored(path: string): boolean
	return string.find(path, "roblox_packages", 1, true) ~= nil
		or string.find(path, "luau_packages", 1, true) ~= nil
		or string.find(path, "/.pesde/", 1, true) ~= nil
end

--- Every file under `root` matching `pred`, depth-first, vendored trees skipped.
local function walk(root: string, pred: (string) -> boolean, out: { string })
	if not fs.isDir(root) then
		return
	end
	for _, name in ipairs(fs.readDir(root)) do
		local path = root .. "/" .. name
		if not isVendored(path) then
			if fs.isDir(path) then
				walk(path, pred, out)
			elseif pred(path) then
				table.insert(out, path)
			end
		end
	end
end

-- ── The census ────────────────────────────────────────────────────────────────

local tests: { string } = {}
-- Package-level lune suites. After ms-44 M3 these live in <pkg>/tests/ rather
-- than <pkg>/src/, so the walk deliberately spans the whole package.
for _, root in ipairs({ "src", "packages", "hosts" }) do
	walk(root, function(p)
		return string.match(p, "%.test%.luau$") ~= nil
	end, tests)
end
-- Central lune suites. One file per suite since the ms-44 layout change; the old shape
-- was `tests/src/<Name>/run_lune_tests.luau`, 26 files sharing one name.
walk("tests", function(p)
	return string.match(p, "%.test%.luau$") ~= nil
end, tests)
-- Engine-tier specs. They used to be scattered inside lune suite directories, which is
-- why the walk above once looked for them; they now live with the host that loads them.
walk("tests/engine", function(p)
	return string.match(p, "%.spec%.luau$") ~= nil
end, tests)

table.sort(tests)

-- ── Who can reach them ────────────────────────────────────────────────────────

--- Comments are stripped before matching, and that is load-bearing rather than
--- tidiness. On this gate's first run `tests/src/RollbackContinuousPhysics` came
--- back REACHED because scripts/netcode_gates.luau:102 names its path in a
--- prose comment ("proof: tests/src/..."). A comment is documentation that a
--- suite ought to be run; it is not something that runs it. Counting it would
--- have made this gate certify the exact situation it exists to find.
local stripComments = require("./source_scan").stripComments

--- Every file that might NAME a test path. Read once; a substring match against
--- these bodies is what "reached" means.
local referrers: { { name: string, body: string } } = {}
local function addReferrer(path: string)
	if fs.isFile(path) then
		table.insert(referrers, { name = path, body = stripComments(fs.readFile(path)) })
	end
end

addReferrer("tests/run.luau")
for _, dir in ipairs({ "tests/verify", "scripts", "scripts/hooks", "scripts/lib" }) do
	if fs.isDir(dir) then
		for _, name in ipairs(fs.readDir(dir)) do
			local p = dir .. "/" .. name
			if fs.isFile(p) and string.match(name, "%.luau$") then
				addReferrer(p)
			end
		end
	end
end

--- `tests/engine/prism/init.luau` requires every `.spec` ModuleScript beneath itself, and
--- tests/engine/default.project.json mounts that host into ServerScriptService — so a spec
--- is reached by DISCOVERY, with no path naming it anywhere. Verified structurally rather
--- than assumed: if either half of that mechanism goes away, specs stop being
--- reachable and this must stop claiming they are.
---
--- The mount is matched by its `$path` VALUE, which is project-file-relative and therefore
--- moves when the project file does — it was `"engine/prism"` while the project sat at
--- tests/, and is `"prism"` now that it sits beside the host (ms-44). Matching the value is
--- what makes this gate notice a move at all, rather than certifying a mount that no longer
--- resolves.
local PROJECT = "tests/engine/default.project.json"
local engineHostScans = fs.isFile("tests/engine/prism/init.luau")
	and string.find(fs.readFile("tests/engine/prism/init.luau"), "%.spec", 1, true) ~= nil
local engineHostMounted = fs.isFile(PROJECT)
	and string.find(fs.readFile(PROJECT), '"$path": "prism"', 1, true) ~= nil
local engineDiscovery = engineHostScans and engineHostMounted

if not engineDiscovery then
	fail(
		"the engine host no longer discovers specs (tests/engine/prism/init.luau's `.spec` scan or "
			.. PROJECT
			.. "'s prism mount is gone) — every *.spec.luau is now unreachable"
	)
end

--- ms-44 M3: the runner DISCOVERS suites rather than listing them, so "named by
--- tests/run.luau" stopped meaning anything — this gate briefly reported 40 files
--- unreached the moment the table was deleted, which is the gate correctly noticing its
--- own premise had expired. "Reached" now means DISCOVERY FINDS IT, computed from the
--- same `tests/suite_config.luau` the runner uses so the two cannot drift.
local SuiteConfig = require("../suites")
local Discover = require("../../pkgs/testkit/core/src/Discover")
local discovered: { [string]: boolean } = {}
for _, s in ipairs(Discover.suites(SuiteConfig)) do
	discovered[s.path] = true
end

local function reachedBy(testPath: string): string?
	if discovered[testPath] then
		return "runner (discovery)"
	end
	if string.match(testPath, "%.spec%.luau$") and engineDiscovery then
		return "engine (discovery)"
	end
	for _, r in ipairs(referrers) do
		if string.find(r.body, testPath, 1, true) then
			if r.name == "tests/run.luau" then
				return "runner"
			end
			return r.name
		end
	end
	return nil
end

-- ── Assertion census ──────────────────────────────────────────────────────────
--
-- Informational. Counted the same way scripts/orientation.luau counts (ms-43 M123):
-- bare `assert(` substrings.
--
-- This used to carry a real caveat: three physics suites reported through their own
-- `check(...)` vocabulary and legitimately scored zero, so zero meant "this proxy
-- cannot see this suite's assertions" rather than "this suite asserts nothing" — an
-- ambiguity that made the number unusable as a gate. ms-44 put every suite on testkit,
-- those three included, and the zero-assert list went empty.
--
-- It stays INFORMATIONAL anyway. The number is a proxy, and the real signal is testkit's
-- runtime vacuity check, which knows what actually executed instead of counting
-- substrings. Promoting a proxy once it happens to read clean is how a gate starts
-- asserting something it cannot see.
local function assertionsIn(path: string): number
	local n = 0
	for _ in string.gmatch(fs.readFile(path), "assert%(") do
		n += 1
	end
	return n
end

-- ── Report ────────────────────────────────────────────────────────────────────

local unreached: { string } = {}
local zeroAssert: { string } = {}
local byRoute: { [string]: number } = {}
local totalAssertions = 0

for _, path in ipairs(tests) do
	local route = reachedBy(path)
	if route then
		local key = if route == "runner (discovery)" or route == "engine (discovery)" then route else "gate"
		byRoute[key] = (byRoute[key] or 0) + 1
	else
		table.insert(unreached, path)
	end

	local n = assertionsIn(path)
	totalAssertions += n
	if n == 0 then
		table.insert(zeroAssert, path)
	end
end

print(`test inventory: {#tests} file(s), {totalAssertions} assertion(s)`)
for _, key in ipairs({ "runner (discovery)", "gate", "engine (discovery)" }) do
	if byRoute[key] then
		print(`  reached via {key}: {byRoute[key]}`)
	end
end

if #zeroAssert > 0 then
	print("")
	print(
		`NOTE  {#zeroAssert} test file(s) show zero bare \`assert(\` calls — either genuinely `
			.. `assertion-free or using their own vocabulary. Runtime counts settle it in ms-44 M2:`
	)
	for _, p in ipairs(zeroAssert) do
		print("      " .. p)
	end
end

for _, p in ipairs(unreached) do
	fail(
		`{p}: UNREACHED — discovery does not find it and no gate names it. Put it under a root in `
			.. `tests/suite_config.luau with a matching name, name it from a verify_* gate, or delete it. A test nobody runs reads as coverage and is not.`
	)
end

print("")
if failures > 0 then
	print(`VERIFY TEST INVENTORY: FAILED ({failures} problem(s))`)
	local process = require("@lune/process")
	process.exit(1)
else
	print(`VERIFY TEST INVENTORY: PASS ({#tests} test files, all reachable)`)
end
return true
