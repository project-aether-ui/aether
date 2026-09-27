--!strict
--!tier math
--[=[
	aether · core/createCheckbox.

	NO VIDE, NO ROUTERS, NO TREE -- the same discipline `createPressable`'s
	own suite holds itself to, and for the same reason: a checkbox's own
	question -- "is it checked, and did a click or a keyboard press just
	change that" -- is answerable without a mounted component or a real
	pointer or a real keyboard to ask it with. Two small fakes stand in for
	both: a pointer router that fires its callbacks on demand (borrowed
	verbatim from createPressable's own suite, since the pointer half of a
	checkbox is exactly a Pressable's), and a selection router that fires
	`OnKeyActivate` on demand the same way.
]=]
local T = require("@testkit")
local createCheckbox = require("../../src/core/createCheckbox").createCheckbox

--- Verbatim from createPressable's own suite: a pointer router that never
--- touches a pointer, recording what it was registered with.
local function pointerRouter()
	local registered: { [string]: any } = {}
	local destroyed = false
	local bound: any = nil

	return {
		Pressable = function(props: { [string]: any })
			registered = props
			return {
				Bind = function(element: any)
					bound = element
				end,
				Destroy = function()
					destroyed = true
				end,
			}
		end,
		--- A PRESS AND ITS RELEASE ARE NOT WHAT DECIDES ACTIVATION HERE --
		--- the real router works that out internally (did the release land on
		--- the same element the press began on), and `createPressable`'s own
		--- fake router mirrors that by never synthesising `OnActivated` from
		--- the two. This fake follows the same rule: a full click is its own
		--- call, exactly what the real router would eventually invoke.
		click = function()
			registered.OnActivated()
		end,
		destroyed = function(): boolean
			return destroyed
		end,
		bound = function(): any
			return bound
		end,
	}
end

--- A selection router that never touches `GuiService` or a real keyboard:
--- `activate()` is standing in for "the activation key was pressed while
--- this element was selected", which is the one fact `SelectionRouter`
--- exists to establish for real.
local function selectionRouter()
	local registered: { [string]: any } = {}
	local destroyed = false
	local bound: any = nil

	return {
		Selectable = function(props: { [string]: any })
			registered = props
			return {
				Bind = function(element: any)
					bound = element
				end,
				Destroy = function()
					destroyed = true
				end,
			}
		end,
		activate = function()
			registered.OnKeyActivate()
		end,
		destroyed = function(): boolean
			return destroyed
		end,
		bound = function(): any
			return bound
		end,
	}
end

local function machine(overrides: { [string]: any }?)
	local pointer = pointerRouter()
	local selection = selectionRouter()
	local options: { [string]: any } = { Router = pointer, Selection = selection }
	if overrides then
		for k, v in pairs(overrides) do
			options[k] = v
		end
	end
	return createCheckbox(options :: any), pointer, selection
end

local function testItRefusesToRunWithoutARouter()
	local ok = pcall(function()
		createCheckbox({ Router = nil :: any, Selection = selectionRouter() })
	end)
	assert(not ok, "a checkbox with no pointer router must say so rather than doing nothing quietly")
end

local function testItRefusesToRunWithoutASelectionRouter()
	local ok = pcall(function()
		createCheckbox({ Router = pointerRouter(), Selection = nil :: any })
	end)
	assert(not ok, "a checkbox with no selection router must say so rather than doing nothing quietly")
end

local function testItStartsUnchecked()
	local m = machine()
	assert(m.Checked() == false, "a checkbox with no initial state starts unchecked")
end

local function testAnInitialCheckedStateIsHonoured()
	local m = machine({ Checked = true })
	assert(m.Checked() == true, "Checked = true should be the starting state")
end

local function testAClickTogglesIt()
	local m, pointer = machine()
	pointer.click()
	assert(m.Checked() == true, "a click should check an unchecked box")

	pointer.click()
	assert(m.Checked() == false, "a second click should uncheck it again")
end

local function testAKeyActivationTogglesIt()
	local m, _pointer, selection = machine()
	selection.activate()
	assert(m.Checked() == true, "a Space press while selected should check an unchecked box")

	selection.activate()
	assert(m.Checked() == false, "a second one should uncheck it again")
end

--- CONTROLLED: `Checked` AS A GETTER, the same shape `createContextMenu`'s
--- own `IsOpen` already uses. A click must still fire `OnCheckedChanged`,
--- but `Checked()` must keep answering the CALLER'S state, not flip on its
--- own -- the same way a controlled `<input>` never checks itself.
local function testControlledCheckedReadsThroughAndNeverWritesItself()
	local external = false
	local seen: { boolean } = {}
	local m, pointer = machine({
		Checked = function()
			return external
		end,
		OnCheckedChanged = function(v: boolean)
			table.insert(seen, v)
		end,
	})

	assert(m.Checked() == false, "controlled Checked should start by reading the external getter")

	pointer.click()
	assert(m.Checked() == false, "a click must not flip Checked on its own while controlled")
	assert(seen[1] == true, "OnCheckedChanged must still fire with the value this click would have set")

	--- ONLY WHEN THE CALLER MOVES ITS OWN STATE does `Checked` agree.
	external = true
	assert(m.Checked() == true, "Checked must track the external getter once the caller updates it")
end

local function testClickAndKeyDriveTheSameState()
	-- THE DONE-WHEN THIS SUITE EXISTS TO PROVE: both input families reach one
	-- state rather than two that could disagree.
	local m, pointer, selection = machine()

	pointer.click()
	assert(m.Checked() == true, "a click checked it")

	selection.activate()
	assert(m.Checked() == false, "a keyboard activation should see and flip the SAME state a click just set")

	pointer.click()
	assert(m.Checked() == true, "and a click after that should see and flip what the keyboard just set")
end

local function testOnCheckedChangedFiresWithTheNewValue()
	local seen: { boolean } = {}
	local m, pointer, selection = machine({
		OnCheckedChanged = function(checked: boolean)
			table.insert(seen, checked)
		end,
	})

	pointer.click()
	selection.activate()

	assert(seen[1] == true, "the handler should see true after the click checked it")
	assert(seen[2] == false, "and false after the key activation unchecked it")
end

local function testDisabledRefusesBothInputFamilies()
	local m, pointer, selection = machine({ Disabled = true })

	pointer.click()
	assert(m.Checked() == false, "a click must not check a disabled checkbox")

	selection.activate()
	assert(m.Checked() == false, "a key activation must not check a disabled checkbox either")
end

local function testBothRoutersAreBound()
	local m, pointer, selection = machine()
	local props = m.GetRootProps()

	--- Two actions in the array part: the pointer router's bind and the
	--- selection router's bind, in that order -- see createCheckbox's own
	--- comment on why both belong in one prop table.
	for _, entry in ipairs(props) do
		if type(entry) == "function" then
			entry("an element")
		end
	end

	assert(pointer.bound() == "an element", "the pointer router should have been bound")
	assert(selection.bound() == "an element", "the selection router should have been bound")
end

--- MILESTONE 54 SPRINT 3'S OWN SUCCESS CRITERION -- see `createPressable`'s
--- own identical case.
local function testGetActionPropsCarriesNoCosmeticDefaults()
	local m, pointer, selection = machine()
	local props = m.GetActionProps()

	assert(props.Name == nil, "GetActionProps must carry no cosmetic Name default")
	assert(props.BackgroundTransparency == nil, "nor BackgroundTransparency")
	assert(props.Selectable == nil, "nor the Selectable default")
	assert(#props == 2, "exactly the pointer bind and the selection bind, nothing else")

	for _, entry in ipairs(props) do
		entry("an element")
	end
	assert(pointer.bound() == "an element", "the pointer router should still be bound through GetActionProps")
	assert(selection.bound() == "an element", "the selection router too")
end

local function testDestroyReleasesBothRegistrations()
	local m, pointer, selection = machine()
	m.Destroy()

	assert(pointer.destroyed(), "destroy should release the pointer router registration")
	assert(selection.destroyed(), "destroy should release the selection router registration")

	m.Destroy()
end

local function testWithNoOverridesTheDefaultsStand()
	local m = machine()
	local props = m.GetRootProps()
	assert(props.Name == "Checkbox", "an unnamed checkbox should still be named")
	assert(props.BackgroundTransparency == 1, "a checkbox has no appearance of its own")
	assert(props.Selectable == true, "a checkbox must be a legal keyboard/gamepad selection target")
end

local function testNothingTheMachineOwnsReachesTheElement()
	local m = machine()
	local props = m.GetRootProps({
		Checked = true,
		OnCheckedChanged = function() end,
		Visible = true,
	})

	assert(props.Checked == nil, "Checked belongs to the machine, not the element")
	assert(props.OnCheckedChanged == nil, "a handler is behaviour, not a property")
	assert(props.Visible == true, "anything the machine does not claim should pass through")
end

--- MILESTONE 54 SPRINT 5'S OWN SUCCESS CRITERION -- see `createPressable`'s
--- own identical case and its comment on why `warn` itself is not captured.
local function testAnUnrecognisedOnKeyStillNeverReachesTheElement()
	local m = machine()
	local props = m.GetRootProps({ OnChecked = function() end })
	assert(props.OnChecked == nil, "a typo'd handler must still never reach the element, warning or not")
end

T.test("it refuses to run without a pointer router", testItRefusesToRunWithoutARouter, "math")
T.test("it refuses to run without a selection router", testItRefusesToRunWithoutASelectionRouter, "math")
T.test("it starts unchecked", testItStartsUnchecked, "math")
T.test("an initial checked state is honoured", testAnInitialCheckedStateIsHonoured, "math")
T.test("a click toggles it", testAClickTogglesIt, "math")
T.test("a key activation toggles it", testAKeyActivationTogglesIt, "math")
T.test(
	"controlled Checked reads through and never writes itself",
	testControlledCheckedReadsThroughAndNeverWritesItself,
	"math"
)
T.test("click and key drive the same state", testClickAndKeyDriveTheSameState, "math")
T.test("OnCheckedChanged fires with the new value", testOnCheckedChangedFiresWithTheNewValue, "math")
T.test("disabled refuses both input families", testDisabledRefusesBothInputFamilies, "math")
T.test("both routers are bound", testBothRoutersAreBound, "math")
T.test("GetActionProps carries no cosmetic defaults", testGetActionPropsCarriesNoCosmeticDefaults, "math")
T.test("destroy releases both registrations", testDestroyReleasesBothRegistrations, "math")
T.test("with no overrides the defaults stand", testWithNoOverridesTheDefaultsStand, "math")
T.test("nothing the machine owns reaches the element", testNothingTheMachineOwnsReachesTheElement, "math")
T.test(
	"an unrecognised On key still never reaches the element",
	testAnUnrecognisedOnKeyStillNeverReachesTheElement,
	"math"
)

return T.run("createCheckbox")
