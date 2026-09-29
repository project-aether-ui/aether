--!strict
return {
	name = "UIListLayout Wraps moves an overflowing child to a new row",
	provenance = "asserted",
	note = "Measurement S12. Widths 60, 80 and 40 in a 150 wide panel, Padding 5: C does not fit and "
		.. "wraps to x 0. The gap between rows is a guess of Padding (y 35); 0 would give 30. The "
		.. "documentation is silent on line spacing.",
	surface = { width = 150, height = 60 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 150, 0, 60 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					Wraps = true,
					Padding = { "UDim", 0, 5 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 80, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 60, h = 20 },
		{ name = "B", x = 65, y = 0, w = 80, h = 30 },
		{ name = "C", x = 0, y = 35, w = 40, h = 20 },
	},
}
