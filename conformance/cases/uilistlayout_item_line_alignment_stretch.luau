--!strict
return {
	name = "UIListLayout ItemLineAlignment Stretch on a single line",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.ItemLineAlignment" },
	note = "Heights 20, 30 and 40 in a 60 tall panel, no Wraps. The engine stretches every child "
		.. "to 40, the tallest child's height, not to the panel's 60.",
	surface = { width = 200, height = 60 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 60 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					ItemLineAlignment = { "Enum", "ItemLineAlignment", "Stretch" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 40 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 40, h = 40 },
		{ name = "B", x = 40, y = 0, w = 40, h = 40 },
		{ name = "C", x = 80, y = 0, w = 40, h = 40 },
	},
}
