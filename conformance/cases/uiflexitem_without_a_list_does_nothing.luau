--!strict
return {
	name = "UIFlexItem under a parent with no UIListLayout has no effect",
	provenance = "asserted",
	note = "Measurement F15, no layout. A Grow child of a plain panel keeps its own Position and "
		.. "Size. Expected from the documentation's 'within a UIListLayout'.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 100 } },
		children = {
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 40, 0, 20 }, Position = { "UDim2", 0, 10, 0, 10 } },
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
		},
	},

	expect = {
		{ name = "A", x = 10, y = 10, w = 40, h = 20 },
	},
}
