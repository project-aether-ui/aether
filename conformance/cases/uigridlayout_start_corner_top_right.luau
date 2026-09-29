--!strict
return {
	name = "UIGridLayout StartCorner TopRight",
	provenance = "asserted",
	note = "Measurement G6, TopRight. Three 100 cells in a 220 panel, alignment Left and Top: A in "
		.. "the panel's top right cell (120, 0), B to its left (15, 0), C below A. Starting from the "
		.. "right of a left-aligned block would put A at 105 instead. Whether the corner is the "
		.. "panel's or the block's is a guess for the Studio run to overwrite.",
	surface = { width = 220, height = 220 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 220, 0, 220 } },
		children = {
			{
				class = "UIGridLayout",
				name = "Grid",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					StartCorner = { "Enum", "StartCorner", "TopRight" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					CellSize = { "UDim2", 0, 100, 0, 100 },
					CellPadding = { "UDim2", 0, 5, 0, 5 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 120, y = 0, w = 100, h = 100 },
		{ name = "B", x = 15, y = 0, w = 100, h = 100 },
		{ name = "C", x = 120, y = 105, w = 100, h = 100 },
	},
}
