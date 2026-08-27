--!strict
--[[
	spektr/zune_host · Reload — load a module again, without restarting (ms-53 P0).

	    local Reload = require("./Reload")
	    Reload.SetHotRoot("pkgs/ui")
	    local App = Reload.Load("pkgs/ui/hosts/web/src/App.luau")

	WHY THIS IS NOT `require` AGAIN
	`zune.require` exposes exactly two things -- `getCached` and `navigate`. There
	is no way to invalidate an entry, so "just require it again" returns the module
	that was already there. Measured, not assumed.

	And restarting the process is not the fallback it sounds like: a bare
	`zune run` of a no-op script costs 276-289 ms before any of this repo's code
	loads, and a cold framework require plus `App.create` takes the total to
	580-676 ms. That is the design this file exists to avoid; it reloads in 2-9 ms.

	HOW IT WORKS, and every step of it is load-bearing:

	  1. Read the source and `zune.luau.compile` it. A fresh chunk, every time.
	  2. `zune.luau.load` it with an INJECTED `require`.
	  3. That injected require resolves the alias against the SOURCE FILE's real
	     path -- not this file's -- because a loaded chunk has no file identity of
	     its own and `chunkName` is cosmetic. Relative requires inside it would
	     otherwise resolve against `Reload.luau`.
	  4. The resolved ABSOLUTE path is turned back into a `./`-relative alias from
	     this file's directory, because zune's `require` rejects absolute paths
	     outright: "must have either @, ./, or ../ prefix".
	  5. If that path is under the HOT ROOT, recurse -- load it fresh too.
	     Otherwise hand it to the real, cached `require`.

	STEP 5 IS THE WHOLE DESIGN. Real HMR invalidates by dependency graph. This
	declares a boundary instead: the application's own source is hot and reloads,
	the framework beneath it is cached and does not. That is both simpler and more
	predictable than an inferred graph, and it is where a UI author wants the line
	anyway -- editing a screen should not rebuild Aether.
]]

local z = (zune :: any)
local fs = z.fs

local Reload = {}

local function norm(p: string): string
	return string.gsub(p, "\\", "/")
end

--- Absolute, with forward slashes.
---
--- Everything here compares paths by prefix, and a comparison between a relative
--- path and an absolute one silently finds no common prefix -- which surfaces as
--- `require` rejecting a path, four frames away from the cause.
local function absolute(p: string): string
	local n = norm(p)
	if string.match(n, "^%a:/") then
		return n
	end
	return norm(z.process.cwd()) .. "/" .. (string.gsub(n, "^%./", ""))
end

--- WHERE THIS FILE IS, so an absolute path can be turned back into an alias.
---
--- `debug.info(1, "s")` answers a required module's own path -- IN WHATEVER FORM
--- IT WAS REQUIRED. Required relatively from a script run relatively, it answers
--- `pkgs/ui/hosts/zune/src/Reload.luau`; run by absolute path, it answers an
--- absolute one. Assuming the absolute form is a bug that only appears when the
--- host is launched a particular way, which is the worst kind.
---
--- Taken at load time rather than per call because it cannot change, and because
--- reading it inside `toAlias` would report the CALLER's file instead.
local SELF: string = absolute(debug.info(1, "s") or "")
local SELF_DIR: string = string.match(SELF, "^(.*)/[^/]*$") or "."

local hotRoots: { string } = {}

--- Which subtree(s) reload. Everything else comes from the cached `require`.
---
--- Accepts one path or a list. A list because the answer is not one prefix: for a
--- story the hot set is the components, kits and tokens -- and pointedly NOT the
--- framework or the vendored packages beneath it.
---
--- Paths are stored normalised and lowercased, because Windows hands back mixed
--- case (`C:\Users` from one API, `c:/users` from another) and a case-sensitive
--- prefix test would silently match nothing -- which fails as "the hot root does
--- nothing", not as an error.
function Reload.SetHotRoot(path: (string | { string })?)
	if path == nil then
		hotRoots = {}
		return
	end
	local list = if type(path) == "table" then path else { path }
	hotRoots = {}
	for _, one in ipairs(list) do
		table.insert(hotRoots, string.lower((string.gsub(absolute(one), "/+$", ""))))
	end
end

--- NEVER HOT, whatever the roots say.
---
--- A fresh load makes a NEW COPY of a module, and for a module with process-wide
--- state that is not a reload -- it is a second instance of a singleton. vide's
--- reactive graph is the sharp case: load a second vide and a story's `spring`
--- belongs to a different graph than the root the app mounts it in, so it fails
--- with "cannot use spring() outside a stable or reactive scope" from code that
--- did not change. The same argument covers Aether itself, whose PointerRouter
--- holds every registration in the process.
---
--- Found by widening the story hot root to `pkgs/ui`, which swallowed
--- `Aether/roblox_packages/.pesde/centau_vide@0.4.1`. The failure names `spring`
--- and points at the story; the cause is three layers away in this loader.
local function isVendored(lower: string): boolean
	return string.find(lower, "/roblox_packages/", 1, true) ~= nil
		or string.find(lower, "/framework/aether/", 1, true) ~= nil
end

local function isHot(abs: string): boolean
	local lower = string.lower(norm(abs))
	if isVendored(lower) then
		return false
	end
	for _, root in ipairs(hotRoots) do
		if string.sub(lower, 1, #root) == root then
			return true
		end
	end
	return false
end

--- An absolute path as an alias this file can `require`.
---
--- Walks up from `SELF_DIR` to the common prefix, then down. The `../` chain is
--- usually long -- this file is five directories deep and the kits are in a
--- sibling tree -- which is fine and is why it is generated rather than written.
local function toAlias(abs: string): string
	local target = norm(abs)
	local from = SELF_DIR

	local function split(p: string): { string }
		local out = {}
		for part in string.gmatch(p, "[^/]+") do
			table.insert(out, part)
		end
		return out
	end

	local a, b = split(from), split(target)
	local i = 1
	while a[i] and b[i] and string.lower(a[i]) == string.lower(b[i]) do
		i += 1
	end
	--- No shared prefix at all means a different drive, and no relative path can
	--- express that. Returning the absolute path lets `require` produce its own
	--- error rather than this function inventing a wrong one.
	if i == 1 then
		return target
	end

	local parts = {}
	for _ = i, #a do
		table.insert(parts, "..")
	end
	for j = i, #b do
		table.insert(parts, b[j])
	end
	local rel = table.concat(parts, "/")
	return if string.sub(rel, 1, 2) == ".." then rel else "./" .. rel
end

--- `.luau` is stripped because `navigate` answers extensionless paths and
--- `require` wants them that way too; a path that already lacks one is untouched.
local function stripExt(p: string): string
	return (string.gsub(p, "%.luau$", ""))
end

--- The FILE a resolved require path names, or nil.
---
--- Two shapes, and missing the second one is what a first attempt does: a
--- require may name a MODULE (`.../Live` -> `Live.luau`) or a DIRECTORY
--- (`.../Aether/src` -> `src/init.luau`). App.luau's very first require is the
--- directory form, so this is not an edge case.
---
--- `pcall`, because `fs.metadata` THROWS on a missing path rather than answering
--- nil -- so the obvious `if fs.metadata(p) then` is an error, not a test.
local function fileAt(resolved: string): string?
	local candidates = if string.match(resolved, "%.luau$")
		then { resolved }
		else { resolved .. ".luau", resolved .. "/init.luau" }
	for _, c in ipairs(candidates) do
		local ok, meta = pcall(fs.metadata, c)
		if ok and meta and meta.kind == "file" then
			return c
		end
	end
	return nil
end

local generation = 0

--- Every file the LAST load evaluated, with the modification time it had then.
---
--- This is the watch set, and it is discovered rather than configured: the files
--- that were loaded are exactly the files whose edits could change the screen.
--- A configured glob would either miss a file or watch a thousand.
local loaded: { [string]: number } = {}

--- START A BUILD. Clears the watch set; every `Load` after it adds to it.
---
--- A BUILD IS NOT A LOAD, and conflating them broke story mode silently. Clearing
--- inside `Load` is correct when one call builds everything -- true for a screen,
--- false for a story, where the host loads every story FILE to discover what is
--- there and then loads the app. Each call wiped the previous one's files, so the
--- set ended up holding only the app, editing a story changed nothing, and the
--- reload simply never fired. No error and no warning: the window just stopped
--- responding to saves.
---
--- So the boundary is explicit. The host calls this once per rebuild and the
--- loads that follow accumulate.
function Reload.BeginBuild()
	loaded = {}
end

--- Load one module fresh. Dependencies under the hot root load fresh too, once
--- each; everything else comes from the cached `require`.
---
--- `seen` is per CALL, not global -- it exists so a diamond dependency evaluates
--- once within a reload, and must NOT survive between reloads or the second
--- reload would serve the first one's modules and appear to do nothing.
function Reload.Load(path: string): any
	generation += 1
	local seen: { [string]: any } = {}

	local function loadFresh(absPath: string): any
		local key = string.lower(norm(absPath))
		local hit = seen[key]
		if hit ~= nil then
			return hit
		end

		local file = fileAt(absPath) or absPath
		--- NO `or 0` FALLBACK. The field is `modified_at`; writing `modifiedAt`
		--- and defaulting the miss to 0 makes every file look unchanged forever
		--- and the reload silently never fires -- which is exactly what the first
		--- version of this did, and it looked like it worked.
		local okMeta, meta = pcall(fs.metadata, file)
		assert(okMeta and meta and type(meta.modified_at) == "number",
			`Reload: fs.metadata gave no modified_at for {file}; the watch set would be dead`)
		loaded[file] = meta.modified_at
		local src = fs.readFile(file)
		local chunk = z.luau.load(z.luau.compile(src), {
			chunkName = absPath,
			--- `env` REPLACES the global environment; it does not overlay it.
			--- Without the metatable the chunk cannot call `print`. The key is
			--- `env` -- `environment`, `globals` and `fenv` are accepted and
			--- silently ignored, which is a quiet way to lose an afternoon.
			env = setmetatable({
				require = function(alias: string): any
					local resolved = norm(z.require.navigate(alias, absPath))
					local file = fileAt(resolved)
					if file ~= nil and isHot(file) then
						return loadFresh(file)
					end
					--- Not hot, or not a file we can see (an alias into
					--- `roblox_packages`, say). The real require knows more about
					--- those than this does, so it gets the last word.
					return require(toAlias(stripExt(resolved)))
				end,
			}, { __index = getfenv() }),
		})

		--- Recorded BEFORE the chunk runs. A hot module that requires something
		--- which requires it back would otherwise recurse forever; this makes the
		--- cycle resolve to nil the way a real module system does, rather than
		--- hanging.
		seen[key] = true
		local value = chunk()
		seen[key] = value
		return value
	end

	return loadFresh(absolute(path))
end

--- How many times `Load` has been called. The reload gate asserts on this, so a
--- reload path that quietly stopped firing cannot pass by leaving the screen
--- looking correct.
function Reload.Generation(): number
	return generation
end

--- The files the last load evaluated. The host's watch set.
function Reload.Watched(): { string }
	local out = {}
	for file in pairs(loaded) do
		table.insert(out, file)
	end
	table.sort(out)
	return out
end

--- Has any watched file changed since it was loaded?
---
--- POLLED, not watched. `zune.fs.watch` blocks the calling thread, and the host
--- already has a loop running at 60-240 Hz -- so a stat over a handful of files
--- on an interval is both simpler and free, where introducing a second thread to
--- the window's message pump is neither.
---
--- A DELETED file counts as changed: `pcall` fails, and reporting "nothing
--- changed" for a file that no longer exists is how a reload silently stops
--- firing.
function Reload.Changed(): boolean
	for file, at in pairs(loaded) do
		local ok, meta = pcall(fs.metadata, file)
		if not ok or not meta then
			return true
		end
		if meta.modified_at ~= at then
			return true
		end
	end
	return false
end

return Reload
