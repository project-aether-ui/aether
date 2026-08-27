--!strict
--[=[
	WindowTopbar — Headless Window Title Bar Primitive
	Part of Aether.Primitives (Layer 2).

	Provides title label, window drag handle, and close button mechanics
	directly composing Aether.Primitives.PressableFrame.
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
		if root and root:FindFirstChild("src") and root.src:FindFirstChild(name) then
			return require(root.src[name])
		end
	end
	local ok, res = pcall(require, "./" .. name)
	if ok then return res end
	local ok2, res2 = pcall(require, "../" .. name)
	if ok2 then return res2 end
	local ok3, res3 = pcall(require, "../../src/" .. name)
	if ok3 then return res3 end
	return {}
end

local Deps = loadSibling("Deps")
--- Renamed from PressableFrame in ms-51 M14; same primitive.
local PressableFrame = loadSibling("Pressable")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, Color3, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.Color3, Deps.Vocabulary.Enum

local create = Deps.create
local source = Deps.source

export type WindowTopbarPartProps = {
	Title: any,
	Height: number,
	IsCloseHovered: () -> boolean,
	IsClosePressed: () -> boolean,
}

export type WindowTopbarProps = {
	Title: any?,
	Height: number?,
	ShowClose: ((() -> boolean) | boolean)?,
	OnClose: (() -> ())?,
	Size: any?,
	Position: any?,
	AnchorPoint: any?,
	ZIndex: any?,
	Visible: any?,
	Parts: {
		Background: ((props: WindowTopbarPartProps) -> any)?,
		Title: ((props: WindowTopbarPartProps) -> any)?,
		Close: ((props: WindowTopbarPartProps) -> any)?,
	}?,
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

local function WindowTopbar(props: WindowTopbarProps): any
	local height = props.Height or 32
	local isCloseHovered = source(false)
	local isClosePressed = source(false)

	local function shouldShowClose(): boolean
		local v = resolve(props.ShowClose)
		if v == nil then return true end
		return v == true
	end

	local partState: WindowTopbarPartProps = {
		Title = props.Title,
		Height = height,
		IsCloseHovered = isCloseHovered,
		IsClosePressed = isClosePressed,
	}

	local defaultTitle = function()
		local t = props.Title or "Window"
		if type(t) == "string" then
			return create("TextLabel")({
				Name = "TitleText",
				Text = t,
				Size = udim2New(1, -height, 1, 0),
				Position = udim2New(0, 12, 0, 0),
				BackgroundTransparency = 1,
				TextColor3 = color3FromRGB(220, 220, 220),
				TextSize = 13,
				TextXAlignment = if isRoblox and typeof(Enum) == "table" and Enum.TextXAlignment then Enum.TextXAlignment.Left else "Left",
				Font = if isRoblox and typeof(Enum) == "table" and Enum.Font then Enum.Font.GothamMedium else "GothamMedium",
				BorderSizePixel = 0,
			})
		end
		return t
	end

	local defaultClose = function()
		return PressableFrame({
			Name = "CloseButton",
			Size = udim2New(0, height, 0, height),
			Position = udim2New(1, -height, 0, 0),
			BackgroundColor3 = function()
				if isClosePressed() then
					return color3FromRGB(180, 40, 40)
				elseif isCloseHovered() then
					return color3FromRGB(220, 50, 50)
				else
					return color3FromRGB(0, 0, 0)
				end
			end,
			BackgroundTransparency = function()
				return if isCloseHovered() or isClosePressed() then 0.2 else 1
			end,
			BorderSizePixel = 0,
			OnPress = function()
				if props.OnClose then
					props.OnClose()
				end
			end,
			create("TextLabel")({
				Name = "CloseIcon",
				Text = "✕",
				Size = udim2New(1, 0, 1, 0),
				BackgroundTransparency = 1,
				TextColor3 = color3FromRGB(200, 200, 200),
				TextSize = 12,
				Font = if isRoblox and typeof(Enum) == "table" and Enum.Font then Enum.Font.GothamBold else "GothamBold",
				BorderSizePixel = 0,
			}),
		})
	end

	local defaultBackground = function()
		return create("Frame")({
			Name = "WindowTopbarBg",
			Size = udim2New(1, 0, 1, 0),
			BackgroundColor3 = color3FromRGB(28, 28, 32),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
		})
	end

	local bgElem = if props.Parts and props.Parts.Background
		then props.Parts.Background(partState)
		else defaultBackground()

	local titleElem = if props.Parts and props.Parts.Title
		then props.Parts.Title(partState)
		else defaultTitle()

	local closeElem = if shouldShowClose()
		then (if props.Parts and props.Parts.Close then props.Parts.Close(partState) else defaultClose())
		else nil

	return create("Frame")({
		Name = "WindowTopbar",
		Size = props.Size or udim2New(1, 0, 0, height),
		Position = props.Position or udim2New(0, 0, 0, 0),
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex or 2,
		Visible = props.Visible,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		bgElem,
		titleElem,
		closeElem,
	})
end

return WindowTopbar
