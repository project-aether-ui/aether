--!strict
return {
	name = "UIFlexItem Fill grows into free space",
	provenance = "asserted",
	note = "Measurement F8, under. A (Fill) and B (none), 40 wide each in 200: A grows to 160. "
		.. "Expected from the documentation's Fill, which both grows and shrinks.",
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
							FlexMode = { "Enum", "UIFlexMode", "Fill" },
						},
					},
				},
			},
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 160, h = 20 },
		{ name = "B", x = 160, y = 0, w = 40, h = 20 },
	},
}
