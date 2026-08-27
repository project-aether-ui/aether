--!strict
--[[
	Where this repo keeps its lune suites — ONE table, read by both the runner and the gate.

	WHY IT IS ITS OWN FILE (inherited from spektr/essentials, ms-44 M3)
	`tests/run.luau` discovers suites from these roots; `verify_test_inventory` must check
	the SAME set, or the two drift in the worst possible way — the gate would certify a
	layout the runner no longer scans, and nobody would find out until a suite went dark.

	This is also the file that makes testkit's portability real: every path, pattern and
	root specific to THIS repo lives here, and `spektr/testkit` mentions none of it. That
	property is what let Aether graduate out of the monorepo without touching the runner —
	only this table changed.

	    monorepo    roots = { "pkgs", "tests/lune", "tests/gates" }
	    here        roots = { "src", "tests", "packages", "hosts" }
]]

return {
	--- Directories the runner walks.
	---
	--- `src` is listed because suites still sit beside the code they cover; the monorepo
	--- had the same arrangement and the same standing intent to move them under `tests/`.
	--- Narrowing this before they move would make suites vanish from the runner silently.
	roots = { "src", "tests", "packages", "hosts" },

	--- A file is a lune suite when its BASENAME matches one of these.
	patterns = { "%.test%.luau$" },
}
