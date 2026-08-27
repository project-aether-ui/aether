--!strict
--[[
	ScrollingFrame — Turnkey compound scrolling assembly combining ScrollArea and ScrollBar.

	Provides a high-level, declarative replacement for Roblox's built-in ScrollingFrame
	with first-class support for:
	- Presentation: "Overlay" (scrollbar sits atop canvas) vs "Inset" (canvas is padded to not overlap the rail).
	- AutoHide: Smoothly fades the scrollbar out when idle, reveals on hover or scrolling activity.
	- Themed & Styled Thumbs: Direct support for ThemeCore tokens or ScrollBar.Styled variants.
	- Headless PointerRouter arbitration: Zero engine input-sinking bugs.
]]

local isRoblox = typeof(game) == "Instance"
local isScriptInstance = typeof(script) == "Instance"

local function loadSibling(name: string): any
	if isScriptInstance then
		local parent = script.Parent
		if parent and parent:FindFirstChild(name) then
			return require(parent[name])
		end
		local root = parent and parent.Parent
		if root and root:FindFirstChild(name) then
			return require(root[name])
		end
		if root and root:FindFirstChild("primitives") and root.primitives:FindFirstChild(name) then
			return require(root.primitives[name])
		end
		if root and root:FindFirstChild("controllers") and root.controllers:FindFirstChild(name) then
			return require(root.controllers[name])
		end
	end
	local ok, res = pcall(require, "./" .. name)
	if ok then return res end
	local ok2, res2 = pcall(require, "../" .. name)
	if ok2 then return res2 end
	local ok3, res3 = pcall(require, "./primitives/" .. name)
	if ok3 then return res3 end
	local ok4, res4 = pcall(require, "./controllers/" .. name)
	if ok4 then return res4 end
	return nil
end

local Deps = if isScriptInstance
	then (function()
		local cur = script.Parent
		while cur and cur ~= game do
			if cur:FindFirstChild("Deps") then
				return require(cur.Deps)
			end
			cur = cur.Parent
		end
		return {}
	end)()
	else (function()
		local ok, res = pcall(require, "../Deps")
		if ok then return res end
		local ok2, res2 = pcall(require, "./Deps")
		return if ok2 then res2 else {}
	end)()

local ScrollArea = loadSibling("ScrollArea")
local ScrollBar = loadSibling("Scrollbar")
local ScrollController = loadSibling("ScrollController")
local VirtualList = loadSibling("VirtualList")

--- ms-51 M16: the motion SEAM, not Flux. Aether is a genuine consumer of
--- springs, so this edge could not be reversed like the component seams —
--- it was made OPTIONAL instead. Unregistered, Smooth hands the target
--- straight back and the value steps. See Motion.luau.
local Motion = loadSibling("Motion")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2 =
	Deps.Vocabulary.UDim2

local create = Deps.create
local source = Deps.source
local action = Deps.action
local cleanup = Deps.cleanup

export type VirtualizeConfig<T> = {
	Items: (() -> { T }) | { T },
	RenderItem: (item: T, index: number) -> any,
	Estimate: number?,
	Overscan: number?,
	Identify: ((item: T, index: number) -> any)?,
}

export type ScrollingFrameProps = {
	Name: string?,
	Scope: any?,
	Size: any?,
	Position: any?,
	AnchorPoint: any?,
	Visible: any?,
	ZIndex: number?,
	LayoutOrder: any?,

	-- Presentation & Layout
	Presentation: ("Overlay" | "Inset")?,
	ShowVerticalBar: any?,
	ShowHorizontalBar: any?,
	AutoHide: any?,
	HideWhenUnscrollable: any?,
	AutomaticCanvasSize: any?,
	CanvasSize: any?,
	ContentHeight: any?,
	Layout: ("List" | "None")?,
	StepSize: number?,

	-- Virtualization
	Virtualize: VirtualizeConfig<any>?,

	-- Sizing & Insets
	ScrollBarWidth: any?,
	ScrollBarPadding: any?,
	ScrollBarPosition: any?,
	ScrollBarSize: any?,

	-- Styling & Theming
	Style: any?,
	ThumbColor: any?,
	ThumbHoverColor: any?,
	TrackColor: any?,
	TrackTransparency: any?,
	ThumbTransparency: any?,
	CornerRadius: any?,
	ScrollBarProps: any?,

	-- Motion & Physics
	Motion: any?,
	Controller: any?,

	-- Content
	Content: any?,
	Children: any?,
	[any]: any,
}

local function resolve<T>(v: ((() -> T) | T)?): T?
	if type(v) == "function" then
		return (v :: any)()
	end
	return v :: any
end

local function udim2New(xs: number, xo: number, ys: number, yo: number): any
	if isRoblox and typeof(UDim2) == "table" and UDim2.new then
		return UDim2.new(xs, xo, ys, yo)
	end
	return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
end

local function ScrollingFrame(props: ScrollingFrameProps): any
	local controller = props.Controller or (if ScrollController then ScrollController.new({
		Orientation = "Vertical",
	}) else nil)

	local presentation = props.Presentation or "Overlay"
	local autoHide = if props.AutoHide ~= nil then props.AutoHide else false
	local showVerticalBar = if props.ShowVerticalBar ~= nil then props.ShowVerticalBar else true

	local rawSbWidth = props.ScrollBarWidth or (props.ScrollBarProps and props.ScrollBarProps.Width) or (props.Style and props.Style.Props and props.Style.Props().Width) or 6
	local rawSbPadding = props.ScrollBarPadding or (props.ScrollBarProps and props.ScrollBarProps.Padding) or (props.Style and props.Style.Props and props.Style.Props().Padding) or 0

	local function getSbWidth(): number
		local w = resolve(rawSbWidth)
		return if type(w) == "number" then w else 6
	end

	local function getSbPadding(): number
		local p = resolve(rawSbPadding)
		return if type(p) == "number" then p else 0
	end

	local isInset = presentation == "Inset"

	local scrollAreaSize = function()
		if isInset then
			local hideUnscrollable = resolve(props.HideWhenUnscrollable) ~= false
			local maxScr = if controller and controller.GetMaxScroll then controller.GetMaxScroll() else 0
			if hideUnscrollable and maxScr <= 0 then
				return udim2New(1, 0, 1, 0)
			end
			local w = getSbWidth()
			local p = getSbPadding()
			local totalInset = w + p * 2 + 2
			return udim2New(1, -totalInset, 1, 0)
		else
			return udim2New(1, 0, 1, 0)
		end
	end

	local styleMotion = if props.Motion
		then props.Motion
		elseif props.Style and props.Style.Props then {
			Period = props.Style.Props().MotionPeriod,
			DampingRatio = props.Style.Props().MotionDamping,
			SmoothScroll = props.Style.Props().SmoothScroll,
		}
		else nil

	-- If a styled component variant is provided, mount ScrollBar(ScrollBar.Styled(props.Style, ...))
	local finalScrollBar = if props.Style and ScrollBar
		then ScrollBar(if ScrollBar.Styled then ScrollBar.Styled(props.Style, {
			Scope = props.Scope,
			Controller = controller,
			Position = props.ScrollBarPosition or defaultPosition,
			Size = props.ScrollBarSize or defaultSize,
			Width = getSbWidth,
			Padding = getSbPadding,
			AutoHide = autoHide,
			HideWhenUnscrollable = props.HideWhenUnscrollable,
			TrackLength = function()
				return math.max(controller.GetViewportSize() - 4, 10)
			end,
			Debug = props.Debug,
			ZIndex = (props.ZIndex or 1) + 2,
		}) else props.Style)
		else nil

	local motionConfig = styleMotion or {}
	local springPeriod = motionConfig.Period or 0.20
	local springDamping = motionConfig.DampingRatio or 0.85
	local smoothScroll = if motionConfig.SmoothScroll ~= nil then motionConfig.SmoothScroll else true

	local isSpringable = smoothScroll and springPeriod >= 0.02
	local offsetSource = source(if controller and controller.GetOffset then controller.GetOffset() else 0)
	if controller and controller.Subscribe then
		controller.Subscribe(function(off)
			offsetSource(off)
		end)
	end

	local smoothOffsetSignal = if isSpringable
		then Motion.Smooth(offsetSource, { Period = springPeriod, DampingRatio = springDamping })
		else offsetSource

	local gatheredChildren = {}
	for k, v in pairs(props) do
		if type(k) == "number" then
			table.insert(gatheredChildren, v)
		end
	end

	local finalContent = if props.Virtualize and VirtualList
		then function()
			return VirtualList({
				Name = "VirtualList",
				Scope = props.Scope,
				Controller = controller,
				Items = props.Virtualize.Items,
				RenderItem = props.Virtualize.RenderItem,
				Estimate = props.Virtualize.Estimate or 30,
				Overscan = props.Virtualize.Overscan or 2,
				Identify = props.Virtualize.Identify,
				SmoothOffset = smoothOffsetSignal,
				Motion = (props.Virtualize and props.Virtualize.Motion) or props.Motion or styleMotion,
			})
		end
		else (if #gatheredChildren > 0 then gatheredChildren else (props.Content or props.Children))

	return create("Frame")({
		Name = props.Name or "ScrollingFrame",
		Size = props.Size or udim2New(1, 0, 1, 0),
		Position = props.Position or udim2New(0, 0, 0, 0),
		AnchorPoint = props.AnchorPoint,
		Visible = props.Visible,
		ZIndex = props.ZIndex or 1,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		if ScrollArea then ScrollArea({
			Name = props.Name or "ViewportArea",
			Scope = props.Scope,
			Controller = controller,
			Size = scrollAreaSize,
			Position = udim2New(0, 0, 0, 0),
			Virtualize = props.Virtualize ~= nil,
			AutomaticCanvasSize = if props.Virtualize then nil else props.AutomaticCanvasSize,
			CanvasSize = props.CanvasSize,
			ContentHeight = props.ContentHeight,
			Layout = if props.Virtualize then "None" else props.Layout,
			StepSize = props.StepSize,
			ShowVerticalBar = if finalScrollBar then false else showVerticalBar,
			AutoHide = autoHide,
			HideWhenUnscrollable = props.HideWhenUnscrollable,
			ScrollBarWidth = getSbWidth,
			ScrollBarPadding = getSbPadding,
			ThumbColor = props.ThumbColor,
			ThumbHoverColor = props.ThumbHoverColor,
			TrackColor = props.TrackColor,
			TrackTransparency = props.TrackTransparency,
			ThumbTransparency = props.ThumbTransparency,
			ScrollbarCornerRadius = props.CornerRadius,
			ScrollbarProps = props.ScrollBarProps,
			Motion = styleMotion,
			Content = finalContent,
			Debug = props.Debug,
			ZIndex = props.ZIndex or 1,
		}) else nil,

		finalScrollBar,
	})
end

return ScrollingFrame
