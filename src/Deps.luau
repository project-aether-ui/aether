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

local isScriptInstance = typeof(script) == "Instance"

local vide: any

local VirtualPkg: any = nil

if isScriptInstance then
	local packages = (script :: any).Parent.Parent.roblox_packages
	--- Unguarded: a missing hard dependency is a build error and must surface.
	---
	--- ms-51: this line was deleted by accident in c296a8c and only found in a
	--- Studio session. It is the reason `Host.detect(vide)` below received nil and
	--- every consumer of Aether failed to load in-engine while 62 headless suites
	--- and six gates stayed green — the Roblox branch is the one thing they cannot
	--- reach. verify_require_paths now asserts it.
	vide = require(packages.vide)

	pcall(function() VirtualPkg = require(packages.Virtual) end)
else
	-- ms-44 M5: ONE shim, in testkit/env, replacing six hand-rolled copies that had drifted
	-- to three fidelity levels — M76's "create records the class" landed in 3 of 6, M43's
	-- "effect actually runs" in 1 of 6. Both were bought with real Studio sessions and
	-- reached none of the other packages.
	--
	-- WHAT IT MODELS, AND WHAT IT DELIBERATELY DOES NOT, is stated in VideShim.luau. The
	-- behaviours are pinned by pkgs/testkit/env/tests/ShimConformance.test.luau, so this
	-- cannot silently regress the way six copies did.
	--
	-- SAFE TO NAME FROM A SHIPPED FILE: this branch is taken only when `script` is not an
	-- Instance, i.e. never in Roblox — the require is never evaluated there, so testkit
	-- cannot reach a place. The alias resolves in the workspace only.
	-- ms-51 M14: was `require("@testkit_env").VideShim.new()`.
	--
	-- The shim substituted the WHOLE of vide, including the reactive core that
	-- never needed substituting — and its substitute was strictly weaker:
	-- `effect` ran once with no dependency tracking, `derive` did not memoise.
	-- No suite written against it could observe a re-render; Aether's own
	-- TreeView suite documents routing around exactly that.
	--
	-- Aether.Host.Headless instead takes the sixteen vide modules that DO load
	-- outside Roblox (the whole reactive core, unmodified) and supplies only the
	-- seven that need an engine, over mock instances. It keeps the shim's
	-- props-table access shape — `_ClassName`, array children, properties by
	-- name — so suites written against the shim keep working.
	--
	-- SAFE TO NAME FROM A SHIPPED FILE: this branch is taken only when `script`
	-- is not an Instance, i.e. never in Roblox.
	vide = require("./host/Headless").new()
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
local HostModule = if isScriptInstance
	then require((script :: any).Parent.host.Host)
	else require("./host/Host")

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
