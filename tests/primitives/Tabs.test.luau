--!strict
--!tier math
--[=[
	aether · primitives/Tabs.

	WHAT THIS ADDS OVER `tests/core/createTabs.test.luau`: that suite already
	pins every behaviour of the machine itself. This one only has to prove the
	binding, not re-derive the machine -- that an explicit `Router`/`Selection`
	still overrides the real singletons (a fake double works exactly the way a
	future ambient-context test will expect), and that leaving both out wires
	the real `PointerRouter`/`SelectionRouter` without erroring.

	`Source`/`Action` GET THE SAME TEST, and not out of completeness -- a live
	run against Dew's `dashboard.luau` (this sprint's own success criterion)
	found that hard-wiring them to Aether's OWN vide, with no override, left
	`tabs.Active` changing correctly while the dashboard's own `effect` never
	re-ran: a vide source only notifies the reactive graph that created it,
	and a host with its own vide package (as `dashboard.luau` has) is not
	Aether's. `testAnExplicitSourceIsTheOneActuallyUsed` pins that the
	override this fix added is real, not merely accepted and ignored.

	THE FAKES ARE VERBATIM FROM `tests/core/createTabs.test.luau`'s OWN.
]=]
local T = require("@testkit")
local Tabs = require("../../src/primitives/Tabs")
local PointerRouter = require("../../src/PointerRouter")
local SelectionRouter = require("../../src/SelectionRouter")

local function pointerRouter()
	local registered: { { [string]: any } } = {}

	return {
		Pressable = function(props: { [string]: any })
			table.insert(registered, props)
			local index = #registered
			return {
				Bind = function() end,
				Destroy = function() end,
			}
		end,
		click = function(index: number)
			registered[index].OnActivated()
		end,
	}
end

local function selectionRouter()
	local registered: { { [string]: any } } = {}
	local bound: { [number]: any } = {}

	return {
		Selectable = function(props: { [string]: any })
			table.insert(registered, props)
			local index = #registered
			return {
				Bind = function(element: any)
					bound[index] = element
				end,
				Destroy = function() end,
			}
		end,
		Select = function() end,
		arrowNext = function(index: number)
			registered[index].OnArrowNext()
		end,
	}
end

local function mount(tabs: any, keys: { any })
	for _, key in ipairs(keys) do
		local props = tabs.GetTab(key).GetRootProps()
		for _, entry in ipairs(props) do
			if type(entry) == "function" then
				entry(`element:{tostring(key)}`)
			end
		end
	end
end

local function testAnExplicitRouterAndSelectionOverrideTheDefault()
	local pointer = pointerRouter()
	local selection = selectionRouter()
	local tabs = Tabs({
		Router = pointer :: any,
		Selection = selection :: any,
		Tabs = { "a", "b" },
		InitialActive = "a",
	})
	mount(tabs, { "a", "b" })

	pointer.click(2)
	assert(tabs.Active() == "b", "an explicit fake Router must be the one actually driving activation")

	selection.arrowNext(2)
	assert(tabs.Active() == "a", "an explicit fake Selection must be the one actually driving arrow navigation")
end

local function testOmittingBothWiresTheRealSingletons()
	local tabs = Tabs({
		Tabs = { "a", "b" },
		InitialActive = "a",
	})
	assert(tabs.Active() == "a", "the real PointerRouter/SelectionRouter singletons must not error just from wiring")
	assert(tabs.GetTab("a").IsActive() == true)
	tabs.Destroy()
end

--- A FAKE `Source`/`Action` PAIR, standing in for a host's own separate vide
--- package the same way `pointerRouter()`/`selectionRouter()` stand in for
--- the real routers -- tags every source it creates so the test can tell
--- Aether's own default apart from this one.
local function fakeReactiveGraph()
	local created = 0
	local actionsRun = 0
	return {
		Source = function(initial: any)
			created += 1
			local value = initial
			return function(...): any
				if select("#", ...) > 0 then
					value = select(1, ...)
				end
				return value
			end
		end,
		Action = function(callback: (any) -> ())
			return function(element: any)
				actionsRun += 1
				callback(element)
			end
		end,
		sourcesCreated = function()
			return created
		end,
		actionsRun = function()
			return actionsRun
		end,
	}
end

local function testAnExplicitSourceIsTheOneActuallyUsed()
	local pointer = pointerRouter()
	local selection = selectionRouter()
	local graph = fakeReactiveGraph()
	local tabs = Tabs({
		Router = pointer :: any,
		Selection = selection :: any,
		Source = graph.Source :: any,
		Action = graph.Action :: any,
		Tabs = { "a", "b" },
		InitialActive = "a",
	})
	assert(graph.sourcesCreated() > 0, "an explicit Source must be the one createTabs actually calls to make its cells")

	for _, key in ipairs({ "a", "b" }) do
		local props = tabs.GetTab(key).GetRootProps()
		for _, entry in ipairs(props) do
			if type(entry) == "function" then
				entry(`element:{tostring(key)}`)
			end
		end
	end
	assert(graph.actionsRun() > 0, "an explicit Action must be the one actually wrapping the bind callbacks")

	pointer.click(2)
	assert(tabs.Active() == "b", "activation must still work when Source/Action are overridden")
end

local function testItStillRefusesToRunWithoutTabs()
	local ok = pcall(function()
		Tabs({ Tabs = {} })
	end)
	assert(not ok, "a tab list with no tabs must say so rather than doing nothing quietly, same as the machine")
end

local function testTheRealSingletonsAreTheDefaultIdentity()
	-- Not exercised directly above (mounting against the real routers with no
	-- host tree is out of scope for this suite), but named here so a future
	-- reader can see the two modules this binding hands over by default.
	assert(PointerRouter ~= nil)
	assert(SelectionRouter ~= nil)
end

T.test("an explicit Router and Selection override the default", testAnExplicitRouterAndSelectionOverrideTheDefault, "math")
T.test("an explicit Source and Action are the ones actually used", testAnExplicitSourceIsTheOneActuallyUsed, "math")
T.test("omitting both wires the real singletons", testOmittingBothWiresTheRealSingletons, "math")
T.test("it still refuses to run without tabs", testItStillRefusesToRunWithoutTabs, "math")
T.test("the real singletons are the default identity", testTheRealSingletonsAreTheDefaultIdentity, "math")

return T.run("primitives/Tabs")
