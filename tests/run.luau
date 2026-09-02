--!strict
--[[
	Run every suite in this repository.

	    lune run tests/run.luau              every suite
	    lune run tests/run.luau Scroll       only suites whose path matches

	WHAT THIS REPLACED was 587 lines inherited from the monorepo, orchestrating
	tiers and naming suites that do not exist here -- ManifoldHull, vehicle runs,
	a 362-shape arena. It required `@testkit_env`, an alias into a repository this
	one no longer sits inside, so it could not run at all. None of what it managed
	is Aether's.

	ONE PROCESS PER SUITE, like the gate runner. Slower than requiring them in
	order, and it means a suite that corrupts global state or crashes outright
	takes only itself down -- which is worth more than the seconds, and is how the
	failure gets attributed to the right file.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

--- WHAT COUNTS AS A SUITE IS NOT DECIDED HERE. `verify_test_inventory` has to
--- check the same answer, and the two lived apart long enough for this file to
--- stop reading the config that claimed to own them both.
local Suites = require("./suites")

local filter = process.args[1]

--- Every file matching `Suites.patterns`, skipping `Suites.excluded`.
local function discover(dir: string, found: { string })
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = `{dir}/{entry}`
		if table.find(Suites.excluded, entry) then
			continue
		end
		if fs.isDir(path) then
			discover(path, found)
		else
			for _, pattern in ipairs(Suites.patterns) do
				if string.match(path, pattern) then
					table.insert(found, path)
					break
				end
			end
		end
	end
	return found
end

local suites = discover(".", {})
table.sort(suites)

local ran, failed = 0, 0
for _, suite in ipairs(suites) do
	if filter and not string.find(string.lower(suite), string.lower(filter), 1, true) then
		continue
	end
	ran += 1
	local r = process.exec("lune", { "run", suite })
	if not r.ok then
		failed += 1
		print(`::error::{suite}`)
		stdio.write(r.stdout)
		stdio.write(r.stderr)
	end
end

print("")
if failed > 0 then
	print(`SUITES: FAILED ({failed} of {ran})`)
	process.exit(1)
end
print(`SUITES: PASS (all {ran})`)
