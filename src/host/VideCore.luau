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
	seven it cannot reach. `Aether.Host.LuauDataModel` builds them over mock instances,
	`Aether.Host.DataModel` takes vide's own.

	AND THAT SECOND HALF IS NOT FREE OFF-ENGINE, measured on Dew 2026-09-04. The
	line quoted above reads `game and typeof or ...`, so `game` is not a NAME the
	blocked modules need -- it is the GATE they reach the four names through. With
	`game` nil the fallback require runs, `test/` is absent from the shipped
	artifact, and all seven fail to load however real the four globals are. See
	Dew's milestone 2 sprint 8 record for the measurement.

	SO A HOST THAT OPENS THE GATE CAN HAVE THEM, and `VideCore.full` below is how
	-- the same operation as `load`, over the other seven. Dew installs a truthy
	`game` for an Aether mod, for that gate and for nothing else; it is the
	boolean `true`, so it is not a DataModel and cannot be mistaken for one.
	`Host.DataModel` calls `full()` and takes `create`, `mount`, `cleanup` and
	`changed` from vide's own modules, which is what distinguishes it from the
	test double below.

	WHAT `full` DOES NOT REQUIRE IS `lib.luau`, and that is deliberate rather than
	an omission: lib.luau is vide's ROBLOX ENTRY POINT and reads the gate twice
	more than the leaves do -- `game:GetService("RunService").Heartbeat` and
	`debug.profilebegin`, neither of which exists off-engine. Assembling from the
	modules is what this file has been doing for the sixteen since ms-52.

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

--- Where the installed vide might be, in order of preference.
---
--- `@vide` FIRST, AND IT IS THE ONE THAT SCALES. The rest are relative paths
--- into this package's own `roblox_packages`, which works when Aether is the
--- thing being developed and fails the moment it is a DEPENDENCY: a consumer
--- pins this repository by commit, and `roblox_packages/` is generated, so the
--- checkout Cargo or pesde made has Aether's source and none of Aether's own
--- dependencies. Dew hit exactly that — "no installed vide reachable" from a
--- pinned checkout that was otherwise perfectly correct.
---
--- An alias makes the supply an explicit seam: a host that embeds Aether
--- installs vide wherever it likes and points `@vide` at it. Nothing here has to
--- guess a layout, and nothing has to be re-listed when a version moves.
---
--- The version-pinned paths stay for the in-repo case — Aether's own tests and
--- the CLI resolve through them — and because a miss on any candidate is caught,
--- an unknown layout degrades to "core unavailable" rather than to a broken
--- require at module scope.
local CANDIDATE_ROOTS = {
	"@vide/",
	"../../roblox_packages/.pesde/centau_vide@0.4.1/vide/src/",
	"../../roblox_packages/.pesde/centau_vide@0.4.0/vide/src/",
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

--- The seven vide leaves behind the `game` gate, which is what `VideCore.full`
--- adds to the sixteen above.
---
--- `defaults` and `implicit_effect` are not listed: they are required BY
--- `create` and `apply` rather than by anything here, so they load as a
--- consequence. `branch` is not listed for the same reason, and lib.luau does not
--- export it either -- the line is commented out in vide's own source.
local GATED_MODULES = {
	"create",
	"apply",
	"mount",
	"cleanup",
	"changed",
}

local cached: Core? = nil
local full: any = nil
local resolvedRoot: string? = nil
local attempted = false
local fullAttempted = false

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

--- THE WHOLE OF vide, ASSEMBLED FROM ITS OWN MODULES, on an environment whose
--- `game` gate is open. nil where it is not, or where no vide is reachable.
---
--- WHY THIS IS NOT `require "@vide/lib"`, which is the obvious thing and is
--- wrong. `lib.luau` is not just vide's assembly; it is vide's ROBLOX ENTRY
--- POINT, and it reads the gate twice more than the leaves do:
---
---     local stepped = game and game:GetService("RunService").Heartbeat:Connect(...)
---     if game then debug.profilebegin("VIDE STEP") end
---
--- Both are guarded by `game`, and a host that opens the gate to load `create`
--- opens them at the same time. `game:GetService` on anything that is not a
--- DataModel is an error at require time, and `debug.profilebegin` is a Roblox
--- extension the standard Luau `debug` library does not carry, so it would be an
--- error every frame. Dew's `game` is the boolean `true`, deliberately, so both
--- of those fail LOUDLY and at the line rather than being answered with silence
--- by something shaped like a service locator.
---
--- So the gate cannot be opened for lib.luau, and it does not have to be: this
--- module already exists to assemble vide out of its parts for a runtime that is
--- not the engine, and it has been doing it for the sixteen since ms-52. This is
--- the same operation over the other seven.
---
--- WHAT IS NOT SUBSTITUTED, WHICH IS THE POINT. `create`, `apply`, `mount`,
--- `cleanup` and `changed` are vide's own modules, required unmodified, building
--- real instances through the environment's real `Instance.new`. ADR-001 forbids
--- a host that supplies its own `create` -- that would be a second implementation
--- inside one host -- and this is not one. What is replaced is twenty lines of
--- table construction and a Heartbeat connection, and the frame source it
--- replaces is `Host.Clock`, which is the whole shape of this layer.
---
--- THE STEPPERS COME BACK WITH IT. `update_springs` and `update_timeouts` are
--- what lib.luau's Heartbeat drives; a host taking this table owes them a frame,
--- and `DataModel.new` subscribes them to `Host.Clock` where the environment is
--- not the engine.
function VideCore.full(): any?
	if fullAttempted then
		return full
	end
	fullAttempted = true

	--- THE GATE, ASKED BEFORE ANYTHING IS REQUIRED. Without it every module
	--- below falls through to `require "../test/mock"`, which the shipped
	--- artifact does not contain -- so the failure would arrive as seven require
	--- errors naming a directory nobody can produce, rather than as nil here.
	if not game then
		return nil
	end

	local core = VideCore.load()
	if not core then
		return nil
	end
	local root = resolvedRoot
	if not root then
		return nil
	end

	local gated: { [string]: any } = {}
	for _, name in ipairs(GATED_MODULES) do
		local ok, mod = pcall(require, root .. name)
		if not ok then
			return nil
		end
		gated[name] = mod
	end

	--- `timeout` is a factory returning the constructor and its stepper, the same
	--- shape as `spring` and `action`. It is OPTIONAL here: nothing in Aether
	--- reads `vide.timeout`, and a vide that lacks the module should still give a
	--- host `create`.
	local timeout, updateTimeouts
	local okTimeout, factory = pcall(require, root .. "timeout")
	if okTimeout and type(factory) == "function" then
		local okCall, made, stepper = pcall(factory)
		if okCall then
			timeout, updateTimeouts = made, stepper
		end
	end

	local action = core.action()

	full = {
		-- core
		root = core.root,
		mount = gated.mount,
		create = gated.create,
		source = core.source,
		effect = core.effect,
		derive = core.derive,
		switch = core.switch,
		show = core.show,
		indexes = core.indexes,
		values = core.values,

		-- util
		cleanup = gated.cleanup,
		untrack = core.untrack,
		read = core.read,
		batch = core.batch,
		context = core.context,

		-- animations
		spring = core.spring,

		-- actions
		action = action,
		changed = gated.changed,

		timeout = timeout,

		--- vide's own `apply` takes an instance and returns a prop applier; the
		--- shape is lib.luau's, kept so that a caller written against vide finds
		--- what vide documents.
		apply = function(instance: any)
			return function(props: { [any]: any })
				gated.apply(instance, props)
				return instance
			end
		end,

		--- WHAT lib.luau'S HEARTBEAT WOULD HAVE DRIVEN. Exposed rather than
		--- connected, because this module does not know what a frame is; the host
		--- that took this table does.
		update_springs = core.update_springs,
		update_timeouts = updateTimeouts,
	}
	return full
end

--- Which root satisfied the load, for diagnostics. nil until `load` succeeds.
function VideCore.resolvedRoot(): string?
	return resolvedRoot
end

--- Testing seam: forget the cached result so a suite can re-probe.
function VideCore._reset()
	cached = nil
	full = nil
	resolvedRoot = nil
	attempted = false
	fullAttempted = false
end

return VideCore
