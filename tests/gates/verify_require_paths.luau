--!strict
--[[
	verify_require_paths — the Roblox branch of every dual-environment require.

	WHY (ms-43 M34)
	Every module in these packages resolves its dependencies twice:

	    local Deps = if isScriptInstance
	        then require((script :: any).Parent.Deps)   -- Roblox
	        else require("./Deps")                      -- headless

	The headless suites only ever execute the SECOND branch. The first is
	unreachable outside Studio, so no amount of headless testing can tell you it
	is wrong — and being wrong is easy, because the correct number of `.Parent`
	hops depends on where the file sits:

	    src/init.luau      is the PACKAGE module; siblings are its CHILDREN
	                       -> script.Deps          (NOT script.Parent.Deps)
	    src/Thing.luau     is a child of that module; siblings share its parent
	                       -> script.Parent.Deps
	    src/sub/Thing.luau -> script.Parent.Deps

	and `roblox_packages` sits beside `src`, so it is one hop further out again.

	I got this wrong writing spektr/sheen: its first init.luau said
	`script.Parent.Deps`, which from the package module points at the package
	FOLDER rather than at src. Every headless test passed. es9 hit
	"Deps is not a valid member of Folder ...spektr+sheen" on the first playtest.

	This gate is static because it has to be: it is checking the branch the test
	runner cannot enter.
]]

local fs = require("@lune/fs")

local failures = 0
local function fail(msg: string)
	failures += 1
	print("FAIL  " .. msg)
end

local NL = string.char(10)

local PACKAGE_SRC_ROOTS = {
	"src",
	"src/Icon/src",
	"packages/virtual/src",
	"hosts/zune/src",
}

--- Files directly in `dir`, by module name.
local function siblingsOf(dir: string): { [string]: true }
	local out: { [string]: true } = {}
	for _, entry in ipairs(fs.readDir(dir)) do
		if string.sub(entry, -5) == ".luau" and not string.find(entry, ".test.", 1, true) then
			out[string.sub(entry, 1, -6)] = true
		end
	end
	return out
end

local function eachLine(body: string): () -> string?
	return string.gmatch(body, "[^" .. NL .. "]+") :: any
end

local checked = 0

local function checkDir(dir: string)
	local siblings = siblingsOf(dir)

	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) and entry ~= "roblox_packages" and entry ~= ".pesde" then
			checkDir(path)
			continue
		end
		if string.sub(entry, -5) ~= ".luau" or string.find(entry, ".test.", 1, true) then
			continue
		end

		local isInit = entry == "init.luau"
		local body = fs.readFile(path)
		checked += 1

		for line in eachLine(body) do
			-- Comments describe these patterns; only code is judged.
			if string.find(line, "^%s*%-%-") then
				continue
			end

			-- 1. Sibling module resolution, and how many levels it walks.
			--
			-- The whole chain after `script...)` is extracted and its hops counted,
			-- rather than matched in one pattern: Lua cannot repeat a capture group,
			-- so `(%s*%.Parent)+` never matches at all — and the version before that
			-- stopped at the FIRST hop, capturing "Parent" as the module name and
			-- passing `script.Parent.Parent.Deps` silently.
			--
			-- Found while probing the pre-commit wiring (M63). The mutation I
			-- reached for first was one this gate did not cover, which is a good
			-- argument for probing a gate with a defect you have not already fixed.
			local chain = string.match(line, "script[^)]-%)([%.%w_]+)")
			if chain then
				local hops = 0
				for _ in string.gmatch(chain, "%.Parent") do
					hops += 1
				end
				local name = string.match(chain, "%.([%w_]+)$")
				if name and siblings[name] then
					-- init.luau IS the package module, so a sibling is its CHILD.
					-- A child module reaches a sibling through exactly one .Parent.
					local expected = if isInit then 0 else 1
					if hops ~= expected then
						local shouldBe = if isInit then `script.{name}` else `script.Parent.{name}`
						fail(`{path}: reaches sibling '{name}' through {hops} .Parent hop(s); `
							.. `from {if isInit then "init.luau (the package MODULE)" else "a child module"} `
							.. `it should be {shouldBe}`)
					end
				end
			end

			-- 2. roblox_packages depth. It sits beside `src`, so: one hop from
			--    init.luau, two from src/X.luau, three from src/sub/X.luau.
			--
			-- ms-51 M19: measured from the package's OWN `src`, which means the LAST
			-- one on the path rather than the first. Nested workspace members —
			-- Aether/src/Icon, CoreInput/src/Mouse, StudioInterfaceSuite/src/StudioUI
			-- — have two `/src/` segments, and a non-greedy strip measured from the
			-- OUTER package's, demanding two hops more than the file needs.
			--
			-- Latent until now: every nested member's entry point was `init.luau`,
			-- which takes the `isInit` branch and never reached this arithmetic. The
			-- moment two of them became named modules, the rule started failing
			-- correct code.
			if string.find(line, "roblox_packages", 1, true) then
				local hops = 0
				for _ in string.gmatch(line, "%.Parent") do
					hops += 1
				end
				local depthBelowSrc = 0
				--- ms-graduation: the pattern needs the `^src/` alternative because
				--- `^.*/src/` requires a separator BEFORE `src`, and in this repo the
				--- framework's own source IS `src/` at the root. Without it the strip
				--- silently failed, `rest` kept its `src/` prefix, and the extra `/`
				--- was counted as a directory level — demanding three hops from
				--- `src/Deps.luau` where the correct answer is two. It read as two
				--- source defects and was one wrong pattern.
				local rest = string.gsub(path, "^.*/src/", "")
				rest = string.gsub(rest, "^src/", "")
				for _ in string.gmatch(rest, "/") do
					depthBelowSrc += 1
				end
				local expected = if isInit then 1 else 2 + depthBelowSrc
				if hops > 0 and hops ~= expected then
					fail(`{path}: roblox_packages needs {expected} .Parent hop(s) from here, found {hops}`)
				end
			end
		end
	end
end

print("=== VERIFY: Roblox require paths (the branch headless tests cannot reach) ===")

for _, root in ipairs(PACKAGE_SRC_ROOTS) do
	if fs.isDir(root) then
		checkDir(root)
	end
end

--- ms-51: THE DEPS CONTRACT, in the branch headless tests cannot reach.
---
--- Each Deps.luau states "every field below is NON-NIL, always. Consumers never
--- guard." The Roblox half of that promise is unreachable from lune, exactly like
--- the require paths above — and it broke the same way, silently.
---
--- What happened: a regex tidying unrelated lines out of Aether's Deps matched
--- `	-- .*?` under DOTALL and swallowed the `vide = require(packages.vide)`
--- line with them. Sixty-two suites and six gates stayed green, because not one
--- of them executes that branch. It surfaced as "Aether.Host.Roblox.new(vide)
--- requires the vide module" on the first Studio launch, taking down every
--- consumer of Aether with it.
---
--- `vide` is the right thing to check: it is the one field every Deps must
--- resolve, it is resolved UNGUARDED by contract (a missing hard dependency is a
--- build error and must surface), and it is what the whole package tree is built
--- on.
do
	local depsFiles: { string } = {}
	for _, root in ipairs(PACKAGE_SRC_ROOTS) do
		if fs.isDir(root) then
			local candidate = root .. "/Deps.luau"
			if fs.isFile(candidate) then
				table.insert(depsFiles, candidate)
			end
		end
	end

	for _, path in ipairs(depsFiles) do
		local src = fs.readFile(path)
		--- Only packages that HAVE a Roblox branch; a headless-only module has
		--- nothing to promise here.
		if string.find(src, "isScriptInstance", 1, true) then
			local assignsVide = string.find(src, "vide = require(packages.vide)", 1, true) ~= nil
				or string.find(src, "vide = require((script", 1, true) ~= nil
				or string.find(src, "roblox_packages.vide", 1, true) ~= nil
			if not assignsVide then
				fail(`{path}: has a Roblox branch but never assigns vide — the Deps contract says every field is non-nil, and nothing headless can catch this`)
			end
		end
	end
end

print("")
if failures > 0 then
	print(`VERIFY REQUIRE PATHS: FAILED ({failures} problem(s) across {checked} modules)`)
	local process = require("@lune/process")
	process.exit(1)
else
	print(`VERIFY REQUIRE PATHS: PASS ({checked} modules)`)
end
return true
