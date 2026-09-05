--!strict
--[[
	Aether · host/DataModel — Layer 2.5 resolver for a host that provides a
	DataModel.

	RENAMED FROM `Roblox.luau` on 2026-09-04. ADR-001's own consequences list
	asked for it in as many words:

	    `src/host/Roblox.luau` becomes a misnomer. It is the DataModel host, and
	    Roblox is one environment providing that model. Worth renaming in Aether
	    before a second implementation makes the name actively misleading.

	THERE IS NO DEW HOST AND THERE NEVER WILL BE. ADR-001 forbids one outright —
	"No Dew branch, no third host, no adapter" — and argues it with the browser
	analogy: Ark UI has no Chrome adapter and no Firefox adapter, because a
	headless framework resolves onto a STANDARD rather than onto a vendor. There
	are two hosts in this directory. This one drives a real DataModel wherever it
	finds one; LuauDataModel.luau is a test double for when there is none.

	WHAT IS ACTUALLY ENVIRONMENT-SPECIFIC IN HERE, measured rather than assumed:
	two service lookups, and nothing else. `create`, `cleanup`, `mount`,
	`Instance`, `typeof`, the Scene contract and `Resolve` are all written against
	a DataModel and were never written against Roblox. So the two lookups moved
	behind `Host.Text` and `Host.Clock` — seams the `Host` interface has declared
	all along — and they are the only place below that names an environment.

	WHY `Resolve` MATTERS. Layer 2 (hit-testing, scope arbitration, floating
	placement) needs one question answered — "where is this thing, how deep is
	it, is it visible" — and today every call site asks the HOST directly, by
	reading `AbsolutePosition`/`AbsoluteSize` off a GuiObject. That is the single
	coupling that stops those algorithms from running anywhere else. `Resolve`
	turns a concrete host target into an abstract `GeometrySource`, so a Layer 2
	algorithm can be written against the contract instead of against a host.

	HitTest.luau already half-discovered this: its `cornerRadiusOf` guards the
	`FindFirstChildOfClass` call because "not every caller hands us a real
	Instance — the InputScope and PointerRouter suites pass minimal stand-ins with
	only the geometry fields". Those stand-ins ARE a GeometrySource, invented
	locally and unnamed. This gives them a name.

	NOT YET DONE, and the honest state of it: HitTest, PointerRouter, InputScope
	and useFloating still read the host inline. Migrating them onto `Resolve`
	is the follow-on — this file establishes the contract and the DataModel
	implementation of it, it does not yet reroute those consumers.
]]

local TextModule = require("./Text")
local VideCore = require("./VideCore")

local DataModel = {}

export type Bounds = { X: number, Y: number, Width: number, Height: number }

export type GeometrySource = {
	GetBounds: () -> Bounds,
	GetZIndex: () -> number,
	IsVisible: () -> boolean,
}

-- ---- THE TWO HOST SERVICES, AND THE ONLY ENVIRONMENT BRANCH IN THIS FILE ----
--
-- Text metrics and a frame clock are the two things this host cannot compute for
-- itself, and they are the two things the DataModel does not carry: an instance
-- tree says nothing about how wide a string is in the face that will draw it, or
-- about when the next frame begins. Every other capability below is asked of the
-- DataModel and answered by it.
--
-- WHETHER A CONFORMING HOST MUST SUPPLY THESE IS AN OPEN QUESTION ON THE
-- STANDARD, flagged in Dew's milestone 2 sprint 7 record with a recommendation of
-- yes. Until it is answered they are resolved here by asking each environment for
-- its own spelling — which is why the two lookups are confined to this block and
-- named after the environment rather than smeared through `new`.
--
-- `game` AND `DewHost` NAME AN ENVIRONMENT, AND THAT IS A DIFFERENT QUESTION
-- FROM THE ONE `available` ASKS. "Where do I obtain a text measurer" is
-- legitimately answered by knowing which environment this is. "Is the DataModel
-- under me faithful" is not, and answering it by looking for one vendor's global
-- is what ADR-001's conformance test used to do.

export type Services = {
	--- Which environment supplied these, for a log line or an assertion. NOT the
	--- host's name: the host is the same host either way, which is the point.
	Environment: string,
	--- `(text, size, font?) -> (width, height)`, synchronous by contract.
	Measure: (text: string, size: number, font: string?) -> (number, number),
	Clock: any,
}

--- ROBLOX: `TextService` and `RunService`, exactly as this file always did.
---
--- `GetTextSize` is SYNCHRONOUS and exact, which is the whole reason the contract
--- is shaped this way: layout runs inside a frame and cannot await. The bundled
--- advance table in Text.luau is never consulted here.
---
--- ONE Heartbeat connection, made lazily, for N listeners. Subscribing costs
--- nothing until something actually animates, and the listener list is
--- snapshotted per frame because a listener may dispose itself, or a sibling,
--- mid-frame. That is the property flux_motion existed to guarantee (ms-51 M16).
local function robloxServices(): Services?
	if typeof(game) ~= "Instance" then
		return nil
	end

	local TextService = game:GetService("TextService")
	local RunService = game:GetService("RunService")

	local frameListeners: { (dt: number) -> () } = {}
	local heartbeat: RBXScriptConnection? = nil

	return {
		Environment = "Roblox",

		Measure = function(text: string, size: number, _font: string?): (number, number)
			--- A very large frame, because we are asking for the string's NATURAL
			--- size rather than how it wraps into a box. A caller that wants
			--- wrapping asks about a box it already has.
			local bounds =
				TextService:GetTextSize(text, size, Enum.Font.SourceSans, Vector2.new(1e6, 1e6))
			return bounds.X, bounds.Y
		end,

		Clock = {
			Name = "Heartbeat",

			OnFrame = function(fn: (dt: number) -> ()): () -> ()
				table.insert(frameListeners, fn)
				if not heartbeat then
					heartbeat = RunService.Heartbeat:Connect(function(dt: number)
						-- Snapshot: a listener may dispose itself, or a sibling,
						-- mid-frame.
						local batch = table.clone(frameListeners)
						for _, listener in ipairs(batch) do
							listener(dt)
						end
					end)
				end
				return function()
					local i = table.find(frameListeners, fn)
					if i then
						table.remove(frameListeners, i)
					end
				end
			end,

			Now = function(): number
				return os.clock()
			end,

			--- In-engine the Heartbeat drives frames; stepping by hand would run
			--- them TWICE. Present so callers need not branch on environment.
			Step = function(_dt: number) end,
		},
	}
end

--- DEW: the `DewHost` global its milestone 2 sprint 7 installs for every guest.
---
--- IT ALREADY HAS THE SHAPE THIS INTERFACE ASKS FOR, which is not a coincidence —
--- it was built against `Host.Text` and `Host.Clock`. `OnFrame` returns a
--- disposer and multiplexes N listeners over one host subscription, so the
--- Heartbeat property above holds here too without this file arranging it.
---
--- `Step` IS SUPPLIED HERE AND IS DELIBERATELY ABSENT THERE. Dew drives its own
--- frames, so a `Step` a guest could call would be a way to run every frame
--- twice — which is exactly why the engine's is an empty function rather than a
--- missing one. Dew's `services.rs` asserts `DewHost.Clock.Step` is nil for that
--- reason and names this line as where the interface member gets filled.
local function dewServices(): Services?
	--- READ AS A PLAIN GLOBAL, NOT THROUGH `_G`, and the distinction is not
	--- cosmetic. In Roblox `_G` is a table scripts SHARE; it is not the
	--- environment they run in, so `_G.UDim2` is nil in the engine. Under Luau
	--- everywhere else the two happen to be the same table -- which is precisely
	--- how a predicate written against `_G` passes every test that can be run
	--- from here and answers false on the one host it must answer true on.
	local dew: any = DewHost
	if type(dew) ~= "table" or type(dew.Text) ~= "table" or type(dew.Clock) ~= "table" then
		return nil
	end

	return {
		Environment = "Dew",
		Measure = dew.Text.Measure,
		Clock = {
			Name = dew.Clock.Name,
			OnFrame = dew.Clock.OnFrame,
			Now = dew.Clock.Now,
			Step = function(_dt: number) end,
		},
	}
end

--- ROBLOX FIRST, because it is the reference implementation of the standard and
--- an environment answering to both would be a conflict worth resolving towards
--- the engine. They are mutually exclusive today: `game` is nil on Dew, `DewHost`
--- is nil in-engine.
local PROVIDERS: { () -> Services? } = { robloxServices, dewServices }

local function resolveServices(): Services?
	for _, provider in ipairs(PROVIDERS) do
		local services = provider()
		if services then
			return services
		end
	end
	return nil
end

-- ---- THE CONFORMANCE PROBE -------------------------------------------------
--
-- ADR-001 made `available()` the conformance test itself, and it was one line:
--
--     return typeof(game) == "Instance"
--
-- The substance of that claim survives -- one host module, two environments, and
-- either the same code runs or the DataModel is not faithful yet. What changed on
-- 2026-09-04 is that the predicate tests FAITHFULNESS rather than testing for one
-- vendor's global, because a framework claiming to run on any conforming host
-- should not decide by looking for the name of one of them.
--
-- IT IS A PROBE AND NOT A CHECKLIST, which is the design decision worth stating.
-- The alternative was a list of names to look for, and a list of names is exactly
-- what the old line was: a shorter one. What a host has to do here is BEHAVE, and
-- the only way to ask that is to build something and read it back.
--
-- WHAT IT DELIBERATELY DOES NOT DECIDE: what the standard requires. This is one
-- framework's account of what it needs to run, arrived at by asking what breaks
-- without each clause; the standard is Dew's `docs/datamodel_scope.md` and
-- Aether's `conformance/`, and neither has a section on what a host must be
-- before a framework will consent to drive it. That section is owed, this
-- predicate is the proposal for it, and the sprint record carries the argument.
--
-- THIS PREDICATE HAS NOT BEEN RUN IN THE ENGINE. `conforms` below is exercised
-- from a suite against a faithful stand-in and against five ways of being
-- unfaithful, so the LOGIC is measured; what is argued rather than measured is
-- that the Roblox engine passes each clause. Aether's 33 suites run under lune,
-- and only `conformance/roblox/` runs in Studio -- a manual step. Clause 4 in
-- particular asserts an engine behaviour this repository cannot execute.

local PROBE_CLASS = "Frame"
local PROBE_NAME = "AetherConformanceProbe"

--- What the probe is handed, so that it can be run against an environment this
--- process is not in.
---
--- SIX OF THE ELEVEN NAMES `Host.Vocabulary` declares, plus the two that make a
--- tree. The sequence types are a gradient feature and no component needs one to
--- mount; `Font` is reached through `Enum` here. `Enum` is on the list because
--- vide's own `defaults` module reads it at LOAD time, so an environment without
--- it cannot load `create` at all -- which is a failure that arrives as a
--- require error from inside a dependency rather than as anything this framework
--- can explain.
export type Environment = {
	Instance: any,
	typeof: (any) -> string,
	UDim: any,
	UDim2: any,
	Vector2: any,
	Color3: any,
	Rect: any,
	Enum: any,
}

--- Run the probe against a supplied environment.
---
--- SEPARATED FROM `available` SO IT CAN BE TESTED, and that is not a convenience.
--- Every clause below describes an engine behaviour, Aether's suites run under
--- lune, and `conformance/roblox/` is a manual step -- so a predicate that could
--- only be exercised through the globals of the process running it would be
--- argued and never executed. Handed an environment, it can be run against a
--- faithful stand-in AND against each way of being unfaithful, here, in CI.
---
--- WHAT IT ASKS, and every clause is here because this host breaks on an
--- environment that fails it:
---
---   1. `Instance.new` constructs something `typeof` calls an Instance. BOTH
---      HALVES ARE THE TEST: an environment that constructs a thing and then
---      describes it as something else does not agree with itself, and this
---      project has already shipped a `typeof` answering "InstanceRef" -- a
---      plausible string rather than an error.
---   2. It knows its own class, and it answers with the name it was given rather
---      than with something plausible. `create` writes `Name` on every node it
---      builds and the Scene contract reads it back.
---   3. It parents, it answers BY NAME, and it tears down. `create` builds a
---      tree, `cleanup` destroys one, and `Resolve` walks one.
---   4. A property round-trips through the value vocabulary WITH ITS NUMBERS
---      INTACT. Dew's own history is the argument: `as_f32` refused an integer,
---      so every literal offset in every `UDim2` was zero, and no test noticed
---      because none set a numeric property. A host that accepts a write and
---      stores something else passes clauses 1 to 3 and lays out nothing
---      correctly.
---
--- WHAT IT DELIBERATELY DOES NOT ASK FOR: text metrics, or a frame clock. Those
--- are resolved by the seam above and they are not part of the standard today;
--- putting them in this predicate would settle a question sprint 7 flagged and
--- left open. When that question is answered yes, this is where the two clauses
--- belong, and adding them is the amendment rather than a quiet widening here.
function DataModel.conforms(env: Environment): boolean
	if
		env.Instance == nil
		or env.typeof == nil
		or env.UDim == nil
		or env.UDim2 == nil
		or env.Vector2 == nil
		or env.Color3 == nil
		or env.Rect == nil
		or env.Enum == nil
	then
		return false
	end

	local ok, faithful = pcall(function(): boolean
		-- 1
		local node = env.Instance.new(PROBE_CLASS)
		if env.typeof(node) ~= "Instance" then
			return false
		end
		-- 2
		if node.ClassName ~= PROBE_CLASS then
			return false
		end
		node.Name = PROBE_NAME
		if node.Name ~= PROBE_NAME then
			return false
		end
		-- 3
		if node.Parent ~= nil then
			return false
		end
		local child = env.Instance.new(PROBE_CLASS)
		child.Name = PROBE_NAME
		child.Parent = node
		if child.Parent ~= node or node:FindFirstChild(PROBE_NAME) ~= child then
			return false
		end
		--- 4. Both halves of both axes, and a NEGATIVE offset, because a host
		---    that clamps or truncates is the failure this clause exists for.
		child.Size = env.UDim2.new(0.5, 4, 0.25, -2)
		local size = child.Size
		if size.X.Scale ~= 0.5 or size.X.Offset ~= 4 then
			return false
		end
		if size.Y.Scale ~= 0.25 or size.Y.Offset ~= -2 then
			return false
		end
		node:Destroy()
		return true
	end)

	return ok and faithful == true
end

--- Does the environment this process is actually in supply a DataModel this host
--- can drive?
---
--- PLAIN GLOBAL READS, ONE PER NAME, for the `_G` reason spelled out above: a
--- loop over a table of names has to index SOMETHING, and the only thing to
--- index in Roblox is the shared table rather than the environment. Eight lines
--- that cannot be wrong beat a loop that can.
---
--- NOT MEMOISED. `Host.detect` memoises the host it builds and `Host._reset`
--- exists so a suite can ask again; a cache here would outlive that seam. The
--- probe builds two instances and destroys them, which is cheaper than the host
--- it gates.
function DataModel.available(): boolean
	return DataModel.conforms({
		Instance = Instance,
		typeof = typeof,
		UDim = UDim,
		UDim2 = UDim2,
		Vector2 = Vector2,
		Color3 = Color3,
		Rect = Rect,
		Enum = Enum,
	})
end

--- The eleven names `Host.Vocabulary` declares, and the members of each that
--- this framework or a mod written against it actually calls.
---
--- ASSERTED BECAUSE THIS HOST INSTALLS NOTHING. `InstallVocabulary` here is
--- `function() end` -- what a host says when the environment already supplies the
--- vocabulary -- so a missing member is not a member this host could have
--- provided and did not. It is a hole in the ENVIRONMENT that nothing else on
--- this path will notice: `available()` asks for six of the names and asks
--- nothing about their members, so an environment carrying a `Color3` without
--- `fromHex` passes the probe, is selected, and produces a nil index inside a
--- component several hundred milliseconds later.
---
--- That is not hypothetical. Dew's vocabulary had `new` and `fromRGB` and not
--- `fromHex`, `fromHex` has 17 call sites in Dew's own mods and 5 in this
--- framework, and the symptom was three mods that stopped loading with an error
--- naming a theme file. This list turns that into one sentence at mount, naming
--- the member and the host.
local REQUIRED_VOCABULARY: { { name: string, members: { string } } } = {
	{ name = "UDim", members = { "new" } },
	{ name = "UDim2", members = { "new", "fromScale", "fromOffset" } },
	{ name = "Vector2", members = { "new", "zero", "one" } },
	{ name = "Color3", members = { "new", "fromRGB", "fromHex", "fromHSV" } },
	{ name = "Rect", members = { "new" } },
	{ name = "Font", members = { "new" } },
	{ name = "NumberSequence", members = { "new" } },
	{ name = "NumberSequenceKeypoint", members = { "new" } },
	{ name = "ColorSequence", members = { "new" } },
	{ name = "ColorSequenceKeypoint", members = { "new" } },
	{ name = "Enum", members = {} },
}

--- The first missing `Type.member`, or nil when the vocabulary is complete.
local function missingVocabulary(vocabulary: any): string?
	for _, entry in ipairs(REQUIRED_VOCABULARY) do
		local value = vocabulary[entry.name]
		if value == nil then
			return entry.name
		end
		for _, member in ipairs(entry.members) do
			--- pcall, because a value type may be userdata whose metatable
			--- errors on an unknown key rather than answering nil.
			local ok, got = pcall(function()
				return (value :: any)[member]
			end)
			if not ok or got == nil then
				return `{entry.name}.{member}`
			end
		end
	end
	return nil
end

--- Build the host. Errors rather than degrading, because a silent degrade is how
--- a host-only path ends up "passing" in a Lune suite that was never exercising
--- it.
---
--- `vide` IS OPTIONAL, AND SINCE 2026-09-04 NOBODY PASSES IT. `Deps.luau` used to
--- resolve vide first -- by `typeof(game) == "Instance"` -- and hand it here, so
--- there were two independent answers to "which DataModel am I on" and this one
--- was the second. Off-engine that meant every component built through the test
--- double's `create` whatever `Host.detect` returned: the host name said
--- `DataModel` and the tree underneath was mock instances. The parameter stays
--- for a caller that has a vide in hand -- Roblox's `Deps` still does -- and the
--- host resolves its own when it does not.
function DataModel.new(vide: any?): any
	if not DataModel.available() then
		error(
			"Aether.Host.DataModel requires an environment providing a conforming DataModel; "
				.. "use Aether.Host.LuauDataModel where there is none.",
			2
		)
	end
	if vide == nil then
		vide = VideCore.full()
	end
	if type(vide) ~= "table" then
		error(
			"Aether.Host.DataModel found a conforming DataModel and no vide to drive it with. "
				.. "On Roblox `roblox_packages/vide` supplies it; elsewhere VideCore assembles "
				.. "it from the installed package, which needs a truthy `game` for vide's own "
				.. "gate and a reachable `@vide`.",
			2
		)
	end

	--- BEFORE THE SURFACE, for the same reason the services check is. A member
	--- missing here is missing everywhere, because this host installs none.
	local missing = missingVocabulary({
		UDim = UDim,
		UDim2 = UDim2,
		Vector2 = Vector2,
		Color3 = Color3,
		Rect = Rect,
		Font = Font,
		NumberSequence = NumberSequence,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		Enum = Enum,
	})
	if missing then
		error(
			`Aether.Host.DataModel: this environment's value vocabulary is missing \`{missing}\`. `
				.. "This host installs no vocabulary of its own -- `InstallVocabulary` is a no-op "
				.. "here, because a host providing a DataModel is expected to define these -- so "
				.. "the gap cannot be filled in from the framework, and a partial vocabulary is "
				.. "worse than none: it passes `available()` and fails at a call site.",
			2
		)
	end

	--- BEFORE ANY OF THE SURFACE BELOW, because a host that cannot measure text
	--- cannot lay out and a host that cannot see frames cannot animate. Both
	--- seams are named in the message: an environment supplying one and not the
	--- other is worth telling apart from one supplying neither.
	local services = resolveServices()
	if not services then
		error(
			"Aether.Host.DataModel found a conforming DataModel but no host services: "
				.. "`Host.Text` needs a synchronous measurer and `Host.Clock` needs a frame "
				.. "source, and this environment offers neither `TextService`/`RunService` "
				.. "nor a `DewHost` global.",
			2
		)
	end

	local host: any = {}

	--- THE HOST IS NAMED FOR WHAT IT DRIVES, not for where it is running. Which
	--- environment supplied the two services is `host.Environment`, and the clock
	--- says it a second time in `host.Clock.Name` — "Heartbeat" in-engine,
	--- "DewFrame" on Dew, "Simulated" under LuauDataModel. A suite that wants to
	--- know which branch ran asserts one of those rather than looking at pixels.
	host.Name = "DataModel"
	host.Environment = services.Environment

	--- THE vide THIS HOST RESOLVED, so that a caller needing the module rather
	--- than the surface takes it from the host instead of resolving a second one.
	--- `Deps.luau` is that caller, and it is the inversion: the host decides which
	--- DataModel this is, and the vide follows from the host rather than the host
	--- being told about a vide chosen some other way.
	host.vide = vide

	-- ---- Layers 2 and 2.5 both come straight from vide here ----
	host.source = vide.source
	host.derive = vide.derive
	host.effect = vide.effect
	host.root = vide.root
	host.batch = vide.batch
	host.untrack = vide.untrack
	host.read = vide.read
	host.switch = vide.switch
	host.show = vide.show
	host.indexes = vide.indexes
	host.values = vide.values
	host.context = vide.context
	host.action = vide.action
	host.create = vide.create
	host.cleanup = vide.cleanup
	host.spring = vide.spring
	host.mount = vide.mount
	host.changed = vide.changed

	-- ---- Host services, from the seam resolved above ----

	--- TEXT METRICS, THROUGH `Text.SetProvider` RATHER THAN AROUND IT.
	---
	--- The provider seam is where the measured-string cache lives, so a host that
	--- assigned `host.Text` a bare function would take the cache away from every
	--- caller — 82 nodes measured at least twice a frame on the shop screen, and
	--- almost always to the same answer. `Text.luau` is the module either way;
	--- what changes per environment is only who answers.
	---
	--- OWNED BY THE ENVIRONMENT THAT SUPPLIED IT, so the diagnostic says which. It
	--- was hard-coded "engine" when this file could only be the engine.
	TextModule.SetProvider(services.Measure, string.lower(services.Environment))

	host.Text = TextModule

	host.Instance = Instance

	--- A no-op: an environment that satisfies `available()` already defines every
	--- one of these as a global, and overwriting them would be strictly worse than
	--- leaving them alone. Present so a host program can call it unconditionally
	--- (ms-52 M5), and clause 5 of the probe is what makes it safe.
	---
	--- THIS IS THE LINE THAT PUTS THE VOCABULARY ON THE ENVIRONMENT, and the
	--- `missingVocabulary` check above is its other half. A host that installs
	--- nothing is a host whose environment must be complete, and the failure mode
	--- of "complete enough to be selected, incomplete at a call site" is what that
	--- check exists to convert into a sentence.
	host.InstallVocabulary = function() end

	host.typeof = typeof

	--- THE CLOCK (ms-51 M16).
	---
	--- Motion needs "advance one frame", and that is the last purely temporal
	--- coupling in the stack: spektr/flux_motion held a single guarded
	--- `RunService.Heartbeat` connection and a `_StepForTest` beside it, so time
	--- was already isolated — it just was not owned by anything that could swap it.
	--- The environment supplies the frame source; this file supplies the interface.
	host.Clock = services.Clock

	--- AND vide'S OWN STEPPERS GET A FRAME, WHERE NOBODY ELSE IS GIVING THEM ONE.
	---
	--- On Roblox `lib.luau` connects `update_springs` and `update_timeouts` to
	--- Heartbeat itself, so the vide obtained there arrives already driven and
	--- exposes no stepper to drive. A vide assembled by `VideCore.full` does not:
	--- it deliberately leaves out lib.luau's Heartbeat connection, because that
	--- line reads `game:GetService` and this environment's `game` is not a
	--- DataModel. So the frame source that would have driven them is `Host.Clock`,
	--- which is the same substitution the rest of this file makes.
	---
	--- WHAT IT COSTS TO FORGET is not an error, it is springs that never move --
	--- `Motion.HasSpringDriver()` answers true, every smoothed value snaps to its
	--- target on the frame it changed, and the UI looks wired up and animates
	--- nothing. That exact failure is recorded in LuauDataModel.luau, which is why
	--- the presence of `update_springs` is what decides this rather than the
	--- environment's name.
	if type(vide.update_springs) == "function" or type(vide.update_timeouts) == "function" then
		local springs, timeouts = vide.update_springs, vide.update_timeouts
		host.Clock.OnFrame(function(dt: number)
			--- SPRINGS FIRST, before anything that reads them this frame. vide's
			--- own lib.luau orders them the same way and for the same reason.
			if springs then
				springs(dt)
			end
			if timeouts then
				timeouts(dt)
			end
		end)
	end

	--- THE VALUE VOCABULARY (ms-51 M16).
	---
	--- es9: these should have a single interface regardless of host. On a host
	--- providing a DataModel that interface is satisfied by the environment's own
	--- globals — same objects, same identity, zero indirection cost. What the
	--- indirection buys is that nothing above Layer 2.5 has to NAME them.
	host.Vocabulary = {
		UDim = UDim,
		UDim2 = UDim2,
		Vector2 = Vector2,
		Color3 = Color3,
		Rect = Rect,
		NumberSequence = NumberSequence,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		Font = Font,
		Enum = Enum,
	}

	host.classOf = function(node: any): string?
		if typeof(node) == "Instance" then
			return node.ClassName
		end
		if type(node) == "table" then
			return (node :: any)._ClassName
		end
		return nil
	end

	--- WHERE A SOLVED RECTANGLE GOES, and it is not into `Position` and `Size`.
	---
	--- This used to be
	---
	---     target.Position = UDim2.fromOffset(x, y)
	---     target.Size = UDim2.fromOffset(width, height)
	---
	--- described as "contract parity with LuauDataModel", on the reasoning that a
	--- caller asking to set bounds on a real Frame wants the element moved. THERE
	--- IS NO SUCH CALLER. `Live.luau`'s `commitLayout` is the only thing in this
	--- framework that calls `SetBounds`, and what it is doing is stated in its own
	--- comment: in Roblox the engine writes `AbsolutePosition`/`AbsoluteSize` after
	--- laying out and everything downstream reads them back, so off-engine the
	--- solver has to write its answer somewhere `Scene.Bounds` will find it. That
	--- is a report of an OUTPUT. `Position` and `Size` are the solver's INPUTS.
	---
	--- Writing the one into the other is a feedback loop, and on Dew it ran:
	--- each frame the solver read a Position it had itself written as an absolute
	--- offset, added the parent's offset again, and wrote a larger one. Measured
	--- on `mods/timetracker` -- a label walking 286 pixels right and 16 down per
	--- frame, a readout drifting 19 up, at 305 repainted frames a second on a
	--- widget that was doing nothing. It survived every test in both repositories
	--- because nothing off-engine had ever driven this host before.
	---
	--- A TABLE BESIDE THE TREE, NOT A WRITE INTO IT. `AbsolutePosition` and
	--- `AbsoluteSize` are read-only on a conforming host, correctly -- they are
	--- what the layout owner computed, and here the layout owner is this
	--- framework. So the answer is recorded here and `Scene.Bounds` prefers it,
	--- which needs no host permission and invents no host API.
	---
	--- ON ROBLOX THIS TABLE STAYS EMPTY, and that is not a special case: nothing
	--- calls `SetBounds` in the engine, because `Live.Session` is the session a
	--- host opens when there is NO engine. `Scene.Bounds` falls through to the
	--- environment's own properties there, exactly as before.
	---
	--- WEAK KEYS, so a discarded subtree does not pin its rectangle for the life
	--- of the process -- the same reason `Live.luau`'s own node ids are weak. That
	--- this works at all depends on the environment handing back ONE object per
	--- instance: a host that built a fresh handle per read would make every entry
	--- unreachable the moment it was written. Dew's DataModel does, the engine
	--- does, and Aether's probe does not currently ask for it.
	local solvedBounds: { [any]: { number } } = setmetatable({}, { __mode = "k" }) :: any

	host.SetBounds = function(target: any, x: number, y: number, width: number, height: number)
		solvedBounds[target] = { x, y, width, height }
	end

	--- THE SCENE CONTRACT (ms-51 M16 part 3) — the questions Layer 2 asks about a
	--- node, answered without Layer 2 naming the engine.
	---
	--- STATELESS FUNCTIONS OVER A RAW TARGET, not a wrapper object per node. That
	--- is deliberate and it is a performance decision, not a style one: hit-testing
	--- runs over every candidate on every pointer move, and `Resolve`-style
	--- wrappers would allocate a table per node per query. A previous measurement
	--- in this repo took a hot tree walk from 121ns to 65ns per visit purely by
	--- removing a table per node — same shape, same cost. `Bounds` returns four
	--- numbers rather than a rectangle for the same reason.
	---
	--- TOLERANT OF STAND-INS. HitTest already notes that "not every caller hands us
	--- a real Instance — the InputScope and PointerRouter suites pass minimal
	--- stand-ins with only the geometry fields". Those stand-ins were an unnamed
	--- GeometrySource all along; every accessor here degrades to a sensible answer
	--- rather than erroring on one.
	local function isInstance(target: any): boolean
		return typeof(target) == "Instance"
	end

	host.Scene = {
		--- DEAD, AND LEFT ALONE DELIBERATELY. `Host.Scene` declares `Name` twice --
		--- once as a string and once as `(target) -> string?` -- and the function
		--- below wins, here and in LuauDataModel.luau alike. Fixing it is a change
		--- to the `Scene` type that belongs in both hosts at once, and this sprint
		--- deliberately keeps its diff on the load-bearing file small.
		Name = "DataModel",

		--- THE SCROLLABLE EXTENT of a node's content (ms-53 D8).
		---
		--- `AbsoluteCanvasSize` is a Roblox property, so spektr/scrollbar read it
		--- directly and got `{0, 0}` in every headless host -- the mock sets it once
		--- at construction and nothing updates it, deliberately, because the HOST is
		--- supposed to report it rather than have application code write it and be
		--- believed. Nothing ever connected the reporting.
		---
		--- The visible consequence: `canvas.Y > viewport.Y` decides whether a
		--- scrollbar is shown at all, so the shop's bar -- track, thumb and steppers
		--- -- rendered in Roblox and was invisible in the native window. es9 found
		--- it and asked the right question: is this not owned by the Scrollbar
		--- component? It is. It was reading the engine instead of the host.
		CanvasExtent = function(target: any): (number, number)
			local canvas = (target :: any).AbsoluteCanvasSize
			if not canvas then
				return 0, 0
			end
			return canvas.X, canvas.Y
		end,

		--- THE SOLVED RECTANGLE FIRST, THE ENVIRONMENT'S SECOND. See `SetBounds`:
		--- an entry exists only where this framework laid the node out itself,
		--- which is only off-engine, so in the engine this reads exactly what it
		--- always read.
		Bounds = function(target: any): (number, number, number, number)
			local solved = solvedBounds[target]
			if solved then
				return solved[1], solved[2], solved[3], solved[4]
			end
			local pos = target.AbsolutePosition
			local size = target.AbsoluteSize
			return pos.X, pos.Y, size.X, size.Y
		end,

		--- Raw property read, for a LAYOUT solver rather than a hit test. In-engine
		--- the layout system has already run, so this is mostly of use to a host
		--- that must solve it itself — but the contract is the same either way.
		Raw = function(target: any, key: string): any
			local ok, value = pcall(function()
				return (target :: any)[key]
			end)
			return if ok then value else nil
		end,

		Children = function(target: any): { any }
			if isInstance(target) then
				return target:GetChildren()
			end
			return {}
		end,

		ClassOf = function(target: any): string?
			if isInstance(target) then
				return target.ClassName
			end
			return (target :: any)._ClassName
		end,

		Name = function(target: any): string?
			return (target :: any).Name
		end,

		ZIndex = function(target: any): number
			return target.ZIndex or 1
		end,

		IsVisible = function(target: any): boolean
			return target.Visible ~= false
		end,

		Parent = function(target: any): any
			return target.Parent
		end,

		--- Declaration order within the parent. Under ZIndexBehavior.Sibling this
		--- is the tie-break when two siblings share a ZIndex.
		ChildIndex = function(target: any): number
			local parent = target.Parent
			if not parent or not isInstance(parent) then
				return 0
			end
			for i, child in ipairs(parent:GetChildren()) do
				if child == target then
					return i
				end
			end
			return 0
		end,

		--- Does this container clip what it contains?
		---
		--- ScrollingFrame and CanvasGroup clip regardless of the ClipsDescendants
		--- flag — a ScrollingFrame with it off still bounds its canvas, and a
		--- CanvasGroup renders its subtree to a texture the size of itself.
		Clips = function(target: any): boolean
			if isInstance(target) then
				if target:IsA("ScrollingFrame") or target:IsA("CanvasGroup") then
					return true
				end
			end
			return target.ClipsDescendants == true
		end,

		--- Is this the root of a render layer (a LayerCollector)?
		IsLayerRoot = function(target: any): boolean
			return isInstance(target) and target:IsA("LayerCollector")
		end,

		--- Is this a node Layer 2 should walk at all? Everything above a
		--- GuiObject chain is somebody else's tree.
		IsSurface = function(target: any): boolean
			if isInstance(target) then
				return target:IsA("GuiObject")
			end
			--- A stand-in with a rectangle IS a surface, which is the whole point
			--- of the contract.
			return type(target) == "table" and target.AbsolutePosition ~= nil
		end,

		DisplayOrder = function(target: any): number
			return target.DisplayOrder or 0
		end,

		IsEnabled = function(target: any): boolean
			return target.Enabled ~= false
		end,

		Attribute = function(target: any, name: string): any
			local get = (target :: any).GetAttribute
			if type(get) ~= "function" then
				return nil
			end
			local ok, value = pcall(get, target, name)
			return if ok then value else nil
		end,

		--- The RENDERED corner, as scale and offset. nil when the element draws
		--- square corners. Kept here rather than in Layer 2 because finding it
		--- means knowing about UICorner, which is an engine class; the clamping
		--- math on top of it stays in HitTest, which is where the rule lives.
		RenderedCorner = function(target: any): (number?, number?)
			local find = (target :: any).FindFirstChildOfClass
			if type(find) ~= "function" then
				return nil, nil
			end
			local ok, corner = pcall(find, target, "UICorner")
			if not ok or not corner then
				return nil, nil
			end
			local r = corner.CornerRadius
			return r.Scale, r.Offset
		end,
	}

	--- The Layer 2.5 contract: an abstract rectangle for a concrete GuiObject.
	---
	--- Reads live on every call rather than caching: `AbsolutePosition` changes
	--- whenever anything in the ancestor chain moves, and a cached rectangle is
	--- exactly the stale-geometry class that ms-43 M20 was about.
	host.Resolve = function(target: any): GeometrySource
		return {
			GetBounds = function(): Bounds
				local pos = target.AbsolutePosition
				local size = target.AbsoluteSize
				return { X = pos.X, Y = pos.Y, Width = size.X, Height = size.Y }
			end,
			GetZIndex = function(): number
				return target.ZIndex or 1
			end,
			IsVisible = function(): boolean
				return target.Visible ~= false
			end,
		}
	end

	return host
end

return DataModel
