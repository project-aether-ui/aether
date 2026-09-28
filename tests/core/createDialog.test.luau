--!strict
--!tier math
--[=[
	aether · core/createDialog.

	NO VIDE, NO ENGINE, NO REAL KEYBOARD. This file requires the machine and
	testkit and nothing else. A fake `Router` (the same shape
	`createPressable.test.luau`'s own `router()` fixture proves out for a
	single Pressable, extended here with a `backdrop()` reader since this
	machine registers exactly one) and a fake `Keys` capability (a plain
	callback list, standing in for `desktop.Input.InputBegan`) are what let
	"opening traps focus and Escape closes it" be asked without a mounted
	surface or a real key press.

	WHAT THESE ASSERT is the seam this sprint's own success criterion names:
	opening sets `IsOpen`; Escape closes; focus moves into the dialog's own
	registered set and Tab-cycles within it without leaking to an element
	outside; on close, focus restores to whatever `Open` was given; `Destroy`
	releases the trap.
]=]
local T = require("@testkit")
local createDialog = require("../../src/core/createDialog").createDialog

--- A pointer router that records exactly the one Pressable this machine
--- registers -- the backdrop -- the same shape `createPressable.test.luau`'s
--- own `router()` proves out for a single registration.
local function router()
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
		activateBackdrop = function()
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

--- Stands in for `desktop.Input.InputBegan`/`UserInputService.InputBegan`: a
--- plain list of subscribers, and a `press` helper that calls every one of
--- them, the way a real key press would.
local function keys()
	local subscribers: { (name: string, shift: boolean) -> () } = {}

	return {
		OnKeyDown = function(callback: (name: string, shift: boolean) -> ())
			table.insert(subscribers, callback)
			return function()
				local index = table.find(subscribers, callback)
				if index then
					table.remove(subscribers, index)
				end
			end
		end,
		press = function(name: string, shift: boolean?)
			for _, callback in ipairs(subscribers) do
				callback(name, shift == true)
			end
		end,
		subscriberCount = function(): number
			return #subscribers
		end,
	}
end

local function testItRefusesToRunWithoutARouter()
	local ok = pcall(function()
		createDialog({ Router = nil :: any })
	end)
	assert(not ok, "a machine with no router must say so rather than doing nothing quietly")
end

local function testOpeningSetsIsOpen()
	local dialog = createDialog({ Router = router() })
	assert(not dialog.IsOpen(), "a dialog nobody opened is closed")
	dialog.Open()
	assert(dialog.IsOpen(), "Open should open it")
	dialog.Close()
	assert(not dialog.IsOpen(), "Close should close it")
end

local function testEscapeCloses()
	local k = keys()
	local dialog = createDialog({ Router = router(), Keys = k })

	dialog.Open()
	assert(dialog.IsOpen(), "opened before Escape")
	k.press("Escape")
	assert(not dialog.IsOpen(), "Escape should close an open dialog")
end

local function testEscapeCanBeDisabled()
	local k = keys()
	local dialog = createDialog({ Router = router(), Keys = k, CloseOnEscape = false })

	dialog.Open()
	k.press("Escape")
	assert(dialog.IsOpen(), "CloseOnEscape = false should refuse the close")
end

local function testBackdropClickCloses()
	local r = router()
	local dialog = createDialog({ Router = r })

	dialog.Open()
	r.activateBackdrop()
	assert(not dialog.IsOpen(), "activating the backdrop should close the dialog")
end

local function testBackdropClickCanBeDisabled()
	local r = router()
	local dialog = createDialog({ Router = r, CloseOnBackdropClick = false })

	dialog.Open()
	r.activateBackdrop()
	assert(dialog.IsOpen(), "CloseOnBackdropClick = false should refuse the close")
end

local function testOpeningFocusesTheFirstRegistered()
	local seen: { any } = {}
	local dialog = createDialog({
		Router = router(),
		OnFocusChanged = function(element: any?)
			table.insert(seen, element)
		end,
	})

	dialog.RegisterFocusable("first", "element-a")
	dialog.RegisterFocusable("second", "element-b")
	dialog.Open()

	assert(dialog.CurrentFocusKey() == "first", "the first registered key should hold focus on open")
	assert(seen[#seen] == "element-a", "OnFocusChanged should have been told about the first element")
end

local function testRegisteringWhileOpenFocusesTheFirstArrival()
	local dialog = createDialog({ Router = router() })
	dialog.Open()
	assert(dialog.CurrentFocusKey() == nil, "nothing registered yet, nothing focused")

	dialog.RegisterFocusable("only", "element-a")
	assert(dialog.CurrentFocusKey() == "only", "the first element registered after opening should take focus")
end

local function testTabCyclesWithinTheRegisteredSetAndWraps()
	local k = keys()
	local dialog = createDialog({ Router = router(), Keys = k })
	dialog.RegisterFocusable("a", "element-a")
	dialog.RegisterFocusable("b", "element-b")
	dialog.RegisterFocusable("c", "element-c")
	dialog.Open()

	assert(dialog.CurrentFocusKey() == "a", "opens on the first")
	k.press("Tab")
	assert(dialog.CurrentFocusKey() == "b", "Tab should move to the next")
	k.press("Tab")
	assert(dialog.CurrentFocusKey() == "c", "Tab should move to the next again")
	k.press("Tab")
	assert(dialog.CurrentFocusKey() == "a", "Tab from the last should wrap to the first, not leak outside")

	k.press("Tab", true)
	assert(dialog.CurrentFocusKey() == "c", "Shift+Tab from the first should wrap to the last")
end

local function testTabDoesNothingWithNoneRegistered()
	local k = keys()
	local dialog = createDialog({ Router = router(), Keys = k })
	dialog.Open()

	k.press("Tab")
	assert(dialog.CurrentFocusKey() == nil, "Tab with nothing registered has nothing to move to")
end

local function testUnregisteringTheCurrentOneClearsFocusRatherThanGuessing()
	local dialog = createDialog({ Router = router() })
	dialog.RegisterFocusable("a", "element-a")
	dialog.RegisterFocusable("b", "element-b")
	dialog.Open()

	assert(dialog.CurrentFocusKey() == "a", "opens on the first")
	dialog.UnregisterFocusable("a")
	assert(dialog.CurrentFocusKey() == nil, "unregistering the current one clears focus rather than guessing a neighbour")
end

local function testClosingRestoresTheTrigger()
	local seen: { any } = {}
	local dialog = createDialog({
		Router = router(),
		OnFocusChanged = function(element: any?)
			table.insert(seen, element)
		end,
	})
	dialog.RegisterFocusable("a", "element-a")

	dialog.Open("trigger-element")
	dialog.Close()

	assert(seen[#seen] == "trigger-element", "closing should restore focus to whatever opened the dialog")
end

local function testClosingWithNoTriggerRestoresNothing()
	--- A PLAIN ARRAY CANNOT HOLD THIS ANSWER: `table.insert(seen, nil)`
	--- leaves `#seen` exactly where it was, so a trailing nil call is
	--- indistinguishable from no call at all. Wrapping each call in a table
	--- keeps "it was called, with nil" apart from "it was never called".
	local calls: { { value: any? } } = {}
	local dialog = createDialog({
		Router = router(),
		OnFocusChanged = function(element: any?)
			table.insert(calls, { value = element })
		end,
	})
	dialog.RegisterFocusable("a", "element-a")

	dialog.Open()
	dialog.Close()

	local last = calls[#calls]
	assert(last ~= nil, "closing should still call OnFocusChanged once, even with nothing to restore")
	assert(last.value == nil, "there is nothing knowable to restore when Open was given no trigger")
end

local function testDestroyReleasesTheTrapAndTheRegistration()
	local r = router()
	local k = keys()
	local dialog = createDialog({ Router = r, Keys = k })
	dialog.RegisterFocusable("a", "element-a")
	dialog.Open()

	assert(k.subscriberCount() == 1, "opening should have subscribed to Keys")
	dialog.Destroy()

	assert(r.destroyed(), "Destroy should release the router's backdrop registration")
	assert(k.subscriberCount() == 0, "Destroy should release the keyboard subscription too")
	assert(not dialog.IsOpen(), "a destroyed dialog is not open")

	dialog.Destroy()
end

local function testGetRootPropsCarriesNoRouterRegistration()
	local r = router()
	local dialog = createDialog({ Router = r })
	local props = dialog.GetRootProps({ Name = "MyDialog" })

	assert(props.Name == "MyDialog", "a caller's name should win over the default")
	assert(props.Visible == dialog.IsOpen, "the root surface should be visible exactly when the dialog is open")
end

local function testGetBackdropPropsBindsTheRouterAction()
	local r = router()
	local dialog = createDialog({ Router = r, Action = function(callback)
		return { bind = callback }
	end })

	local props = dialog.GetBackdropProps()
	local bindEntry = props[#props]
	bindEntry.bind("a real element")
	assert(r.bound() == "a real element", "the backdrop's bind action should register whatever the host created")
end

local function testNothingTheMachineOwnsReachesTheElement()
	local dialog = createDialog({ Router = router() })
	local props = dialog.GetRootProps({
		Keys = "not a real capability",
		OnClose = function() end,
		OnFocusChanged = function() end,
		Visible = true,
	})

	assert(props.Keys == nil, "Keys belongs to the machine")
	assert(props.OnClose == nil, "a handler is behaviour, not a property")
	assert(props.OnFocusChanged == nil, "a handler is behaviour, not a property")
	assert(props.Visible == true, "anything the machine does not claim should pass through")
end

T.test("it refuses to run without a router", testItRefusesToRunWithoutARouter, "math")
T.test("opening sets IsOpen", testOpeningSetsIsOpen, "math")
T.test("escape closes", testEscapeCloses, "math")
T.test("escape can be disabled", testEscapeCanBeDisabled, "math")
T.test("a backdrop click closes", testBackdropClickCloses, "math")
T.test("a backdrop click can be disabled", testBackdropClickCanBeDisabled, "math")
T.test("opening focuses the first registered", testOpeningFocusesTheFirstRegistered, "math")
T.test("registering while open focuses the first arrival", testRegisteringWhileOpenFocusesTheFirstArrival, "math")
T.test("Tab cycles within the registered set and wraps", testTabCyclesWithinTheRegisteredSetAndWraps, "math")
T.test("Tab does nothing with none registered", testTabDoesNothingWithNoneRegistered, "math")
T.test(
	"unregistering the current one clears focus rather than guessing",
	testUnregisteringTheCurrentOneClearsFocusRatherThanGuessing,
	"math"
)
T.test("closing restores the trigger", testClosingRestoresTheTrigger, "math")
T.test("closing with no trigger restores nothing", testClosingWithNoTriggerRestoresNothing, "math")
T.test("destroy releases the trap and the registration", testDestroyReleasesTheTrapAndTheRegistration, "math")
T.test("GetRootProps carries no router registration", testGetRootPropsCarriesNoRouterRegistration, "math")
T.test("GetBackdropProps binds the router action", testGetBackdropPropsBindsTheRouterAction, "math")
T.test("nothing the machine owns reaches the element", testNothingTheMachineOwnsReachesTheElement, "math")

return T.run("createDialog")
