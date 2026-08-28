--!strict
--[[
	verify_cycles — no require cycles among a package's own source modules.

	WHY (ms-43 M31)
	Lune does not error on a circular require. It DEADLOCKS: the require blocks
	forever, at zero CPU, with no message. Every suite that transitively touches
	either module hangs, and the runner reports a timeout rather than a cause.

	I introduced one by adding `NavigationState -> TransitionOrchestrator` without
	noticing that TransitionOrchestrator already required NavigationState — its
	require sits on a continuation line, so the obvious grep for `^local .*require`
	misses it. The failure looked like a flaky environment for some time, and the
	only thing that pointed at the truth was the process using no CPU while it
	hung, which is what a lock looks like and not what a loop looks like.

	In Roblox the same cycle does not deadlock — requires resolve differently —
	so this is exactly the class of defect that passes a playtest and stops the
	headless suites dead. Static, cheap, and it runs over every package.
]]

local fs = require("@lune/fs")

local failures = 0
local function check(ok: boolean, label: string)
	if ok then
		print("ok    " .. label)
	else
		failures += 1
		print("FAIL  " .. label)
	end
end

local NL = string.char(10)

--- Every `.luau` under a package's src/, excluding tests and vendored trees.
local function collectModules(root: string, out: { string })
	for _, entry in ipairs(fs.readDir(root)) do
		local path = root .. "/" .. entry
		if entry == "roblox_packages" or entry == ".pesde" then
			continue
		end
		if fs.isDir(path) then
			collectModules(path, out)
		elseif string.sub(entry, -5) == ".luau" and not string.find(entry, ".test.", 1, true) then
			table.insert(out, path)
		end
	end
end

--- Sibling modules this file requires AT LOAD TIME, by module name.
---
--- Load time is the whole point. A require deferred inside a function is the
--- standard, correct way to break a cycle — InputScope does exactly that for
--- PointerRouter, with a comment naming this deadlock — and flagging it would
--- make the gate punish the fix for the bug it is looking for.
---
--- So: a require counts only if its statement begins in column 0. Continuation
--- lines of a top-level statement count too, because the codebase spells the
--- environment split across three lines:
---     local NavigationState = if isScriptInstance
---         then require((script :: any).Parent.NavigationState)
---         else require("./NavigationState")
local function loadTimeRequiresOf(body: string): { [string]: true }
	local found: { [string]: true } = {}
	local topLevel = false

	for line in string.gmatch(body, "[^" .. NL .. "]*") do
		local indented = string.find(line, "^%s") ~= nil
		if line ~= "" and not indented then
			topLevel = true
		elseif indented then
			-- Only `then`/`else`/`or`/`and` continue the statement above.
			if not string.find(line, "^%s*[toa][hrn]") then
				topLevel = false
			end
		end

		if topLevel then
			for name in string.gmatch(line, 'require%("%./([%w_]+)"%)') do
				found[name] = true
			end
			for name in string.gmatch(line, "Parent%.([%w_]+)%s*%)") do
				found[name] = true
			end
		end
	end

	return found
end

local function moduleName(path: string): string
	local name = string.match(path, "([^/]+)%.luau$") or path
	return name
end

local PACKAGE_ROOTS = {
	"src",
	"src/Icon/src",
	"packages/virtual/src",
}

print("=== VERIFY: require cycles ===")

for _, root in ipairs(PACKAGE_ROOTS) do
	if not fs.isDir(root) then
		continue
	end

	local files: { string } = {}
	collectModules(root, files)

	-- name -> set of names, for files that sit directly in this package.
	local graph: { [string]: { [string]: true } } = {}
	local present: { [string]: true } = {}
	for _, path in ipairs(files) do
		present[moduleName(path)] = true
	end
	for _, path in ipairs(files) do
		local edges: { [string]: true } = {}
		for name in pairs(loadTimeRequiresOf(fs.readFile(path))) do
			if present[name] and name ~= moduleName(path) then
				edges[name] = true
			end
		end
		graph[moduleName(path)] = edges
	end

	-- Depth-first, reporting the actual cycle path rather than just "a cycle".
	local state: { [string]: string } = {}
	local stack: { string } = {}
	local cycles: { string } = {}

	local function visit(node: string)
		state[node] = "open"
		table.insert(stack, node)
		for next_ in pairs(graph[node] or {}) do
			if state[next_] == "open" then
				local from = 1
				for i, n in ipairs(stack) do
					if n == next_ then
						from = i
						break
					end
				end
				local path = table.concat(stack, " -> ", from) .. " -> " .. next_
				table.insert(cycles, path)
			elseif state[next_] ~= "done" then
				visit(next_)
			end
		end
		table.remove(stack)
		state[node] = "done"
	end

	for name in pairs(graph) do
		if state[name] ~= "done" then
			visit(name)
		end
	end

	check(#cycles == 0, `{root}: no require cycles ({#cycles} found)`)
	for _, path in ipairs(cycles) do
		print("        " .. path)
	end
end

-- ═══ PACKAGE-LEVEL CYCLES (ms-43 M35) ═══
--
-- The module-level pass above would not have caught the one that actually
-- blocked work: CoreUI.Panel embeds a scrollbar while the scrollbar needed
-- CoreUI for hover — a cycle BETWEEN packages, invisible to a scan that stops at
-- the package boundary. It was caught by reading the code, which is not a gate.
--
-- Read from the manifests, since that is where a dependency is actually declared.
print("")
do
	local graph: { [string]: { [string]: true } } = {}

	--- The workspace members, ENUMERATED rather than discovered. The monorepo read
	--- `fs.readDir("pkgs")` because its packages sat one level under a single root;
	--- here they sit at four different depths, and a walk deep enough to find them
	--- would also find every vendored manifest under a generated packages tree.
	for _, manifest in ipairs({
		"pesde.toml",
		"src/Icon/pesde.toml",
		"packages/virtual/pesde.toml",
		"hosts/zune/pesde.toml",
	}) do
		if not fs.isFile(manifest) then
			continue
		end
		local body = fs.readFile(manifest)
		local name = string.match(body, 'name%s*=%s*"([^"]+)"')
		if not name then
			continue
		end
		local edges: { [string]: true } = {}
		for dep in string.gmatch(body, 'workspace%s*=%s*"([^"]+)"') do
			edges[dep] = true
		end
		graph[name] = edges
	end

	local state: { [string]: string } = {}
	local stack: { string } = {}
	local cycles: { string } = {}

	local function visit(node: string)
		state[node] = "open"
		table.insert(stack, node)
		for next_ in pairs(graph[node] or {}) do
			if state[next_] == "open" then
				local from = 1
				for i, n in ipairs(stack) do
					if n == next_ then
						from = i
						break
					end
				end
				table.insert(cycles, table.concat(stack, " -> ", from) .. " -> " .. next_)
			elseif graph[next_] and state[next_] ~= "done" then
				visit(next_)
			end
		end
		table.remove(stack)
		state[node] = "done"
	end

	for name in pairs(graph) do
		if state[name] ~= "done" then
			visit(name)
		end
	end

	check(#cycles == 0, `package manifests: no dependency cycles ({#cycles} found)`)
	for _, path in ipairs(cycles) do
		print("        " .. path)
	end
end

print("")
if failures > 0 then
	print(`VERIFY CYCLES: FAILED ({failures} package(s))`)
	process = require("@lune/process")
	process.exit(1)
else
	print("VERIFY CYCLES: PASS")
end
return true
