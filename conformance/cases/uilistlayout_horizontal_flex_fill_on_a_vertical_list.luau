--!strict
return {
	name = "UIListLayout HorizontalFlex Fill stretches a vertical list's children across",
	provenance = "asserted",
	note = "Measurement S20, Fill. On a vertical list HorizontalFlex is the cross axis, and the "
		.. "documentation says Fill makes siblings fill the horizontal space: every child becomes "
		.. "200 wide.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 100 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Vertical" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					HorizontalFlex = { "Enum", "UIFlexAlignment", "Fill" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 80, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 200, h = 20 },
		{ name = "B", x = 0, y = 20, w = 200, h = 20 },
		{ name = "C", x = 0, y = 40, w = 200, h = 20 },
	},
}
