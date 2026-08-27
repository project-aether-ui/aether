--!strict
--!tier math
--[=[
	The editing model, off-engine (ms-52 M3).

	WHY THIS SUITE EXISTS
	Until now there was no editing model in this repo at all. The proxy TextBox is
	focused and ROBLOX turns keystrokes into text; this module reacted to the
	finished string. `_SimulateTyping` hands over a finished string too, so no
	existing test could have noticed the gap -- it tested the reaction, never the
	edit.

	The second host found it the moment a browser reported a KEY and there was
	nothing to give it to. Same shape as the scrollbar drag and the wheel: the
	logic around the input was portable, the input was not.

	What is asserted here is the ARITHMETIC of editing -- exact strings, exact
	caret indices -- because a caret that lands one character off is the whole
	difference between a working field and an unusable one, and "the text changed"
	would pass for both.
]=]
local T = require("@testkit")
local TextInputManager = require("../src/TextInputManager")

--- A minimal field: the manager only needs to get and set a string.
local function field(initial: string)
	local text = initial
	local changes = 0
	local committed: string? = nil
	local enterWasPressed: boolean? = nil
	local session = {
		Id = {},
		GetText = function()
			return text
		end,
		SetText = function(next: string)
			text = next
		end,
		OnChanged = function()
			changes += 1
		end,
		OnCommitted = function(final: string, enter: boolean)
			committed = final
			enterWasPressed = enter
		end,
	}
	return {
		Session = session,
		Text = function()
			return text
		end,
		Changes = function()
			return changes
		end,
		Committed = function()
			return committed
		end,
		EnterPressed = function()
			return enterWasPressed
		end,
	}
end

local function focus(initial: string, cursor: number?)
	local f = field(initial)
	TextInputManager.Focus(f.Session, cursor or (#initial + 1))
	return f
end

local function typeString(str: string)
	for i = 1, #str do
		TextInputManager.HandleKey(string.sub(str, i, i))
	end
end

local function testTypingInsertsAtTheCaret()
	local f = focus("", 1)
	typeString("hello")
	assert(f.Text() == "hello", "typing should build the string, got " .. f.Text())
	local cursor = TextInputManager.GetSelection()
	assert(cursor == 6, "the caret should sit after the last character, got " .. cursor)

	--- INSERT IN THE MIDDLE, which is where an append-only implementation fails
	--- while still passing the assertion above.
	TextInputManager.HandleKey("Home")
	typeString(">")
	assert(f.Text() == ">hello", "Home then type should insert at the front, got " .. f.Text())
	local c2 = TextInputManager.GetSelection()
	assert(c2 == 2, "the caret should follow the inserted character, got " .. c2)
end

local function testBackspaceAndDelete()
	local f = focus("abcd")
	TextInputManager.HandleKey("Backspace")
	assert(f.Text() == "abc", "Backspace removes the character BEFORE the caret, got " .. f.Text())

	TextInputManager.HandleKey("Home")
	TextInputManager.HandleKey("Delete")
	assert(f.Text() == "bc", "Delete removes the character AT the caret, got " .. f.Text())

	--- At the ends they must be no-ops rather than errors or wraps.
	TextInputManager.HandleKey("Home")
	TextInputManager.HandleKey("Backspace")
	assert(f.Text() == "bc", "Backspace at the start does nothing")
	TextInputManager.HandleKey("End")
	TextInputManager.HandleKey("Delete")
	assert(f.Text() == "bc", "Delete at the end does nothing")
end

local function testCaretMovementAndSelection()
	local f = focus("abcd")
	TextInputManager.HandleKey("Left")
	local c = TextInputManager.GetSelection()
	assert(c == 4, "Left moves the caret back one, got " .. c)

	--- Shift extends a selection; the anchor must be remembered from the FIRST
	--- shifted press, or it follows the caret and nothing is ever selected.
	TextInputManager.HandleKey("Left", { Shift = true })
	TextInputManager.HandleKey("Left", { Shift = true })
	local cursor, sel = TextInputManager.GetSelection()
	assert(cursor == 2 and sel == 4, "shift-Left twice should select b..c, got " .. cursor .. "/" .. sel)

	--- Typing over a selection replaces it.
	TextInputManager.HandleKey("X")
	assert(f.Text() == "aXd", "typing over a selection replaces it, got " .. f.Text())
	local _, sel2 = TextInputManager.GetSelection()
	assert(sel2 == -1, "and clears the selection")
end

local function testUnshiftedArrowCollapsesToTheEdge()
	local f = focus("abcd", 1)
	TextInputManager.HandleKey("Right", { Shift = true })
	TextInputManager.HandleKey("Right", { Shift = true })
	local cursor, sel = TextInputManager.GetSelection()
	assert(cursor == 3 and sel == 1, "expected a..b selected, got " .. cursor .. "/" .. sel)

	--- An unshifted arrow with a selection collapses to its EDGE rather than
	--- stepping from the caret -- what every text field does, and a detail a
	--- from-scratch implementation reliably gets wrong.
	TextInputManager.HandleKey("Left")
	local c2, s2 = TextInputManager.GetSelection()
	assert(c2 == 1 and s2 == -1, "Left should collapse to the selection start, got " .. c2 .. "/" .. s2)
	assert(f.Text() == "abcd", "and must not alter the text")
end

local function testSelectAllAndDelete()
	local f = focus("abcd")
	TextInputManager.HandleKey("a", { Ctrl = true })
	local cursor, sel = TextInputManager.GetSelection()
	assert(cursor == 5 and sel == 1, "ctrl-A selects everything, got " .. cursor .. "/" .. sel)
	--- And it must NOT have typed the letter.
	assert(f.Text() == "abcd", "ctrl-A must not insert a character, got " .. f.Text())

	TextInputManager.HandleKey("Backspace")
	assert(f.Text() == "", "Backspace over a full selection clears the field, got " .. f.Text())
end

local function testEnterCommitsAndEscapeDoesNot()
	local f = focus("typed")
	TextInputManager.HandleKey("Enter")
	assert(f.Committed() == "typed", "Enter commits the text, got " .. tostring(f.Committed()))
	assert(f.EnterPressed() == true, "and reports that Enter was the cause")
	assert(TextInputManager.GetActiveField() == nil, "and releases focus")

	local g = focus("other")
	TextInputManager.HandleKey("Escape")
	assert(g.EnterPressed() == false, "Escape reports that Enter was NOT the cause")
	assert(TextInputManager.GetActiveField() == nil, "and also releases focus")
end

local function testUnknownKeysAreIgnored()
	local f = focus("abc")
	local before = f.Changes()
	--- A host forwarding browser key names must not be able to corrupt the text.
	for _, key in ipairs({ "F5", "ArrowUp", "PageDown", "Shift", "Meta" }) do
		TextInputManager.HandleKey(key)
	end
	assert(f.Text() == "abc", "unknown keys must not edit the text, got " .. f.Text())
	assert(f.Changes() == before, "and must not report a change")

	--- Control bytes are refused too: some layouts report Tab and Escape as
	--- one-character strings, and a literal tab in a single-line field is never
	--- what was meant.
	TextInputManager.HandleKey(string.char(9))
	assert(f.Text() == "abc", "a control byte is not inserted")
end

local function testKeysWithNoFocusedFieldAreRefused()
	TextInputManager.Blur(false)
	assert(TextInputManager.HandleKey("x") == false, "a key with nothing focused is not consumed")
end

T.test("typing inserts at the caret, including mid-string", testTypingInsertsAtTheCaret, "math")
T.test("Backspace and Delete remove the right side, and no-op at the ends", testBackspaceAndDelete, "math")
T.test("arrows move the caret and Shift extends a selection", testCaretMovementAndSelection, "math")
T.test("an unshifted arrow collapses a selection to its edge", testUnshiftedArrowCollapsesToTheEdge, "math")
T.test("ctrl-A selects all without typing the letter", testSelectAllAndDelete, "math")
T.test("Enter commits, Escape does not", testEnterCommitsAndEscapeDoesNot, "math")
T.test("unknown keys and control bytes are ignored", testUnknownKeysAreIgnored, "math")
T.test("keys with no focused field are refused", testKeysWithNoFocusedFieldAreRefused, "math")

return T.run("TextEditing")
