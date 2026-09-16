--!strict
--!tier math
--[=[
	aether · core/createContextMenu.

	NO VIDE, NO ROUTER, NO TREE. This file requires the machine and testkit and
	nothing else. A menu is the first primitive here whose state is worth more
	than one boolean -- open, which row is focused, and what a dismissal means --
	and every one of those questions used to need a mounted surface, a real
	pointer and a screenshot to ask.

	WHAT THESE ASSERT is the seam rather than the drawing. The machine owns open
	and focus, hands back the props a binding spreads, and decides the ORDER of
	the two things an activation does; so the cases are: the flag follows the
	verbs, hovering a row focuses it, focus skips what cannot take it, an
	activation closes before it calls, and nothing the machine owns leaks onto an
	element.
]=]
local T = require("@testkit")
local createContextMenu = require("../../src/core/createContextMenu").createContextMenu

type Item = {
	Id: string,
	Label: string,
	Disabled: boolean?,
	OnActivated: (() -> ())?,
}

local function items(): { Item }
	return {
		{ Id = "cut", Label = "Cut" },
		{ Id = "copy", Label = "Copy" },
		{ Id = "paste", Label = "Paste", Disabled = true },
		{ Id = "delete", Label = "Delete" },
	}
end

--- Hover a row the way a binding does: through the props the machine handed it,
--- rather than by calling an internal.
local function hover(machine: any, id: string, hovered: boolean)
	machine.GetItemProps(id).OnHoverChanged(hovered)
end

local function testItOpensAndCloses()
	local machine = createContextMenu({ Items = items })

	assert(not machine.IsOpen(), "a menu nobody summoned is closed")
	machine.Open()
	assert(machine.IsOpen(), "Open should open it")
	machine.Close()
	assert(not machine.IsOpen(), "Close should close it")

	machine.Toggle()
	assert(machine.IsOpen(), "Toggle should open a closed menu")
	machine.Toggle()
	assert(not machine.IsOpen(), "Toggle should close an open one")
end

--- A CLOSED MENU FOCUSES NOTHING. Otherwise the next opening starts on whichever
--- row the pointer left last time, which reads as the menu remembering a choice
--- nobody made.
local function testClosingForgetsTheFocusedRow()
	local machine = createContextMenu({ Items = items, InitiallyOpen = true })

	hover(machine, "copy", true)
	assert(machine.FocusedId() == "copy", "a hovered row is the focused row")

	machine.Close()
	assert(machine.FocusedId() == nil, "a closed menu focuses nothing")
end

--- THE ONE THAT MATTERS FOR A CONTROLLED CALLER. A right-click menu sits inside
--- something that already holds the flag next to the anchor it captured, and a
--- machine that mirrored that flag would be one frame behind on every opening.
local function testAControlledFlagIsReadThroughRatherThanCopied()
	local open = false
	local closes = 0
	local machine = createContextMenu({
		Items = items,
		IsOpen = function(): boolean
			return open
		end,
		OnClose = function()
			closes += 1
			open = false
		end,
	})

	assert(not machine.IsOpen(), "the machine should answer with the caller's flag")
	open = true
	assert(machine.IsOpen(), "a flag the caller changed should be visible immediately")

	machine.Close()
	assert(closes == 1, "a controlled close should reach the caller")
	assert(not machine.IsOpen(), "and the caller's own flag is what closed it")

	machine.Close()
	assert(closes == 1, "closing what is already closed should tell nobody twice")
end

local function testOpenChangesAreAnnouncedOnce()
	local seen: { boolean } = {}
	local closes = 0
	local machine = createContextMenu({
		Items = items,
		OnOpenChanged = function(open: boolean)
			table.insert(seen, open)
		end,
		OnClose = function()
			closes += 1
		end,
	})

	machine.Open()
	machine.Open()
	machine.Close()

	assert(#seen == 2 and seen[1] == true and seen[2] == false, `an open and a close, got {#seen} change(s)`)
	assert(closes == 1, "OnClose belongs to the transition, not to the call")
end

local function testHoverFocusesAndLeavingClearsIt()
	--- RECORDED AS A NAME RATHER THAN AS THE ID, because `table.insert` with a
	--- nil is a no-op and an unfocus would count as nothing having happened.
	local focused: { string } = {}
	local machine = createContextMenu({
		Items = items,
		InitiallyOpen = true,
		OnFocusChanged = function(id: string?)
			table.insert(focused, id or "nothing")
		end,
	})

	hover(machine, "cut", true)
	assert(machine.IsItemFocused("cut"), "hovering a row should focus it")

	hover(machine, "cut", false)
	assert(not machine.IsItemFocused("cut"), "leaving the row should unfocus it")

	--- LEAVING A ROW THAT IS NOT THE FOCUSED ONE CHANGES NOTHING. Two rows
	--- report their hovers in whatever order the router resolves them, and an
	--- unconditional clear would let the row being left erase the focus of the
	--- row being entered.
	hover(machine, "copy", true)
	hover(machine, "cut", false)
	assert(machine.IsItemFocused("copy"), "a stale leave should not steal the new focus")

	assert(#focused == 3, `three focus changes, got {#focused}`)
	assert(focused[2] == "nothing", "the middle one is the row being left")
end

local function testFocusSkipsDisabledRowsAndWraps()
	local machine = createContextMenu({ Items = items, InitiallyOpen = true })

	machine.FocusNext()
	assert(machine.FocusedId() == "cut", "the first move should land on the first row")
	machine.FocusNext()
	assert(machine.FocusedId() == "copy", "and then the second")
	machine.FocusNext()
	assert(machine.FocusedId() == "delete", "a disabled row cannot take focus and is skipped")
	machine.FocusNext()
	assert(machine.FocusedId() == "cut", "focus wraps at the end")

	machine.FocusPrevious()
	assert(machine.FocusedId() == "delete", "backwards wraps too")
	machine.FocusPrevious()
	assert(machine.FocusedId() == "copy", "and skips the disabled row on the way back")
end

--- THE ORDER IS THE DECISION. A row whose handler opens another menu would be
--- shut again by the dismissal of the one that invoked it if these ran the other
--- way round.
local function testActivationClosesBeforeItCalls()
	local order: { string } = {}
	local list: { Item } = {
		{
			Id = "rename",
			Label = "Rename",
			OnActivated = function()
				table.insert(order, "handler")
			end,
		},
	}

	local machine = createContextMenu({
		Items = list,
		InitiallyOpen = true,
		OnClose = function()
			table.insert(order, "close")
		end,
		OnItemActivated = function(item: any)
			table.insert(order, `activated:{item.Id}`)
		end,
	})

	machine.GetItemProps("rename").OnActivated()

	assert(order[1] == "close", `the menu should close first, got {order[1]}`)
	assert(order[2] == "handler", `then the row's own handler, got {order[2]}`)
	assert(order[3] == "activated:rename", "and the machine's own listener last")
	assert(not machine.IsOpen(), "an activated menu is closed")
end

local function testADisabledRowDoesNothing()
	local machine = createContextMenu({ Items = items, InitiallyOpen = true })

	machine.GetItemProps("paste").OnActivated()
	assert(machine.IsOpen(), "activating a disabled row should not close the menu")

	machine.ActivateItem("nothing-by-that-name")
	assert(machine.IsOpen(), "activating a row that is not there should do nothing at all")

	assert(machine.GetItemProps("paste").Disabled() == true, "a disabled row says so to whatever draws it")
	assert(machine.GetItemProps("cut").Disabled() == false, "and an enabled one says that")
end

--- Dismissal is the surface noticing something outside it; what that MEANS is
--- the machine's, and it means closed.
local function testDismissalClosesTheMenu()
	local machine = createContextMenu({ Items = items, InitiallyOpen = true })
	local surface = machine.GetSurfaceProps()

	assert(surface.Visible() == true, "an open menu is visible")
	surface.OnDismiss()
	assert(not machine.IsOpen(), "a dismissed menu is closed")
	assert(surface.Visible() == false, "and the props already handed out follow it")
end

local function testThePropsAreSpreadable()
	local machine = createContextMenu({ Items = items, InitiallyOpen = true })

	local child = { aChild = true }
	local surface = machine.GetSurfaceProps({
		Name = "AetherContextMenu",
		ZIndex = 100,
		Items = items,
		OnClose = function() end,
		child,
	})

	assert(surface.Name == "AetherContextMenu", "a caller's name should win over the default")
	assert(surface.ZIndex == 100, "anything the machine does not claim should pass through")
	assert(surface.Items == nil, "the item list belongs to the machine")
	assert(surface.OnClose == nil, "a machine option is not a property of the element")
	assert(surface[1] == child, "children should keep their place in the array part")

	local row = machine.GetItemProps("cut", { BorderSizePixel = 0 })
	assert(row.Name == "Item_cut", "a row is named after the item it draws")
	assert(row.BorderSizePixel == 0, "a caller's drawing property survives")
	assert(type(row.OnActivated) == "function", "and the behaviour comes from the machine")
end

--- The sources are a PORT, and the closure inside the machine is only what runs
--- when no caller supplies one. A binding passes `vide.source` and expects every
--- write to go through it.
local function testWritesGoThroughTheSuppliedSource()
	local writes = 0
	local machine = createContextMenu({
		Items = items,
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

	machine.Open()
	hover(machine, "copy", true)
	machine.Close()

	--- FOUR, NOT THREE: closing also clears the focused row, and that is a second
	--- source this machine owns rather than a bookkeeping detail -- a binding
	--- derives a row's fill from it and has to be told.
	assert(writes == 4, `open, focus, close and the focus it cleared, got {writes}`)
	assert(not machine.IsOpen(), "the supplied source should be the one the machine reads back")
end

T.test("it opens and closes", testItOpensAndCloses, "math")
T.test("closing forgets the focused row", testClosingForgetsTheFocusedRow, "math")
T.test("a controlled flag is read through rather than copied", testAControlledFlagIsReadThroughRatherThanCopied, "math")
T.test("open changes are announced once", testOpenChangesAreAnnouncedOnce, "math")
T.test("hover focuses and leaving clears it", testHoverFocusesAndLeavingClearsIt, "math")
T.test("focus skips disabled rows and wraps", testFocusSkipsDisabledRowsAndWraps, "math")
T.test("activation closes before it calls", testActivationClosesBeforeItCalls, "math")
T.test("a disabled row does nothing", testADisabledRowDoesNothing, "math")
T.test("dismissal closes the menu", testDismissalClosesTheMenu, "math")
T.test("the props are spreadable", testThePropsAreSpreadable, "math")
T.test("writes go through the supplied source", testWritesGoThroughTheSuppliedSource, "math")

return T.run("createContextMenu")
