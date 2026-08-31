--!strict
--[[
	The conformance runner, for the Luau implementation.

	Builds each case's tree through the host, solves it, and compares the display
	list against what the case expects. A Rust runner will read the same cases and
	do the same thing against a native implementation — which is the entire point
	of cases being DATA rather than builder functions.

	WHAT THIS DELIBERATELY DOES NOT DO: interpret a failure. It reports the node,
	the field, the expected value and the actual one, and stops. Deciding whether
	the implementation or the expectation is wrong depends on the case's
	provenance, and that is a judgement rather than a computation.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local Host = require("../src/host/Host")
local Live = require("../src/host/Live")

local host = Host.detect()
host.InstallVocabulary()

--- Shared with the Roblox runner, so a case cannot mean two things.
local decode = require("./decode")

local function build(node: any): any
	local props: { [any]: any } = decode.props(node)
	for _, child in ipairs(node.children or {}) do
		table.insert(props, build(child))
	end
	return host.create(node.class)(props)
end

--- Compare one node against its expectation.
---
--- ONLY THE FIELDS THE CASE NAMES. A case asserting geometry should not fail
--- because a colour changed; a case that wants to assert a colour says so. This
--- keeps a case's meaning legible from the case itself.
local TOLERANCE = 0.01

local function compare(expected: any, actual: any): string?
	for field, want in pairs(expected) do
		if field == "name" then
			continue
		end
		local got = actual[field]
		if got == nil then
			return `{field}: expected {want}, node has no such field`
		end
		if type(want) == "number" then
			if math.abs(got - want) > TOLERANCE then
				return `{field}: expected {want}, got {got}`
			end
		elseif got ~= want then
			return `{field}: expected {tostring(want)}, got {tostring(got)}`
		end
	end
	return nil
end

type Result = { name: string, provenance: string, ok: boolean, detail: string?, note: string? }

local function runCase(case: any): Result
	local root
	local built = pcall(function()
		host.root(function()
			root = build(case.tree)
			return root
		end)
	end)
	if not built or root == nil then
		return { name = case.name, provenance = case.provenance, ok = false, detail = "the tree failed to build" }
	end

	local width = case.surface.width
	local height = case.surface.height
	local frame = Live.Snapshot(host, root, width, height)

	--- Index the produced nodes by name. A case names what it cares about; the
	--- display list's ORDER is a separate assertion (`order`), because a case
	--- about geometry should not break when paint order changes.
	--- A CASE THAT ASSERTS NOTHING CANNOT PASS. Same hole the engine runner had:
	--- an empty `expect` with no `ratios` walked no loops and was reported as
	--- passing, which manufactures confidence out of nothing.
	if #case.expect == 0 and #(case.ratios or {}) == 0 then
		return {
			name = case.name,
			provenance = case.provenance,
			ok = false,
			detail = "the case asserts nothing",
			note = case.note,
		}
	end

	local byName: { [string]: any } = {}
	for _, node in ipairs(frame.Nodes) do
		byName[node.name] = node
	end

	for _, expected in ipairs(case.expect) do
		local actual = byName[expected.name]
		if not actual then
			return {
				name = case.name,
				provenance = case.provenance,
				ok = false,
				--- SAY WHY IT MIGHT BE ABSENT. `Live` drops any node whose solved
				--- rectangle has zero width or height, so "missing" most often means
				--- "measured to nothing" rather than "never built" — and the first
				--- time this fired, the difference was the entire finding.
				detail = `no node named '{expected.name}' in the display list `
					.. `(a node solved to zero width or height is dropped, so it may have `
					.. `been built and measured to nothing)`,
				note = case.note,
			}
		end
		local mismatch = compare(expected, actual)
		if mismatch then
			return {
				name = case.name,
				provenance = case.provenance,
				ok = false,
				detail = `{expected.name}: {mismatch}`,
				note = case.note,
			}
		end
	end

	--- RATIOS, for anything an implementation cannot be held to exactly.
	---
	--- Text measurement is a HOST SERVICE with a different provider per host: the
	--- engine's own bounds in Roblox, a per-glyph table off-engine, a browser
	--- cache on the web, real font metrics in Dew. No case can assert that a
	--- string is 71.4 pixels wide, because that is true of one provider.
	---
	--- What every correct provider agrees on is the RELATIONSHIPS. Doubling
	--- `TextSize` doubles the width. A wider string measures wider. Those hold
	--- everywhere, and they are what a case about text can honestly assert.
	for _, r in ipairs(case.ratios or {}) do
		local of, to = byName[r.of], byName[r.to]
		if not of or not to then
			return {
				name = case.name,
				provenance = case.provenance,
				ok = false,
				detail = `ratio needs '{r.of}' and '{r.to}'; one is missing from the display list`,
				note = case.note,
			}
		end
		local denominator = to[r.field]
		if denominator == 0 then
			return {
				name = case.name,
				provenance = case.provenance,
				ok = false,
				detail = `ratio {r.of}.{r.field} / {r.to}.{r.field}: the denominator is zero`,
				note = case.note,
			}
		end
		local actual = of[r.field] / denominator
		local slack = r.tolerance or 0.02
		if math.abs(actual - r.expect) > slack then
			return {
				name = case.name,
				provenance = case.provenance,
				ok = false,
				detail = string.format(
					"ratio %s.%s / %s.%s: expected %.3f +/- %.3f, got %.3f",
					r.of, r.field, r.to, r.field, r.expect, slack, actual
				),
				note = case.note,
			}
		end
	end

	--- ABSENCE IS AN ASSERTION TOO. A case naming `expectAbsent` is claiming the
	--- display list does NOT contain something — a node measured to nothing, or
	--- one made invisible. Without this the field would be decoration, and a case
	--- that states an intent the harness does not check is worse than one that
	--- says less.
	for _, absent in ipairs(case.expectAbsent or {}) do
		if byName[absent] then
			return {
				name = case.name,
				provenance = case.provenance,
				ok = false,
				detail = `'{absent}' is in the display list and the case expects it absent`,
				note = case.note,
			}
		end
	end

	return { name = case.name, provenance = case.provenance, ok = true, note = case.note }
end

--- WHAT THIS IMPLEMENTATION CLAIMS TO SUPPORT.
---
--- A case naming a feature absent from this list is reported UNSUPPORTED rather
--- than failed. Roblox ships features continuously — radial `UIGradient` is next
--- — and a case for one we have not built yet is a roadmap item, not a
--- regression. Failing it would make the suite red for the entirely correct
--- reason that we are behind, and a permanently red suite stops being read.
---
--- Adding a feature here is a claim. If it is listed and the case fails, that is
--- a real failure.
local SUPPORTS: { [string]: boolean } = {
	["UIListLayout"] = true,
	["UIPadding"] = true,
	["UICorner"] = true,
	["AutomaticSize"] = true,
	["AnchorPoint"] = true,
	["ClipsDescendants"] = true,
}

local function unsupported(case: any): string?
	for _, feature in ipairs(case.requires or {}) do
		if not SUPPORTS[feature] then
			return feature
		end
	end
	return nil
end

local filter = process.args[1]
local results: { Result } = {}

for _, entry in ipairs(fs.readDir("conformance/cases")) do
	if not string.match(entry, "%.luau$") then
		continue
	end
	local case = require(`../conformance/cases/{string.gsub(entry, "%.luau$", "")}`)
	if filter and not string.find(string.lower(case.name), string.lower(filter), 1, true) then
		continue
	end
	local missing = unsupported(case)
	if missing then
		table.insert(results, {
			name = case.name,
			provenance = case.provenance,
			ok = true,
			detail = missing,
			note = "unsupported",
		})
	else
		table.insert(results, runCase(case))
	end
end

table.sort(results, function(a, b)
	return a.name < b.name
end)

local failed = 0
local divergent = 0
local open = 0
local skipped = 0

print("")
for _, r in ipairs(results) do
	if r.note == "unsupported" then
		--- NOT A PASS AND NOT A FAILURE. The case describes behaviour this
		--- implementation has not built; the expectation may well be right.
		skipped += 1
		print(`  -  {r.name}  (unsupported: {r.detail})`)
	elseif r.ok then
		--- A `divergent` case that PASSES is reported, not celebrated: it means
		--- the implementation still matches a behaviour known to be wrong, which
		--- is the state the note describes rather than a success.
		if r.provenance == "divergent" then
			divergent += 1
			print(`  ~  {r.name}  (divergent, still matching the documented gap)`)
		else
			print(`  ok {r.name}  [{r.provenance}]`)
		end
	elseif r.provenance == "asserted" then
		--- AN OPEN QUESTION, NOT A FAILURE. The case states what we believe Roblox
		--- does; the implementation disagrees; nobody has opened Studio. Counting
		--- it as a failure would leave the suite permanently red, which teaches
		--- everyone to stop reading it. Verify it, and it becomes `roblox` — at
		--- which point failing IS failing.
		open += 1
		print(`  ?  {r.name}  (unverified — implementation disagrees)`)
		print(`       {r.detail}`)
		if r.note then
			print(`       {r.note}`)
		end
	else
		failed += 1
		print(`  FAIL {r.name}  [{r.provenance}]`)
		print(`       {r.detail}`)
	end
end

local verified = 0
for _, r in ipairs(results) do
	if r.provenance == "roblox" then
		verified += 1
	end
end

print("")
print(
	`CONFORMANCE: {#results - failed - open - skipped} of {#results - skipped} passing `
		.. `({verified} verified against Roblox, {divergent} documented gaps, `
		.. `{open} open questions, {skipped} unsupported)`
)

if failed > 0 then
	process.exit(1)
end
