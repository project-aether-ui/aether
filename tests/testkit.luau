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

--- Register a test. The third argument is a tier the monorepo's runner used to
--- filter on; it is accepted and ignored, because nothing here filters and a
--- suite passing an argument that errors is worse than one passing an argument
--- that does nothing.
function Testkit.test(name: string, fn: () -> (), tier: string?)
	table.insert(pending, { name = prefix .. name, fn = fn, tier = tier })
end

--- The same thing under the name a BDD-shaped suite reaches for.
function Testkit.it(name: string, fn: () -> ())
	Testkit.test(name, fn)
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
