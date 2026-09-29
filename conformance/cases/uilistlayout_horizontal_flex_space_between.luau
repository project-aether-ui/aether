--!strict
return {
	name = "UIListLayout HorizontalFlex SpaceBetween puts the free space between children",
	provenance = "asserted",
	note = "Measurement S17, SpaceBetween. Widths 20, 40 and 60 in 240: two gaps of 60, first and "
		.. "last child on the edges. Expected from the CSS meaning the enum name borrows.",
	surface = { width = 240, height = 40 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 240, 0, 40 } },
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
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 20, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 20, h = 20 },
		{ name = "B", x = 80, y = 0, w = 40, h = 20 },
		{ name = "C", x = 180, y = 0, w = 60, h = 20 },
	},
}
