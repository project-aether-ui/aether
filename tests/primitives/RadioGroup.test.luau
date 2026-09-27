--!strict
--!tier math
--[=[
	aether · primitives/RadioGroup.

	Mirrors `tests/primitives/Tabs.test.luau`'s own scope: `tests/core/
	createRadioGroup.test.luau` already pins the machine's behaviour, so this
	suite only proves the binding -- an explicit `Router`/`Selection` still
	overrides the real singletons, and omitting both wires them without
	erroring. `Source`/`Action` get the same override test, for the same
	reason `Tabs.test.luau`'s own does -- see that file's header.
]=]
local T = require("@testkit")
local RadioGroup = require("../../src/primitives/RadioGroup")

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
		activate = function(index: number)
			registered[index].OnKeyActivate()
		end,
	}
end

local function mount(group: any, keys: { any })
	for _, key in ipairs(keys) do
		local props = group.GetOption(key).GetRootProps()
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
	local group = RadioGroup({
		Router = pointer :: any,
		Selection = selection :: any,
		Options = { "small", "large" },
	})
	mount(group, { "small", "large" })

	pointer.click(2)
	assert(group.Value() == "large", "an explicit fake Router must be the one actually driving selection")

	selection.activate(1)
	assert(group.Value() == "small", "an explicit fake Selection must be the one actually driving key activation")
end

--- A fake `Source`/`Action` pair, standing in for a host's own separate vide
--- package -- verbatim from `tests/primitives/Tabs.test.luau`'s own.
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
	local group = RadioGroup({
		Router = pointer :: any,
		Selection = selection :: any,
		Source = graph.Source :: any,
		Action = graph.Action :: any,
		Options = { "small", "large" },
	})
	assert(graph.sourcesCreated() > 0, "an explicit Source must be the one createRadioGroup actually calls to make its cells")

	mount(group, { "small", "large" })
	assert(graph.actionsRun() > 0, "an explicit Action must be the one actually wrapping the bind callbacks")

	pointer.click(2)
	assert(group.Value() == "large", "selection must still work when Source/Action are overridden")
end

local function testOmittingBothWiresTheRealSingletons()
	local group = RadioGroup({
		Options = { "small", "large" },
		InitialValue = "small",
	})
	assert(group.Value() == "small", "the real PointerRouter/SelectionRouter singletons must not error just from wiring")
	assert(group.GetOption("small").IsSelected() == true)
	group.Destroy()
end

local function testItStillRefusesToRunWithoutOptions()
	local ok = pcall(function()
		RadioGroup({ Options = {} })
	end)
	assert(not ok, "a radio group with no options must say so rather than doing nothing quietly, same as the machine")
end

T.test("an explicit Router and Selection override the default", testAnExplicitRouterAndSelectionOverrideTheDefault, "math")
T.test("an explicit Source and Action are the ones actually used", testAnExplicitSourceIsTheOneActuallyUsed, "math")
T.test("omitting both wires the real singletons", testOmittingBothWiresTheRealSingletons, "math")
T.test("it still refuses to run without options", testItStillRefusesToRunWithoutOptions, "math")

return T.run("primitives/RadioGroup")
