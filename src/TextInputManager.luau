--!strict
local isRoblox = typeof(game) == "Instance"
local Players = if isRoblox then game:GetService("Players") else nil

local InputScope = require("./InputScope")

--- ms-51 M16: resolved here purely for the value vocabulary below.
local Deps = require("./Deps")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below is unchanged.
local UDim2, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.Enum

local TextInputManager = {}

export type FieldSession = {
	Id: any,
	GetText: () -> string,
	SetText: (text: string) -> (),
	OnChanged: ((newText: string) -> ())?,
	OnSelectionChanged: ((cursorPos: number, selectionStart: number) -> ())?,
	OnCommitted: ((newText: string, enterPressed: boolean) -> ())?,
	OnFocusLost: (() -> ())?,
	GetBounds: (() -> (Vector2, Vector2))?, -- (AbsolutePosition, AbsoluteSize)
}

local activeSession: FieldSession? = nil
local proxyTextBox: any = nil
local proxyGui: any = nil
local isInitialised = false

local function ensureProxy()
	if isInitialised then return end
	isInitialised = true

	if isRoblox and Players and Players.LocalPlayer then
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 5)
		if playerGui then
			local gui = Instance.new("ScreenGui")
			gui.Name = "Spektr_VirtualInputProxy"
			gui.DisplayOrder = 10000
			gui.IgnoreGuiInset = true
			gui.ResetOnSpawn = false
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

			local box = Instance.new("TextBox")
			box.Name = "ProxyInput"
			box.Size = UDim2.fromOffset(1, 1)
			box.Position = UDim2.fromOffset(-1000, -1000)
			box.BackgroundTransparency = 1
			box.TextTransparency = 1
			box.BorderSizePixel = 0
			box.ClearTextOnFocus = false
			box.Visible = false
			box.Parent = gui
			gui.Parent = playerGui

			proxyGui = gui
			proxyTextBox = box

			box:GetPropertyChangedSignal("Text"):Connect(function()
				if activeSession then
					activeSession.SetText(box.Text)
					if activeSession.OnChanged then
						activeSession.OnChanged(box.Text)
					end
					if activeSession.OnSelectionChanged then
						activeSession.OnSelectionChanged(box.CursorPosition, box.SelectionStart)
					end
				end
			end)

			box:GetPropertyChangedSignal("CursorPosition"):Connect(function()
				if activeSession and activeSession.OnSelectionChanged then
					activeSession.OnSelectionChanged(box.CursorPosition, box.SelectionStart)
				end
			end)

			box:GetPropertyChangedSignal("SelectionStart"):Connect(function()
				if activeSession and activeSession.OnSelectionChanged then
					activeSession.OnSelectionChanged(box.CursorPosition, box.SelectionStart)
				end
			end)

			box.FocusLost:Connect(function(enterPressed)
				if not activeSession then return end
				if enterPressed then
					TextInputManager.Blur(true)
					return
				end

				-- Check if click landed within the active field's bounding box
				if activeSession.GetBounds then
					local ptrX, ptrY = InputScope.GetPointerPosition()
					local pos, size = activeSession.GetBounds()
					if ptrX >= (pos.X - 4) and ptrX <= (pos.X + size.X + 4)
						and ptrY >= (pos.Y - 4) and ptrY <= (pos.Y + size.Y + 4) then
						-- The click was inside the active field (e.g. moving caret or drag selecting).
						-- Keep the session alive and recapture engine focus on the proxy.
						pcall(function()
							proxyTextBox:CaptureFocus()
						end)
						return
					end
				end

				TextInputManager.Blur(false)
			end)
		end
	end

	if not proxyTextBox then
		-- Headless test double
		proxyTextBox = {
			Text = "",
			CursorPosition = 1,
			SelectionStart = -1,
			CaptureFocus = function(self) end,
			ReleaseFocus = function(self, enterPressed)
				if activeSession then
					local session = activeSession
					activeSession = nil
					if session.OnCommitted then
						session.OnCommitted(self.Text, enterPressed or false)
					end
					if session.OnFocusLost then
						session.OnFocusLost()
					end
				end
			end,
			Size = UDim2.new(),
			Position = UDim2.new(),
		}
	end
end

--- Focus a virtual text input field.
---
--- Commits and blurs any previously active field, moves the hidden proxy TextBox
--- to the field's screen position, syncs text, and requests engine keyboard capture.
function TextInputManager.Focus(field: FieldSession, initialCursorPos: number?, initialSelectionStart: number?)
	ensureProxy()

	if activeSession and activeSession.Id ~= field.Id then
		TextInputManager.Blur(false)
	end

	activeSession = field
	local initialText = field.GetText()
	proxyTextBox.Text = initialText

	local cPos = initialCursorPos or (#initialText + 1)
	local sStart = initialSelectionStart or -1
	pcall(function()
		proxyTextBox.SelectionStart = sStart
		proxyTextBox.CursorPosition = cPos
	end)

	if isRoblox and proxyTextBox and field.GetBounds then
		local pos, size = field.GetBounds()
		proxyTextBox.Position = UDim2.fromOffset(pos.X, pos.Y)
		proxyTextBox.Size = UDim2.fromOffset(math.max(1, size.X), math.max(1, size.Y))
	end

	pcall(function()
		proxyTextBox:CaptureFocus()
	end)

	if field.OnSelectionChanged then
		field.OnSelectionChanged(cPos, sStart)
	end
end

--- Update the proxy's cursor position and selection start from mouse interaction.
function TextInputManager.SetCursorAndSelection(cursorPos: number, selectionStart: number)
	if not proxyTextBox then return end
	pcall(function()
		proxyTextBox.SelectionStart = selectionStart
		proxyTextBox.CursorPosition = cursorPos
	end)
	if activeSession and activeSession.OnSelectionChanged then
		activeSession.OnSelectionChanged(cursorPos, selectionStart)
	end
end

--- Release focus from the currently active text input field.
function TextInputManager.Blur(enterPressed: boolean?)
	if not activeSession then return end
	ensureProxy()

	local session = activeSession
	activeSession = nil

	local committedText = proxyTextBox.Text
	if session.OnCommitted then
		session.OnCommitted(committedText, enterPressed or false)
	end
	if session.OnFocusLost then
		session.OnFocusLost()
	end

	pcall(function()
		proxyTextBox:ReleaseFocus(enterPressed or false)
	end)
end

--- Get the currently active field session, or nil if no field is focused.
function TextInputManager.GetActiveField(): FieldSession?
	return activeSession
end

--- Check if a specific field is currently focused.
function TextInputManager.IsFocused(fieldId: any): boolean
	return activeSession ~= nil and activeSession.Id == fieldId
end

--- THE EDITING MODEL, WHICH USED TO BE THE ENGINE'S (ms-52 M3).
---
--- Everything above assumes something else turns keystrokes into text: the proxy
--- TextBox is focused, Roblox edits it, and this module reacts to the finished
--- string. That is a good design in Roblox -- the engine handles IME, mobile
--- keyboards, clipboard and selection gestures, and none of that is worth
--- reimplementing.
---
--- It also meant there was no editing model here AT ALL. `_SimulateTyping` hands
--- over a finished string, so it could never have revealed the gap; the second
--- host did, immediately, because a browser reports KEYS and there was nothing
--- to give them to. Same shape as the scrollbar drag and the wheel: the
--- surrounding logic was portable and the input was not.
---
--- So the model lives here now, host-agnostic, operating on the same (text,
--- cursor, selection) triple the proxy holds. Roblox keeps using the native
--- TextBox -- this is not wired in there, because replacing a working IME-aware
--- editor with a hand-rolled one would be a downgrade. Off-engine it IS the
--- editor.
---
--- CURSOR CONVENTION, matching Roblox's TextBox so both paths speak one language:
--- `CursorPosition` is 1-based and sits BEFORE the character at that index, so it
--- ranges over 1..#text+1. `SelectionStart` is -1 for no selection, otherwise the
--- other end of the range -- which may be before OR after the cursor.
local function selectionRange(cursor: number, sel: number): (number, number)
	if sel == -1 or sel == cursor then
		return cursor, cursor
	end
	return math.min(cursor, sel), math.max(cursor, sel)
end

--- Push edited state back onto the proxy and tell the field about it.
local function commitEdit(text: string, cursor: number, sel: number, textChanged: boolean)
	proxyTextBox.Text = text
	proxyTextBox.CursorPosition = cursor
	proxyTextBox.SelectionStart = sel

	local session = activeSession
	if not session then
		return
	end
	if textChanged then
		session.SetText(text)
		if session.OnChanged then
			session.OnChanged(text)
		end
	end
	if session.OnSelectionChanged then
		session.OnSelectionChanged(cursor, sel)
	end
end

export type KeyModifiers = { Shift: boolean?, Ctrl: boolean? }

--- Apply one key to the focused field. Returns whether it was consumed.
---
--- `key` is either a single character to insert, or one of the named editing
--- keys below. Unknown keys are ignored rather than inserted, so a host that
--- forwards "F5" or "ArrowUp" cannot corrupt the text.
function TextInputManager.HandleKey(key: string, modifiers: KeyModifiers?): boolean
	if not activeSession then
		return false
	end
	ensureProxy()

	local mods = modifiers or {}
	local text: string = proxyTextBox.Text or ""
	local cursor: number = proxyTextBox.CursorPosition or (#text + 1)
	local sel: number = proxyTextBox.SelectionStart or -1
	cursor = math.clamp(cursor, 1, #text + 1)

	local lo, hi = selectionRange(cursor, sel)
	local hasSelection = hi > lo

	local function deleteSelection(): string
		local next = string.sub(text, 1, lo - 1) .. string.sub(text, hi)
		cursor = lo
		sel = -1
		return next
	end

	--- Moving the caret with Shift held EXTENDS the selection, which means
	--- remembering where it started the first time. Without this the anchor
	--- follows the caret and a shift-arrow selects nothing.
	local function moveTo(position: number)
		if mods.Shift then
			if sel == -1 then
				sel = cursor
			end
		else
			sel = -1
		end
		cursor = math.clamp(position, 1, #text + 1)
	end

	if key == "Backspace" then
		if hasSelection then
			text = deleteSelection()
		elseif cursor > 1 then
			text = string.sub(text, 1, cursor - 2) .. string.sub(text, cursor)
			cursor -= 1
			sel = -1
		else
			return true
		end
		commitEdit(text, cursor, sel, true)
		return true
	elseif key == "Delete" then
		if hasSelection then
			text = deleteSelection()
		elseif cursor <= #text then
			text = string.sub(text, 1, cursor - 1) .. string.sub(text, cursor + 1)
			sel = -1
		else
			return true
		end
		commitEdit(text, cursor, sel, true)
		return true
	elseif key == "Left" then
		--- An unshifted arrow with a selection collapses to its EDGE rather than
		--- stepping from the caret, which is what every text field does.
		if hasSelection and not mods.Shift then
			cursor, sel = lo, -1
		else
			moveTo(cursor - 1)
		end
		commitEdit(text, cursor, sel, false)
		return true
	elseif key == "Right" then
		if hasSelection and not mods.Shift then
			cursor, sel = hi, -1
		else
			moveTo(cursor + 1)
		end
		commitEdit(text, cursor, sel, false)
		return true
	elseif key == "Home" then
		moveTo(1)
		commitEdit(text, cursor, sel, false)
		return true
	elseif key == "End" then
		moveTo(#text + 1)
		commitEdit(text, cursor, sel, false)
		return true
	elseif key == "SelectAll" or (mods.Ctrl and (key == "a" or key == "A")) then
		cursor, sel = #text + 1, 1
		commitEdit(text, cursor, sel, false)
		return true
	elseif key == "Enter" then
		TextInputManager.Blur(true)
		return true
	elseif key == "Escape" then
		TextInputManager.Blur(false)
		return true
	elseif #key == 1 then
		--- A printable character. Control bytes are refused: a browser reports
		--- Tab and Escape as one-character strings in some layouts, and inserting
		--- a literal tab into a single-line field is never what was meant.
		local byte = string.byte(key)
		if byte < 32 or byte == 127 then
			return false
		end
		if mods.Ctrl then
			return false
		end
		if hasSelection then
			text = deleteSelection()
		end
		text = string.sub(text, 1, cursor - 1) .. key .. string.sub(text, cursor)
		cursor += 1
		sel = -1
		commitEdit(text, cursor, sel, true)
		return true
	end

	return false
end

--- Where the caret and selection currently are. Test seam, and what a host needs
--- in order to draw them.
function TextInputManager.GetSelection(): (number, number)
	if not proxyTextBox then
		return 1, -1
	end
	return proxyTextBox.CursorPosition or 1, proxyTextBox.SelectionStart or -1
end

--- Headless test helper to simulate typing into the proxy.
function TextInputManager._SimulateTyping(text: string, cursorPos: number?, selectionStart: number?)
	ensureProxy()
	proxyTextBox.Text = text
	proxyTextBox.CursorPosition = cursorPos or (#text + 1)
	proxyTextBox.SelectionStart = selectionStart or -1
	if activeSession then
		activeSession.SetText(text)
		if activeSession.OnChanged then
			activeSession.OnChanged(text)
		end
		if activeSession.OnSelectionChanged then
			activeSession.OnSelectionChanged(proxyTextBox.CursorPosition, proxyTextBox.SelectionStart)
		end
	end
end

return TextInputManager
