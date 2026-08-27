--!strict
--[[
	verify_frame_checks — every check catches its violation, and lets the rest be
	(ms-53 P3).

	    lune run tests/gates/verify_frame_checks.luau

	WHAT IT PROTECTS

	`aether-cli check` asserts PROPERTIES of a frame -- text wider than its box,
	a line taller than its box, contrast below a threshold -- and needs no
	baseline, which is the whole reason it exists: this renderer is not bit-stable
	across backends (ms-52), upstream versions (ms-52) or platforms (ms-53 P2), so
	a pixel baseline is three-dimensional and a property is not.

	A checker like that has exactly one interesting failure mode: it stops
	catching things and nobody notices, because a run with no findings looks
	identical to a run with a broken checker. So every rule owns a story that
	breaks it ON PURPOSE, and this requires each one to be caught.

	BOTH DIRECTIONS, and the second is the half that matters. `Clean` must produce
	NOTHING -- a checker that flags everything passes the first half of this gate
	perfectly, and would make the tool useless in a way that reads as diligence.

	AND THE EXEMPTION IS TESTED TOO. `Low contrast, allowed` is the same violation
	as `Low contrast text` with `Allow = { "contrast" }` on the story. One must be
	caught and the other must not, or the escape hatch is either inert (and people
	disable the check globally) or too wide (and it silences its neighbours).

	IT RUNS THE REAL CLI. The checks need real text metrics, which need the Rust
	backend, which needs zune -- so this spawns the command a developer runs rather
	than reimplementing it. A gate that exercises a copy of the thing is a gate for
	the copy.
]]

local process = require("@lune/process")

local CLI = "hosts/zune/src/Cli.luau"

type Case = {
	--- Story query passed to `--story`.
	story: string,
	--- Extra flags, for the localisation mode.
	args: { string }?,
	--- The check that must appear, or nil when the run must be SILENT.
	expect: string?,
	--- Why this case exists, for the report.
	why: string,
}

local CASES: { Case } = {
	{
		story = "Violations:Clean",
		expect = nil,
		why = "the control -- a checker that flags everything fails here and nowhere else",
	},
	{
		story = "Violations:Overflowing text",
		expect = "overflow",
		why = "text wider than its box",
	},
	{
		story = "Violations:Vertically clipped text",
		expect = "vertical",
		why = "a line taller than its box",
	},
	{
		story = "Violations:Low contrast text",
		expect = "contrast",
		why = "white on #38BDF8, 2.14:1 -- the real ShopUI call-to-action",
	},
	{
		story = "Violations:Blue on white, legible",
		expect = nil,
		why = "WCAG measures 8.59:1 and passes; a naive (r+g+b)/3 measures 2.74:1 and does not -- "
			.. "this is the only case that asserts the luminance WEIGHTS rather than the check",
	},
	{
		story = "Violations:Low contrast, allowed",
		expect = nil,
		why = "the same violation with Allow = { contrast } -- the exemption must silence it",
	},
	{
		story = "Violations:Fits in English only",
		expect = nil,
		why = "fits at 1x, so the overflow check must NOT fire",
	},
	{
		story = "Violations:Fits in English only",
		args = { "--expand", "1.5" },
		expect = "overflow",
		why = "and MUST fire at 1.5x -- this is what separates the localisation mode from the check",
	},
}

local function run(case: Case): (boolean, string, string)
	local args = { "run", CLI, "check", "--story", case.story }
	for _, a in ipairs(case.args or {}) do
		table.insert(args, a)
	end
	local result = process.exec("zune", args)
	--- BOTH STREAMS: zune's `print` goes to stderr, so reading stdout alone
	--- reports every run as silent -- which for this gate would mean every
	--- "expect nothing" case passing vacuously.
	local combined = result.stdout .. string.char(10) .. result.stderr

	--- A run that produced no summary line did not check anything. Without this,
	--- a CLI that crashed on startup satisfies every `expect = nil` case.
	local ran = string.find(combined, "finding%(s%) across") ~= nil
	if not ran then
		return false, combined, "the CLI produced no summary -- it did not run"
	end

	local found = case.expect ~= nil and string.find(combined, case.expect, 1, true) ~= nil
	if case.expect == nil then
		if result.ok and string.find(combined, "0 finding%(s%)") then
			return true, combined, "silent, as required"
		end
		return false, combined, "expected NO findings"
	end
	if found and not result.ok then
		return true, combined, `caught by "{case.expect}"`
	end
	return false, combined, `expected a "{case.expect}" finding and a non-zero exit`
end

local failures = 0
for _, case in ipairs(CASES) do
	local passed, output, note = run(case)
	local label = case.story .. (if case.args then " " .. table.concat(case.args, " ") else "")
	print(string.format("  %-6s %-44s %s", if passed then "ok" else "FAIL", label, note))
	if not passed then
		failures += 1
		print(`         why this case exists: {case.why}`)
		for line in string.gmatch(output, "[^\n]+") do
			print(`         | {line}`)
		end
	end
end

if failures > 0 then
	print(`{failures} of {#CASES} case(s) failed`)
	process.exit(1)
end

print(`OK -- {#CASES} cases: every check catches its violation, the control stays silent, `
	.. "and the exemption silences exactly one story.")
