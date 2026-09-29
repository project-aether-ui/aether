--!strict
return {
	name = "UIFlexItem Custom GrowRatio 0 and 1 gives all free space to the second",
	provenance = "asserted",
	note = "Measurement F4, zero and one. Two 40 wide children in 200 with GrowRatio 0 and 1: B "
		.. "takes all 120 free and becomes 160. Expected from the GrowRatio documentation.",
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
				props = { Size = { "UDim2", 0, 40, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Custom" },
							GrowRatio = 0,
						},
					},
				},
			},
			{
				class = "Frame",
				name = "B",
				props = { Size = { "UDim2", 0, 40, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Custom" },
							GrowRatio = 1,
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 40, h = 20 },
		{ name = "B", x = 40, y = 0, w = 160, h = 20 },
	},
}
