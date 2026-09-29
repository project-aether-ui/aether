--!strict
return {
	name = "UIGridLayout lets a UISizeConstraint shrink a child within its cell",
	provenance = "asserted",
	note = "Measurement G8, size constraint. A carries MaxSize 60 by 60 in a 100 cell: it becomes 60 "
		.. "by 60 at the cell's corner, and B keeps its cell. Expected from the documentation's 'a "
		.. "UIConstraint on the child overrides CellSize'.",
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
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					CellSize = { "UDim2", 0, 100, 0, 100 },
					CellPadding = { "UDim2", 0, 5, 0, 5 },
				},
			},
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 30, 0, 30 } },
				children = {
					{
						class = "UISizeConstraint",
						name = "Constraint",
						props = {
							MaxSize = { "Vector2", 60, 60 },
						},
					},
				},
			},
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 60, h = 60 },
		{ name = "B", x = 105, y = 0, w = 100, h = 100 },
	},
}
