--!strict
--[=[
	Scrollbar — Headless Scrollbar Track & Thumb Primitive
	Part of Aether.Primitives (Layer 2).

	Directly binds to Aether.Primitives.PressableFrame & PointerRouter
	without requiring Active property or engine GuiButton constraints.
	Consumes all 12 style packages with full slot and token polymorphism.
]=]

local isRoblox = typeof(game) == "Instance"
local isScriptInstance = typeof(script) == "Instance"

local function loadSibling(name: string): any
	if isScriptInstance then
		local parent = (script :: any).Parent
		if parent and parent:FindFirstChild(name) then
			return require(parent[name])
		end
		local root = parent and parent.Parent
		if root and root:FindFirstChild(name) then
			return require(root[name])
		end
		if root and root:FindFirstChild("controllers") and root.controllers:FindFirstChild(name) then
			return require(root.controllers[name])
		end
		if root and root:FindFirstChild("src") and root.src:FindFirstChild(name) then
			return require(root.src[name])
		end
		if root and root:FindFirstChild("src") and root.src:FindFirstChild("controllers") and root.src.controllers:FindFirstChild(name) then
			return require(root.src.controllers[name])
		end
	end
	local ok, res = pcall(require, "./" .. name)
	if ok then return res end
	local ok2, res2 = pcall(require, "../" .. name)
	if ok2 then return res2 end
	local ok3, res3 = pcall(require, "../../src/" .. name)
	if ok3 then return res3 end
	local ok4, res4 = pcall(require, "../controllers/" .. name)
	if ok4 then return res4 end
	local ok5, res5 = pcall(require, "../../src/controllers/" .. name)
	if ok5 then return res5 end
	return {}
end

local Deps = loadSibling("Deps")
local ScrollController = loadSibling("ScrollController")
--- Renamed from PressableFrame in ms-51 M14; same primitive.
local PressableFrame = loadSibling("Pressable")
local PointerRouter = loadSibling("PointerRouter")
local InputScope = loadSibling("InputScope")

--- ms-51 M16: the motion SEAM, not Flux. Aether is a genuine consumer of
--- springs, so this edge could not be reversed like the component seams —
--- it was made OPTIONAL instead. Unregistered, Smooth hands the target
--- straight back and the value steps. See Motion.luau.
local Motion = loadSibling("Motion")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, UDim, Vector2, Color3, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.UDim, Deps.Vocabulary.Vector2, Deps.Vocabulary.Color3, Deps.Vocabulary.Enum

local create = Deps.create
local source = Deps.source
local action = Deps.action
local cleanup = Deps.cleanup

local UserInputService = if isRoblox and typeof(game) == "Instance" and game:GetService("UserInputService")
	then game:GetService("UserInputService")
	else nil
local RunService = if isRoblox and typeof(game) == "Instance" and game:GetService("RunService")
	then game:GetService("RunService")
	else nil

export type ScrollbarMotionConfig = {
	Period: number?,
	DampingRatio: number?,
	HoverEffect: boolean?,
}

export type ScrollbarProps = {
	Scope: any?,
	Axis: ("Vertical" | "Horizontal")?,
	Size: any?,
	Position: any?,
	AnchorPoint: any?,
	Width: ((() -> number) | number)?,
	Padding: ((() -> number) | number)?,
	TrackLength: ((() -> number) | number)?,
	ThumbSize: ((() -> number) | number)?,
	ThumbOffset: ((() -> number) | number)?,
	OnThumbDrag: ((delta: number, initialThumbOffset: number) -> ())?,
	OnDragStart: (() -> ())?,
	OnDragEnd: (() -> ())?,
	OnTrackClick: ((position: number) -> ())?,
	TrackClickScrolls: ((() -> boolean) | boolean)?,
	OnStep: ((direction: number) -> ())?,
	Motion: ScrollbarMotionConfig?,
	RenderTrack: ((trackProps: any) -> any)?,
	RenderThumb: ((thumbProps: any) -> any)?,
	Parts: {
		Track: any?,
		Thumb: any?,
		Buttons: any?,
	}?,
	ShowButtons: ((() -> boolean) | boolean)?,
	ButtonSize: ((() -> number) | number)?,
	ButtonGlyphs: { Start: string, End: string }?,
	ButtonColor: any?,
	ButtonHoverColor: any?,
	TrackColor: any?,
	TrackTransparency: any?,
	ThumbColor: any?,
	ThumbHoverColor: any?,
	ThumbTransparency: any?,
	CornerRadius: any?,
	AutoHide: ((() -> boolean) | boolean)?,
	AutoFade: ((() -> boolean) | boolean)?,
	RevealOn: any?,
	Controller: any?,
	Controls: { [string]: any }?,
	Visible: ((() -> boolean) | boolean)?,
	ZIndex: ((() -> number) | number)?,
	[any]: any,
}

local function resolve<T>(v: ((() -> T) | T)?): T?
	if type(v) == "function" then
		return (v :: any)()
	end
	return v :: any
end

local function color3FromRGB(r: number, g: number, b: number): any
	if isRoblox and typeof(Color3) == "table" and Color3.fromRGB then
		return Color3.fromRGB(r, g, b)
	end
	return { R = r / 255, G = g / 255, B = b / 255 }
end

local function udim2New(xs: number, xo: number, ys: number, yo: number): any
	if isRoblox and typeof(UDim2) == "table" and UDim2.new then
		return UDim2.new(xs, xo, ys, yo)
	end
	return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
end

local function vector2New(x: number, y: number): any
	if isRoblox and typeof(Vector2) == "table" and Vector2.new then
		return Vector2.new(x, y)
	end
	return { X = x, Y = y }
end

local function udimNew(scale: number, offset: number): any
	if isRoblox and typeof(UDim) == "table" and UDim.new then
		return UDim.new(scale, offset)
	end
	return { Scale = scale, Offset = offset }
end

local function Scrollbar(props: ScrollbarProps): any
	local axis = props.Axis or "Vertical"
	local isVertical = axis == "Vertical"
	local isHovered = source(false)
	local isDragging = source(false)
	local revealHovered = source(false)
	local activityStamp = source(os.clock())
	local dragStartPos = 0
	local dragStartOffset = 0
	local trackSurface: GuiObject? = nil

	local controllerOffset = source(if props.Controller and props.Controller.GetOffset then props.Controller.GetOffset() else 0)
	local controllerMaxScroll = source(if props.Controller and props.Controller.GetMaxScroll then props.Controller.GetMaxScroll() else 0)
	if props.Controller and props.Controller.Subscribe then
		local unsub = props.Controller.Subscribe(function(newOffset)
			controllerOffset(newOffset)
			if props.Controller.GetMaxScroll then
				controllerMaxScroll(props.Controller.GetMaxScroll())
			end
			activityStamp(os.clock())
		end)
		if cleanup then
			cleanup(unsub)
		end
	end

	local maxScroll = function(): number
		if props.MaxScroll then
			return resolve(props.MaxScroll) or 0
		end
		if props.ContentHeight and props.ViewportHeight then
			local ch = resolve(props.ContentHeight) or 0
			local vh = resolve(props.ViewportHeight) or 0
			return math.max(0, ch - vh)
		end
		local _ = controllerOffset()
		return controllerMaxScroll()
	end

	local motionConfig = props.Motion or {}
	local smoothThumb = if props.SmoothThumb ~= nil
		then props.SmoothThumb
		elseif motionConfig.SmoothThumb ~= nil
		then motionConfig.SmoothThumb
		elseif props.SmoothScroll ~= nil
		then props.SmoothScroll
		else true
	local motionPeriod = props.MotionPeriod or motionConfig.Period or 0.18
	local motionDamping = props.MotionDamping or motionConfig.DampingRatio or 0.85

	local isSpringable = smoothThumb and motionPeriod >= 0.02
	local smoothedControllerOffset = if isSpringable
		then Motion.Smooth(controllerOffset, { Period = motionPeriod, DampingRatio = motionDamping })
		else controllerOffset

	local renderedControllerOffset = function(): number
		if isDragging() or not smoothThumb or not isSpringable then
			return controllerOffset()
		end
		return smoothedControllerOffset()
	end

	local hoverTarget = function()
		if not enableHoverEffect then return 0.0 end
		if isDragging() then return 1.0 end
		if isHovered() then return 0.7 end
		return 0.0
	end

	local hoverPeriod = motionConfig.HoverPeriod or 0.15
	local hoverDamping = motionConfig.HoverDampingRatio or 0.85
	local enableHoverEffect = if motionConfig.HoverEffect ~= nil then motionConfig.HoverEffect else true
	local isHoverSpringable = enableHoverEffect and hoverPeriod >= 0.02

	local hoverSpring = if isHoverSpringable
		then Motion.Smooth(hoverTarget, { Period = hoverPeriod, DampingRatio = hoverDamping })
		else hoverTarget

	local function getWidth(): number
		local w = resolve(props.Width)
		return if type(w) == "number" then w else 6
	end

	local function getPadding(): number
		local p = resolve(props.Padding)
		return if type(p) == "number" then p else 0
	end

	local parts = props.Parts or {}

	local showButtonsRaw = resolve(props.ShowButtons)
	local showButtons = (showButtonsRaw == true)
		or (parts.Buttons ~= nil and parts.Buttons ~= false)
	local buttonSize = resolve(props.ButtonSize) or getWidth() or 10
	local buttonSpan = if showButtons then buttonSize else 0

	local measuredTrackLength = source(100)

	local function getFullSpan(): number
		local fromProps = resolve(props.TrackLength)
		if fromProps and fromProps > 0 then
			return fromProps
		end
		return measuredTrackLength()
	end

	local function getTrackLength(): number
		local full = getFullSpan()
		return math.max(full - (buttonSpan * 2), 1)
	end

	local function getThumbSize(): number
		local tLen = getTrackLength()
		if props.ThumbSize then
			return resolve(props.ThumbSize) or math.max(tLen * 0.2, 16)
		end
		if props.Controller and props.Controller.GetThumbSize then
			return props.Controller.GetThumbSize(tLen)
		end
		return math.max(tLen * 0.2, 16)
	end

	local function getThumbOffset(): number
		if props.ThumbOffset then
			local baseOffset = resolve(props.ThumbOffset) or 0
			return baseOffset + buttonSpan
		end
		if props.Controller then
			local cur = renderedControllerOffset()
			local tLen = getTrackLength()
			local thumbLen = getThumbSize()
			local maxScr = if props.Controller.GetMaxScroll then props.Controller.GetMaxScroll() else 0
			local baseOffset = ScrollController.computeThumbOffset(cur, maxScr, tLen, thumbLen)
			return baseOffset + buttonSpan
		end
		return buttonSpan
	end

	local function markActivity()
		activityStamp(os.clock())
	end

	-- Auto-hide / Auto-fade
	local autoHide = function(): boolean
		local ah = resolve(props.AutoHide)
		if ah ~= nil then return ah end
		local af = resolve(props.AutoFade)
		if af ~= nil then return af end
		return false
	end

	local isIdle = function(): boolean
		if not autoHide() then return false end
		if isDragging() or isHovered() or revealHovered() then return false end
		return (os.clock() - activityStamp()) > 1.2
	end

	local barOpacity = Motion.Smooth(function()
		return if isIdle() then 0.0 else 1.0
	end, { Period = 0.22, DampingRatio = 0.95 })

	-- RevealOn hover binding
	if props.RevealOn and RunService then
		local revealTarget = props.RevealOn
		local revealConn = RunService.Heartbeat:Connect(function()
			local target = resolve(revealTarget)
			if target and typeof(target) == "Instance" and (target :: any):IsA("GuiObject") then
				local px, py = InputScope.GetPointerPosition()
				local over = PointerRouter.IsPointerOver(target :: any, px, py)
				if over ~= revealHovered() then
					revealHovered(over)
					if over then markActivity() end
				end
			end
		end)
		if cleanup then
			cleanup(function()
				revealConn:Disconnect()
			end)
		end
	end

	local function stopDrag()
		if isDragging() then
			isDragging(false)
			markActivity()
			if props.OnDragEnd then
				props.OnDragEnd()
			end
		end
	end

	--- DRAG, THROUGH THE ROUTER (ms-52 M2).
	---
	--- This used to be a private `UserInputService.InputChanged` connection behind
	--- `if UserInputService then`, which made the thumb's drag the one part of this
	--- primitive that only existed in Roblox. The second host proved it: a real
	--- ScrollingFrame's thumb laid out, hit-tested and pressed correctly off-engine
	--- and then would not move, because the entire branch was skipped.
	---
	--- The router already owns the single UserInputService connection in Roblox, so
	--- reading movement from it is the same signal by a portable route -- and one
	--- shared connection instead of one per scrollbar on screen.
	---
	--- Drag END needs no listener at all: `OnPressUp` is wired to the Pressable's
	--- OnReleased, which the router fires on the record the press BEGAN on wherever
	--- the release lands. That is the behaviour the old global InputEnded handler
	--- was approximating.
	local unsubscribeMove = PointerRouter.OnPointerMove(function(x: number, y: number)
		if not isDragging() then return end
		local currentPos = if isVertical then y else x
		local delta = currentPos - dragStartPos
		markActivity()
		if props.OnThumbDrag then
			props.OnThumbDrag(delta, dragStartOffset)
		elseif props.Controller and props.Controller.ScrollTo then
			local tLen = getTrackLength()
			local thumbLen = getThumbSize()
			local maxScr = if props.Controller.GetMaxScroll then props.Controller.GetMaxScroll() else 0
			if maxScr > 0 and tLen > thumbLen then
				local targetThumbPos = (dragStartOffset - buttonSpan) + delta
				local targetScroll = ScrollController.computeScrollFromThumb(targetThumbPos, tLen, thumbLen, maxScr)
				props.Controller.ScrollTo(targetScroll)
			end
		end
	end)

	if cleanup then
		cleanup(unsubscribeMove)
	end

	-- Wire external Controls table if supplied
	if props.Controls and type(props.Controls) == "table" then
		props.Controls.ScrollTo = function(target: number)
			if props.Controller and props.Controller.ScrollTo then
				props.Controller.ScrollTo(target)
			end
			markActivity()
		end
		props.Controls.ScrollBy = function(delta: number)
			if props.Controller and props.Controller.ScrollBy then
				props.Controller.ScrollBy(delta)
			end
			markActivity()
		end
		props.Controls.GetThumbSize = getThumbSize
		props.Controls.GetThumbOffset = getThumbOffset
	end

	-- Colors and Appearance
	local trackColor = function(): any
		local c = resolve(props.TrackColor)
		return if c then c else color3FromRGB(20, 26, 40)
	end
	local trackTransparency = function(): number
		local base = resolve(props.TrackTransparency) or 0.4
		local opacity = barOpacity()
		return 1 - ((1 - base) * opacity)
	end

	local thumbColor = function(): any
		local h = hoverSpring()
		local customColor = resolve(props.ThumbColor)
		local customHover = resolve(props.ThumbHoverColor)
		if customColor and customHover and typeof(customColor) == "Color3" and typeof(customHover) == "Color3" then
			return customColor:Lerp(customHover, h)
		elseif customColor then
			return customColor
		end
		return color3FromRGB(
			math.floor(120 + h * 40),
			math.floor(160 + h * 40),
			math.floor(230 + h * 25)
		)
	end
	local thumbTransparency = function(): number
		local customTrans = resolve(props.ThumbTransparency) or 0.0
		local h = hoverSpring()
		local activeTrans = customTrans * (1 - h * 0.3)
		local opacity = barOpacity()
		return 1 - ((1 - activeTrans) * opacity)
	end

	local cornerRadius = resolve(props.CornerRadius) or function()
		return udimNew(0, math.floor(getWidth() / 2))
	end

	local thumbProps = {
		Size = function()
			local size = getThumbSize()
			local w = getWidth() - getPadding() * 2
			local pad = getPadding()
			return if isVertical then udim2New(1, -pad * 2, 0, size) else udim2New(0, size, 1, -pad * 2)
		end,
		Position = function()
			local offset = getThumbOffset()
			local pad = getPadding()
			return if isVertical then udim2New(0, pad, 0, offset) else udim2New(0, offset, 0, pad)
		end,
		AnchorPoint = vector2New(0, 0),
		IsDragging = isDragging,
		IsHovered = isHovered,
		Transparency = thumbTransparency,
		OnPressDown = function()
			isDragging(true)
			markActivity()
			local px, py = InputScope.GetPointerPosition()
			dragStartPos = if isVertical then py else px
			dragStartOffset = getThumbOffset()
			if props.OnDragStart then
				props.OnDragStart()
			end
		end,
		OnPressUp = function()
			stopDrag()
		end,
	}

	local defaultThumb = function()
		return PressableFrame({
			Name = "ScrollbarThumb",
			Scope = props.Scope,
			Cursor = "Grab",
			Size = thumbProps.Size,
			Position = thumbProps.Position,
			AnchorPoint = thumbProps.AnchorPoint,
			BackgroundColor3 = thumbColor,
			BackgroundTransparency = thumbTransparency,
			BorderSizePixel = 0,
			HitTestable = false,
			OnPressed = thumbProps.OnPressDown,
			OnReleased = thumbProps.OnPressUp,
			OnHoverChanged = function(hovered)
				isHovered(hovered)
				if hovered then markActivity() end
			end,
			create("UICorner") {
				CornerRadius = cornerRadius,
			},
		})
	end

	local thumbPressable = PointerRouter.Pressable({
		Scope = props.Scope,
		Cursor = "Grab",
		HitTestable = false,
		OnPressed = thumbProps.OnPressDown,
		OnReleased = thumbProps.OnPressUp,
		OnHoverChanged = function(hovered)
			isHovered(hovered)
			if hovered then markActivity() end
		end,
	})

	if cleanup then
		cleanup(thumbPressable.Destroy)
	end

	local thumbElement: any
	if parts.Thumb and type(parts.Thumb) == "function" then
		local thumbState = {
			Size = thumbProps.Size,
			Position = thumbProps.Position,
			AnchorPoint = thumbProps.AnchorPoint,
			IsHovered = isHovered,
			IsDragging = isDragging,
			Transparency = thumbTransparency,
			Default = defaultThumb,
		}
		local slotThumb = parts.Thumb(thumbState)
		thumbElement = slotThumb
		if isRoblox and slotThumb and typeof(slotThumb) == "Instance" and (slotThumb :: any):IsA("GuiObject") then
			thumbPressable.Bind(slotThumb :: any)
		end
	elseif props.RenderThumb then
		local slotThumb = props.RenderThumb(thumbProps)
		thumbElement = slotThumb
		if isRoblox and slotThumb and typeof(slotThumb) == "Instance" and (slotThumb :: any):IsA("GuiObject") then
			thumbPressable.Bind(slotThumb :: any)
		end
	else
		thumbElement = defaultThumb()
	end

	-- Stepper Buttons
	local glyphs = props.ButtonGlyphs or {
		Start = if isVertical then "▲" else "◄",
		End = if isVertical then "▼" else "►",
	}

	local function createStepper(name: string, dir: number, glyph: string, pos: any)
		local btnHovered = source(false)
		return PressableFrame({
			Name = name,
			Scope = props.Scope,
			Cursor = "Pointer",
			Size = if isVertical then udim2New(1, 0, 0, buttonSpan) else udim2New(0, buttonSpan, 1, 0),
			Position = pos,
			BackgroundColor3 = function()
				local base = resolve(props.ButtonColor) or trackColor()
				local hov = resolve(props.ButtonHoverColor) or thumbColor()
				return if btnHovered() then hov else base
			end,
			BackgroundTransparency = trackTransparency,
			BorderSizePixel = 0,
			HitTestable = false,
			OnHoverChanged = function(hov)
				btnHovered(hov)
				if hov then markActivity() end
			end,
			OnActivated = function()
				markActivity()
				if props.OnStep then
					props.OnStep(dir)
				elseif props.Controller and props.Controller.ScrollBy then
					props.Controller.ScrollBy(dir * (props.Controller.GetStepSize and props.Controller.GetStepSize() or 40))
				end
			end,
			create("UICorner") { CornerRadius = cornerRadius },
			create("TextLabel") {
				Name = "Glyph",
				Size = udim2New(1, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = glyph,
				TextSize = math.max(math.floor(buttonSpan * 0.6), 8),
				TextColor3 = function()
					return if btnHovered() then color3FromRGB(255, 255, 255) else color3FromRGB(160, 175, 200)
				end,
				TextTransparency = function()
					return 1 - barOpacity()
				end,
				Font = Enum.Font.GothamBold,
				ZIndex = (props.ZIndex or 2) + 1,
			},
		})
	end

	local buttonStartElement = if showButtons
		then createStepper("ButtonStart", -1, glyphs.Start, udim2New(0, 0, 0, 0))
		else nil
	local buttonEndElement = if showButtons
		then createStepper("ButtonEnd", 1, glyphs.End, if isVertical then udim2New(0, 0, 1, -buttonSpan) else udim2New(1, -buttonSpan, 0, 0))
		else nil

	local trackClickScrolls = if props.TrackClickScrolls ~= nil then props.TrackClickScrolls else true

	local trackPressable = PointerRouter.Pressable({
		Scope = props.Scope,
		HitTestable = false,
		OnPressed = function()
			markActivity()
			if trackSurface and trackSurface.Parent and trackSurface.AbsolutePosition then
				local px, py = InputScope.GetPointerPosition()
				local clickPos = if isVertical
					then (py - trackSurface.AbsolutePosition.Y) - buttonSpan
					else (px - trackSurface.AbsolutePosition.X) - buttonSpan

				if props.OnTrackClick then
					props.OnTrackClick(clickPos)
				elseif trackClickScrolls and props.Controller and props.Controller.ScrollTo then
					local tLen = getTrackLength()
					local thumbLen = getThumbSize()
					local maxScr = if props.Controller.GetMaxScroll then props.Controller.GetMaxScroll() else 0
					if maxScr > 0 and tLen > thumbLen then
						local targetThumbPos = clickPos - (thumbLen / 2)
						local targetScroll = ScrollController.computeScrollFromThumb(targetThumbPos, tLen, thumbLen, maxScr)
						props.Controller.ScrollTo(targetScroll)
					end
				end
			end
		end,
	})

	if cleanup then
		cleanup(trackPressable.Destroy)
	end

	local defaultTrack = function()
		return create("Frame")({
			Name = "ScrollbarTrack",
			Size = props.Size or function()
				local w = getWidth()
				return if isVertical then udim2New(0, w, 1, -8) else udim2New(1, -8, 0, w)
			end,
			Position = props.Position or function()
				local w = getWidth()
				return if isVertical then udim2New(1, -w - 4, 0, 4) else udim2New(0, 4, 1, -w - 4)
			end,
			AnchorPoint = props.AnchorPoint,
			BackgroundColor3 = trackColor,
			BackgroundTransparency = trackTransparency,
			BorderSizePixel = 0,
			Visible = function()
				local maxScr = maxScroll()
				if props.Visible ~= nil then
					local v = resolve(props.Visible)
					if v == false then return false end
				end
				local hideWhenUnscrollable = resolve(props.HideWhenUnscrollable)
				if hideWhenUnscrollable ~= false then
					if maxScr <= 0 then
						return false
					end
				end
				if autoHide() and barOpacity() <= 0.01 then
					return false
				end
				return true
			end,
			ZIndex = props.ZIndex or 2,
			action(trackPressable.Bind),
			action(function(rbx: GuiObject)
				trackSurface = rbx
				if isRoblox and rbx and typeof(rbx) == "Instance" and rbx:IsA("GuiObject") then
					local function updateTrack()
						if rbx.AbsoluteSize then
							local len = if isVertical then rbx.AbsoluteSize.Y else rbx.AbsoluteSize.X
							if len > 0 then
								measuredTrackLength(len)
							end
						end
					end
					task.defer(updateTrack)
					rbx:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTrack)
				end
			end),
			create("UICorner") {
				CornerRadius = cornerRadius,
			},
			buttonStartElement,
			thumbElement,
			buttonEndElement,
		})
	end

	if parts.Track and type(parts.Track) == "function" then
		return parts.Track({
			Size = props.Size,
			Position = props.Position,
			AnchorPoint = props.AnchorPoint,
			Thumb = thumbElement,
			ButtonStart = buttonStartElement,
			ButtonEnd = buttonEndElement,
			Transparency = trackTransparency,
			IsHovered = isHovered,
			Visible = props.Visible,
			Default = defaultTrack,
		})
	elseif props.RenderTrack then
		return props.RenderTrack({
			Size = props.Size,
			Position = props.Position,
			Thumb = thumbElement,
			ButtonStart = buttonStartElement,
			ButtonEnd = buttonEndElement,
			Visible = props.Visible,
		})
	end

	return defaultTrack()
end

local function Styled(style: any, overrides: { [string]: any }?): { [string]: any }
	local base = if type(style) == "table" and type(style.Props) == "function" then style.Props() else {}
	local merged: { [string]: any } = {}
	for k, v in pairs(base) do
		merged[k] = v
	end
	for k, v in pairs(overrides or {}) do
		merged[k] = v
	end
	return merged
end

return setmetatable({
	Scrollbar = Scrollbar,
	Styled = Styled,
}, {
	__call = function(_self, props: ScrollbarProps)
		return Scrollbar(props)
	end,
})
