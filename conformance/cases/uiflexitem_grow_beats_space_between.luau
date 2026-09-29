--!strict
return {
	name = "UIFlexItem Grow consumes the free space before HorizontalFlex SpaceBetween",
	provenance = "asserted",
	note = "Measurement F9, SpaceBetween. Three 40 wide children in 200, A Grow, list SpaceBetween: "
		.. "if growth wins A is 120 and nothing is left to space (B 120, C 160); if spacing wins A "
		.. "stays 40 and B sits at 80. The documentation is silent here, so this expectation is a "
		.. "guess for the Studio run to overwrite.",
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
					HorizontalFlex = { "Enum", "UIFlexAlignment", "SpaceBetween" },
				},
			},
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 40, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Grow" },
						},
					},
				},
			},
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 120, h = 20 },
		{ name = "B", x = 120, y = 0, w = 40, h = 20 },
		{ name = "C", x = 160, y = 0, w = 40, h = 20 },
	},
}
