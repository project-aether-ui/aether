--!strict
--[[
	verify_framework_boundaries -- Aether is Luau, and consumes a DataModel it
	does not implement.

	WHY (ADR-004, in Dew's milestone records)
	Aether is a headless UI framework that runs on any host adhering to the
	DataModel Standard. Roblox is one such host and Dew is another. The framework
	therefore owns NO rendering, NO rasteriser, NO window, NO VM hosting and NO
	DataModel of its own -- all of that belongs to whichever host it is running
	inside.

	That was decided and then read off the directory layout instead, because this
	repository still contains a three-crate Rust workspace. Measured: `pesde.toml`
	ships `src/**`, so none of that Rust reaches a Luau consumer, and its only
	dependents are Dew and aether-cli -- both hosts, one of them retiring. They are
	Dew's rendering stack living here, and "add an image node to the display list"
	looked like changing a public framework contract when it is Dew editing its own
	renderer.

	A BOUNDARY WITH NOTHING CHECKING IT IS A BOUNDARY NOBODY FOLLOWS, and this
	repository has found that class five times in one milestone. So the rule is a
	gate.

	THE ALLOWLISTS ARE THE MIGRATION, not exceptions. A NEW violation fails on the
	commit that introduces it; an existing one is named below and has to be deleted
	from the list to be resolved. Emptying every list here is what finishing ADR-004
	looks like from inside this repository.

	Chosen over a permanently red gate deliberately: a gate expected to fail is a
	gate people stop reading, which is the argument `all_gates.luau` already makes
	about `M.BLOCKED`.
]]

local fs = require("@lune/fs")

local failures = 0
local function fail(msg: string)
	failures += 1
	print("FAIL  " .. msg)
end

--- Rust that has not moved to Dew yet. ADR-004 consequence one.
---
--- These are the whole Cargo workspace. `hosts/runtime` splits on the way out:
--- the painter, rasteriser, window and VM hosting become Dew's, while
--- `session.rs`, `driver.rs` and `frame.rs`'s decoding half retire with
--- `Headless.luau` -- they exist to consume what `Live.luau` emits, and
--- Aether-on-Dew will build DataModel instances instead, exactly as it does on
--- Roblox.
local RUST_NOT_MOVED_YET = {
	"Cargo.toml",
	"Cargo.lock",
	"hosts",
}

--- Files implementing a DataModel rather than consuming one.
---
--- CALLING `Instance.new` IS CORRECT AND STAYS. Aether is a consumer of whatever
--- DataModel its host provides, so `Host.luau` and `TextInputManager.luau` calling
--- it are the framework working as intended. What is forbidden is IMPLEMENTING
--- one, and the marker for that is mock-instance machinery.
---
--- `Headless.luau` is 1198 lines against `Roblox.luau`'s 390 and implements
--- `Instance.new`, `AbsolutePosition`, `AbsoluteSize`, property-changed firing and
--- geometry resolution. ADR-002 moves it to `OSS/luau-datamodel/` as a jsdom for
--- the standard: archived rather than deleted, moved rather than copied, and
--- Aether does not depend on it afterwards.
local DATAMODEL_NOT_MOVED_YET = {
	"src/host/Headless.luau",
}

--- Anything under here is vendored or generated and is nobody's business.
local NOT_OURS = { "roblox_packages", "luau_packages", ".pesde", "target", "node_modules", ".git" }

local function walk(dir: string, out: { string })
	if not fs.isDir(dir) then
		return out
	end
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = `{dir}/{entry}`
		if table.find(NOT_OURS, entry) then
			continue
		end
		if fs.isDir(path) then
			walk(path, out)
		else
			table.insert(out, path)
		end
	end
	return out
end

-- 1 - THE PACKAGE IS LUAU ----------------------------------------------------
--
-- `includes` is the whole product. If Rust ever appears in it, a Roblox author
-- installing this package starts downloading a rasteriser they cannot run.

local manifest = if fs.isFile("pesde.toml") then fs.readFile("pesde.toml") else ""
local includes = string.match(manifest, "includes%s*=%s*(%b[])") or ""
for _, forbidden in ipairs({ "Cargo", "hosts", "%.rs" }) do
	if string.find(includes, forbidden) then
		fail(
			`pesde.toml ships something matching "{forbidden}". Aether ships Luau; a host's `
				.. `Rust is that host's to ship.`
		)
	end
end

-- 2 - THE SHIPPED SOURCE IS LUAU, AND KNOWS OF NO HOST CRATE -----------------

for _, path in ipairs(walk("src", {})) do
	if string.match(path, "%.rs$") then
		fail(`{path}: Rust under src/. The shipped framework is Luau only.`)
	end
end

--- The framework must not name the crates that host it. It runs on Roblox with
--- no Rust at all, so a reference here would be a branch that cannot exist on
--- half its targets.
local HOST_CRATES = { "aether_runtime", "aether_raster", "aether_window" }
for _, path in ipairs(walk("src", {})) do
	if not string.match(path, "%.luau?$") then
		continue
	end
	local body = fs.readFile(path)
	for _, crate in ipairs(HOST_CRATES) do
		if string.find(body, crate, 1, true) then
			fail(
				`{path} names the host crate {crate}. The framework does not know what is `
					.. `hosting it; that is what Host.detect() is for.`
			)
		end
	end
end

-- 3 - NO LIBRARY DEPENDENCY ON A HOST ----------------------------------------
--
-- ADR-002 lets Aether take Dew as a TOOL, for running suites and headless
-- renders. A tool is invoked; a dependency is shipped. Naming Dew in a manifest
-- would put a desktop platform inside a Roblox author's package.

for _, path in ipairs({ "pesde.toml", "Cargo.toml" }) do
	if fs.isFile(path) then
		local body = string.lower(fs.readFile(path))
		if string.find(body, "dew", 1, true) then
			fail(
				`{path} names Dew. Aether may USE Dew as a tool and may never DEPEND on it; `
					.. `a tool is invoked from CI, a dependency ships to consumers.`
			)
		end
	end
end

-- 4 - THE DEBT, NAMED AND COUNTED --------------------------------------------
--
-- Everything below is a known ADR-004 violation. It does not fail the gate; it is
-- reported so it cannot be forgotten, and a violation NOT on the list does fail.

local outstanding: { string } = {}

for _, path in ipairs(RUST_NOT_MOVED_YET) do
	if fs.isFile(path) or fs.isDir(path) then
		table.insert(outstanding, `{path} (Rust workspace, moves to Dew)`)
	end
end
for _, path in ipairs(DATAMODEL_NOT_MOVED_YET) do
	if fs.isFile(path) then
		table.insert(outstanding, `{path} (DataModel, archives to OSS/luau-datamodel)`)
	end
end

--- Rust ANYWHERE that the allowlist does not cover. This is the half that makes
--- the gate bite: a new crate, or a stray `.rs`, fails on the commit that adds it.
local function allowed(path: string): boolean
	for _, entry in ipairs(RUST_NOT_MOVED_YET) do
		if path == entry or string.sub(path, 1, #entry + 3) == `./{entry}/` then
			return true
		end
	end
	return false
end

for _, path in ipairs(walk(".", {})) do
	local relative = string.gsub(path, "^%./", "")
	if string.match(relative, "%.rs$") or string.match(relative, "Cargo%.toml$") then
		if not allowed(path) and not allowed(relative) then
			fail(
				`{relative}: Rust outside the migration allowlist. Aether owns no Rust; if this `
					.. `is host code it belongs in Dew, and if the allowlist is stale, shrink it.`
			)
		end
	end
end

-- -- Report -------------------------------------------------------------------

print(`framework boundaries: {#outstanding} known violation(s) still to migrate`)
for _, entry in ipairs(outstanding) do
	print(`  DEBT  {entry}`)
end

print("")
if failures > 0 then
	print(`VERIFY FRAMEWORK BOUNDARIES: FAILED ({failures} problem(s))`)
	local process = require("@lune/process")
	process.exit(1)
elseif #outstanding > 0 then
	print(
		`VERIFY FRAMEWORK BOUNDARIES: PASS (no new violations; {#outstanding} named for migration)`
	)
else
	print("VERIFY FRAMEWORK BOUNDARIES: PASS (Aether is Luau, and hosts nothing)")
end
return true
