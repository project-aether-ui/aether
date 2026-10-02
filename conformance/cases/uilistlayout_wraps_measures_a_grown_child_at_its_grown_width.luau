--!strict
--[[
	A flex grown AutomaticSize Y child of a wrapping list is measured at the
	width it grows to, not at its basis.

	Each panel is a horizontal list with Wraps, AutomaticSize Y and
	VerticalAlignment Top. It holds a 40 by 40 Icon, a Text frame that grows
	(UIFlexItem Grow, UISizeConstraint MinSize X 120) and is AutomaticSize Y,
	and a 150 by 28 Actions frame. Text holds six 50 by 20 tiles in a wrapping
	list of its own, so its height depends on its width with no text involved.

	At its minimum width of 120 Text fits two tiles a line and is 60 tall. In
	the 200, 260 and 320 panels Actions wraps, Text grows to 150, 210 or 270
	and is 40 tall, and Actions sits at 50: the first line is as tall as Text
	at its grown width. In the 420 panel all three share a line, and at 600
	Text grows to 390 and holds every tile in one line of 20.
]]

local function panel(width: number, y: number)
	local p = "Top" .. width
	local tiles = {}
	for i = 1, 6 do
		table.insert(tiles, {
			class = "Frame",
			name = p .. "T" .. i,
			props = { LayoutOrder = i, Size = { "UDim2", 0, 50, 0, 20 } },
		})
	end
	table.insert(tiles, {
		class = "UIListLayout",
		name = p .. "TextLayout",
		props = {
			FillDirection = { "Enum", "FillDirection", "Horizontal" },
			SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
			Wraps = true,
		},
	})
	table.insert(tiles, {
		class = "UIFlexItem",
		name = p .. "Flex",
		props = { FlexMode = { "Enum", "UIFlexMode", "Grow" } },
	})
	table.insert(tiles, {
		class = "UISizeConstraint",
		name = p .. "Min",
		props = { MinSize = { "Vector2", 120, 0 } },
	})
	return {
		class = "Frame",
		name = p,
		props = {
			Position = { "UDim2", 0, 0, 0, y },
			Size = { "UDim2", 0, width, 0, 0 },
			AutomaticSize = { "Enum", "AutomaticSize", "Y" },
		},
		children = {
			{
				class = "UIListLayout",
				name = p .. "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					Padding = { "UDim", 0, 10 },
					Wraps = true,
				},
			},
			{ class = "Frame", name = p .. "Icon", props = { LayoutOrder = 1, Size = { "UDim2", 0, 40, 0, 40 } } },
			{
				class = "Frame",
				name = p .. "Text",
				props = {
					LayoutOrder = 2,
					Size = { "UDim2", 0, 0, 0, 0 },
					AutomaticSize = { "Enum", "AutomaticSize", "Y" },
				},
				children = tiles,
			},
			{ class = "Frame", name = p .. "Actions", props = { LayoutOrder = 3, Size = { "UDim2", 0, 150, 0, 28 } } },
		},
	}
end

--- A child's rectangle from its offset within the panel at `y`.
local function at(name: string, y: number, x: number, dy: number, w: number, h: number)
	return { name = name, x = x, y = y + dy, w = w, h = h }
end

return {
	name = "UIListLayout with Wraps measures a grown AutomaticSize child at its grown width",
	provenance = "asserted",
	requires = { "UIFlexItem", "UISizeConstraint", "UIListLayout.Wraps" },
	note = "From a command-bar measurement on 2026-10-02 against 0.741.19.7411056, not yet from "
		.. "this runner: panel heights 78, 78, 78, 40 and 40 for widths 200, 260, 320, 420 and 600, "
		.. "with Actions at y 50 in the three that wrap. Offsets were read from AbsolutePosition "
		.. "against each panel.",
	surface = { width = 600, height = 500 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			panel(200, 0),
			panel(260, 100),
			panel(320, 200),
			panel(420, 300),
			panel(600, 400),
		},
	},

	expect = {
		at("Top200", 0, 0, 0, 200, 78),
		at("Top200Icon", 0, 0, 0, 40, 40),
		at("Top200Text", 0, 50, 0, 150, 40),
		at("Top200Actions", 0, 0, 50, 150, 28),

		at("Top260", 100, 0, 0, 260, 78),
		at("Top260Icon", 100, 0, 0, 40, 40),
		at("Top260Text", 100, 50, 0, 210, 40),
		at("Top260Actions", 100, 0, 50, 150, 28),

		at("Top320", 200, 0, 0, 320, 78),
		at("Top320Icon", 200, 0, 0, 40, 40),
		at("Top320Text", 200, 50, 0, 270, 40),
		at("Top320Actions", 200, 0, 50, 150, 28),

		at("Top420", 300, 0, 0, 420, 40),
		at("Top420Icon", 300, 0, 0, 40, 40),
		at("Top420Text", 300, 50, 0, 210, 40),
		at("Top420Actions", 300, 270, 0, 150, 28),

		at("Top600", 400, 0, 0, 600, 40),
		at("Top600Icon", 400, 0, 0, 40, 40),
		at("Top600Text", 400, 50, 0, 390, 20),
		at("Top600Actions", 400, 450, 0, 150, 28),
	},
}
