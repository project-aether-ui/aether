--!strict
--[[
	A wrapping list sizes and centres a line on the height of a flex grown
	AutomaticSize Y child at its grown width.

	The panels of `uilistlayout_wraps_measures_a_grown_child_at_its_grown_width`
	under VerticalAlignment Center. Text is 60 tall at its minimum width of 120
	and 40 or 20 once grown, so a line sized on the first answer would be too
	tall and every child in it would sit off its slot.

	In the 420 panel the line is 40, as tall as Icon and Text, and Actions is
	centred at 6. At 600 Text holds every tile in one line of 20 and is
	centred at 10 against the 40 of Icon. Where Actions wraps, each line is as
	tall as its tallest child and nothing moves.
]]

local function panel(width: number, y: number)
	local p = "Center" .. width
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
					VerticalAlignment = { "Enum", "VerticalAlignment", "Center" },
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
	name = "UIListLayout with Wraps centres a line on a grown AutomaticSize child",
	provenance = "asserted",
	requires = { "UIFlexItem", "UISizeConstraint", "UIListLayout.Wraps" },
	note = "From a command-bar measurement on 2026-10-02 against 0.741.19.7411056, not yet from "
		.. "this runner: panel heights 78, 78, 78, 40 and 40 for widths 200, 260, 320, 420 and 600. "
		.. "At 420 Actions is at y 6; at 600 Text is at y 10 and Actions at y 6. Offsets were read "
		.. "from AbsolutePosition against each panel.",
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
		at("Center200", 0, 0, 0, 200, 78),
		at("Center200Icon", 0, 0, 0, 40, 40),
		at("Center200Text", 0, 50, 0, 150, 40),
		at("Center200Actions", 0, 0, 50, 150, 28),

		at("Center260", 100, 0, 0, 260, 78),
		at("Center260Icon", 100, 0, 0, 40, 40),
		at("Center260Text", 100, 50, 0, 210, 40),
		at("Center260Actions", 100, 0, 50, 150, 28),

		at("Center320", 200, 0, 0, 320, 78),
		at("Center320Icon", 200, 0, 0, 40, 40),
		at("Center320Text", 200, 50, 0, 270, 40),
		at("Center320Actions", 200, 0, 50, 150, 28),

		at("Center420", 300, 0, 0, 420, 40),
		at("Center420Icon", 300, 0, 0, 40, 40),
		at("Center420Text", 300, 50, 0, 210, 40),
		at("Center420Actions", 300, 270, 6, 150, 28),

		at("Center600", 400, 0, 0, 600, 40),
		at("Center600Icon", 400, 0, 0, 40, 40),
		at("Center600Text", 400, 50, 10, 390, 20),
		at("Center600Actions", 400, 450, 6, 150, 28),
	},
}
