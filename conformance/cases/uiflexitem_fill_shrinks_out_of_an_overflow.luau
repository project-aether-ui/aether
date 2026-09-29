--!strict
return {
	name = "UIFlexItem Fill shrinks out of an overflow",
	provenance = "asserted",
	note = "Measurement F8, over. A 150 (Fill) and B 100 (none) in 200: A absorbs the 50 overflow "
		.. "and becomes 100. Expected from the documentation's Fill, which both grows and shrinks.",
	surface = { width = 200, height = 40 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 40 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
				},
			},
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 150, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Fill" },
						},
					},
				},
			},
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 100, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 100, h = 20 },
		{ name = "B", x = 100, y = 0, w = 100, h = 20 },
	},
}
