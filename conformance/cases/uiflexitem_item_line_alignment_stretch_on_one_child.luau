--!strict
return {
	name = "UIFlexItem ItemLineAlignment Stretch stretches one child in a centred line",
	provenance = "asserted",
	requires = { "UIFlexItem" },
	note = "List ItemLineAlignment Center with children 20, 40 and 30 tall, A carrying a UIFlexItem "
		.. "with Stretch. The line is 40 tall, so the override can show: A is stretched to 40 at y 0, "
		.. "where Center alone would put it 20 tall at y 10, and C stays centred at y 5. Needs a "
		.. "Studio pass.",
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
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 40, 0, 20 }, LayoutOrder = 1 },
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
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 40 }, LayoutOrder = 2 } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 30 }, LayoutOrder = 3 } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 40, h = 40 },
		{ name = "B", x = 40, y = 0, w = 40, h = 40 },
		{ name = "C", x = 80, y = 5, w = 40, h = 30 },
	},
}
