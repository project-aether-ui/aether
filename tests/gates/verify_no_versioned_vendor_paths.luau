--!strict
--[[
	verify_no_versioned_vendor_paths — no source may require a vendored package BY VERSION.

	WHY (ms-44)
	Nine suites contained requires like:

	    require("../../roblox_packages/.pesde/spektr+prism_physics/0.1.0-alpha.1/prism_physics/src/AtomCache")

	That path embeds a version number, so it breaks on EVERY version bump. Worse, it breaks
	invisibly: the old `.pesde/…/0.1.0-alpha.1/` directory lingers on any machine that has
	installed before, so the suites keep passing locally while failing on any clean install.
	The alpha.4 lockstep bump turned six suites red in CI and green here, simultaneously.

	pesde already solves this. `pesde install` generates an UNVERSIONED shim per dependency —
	`roblox_packages/prism_physics.luau` — that requires the versioned path on your behalf and
	is regenerated every install. Requiring through the shim is always correct; reaching past
	it into `.pesde/` is what goes stale.

	WHAT THE FIX COSTS, recorded because it is not free: reaching a package's SUBMODULE by
	file path bypasses its `init`, and going through the shim does not. Three submodules had
	to be added to `prism_physics`'s public surface (AtomCache, WorldStore, RayCast), and the
	StaticGeometry suite had to install the same Platform stubs its sibling already did,
	because loading the package root reaches for RunService. Both are improvements — the
	dependency is now declared rather than smuggled — but a future migration should expect
	them rather than be surprised.

	COMMENTS ARE STRIPPED before matching. The `.pesde` path appears in prose in this file
	and in the very comments explaining the fix, and a gate that counts documentation as a
	violation trains people to stop documenting. Same lesson as verify_test_inventory, where
	a path named in a comment was miscounted as reachability.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local failures = 0
local function fail(msg: string)
	failures += 1
	print("FAIL  " .. msg)
end

local stripComments = require("./source_scan").stripComments

--- Tracked .luau only. Vendored trees legitimately contain versioned paths — the generated
--- shims ARE versioned paths, and rewriting them is pesde's job, not ours.
local files: { string } = {}
do
	local r = process.exec("git", { "ls-files", "*.luau" })
	if not r.ok then
		error("cannot list tracked files — is this a git repository?", 0)
	end
	for line in string.gmatch(r.stdout, "[^\r\n]+") do
		table.insert(files, line)
	end
end

local scanned = 0
for _, path in ipairs(files) do
	if fs.isFile(path) then
		scanned += 1
		local body = stripComments(fs.readFile(path))
		local lineNo = 0
		for line in string.gmatch(body, "[^\n]*") do
			lineNo += 1
			-- `.pesde/<package>/<version>/` — the version segment is what dates it.
			if string.match(line, "%.pesde/[^/\"]+/%d+%.%d+%.%d+") then
				fail(
					`{path}:{lineNo}: requires a vendored package BY VERSION. That path dies on the `
						.. `next version bump and stays green locally off a stale directory. Require the `
						.. `unversioned shim instead — roblox_packages/<package> — and reach submodules `
						.. `through the package's exports.`
				)
			end
		end
	end
end

print("")
if failures > 0 then
	print(`VERIFY NO VERSIONED VENDOR PATHS: FAILED ({failures} problem(s))`)
	process.exit(1)
else
	print(`VERIFY NO VERSIONED VENDOR PATHS: PASS ({scanned} tracked files)`)
end
return true
