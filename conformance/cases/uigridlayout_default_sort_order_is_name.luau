--!strict
return {
	name = "UIGridLayout with SortOrder unset orders cells by Name",
	provenance = "asserted",
	note = "Measurement G9, the grid's copy of S2. Children declared C, A, B with SortOrder unset: a "
		.. "Name default puts A in the first cell, declaration order puts C there. Expected from the "
		.. "reflection default of Name.",
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
					StartCorner = { "Enum", "StartCorner", "TopLeft" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					CellSize = { "UDim2", 0, 60, 0, 60 },
					CellPadding = { "UDim2", 0, 5, 0, 5 },
				},
			},
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 60, h = 60 },
		{ name = "B", x = 65, y = 0, w = 60, h = 60 },
		{ name = "C", x = 130, y = 0, w = 60, h = 60 },
	},
}
