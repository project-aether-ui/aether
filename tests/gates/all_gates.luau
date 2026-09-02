--!strict
--[[
	The structural gates, in ONE list — read by the pre-commit hook and by CI.

	WHY (ms-44 M7)
	The hook had this list inline and the workflow had its own copy. They happened to be
	identical the day the workflow was written, which is the most dangerous state for two
	lists to be in: nothing would have reported the day they stopped matching, and the
	failure is silent in the worst direction — CI green because it never ran the gate the
	hook enforces, or a hook enforcing a gate CI never sees.

	This repo has hit that exact class three times now: ms-43 M116 split the tier table out
	of its gate for it, ms-44 M3 made `tests/suite_config.luau` shared between the runner
	and the inventory gate for it, and this is the third.

	RUN DIRECTLY to execute every gate:  lune run tests/gates/all_gates.luau --run
	REQUIRE to read the list:            require("./all_gates").GATES

	`--run` IS NOT OPTIONAL, and this line said it was. Without the flag the file
	is a module: it returns its list, prints nothing, and exits 0. Following the
	instruction as written gave a silent pass for every gate in it, which is the
	one result a gate runner must never produce by accident.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
-- lune has no `io` global; stdout goes through @lune/stdio.
local stdio = require("@lune/stdio")

local M = {}

--- Permanent repo invariants, cheapest first so a failure surfaces fast.
---
--- WHAT DID NOT COME ACROSS AT GRADUATION, and why each one belongs to the monorepo
--- rather than here:
---
---     verify_package_tiers        asserts `pkgs/` is grouped by domain then tier, with
---                                 dependencies running downward inside a domain. This
---                                 repo has one package and three members; there is no
---                                 tier lattice for it to check.
---     verify_lockstep             enforces that every manifest moves together. That is
---                                 the policy Aether left. Versions here are independent
---                                 and consumers pin by commit.
---     verify_package_resolution   its path list is prism and studio.
---     verify_53d8                 walks `pkgs/ui` and the AetherSwitcherDemo example,
---                                 neither of which exists here.
---     verify_43                   milestone-scoped to ms-43, already the odd one out.
---
---     verify_frame_checks         drove the zune CLI, and so did
---     verify_headless_is_portable  verify_headless_is_portable. Both are gates worth
---                                  having -- one is the control proving a checker that
---                                  flags everything fails nowhere else, the other proves
---                                  no headless entry point reaches a platform. They come
---                                  BACK, repointed at `aether` once that CLI exists.
---                                  They are deleted rather than left failing because a
---                                  permanently red gate teaches everyone to ignore the
---                                  gate report.
---
--- The rest are permanent and should stay.
M.GATES = {
	"tests/gates/verify_cycles.luau",
	"tests/gates/verify_require_paths.luau",
	"tests/gates/verify_property_names.luau",
	"tests/gates/verify_use_before_declaration.luau",
	"tests/gates/verify_reactive_scopes.luau",
	"tests/gates/verify_autosize_cycles.luau",
	"tests/gates/verify_test_inventory.luau",
	"tests/gates/verify_tests_not_shipped.luau",
	"tests/gates/verify_no_versioned_vendor_paths.luau",
}

--- Gates that fail for a reason outside this repository, and why.
---
--- A KNOWN-FAILING GATE IS STILL RUN and still reported; it simply does not fail
--- the run. The alternative is a suite that is permanently red, which trains
--- everyone to stop reading it -- the same reasoning the conformance suite uses
--- for a case it cannot yet support.
---
--- Each entry is a debt with a name. Emptying this table is the goal; adding to
--- it should feel expensive.
M.BLOCKED = {
	--- EMPTY, and it is meant to stay that way.
	---
	--- The last entry was `verify_test_inventory`, blocked because it checked the
	--- MONOREPO's layout: testkit's `Discover` out of `pkgs/`, and an assertion
	--- that `tests/engine/prism` scanned for `.spec.luau` files. Neither exists
	--- here. It has been rewritten to ask what a test inventory means in THIS
	--- repository -- a file named like a test that no pattern runs, a suite hidden
	--- by `tests/suites.luau`, a suite that never calls a runner -- and each of
	--- those three was checked by breaking it on purpose before the entry came
	--- out. A gate that has never been seen to fail is not known to work.
}

--- Executed only when this file is RUN, not when it is required. `process.args` is empty
--- for a required module and `script` is nil under lune, so the discriminator is simply
--- whether the caller asked us to run: CI passes `--run`.
---
--- Kept explicit rather than clever. A module that executes on require would break the
--- hook, which requires it purely for the list.
function M.run(): number
	local failed = 0
	local blocked = 0
	for _, gate in ipairs(M.GATES) do
		if not fs.isFile(gate) then
			print(`::error::{gate} is listed but does not exist`)
			failed += 1
			continue
		end
		print(`::group::{gate}`)
		local r = process.exec("lune", { "run", gate })
		stdio.write(r.stdout)
		if not r.ok then
			stdio.write(r.stderr)
			local why = M.BLOCKED[gate]
			if why then
				blocked += 1
				print(`::warning::{gate} is BLOCKED: {why}`)
			else
				print(`::error::{gate} FAILED`)
				failed += 1
			end
		end
		print("::endgroup::")
	end
	print("")
	local ran = #M.GATES - blocked
	if failed > 0 then
		print(`GATES: FAILED ({failed} of {ran} runnable, {blocked} blocked)`)
	elseif blocked > 0 then
		print(`GATES: PASS ({ran} of {#M.GATES}; {blocked} blocked, see BLOCKED)`)
	else
		print(`GATES: PASS (all {#M.GATES})`)
	end
	return failed
end

for _, a in ipairs(process.args) do
	if a == "--run" then
		process.exit(if M.run() > 0 then 1 else 0)
	end
end

return M
