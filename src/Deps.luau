--!strict
--[[
	Deps: the ONE place Aether resolves its cross-package dependencies.

	See pkgs/ui/motion/Flux/src/Deps.luau for the full rationale (ms-43 blueprint B-2/E-1).
	In short: seven Aether modules each carried a private copy of a reflective
	`getPackage(name)` substring scan that could return nil and could bind the
	wrong package, and every consumer had to nil-guard around it. pesde already
	emits a deterministic `Aether/roblox_packages/<Dep>.luau` for each declared
	dependency.

	THE CONTRACT: every field below is NON-NIL, always. Consumers never guard.
]]

--- THE ONE PLACE AN ENVIRONMENT IS STILL BRANCHED ON, and it is not about paths.
---
--- Every require in this package is now a string, resolved the same way by every
--- runtime. This branch survives because the two hosts do not obtain the same
--- ARTEFACT, not because they spell the path differently:
---
---   * On Roblox, `roblox_packages/vide` is a redirect pesde GENERATES, and it
---     reaches its target through the Instance tree. We require it by string; what
---     it does inside is pesde's business and not ours to spell away.
---   * Off-engine that redirect cannot resolve — there is no Instance tree — so
---     VideCore takes the sixteen vide modules that load as plain Luau and
---     supplies the seven that need an engine, over mock instances.
---
--- `typeof(game)` rather than `typeof(script)`: the question being asked is "is
--- this the Roblox engine", and `game` answers it directly. `script` answers
--- "was this loaded as an Instance", which is the same thing today and is a
--- proxy rather than the question.
local isRobloxEngine = typeof(game) == "Instance"

local vide: any
local VirtualPkg: any = nil

if isRobloxEngine then
	--- Unguarded: a missing hard dependency is a build error and must surface.
	---
	--- ms-51: this line was deleted by accident in c296a8c and only found in a
	--- Studio session. It is the reason `Host.detect(vide)` below received nil and
	--- every consumer of Aether failed to load in-engine while 62 headless suites
	--- and six gates stayed green — the Roblox branch is the one thing they cannot
	--- reach. verify_require_paths now asserts it.
	vide = require("../roblox_packages/vide")

	--- OPTIONAL. `spektr/virtual` windows a long list; without it VirtualList
	--- renders every row, which is slow rather than wrong.
	pcall(function()
		VirtualPkg = require("../roblox_packages/Virtual")
	end)
else
	--- The reactive core, unmodified, plus mock instances for the seven modules
	--- that need an engine. VideCore.luau carries the measurement and the reason
	--- the split lands exactly there.
	vide = require("./host/LuauDataModel").new()
end

--- Read a source WITHOUT subscribing the enclosing reactive scope to it.
---
--- ms-51 M14. vide refuses to re-enter a scope that is already running:
---
---     "a scope, that should rerun due to the update of a source, is already active"
---
--- So any source that is READ and then WRITTEN inside the same reactive pass is a
--- fault — the read subscribes the running effect, and the write then asks that
--- effect to re-run while it is still on the stack. Two shipped instances of this
--- were found the moment real vide replaced VideShim (whose effect never tracked
--- anything, so neither could fire): VirtualList's `mountedCount` change-guard,
--- and ScrollArea's `versionSignal(versionSignal() + 1)`.
---
--- Neither is headless-only. Real vide raises the same error in-engine; they
--- survived because the reachable paths happened to start from an empty item set
--- or from outside an effect.
---
--- Use `peek` for any source that is a GUARD or a COUNTER rather than a value the
--- surrounding scope should react to.
local function peek<T>(src: () -> T): T
	if vide.untrack then
		return vide.untrack(src)
	end
	return src()
end

local function scopedCleanup(fn: () -> ())
	pcall(vide.cleanup, fn)
end

--- THE VALUE VOCABULARY (ms-51 M16), from the host rather than from globals.
---
--- es9: a single interface regardless of host. UDim2, Color3, Vector2 and the
--- rest were read as GLOBALS everywhere in this tree — ~712 call sites — which
--- worked in Roblox because the engine defines them, and worked headlessly only
--- because each test file happened to assign them (`Vector2 = rbx.Vector2`) as
--- implicit globals before requiring anything. That was the last coupling still
--- sitting outside Layer 2.5.
---
--- Modules bind these as LOCALS at the top of the file, which is what lets the
--- call sites stay exactly as they are while the provider becomes swappable.
--- They are not deeply Roblox types: UDim2 is {scale, offset} per axis, Color3 is
--- three floats. A non-Roblox host implements the same eleven names.
local HostModule = require("./host/Host")

local ResolvedHost = HostModule.detect(vide)
local Vocabulary = ResolvedHost.Vocabulary

return {
	vide = vide,
	Vocabulary = Vocabulary,
	--- Layer 2.5 itself. `Host.Scene` is what the hit-testing and arbitration
	--- algorithms ask instead of asking the engine (ms-51 M16 part 3).
	Host = ResolvedHost,
	source = vide.source,
	spring = vide.spring,
	derive = vide.derive,
	effect = vide.effect,
	read = vide.read,
	root = vide.root,
	untrack = vide.untrack,
	peek = peek,
	create = vide.create,
	action = vide.action,
	cleanup = scopedCleanup,

	Virtual = VirtualPkg,
	isRoblox = typeof(game) == "Instance",
}
