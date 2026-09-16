--!strict
--[=[
	ContextMenu — Composite Headless Primitive (Cursor / Anchor Popover Menu)
	Part of Aether.Primitives (Layer 2B Composite).

	Embeds:
	- Aether.Core.createContextMenu (open, focus, dismissal, activation)
	- Aether.Engine.useFloating (cursor positioning & boundary auto-flip)
	- Aether.Primitives.ScopedSurface (modal isolation & click-outside dismissal)
	- Aether.Primitives.PressableFrame (hit-tested menu item rows)
	- Aether.Runtime.For (keyed item diffing)

	WHAT IS LEFT HERE IS THE TREE. `core/createContextMenu` decides what is true
	-- whether the menu is open, which row is focused, what a dismissal means and
	what happens when a row activates -- and hands back the props for it. This
	file supplies the two things a machine cannot have, vide's `source` and the
	host's vocabulary, and draws a surface with rows in it.

	COLOUR IS STILL DECIDED HERE, and that is the one piece of state the machine
	could not take. A focused row draws darker, and the value that says so is a
	host type Layer 1 may not name. So the machine answers which row is focused
	and this file turns that into a fill -- a derived property rather than a
	decision, and the last of them goes when primitives take their styling
	instead of choosing it.
]=]

local Deps = require("../Deps")
local useFloating = require("../useFloating")
local For = require("../For")
--- Renamed from PressableFrame in ms-51 M14; same primitive.
local PressableFrame = require("./Pressable")
local ScopedSurface = require("../ScopedSurface")

local createContextMenu = require("../core/createContextMenu").createContextMenu

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
	RenderItem: ((item: ContextMenuItem, isFocused: () -> boolean) -> any)?,
	[any]: any,
}

local function ContextMenu(props: ContextMenuProps): any
	local itemsSource = if typeof(props.Items) == "function" then props.Items else function() return props.Items end

	--- CONTROLLED, because a menu summoned by a right-click sits inside
	--- something that already captured where the click was and keeps the flag
	--- next to it. The machine reads that flag rather than mirroring it, and a
	--- caller with no flag of its own can leave both out and drive the machine.
	local menu = createContextMenu({
		Source = source,
		Items = itemsSource,
		IsOpen = props.IsOpen,
		OnClose = props.OnClose,
	})

	local floating = useFloating({
		Anchor = props.AnchorPosition,
		Placement = "bottom-start",
		Offset = 2,
		AutoFlip = true,
		IsOpen = menu.IsOpen,
	})

	local function itemsList()
		return For({
			Each = itemsSource,
		Key = "Id",
		Render = function(itemSource: () -> ContextMenuItem, key: string, indexSource: () -> number)
			if props.RenderItem then
				--- A REAL ANSWER NOW. This argument used to be a closure that
				--- returned false forever, so a custom row could not draw its own
				--- focus even though the menu knew which row had it.
				return props.RenderItem(itemSource(), function()
					return menu.IsItemFocused(key)
				end)
			end

			return PressableFrame(menu.GetItemProps(key, {
				Size = UDim2.new(1, 0, 0, 26),
				--- ROWS DRAW IN THE ORDER THEY WERE GIVEN. `For` reconciles by
				--- key, so the instances arrive in whatever order the diff
				--- produced, and a list layout sorting on an unset LayoutOrder
				--- falls back to that -- a menu whose rows shuffled between
				--- openings for no reason a reader could see.
				LayoutOrder = indexSource,
				BackgroundColor3 = function()
					return if menu.IsItemFocused(key) then Color3.fromRGB(35, 48, 72) else Color3.fromRGB(0, 0, 0)
				end,
				BackgroundTransparency = function()
					return if menu.IsItemFocused(key) then 0.2 else 1
				end,
				BorderSizePixel = 0,

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
			}))
		end,
		})
	end

	local autoSizeY = if Enum and Enum.AutomaticSize then Enum.AutomaticSize.Y else nil

	return ScopedSurface(menu.GetSurfaceProps({
		Name = "AetherContextMenu",
		Layer = "Popups",
		Policy = "Modal",
		Position = props.Position or UDim2.fromOffset(0, 264),
		Size = props.Size or UDim2.new(1, 0, 0, 0),
		AutomaticSize = autoSizeY,
		BackgroundColor3 = Color3.fromRGB(18, 24, 38),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = 100,

		create "UICorner" { CornerRadius = UDim.new(0, 8) },
		create "UIStroke" { Color = Color3.fromRGB(60, 85, 130), Thickness = 1, Transparency = 0.3 },
		create "UIPadding" {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
		},

		--- THE ROWS GET A CONTAINER OF THEIR OWN, and this is not a wrapper for
		--- tidiness. A modal `ScopedSurface` renders a full-size input barrier as
		--- its FIRST child, so a list layout on the surface itself gave that
		--- barrier the first slot and pushed every row down by the height of the
		--- menu -- rows laid out past the bottom edge, and a press that landed on
		--- the backdrop wherever the menu was drawn. The barrier is not a row and
		--- must not be laid out as one.
		--- BUILT INSIDE THE SURFACE'S SCOPE, which is what `Children` is for. A
		--- row written in the array part here is constructed before the surface
		--- exists, so it registers with the router carrying no scope -- and the
		--- surface's own modal barrier, which HAS one, then outranks every row
		--- and eats the click. The menu drew perfectly and could not be used.
		Children = function()
			return create "Frame" {
				Name = "Items",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = autoSizeY,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 101,

				create "UIListLayout" {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 3),
				},

				itemsList(),
			}
		end,
	}))
end

return ContextMenu
