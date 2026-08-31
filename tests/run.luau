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

local filter = process.args[1]

--- Every `*.test.luau`, excluding installed packages: a dependency's own suites
--- are its business and pass or fail on its terms, not ours.
local function discover(dir: string, found: { string })
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = `{dir}/{entry}`
		if entry == "roblox_packages" or entry == ".pesde" or entry == "target" then
			continue
		end
		if fs.isDir(path) then
			discover(path, found)
		elseif string.match(entry, "%.test%.luau$") then
			table.insert(found, path)
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
