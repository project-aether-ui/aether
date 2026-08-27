--!strict
--[[
	verify_autosize_cycles — a child must not size in Scale on an axis its parent
	measures automatically.

	WHY (ms-43 M94)
	Roblox resolves layout one way: a parent's AutomaticSize comes from its
	children's RESOLVED sizes, and a Scale child resolves against its parent. Put
	them together and the definition has no base case — the engine does not
	error, the child contributes nothing, and the parent settles at whatever
	fixed padding it carries.

	The symptom is COLLAPSE, not breakage, which is why it reads as "too small"
	rather than as a bug. es9 reported exactly that, twice, in two widgets:

	  window_topbar  close button width derived from a constraint that never
	                 resolved            -> the button vanished
	  button         content sized `UDim2.new(1, -(padding * 2), 1, 0)` under an
	                 auto-sized parent   -> every button collapsed to its padding

	Both mounts were the first time either ran in an engine. The headless shim's
	`create` returns a plain table, so nothing resolves and nothing collapses —
	the same permissiveness that hid the reactive-scope and class-member defects.
	A static rule is the only thing that sees this before Studio does.

	THE FIX IS ALWAYS ON THE CHILD. Turning off the parent's AutomaticSize gives
	it a size again, but then nothing measures the content and a collapse has
	been swapped for a fixed guess that is wrong at every other content length.
	Insets on a measured axis come from UIPadding on the PARENT, which applies
	after measurement rather than participating in it.

	WHAT IT CANNOT SEE, stated because a gate whose limits are unstated gets
	trusted past them: only children written INLINE in the same create block. A
	child from a slot, a helper, or a prop is invisible. It is a floor, not a
	proof — see docs/ui/explanation/automatic-size-cycles.md for the rule that
	still has to be held in the head.
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

--- Does this Size expression carry a non-zero Scale term on `axis`?
---
--- Conservative on purpose. `UDim2.fromOffset(...)` and `UDim2.new(0, n, 0, m)`
--- are pure offset and safe; `fromScale`, and `UDim2.new(1, …` on the measured
--- axis, are the cycle.
local function hasScaleOn(expr: string, axis: string): boolean
	if string.find(expr, "fromOffset", 1, true) then
		return false
	end
	if string.find(expr, "fromScale", 1, true) then
		return true
	end
	local sx, sy = string.match(expr, "UDim2%.new%(%s*([%d%.]+)%s*,[^,]*,%s*([%d%.]+)%s*,")
	if not sx then
		return false
	end
	local term = if axis == "X" then sx else sy
	return (tonumber(term) or 0) > 0
end

local function checkFile(path: string, body: string)
	local lines: { string } = {}
	for line in string.gmatch(body .. NL, "(.-)" .. NL) do
		table.insert(lines, line)
	end

	for i, raw in ipairs(lines) do
		local line = string.gsub(raw, "%-%-.*$", "")
		if not string.match(line, 'create%s*"[%w_]+"%s*{') then
			continue
		end

		-- Walk the block tracking BRACE DEPTH, and treat a line as belonging to
		-- this block only at depth 1.
		--
		-- Indentation is not a reliable proxy — nested create chains vary — and
		-- dropping the check entirely is worse: an AutomaticSize on some deep
		-- descendant then sets the axis for the whole outer tree and every
		-- Scale-sized element under it is reported. That produced 78 findings
		-- from one block, which is exactly the noise that gets a gate silenced.
		local axes: { string } = {}
		local ownSizes: { { line: number, expr: string } } = {}
		local depth = 0
		local opened = false

		for j = i, #lines do
			local src = string.gsub(lines[j], "%-%-.*$", "")

			-- Read properties BEFORE this line's braces move the depth, so the
			-- opening line's own props count as depth 1.
			local atOwnLevel = opened and depth == 1
			if atOwnLevel or j == i then
				-- The PROPERTY, not the substring. `AutomaticCanvasSize = Enum.
				-- AutomaticSize.Y` contains "AutomaticSize" inside the ENUM name,
				-- and matching that reported every ScrollingFrame in the showcase.
				--
				-- They are different things: AutomaticCanvasSize measures the
				-- CANVAS, not the frame, so a scale-sized ScrollingFrame is exactly
				-- right and there is no cycle. Six false positives came from
				-- conflating them.
				if string.match(src, "[^%w]AutomaticSize%s*=") or string.match(src, "^%s*AutomaticSize%s*=") then
					local auto = string.match(src, "Enum%.AutomaticSize%.(%a+)")
					if auto == "XY" then
						axes = { "X", "Y" }
					elseif auto == "X" or auto == "Y" then
						axes = { auto }
					end
				end
			end
			if atOwnLevel then
				local expr = string.match(src, "^%s*Size%s*=%s*(.+)$")
				-- A CONDITIONAL size is indeterminate here and is skipped.
				--
				-- spektr/button writes both properties as one-line conditionals on
				-- the same flag:
				--
				--   Size = if autoSized then UDim2.new(0, 0, 1, 0) else UDim2.fromScale(1, 1),
				--   AutomaticSize = if autoSized then Enum.AutomaticSize.X else nil,
				--
				-- The scale branch and the measuring branch never coexist, but a
				-- line scanner cannot pair them and reported it. Forcing correct
				-- code to contort for a gate is worse than a stated blind spot, so
				-- this is the blind spot: a conditional Size is not analysed.
				if expr and not string.match(expr, "^if%s") then
					table.insert(ownSizes, { line = j, expr = expr })
				end
			end

			local finished = false
			for char in string.gmatch(src, "[{}]") do
				depth += if char == "{" then 1 else -1
				if depth > 0 then
					opened = true
				elseif opened then
					finished = true
					break
				end
			end
			if finished then
				break
			end
		end

		if #axes == 0 then
			continue
		end
		checked += 1

		-- This block measures. Its OWN Size must not carry a scale term on a
		-- measured axis — that is the element measuring itself.
		for _, entry in ipairs(ownSizes) do
			for _, axis in ipairs(axes) do
				if hasScaleOn(entry.expr, axis) then
					fail(
						`{path}:{entry.line}: sizes in Scale on {axis} while ALSO measuring {axis} `
							.. `automatically (line {i}). The element measures its children and its own `
							.. `size measures its parent — the axis resolves to zero. Inset with `
							.. `UIPadding instead.`
					)
					break
				end
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

print("=== VERIFY: no AutomaticSize cycles ===")
for _, root in ipairs({ "src", "packages", "hosts" }) do
	if fs.isDir(root) then
		walk(root)
	end
end

print("")
if failures > 0 then
	print(`VERIFY AUTOSIZE CYCLES: FAILED ({failures} problem(s))`)
	local process = require("@lune/process")
	process.exit(1)
else
	print(`VERIFY AUTOSIZE CYCLES: PASS ({checked} auto-sized blocks)`)
end
return true
