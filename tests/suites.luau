--!strict
--[[
	What counts as a suite, and what the runner skips -- ONE table, read by both
	`tests/run.luau` and `verify_test_inventory`.

	WHY IT IS ITS OWN FILE (inherited from spektr/essentials, ms-44 M3)
	The runner decides what runs; the gate decides what SHOULD run. If those two
	answers come from two places they drift in the worst possible direction -- the
	gate certifies a layout the runner no longer scans, and nobody finds out until
	a suite goes dark.

	IT HAD ALREADY DRIFTED. This file declared `roots = { "src", "tests",
	"packages", "hosts" }` and the runner had stopped reading it, scanning the
	whole repository instead. The claim in this header was false for as long as
	that lasted -- the failure this file exists to prevent, committed by the file
	that prevents it. `verify_test_inventory` now checks that the runner still
	requires this module, so the claim is enforced rather than asserted in prose.

	THERE IS NO `roots` ANY MORE. A root list is a way for a suite to go dark by
	being written outside it: nothing fails, the file simply is never looked at.
	The runner walks the repository and skips `excluded`, so a new directory is
	covered the day it appears rather than the day someone remembers this file.
]]

return {
	--- Directory NAMES the runner does not descend into, matched at any depth.
	---
	--- Every one is vendored or generated. A dependency's own suites are its
	--- business and pass or fail on its terms, not ours.
	---
	--- ADDING ANYTHING OF OURS HERE IS A GATE FAILURE, not a configuration
	--- change: `verify_test_inventory` walks past this list and reports every
	--- suite it hid. Silencing a suite has to be visible.
	excluded = { "roblox_packages", "luau_packages", ".pesde", "target", "node_modules", ".git" },

	--- A file is a suite when its path matches one of these, and the runner
	--- executes it as its own process.
	patterns = { "%.test%.luau$" },

	--- Naming conventions that LOOK like tests and that the runner does not run.
	---
	--- Read only by `verify_test_inventory`, which fails on any file matching one
	--- of these. That is the whole of what a gate can still catch here: the runner
	--- scans the entire repository for `patterns`, so a `*.test.luau` is reachable
	--- by construction and checking it would be a green number that reads the same
	--- with the runner switched off. A `Foo.spec.luau` is not reachable, and would
	--- sit in the tree looking exactly like coverage.
	---
	--- The wrong EXTENSION is on the list for the same reason: `Foo.test.lua` is
	--- one keystroke from a suite and invisible to every pattern above.
	---
	--- Deliberately NOT `[Tt]ests?%.luau$`: `src/HitTest.luau` is a source module
	--- and would be reported as a dark test forever. A gate that cries wolf is a
	--- gate people learn to pass with an exception list.
	alsoTestShaped = {
		"%.spec%.luau$",
		"%.spec%.lua$",
		"%.test%.lua$",
		"%.tests%.luau$",
		"_test%.luau$",
		"/test_[^/]*%.luau$",
	},
}
