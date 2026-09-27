--!strict
--!tier math
--[=[
	aether · core/createRadioGroup.

	NO VIDE, NO ROUTERS, NO TREE -- the same discipline createPressable's and
	createCheckbox's own suites hold themselves to. Two fakes stand in for
	both input families, each tracking one registration PER OPTION rather
	than one overall, since a radio group registers a `Pressable` and a
	`Selectable` for every option it is asked for.

	WHAT THESE ASSERT, matching this sprint's own completion test almost
	word for word: arrow-key navigation moves focus without touching which
	option is checked, an activation key changes what is checked, and
	`SelectionModel`'s own single-select-of-N invariant means selecting one
	option is indistinguishable from clearing every other one.
]=]
local T = require("@testkit")
local createRadioGroup = require("../../src/core/createRadioGroup").createRadioGroup

--- A pointer router tracking one `Pressable` registration per option, in the
--- order `GetOption` first asked for each one.
local function pointerRouter()
	local registered: { { [string]: any } } = {}
	local bound: { [number]: any } = {}
	local destroyed: { [number]: boolean } = {}

	return {
		Pressable = function(props: { [string]: any })
			table.insert(registered, props)
			local index = #registered
			return {
				Bind = function(element: any)
					bound[index] = element
				end,
				Destroy = function()
					destroyed[index] = true
				end,
			}
		end,
		click = function(index: number)
			registered[index].OnActivated()
		end,
		boundAt = function(index: number): any
			return bound[index]
		end,
		destroyedAt = function(index: number): boolean
			return destroyed[index] == true
		end,
	}
end

--- A selection router tracking one `Selectable` registration per option, and
--- `selected()` standing in for `GuiService.SelectedObject`: whatever
--- element `Select` was last called with.
local function selectionRouter()
	local registered: { { [string]: any } } = {}
	local bound: { [number]: any } = {}
	local destroyed: { [number]: boolean } = {}
	local selectedElement: any = nil

	return {
		Selectable = function(props: { [string]: any })
			table.insert(registered, props)
			local index = #registered
			return {
				Bind = function(element: any)
					bound[index] = element
				end,
				Destroy = function()
					destroyed[index] = true
				end,
			}
		end,
		Select = function(element: any)
			selectedElement = element
		end,
		activate = function(index: number)
			registered[index].OnKeyActivate()
		end,
		arrowNext = function(index: number)
			registered[index].OnArrowNext()
		end,
		arrowPrevious = function(index: number)
			registered[index].OnArrowPrevious()
		end,
		selected = function(): any
			return selectedElement
		end,
		boundAt = function(index: number): any
			return bound[index]
		end,
		destroyedAt = function(index: number): boolean
			return destroyed[index] == true
		end,
		--- Which registration index owns the currently selected element --
		--- what a test asks instead of comparing opaque fake elements by
		--- hand.
		selectedIndex = function(): number?
			for i, element in pairs(bound) do
				if element == selectedElement then
					return i
				end
			end
			return nil
		end,
	}
end

--- Builds a group, then MOUNTS every option in order -- calling
--- `GetRootProps` and running its bind actions with a distinct fake element
--- per option, the same as a host creating three real Frames would. Returns
--- the group and both fakes so a case can drive input directly.
local function mountedGroup(optionKeys: { any }, overrides: { [string]: any }?)
	local pointer = pointerRouter()
	local selection = selectionRouter()
	local groupOptions: { [string]: any } = {
		Router = pointer,
		Selection = selection,
		Options = optionKeys,
	}
	if overrides then
		for k, v in pairs(overrides) do
			groupOptions[k] = v
		end
	end
	local group = createRadioGroup(groupOptions :: any)

	for _, key in ipairs(optionKeys) do
		local option = group.GetOption(key)
		local props = option.GetRootProps()
		for _, entry in ipairs(props) do
			if type(entry) == "function" then
				entry(`element:{tostring(key)}`)
			end
		end
	end

	return group, pointer, selection
end

local function testItRefusesToRunWithoutOptions()
	local ok = pcall(function()
		createRadioGroup({ Router = pointerRouter(), Selection = selectionRouter(), Options = {} })
	end)
	assert(not ok, "a radio group with no options must say so rather than doing nothing quietly")
end

local function testNoInitialValueMeansNothingIsSelected()
	local group = mountedGroup({ "a", "b", "c" })
	assert(group.Value() == nil, "with no InitialValue nothing should be selected")
	local a = group.GetOption("a")
	assert(a.IsSelected() == false, "and no option should read as selected")
end

local function testAnInitialValueIsHonoured()
	local group = mountedGroup({ "a", "b", "c" }, { InitialValue = "b" })
	assert(group.Value() == "b", "InitialValue should be the starting value")
	assert(group.GetOption("b").IsSelected() == true, "the initial option should read as selected")
	assert(group.GetOption("a").IsSelected() == false, "and the others should not")
end

local function testAClickSelectsThatOption()
	local group, pointer = mountedGroup({ "a", "b", "c" })
	pointer.click(2) -- "b"
	assert(group.Value() == "b", "clicking an option should select it")
	assert(group.GetOption("b").IsSelected() == true)
end

--- CONTROLLED: `Value` AS A GETTER -- see `createCheckbox`'s own identical
--- case. A click must still fire `OnValueChanged`, but neither `Value()` nor
--- any option's `IsSelected()` may move on their own.
local function testControlledValueReadsThroughAndNeverWritesItself()
	local external: any = "a"
	local seen: { any } = {}
	local group, pointer = mountedGroup({ "a", "b", "c" }, {
		Value = function()
			return external
		end,
		OnValueChanged = function(v: any)
			table.insert(seen, v)
		end,
	})

	assert(group.Value() == "a", "controlled Value should start by reading the external getter")
	assert(group.GetOption("a").IsSelected() == true)

	pointer.click(2) -- "b"
	assert(group.Value() == "a", "a click must not move Value on its own while controlled")
	assert(group.GetOption("a").IsSelected() == true, "nor any option's IsSelected")
	assert(group.GetOption("b").IsSelected() == false)
	assert(seen[1] == "b", "OnValueChanged must still fire with the key this click would have selected")

	--- ONLY WHEN THE CALLER MOVES ITS OWN STATE do the options agree.
	external = "b"
	assert(group.Value() == "b")
	assert(group.GetOption("a").IsSelected() == false)
	assert(group.GetOption("b").IsSelected() == true)
end

--- THE ONE-OF-N INVARIANT, WHICH IS SelectionModel'S OWN "single" MODE, NOT
--- SOMETHING THIS FILE RE-DERIVES.
local function testSelectingOneClearsEveryOther()
	local group, pointer = mountedGroup({ "a", "b", "c" }, { InitialValue = "a" })
	assert(group.GetOption("a").IsSelected() == true)

	pointer.click(2) -- "b"

	assert(group.GetOption("a").IsSelected() == false, "selecting b should clear a")
	assert(group.GetOption("b").IsSelected() == true)
	assert(group.GetOption("c").IsSelected() == false)
end

--- THIS SPRINT'S OWN NAMED BEHAVIOUR: arrows move focus, they do not select.
local function testArrowKeysMoveFocusWithoutChangingSelection()
	local group, _pointer, selection = mountedGroup({ "a", "b", "c" }, { InitialValue = "a" })

	selection.arrowNext(1) -- from "a"
	assert(selection.selectedIndex() == 2, "arrow-next from a should move focus to b")
	assert(group.Value() == "a", "moving focus must not change what is selected")
	assert(group.GetOption("a").IsSelected() == true, "a should still read as selected")
end

local function testActivationKeySelectsWhereverFocusMovedTo()
	local group, _pointer, selection = mountedGroup({ "a", "b", "c" }, { InitialValue = "a" })

	selection.arrowNext(1) -- focus moves to b, from a's own registration
	selection.activate(2) -- b's own registration answers the activation

	assert(group.Value() == "b", "activating after roving to b should select b")
	assert(group.GetOption("a").IsSelected() == false)
end

local function testArrowNavigationWrapsAtBothEnds()
	local group, _pointer, selection = mountedGroup({ "a", "b", "c" })

	selection.arrowPrevious(1) -- from "a", backward, should wrap to "c"
	assert(selection.selectedIndex() == 3, "arrow-previous from the first option should wrap to the last")

	selection.arrowNext(3) -- from "c", forward, should wrap to "a"
	assert(selection.selectedIndex() == 1, "arrow-next from the last option should wrap to the first")
end

local function testEnterAlsoActivates()
	-- A RADIO GROUP ANSWERS BOTH SPACE AND RETURN, unlike createCheckbox's
	-- own Space-only default -- see createRadioGroup's own comment on why.
	local group, _pointer, selection = mountedGroup({ "a", "b" })
	selection.activate(2) -- "b" -- OnKeyActivate is wired to both keys alike
	assert(group.Value() == "b")
end

local function testDisabledRefusesBothInputFamilies()
	local group, pointer, selection = mountedGroup({ "a", "b" }, { Disabled = true })

	pointer.click(1)
	assert(group.Value() == nil, "a click must not select on a disabled group")

	selection.activate(1)
	assert(group.Value() == nil, "a key activation must not select on a disabled group either")
end

local function testOnValueChangedFiresWithTheNewValue()
	local seen: { any } = {}
	local group, pointer = mountedGroup({ "a", "b" }, {
		OnValueChanged = function(v: any)
			table.insert(seen, v)
		end,
	})
	pointer.click(2)
	assert(seen[1] == "b", "the handler should see the newly selected key")
end

local function testGetOptionIsMemoised()
	local group = mountedGroup({ "a", "b" })
	assert(group.GetOption("a") == group.GetOption("a"), "asking for the same option twice must answer the same machine")
end

local function testDestroyReleasesEveryOptionsRegistrations()
	local group, pointer, selection = mountedGroup({ "a", "b" })
	group.Destroy()

	assert(pointer.destroyedAt(1) and pointer.destroyedAt(2), "destroy should release every option's pointer registration")
	assert(selection.destroyedAt(1) and selection.destroyedAt(2), "and every option's selection registration")
end

local function testWithNoOverridesTheDefaultsStand()
	local group = mountedGroup({ "a" })
	local props = group.GetOption("a").GetRootProps()
	assert(props.Name == "RadioOption", "an unnamed option should still be named")
	assert(props.Selectable == true, "an option must be a legal keyboard/gamepad selection target")
end

--- MILESTONE 54 SPRINT 5'S OWN SUCCESS CRITERION -- see `createPressable`'s
--- own identical case and its comment on why `warn` itself is not captured.
local function testAnUnrecognisedOnKeyStillNeverReachesTheElement()
	local group = mountedGroup({ "a" })
	local props = group.GetOption("a").GetRootProps({ OnSelect = function() end })
	assert(props.OnSelect == nil, "a typo'd handler must still never reach the element, warning or not")
end

--- MILESTONE 54 SPRINT 3'S OWN SUCCESS CRITERION -- see `createCheckbox`'s
--- own identical case.
local function testGetActionPropsCarriesNoCosmeticDefaults()
	local pointer = pointerRouter()
	local selection = selectionRouter()
	local group = createRadioGroup({ Router = pointer, Selection = selection, Options = { "a" } } :: any)

	local props = group.GetOption("a").GetActionProps()

	assert(props.Name == nil, "GetActionProps must carry no cosmetic Name default")
	assert(props.Selectable == nil, "nor the Selectable default")
	assert(#props == 2, "exactly the pointer bind and the selection bind, nothing else")

	for _, entry in ipairs(props) do
		entry("an element")
	end
	assert(pointer.boundAt(1) == "an element", "the pointer router should still be bound through GetActionProps")
	assert(selection.boundAt(1) == "an element", "the selection router too")
end

T.test("it refuses to run without options", testItRefusesToRunWithoutOptions, "math")
T.test("no initial value means nothing is selected", testNoInitialValueMeansNothingIsSelected, "math")
T.test("an initial value is honoured", testAnInitialValueIsHonoured, "math")
T.test("a click selects that option", testAClickSelectsThatOption, "math")
T.test(
	"controlled Value reads through and never writes itself",
	testControlledValueReadsThroughAndNeverWritesItself,
	"math"
)
T.test("selecting one clears every other", testSelectingOneClearsEveryOther, "math")
T.test("arrow keys move focus without changing selection", testArrowKeysMoveFocusWithoutChangingSelection, "math")
T.test("activation key selects wherever focus moved to", testActivationKeySelectsWhereverFocusMovedTo, "math")
T.test("arrow navigation wraps at both ends", testArrowNavigationWrapsAtBothEnds, "math")
T.test("enter also activates", testEnterAlsoActivates, "math")
T.test("disabled refuses both input families", testDisabledRefusesBothInputFamilies, "math")
T.test("OnValueChanged fires with the new value", testOnValueChangedFiresWithTheNewValue, "math")
T.test("GetOption is memoised", testGetOptionIsMemoised, "math")
T.test("destroy releases every option's registrations", testDestroyReleasesEveryOptionsRegistrations, "math")
T.test("with no overrides the defaults stand", testWithNoOverridesTheDefaultsStand, "math")
T.test(
	"an unrecognised On key still never reaches the element",
	testAnUnrecognisedOnKeyStillNeverReachesTheElement,
	"math"
)
T.test("GetActionProps carries no cosmetic defaults", testGetActionPropsCarriesNoCosmeticDefaults, "math")

return T.run("createRadioGroup")
