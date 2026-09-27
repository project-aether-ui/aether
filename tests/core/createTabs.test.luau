--!strict
--!tier math
--[=[
	aether · core/createTabs.

	NO VIDE, NO ROUTERS, NO TREE -- the same discipline every other Layer 1
	suite in this tree holds itself to. The two fakes are borrowed from
	createRadioGroup's own suite almost verbatim, since a tab list registers
	one `Pressable` and one `Selectable` per tab the same way a radio group
	registers one per option.

	WHAT THESE ASSERT, matching this sprint's own completion test: arrow-key
	navigation between tabs, and that `SelectionModel`'s own single-select-of
	-N invariant means exactly one panel's visibility follows the active tab
	at a time. The one behaviour this suite exists to pin down against
	createRadioGroup's own suite is the opposite of that one's: an arrow
	press here switches the active tab immediately, it does not merely rove
	focus toward one an activation key would still need to confirm.
]=]
local T = require("@testkit")
local createTabs = require("../../src/core/createTabs").createTabs

--- Verbatim shape from createRadioGroup's own suite: one `Pressable`
--- registration per tab, in the order `GetTab` first asked for each one.
local function pointerRouter()
	local registered: { { [string]: any } } = {}
	local destroyed: { [number]: boolean } = {}

	return {
		Pressable = function(props: { [string]: any })
			table.insert(registered, props)
			local index = #registered
			return {
				Bind = function() end,
				Destroy = function()
					destroyed[index] = true
				end,
			}
		end,
		click = function(index: number)
			registered[index].OnActivated()
		end,
		destroyedAt = function(index: number): boolean
			return destroyed[index] == true
		end,
	}
end

--- A selection router tracking one `Selectable` registration per tab, and
--- `selected()` standing in for `GuiService.SelectedObject`.
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
		arrowNext = function(index: number)
			registered[index].OnArrowNext()
		end,
		arrowPrevious = function(index: number)
			registered[index].OnArrowPrevious()
		end,
		destroyedAt = function(index: number): boolean
			return destroyed[index] == true
		end,
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

--- Builds a set of tabs, mounts every one of them (running each tab's own
--- bind actions with a distinct fake element, the same as a host creating
--- real Frames would), and returns the group plus both fakes.
local function mountedTabs(tabKeys: { any }, overrides: { [string]: any }?)
	local pointer = pointerRouter()
	local selection = selectionRouter()
	local tabOptions: { [string]: any } = {
		Router = pointer,
		Selection = selection,
		Tabs = tabKeys,
	}
	if overrides then
		for k, v in pairs(overrides) do
			tabOptions[k] = v
		end
	end
	local tabs = createTabs(tabOptions :: any)

	for _, key in ipairs(tabKeys) do
		local tab = tabs.GetTab(key)
		local props = tab.GetRootProps()
		for _, entry in ipairs(props) do
			if type(entry) == "function" then
				entry(`element:{tostring(key)}`)
			end
		end
	end

	return tabs, pointer, selection
end

local function testItRefusesToRunWithoutTabs()
	local ok = pcall(function()
		createTabs({ Router = pointerRouter(), Selection = selectionRouter(), Tabs = {} })
	end)
	assert(not ok, "a tab list with no tabs must say so rather than doing nothing quietly")
end

local function testNoInitialActiveMeansNothingIsActive()
	local tabs = mountedTabs({ "a", "b", "c" })
	assert(tabs.Active() == nil)
	assert(tabs.GetTab("a").IsActive() == false)
	assert(tabs.GetPanel("a").IsVisible() == false)
end

local function testAnInitialActiveIsHonoured()
	local tabs = mountedTabs({ "a", "b", "c" }, { InitialActive = "b" })
	assert(tabs.Active() == "b")
	assert(tabs.GetTab("b").IsActive() == true)
	assert(tabs.GetPanel("b").IsVisible() == true)
	assert(tabs.GetTab("a").IsActive() == false)
	assert(tabs.GetPanel("a").IsVisible() == false)
end

local function testAClickActivatesThatTab()
	local tabs, pointer = mountedTabs({ "a", "b", "c" })
	pointer.click(2) -- "b"
	assert(tabs.Active() == "b")
	assert(tabs.GetPanel("b").IsVisible() == true)
end

--- EXACTLY ONE PANEL VISIBLE AT A TIME, this sprint's own named completion
--- test, and SelectionModel's own "single" mode is the entire reason it
--- holds: activating one clears the previous one's selection, and every
--- panel's own IsVisible follows the model directly.
local function testActivatingOneHidesEveryOtherPanel()
	local tabs, pointer = mountedTabs({ "a", "b", "c" }, { InitialActive = "a" })
	assert(tabs.GetPanel("a").IsVisible() == true)

	pointer.click(2) -- "b"

	assert(tabs.GetPanel("a").IsVisible() == false, "activating b should hide a's panel")
	assert(tabs.GetPanel("b").IsVisible() == true)
	assert(tabs.GetPanel("c").IsVisible() == false)
	assert(tabs.GetTab("a").IsActive() == false)
	assert(tabs.GetTab("b").IsActive() == true)
end

--- THE BEHAVIOUR THIS SUITE EXISTS TO PIN AGAINST createRadioGroup'S OWN:
--- an arrow press activates immediately, it does not only rove focus.
local function testAnArrowPressActivatesTheNextTabImmediately()
	local tabs, _pointer, selection = mountedTabs({ "a", "b", "c" }, { InitialActive = "a" })

	selection.arrowNext(1) -- from "a"

	assert(tabs.Active() == "b", "an arrow press should activate the next tab immediately")
	assert(tabs.GetPanel("b").IsVisible() == true)
	assert(tabs.GetPanel("a").IsVisible() == false)
	assert(selection.selectedIndex() == 2, "keyboard focus should follow the newly active tab")
end

local function testArrowNavigationWrapsAtBothEnds()
	local tabs, _pointer, selection = mountedTabs({ "a", "b", "c" }, { InitialActive = "a" })

	selection.arrowPrevious(1) -- from "a", backward, should wrap to "c"
	assert(tabs.Active() == "c", "arrow-previous from the first tab should wrap to the last")

	selection.arrowNext(3) -- from "c", forward, should wrap to "a"
	assert(tabs.Active() == "a", "arrow-next from the last tab should wrap to the first")
end

local function testDisabledRefusesBothInputFamilies()
	local tabs, pointer, selection = mountedTabs({ "a", "b" }, { InitialActive = "a", Disabled = true })

	pointer.click(2)
	assert(tabs.Active() == "a", "a click must not activate a tab in a disabled list")

	selection.arrowNext(1)
	assert(tabs.Active() == "a", "an arrow press must not activate a tab in a disabled list either")
end

local function testOnActiveChangedFiresWithTheNewValue()
	local seen: { any } = {}
	local tabs, pointer = mountedTabs({ "a", "b" }, {
		OnActiveChanged = function(v: any)
			table.insert(seen, v)
		end,
	})
	pointer.click(2)
	assert(seen[1] == "b")
end

local function testGetTabAndGetPanelAreMemoised()
	local tabs = mountedTabs({ "a", "b" })
	assert(tabs.GetTab("a") == tabs.GetTab("a"), "asking for the same tab twice must answer the same machine")
	assert(tabs.GetPanel("a") == tabs.GetPanel("a"), "the same for a panel")
end

local function testDestroyReleasesEveryTabsRegistrations()
	local tabs, pointer, selection = mountedTabs({ "a", "b" })
	tabs.Destroy()

	assert(pointer.destroyedAt(1) and pointer.destroyedAt(2), "destroy should release every tab's pointer registration")
	assert(
		selection.destroyedAt(1) and selection.destroyedAt(2),
		"and every tab's selection registration"
	)
end

local function testWithNoOverridesTheDefaultsStand()
	local tabs = mountedTabs({ "a" })
	local tabProps = tabs.GetTab("a").GetRootProps()
	assert(tabProps.Name == "Tab")
	assert(tabProps.Selectable == true, "a tab must be a legal keyboard/gamepad selection target")

	local panelProps = tabs.GetPanel("a").GetRootProps()
	assert(panelProps.Name == "TabPanel")
	assert(type(panelProps.Visible) == "function", "a panel's Visible should be its own IsVisible source")
end

--- MILESTONE 54 SPRINT 5'S OWN SUCCESS CRITERION -- see `createPressable`'s
--- own identical case and its comment on why `warn` itself is not captured.
local function testAnUnrecognisedOnKeyStillNeverReachesTheElement()
	local tabs = mountedTabs({ "a" })
	local props = tabs.GetTab("a").GetRootProps({ OnActive = function() end })
	assert(props.OnActive == nil, "a typo'd handler must still never reach the element, warning or not")
end

--- MILESTONE 54 SPRINT 3'S OWN SUCCESS CRITERION -- see `createCheckbox`'s
--- own identical case. A tab's `GetActionProps` carries the same two binds
--- `GetRootProps`' own array part does; a panel's carries no cosmetic `Name`
--- either, only the `Visible` state it exists to hand over -- see this
--- file's own `Panel` type comment on why that is not itself a cosmetic
--- default.
local function testGetActionPropsCarriesNoCosmeticDefaults()
	local pointer = pointerRouter()
	local selection = selectionRouter()
	local tabs = createTabs({ Router = pointer, Selection = selection, Tabs = { "a" } } :: any)

	local tabProps = tabs.GetTab("a").GetActionProps()
	assert(tabProps.Name == nil, "a tab's GetActionProps must carry no cosmetic Name default")
	assert(tabProps.Selectable == nil, "nor the Selectable default")
	assert(#tabProps == 2, "exactly the pointer bind and the selection bind, nothing else")
	for _, entry in ipairs(tabProps) do
		entry("an element")
	end
	pointer.click(1)
	assert(tabs.Active() == "a", "the bind from GetActionProps must be the real one the router activates through")

	local panelProps = tabs.GetPanel("a").GetActionProps()
	assert(panelProps.Name == nil, "a panel's GetActionProps must carry no cosmetic Name default")
	assert(type(panelProps.Visible) == "function", "but it must still carry Visible, its own state")
end

T.test("it refuses to run without tabs", testItRefusesToRunWithoutTabs, "math")
T.test("no initial active means nothing is active", testNoInitialActiveMeansNothingIsActive, "math")
T.test("an initial active is honoured", testAnInitialActiveIsHonoured, "math")
T.test("a click activates that tab", testAClickActivatesThatTab, "math")
T.test("activating one hides every other panel", testActivatingOneHidesEveryOtherPanel, "math")
T.test("an arrow press activates the next tab immediately", testAnArrowPressActivatesTheNextTabImmediately, "math")
T.test("arrow navigation wraps at both ends", testArrowNavigationWrapsAtBothEnds, "math")
T.test("disabled refuses both input families", testDisabledRefusesBothInputFamilies, "math")
T.test("OnActiveChanged fires with the new value", testOnActiveChangedFiresWithTheNewValue, "math")
T.test("GetTab and GetPanel are memoised", testGetTabAndGetPanelAreMemoised, "math")
T.test("destroy releases every tab's registrations", testDestroyReleasesEveryTabsRegistrations, "math")
T.test("with no overrides the defaults stand", testWithNoOverridesTheDefaultsStand, "math")
T.test(
	"an unrecognised On key still never reaches the element",
	testAnUnrecognisedOnKeyStillNeverReachesTheElement,
	"math"
)
T.test("GetActionProps carries no cosmetic defaults", testGetActionPropsCarriesNoCosmeticDefaults, "math")

return T.run("createTabs")
