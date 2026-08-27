--!strict
--[[
	spektr/zune_host · Stories — find, name and mount isolated UI states (ms-53 P1).

	    local Stories = require("./Stories")
	    local all = Stories.Discover("pkgs/ui")
	    local one = Stories.Find(all, "Kits/ShopUI/ShopMenu:Default")

	WHAT A STORY FILE LOOKS LIKE

	    -- pkgs/ui/kits/ShopUI/stories/ShopMenu.story.luau
	    local ShopMenu = require("../src/ShopMenu")

	    return {
	        Title = "Kits/ShopUI/ShopMenu",
	        Stories = {
	            { Name = "Default", Build = function() return ShopMenu({ Visible = true }) end },
	            { Name = "Hidden",  Build = function() return ShopMenu({ Visible = false }) end },
	        },
	    }

	A THUNK, NOT A PROPS TABLE, and that is the design decision this file rests on.

	The obvious format is `stories = { Default = { item = ... } }` -- a table of
	props per story, mounted by a runner that knows how to call the component. It
	reads better and it would force every component in this repo to adopt one
	calling convention before a single story could exist. A story format should not
	arrive as a refactor of `pkgs/ui/components/*`.

	A thunk imposes nothing. The story calls the component itself, however that
	component wants to be called, and the runner only has to mount what comes back.
	Components that later converge on a convention lose nothing by it.

	AN ORDERED ARRAY, NOT A MAP. Luau's `pairs` order is unspecified, so a map
	would list stories in a different order between runs -- which makes a picker
	jump around and, in P2, makes CI snapshot filenames unstable. Order is content
	here, so it is expressed as order.

	STORIES ARE NOT SHIPPED. They live in `<pkg>/stories/`, a sibling of `tests/`,
	because `verify_tests_not_shipped` exists for exactly this reason: anything
	under `src/**` reaches a player's DataModel, and a story file requires fixtures
	and mock data that have no business there.
]]

local Aether = require("../../../src")
local Reload = require("./Reload")

local z = (zune :: any)
local fs = z.fs

local Stories = {}

export type Story = {
	--- "Kits/ShopUI/ShopMenu:Default" — the stable identity, used by `--story`,
	--- by the picker, and (in P2) as the snapshot filename.
	Id: string,
	Title: string,
	Name: string,
	--- Absolute path of the file it came from, so the picker can group and the
	--- reloader can watch.
	File: string,
	Build: () -> any,
	--- Check names this story violates ON PURPOSE, from `host/Checks.luau`
	--- (ms-53 P3). Declared per story or per file.
	---
	--- A NAMED EXEMPTION, not a disabled check. A subject that breaks a rule
	--- deliberately -- a marquee that must overflow, a watermark that must be
	--- low-contrast -- has to say so in the story, where the next reader sees it
	--- beside the thing it excuses. The alternative people reach for is turning
	--- the check off globally, which loses every other subject with it.
	Allow: { string }?,
	--- This story MOUNTS AND PAINTS NOTHING, on purpose (ms-53 D3).
	---
	--- `ShopMenu:Hidden` is the case: a menu told not to be visible should draw
	--- no pixels, and until D3 it drew all of them.
	---
	--- It ASSERTS, it does not exempt. `--stories-check` requires a story marked
	--- this way to be empty, so one that quietly starts painting again is caught
	--- by the same flag that permits the emptiness -- which an exemption would
	--- not do.
	Empty: boolean?,
	--- This story exists to BREAK something, for a gate to catch (ms-53).
	---
	--- `aether-cli check` skips fixtures unless one is named with `--story`, so a
	--- normal run reports the repo's real findings and its exit code means what it
	--- says. Without this the deliberate violations fire on every run and the
	--- command is red forever -- which is indistinguishable from red for a reason,
	--- and is how a check stops being read.
	Fixture: boolean?,
}

local function norm(p: string): string
	return (string.gsub(p, "\\", "/"))
end

--- Every `*.story.luau` under `root`, depth-first, sorted.
---
--- SORTED AT EVERY LEVEL, not just at the end. `fs.entries` gives no order
--- guarantee, and an unordered walk makes the story list -- and therefore the
--- picker and the snapshot set -- depend on directory layout on disk.
---
--- `fs.entries` answers an ARRAY of `{ name, kind }`, and its kind for a folder
--- is `"directory"` -- not `"dir"`, which is what `fs.metadata` says. Reading it
--- as a name-keyed map, or matching on the wrong spelling, finds NOTHING and
--- reports success: the first version of this walk discovered zero stories and
--- printed "discovered 0" rather than failing.
local function walk(dir: string, out: { string })
	local ok, entries = pcall(fs.entries, dir)
	if not ok or type(entries) ~= "table" then
		return
	end
	local names: { { name: string, kind: string } } = {}
	for _, e in ipairs(entries) do
		if type(e) == "table" and type(e.name) == "string" then
			table.insert(names, e)
		end
	end
	table.sort(names, function(a, b)
		return a.name < b.name
	end)
	for _, e in ipairs(names) do
		local path = `{dir}/{e.name}`
		if e.kind == "directory" then
			--- `roblox_packages` holds INSTALLED copies of this workspace's own
			--- packages. Walking it would find every story twice, under a
			--- vendored path, and mount the installed copy rather than the source
			--- being edited.
			if e.name ~= "roblox_packages" and e.name ~= "target" and string.sub(e.name, 1, 1) ~= "." then
				walk(path, out)
			end
		elseif string.match(e.name, "%.story%.luau$") then
			table.insert(out, norm(path))
		end
	end
end

--- Load every story file under `root` and flatten it into one ordered list.
---
--- `load` is injected so a caller can substitute the loader, but the DEFAULT is
--- `Reload.Load` rather than `require` -- and it has to be. zune's `require`
--- accepts only `@`/`./`/`../` aliases resolved against the calling script, and a
--- discovered path is neither: plain `require` answers *"must have either @, ./,
--- or ../ prefix"* for every story file found. `Reload.Load` already does that
--- round trip, and loading stories fresh is what makes editing one reload it.
function Stories.Discover(root: string, load: ((string) -> any)?): { Story }
	local files: { string } = {}
	walk(root, files)

	--- THE HOST MUST EXIST BEFORE A STORY FILE LOADS.
	---
	--- A story requires the component it shows, at module scope, and a component
	--- reaches for the value vocabulary -- `UDim2`, `Color3`,
	--- `NumberSequenceKeypoint` -- as GLOBALS. Off-engine those are supplied by the
	--- host, so loading a story before any host exists fails inside a token module
	--- four requires down, with `attempt to index nil with 'new'` and no hint that
	--- the cause is ordering.
	---
	--- `detect` rather than `new`: there is one host in a process, for the same
	--- reason there is one engine, and a second one would leave flux-motion's
	--- springs listening to a clock nobody steps.
	--- And the vocabulary must be INSTALLED, not merely available on the host.
	--- Component sources read `UDim2`/`Color3`/`NumberSequenceKeypoint` as bare
	--- globals; `host.Vocabulary` holds them but does not put them there. Every
	--- suite in this repo opens with the same line for the same reason.
	Aether.Host.detect().InstallVocabulary()

	local loader = load or Reload.Load
	local out: { Story } = {}
	for _, file in ipairs(files) do
		local ok, mod = pcall(loader, file)
		if not ok then
			--- REPORTED, NOT SWALLOWED, and not fatal either. One broken story
			--- file must not hide the other forty; a story that cannot load is
			--- itself a finding, and silently skipping it turns "my story
			--- disappeared" into a mystery.
			out[#out + 1] = {
				Id = `{file}:<failed to load>`,
				Title = file,
				Name = "<failed to load>",
				File = file,
				Build = function()
					error(`story file failed to load: {mod}`, 0)
				end,
			}
		elseif type(mod) == "table" and type(mod.Stories) == "table" then
			local title = tostring(mod.Title or file)
			for _, entry in ipairs(mod.Stories) do
				if type(entry) == "table" and type(entry.Build) == "function" then
					local name = tostring(entry.Name or "?")
					--- File-level `Allow` is inherited and a story's own OVERRIDES
					--- it, rather than merging: a story that lists its own
					--- exemptions is stating the complete set, and silently adding
					--- the file's to it is how an exemption outlives its reason.
					table.insert(out, {
						Id = `{title}:{name}`,
						Title = title,
						Name = name,
						File = file,
						Build = entry.Build,
						Allow = entry.Allow or mod.Allow,
						Empty = entry.Empty,
						Fixture = entry.Fixture or mod.Fixture,
					})
				end
			end
		end
	end
	return out
end

--- Find one story by exact id, or by a unique suffix match on its name.
---
--- The suffix form is for typing at a command line: `--story Default` when only
--- one story is called that. AMBIGUITY IS AN ERROR, not a first match --
--- silently mounting one of two candidates is how a snapshot ends up naming a
--- component nobody edited.
function Stories.Find(all: { Story }, query: string): Story?
	for _, s in ipairs(all) do
		if s.Id == query then
			return s
		end
	end
	local matches: { Story } = {}
	for _, s in ipairs(all) do
		if s.Name == query or string.find(s.Id, query, 1, true) then
			table.insert(matches, s)
		end
	end
	if #matches == 1 then
		return matches[1]
	end
	if #matches > 1 then
		local ids = {}
		for _, s in ipairs(matches) do
			table.insert(ids, s.Id)
		end
		error(`"{query}" matches {#matches} stories: {table.concat(ids, ", ")}`, 0)
	end
	return nil
end

--- The distinct story FILES behind a list, in order. The reloader's watch set
--- when a story is mounted rather than a screen.
function Stories.Files(all: { Story }): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, s in ipairs(all) do
		if not seen[s.File] then
			seen[s.File] = true
			table.insert(out, s.File)
		end
	end
	return out
end

return Stories
