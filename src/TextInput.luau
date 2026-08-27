--!strict
local isScriptInstance = typeof(script) == "Instance"
local Deps = require("./Deps")
--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, UDim, Vector2, Color3, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.UDim, Deps.Vocabulary.Vector2, Deps.Vocabulary.Color3, Deps.Vocabulary.Enum

local vide = Deps.vide
local create = vide.create
local source = vide.source
local action = vide.action
local effect = vide.effect
local cleanup = vide.cleanup

--- Renamed from PressableFrame and moved into primitives/ in ms-51 M14.
local PressableFrame = if isScriptInstance
	then require((script :: any).Parent.primitives.Pressable)
	else require("./primitives/Pressable")
local TextInputManager = require("./TextInputManager")
local InputScope = require("./InputScope")

local isRoblox = typeof(game) == "Instance"
local TextService = if isRoblox then game:GetService("TextService") else nil
local UserInputService = if isRoblox then game:GetService("UserInputService") else nil
local RunService = if isRoblox then game:GetService("RunService") else nil

--- ONE SOURCE OF TEXT METRICS (ms-52 M3).
---
--- The headless branch of this used to be `#text * (textSize * 0.55)` -- a
--- uniform advance, which is exactly what D-text_metrics_provider rejected for
--- ms-52 M1: it reports a plausible width for every string while being wrong
--- about all of them. Two strings of equal LENGTH measured identically, so a
--- caret placed after "iii" and after "WWW" landed in the same place.
---
--- Worse than being wrong, it was wrong DIFFERENTLY from everything else: layout
--- measures through `Host.Text`, so the caret and the glyphs it sits between
--- were being positioned by two unrelated approximations.
---
--- `Host.Text.Measure` is that one source. In Roblox its provider is the
--- engine's own synchronous `GetTextSize`, so this is the same number it always
--- was there; off-engine it is the per-glyph advance table, or whatever richer
--- provider the host registered (the web host registers browser metrics).
local function measureTextWidth(text: string, font: any, textSize: number): number
	if text == "" then return 0 end
	if isRoblox and TextService then
		local ok, sz = pcall(function()
			return TextService:GetTextSize(text, textSize, font or Enum.Font.SourceSans, Vector2.new(10000, 10000))
		end)
		if ok and sz then
			return sz.X
		end
	end
	local width = Deps.Host.Text.Measure(text, textSize, nil)
	return width
end

--- Maps local X pixel offset (relative to text start) to character boundary index.
--- Accurately resolves left-of-center vs right-of-center clicks.
local function mapLocalXToCharIndex(localX: number, text: string, font: any, textSize: number): number
	if localX <= 0 or text == "" then return 1 end
	local totalLen = #text
	local prevW = 0
	for i = 1, totalLen do
		local nextW = measureTextWidth(string.sub(text, 1, i), font, textSize)
		local mid = (prevW + nextW) / 2
		if localX < mid then
			return i
		end
		prevW = nextW
	end
	return totalLen + 1
end

--- Finds word boundaries (contiguous alphanumeric/identifiers, whitespace, or punctuation) around charIdx.
local function findWordBoundaries(text: string, charIdx: number): (number, number)
	local len = #text
	if len == 0 then return 1, 1 end
	local idx = math.clamp(charIdx, 1, len)

	local targetChar = string.sub(text, idx, idx)
	local isWordChar = string.match(targetChar, "[%w_]") ~= nil
	local isWhitespace = string.match(targetChar, "%s") ~= nil

	local pattern = if isWordChar then "[%w_]" elseif isWhitespace then "%s" else "[^%w_%s]"

	local startIdx = idx
	while startIdx > 1 and string.match(string.sub(text, startIdx - 1, startIdx - 1), pattern) do
		startIdx -= 1
	end

	local endIdx = idx
	while endIdx < len and string.match(string.sub(text, endIdx + 1, endIdx + 1), pattern) do
		endIdx += 1
	end

	return startIdx, endIdx + 1
end

export type TextInputProps = {
	Value: (string | () -> string)?,
	PlaceholderText: (string | () -> string)?,
	IsReadOnly: (boolean | () -> boolean)?,
	Disabled: (boolean | () -> boolean)?,
	ClearTextOnFocus: (boolean | () -> boolean)?,
	MultiLine: boolean?,
	Font: any?,
	TextSize: (number | () -> number)?,
	TextColor3: any?,
	PlaceholderColor3: any?,
	TextXAlignment: Enum.TextXAlignment?,
	TextYAlignment: Enum.TextYAlignment?,
	Size: any?,
	Position: any?,
	AnchorPoint: any?,
	LayoutOrder: number?,
	ZIndex: any?,
	BackgroundTransparency: any?,
	BackgroundColor3: any?,
	BorderSizePixel: any?,
	BorderColor3: any?,

	-- Virtual Caret & Selection Visual Props
	CaretColor3: any?,
	CaretWidth: (number | () -> number)?,
	SelectionColor3: any?,
	SelectionTransparency: (number | () -> number)?,
	SelectionCornerRadius: UDim?,

	-- Reactive interaction state signals / out-params
	IsFocused: ((isFocused: boolean) -> ())?,
	IsHovered: ((isHovered: boolean) -> ())?,

	-- Events
	OnChanged: ((newText: string) -> ())?,
	OnCommitted: ((newText: string, enterPressed: boolean) -> ())?,
	OnFocusGained: (() -> ())?,
	OnFocusLost: (() -> ())?,
	OnHoverChanged: ((isHovered: boolean) -> ())?,

	[any]: any,
}

--- TextInput: Pure Virtual Text Input Base Primitive in Aether.
---
--- Features:
--- 1. 100% Virtual: Contains zero native TextBox instances in the DOM tree.
--- 2. Blinking Caret: Precise pixel positioning via TextService text measurement.
--- 3. Selection Highlight: Deterministic selection quad behind selected characters.
--- 4. Double-Click Word Selection: Expands selection over continuous word/punctuation tokens.
--- 5. Sub-pixel Character Boundary: Left-of-center / Right-of-center click resolution.
--- 6. Mouse Drag Selection: Maps mouse coordinates to character indices and syncs with proxy.
--- 7. Themeable: Completely unstyled by default, exposing full styling hooks to components.
local function TextInput(props: TextInputProps)
	local isHovered = source(false)
	local isFocused = source(false)
	local localBuffer = source("")
	local cursorPosition = source(1)
	local selectionStart = source(-1)
	local caretBlink = source(true)

	local frameRef: Frame? = nil
	local displayLabelRef: TextLabel? = nil
	local fieldId = {}
	local isDragging = false
	--- Did the press already place the caret? (ms-52 M3)
	---
	--- In Roblox the InputBegan handler below places the caret on PRESS and may
	--- then extend a selection by dragging. `OnActivated` fires on RELEASE, so if
	--- it also placed the caret it would collapse that selection every time.
	---
	--- The flag is set by whichever path handled the press, so the release path
	--- does not have to ask which host it is in -- which is the point, because
	--- off-engine NOTHING handles the press and the release must do the work.
	local pressPlacedCaret = false
	local dragAnchorIndex = 1
	local lastClickTime = 0
	local lastClickPos = Vector2.zero

	local isReadOnlyVal = function()
		if props.IsReadOnly then
			return if type(props.IsReadOnly) == "function" then props.IsReadOnly() else props.IsReadOnly
		end
		return false
	end

	local isDisabledVal = function()
		if props.Disabled then
			return if type(props.Disabled) == "function" then props.Disabled() else props.Disabled
		end
		return false
	end

	local clearOnFocusVal = function()
		if props.ClearTextOnFocus ~= nil then
			return if type(props.ClearTextOnFocus) == "function" then props.ClearTextOnFocus() else props.ClearTextOnFocus
		end
		return false
	end

	local currentExternalText = function()
		local val = props.Value
		if val == nil then
			val = (props :: any).Text
		end
		if val ~= nil then
			return if type(val) == "function" then (val :: any)() else tostring(val)
		end
		return ""
	end

	local getActiveFont = function()
		local f = if type(props.Font) == "function" then props.Font() else props.Font
		return f or Enum.Font.SourceSans
	end

	local getActiveTextSize = function()
		local s = if type(props.TextSize) == "function" then props.TextSize() else props.TextSize
		return s or 14
	end

	-- Caret blinking timer: 530ms toggle while focused
	if isRoblox and RunService then
		local timeAcc = 0
		local conn = RunService.RenderStepped:Connect(function(dt)
			if isFocused() then
				timeAcc += dt
				if timeAcc >= 0.53 then
					timeAcc = 0
					caretBlink(not caretBlink())
				end
			end
		end)
		cleanup(conn)
	end

	local function resetCaretBlink()
		caretBlink(true)
	end

	local function startEditing(initialCharIndex: number?, initialSelectionStart: number?)
		if isReadOnlyVal() or isDisabledVal() then return end

		local startText = if isFocused() then localBuffer() elseif clearOnFocusVal() then "" else currentExternalText()
		localBuffer(startText)
		isFocused(true)
		resetCaretBlink()

		local initPos = initialCharIndex or (#startText + 1)
		local initSel = initialSelectionStart or -1
		cursorPosition(initPos)
		selectionStart(initSel)

		if props.IsFocused then props.IsFocused(true) end
		if props.OnFocusGained then props.OnFocusGained() end

		TextInputManager.Focus({
			Id = fieldId,
			GetText = function()
				return startText
			end,
			SetText = function(text)
				localBuffer(text)
				resetCaretBlink()
			end,
			OnSelectionChanged = function(cPos, sStart)
				cursorPosition(cPos)
				selectionStart(sStart)
				resetCaretBlink()
			end,
			OnChanged = function(text)
				if props.OnChanged then
					props.OnChanged(text)
				end
				if (props :: any).OnTextChanged then
					(props :: any).OnTextChanged(text)
				end
			end,
			OnCommitted = function(committedText, enterPressed)
				isFocused(false)
				selectionStart(-1)
				if props.IsFocused then props.IsFocused(false) end
				if props.OnCommitted then
					props.OnCommitted(committedText, enterPressed)
				end
			end,
			OnFocusLost = function()
				isFocused(false)
				selectionStart(-1)
				if props.IsFocused then props.IsFocused(false) end
				if props.OnFocusLost then
					props.OnFocusLost()
				end
			end,
			GetBounds = function()
				if frameRef then
					return frameRef.AbsolutePosition, frameRef.AbsoluteSize
				end
				return Vector2.zero, Vector2.zero
			end,
		}, initPos, initSel)
	end

	cleanup(function()
		if TextInputManager.IsFocused(fieldId) then
			TextInputManager.Blur(false)
		end
	end)

	local displayText = function()
		if isFocused() then
			return localBuffer()
		end
		return currentExternalText()
	end

	local showPlaceholder = function()
		local t = displayText()
		return t == "" and not isFocused()
	end

	-- Caret X pixel coordinate calculation
	local caretPositionX = function(): number
		if not isFocused() then return 0 end
		local t = localBuffer()
		local cPos = cursorPosition()
		if cPos <= 1 or t == "" then return 0 end
		local sub = string.sub(t, 1, math.min(#t, cPos - 1))
		return measureTextWidth(sub, getActiveFont(), getActiveTextSize())
	end

	-- Selection highlight quad bounds calculation
	local hasSelection = function(): boolean
		if not isFocused() then return false end
		local sStart = selectionStart()
		local cPos = cursorPosition()
		return sStart ~= -1 and sStart ~= cPos
	end

	local selectionBounds = function(): (number, number)
		local sStart = selectionStart()
		local cPos = cursorPosition()
		if sStart == -1 or sStart == cPos then return 0, 0 end

		local t = localBuffer()
		local minIdx = math.max(1, math.min(sStart, cPos))
		local maxIdx = math.max(1, math.max(sStart, cPos))

		local startX = if minIdx <= 1 then 0 else measureTextWidth(string.sub(t, 1, minIdx - 1), getActiveFont(), getActiveTextSize())
		local endX = if maxIdx <= 1 then 0 else measureTextWidth(string.sub(t, 1, math.min(#t, maxIdx - 1)), getActiveFont(), getActiveTextSize())
		return startX, math.max(0, endX - startX)
	end

	local RESERVED_TEXT_PROPS: { [string]: boolean } = {
		Value = true,
		Text = true,
		PlaceholderText = true,
		Placeholder = true,
		IsReadOnly = true,
		Disabled = true,
		ClearTextOnFocus = true,
		MultiLine = true,
		Font = true,
		TextSize = true,
		TextColor3 = true,
		PlaceholderColor3 = true,
		TextXAlignment = true,
		TextYAlignment = true,
		CaretColor3 = true,
		CaretWidth = true,
		SelectionColor3 = true,
		SelectionTransparency = true,
		SelectionCornerRadius = true,
		IsFocused = true,
		IsHovered = true,
		OnChanged = true,
		OnTextChanged = true,
		OnCommitted = true,
		OnFocusGained = true,
		OnFocusLost = true,
		OnHoverChanged = true,
		OnKeyDown = true,
		OnKeyUp = true,
	}

	local children: { any } = {}
	local passProps: { [any]: any } = {}

	for k, v in pairs(props) do
		if type(k) == "number" then
			table.insert(children, v)
		elseif not RESERVED_TEXT_PROPS[k] then
			passProps[k] = v
		end
	end

	return PressableFrame({
		Name = props.Name or "TextInput",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		BackgroundTransparency = if props.BackgroundTransparency ~= nil then props.BackgroundTransparency else 1,
		BackgroundColor3 = props.BackgroundColor3,
		BorderSizePixel = props.BorderSizePixel or 0,
		BorderColor3 = props.BorderColor3,
		Cursor = props.Cursor or "Text",
		OnHoverChanged = function(h)
			isHovered(h)
			if props.IsHovered then props.IsHovered(h) end
			if props.OnHoverChanged then props.OnHoverChanged(h) end
		end,
		OnActivated = function()
			--- The press already did this; doing it again on release would
			--- collapse any selection the drag just made.
			if pressPlacedCaret then
				pressPlacedCaret = false
				return
			end

			local clickX = 0
			if displayLabelRef then
				local ptrX, _ = InputScope.GetPointerPosition()
				clickX = math.max(0, ptrX - displayLabelRef.AbsolutePosition.X)
			end
			local targetChar = mapLocalXToCharIndex(clickX, currentExternalText(), getActiveFont(), getActiveTextSize())

			if not isFocused() then
				startEditing(targetChar)
			else
				--- REPOSITIONING AN ALREADY-FOCUSED FIELD (ms-52 M3).
				---
				--- This branch did not exist: `OnActivated` acted only when the
				--- field was unfocused, so clicking elsewhere in a field you were
				--- already editing moved nothing. In Roblox that was invisible
				--- because the InputBegan handler above covers it; off-engine
				--- there was nothing to cover it, and the caret was stuck where
				--- the first click put it.
				cursorPosition(targetChar)
				selectionStart(-1)
				resetCaretBlink()
				TextInputManager.SetCursorAndSelection(targetChar, -1)
			end
		end,

		action(function(ref)
			frameRef = ref :: Frame

			-- Mouse click & drag selection support with double-click word expansion
			if isRoblox and ref:IsA("GuiObject") then
				local inputBeganConn = (ref :: GuiObject).InputBegan:Connect(function(input)
					if isReadOnlyVal() or isDisabledVal() then return end
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						local now = os.clock()
						local mousePos = Vector2.new(input.Position.X, input.Position.Y)
						local isDoubleClick = (now - lastClickTime <= 0.35) and ((mousePos - lastClickPos).Magnitude < 15)
						lastClickTime = now
						lastClickPos = mousePos

						local labelX = if displayLabelRef then displayLabelRef.AbsolutePosition.X else ref.AbsolutePosition.X
						local localX = math.max(0, input.Position.X - labelX)
						local curText = displayText()
						local charIdx = mapLocalXToCharIndex(localX, curText, getActiveFont(), getActiveTextSize())

						if isDoubleClick and curText ~= "" then
							local wStart, wEnd = findWordBoundaries(curText, charIdx)
							if not isFocused() then
								startEditing(wEnd, wStart)
							else
								cursorPosition(wEnd)
								selectionStart(wStart)
								resetCaretBlink()
								TextInputManager.SetCursorAndSelection(wEnd, wStart)
							end
							isDragging = false
							pressPlacedCaret = true
							return
						end

						pressPlacedCaret = true
						isDragging = true
						dragAnchorIndex = charIdx

						if not isFocused() then
							startEditing(charIdx, -1)
						else
							cursorPosition(charIdx)
							selectionStart(-1)
							resetCaretBlink()
							TextInputManager.SetCursorAndSelection(charIdx, -1)
						end
					end
				end)

				local inputChangedConn = (ref :: GuiObject).InputChanged:Connect(function(input)
					if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						local labelX = if displayLabelRef then displayLabelRef.AbsolutePosition.X else ref.AbsolutePosition.X
						local localX = math.max(0, input.Position.X - labelX)
						local charIdx = mapLocalXToCharIndex(localX, displayText(), getActiveFont(), getActiveTextSize())
						cursorPosition(charIdx)
						selectionStart(dragAnchorIndex)
						resetCaretBlink()
						TextInputManager.SetCursorAndSelection(charIdx, dragAnchorIndex)
					end
				end)

				local inputEndedConn = (ref :: GuiObject).InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						isDragging = false
					end
				end)

				cleanup(function()
					inputBeganConn:Disconnect()
					inputChangedConn:Disconnect()
					inputEndedConn:Disconnect()
				end)
			end
		end),

		-- Layer 1: Selection Highlight Quad (behind text)
		create("Frame")({
			Name = "SelectionHighlight",
			Visible = hasSelection,
			BackgroundTransparency = function()
				local t = if type(props.SelectionTransparency) == "function" then props.SelectionTransparency() else props.SelectionTransparency
				return t or 0.6
			end,
			BackgroundColor3 = function()
				local sc = if type(props.SelectionColor3) == "function" then props.SelectionColor3() else props.SelectionColor3
				return sc or Color3.fromRGB(0, 120, 215)
			end,
			BorderSizePixel = 0,
			Position = function()
				local startX = selectionBounds()
				return UDim2.new(0, startX, 0.1, 0)
			end,
			Size = function()
				local _, width = selectionBounds()
				return UDim2.new(0, width, 0.8, 0)
			end,
			ZIndex = 1,

			create("UICorner")({
				CornerRadius = props.SelectionCornerRadius or UDim.new(0, 2),
			}),
		}),

		-- Layer 2: Text Display Label
		create("TextLabel")({
			Name = "DisplayLabel",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 2,
			Font = getActiveFont,
			TextSize = getActiveTextSize,
			TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
			TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
			Text = function()
				if showPlaceholder() then
					if props.PlaceholderText then
						return if type(props.PlaceholderText) == "function" then props.PlaceholderText() else props.PlaceholderText
					end
					return ""
				end
				return displayText()
			end,
			TextColor3 = function()
				if showPlaceholder() then
					local pc = if type(props.PlaceholderColor3) == "function" then props.PlaceholderColor3() else props.PlaceholderColor3
					return pc or Color3.fromRGB(120, 120, 120)
				end
				local tc = if type(props.TextColor3) == "function" then props.TextColor3() else props.TextColor3
				return tc or Color3.fromRGB(220, 220, 220)
			end,

			action(function(ref)
				displayLabelRef = ref :: TextLabel
			end),
		}),

		-- Layer 3: Virtual Blinking Caret Line
		create("Frame")({
			Name = "VirtualCaret",
			Visible = function()
				return isFocused() and caretBlink() and not hasSelection()
			end,
			BackgroundColor3 = function()
				local cc = if type(props.CaretColor3) == "function" then props.CaretColor3() else props.CaretColor3
				if cc then return cc end
				local tc = if type(props.TextColor3) == "function" then props.TextColor3() else props.TextColor3
				return tc or Color3.fromRGB(220, 220, 220)
			end,
			BorderSizePixel = 0,
			ZIndex = 3,
			Position = function()
				local x = caretPositionX()
				return UDim2.new(0, x, 0.15, 0)
			end,
			Size = function()
				local w = if type(props.CaretWidth) == "function" then props.CaretWidth() else props.CaretWidth
				return UDim2.new(0, w or 1.5, 0.7, 0)
			end,
		}),

		passProps,
		table.unpack(children),
	})
end

return TextInput
