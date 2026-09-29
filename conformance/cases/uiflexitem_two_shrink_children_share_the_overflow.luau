--!strict
return {
	name = "UIFlexItem two Shrink children share an overflow equally",
	provenance = "asserted",
	note = "Measurement F6. A 100 and B 200, both Shrink, in 150: an equal share of the 150 overflow "
		.. "gives 25 and 125; shrinking in proportion to width as CSS does gives 50 and 100. The "
		.. "documentation is silent here, so this expectation is a guess for the Studio run to "
		.. "overwrite.",
	surface = { width = 150, height = 40 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 150, 0, 40 } },
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
							FlexMode = { "Enum", "UIFlexMode", "Shrink" },
						},
					},
				},
			},
			{
				class = "Frame",
				name = "B",
				props = { Size = { "UDim2", 0, 200, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Shrink" },
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 25, h = 20 },
		{ name = "B", x = 25, y = 0, w = 125, h = 20 },
	},
}
