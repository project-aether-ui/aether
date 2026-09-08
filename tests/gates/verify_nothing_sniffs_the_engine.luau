--!strict
--[[
	verify_nothing_sniffs_the_engine -- one place asks what the environment is.

	WHY
	`src/host/Host.luau` states the rule this gate enforces:

	    SELECTION IS BY CAPABILITY, never by configuration. There is no flag to
	    force the wrong one, because every bug in this area has been a path that
	    silently took the wrong branch.

	Measured 2026-09-08, the framework did not follow it: 23 modules asked
	`typeof(game) == "Instance"` on their own, including all ten primitives, and
	six reached `game:GetService` from inside a component. Every one of those is a
	module deciding for itself what it is running on, instead of taking the answer
	from the layer whose whole job is knowing.

	THE SHAPE THIS IS COPIED FROM. `@zag-js/dialog` cannot sniff a browser: it
	depends on the machine core and nothing else, and reaches the document only
	through what its binding hands it. The impossibility is structural rather than
	disciplined -- there is no `navigator` in scope to write the check against.
	This gate is the closest a single-package framework gets to that.

	WHAT IT DOES NOT ASK FOR. Not an `isRoblox()` helper. Wrapping the check in a
	utility is the same coupling with a nicer spelling, and it would pass a gate
	that only looked for the literal. What a component wants is never "am I on
	Roblox" -- it is a service, a measurement, or a vocabulary type, and those
	arrive from the host.

	A NUMBER, NOT ONLY A VERDICT. While the count is above the allowance this
	prints how far there is to go, so the milestone can be measured rather than
	asserted. Lower the allowance whenever the number drops; never raise it.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local stripComments = require("./source_scan").stripComments

--- THE FRAMEWORK IS THE SUBJECT, not the repository.
---
--- `tests/` builds environments on purpose, `conformance/roblox/` is an
--- in-engine harness whose entire job is running inside the engine, and
--- `stories/` and `examples/` are consumers. A gate that failed those would be
--- asking the wrong question and would be silenced rather than obeyed.
local SUBJECT = "src/"

--- The layer allowed to know. A host binds to a target; that is its job.
local ALLOWED_PREFIX = "src/host/"

--- Vendored trees are not ours to fix.
local function isVendored(path: string): boolean
	return string.find(path, "roblox_packages", 1, true) ~= nil
		or string.find(path, ".pesde", 1, true) ~= nil
end

--- WHAT REMAINS AFTER STRINGS GO.
---
--- `className == "GuiObject"` is a comparison against data and says nothing
--- about the environment; `typeof(game)` is a question about it. Stripping
--- string literals is what keeps the first out of the count. Require paths live
--- in strings too, and this gate does not read them.
local function stripStrings(src: string): string
	local out = string.gsub(src, "%[%[.-%]%]", '""')
	out = string.gsub(out, '"[^"\n]*"', '""')
	out = string.gsub(out, "'[^'\n]*'", "''")
	return out
end

local result = process.exec("git", { "ls-files", "*.luau" })
if not result.ok then
	error("cannot list tracked files -- is this a git repository?", 0)
end

local offenders: { { path: string, line: number, text: string } } = {}
local scanned = 0

for path in string.gmatch(result.stdout, "[^\r\n]+") do
	if not fs.isFile(path) or isVendored(path) then
		continue
	end
	if string.sub(path, 1, #SUBJECT) ~= SUBJECT then
		continue
	end
	if string.sub(path, 1, #ALLOWED_PREFIX) == ALLOWED_PREFIX then
		continue
	end

	scanned += 1
	local body = stripStrings(stripComments(fs.readFile(path)))
	local lineNo = 0
	for line in string.gmatch(body, "[^\n]*") do
		lineNo += 1
		--- `game` as a WORD. `gameplay` and `minigame` are not this.
		if string.find(line, "%f[%w_]game%f[^%w_]") then
			table.insert(offenders, { path = path, line = lineNo, text = line })
		end
	end
end

--- HOW MANY MODULES MAY STILL ASK, and it only ever goes down.
---
--- 22 the day this gate was written, counting any bare `game` rather than one
--- phrase, which is why it is not the 23 the milestone note quotes. It is not a target; it is a ratchet, so
--- that the number cannot quietly climb back while milestone 7 is in progress.
local ALLOWANCE = 0

local modules: { [string]: boolean } = {}
local distinct = 0
for _, o in ipairs(offenders) do
	if not modules[o.path] then
		modules[o.path] = true
		distinct += 1
	end
end

print("")
print(`ENGINE SNIFF: {distinct} of {scanned} modules under {SUBJECT} name \`game\` outside {ALLOWED_PREFIX}`)

if distinct > ALLOWANCE then
	for _, o in ipairs(offenders) do
		print(`  {o.path}:{o.line}: {string.gsub(o.text, "^%s+", "")}`)
	end
	print("")
	print(`VERIFY NOTHING SNIFFS THE ENGINE: FAILED ({distinct} module(s), at most {ALLOWANCE} allowed)`)
	print("Selection is by capability. Take the answer from the host rather than asking the environment.")
	process.exit(1)
else
	local left = if distinct == 0 then "none left" else `{distinct} still to move`
	print(`VERIFY NOTHING SNIFFS THE ENGINE: PASS ({left}, allowance {ALLOWANCE})`)
end
