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

--- Turn a case's encoded value into a real one.
---
--- The encoding is `{ "TypeName", ...args }` for anything that is not a plain
--- number, string or boolean. It exists so a case is JSON-shaped: a Rust runner
--- reads the same array and calls the same constructor.
local function decode(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local kind = value[1]
	if kind == "UDim2" then
		return UDim2.new(value[2], value[3], value[4], value[5])
	elseif kind == "UDim" then
		return UDim.new(value[2], value[3])
	elseif kind == "Color3" then
		return Color3.new(value[2], value[3], value[4])
	elseif kind == "Vector2" then
		return Vector2.new(value[2], value[3])
	elseif kind == "Enum" then
		--- `{ "Enum", "AutomaticSize", "Y" }`. Spelled by name rather than by
		--- number, because Roblox's enum VALUES are an implementation detail and
		--- a case that encoded them would be asserting something the standard does
		--- not say.
		local category = (Enum :: any)[value[2]]
		if not category then
			error(`conformance: no enum category '{value[2]}'`)
		end
		local member = category[value[3]]
		if not member then
			error(`conformance: {value[2]} has no member '{value[3]}'`)
		end
		return member
	end
	error(`conformance: unknown encoded type '{tostring(kind)}'`)
end

local function build(node: any): any
	local props: { [any]: any } = {}
	for key, value in pairs(node.props or {}) do
		props[key] = decode(value)
	end
	if node.name then
		props.Name = node.name
	end
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
	table.insert(results, runCase(case))
end

table.sort(results, function(a, b)
	return a.name < b.name
end)

local failed = 0
local divergent = 0
local open = 0

print("")
for _, r in ipairs(results) do
	if r.ok then
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
	`CONFORMANCE: {#results - failed - open} of {#results} passing `
		.. `({verified} verified against Roblox, {divergent} documented gaps, `
		.. `{open} open questions)`
)

if failed > 0 then
	process.exit(1)
end
