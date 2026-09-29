--!strict
return {
	name = "UIGridLayout StartCorner BottomRight",
	provenance = "asserted",
	note = "Measurement G6, BottomRight. Three 100 cells in a 220 panel, alignment Left and Top: A "
		.. "in the bottom right cell (120, 120), B to its left, C above A. Starting within a "
		.. "top-left aligned block would put A at (105, 105) instead. Whether the corner is the "
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
					StartCorner = { "Enum", "StartCorner", "BottomRight" },
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
		{ name = "A", x = 120, y = 120, w = 100, h = 100 },
		{ name = "B", x = 15, y = 120, w = 100, h = 100 },
		{ name = "C", x = 120, y = 15, w = 100, h = 100 },
	},
}
