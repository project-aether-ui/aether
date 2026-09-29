--!strict
return {
	name = "UIGridLayout CellSize scale resolves against the padded content box",
	provenance = "asserted",
	note = "Measurement G2. CellSize 0.5 scale in a 220 panel with UIPadding 10: the content box "
		.. "gives 100 cells, two per row (C at y 110); the panel gives 110 cells, one per row (B at "
		.. "y 120). The documentation is silent here, so this expectation is a guess for the Studio "
		.. "run to overwrite.",
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
					CellSize = { "UDim2", 0.5, 0, 0.5, 0 },
					CellPadding = { "UDim2", 0, 0, 0, 0 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 10, y = 10, w = 100, h = 100 },
		{ name = "B", x = 110, y = 10, w = 100, h = 100 },
		{ name = "C", x = 10, y = 110, w = 100, h = 100 },
	},
}
