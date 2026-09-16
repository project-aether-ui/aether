--!strict
--[[
	verify_primitives_bind_machines -- a primitive draws; a machine decides what
	is true.

	WHY
	`@ark-ui/react`'s Pressable equivalent is a file that imports a machine,
	spreads the prop bags the machine hands back, and decides nothing. That is why
	ark can ship the same component for React, Solid and Vue: the part that would
	have to be written three times contains no rules. Aether has the machines --
	`src/core/` and `src/controllers/` reach no framework and name no engine type,
	and a gate fails a build over it -- and several of the components do not use
	them.

	THE FIRST HALF IS CHEAP AND THE SECOND HALF IS THE GATE. Asking whether a
	primitive REQUIRES a Layer 1 module is a question anyone can answer by adding
	a require and using the result for nothing. So this reports two things per
	primitive and enforces both:

	  1. it names a module under `src/core/` or `src/controllers/`, AND refers to
	     the local it bound that require to somewhere other than the require line;
	  2. it implements no interaction logic of its own, by four signals that are
	     about STATEMENTS rather than imports -- see SIGNALS.

	WHAT COUNTS AS INTERACTION LOGIC, and why these four. Each one is a place
	where the component decides something a machine could have decided, and each
	is visible as a statement in the body rather than as a line at the top:

	  writes an input handler        `OnActivated = function() ... end` is a rule
	                                 about what a press MEANS, written where the
	                                 drawing is.
	  holds interaction state        `local isHovered = source(false)` is the
	                                 state chart, spelled out one boolean at a
	                                 time in the binding.
	  registers with the router      calling `PointerRouter.Pressable(...)` is
	                                 doing the hit-testing wiring in person. A
	                                 binding may still KNOW the router -- it is
	                                 the thing that has one -- but it hands it to
	                                 a machine rather than driving it.
	  listens to host input          `UserInputService`, `InputBegan` and their
	                                 relatives are the platform, and a component
	                                 reaching them has no headless half at all.

	A PRIMITIVE IS UNDER THE RULE UNLESS IT IS IN `PENDING`. Membership by
	location, the same as the Layer 1 boundary gate: a primitive added tomorrow is
	checked tomorrow, rather than on the day someone remembers to list it. Each
	entry in `PENDING` is a component whose machine has not been extracted yet and
	says what that machine would own. Emptying that table is the point; adding to
	it should feel expensive.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local SourceScan = require("./source_scan")

local SUBJECT = "src/primitives/"

--- Where a machine lives. Identical to the Layer 1 boundary gate's list, because
--- it is the same boundary read from the other side.
local LAYER_1 = { "core/", "controllers/" }

--- Interaction state a binding must not hold, matched against the NAME of a
--- local initialised to a boolean or to a source. `hoverPeriod = 0.15` is a
--- spring constant and stays; `isHovered = source(false)` is a state chart.
local INTERACTION_STATE = {
	"hover", "press", "down", "held", "hold", "drag", "grab", "click", "active", "armed", "focus",
}

--- Host input a component has no business naming.
local HOST_INPUT = { "UserInputService", "InputBegan", "InputEnded", "InputChanged" }

--- Components whose machine does not exist yet, and what it would own.
---
--- NOT a list of exceptions to the rule. A name here is a debt with a shape
--- attached, and the shape is what the next extraction is measured against.
local PENDING: { [string]: string } = {
	["ContextMenu.luau"] = "open, closed, which item is focused, and dismissal",
	["WindowTopbar.luau"] = "a drag: grab point, delta, release",
	["ScrollArea.luau"] = "wheel, drag and clamp, shared with Scrollbar and ScrollingFrame",
	["Scrollbar.luau"] = "thumb geometry and track arithmetic",
	["Combobox.luau"] = "open, filter, highlight, commit",
}

type Finding = { signal: string, line: number, text: string }

type Report = {
	file: string,
	machines: { string },
	findings: { Finding },
}

local function isLayer1Require(target: string): boolean
	for _, dir in ipairs(LAYER_1) do
		if string.find(target, dir, 1, true) then
			return true
		end
	end
	return false
end

local function matchesVocabulary(name: string, vocabulary: { string }): boolean
	local lowered = string.lower(name)
	for _, word in ipairs(vocabulary) do
		if string.find(lowered, word, 1, true) then
			return true
		end
	end
	return false
end

--- Layer 1 modules this file requires AND refers to again.
---
--- The second condition is the whole reason this is not a grep. A require whose
--- local is never read is an import that satisfies a counter, which is exactly
--- the shape of gate this one was written to avoid being.
local function machinesUsed(code: string): { string }
	local used: { string } = {}
	for name, target in string.gmatch(code, "local%s+([%w_]+)%s*=%s*require%(\"([^\"]+)\"%)") do
		if not isLayer1Require(target) then
			continue
		end
		local mentions = 0
		for _ in string.gmatch(code, `%f[%w_]{name}%f[^%w_]`) do
			mentions += 1
		end
		if mentions > 1 then
			table.insert(used, (string.gsub(target, "^%.%./", "")))
		end
	end
	table.sort(used)
	return used
end

--- Statements in which this file decides something about an interaction.
local function interactionLogic(code: string): { Finding }
	local findings: { Finding } = {}
	local line = 0
	for text in string.gmatch(code .. "\n", "([^\n]*)\n") do
		line += 1

		local handler = string.match(text, "(On%u[%w_]*)%s*=%s*function")
		if handler then
			table.insert(findings, { signal = `writes \`{handler}\` in place`, line = line, text = text })
		end

		local name, init = string.match(text, "local%s+([%w_]+)%s*=%s*(%a+)")
		if name and (init == "source" or init == "true" or init == "false") and matchesVocabulary(name, INTERACTION_STATE) then
			table.insert(findings, { signal = `holds \`{name}\``, line = line, text = text })
		end

		local router = string.match(text, "PointerRouter%s*%.%s*([%w_]+)%s*%(")
		if router then
			table.insert(findings, { signal = `drives the router itself (\`PointerRouter.{router}\`)`, line = line, text = text })
		end

		for _, input in ipairs(HOST_INPUT) do
			if string.find(text, `%f[%w_]{input}%f[^%w_]`) then
				table.insert(findings, { signal = `names \`{input}\``, line = line, text = text })
				break
			end
		end
	end
	return findings
end

local files = fs.readDir(SUBJECT)
table.sort(files)

local reports: { Report } = {}
for _, file in ipairs(files) do
	local path = SUBJECT .. file
	if not fs.isFile(path) or not string.match(file, "%.luau$") then
		continue
	end
	--- REQUIRE PATHS ARE STRINGS, so the two scans read two versions. Blanking
	--- string literals is what keeps `className == "GuiObject"` out of an
	--- identifier count, and it would also blank every require target.
	local withStrings = SourceScan.blankComments(fs.readFile(path))
	table.insert(reports, {
		file = file,
		machines = machinesUsed(withStrings),
		findings = interactionLogic(SourceScan.blankStrings(withStrings)),
	})
end

local binding = 0
local clean = 0
local waiting = 0
local failures: { string } = {}

print("")
for _, report in ipairs(reports) do
	if #report.machines > 0 then
		binding += 1
	end
	if #report.findings == 0 then
		clean += 1
	end

	local machines = if #report.machines > 0 then table.concat(report.machines, ", ") else "no machine"
	local logic = if #report.findings > 0 then `{#report.findings} own` else "none"
	local pending = PENDING[report.file]
	local mark = if pending then "wait" else "    "
	if pending then
		waiting += 1
	end
	print(`  [{mark}] {report.file}  --  binds: {machines}  --  interaction logic: {logic}`)
	for _, finding in ipairs(report.findings) do
		print(`           line {finding.line}: {finding.signal}`)
	end
	if pending then
		print(`           not extracted yet: {pending}`)
		continue
	end

	if #report.machines == 0 then
		table.insert(failures, `{SUBJECT}{report.file}: names no module under src/core/ or src/controllers/`)
	end
	for _, finding in ipairs(report.findings) do
		table.insert(failures, `{SUBJECT}{report.file}:{finding.line}: {finding.signal}`)
	end
end

print("")
print(`PRIMITIVES: {binding} of {#reports} bind a Layer 1 machine; {clean} implement no interaction logic of their own`)
print(`WAITING ON A MACHINE: {waiting}, each named in PENDING with what its machine would own`)

if #failures > 0 then
	print("")
	for _, failure in ipairs(failures) do
		print(`  {failure}`)
	end
	print(`VERIFY PRIMITIVES BIND MACHINES: FAILED ({#failures} problem(s))`)
	process.exit(1)
else
	print("")
	print(`VERIFY PRIMITIVES BIND MACHINES: PASS ({#reports - waiting} primitive(s) under the rule, {waiting} waiting)`)
end
