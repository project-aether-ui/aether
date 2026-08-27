--!strict
--[[
	Aether · host/VideCore — REAL vide, loaded outside Roblox.

	WHY THIS EXISTS
	The premise everything below rests on, measured against centau_vide@0.4.1:

	    REACHABLE in Lune (16)  graph source effect derive root batch untrack context
	                            switch show indexes values read branch flags action
	    BLOCKED      (7)        create apply defaults mount cleanup changed lib

	Every blocked module opens with the same line —

	    local typeof = game and typeof or require "../test/mock".typeof

	— so vide ALREADY declares its own host boundary, and declares it in exactly
	four names: `typeof`, `Instance`, `Enum`, `Color3`. The wally/pesde artifact
	simply ships without the `test/` directory, so that fallback is a dangling
	require. Nothing else blocks any of them.

	The split falls precisely on Layer 2 (pure reactive protocol) versus Layer 2.5
	(host resolver). So we do NOT patch vide, and we do NOT reimplement its graph:
	we take the 16 reachable modules AS THEY SHIP and let each host supply the
	seven it cannot reach. `Aether.Host.Headless` builds them over mock instances,
	`Aether.Host.Roblox` takes vide's own.

	WHAT THIS BUYS OVER A SHIM. testkit's VideShim substituted the WHOLE of vide,
	including the pure core that never needed substituting, and its substitute was
	strictly weaker: `effect` ran once with no dependency tracking and `derive`
	did not memoise. Suites written against it could not observe a re-render at
	all — Aether's own TreeView suite had to route around it. Here `effect` IS
	vide's effect, tracking through vide's real graph.

	NOT AVAILABLE HEADLESSLY, and deliberately not faked: `mount`/`changed` (host
	rendering).

	`spring` USED to be on that list, excluded because it "needs a clock". The
	host has had one since ms-51 M16, and the module is pure arithmetic over
	`graph`, so ms-52 M3 loads it for real and lets `Host.Clock` step it. Until
	then every Flux spring settled instantly off-engine -- motion appeared to
	work, and animated nothing.
]]

local VideCore = {}

--- Candidate roots for the installed vide, newest first.
---
--- Version-pinned because pesde writes the version into the path, and the
--- redirect at `roblox_packages/vide.luau` cannot help us: it resolves through
--- `script.Parent`, which does not exist outside Roblox. A miss on any one of
--- these is caught, so an unknown version degrades to "core unavailable" rather
--- than to a broken require at module scope.
local CANDIDATE_ROOTS = {
	"../../roblox_packages/.pesde/centau_vide@0.4.1/vide/src/",
	"../../roblox_packages/.pesde/centau_vide@0.4.0/vide/src/",
	"../../../../../ui/framework/Aether/roblox_packages/.pesde/centau_vide@0.4.1/vide/src/",
	"../../../../../ui/framework/Aether/roblox_packages/.pesde/centau_vide@0.4.0/vide/src/",
}

--- The modules that load outside Roblox, verified one-per-process against 0.4.1.
--- `action` is here because it only tags a function; it never touches Instance.
local CORE_MODULES = {
	"graph",
	"source",
	"effect",
	"derive",
	"root",
	"batch",
	"untrack",
	"context",
	"switch",
	"show",
	"indexes",
	"values",
	"read",
	"action",
}

export type Core = {
	graph: any,
	source: any,
	effect: any,
	derive: any,
	root: any,
	batch: any,
	untrack: any,
	context: any,
	switch: any,
	show: any,
	indexes: any,
	values: any,
	read: any,
	action: any,
	--- vide's real spring, plus the stepper that advances every live one.
	--- nil only if the installed vide lacks the module.
	spring: any,
	update_springs: any,
}

local cached: Core? = nil
local resolvedRoot: string? = nil
local attempted = false

--- Load the reactive core, or nil when no installed vide can be reached.
---
--- Returns nil rather than erroring: a caller with no vide present should fall
--- back visibly (Headless states what it does), not die at require time in a
--- test process that may not need reactivity at all.
function VideCore.load(): Core?
	if attempted then
		return cached
	end
	attempted = true

	for _, root in ipairs(CANDIDATE_ROOTS) do
		-- `source` is the probe: if it resolves, this root is real.
		local ok, probe = pcall(require, root .. "source")
		if ok and type(probe) == "function" then
			local core: any = {}
			local complete = true
			for _, name in ipairs(CORE_MODULES) do
				local okMod, mod = pcall(require, root .. name)
				if okMod then
					core[name] = mod
				else
					complete = false
					break
				end
			end
			--- SPRING, loaded specially (ms-52 M3).
			---
			--- It was excluded with the note "needs a clock", which was true when
			--- it was written and stopped being true when the host gained one
			--- (ms-51 M16). Its module is pure arithmetic over `graph` -- no
			--- Instance, no RunService -- so the only thing it ever needed was
			--- somebody to call it every frame.
			---
			--- The module is a FACTORY returning two values: the `spring`
			--- constructor and the stepper that advances every live spring.
			--- vide's own lib.luau connects that stepper to Heartbeat; headless,
			--- the host Clock drives it instead. Same arithmetic, different frame
			--- source, which is the whole shape of this layer.
			if complete then
				local okSpring, factory = pcall(require, root .. "spring")
				if okSpring and type(factory) == "function" then
					local okCall, spring, updateSprings = pcall(factory)
					if okCall and type(spring) == "function" then
						core.spring = spring
						core.update_springs = updateSprings
					end
				end
			end

			if complete then
				resolvedRoot = root
				cached = core :: Core
				return cached
			end
		end
	end

	return nil
end

--- Which root satisfied the load, for diagnostics. nil until `load` succeeds.
function VideCore.resolvedRoot(): string?
	return resolvedRoot
end

--- Testing seam: forget the cached result so a suite can re-probe.
function VideCore._reset()
	cached = nil
	resolvedRoot = nil
	attempted = false
end

return VideCore
