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

--- THE HOST DECIDES, AND vide FOLLOWS FROM IT. Inverted 2026-09-04.
---
--- This file used to open with
---
---     local isRobloxEngine = typeof(game) == "Instance"
---
--- and resolve vide from it -- the pesde redirect in the engine, the Luau test
--- double everywhere else -- and then hand the result to `Host.detect(vide)`.
---
--- THAT WAS A SECOND ANSWER TO A QUESTION THE HOST ALREADY ANSWERS, and the two
--- could disagree. `Host.detect()` selects by capability now: it builds an
--- instance, agrees with `typeof` about it, reads a name back, parents a child,
--- round-trips a `UDim2` and tears the tree down. This line selected by looking
--- for one vendor's global, which is the thing `available()` stopped doing --
--- and it selected the ARTEFACT EVERY COMPONENT IS BUILT WITH, so it outranked
--- the host in practice. On a conforming non-Roblox host the pair produced a
--- framework reporting `Host.Name == "DataModel"` over a tree of mock instances,
--- with every suite green and every widget rendering correctly, because
--- `Deps.create` was the double's `create`. Dew measured exactly that.
---
--- So: resolve the host, take vide from the host. `Host.DataModel` gets the
--- engine's artefact where there is one and assembles vide from the installed
--- package with `VideCore.full()` where there is not; `Host.LuauDataModel` IS a
--- vide, which is what makes it a test double. Either way there is one decision,
--- it is made by capability, and this file reads the result.
local HostModule = require("./host/Host")

--- THE ENGINE'S OWN ARTEFACT, OFFERED TO THE HOST RATHER THAN CHOSEN INSTEAD OF
--- IT, and this is the one line of the old branch that stays exactly where it is.
---
--- `roblox_packages/vide` is a redirect pesde GENERATES and it reaches its target
--- through the Instance tree, so there is nothing here to require off-engine.
--- VideCore assembles vide from the installed package there instead, and the host
--- calls it; this is the artefact that has no off-engine equivalent.
---
--- IT IS NOT MOVED INTO THE HOST, deliberately, and the reason is ms-51: this
--- exact line was deleted by accident in c296a8c, sixty-two suites and six gates
--- stayed green because not one of them can execute the Roblox branch, and it
--- surfaced in a Studio session as every consumer of Aether failing to load.
--- `verify_require_paths` asserts it in this file. A Roblox-only require is worth
--- keeping in the file that already has a gate watching it.
---
--- OFFERED, NOT DECIDED WITH. `detect()` still picks the host by capability, and
--- uses this only if it picked the host that drives a DataModel. A host that
--- declined would ignore it, which is the correct answer rather than a lost one.
local engineVide: any = nil
if typeof(game) == "Instance" then
	engineVide = require("../roblox_packages/vide")
end

local ResolvedHost = HostModule.detect(engineVide)

--- The vide the resolved host is driving. Never nil: both hosts set it, and a
--- host that could not resolve one errors in its own constructor rather than
--- handing back a half-built surface.
local vide: any = ResolvedHost.vide

--- STILL BRANCHED ON, FOR ONE OPTIONAL PACKAGE AND NOT FOR vide. `spektr/virtual`
--- is a pesde redirect that reaches its target through the Instance tree, so
--- there is nothing to require off-engine and the require itself is the failure.
--- Without it VirtualList renders every row, which is slow rather than wrong.
---
--- `typeof(game)` rather than `typeof(script)`: the question is "is this the
--- Roblox engine", and `game` answers it directly. It is ALSO the last use of
--- `game` in this framework, and it is a genuine one -- Dew's `game` is the
--- boolean `true`, so this answers false there, correctly.
local isRobloxEngine = typeof(game) == "Instance"

local VirtualPkg: any = nil
if isRobloxEngine then
	pcall(function()
		VirtualPkg = require("../roblox_packages/Virtual")
	end)
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
---
--- FROM THE SAME HOST vide CAME FROM, which is the point of the inversion at the
--- top of this file: the vocabulary and the reactive surface are now two readings
--- of ONE decision rather than two decisions that happened to agree.
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
	--- STILL A VENDOR TEST, AND STILL THE RIGHT ONE. Its consumers ask "am I in
	--- the engine" about engine-only affordances -- `Enum.Font.GothamMedium`
	--- against the string "GothamMedium" in WindowTopbar, for one -- rather than
	--- asking which DataModel they are on. That second question is `Host.Name`.
	isRoblox = isRobloxEngine,
}
