--!strict
--!tier math
--[=[
	aether · core/createPressable.

	NO VIDE, NO ROUTER, NO TREE. This file requires the machine and testkit and
	nothing else. Every platform the machine talks to is supplied here, in about
	thirty lines: a router that records what it was registered with and fires the
	callbacks on demand, a source that is a closure, and an action that hands the
	callback straight back so a case can read it out of the prop table.

	That is what makes these cases answerable at all. The question a press asks --
	"is it held, and what does the element look like while it is" -- used to need
	a mounted component and a real pointer to ask, which meant it was asked by
	running the desktop and looking.

	WHAT THESE ASSERT is the seam rather than the arithmetic. The machine owns two
	booleans and a prop table, so the cases are: the router hears about the press,
	the sources follow it, the props carry the state, the caller's handlers still
	fire, and nothing the machine owns leaks onto the element.
]=]
local T = require("@testkit")
local createPressable = require("../../src/core/createPressable").createPressable

--- A pointer router that never touches a pointer. `props()` is what the machine
--- registered with, which is how "the router was told" gets asserted rather than
--- inferred from the state that follows.
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
		props = function(): { [string]: any }
			return registered
		end,
		hover = function(hovered: boolean)
			registered.OnHoverChanged(hovered)
		end,
		press = function(x: number, y: number)
			registered.OnPressed(x, y)
		end,
		release = function()
			registered.OnReleased()
		end,
		destroyed = function(): boolean
			return destroyed
		end,
		bound = function(): any
			return bound
		end,
	}
end

--- The one entry in the array part that is not a child: whatever `Action` made
--- of the machine's bind callback.
local function bindEntry(props: { [any]: any }): any
	return props[#props]
end

local function testItRefusesToRunWithoutARouter()
	local ok = pcall(function()
		createPressable({ Router = nil :: any })
	end)
	assert(not ok, "a machine with no router must say so rather than doing nothing quietly")
end

local function testPressAndHoverFollowTheRouter()
	local r = router()
	local m = createPressable({ Router = r })

	assert(not m.IsHovered(), "nothing is hovered before the pointer arrives")
	assert(not m.IsPressed(), "nothing is pressed before the pointer arrives")

	r.hover(true)
	assert(m.IsHovered(), "the machine should follow the router into hover")

	r.press(120, 48)
	assert(m.IsPressed(), "a press the router reported should be held by the machine")

	r.release()
	assert(not m.IsPressed(), "a release should end the press")
	assert(m.IsHovered(), "a release is not a departure; hover should survive it")
end

--- THE ONE THAT MATTERS FOR A BINDING. A component derives from these sources,
--- so a handler that fires before the write lands would hand every consumer the
--- previous value for one frame.
local function testTheCallersHandlersSeeTheNewState()
	local r = router()
	local seen: { boolean } = {}
	local activated = 0

	--- Declared before it is built, because both handlers below read the machine
	--- that is being constructed -- which is the whole question.
	local m: any = nil
	m = createPressable({
		Router = r,
		OnHoverChanged = function(_hovered: boolean)
			table.insert(seen, m.IsHovered())
		end,
		OnPressed = function(_x: number, _y: number)
			table.insert(seen, m.IsPressed())
		end,
		OnActivated = function()
			activated += 1
		end,
	})

	r.hover(true)
	r.press(0, 0)

	assert(seen[1] == true, "a hover handler should see the source already true")
	assert(seen[2] == true, "a press handler should see the source already true")

	r.props().OnActivated()
	assert(activated == 1, "the caller's activate handler should reach the router untouched")
end

local function testThePressPositionSurvives()
	local r = router()
	local at: { number } = {}
	createPressable({
		Router = r,
		OnPressed = function(x: number, y: number)
			at = { x, y }
		end,
	})

	r.press(320, 180)
	assert(at[1] == 320 and at[2] == 180, `the press position should arrive intact, got {at[1]}, {at[2]}`)
end

local function testDisabledLeavesAsAGetter()
	local r = router()
	createPressable({ Router = r, Disabled = true })
	assert(r.props().Disabled() == true, "a disabled value should reach the router as a getter")

	local flag = false
	local other = router()
	createPressable({
		Router = other,
		Disabled = function()
			return flag
		end,
	})
	assert(other.props().Disabled() == false, "a disabled getter should be read, not copied")
	flag = true
	assert(other.props().Disabled() == true, "the router should see the getter's later answer")
end

local function testTheRootPropsAreSpreadable()
	local r = router()
	local m = createPressable({ Router = r, Action = function(callback)
		return { bind = callback }
	end })

	local child = { aChild = true }
	local props = m.GetRootProps({
		Name = "Row",
		Size = "whatever the host calls a size",
		BackgroundTransparency = 0.5,
		child,
	})

	assert(props.Name == "Row", "a caller's name should win over the default")
	assert(props.BackgroundTransparency == 0.5, "a caller's value should win over the default")
	assert(props.BorderSizePixel == 0, "a default the caller said nothing about should survive")
	assert(props[1] == child, "children should keep their place in the array part")

	bindEntry(props).bind("an element")
	assert(r.bound() == "an element", "the bind action should register whatever the host created")
end

local function testWithNoOverridesTheDefaultsStand()
	local r = router()
	local props = createPressable({ Router = r }).GetRootProps()
	assert(props.Name == "Pressable", "an unnamed pressable should still be named")
	assert(props.BackgroundTransparency == 1, "a press has no appearance of its own")
end

--- The machine's own vocabulary must not reach the element: a host asked to set
--- `Scope` or `OnActivated` on something it drew would fail at the far end of
--- the call, with nothing pointing back here.
local function testNothingTheMachineOwnsReachesTheElement()
	local r = router()
	local m = createPressable({ Router = r })

	local props = m.GetRootProps({
		Scope = "a scope",
		Cursor = "Grab",
		Disabled = true,
		OnActivated = function() end,
		OnPress = function() end,
		Visible = true,
	})

	assert(props.Scope == nil, "Scope belongs to the router")
	assert(props.Cursor == nil, "Cursor belongs to the router")
	assert(props.Disabled == nil, "Disabled belongs to the router")
	assert(props.OnActivated == nil, "a handler is behaviour, not a property")
	assert(props.OnPress == nil, "a handler this machine does not implement is still not a property")
	assert(props.Visible == true, "anything the machine does not claim should pass through")
end

local function testDestroyReleasesTheRegistration()
	local r = router()
	local m = createPressable({ Router = r })

	r.hover(true)
	r.press(0, 0)
	m.Destroy()

	assert(r.destroyed(), "destroy should release the router registration")
	assert(not m.IsHovered(), "a destroyed pressable is not hovered")
	assert(not m.IsPressed(), "a destroyed pressable is not pressed")

	m.Destroy()
end

--- The sources are a PORT, and the default closure is only what runs when no
--- caller supplies one. A binding passes `vide.source` and expects every write
--- to go through it.
local function testWritesGoThroughTheSuppliedSource()
	local writes = 0
	local r = router()
	local m = createPressable({
		Router = r,
		Source = function<T>(initial: T)
			local value = initial
			return function(...): T
				if select("#", ...) > 0 then
					writes += 1
					value = (select(1, ...) :: any) :: T
				end
				return value
			end :: any
		end,
	})

	r.hover(true)
	r.press(0, 0)
	r.release()

	assert(writes == 3, `every state change should go through the supplied source, got {writes}`)
	assert(m.IsHovered(), "the supplied source should be the one the machine reads back")
end

T.test("it refuses to run without a router", testItRefusesToRunWithoutARouter, "math")
T.test("press and hover follow the router", testPressAndHoverFollowTheRouter, "math")
T.test("the caller's handlers see the new state", testTheCallersHandlersSeeTheNewState, "math")
T.test("the press position survives", testThePressPositionSurvives, "math")
T.test("disabled leaves as a getter", testDisabledLeavesAsAGetter, "math")
T.test("the root props are spreadable", testTheRootPropsAreSpreadable, "math")
T.test("with no overrides the defaults stand", testWithNoOverridesTheDefaultsStand, "math")
T.test("nothing the machine owns reaches the element", testNothingTheMachineOwnsReachesTheElement, "math")
T.test("destroy releases the registration", testDestroyReleasesTheRegistration, "math")
T.test("writes go through the supplied source", testWritesGoThroughTheSuppliedSource, "math")

return T.run("createPressable")
