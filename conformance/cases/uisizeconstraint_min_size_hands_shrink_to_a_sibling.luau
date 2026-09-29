--!strict
return {
	name = "UISizeConstraint MinSize on a Shrink child hands the rest to its Shrink sibling",
	provenance = "asserted",
	note = "Measurement C4. A 160 and B 100 both Shrink in 200, A held at 140 wide: A stops at 140 "
		.. "and B absorbs the rest of the 60 overflow (60 wide). An equal share without "
		.. "redistribution gives B 70. The documentation is silent here, so this expectation is a "
		.. "guess for the Studio run to overwrite.",
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
							MinSize = { "Vector2", 140, 0 },
						},
					},
				},
			},
			{
				class = "Frame",
				name = "B",
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
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 140, h = 20 },
		{ name = "B", x = 140, y = 0, w = 60, h = 20 },
	},
}
