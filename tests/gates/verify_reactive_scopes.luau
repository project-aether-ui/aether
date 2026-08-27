--!strict
--[[
	verify_reactive_scopes — no `create` inside an `effect` body.

	WHY (ms-43 M81)
	vide refuses to open a reactive scope inside another one:

	    effect error: cannot create a new reactive scope inside another
	    reactive scope

	`create` opens a scope, so building an Instance inside an effect throws at
	MOUNT TIME. es9 hit it on every Settings and Shop menu the moment M80 set
	Presentation = "Inset", because M79's inset built its UIPadding inside an
	effect.

	THE HEADLESS SUITE CANNOT SEE THIS, AND NEVER WILL. The vide shim's `effect`
	just calls the function and its `create` returns a table — neither models a
	scope, so the stand-in accepts what the engine rejects. Same shape as the
	property-name gate: a stub that accepts everything proves nothing about the
	engine, and the only defence is a static rule.

	THE CORRECT SHAPE, for anyone this fires on: build the Instance at COMPONENT
	scope and let the effect do only the reactive part — parenting it, or setting
	a property. Properties can be reactive getters, so an Instance almost never
	needs to be built inside an effect in the first place.

	Conservative: it looks for `create` at the start of an expression inside an
	effect body, and skips `cleanup` bodies, which are not reactive scopes.
]]

local fs = require("@lune/fs")

local failures = 0
local function fail(msg: string)
	failures += 1
	print("FAIL  " .. msg)
end

local NL = string.char(10)
local SKIP: { [string]: boolean } = {
	roblox_packages = true,
	[".pesde"] = true,
	[".artifacts"] = true,
	lune_packages = true,
}

local checked = 0

local function indentOf(line: string): number
	return #(string.match(line, "^[\t ]*") or "")
end

local function checkFile(path: string, body: string)
	local lines: { string } = {}
	for line in string.gmatch(body .. NL, "(.-)" .. NL) do
		table.insert(lines, line)
	end

	for i, raw in ipairs(lines) do
		local line = string.gsub(raw, "%-%-.*$", "")
		-- `effect(function()` — the only form used in this repo.
		if not string.match(line, "[%w_%.]*effect%s*%(%s*function%s*%(") then
			continue
		end
		checked += 1
		local openIndent = indentOf(raw)

		for j = i + 1, #lines do
			local src = string.gsub(lines[j], "%-%-.*$", "")
			-- The effect closes at `end)` back at its own indentation.
			if string.match(src, "^%s*end%)") and indentOf(lines[j]) <= openIndent then
				break
			end
			-- `local x = create "Frame" {` / `create "UIPadding" {` / `create(...)`
			if string.match(src, "[=%s%(,]create%s*[\"'{(]") or string.match(src, "^%s*create%s*[\"'{(]") then
				fail(
					`{path}:{j}: 'create' inside an effect body opened at line {i} `
						.. `— vide throws "cannot create a new reactive scope inside another reactive scope" at mount`
				)
				break
			end
		end
	end
end

local function walk(dir: string)
	for _, entry in ipairs(fs.readDir(dir)) do
		if SKIP[entry] then
			continue
		end
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			walk(path)
		elseif string.sub(entry, -5) == ".luau" and not string.find(entry, ".test.", 1, true) then
			checkFile(path, fs.readFile(path))
		end
	end
end

print("=== VERIFY: no reactive scope created inside an effect ===")
for _, root in ipairs({ "src", "packages", "hosts" }) do
	if fs.isDir(root) then
		walk(root)
	end
end

print("")
if failures > 0 then
	print(`VERIFY REACTIVE SCOPES: FAILED ({failures} problem(s))`)
	local process = require("@lune/process")
	process.exit(1)
else
	print(`VERIFY REACTIVE SCOPES: PASS ({checked} effect bodies)`)
end
return true
