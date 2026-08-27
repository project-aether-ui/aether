--!strict
--[[
	verify_headless_is_portable — the CLI must never reach a platform (ms-53 P2).

	    lune run tests/gates/verify_headless_is_portable.luau

	WHAT IT PROTECTS

	`aether-cli` renders stories to PNG with no window and no DC, which is what
	every CI and cloud claim in the ms-53 roadmap runs through. A snapshot pipeline
	that only works on the maintainer's Windows box is not a pipeline.

	Getting there was a factoring, not a port -- the Rust crate has no platform
	`cfg` outside optional features and builds clean on Linux x86_64 -- but the
	Luau side had THREE edges into Windows and only one was obvious:

	  1. `RasterPainter` required `Win32` for two `SetDIBitsToDevice` calls.
	     Moved to `WindowsPresenter`.
	  2. `RasterPainter` required `NativePainter` -- the GDI painter -- for
	     `TextOrigin`, which is PURE ARITHMETIC and lived there only because it
	     was written there first. Moved to `TextOrigin`.
	  3. The library and font paths were hardcoded `.dll` and `C:/Windows/Fonts`.

	WHY THIS IS STATIC. The failure it catches is invisible on the machine that
	introduces it: adding `require("./Win32")` to a shared module works perfectly
	on Windows and breaks a Linux container that nobody runs locally. This is the
	same argument `verify_require_paths` makes about the Roblox branch, and the
	same reason it is a scan rather than a test.

	It resolves requires by hand rather than loading anything, because loading is
	exactly what fails on the wrong platform -- and a gate that has to run on Linux
	to protect Linux protects nothing on the machine where the mistake is made.
]]

local fs = require("@lune/fs")

--- The entry points that must stay portable, and what they must not reach.
local ENTRIES = {
	"hosts/zune/src/Cli.luau",
}

--- FORBIDDEN BY MODULE, not by symbol. `Win32` is the binding; the other two are
--- the files that legitimately use it, and a shared module reaching either of
--- them drags the whole platform along -- which is exactly how `RasterPainter`
--- ended up Windows-only via a text-alignment helper.
local FORBIDDEN: { [string]: string } = {
	["Win32"] = "the Win32 FFI bindings",
	["WindowsPresenter"] = "the DIB present path (Windows only, by design)",
	["NativePainter"] = "the GDI painter (requires Win32)",
	["WindowedPainter"] = "the wgpu swapchain painter (requires a window)",
}

local function norm(p: string): string
	return (string.gsub(p, "\\", "/"))
end

--- Resolve a `./` or `../` alias against the requiring file's directory.
---
--- Only relative aliases are followed. An `@alias` is a package boundary and
--- resolving it would mean reimplementing pesde's resolver inside a gate; the
--- entry points here use relative requires throughout, and a NEW `@alias` on this
--- path is reported rather than silently skipped -- see `unresolved` below.
local function resolve(fromFile: string, alias: string): string?
	if string.sub(alias, 1, 1) ~= "." then
		return nil
	end
	local dir = string.match(norm(fromFile), "^(.*)/[^/]*$") or "."
	local parts: { string } = {}
	for part in string.gmatch(dir, "[^/]+") do
		table.insert(parts, part)
	end
	for part in string.gmatch(alias, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	local joined = table.concat(parts, "/")
	for _, candidate in ipairs({ joined .. ".luau", joined .. "/init.luau" }) do
		if fs.isFile(candidate) then
			return candidate
		end
	end
	return nil
end

--- Requires in a file, with block comments and line comments removed first.
---
--- STRIPPED, because this repo documents heavily and several of those documents
--- QUOTE a require in prose -- including, in `RasterPainter`, the very line this
--- gate exists to forbid. Scanning raw text reports the comment and the gate
--- becomes a thing people work around by rewording a sentence.
local function requiresIn(source: string): { string }
	local stripped = string.gsub(source, "%-%-%[%[.-%]%]", "")
	stripped = string.gsub(stripped, "%-%-[^\n]*", "")
	local out: { string } = {}
	for alias in string.gmatch(stripped, 'require%s*%(%s*"([^"]+)"%s*%)') do
		table.insert(out, alias)
	end
	return out
end

local failures: { string } = {}
local unresolved: { string } = {}
local visitedCount = 0

for _, entry in ipairs(ENTRIES) do
	assert(fs.isFile(entry), `{entry} does not exist`)

	--- Breadth-first with a path, so a failure names the CHAIN rather than just
	--- the offending file. "RasterPainter requires NativePainter" is actionable;
	--- "something requires Win32" is a search.
	local seen: { [string]: boolean } = { [entry] = true }
	local queue: { { file: string, path: string } } = { { file = entry, path = entry } }

	while #queue > 0 do
		local item = table.remove(queue, 1) :: any
		visitedCount += 1
		local source = fs.readFile(item.file)

		for _, alias in ipairs(requiresIn(source)) do
			local name = string.match(alias, "([^/]+)$") or alias
			local bad = FORBIDDEN[name]
			if bad then
				table.insert(failures, `{item.path}\n      -> requires "{alias}" ({bad})`)
			end

			local target = resolve(item.file, alias)
			if target == nil then
				if string.sub(alias, 1, 1) == "." then
					table.insert(unresolved, `{item.file} -> {alias}`)
				end
			elseif not seen[target] then
				seen[target] = true
				table.insert(queue, { file = target, path = `{item.path}\n      -> {target}` })
			end
		end
	end
end

print(`walked {visitedCount} module(s) from {#ENTRIES} entry point(s)`)

--- A RELATIVE REQUIRE THAT DOES NOT RESOLVE IS A HOLE IN THIS GATE, not a
--- curiosity. It means a branch of the graph was never walked, so anything
--- forbidden beyond it is invisible -- the gate would pass by not looking.
if #unresolved > 0 then
	print("relative requires that could not be resolved -- the walk did not cover these:")
	for _, u in ipairs(unresolved) do
		print(`  {u}`)
	end
end

if #failures > 0 or #unresolved > 0 then
	print("")
	for _, f in ipairs(failures) do
		print(`FAIL: {f}`)
	end
	print(`the headless entry points must not reach a platform: {#failures} forbidden require(s), `
		.. `{#unresolved} unresolved`)
	local process = require("@lune/process")
	process.exit(1)
end

print("OK -- the headless CLI reaches no window, no DC and no Win32.")
