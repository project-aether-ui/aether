--!strict
return {
	name = "UIListLayout Wraps gives a child wider than the panel its own row",
	provenance = "asserted",
	note = "Measurement S16. B is 200 wide in a 150 wide panel: the guess is that it takes its own "
		.. "row unshrunk and C wraps below it; staying on the first row or shrinking to 150 are the "
		.. "alternatives. The documentation is silent here, so this expectation is a guess for the "
		.. "Studio run to overwrite.",
	surface = { width = 150, height = 80 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 150, 0, 80 } },
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
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 200, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 60, h = 20 },
		{ name = "B", x = 0, y = 25, w = 200, h = 20 },
		{ name = "C", x = 0, y = 50, w = 40, h = 20 },
	},
}
