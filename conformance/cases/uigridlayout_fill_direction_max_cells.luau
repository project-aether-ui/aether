--!strict
return {
	name = "UIGridLayout FillDirectionMaxCells caps a row before the width does",
	provenance = "asserted",
	note = "Measurement G5. Five 50 cells in a 400 panel with FillDirectionMaxCells 2: two per row, "
		.. "E alone on the third row. Expected from the UIGridLayout documentation.",
	surface = { width = 400, height = 400 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 400, 0, 400 } },
		children = {
			{
				class = "UIGridLayout",
				name = "Grid",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					StartCorner = { "Enum", "StartCorner", "TopLeft" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					CellSize = { "UDim2", 0, 50, 0, 50 },
					CellPadding = { "UDim2", 0, 5, 0, 5 },
					FillDirectionMaxCells = 2,
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "D", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "E", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 50, h = 50 },
		{ name = "B", x = 55, y = 0, w = 50, h = 50 },
		{ name = "C", x = 0, y = 55, w = 50, h = 50 },
		{ name = "D", x = 55, y = 55, w = 50, h = 50 },
		{ name = "E", x = 0, y = 110, w = 50, h = 50 },
	},
}
