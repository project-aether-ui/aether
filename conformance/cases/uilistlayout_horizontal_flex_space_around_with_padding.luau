--!strict
return {
	name = "UIListLayout HorizontalFlex SpaceAround keeps Padding as a fixed gap",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.Flex" },
	note = "Widths 20, 40 and 60 in 240 with Padding 6. The engine gives A 20, B 80, C 160, "
		.. "exactly as with no Padding: SpaceAround ignores Padding here.",
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
					HorizontalFlex = { "Enum", "UIFlexAlignment", "SpaceAround" },
					Padding = { "UDim", 0, 6 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 20, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 20, y = 0, w = 20, h = 20 },
		{ name = "B", x = 80, y = 0, w = 40, h = 20 },
		{ name = "C", x = 160, y = 0, w = 60, h = 20 },
	},
}
