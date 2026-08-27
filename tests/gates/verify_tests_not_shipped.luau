--!strict
--[[
	verify_tests_not_shipped — a test file must never reach a player's DataModel.

	WHY (ms-44 M4 — the defect that started this milestone)
	32 `*.test.luau` files lived in `pkgs/ui/*/src/`, and every UI manifest declares
	`includes = ["src/**"]` / `build_files = ["src"]`. pesde therefore carried them into
	`examples/*/roblox_packages/`, and each demo's `dev.project.json` mounts
	`roblox_packages` into ReplicatedStorage — so the tests were real ModuleScripts in the
	shipped place. Verified on disk before the move: `spektr+scrollbar/.../src/` contained
	`Scrollbar.test.luau`, `ItemIndex.test.luau` and `VirtualList.test.luau`.

	The fix was to move them to `<pkg>/tests/`, which `src/**` cannot match. This gate is
	what stops them coming back, because the next person to add a test next to its source
	will not know any of the above.

	THREE CHECKS, because the defect can return three ways:
	  1. a test file inside a package's `src/` — the original shape
	  2. a test file inside an INSTALLED package tree — the observable consequence, and the
	     only check that sees a manifest whose include patterns are wrong in a way this
	     gate did not anticipate
	  3. a manifest that names a tests directory in `includes`/`build_files` — the shape
	     that would ship them even from the right location

	WHAT IT DOES NOT CATCH, stated so the gate is not trusted past its evidence: it reads
	the working tree. A published package version already in the registry with tests baked
	in is beyond its reach, and so is a place file built before the move.
]]

local fs = require("@lune/fs")

local failures = 0
local function fail(msg: string)
	failures += 1
	print("FAIL  " .. msg)
end

local SKIP: { [string]: boolean } = {
	[".pesde"] = true,
	luau_packages = true,
	lune_packages = true,
	[".git"] = true,
}

local function walk(dir: string, out: { string }, skipVendored: boolean)
	if not fs.isDir(dir) then
		return
	end
	for _, name in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			if not (SKIP[name] or (skipVendored and name == "roblox_packages")) then
				walk(path, out, skipVendored)
			end
		elseif string.match(name, "%.test%.luau$") or string.match(name, "%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

-- 1 ── no test file inside a package's src/ -----------------------------------
do
	local found: { string } = {}
	for _, root in ipairs({ "src", "packages", "hosts" }) do
		walk(root, found, true)
	end
	for _, p in ipairs(found) do
		if string.find(p, "/src/", 1, true) then
			fail(
				`{p}: a test file inside a package's src/. Every manifest here declares `
					.. `includes = ["src/**"], so pesde SHIPS this into every consumer's DataModel. `
					.. `Move it to the package's tests/ directory.`
			)
		end
	end
end

-- 2 ── no test file in an installed tree --------------------------------------
-- The consequence check. pesde links workspace dependencies rather than copying, so this
-- reflects the working tree immediately — which is exactly why it is worth asserting: it
-- catches an include pattern that is wrong in a way check 1 and check 3 did not predict.
do
	local roots: { string } = {}
	for _, base in ipairs({ "examples", "sandbox" }) do
		if fs.isDir(base) then
			for _, name in ipairs(fs.readDir(base)) do
				local rp = `{base}/{name}/roblox_packages`
				if fs.isDir(rp) then
					table.insert(roots, rp)
				end
			end
		end
	end
	for _, root in ipairs(roots) do
		local found: { string } = {}
		walk(root, found, false)
		for _, p in ipairs(found) do
			fail(`{p}: a test file inside an INSTALLED package — it will mount into the place`)
		end
	end
end

-- 3 ── no manifest sweeps a tests directory -----------------------------------
do
	local manifests: { string } = {}
	local function findManifests(dir: string)
		if not fs.isDir(dir) then
			return
		end
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				if not (SKIP[name] or name == "roblox_packages") then
					findManifests(path)
				end
			elseif name == "pesde.toml" then
				table.insert(manifests, path)
			end
		end
	end
	for _, root in ipairs({ ".", "src", "packages", "hosts" }) do
		findManifests(root)
	end

	for _, m in ipairs(manifests) do
		local body = fs.readFile(m)
		for _, field in ipairs({ "includes", "build_files" }) do
			local list = string.match(body, field .. '%s*=%s*%[(.-)%]')
			if list then
				for entry in string.gmatch(list, '"([^"]+)"') do
					-- `tests` named directly, or a glob broad enough to swallow it.
					if string.match(entry, "^tests") or entry == "**" or entry == "*" then
						fail(
							`{m}: {field} contains "{entry}", which ships the package's tests. `
								.. `List src/ explicitly instead.`
						)
					end
				end
			end
		end
	end
end

print("")
if failures > 0 then
	print(`VERIFY TESTS NOT SHIPPED: FAILED ({failures} problem(s))`)
	local process = require("@lune/process")
	process.exit(1)
else
	print("VERIFY TESTS NOT SHIPPED: PASS (no test file in any src/, installed tree, or include pattern)")
end
return true
