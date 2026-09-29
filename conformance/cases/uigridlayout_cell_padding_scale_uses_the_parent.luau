--!strict
return {
	name = "UIGridLayout CellPadding scale resolves against the parent's size",
	provenance = "asserted",
	note = "Measurement G3. CellPadding 0.1 scale, 50 cells, a 220 panel with UIPadding 10: the "
		.. "parent gives a 22 gap (B at 82), the content box a 20 gap (B at 80). Expected from the "
		.. "documentation's 'scale of the parent'.",
	surface = { width = 220, height = 220 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 220, 0, 220 } },
		children = {
			{
				class = "UIPadding",
				name = "Inset",
				props = {
					PaddingTop = { "UDim", 0, 10 },
					PaddingBottom = { "UDim", 0, 10 },
					PaddingLeft = { "UDim", 0, 10 },
					PaddingRight = { "UDim", 0, 10 },
				},
			},
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
					CellPadding = { "UDim2", 0.1, 0, 0.1, 0 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 10, y = 10, w = 50, h = 50 },
		{ name = "B", x = 82, y = 10, w = 50, h = 50 },
		{ name = "C", x = 154, y = 10, w = 50, h = 50 },
	},
}
