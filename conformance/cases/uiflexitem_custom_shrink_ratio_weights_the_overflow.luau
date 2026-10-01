--!strict
return {
	name = "UIFlexItem Custom ShrinkRatio 1 and 3 shares an overflow one to three",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIFlexItem" },
	note = "A 100 and B 140 in 200 overflow by 40 with ShrinkRatio 1 and 3. The engine gives A "
		.. "92.31 and B 107.69: the overflow splits in proportion to ratio times width (100 and "
		.. "420), so A loses 40 x 100 / 520. Exactly 1200/13 and 1400/13; the runner rounds to two "
		.. "places.",
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
				props = { Size = { "UDim2", 0, 100, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Custom" },
							ShrinkRatio = 1,
						},
					},
				},
			},
			{
				class = "Frame",
				name = "B",
				props = { Size = { "UDim2", 0, 140, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Custom" },
							ShrinkRatio = 3,
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 92.31, h = 20 },
		{ name = "B", x = 92.31, y = 0, w = 107.69, h = 20 },
	},
}
