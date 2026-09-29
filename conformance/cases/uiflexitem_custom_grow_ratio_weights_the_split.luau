--!strict
return {
	name = "UIFlexItem Custom GrowRatio 1 and 2 splits free space one to two",
	provenance = "asserted",
	note = "Measurement F3. Two 40 wide children in 200 with GrowRatio 1 and 2: 40 and 80 of the 120 "
		.. "free, giving 80 and 120. An equal split would give 100 each. Expected from the GrowRatio "
		.. "documentation.",
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
							GrowRatio = 1,
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
							GrowRatio = 2,
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 80, h = 20 },
		{ name = "B", x = 80, y = 0, w = 120, h = 20 },
	},
}
