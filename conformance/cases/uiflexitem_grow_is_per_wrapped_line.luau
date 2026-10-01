--!strict
return {
	name = "UIFlexItem Grow with Wraps grows within its own line",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIFlexItem", "UIListLayout.Wraps" },
	note = "Three 60 wide children in 150 with Wraps, A Grow. The engine grows A by its own line's "
		.. "30 free (90) and wraps C to y 20.",
	surface = { width = 150, height = 60 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 150, 0, 60 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					Wraps = true,
				},
			},
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 60, 0, 20 } },
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
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 90, h = 20 },
		{ name = "B", x = 90, y = 0, w = 60, h = 20 },
		{ name = "C", x = 0, y = 20, w = 60, h = 20 },
	},
}
