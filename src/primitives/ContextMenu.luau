--!strict
--[=[
	ContextMenu — Composite Headless Primitive (Cursor / Anchor Popover Menu)
	Part of Aether.Primitives (Layer 2B Composite).
	
	Embeds:
	- Aether.Engine.useFloating (cursor positioning & boundary auto-flip)
	- Aether.Primitives.ScopedSurface (modal isolation & click-outside dismissal)
	- Aether.Primitives.PressableFrame (hit-tested menu item rows)
	- Aether.Runtime.For (keyed item diffing)
]=]

local isRoblox = typeof(game) == "Instance"
local Deps = require("../Deps")
local useFloating = require("../useFloating")
local For = require("../For")
--- Renamed from PressableFrame in ms-51 M14; same primitive.
local PressableFrame = require("./Pressable")
local ScopedSurface = require("../ScopedSurface")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, UDim, Color3, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.UDim, Deps.Vocabulary.Color3, Deps.Vocabulary.Enum

local create = Deps.create
local source = Deps.source

export type ContextMenuItem = {
	Id: string,
	Label: string,
	Icon: string?,
	Disabled: boolean?,
	OnActivated: (() -> ())?,
}

export type ContextMenuProps = {
	IsOpen: () -> boolean,
	OnClose: () -> (),
	AnchorPosition: () -> Vector2,
	Items: () -> { ContextMenuItem },
	Width: number?,
	RenderItem: ((item: ContextMenuItem, isHovered: () -> boolean) -> any)?,
}

local function ContextMenu(props: ContextMenuProps): any
	local floating = useFloating({
		Anchor = props.AnchorPosition,
		Placement = "bottom-start",
		Offset = 2,
		AutoFlip = true,
		IsOpen = props.IsOpen,
	})

	local itemsSource = if typeof(props.Items) == "function" then props.Items else function() return props.Items end

	local itemsList = For({
		Each = itemsSource,
		Key = "Id",
		Render = function(itemSource: () -> ContextMenuItem, key: string)
			if props.RenderItem then
				return props.RenderItem(itemSource(), function() return false end)
			end

			local isHovered = source(false)

			return PressableFrame {
				Name = `Item_{key}`,
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = function()
					return if isHovered() then Color3.fromRGB(35, 48, 72) else Color3.fromRGB(0, 0, 0)
				end,
				BackgroundTransparency = function()
					return if isHovered() then 0.2 else 1
				end,
				BorderSizePixel = 0,
				Disabled = function() return itemSource().Disabled or false end,
				OnHoverChanged = function(h)
					isHovered(h)
				end,
				OnActivated = function()
					props.OnClose()
					local item = itemSource()
					if item.OnActivated then
						item.OnActivated()
					end
				end,

				create "UICorner" { CornerRadius = UDim.new(0, 4) },

				create "TextLabel" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -16, 1, 0),
					Position = UDim2.new(0, 8, 0, 0),
					Text = function() return itemSource().Label end,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = function()
						return if itemSource().Disabled then Color3.fromRGB(130, 130, 130) else Color3.fromRGB(240, 240, 240)
					end,
					Font = Enum.Font.GothamMedium,
					TextSize = 11,
					ZIndex = 101,
				},
			}
		end,
	})

	local autoSizeY = if Enum and Enum.AutomaticSize then Enum.AutomaticSize.Y else nil

	return ScopedSurface {
		Name = "AetherContextMenu",
		Layer = "Popups",
		Policy = "Modal",
		Visible = props.IsOpen,
		Position = props.Position or UDim2.fromOffset(0, 264),
		Size = props.Size or UDim2.new(1, 0, 0, 0),
		AutomaticSize = autoSizeY,
		BackgroundColor3 = Color3.fromRGB(18, 24, 38),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = 100,
		OnDismiss = props.OnClose,

		create "UICorner" { CornerRadius = UDim.new(0, 8) },
		create "UIStroke" { Color = Color3.fromRGB(60, 85, 130), Thickness = 1, Transparency = 0.3 },
		create "UIPadding" {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
		},

		create "UIListLayout" {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 3),
		},

		itemsList,
	}
end

return ContextMenu
