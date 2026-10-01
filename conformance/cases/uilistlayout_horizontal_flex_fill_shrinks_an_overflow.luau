--!strict
return {
	name = "UIListLayout HorizontalFlex Fill shrinks overflowing children by an equal share",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.Flex" },
	note = "Widths 60, 90 and 150 in 240 overflow by 60. The engine gives 48, 72 and 120: each "
		.. "child loses in proportion to its width, not an equal share.",
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
					HorizontalFlex = { "Enum", "UIFlexAlignment", "Fill" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 90, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 150, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 48, h = 20 },
		{ name = "B", x = 48, y = 0, w = 72, h = 20 },
		{ name = "C", x = 120, y = 0, w = 120, h = 20 },
	},
}
