--!strict
--[=[
	Tooltip — Composite Headless Primitive (Hover-Dwell Floating Badge)
	Part of Aether.Primitives (Layer 2B Composite).
	
	Embeds:
	- Aether.Engine.useHover (pointer dwell detection)
	- Aether.Engine.useFloating (spatial auto-flip & boundary clamping)
	- Aether.Primitives.ScopedSurface (floating container)
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
local useHover = loadSibling("useHover")
local useFloating = loadSibling("useFloating")
local ScopedSurface = loadSibling("ScopedSurface")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, UDim, Color3, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.UDim, Deps.Vocabulary.Color3, Deps.Vocabulary.Enum

local create = Deps.create
local source = Deps.source
local action = Deps.action

export type TooltipProps = {
	Anchor: (GuiObject | (() -> GuiObject?))?,
	Child: any?,
	Content: string | (() -> any),
	Placement: string?,
	Delay: number?,
	Offset: number?,
	RenderContent: ((text: string) -> any)?,
}

local function Tooltip(props: TooltipProps): any
	local isOpen = source(false)
	local timerThread: thread? = nil
	local delayTime = props.Delay or 0.35

	local hoverHandle = useHover()
	local isHovered = hoverHandle.IsHovered
	local childRef = source(nil :: GuiObject?)

	if props.Anchor then
		if typeof(props.Anchor) == "function" then
			Deps.effect(function()
				local a = (props.Anchor :: any)()
				if a and typeof(a) == "Instance" and (a :: any):IsA("GuiObject") then
					hoverHandle.Bind(a)
				end
			end)
		elseif typeof(props.Anchor) == "Instance" and (props.Anchor :: any):IsA("GuiObject") then
			hoverHandle.Bind(props.Anchor :: any)
		end
	end

	-- Handle dwell delay
	Deps.effect(function()
		local hovered = isHovered()
		if timerThread then
			task.cancel(timerThread)
			timerThread = nil
		end

		if hovered then
			timerThread = task.delay(delayTime, function()
				isOpen(true)
			end)
		else
			isOpen(false)
		end
	end)

	local effectiveAnchor = function()
		if props.Anchor then
			return if typeof(props.Anchor) == "function" then (props.Anchor :: any)() else props.Anchor
		end
		return childRef()
	end

	local floating = useFloating({
		Anchor = effectiveAnchor,
		Placement = (props.Placement or "top") :: any,
		Offset = props.Offset or 6,
		AutoFlip = true,
		IsOpen = isOpen,
	})

	local renderBadge = function()
		if not isOpen() then return nil end

		return ScopedSurface {
			Name = "AetherTooltip",
			Layer = "Tooltips",
			Position = floating.Position,
			Size = UDim2.new(0, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Color3.fromRGB(15, 20, 30),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			ZIndex = 100,

			create "UICorner" { CornerRadius = UDim.new(0, 6) },
			create "UIStroke" { Color = Color3.fromRGB(60, 80, 120), Thickness = 1, Transparency = 0.3 },
			create "UIPadding" {
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			},

			if typeof(props.Content) == "string" then
				if props.RenderContent then
					props.RenderContent(props.Content)
				else
					create "TextLabel" {
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.XY,
						Text = props.Content,
						TextColor3 = Color3.fromRGB(240, 240, 240),
						TextSize = 10,
						Font = Enum.Font.GothamMedium,
						ZIndex = 101,
					}
			elseif typeof(props.Content) == "function" then
				props.Content()
			else
				props.Content,
		}
	end

	if props.Child then
		return create "Frame" {
			Name = "TooltipContainer",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,

			action(function(node: GuiObject)
				if node then
					hoverHandle.Bind(node)
					childRef(node)
				end
			end),

			props.Child,
			renderBadge,
		}
	end

	return renderBadge
end

return Tooltip
