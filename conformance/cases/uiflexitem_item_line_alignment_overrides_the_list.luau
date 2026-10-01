--!strict
return {
	name = "UIFlexItem ItemLineAlignment Stretch overrides the list's Center",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	note = "List ItemLineAlignment Center, B carries Stretch, every child 20 tall in a 60 tall "
		.. "panel. The engine leaves all three at y 0 and 20 tall: the line is as tall as its "
		.. "tallest child, so neither Center nor Stretch has room to move anything, and this case "
		.. "cannot show the override.",
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
					ItemLineAlignment = { "Enum", "ItemLineAlignment", "Center" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{
				class = "Frame",
				name = "B",
				props = { Size = { "UDim2", 0, 40, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							ItemLineAlignment = { "Enum", "ItemLineAlignment", "Stretch" },
						},
					},
				},
			},
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 40, h = 20 },
		{ name = "B", x = 40, y = 0, w = 40, h = 20 },
		{ name = "C", x = 80, y = 0, w = 40, h = 20 },
	},
}
