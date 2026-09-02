--!strict
--[[
	The four functions the suites actually use.

	`spektr/testkit` was reached through a `.luaurc` alias into the monorepo, so
	when Aether graduated the alias pointed at `./.testkit/core/src`, which does
	not exist here. Thirty-three suites stopped running, and the gate that counts
	them was the only visible symptom -- their silence read as success for months.

	WHAT IT WAS PROVIDING, measured across every suite in this repository:

	    T.test       171 uses
	    T.run         33
	    T.it          11
	    T.describe     6

	And 815 plain `assert()` calls doing the actual checking. That is a registry,
	not a framework, so this replaces it rather than chasing a cross-repository
	dependency on a private monorepo for four functions.

	A suite registers its tests and then calls `T.run`, which is why requiring a
	suite file runs it. That shape is kept exactly, so no suite changed.
]]

local process = require("@lune/process")

local Testkit = {}

type Case = { name: string, fn: () -> (), tier: string? }

local pending: { Case } = {}
local prefix = ""

--- Register a test.
---
--- TWO SHAPES, because the suites use two. Most call `test(name, fn)`; the
--- conformance suites call `it(name, { tier = "math" }, fn)`, with the options
--- table in the MIDDLE. A first draft of this file guessed a tier STRING in the
--- trailing position, which type-checked fine and then failed all eleven of
--- HostConformance's cases with "attempt to call a table value" -- the options
--- table being called as the body.
---
--- `tier` selected subsets in the monorepo's runner. Nothing here selects, so it
--- is recorded and not acted on: a suite is either in this repository and run, or
--- it is not here. It is kept rather than rejected because a suite passing an
--- argument that does nothing is a great deal better than one that errors.
local function register(name: string, a: any, b: any)
	local fn = if type(a) == "function" then a else b
	local opts = if type(a) == "table" then a else nil
	assert(type(fn) == "function", `{name}: no test body`)
	table.insert(pending, {
		name = prefix .. name,
		fn = fn,
		tier = if opts then opts.tier else nil,
	})
end

function Testkit.test(name: string, a: any, b: any?)
	register(name, a, b)
end

--- The same thing under the name a BDD-shaped suite reaches for.
function Testkit.it(name: string, a: any, b: any?)
	register(name, a, b)
end

--- Group the tests a callback registers under one label.
function Testkit.describe(name: string, fn: () -> ())
	local outer = prefix
	prefix = `{outer}{name} > `
	fn()
	prefix = outer
end

--- Run everything registered, report, and exit non-zero if anything failed.
---
--- EXITS RATHER THAN RETURNING A FLAG. Each suite is its own process under
--- tests/run.luau, and a suite that fails silently and returns is a suite the
--- runner records as passing.
function Testkit.run(label: string): number
	local failed = 0
	local cases = pending
	pending = {}

	--- A SUITE THAT REGISTERED NOTHING IS A FAILURE, not a pass.
	---
	--- Without this, `run` on an empty registry printed "0 passed" and returned
	--- 0, which is the same shape as a green suite and reads as one in a log.
	--- Every way a suite goes dark short of a load error ends here: a `test`
	--- call moved inside a branch that is never taken, a `describe` body that
	--- errors before registering, a file whose registrations were deleted with
	--- the code they covered.
	---
	--- `verify_test_inventory` used to claim this check existed, inherited from a
	--- testkit that had it. It was not true of this one.
	if #cases == 0 then
		print(`{label}: NO TESTS REGISTERED: a suite that registers nothing cannot pass`)
		process.exit(1)
	end

	for _, case in ipairs(cases) do
		local ok, err = pcall(case.fn)
		if not ok then
			failed += 1
			print(`  FAIL  {case.name}`)
			print(`        {tostring(err)}`)
		end
	end

	if failed > 0 then
		print(`{label}: {#cases - failed} of {#cases} passed`)
		process.exit(1)
	end

	print(`{label}: {#cases} passed`)
	return 0
end

return Testkit
