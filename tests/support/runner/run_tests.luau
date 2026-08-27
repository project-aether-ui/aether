--!strict
--[[
	run_tests.luau — the prism spec suite, by its historical name.

	This used to drive rojo + run-in-roblox itself, and was the SECOND copy of the engine
	path after `tests/run.luau --env=engine` landed. Two copies that agree until they don't
	is the class this repo has now paid for four times (ms-43 M116, ms-44 M3/M7), and this
	copy had already gone wrong in the quiet direction: it named `tests/default.project.json`
	and `tests/runner/entry.server.luau`, neither of which survived the ms-44 layout change.
	Nothing reported that, because the only callers are the milestone-scoped verify_m1/m2/m3
	gates, which are not in `all_gates`.

	So it is a DELEGATOR now, not a runner. It keeps the name those gates spawn while the one
	real engine path stays in `tests/run.luau` — which also means it picks up transport
	selection (run-in-roblox panics when Studio is open) that this file never had.
]]

local process = require("@lune/process")

local result = process.exec("lune", { "run", "tests/run.luau", "--env=engine", "prism" }, { stdio = "forward" })
if not result.ok then
	process.exit(if result.code ~= 0 then result.code else 1)
end
