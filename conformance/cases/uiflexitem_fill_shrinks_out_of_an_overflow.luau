--!strict
return {
	name = "UIFlexItem Fill shrinks out of an overflow",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIFlexItem" },
	note = "A 150 (Fill) and B 100 (none) in 200. The engine shrinks A by the whole 50 overflow, "
		.. "to 100.",
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
				props = { Size = { "UDim2", 0, 150, 0, 20 } },
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
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 100, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 100, h = 20 },
		{ name = "B", x = 100, y = 0, w = 100, h = 20 },
	},
}
