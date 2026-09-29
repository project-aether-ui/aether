--!strict
return {
	name = "UIFlexItem Custom ShrinkRatio 1 and 3 shares an overflow one to three",
	provenance = "asserted",
	note = "Measurement F7. A 100 and B 140 in 200 overflow by 40, ShrinkRatio 1 and 3: A loses 10 "
		.. "and B 30, giving 90 and 110. An equal share gives 80 and 120. Expected from the "
		.. "ShrinkRatio documentation, assuming no weighting by width.",
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
				props = { Size = { "UDim2", 0, 100, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Custom" },
							ShrinkRatio = 1,
						},
					},
				},
			},
			{
				class = "Frame",
				name = "B",
				props = { Size = { "UDim2", 0, 140, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Custom" },
							ShrinkRatio = 3,
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 90, h = 20 },
		{ name = "B", x = 90, y = 0, w = 110, h = 20 },
	},
}
