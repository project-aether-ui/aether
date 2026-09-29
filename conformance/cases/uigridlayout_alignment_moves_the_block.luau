--!strict
return {
	name = "UIGridLayout alignment moves the grid as a block, not each row",
	provenance = "asserted",
	note = "Measurement G7. Four 60 cells, three per row, in a 220 panel with HorizontalAlignment "
		.. "Center and VerticalAlignment Bottom: centring the block puts the short row's D at x 15, "
		.. "centring each row puts it at 80. The block sits on the bottom edge (D at y 160). The "
		.. "documentation is silent here, so this expectation is a guess for the Studio run to "
		.. "overwrite.",
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
					StartCorner = { "Enum", "StartCorner", "TopLeft" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Center" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Bottom" },
					CellSize = { "UDim2", 0, 60, 0, 60 },
					CellPadding = { "UDim2", 0, 5, 0, 5 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "D", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 15, y = 95, w = 60, h = 60 },
		{ name = "B", x = 80, y = 95, w = 60, h = 60 },
		{ name = "C", x = 145, y = 95, w = 60, h = 60 },
		{ name = "D", x = 15, y = 160, w = 60, h = 60 },
	},
}
