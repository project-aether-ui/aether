--!strict
--[[
	verify_test_inventory -- a file that LOOKS like a test either runs or is named.

	WHY (ms-44 M1)
	A test nobody runs is worse than no test: it reads as coverage in a review, it
	is cited as evidence, and it is silently dark. This repository has paid for
	that lesson repeatedly -- eight suites that returned an uninvoked function and
	passed on exit code, a run-in-roblox tier dead in its bootstrap for nine days,
	and thirty-three suites unrunnable for months behind a `.luaurc` alias into a
	repository they no longer sat inside.

	WHAT THIS GATE USED TO BE, and why it could not stay
	It checked the MONOREPO's layout: testkit's `Discover` out of `pkgs/`, and an
	assertion that `tests/engine/prism` still scanned for `.spec.luau` files.
	Neither the package nor the engine tier came across at graduation, so the gate
	failed for a reason that had nothing to do with this repository's tests, and
	sat in `all_gates.BLOCKED` with an accurate description of a question nobody
	had answered. A permanently blocked gate is silent failure in slow motion.

	WHAT IT CANNOT BE HERE, which is the load-bearing part
	The obvious rewrite is "every `*.test.luau` is found by the runner". That is
	worthless. `tests/run.luau` walks the whole repository for exactly the
	patterns in `tests/suites.luau`, so every `*.test.luau` outside `excluded` is
	discovered BY CONSTRUCTION. The gate could never fail; it would print a green
	number that reads identically to the number it would print with the runner
	switched off entirely. Reachability for that one filename shape is closed by
	the runner, and a gate is the wrong instrument for a closed question.

	WHAT IS ACTUALLY STILL OPEN, and what this checks
	Three things, each with a way to happen and no other alarm on it:

	  1. NAMING DRIFT. `Foo.spec.luau`, `foo_test.luau`, `Foo.test.lua` -- one
	     keystroke, or one habit from another repository, away from a suite;
	     matching no runner pattern; sitting in the tree looking exactly like
	     coverage. This is what the old engine tier leaves behind: its `.spec.luau`
	     convention is gone and the muscle memory for it is not.
	  2. A SUITE SILENCED BY CONFIGURATION. `tests/suites.luau` decides what the
	     runner skips. Adding one of ours to `excluded` takes a suite dark with no
	     other symptom, so the census walks PAST that list and reports what it hid.
	  3. A SUITE THAT NEVER REPORTS. A file the runner executes that never calls
	     `T.run` exits 0 having asserted nothing, which is the ms-43 M30 failure
	     exactly. Static and cheap; the runtime half is testkit refusing a run that
	     registered no tests.

	WHAT THIS DOES NOT CATCH, stated because a gate whose limits are unstated gets
	trusted past them:

	  * Reached is not RUN, and a static gate cannot close that. What can, and now
	    does, is `Testkit.run` exiting non-zero on an empty registry -- enforced by
	    the thing that runs the tests, which is where it belongs. The old version
	    of this gate CLAIMED that check already existed here. It did not: the
	    testkit it was inherited from had one and `tests/testkit.luau` did not.
	  * An assertion that cannot fail. Nothing here reads what a test asserts.
]]

local fs = require("@lune/fs")
local Suites = require("../suites")

local failures = 0
local function fail(msg: string)
	failures += 1
	print("FAIL  " .. msg)
end

local stripComments = require("./source_scan").stripComments

-- The premise, checked rather than assumed ------------------------------------
--
-- This gate compares the runner's answer against a broader census, which means
-- something only while the runner takes its answer from the same file. It did
-- not, once: `tests/suites.luau` declared roots that `tests/run.luau` had
-- stopped reading, and the header claiming they shared one home was false for as
-- long as that lasted. The old gate died of that exact class -- asserting a
-- mechanism that had gone away -- so this one checks its own.

local RUNNER = "tests/run.luau"
if not fs.isFile(RUNNER) then
	fail(RUNNER .. " is gone; this gate has nothing to compare against")
elseif not string.find(stripComments(fs.readFile(RUNNER)), 'require("./suites")', 1, true) then
	fail(
		RUNNER
			.. " no longer reads tests/suites.luau, so the patterns this gate checks are not the "
			.. "ones it runs. Repoint the runner, or delete this gate; do not leave the two apart."
	)
end

-- The census ------------------------------------------------------------------
--
-- Deliberately WIDER than the runner's walk, in both directions: it descends
-- into what `Suites.excluded` hides, and it matches names the runner would not
-- run. A census identical to the runner's can only ever agree with it.

--- Vendored or generated. NOT read from `Suites.excluded`, on purpose: the whole
--- point is to see what that list hides, so this is the smaller fixed set of
--- trees that are nobody's business here.
local NOT_OURS = { "roblox_packages", "luau_packages", ".pesde", "target", "node_modules", ".git" }

local candidates: { string } = {}
local function walk(dir: string)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = `{dir}/{entry}`
		if table.find(NOT_OURS, entry) then
			continue
		end
		if fs.isDir(path) then
			walk(path)
		elseif string.match(entry, "%.luau?$") then
			table.insert(candidates, path)
		end
	end
end
walk(".")
table.sort(candidates)

local function matchesAny(path: string, patterns: { string }): boolean
	for _, pattern in ipairs(patterns) do
		if string.match(path, pattern) then
			return true
		end
	end
	return false
end

--- The directory name that stops `tests/run.luau` descending to this path, if any.
local function runnerSkips(path: string): string?
	for segment in string.gmatch(path, "[^/]+") do
		if table.find(Suites.excluded, segment) then
			return segment
		end
	end
	return nil
end

-- The three checks ------------------------------------------------------------

local suites: { string } = {}
local misnamed: { string } = {}
local hidden: { string } = {}

for _, path in ipairs(candidates) do
	local isSuite = matchesAny(path, Suites.patterns)
	local looksLikeOne = matchesAny(path, Suites.alsoTestShaped)
	local skippedBy = runnerSkips(path)

	if isSuite then
		if skippedBy then
			table.insert(hidden, `{path} (hidden by "{skippedBy}")`)
		else
			table.insert(suites, path)
		end
	elseif looksLikeOne and not skippedBy then
		table.insert(misnamed, path)
	end
end

for _, path in ipairs(misnamed) do
	fail(
		`{path}: DARK -- it is named like a test, matches no pattern in tests/suites.luau, and so `
			.. `nothing runs it. Rename it to *.test.luau, or delete it. A test nobody runs reads as `
			.. `coverage and is not.`
	)
end

for _, entry in ipairs(hidden) do
	fail(
		`{entry}: a suite of ours sits under a directory tests/suites.luau tells the runner to `
			.. `skip. Silencing a suite is a decision, and it does not get to be a quiet one.`
	)
end

--- A suite the runner EXECUTES that never reports. It exits 0 having asserted
--- nothing, which is how eight suites passed in ms-43 M30 while returning an
--- uninvoked function. Comments are stripped first, so a suite that only
--- MENTIONS `run` in prose does not count as calling it.
local silent: { string } = {}
for _, path in ipairs(suites) do
	if not string.find(stripComments(fs.readFile(path)), "%.run%(") then
		table.insert(silent, path)
	end
end

for _, path in ipairs(silent) do
	fail(
		`{path}: never calls a runner. It is executed as its own process and exits 0 whatever its `
			.. `tests would have done -- add the T.run(...) call that reports them.`
	)
end

-- Report ----------------------------------------------------------------------

print(`test inventory: {#suites} suite(s) the runner executes, {#candidates} luau file(s) scanned`)
print(`  runner patterns:  {table.concat(Suites.patterns, "  ")}`)
print(`  also test-shaped: {table.concat(Suites.alsoTestShaped, "  ")}`)

print("")
if failures > 0 then
	print(`VERIFY TEST INVENTORY: FAILED ({failures} problem(s))`)
	local process = require("@lune/process")
	process.exit(1)
else
	print(`VERIFY TEST INVENTORY: PASS ({#suites} suites, nothing dark)`)
end
return true
