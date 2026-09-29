--!strict
return {
	name = "UIListLayout Wraps with VerticalAlignment Bottom aligns the block of rows",
	provenance = "asserted",
	note = "Measurement S14. Wrapped rows (30 and 20 tall, gap 5) in a 100 tall panel with "
		.. "VerticalAlignment Bottom: the guess is that the block of rows sits at the bottom with "
		.. "the first row on top (A 55, B 45, C 80); rows stacking upward from the bottom edge would "
		.. "put C at 45. The documentation is silent here, so this expectation is a guess for the "
		.. "Studio run to overwrite.",
	surface = { width = 150, height = 100 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 150, 0, 100 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Bottom" },
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
		{ name = "A", x = 0, y = 55, w = 60, h = 20 },
		{ name = "B", x = 65, y = 45, w = 80, h = 30 },
		{ name = "C", x = 0, y = 80, w = 40, h = 20 },
	},
}
