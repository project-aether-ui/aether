--!strict
return {
	name = "UIFlexItem ItemLineAlignment Stretch overrides the list's Center",
	provenance = "asserted",
	note = "Measurement F11. List ItemLineAlignment Center in a 60 tall panel, B carries Stretch: A "
		.. "and C centre at y 20, B stretches to 60. Expected from the documentation's per item "
		.. "override; the line is assumed to span the panel.",
	surface = { width = 200, height = 60 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 60 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					ItemLineAlignment = { "Enum", "ItemLineAlignment", "Center" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{
				class = "Frame",
				name = "B",
				props = { Size = { "UDim2", 0, 40, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							ItemLineAlignment = { "Enum", "ItemLineAlignment", "Stretch" },
						},
					},
				},
			},
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 20, w = 40, h = 20 },
		{ name = "B", x = 40, y = 0, w = 40, h = 60 },
		{ name = "C", x = 80, y = 20, w = 40, h = 20 },
	},
}
