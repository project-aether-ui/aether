--!strict
return {
	name = "UIFlexItem Shrink stops at a UISizeConstraint MinSize",
	provenance = "asserted",
	note = "Measurement F13. A 160 Shrink with MinSize 120 wide, B 100 none, in 200: A would shrink "
		.. "to 100 but stops at 120, and B sits at 120. Expected from the UISizeConstraint "
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
				props = { Size = { "UDim2", 0, 160, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Shrink" },
						},
					},
					{
						class = "UISizeConstraint",
						name = "Constraint",
						props = {
							MinSize = { "Vector2", 120, 0 },
						},
					},
				},
			},
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 100, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 120, h = 20 },
		{ name = "B", x = 120, y = 0, w = 100, h = 20 },
	},
}
