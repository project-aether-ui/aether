--!strict
--[=[
	Combobox — Composite Headless Primitive (Autocomplete / Searchable Dropdown)
	Part of Aether.Primitives (Layer 2B Composite).
	
	Embeds:
	- Aether.Primitives.TextInput (search input & virtual caret)
	- Aether.Engine.useFloating (anchor placement & auto-flip)
	- Aether.Controllers.SelectionModel (keyboard roving & selection state)
	- Aether.Runtime.For (keyed item diffing & isolated spring lifecycles)
	- Aether.Primitives.PressableFrame (hit-tested option rows)
	- Aether.Primitives.ScopedSurface (popup boundary & click-outside dismissal)
]=]

local isRoblox = typeof(game) == "Instance"
local Deps = require("../Deps")
local TextInput = require("../TextInput")
local useFloating = require("../useFloating")
local For = require("../For")
--- Renamed from PressableFrame in ms-51 M14; same primitive.
local PressableFrame = require("./Pressable")
local ScopedSurface = require("../ScopedSurface")
local ScrollArea = require("./ScrollArea")

local SelectionModel = require("../controllers/SelectionModel")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, UDim, Vector2, Color3, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.UDim, Deps.Vocabulary.Vector2, Deps.Vocabulary.Color3, Deps.Vocabulary.Enum

local create = Deps.create
local source = Deps.source
local action = Deps.action
local effect = Deps.effect

export type ComboboxProps<T> = {
	Items: { T } | (() -> { T }),
	Value: (T | (() -> T?))?,
	OnSelect: ((item: T) -> ())?,
	Filter: ((item: T, query: string) -> boolean)?,
	GetKey: ((item: T) -> string)?,
	GetLabel: ((item: T) -> string)?,
	Placeholder: string?,
	Placement: string?,
	MaxVisibleItems: number?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	RenderItem: ((item: T, isHighlighted: () -> boolean, isSelected: () -> boolean) -> any)?,
	RenderPopupContainer: ((children: () -> any) -> any)?,
}

local function defaultFilter<T>(item: T, query: string, getLabel: (T) -> string): boolean
	if query == "" then return true end
	local label = getLabel(item)
	return string.find(string.lower(label), string.lower(query), 1, true) ~= nil
end

local function defaultGetLabel<T>(item: T): string
	if typeof(item) == "string" then
		return item
	elseif typeof(item) == "table" and (item :: any).Label then
		return tostring((item :: any).Label)
	elseif typeof(item) == "table" and (item :: any).Name then
		return tostring((item :: any).Name)
	end
	return tostring(item)
end

local function defaultGetKey<T>(item: T, getLabel: (T) -> string): string
	if typeof(item) == "string" then
		return item
	elseif typeof(item) == "table" and (item :: any).Id then
		return tostring((item :: any).Id)
	elseif typeof(item) == "table" and (item :: any).Key then
		return tostring((item :: any).Key)
	end
	return getLabel(item)
end

local function Combobox<T>(props: ComboboxProps<T>): any
	local getLabel = props.GetLabel or defaultGetLabel
	local getKey = props.GetKey or function(item: T) return defaultGetKey(item, getLabel) end
	local filterFn = props.Filter or function(item: T, q: string) return defaultFilter(item, q, getLabel) end

	local isOpen = source(false)
	local query = source("")
	local anchorFrame = source(nil :: GuiObject?)

	local selection = SelectionModel.new({ Mode = "single" })
	if props.Value ~= nil then
		local val = if typeof(props.Value) == "function" then (props.Value :: any)() else props.Value
		if val ~= nil then
			selection.Select(getKey(val :: T))
		end
	end

	local getItems = function(): { T }
		if typeof(props.Items) == "function" then
			return (props.Items :: any)()
		elseif typeof(props.Items) == "table" then
			return props.Items :: { T }
		end
		return {}
	end

	local filteredItems = function(): { T }
		local all = getItems()
		local q = query()
		local out = {}
		for _, item in ipairs(all) do
			if filterFn(item, q) then
				table.insert(out, item)
			end
		end
		return out
	end

	local floating = useFloating({
		Anchor = function() return anchorFrame() end,
		Placement = (props.Placement or "bottom-start") :: any,
		Offset = 4,
		AutoFlip = true,
		IsOpen = isOpen,
	})

	local function selectItem(item: T)
		local key = getKey(item)
		selection.Select(key)
		query(getLabel(item))
		isOpen(false)
		if props.OnSelect then
			props.OnSelect(item)
		end
	end

	local itemsList = For({
		Each = filteredItems,
		Key = function(item: T) return getKey(item) end,
		Render = function(itemSource: () -> T, key: string)
			local isSelected = function() return selection.IsSelected(key) end

			if props.RenderItem then
				return props.RenderItem(itemSource(), isSelected, isSelected)
			end

			return PressableFrame {
				Name = `Item_{key}`,
				Size = UDim2.new(1, 0, 0, 28),
				OnActivated = function()
					selectItem(itemSource())
				end,

				create "TextLabel" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -16, 1, 0),
					Position = UDim2.new(0, 8, 0, 0),
					Text = function() return getLabel(itemSource()) end,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = function()
						return if isSelected() then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(200, 200, 200)
					end,
					TextSize = 14,
				},
			}
		end,
	})

	local popupContent = ScopedSurface {
		Name = "ComboboxPopup",
		Layer = "Dropdowns",
		Policy = "Modal",
		Visible = isOpen,
		Position = props.Position or UDim2.new(0, 0, 1, 4),
		Size = props.PopupSize or UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Color3.fromRGB(18, 24, 38),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ZIndex = 100,
		OnDismiss = function()
			isOpen(false)
		end,

		create "UICorner" { CornerRadius = UDim.new(0, 8) },
		create "UIStroke" { Color = Color3.fromRGB(60, 85, 130), Thickness = 1, Transparency = 0.3 },
		create "UIPadding" {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
		},

		ScrollArea({
			Size = UDim2.fromScale(1, 1),
			AutoHide = true,
			Motion = { Period = 0.15, DampingRatio = 0.85 },
			Content = function()
				return create "Frame" {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					create "UIListLayout" {
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 2),
					},
					itemsList,
				}
			end,
		}),
	}

	local popupRender = if props.RenderPopupContainer
		then props.RenderPopupContainer(function() return popupContent end)
		else popupContent

	return create "Frame" {
		Name = "AetherCombobox",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, 32),
		Position = props.Position or UDim2.new(0, 0, 0, 0),
		AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
		LayoutOrder = props.LayoutOrder or 0,

		-- Anchor Reference Binding
		action(function(node: GuiObject)
			anchorFrame(node)
		end),

		-- 1. Input Trigger
		TextInput {
			Value = query,
			PlaceholderText = props.Placeholder or "Select...",
			Size = UDim2.new(1, 0, 1, 0),
			OnChanged = function(newText: string)
				query(newText)
				if not isOpen() then
					isOpen(true)
				end
			end,
			OnFocusGained = function()
				isOpen(true)
			end,
		},

		-- 2. Floating Popup
		popupRender,
	}
end

return Combobox
