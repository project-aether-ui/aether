--!strict
return {
	name = "UISizeConstraint MaxSize on a Grow child hands the rest to its Grow sibling",
	provenance = "asserted",
	note = "Measurement C3. A and B both Grow, 40 each in 200, A capped at 60 wide: A stops at 60 "
		.. "and B takes the remaining 100 (140 wide). Without redistribution B would be 100. The "
		.. "documentation is silent here, so this expectation is a guess for the Studio run to "
		.. "overwrite.",
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
							FlexMode = { "Enum", "UIFlexMode", "Grow" },
						},
					},
					{
						class = "UISizeConstraint",
						name = "Constraint",
						props = {
							MaxSize = { "Vector2", 60, 1000 },
						},
					},
				},
			},
			{
				class = "Frame",
				name = "B",
				props = { Size = { "UDim2", 0, 40, 0, 20 } },
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
		{ name = "A", x = 0, y = 0, w = 60, h = 20 },
		{ name = "B", x = 60, y = 0, w = 140, h = 20 },
	},
}
