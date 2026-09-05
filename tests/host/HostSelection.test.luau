--!strict
--!tier math
--[[
	WHICH HOST RAN, asserted by NAME rather than shown in pixels.

	WHY THIS SUITE EXISTS (Dew milestone 2, sprint 8)
	`Host.detect()` chooses between two hosts, and both of them draw a correct
	widget. That is the whole difficulty: "the three Aether mods still render" is
	true under either branch, so it is not evidence that either branch was taken.
	Every suite in this repository could pass with the wrong host selected, and
	the one before this could not tell you which one it had.

	So this suite asks the question directly, in three ways:

	  1. WHAT `detect` ACTUALLY RETURNED, by `Name` and by `Environment`. Under
	     lune that is the Luau test double, and saying so out loud is the point.
	  2. WHETHER THE PREDICATE IS CAPABILITY-BASED, by running it against a
	     faithful DataModel WITH NO `game` ANYWHERE. That environment is built
	     from the test double's own mock instances and lune's real value types,
	     so it is a genuine non-Roblox host, and the predicate accepting it is
	     the claim ADR-001 rests on: two implementations, one host module.
	  3. WHETHER IT IS A REAL PROBE OR A CHECKLIST, by handing it five ways of
	     being unfaithful that a name-checking predicate would wave through.

	WHAT IT CANNOT ASK. That the Roblox engine passes each clause. Aether's suites
	run under lune; only `conformance/roblox/` runs in Studio and that is a manual
	step. The clauses are argued in DataModel.luau and the sprint record names
	this as unchecked rather than assumed.
]]

local T = require("@testkit")
local Aether = require("../../src/api")
local DataModel = Aether.Host.DataModel

--- A FAITHFUL NON-ROBLOX ENVIRONMENT, assembled from parts that already exist.
---
--- Mock instances from the test double, value types from `@lune/roblox`, and a
--- `typeof` that answers "Instance" for a mock the way an engine answers for a
--- real one. It is not a DataModel anyone should ship -- it is the test double,
--- and LuauDataModel.luau spends its header saying so -- but it satisfies every
--- clause of the probe, and it does so with no `game` in the process at all.
---
--- THAT IS THE ASSERTION. If the predicate can accept this, it is not asking who
--- the vendor is.
local function faithfulEnvironment(): DataModel.Environment
	local double = Aether.Host.LuauDataModel.new()
	local V = double.Vocabulary
	return {
		Instance = double.Instance,
		typeof = double.typeof,
		UDim = V.UDim,
		UDim2 = V.UDim2,
		Vector2 = V.Vector2,
		Color3 = V.Color3,
		Rect = V.Rect,
		Enum = V.Enum,
	}
end

--- The faithful environment with one thing broken, named by what is broken.
local function bent(mutate: (DataModel.Environment) -> ()): DataModel.Environment
	local env = faithfulEnvironment()
	mutate(env)
	return env
end

--- 1 - WHAT RAN HERE ---------------------------------------------------------

local function testDetectReportsItselfByName()
	Aether.Host._reset()
	local host = Aether.Host.detect()

	--- UNDER LUNE THIS IS THE TEST DOUBLE, and the assertion says the name rather
	--- than "not the other one" so that a third host appearing would fail here
	--- rather than pass by elimination.
	assert(
		host.Name == "LuauDataModel",
		`under lune detect() must select the Luau test double, got {tostring(host.Name)}`
	)
	assert(
		host.Environment == "Luau",
		`the test double supplies its own services, got {tostring(host.Environment)}`
	)

	--- THE CLOCK SAYS IT A SECOND TIME, from a different field written by a
	--- different line. "Heartbeat" in-engine, "DewFrame" on Dew, "Simulated"
	--- here -- a mod animating against the wrong clock is invisible in a render
	--- and obvious in this string.
	assert(
		host.Clock.Name == "Simulated",
		`the simulated clock must name itself, got {tostring(host.Clock.Name)}`
	)
	Aether.Host._reset()
end

local function testTheDataModelHostIsNotAvailableHere()
	--- CORRECTLY FALSE, and worth asserting rather than assuming: lune supplies
	--- no `Instance` and no vocabulary as globals, so there is nothing here for
	--- this host to drive.
	assert(DataModel.available() == false, "lune supplies no DataModel; available() must say so")
end

--- 2 - THE PREDICATE IS A CAPABILITY TEST ------------------------------------

local function testAFaithfulNonRobloxEnvironmentPasses()
	--- THE CENTRAL CLAIM OF ADR-001, executed rather than argued. No `game`, no
	--- engine, no vendor name anywhere in the environment handed over -- and the
	--- host that used to require `typeof(game) == "Instance"` accepts it.
	assert(
		DataModel.conforms(faithfulEnvironment()) == true,
		"a faithful DataModel must be accepted with no `game` in the process"
	)
end

local function testTheOldVendorTestWouldHaveRefusedIt()
	--- THE SAME ENVIRONMENT, THROUGH THE PREDICATE THIS SPRINT REPLACED. Kept as
	--- a literal rather than described, because the whole change is the
	--- difference between these two answers about one environment.
	local old = typeof(game) == "Instance"
	assert(old == false, "lune has no `game`, so the old predicate refuses")
	assert(
		DataModel.conforms(faithfulEnvironment()) ~= old,
		"the new predicate must disagree with the old one about a faithful non-Roblox host; "
			.. "if they agree, nothing was actually changed"
	)
end

--- 3 - IT IS A PROBE, NOT A CHECKLIST ----------------------------------------

local function testAMissingVocabularyIsRefused()
	--- `InstallVocabulary` is a NO-OP on this host, so an environment without the
	--- value types leaves every `UDim2.new` in the framework nil.
	assert(
		DataModel.conforms(bent(function(env)
			env.UDim2 = nil :: any
		end)) == false,
		"an environment with no UDim2 cannot be driven by a host that installs none"
	)
	assert(
		DataModel.conforms(bent(function(env)
			env.Enum = nil :: any
		end)) == false,
		"no Enum: vide's own `defaults` module reads it at load time"
	)
end

local function testATypeofThatDoesNotAgreeWithItselfIsRefused()
	--- THE `"InstanceRef"` FAILURE, which this project has actually shipped: a
	--- plausible string rather than an error. Everything else about the
	--- environment is faithful, and a predicate that only checked `Instance.new`
	--- exists would accept it.
	assert(
		DataModel.conforms(bent(function(env)
			env.typeof = function(_value: any): string
				return "InstanceRef"
			end
		end)) == false,
		"an environment whose typeof does not call its own instances Instances is refused"
	)
end

local function testAPropertyThatDoesNotRoundTripIsRefused()
	--- THE `as_f32` FAILURE, ported into a stand-in: the write is accepted and
	--- the offsets come back zero. A tree built on this constructs, parents,
	--- names and destroys perfectly, and lays out nothing correctly.
	assert(
		DataModel.conforms(bent(function(env)
			local real = env.UDim2
			env.UDim2 = {
				new = function(xs: number, _xo: number, ys: number, _yo: number): any
					return real.new(xs, 0, ys, 0)
				end,
			}
		end)) == false,
		"an environment that drops the offsets of a UDim2 is refused"
	)
end

local function testANameThatDoesNotReadBackIsRefused()
	--- `create` writes `Name` on every node it builds and the Scene contract
	--- reads it back; a host that accepts the write and answers something else
	--- breaks every lookup in Layer 2.
	assert(
		DataModel.conforms(bent(function(env)
			local real = env.Instance
			env.Instance = {
				new = function(class: string): any
					local node = real.new(class)
					return setmetatable({}, {
						__index = function(_self: any, key: any): any
							if key == "Name" then
								return "something plausible"
							end
							return node[key]
						end,
						__newindex = function(_self: any, key: any, value: any)
							node[key] = value
						end,
					})
				end,
			}
		end)) == false,
		"an environment that does not answer with the Name it was given is refused"
	)
end

local function testAnEnvironmentThatCannotBuildATreeIsRefused()
	--- The bluntest failure, and the one a checklist-shaped predicate misses
	--- most easily: every name is present and `Instance.new` throws.
	assert(
		DataModel.conforms(bent(function(env)
			env.Instance = {
				new = function(_class: string): any
					error("no DataModel here")
				end,
			}
		end)) == false,
		"an environment whose Instance.new errors is refused rather than propagating"
	)
end

--- 4 - AND WHAT THE FRAMEWORK BUILDS WITH ------------------------------------

--- The half `Name` cannot report, and the one that was wrong for a whole sprint.
---
--- `Deps.luau` used to resolve vide by `typeof(game) == "Instance"` and hand it
--- to `Host.detect(vide)`. Two independent answers to "which DataModel am I on",
--- and the one this suite asserts was the SECOND of them: off-engine every
--- component in the framework built through the test double's `create` whatever
--- `detect` returned. Dew measured a mount reporting `Host.Name == "DataModel"`
--- over a tree of mock instances, with every suite here green.
---
--- So the host now resolves its own vide and `Deps` reads it back off the host.
--- This asserts the two are one object rather than two that happen to agree --
--- which is a claim about identity, and the only shape of assertion that a
--- second resolver could not satisfy by coincidence.
--- ASKED OF `Deps.Host` RATHER THAN OF `detect()`, and that is not a dodge.
--- `Deps` resolves the host ONCE, at require time, and `Host._reset` exists so
--- other cases in this file can re-probe -- so a later `detect()` is a different
--- object by construction and comparing against it would test the memo rather
--- than the wiring. `Deps.Host` is the host `Deps` actually built with, which is
--- the thing the claim is about.
local function testDepsBuildsWithTheResolvedHostsVide()
	local Deps = require("../../src/Deps")

	assert(
		rawequal(Deps.vide, Deps.Host.vide),
		"Deps must take vide FROM the resolved host, not resolve one of its own"
	)
	--- AND THE MEMBER EVERY COMPONENT ACTUALLY CALLS, because `Deps.vide` being
	--- right while `Deps.create` was captured from somewhere else is exactly the
	--- failure this is about.
	assert(
		rawequal(Deps.create, Deps.Host.create),
		"Deps.create must be the resolved host's create"
	)
	--- AND IT IS THE HOST THIS ENVIRONMENT SELECTS, so that "one decision" is a
	--- claim about the right decision. Under lune that is the test double.
	assert(
		Deps.Host.Name == "LuauDataModel",
		`Deps must build with the host detect() chooses here, got {tostring(Deps.Host.Name)}`
	)
end

--- vide's gate, asked of the module that reads it.
---
--- `VideCore.full` assembles the seven vide modules that sit behind
--- `local typeof = game and typeof or require "../test/mock".typeof`. Under lune
--- there is no `game`, so the honest answer is nil -- and nil rather than seven
--- require errors naming a `test/` directory the shipped artifact does not
--- contain, which is what asking the gate first buys.
local function testVideCoreRefusesTheGatedHalfWithoutTheGate()
	assert(
		(game :: any) == nil,
		"this suite's premise is that lune has no `game`; something installed one"
	)
	assert(
		Aether.Host.VideCore.full() == nil,
		"without the gate the seven gated vide modules cannot load, and full() must say so"
	)
	--- THE UNGATED SIXTEEN STILL LOAD, which is the measurement VideCore exists
	--- for and the reason the test double works here at all.
	local core = Aether.Host.VideCore.load()
	assert(core ~= nil and core.source ~= nil, "the reactive core loads without the gate")
end

T.test("detect() reports the host it chose, by name", testDetectReportsItselfByName, "math")
T.test("Deps builds with the resolved host's vide", testDepsBuildsWithTheResolvedHostsVide, "math")
T.test("VideCore refuses the gated half without `game`", testVideCoreRefusesTheGatedHalfWithoutTheGate, "math")
T.test("the DataModel host is correctly unavailable under lune", testTheDataModelHostIsNotAvailableHere, "math")
T.test("a faithful DataModel is accepted with no `game` present", testAFaithfulNonRobloxEnvironmentPasses, "math")
T.test("the predicate disagrees with the vendor test it replaced", testTheOldVendorTestWouldHaveRefusedIt, "math")
T.test("a missing value vocabulary is refused", testAMissingVocabularyIsRefused, "math")
T.test("a typeof that answers a plausible string is refused", testATypeofThatDoesNotAgreeWithItselfIsRefused, "math")
T.test("a UDim2 that loses its offsets is refused", testAPropertyThatDoesNotRoundTripIsRefused, "math")
T.test("a Name that does not read back is refused", testANameThatDoesNotReadBackIsRefused, "math")
T.test("an environment that cannot build a tree is refused", testAnEnvironmentThatCannotBuildATreeIsRefused, "math")

return T.run("HostSelection")
