--!strict
return {
	name = "UIListLayout HorizontalAlignment Center centres a horizontal run",
	provenance = "asserted",
	note = "Measurement S8. Widths 60, 80 and 40 in a 200 wide panel: centring the run starts it at "
		.. "10, ignoring the main axis leaves it at 0. Expected from UIGridStyleLayout's alignment "
		.. "documentation.",
	surface = { width = 200, height = 60 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 60 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Center" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 80, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 10, y = 0, w = 60, h = 20 },
		{ name = "B", x = 70, y = 0, w = 80, h = 20 },
		{ name = "C", x = 150, y = 0, w = 40, h = 20 },
	},
}
