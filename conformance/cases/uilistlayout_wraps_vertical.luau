--!strict
return {
	name = "UIListLayout Wraps moves an overflowing child to a new column",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.Wraps" },
	note = "Heights 60, 80 and 40 in a 150 tall panel, Padding 5. The engine wraps C to y 0 and "
		.. "spaces the columns by Padding (x 35).",
	surface = { width = 60, height = 150 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 60, 0, 150 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Vertical" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					Wraps = true,
					Padding = { "UDim", 0, 5 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 20, 0, 60 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 80 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 20, 0, 40 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 20, h = 60 },
		{ name = "B", x = 0, y = 65, w = 30, h = 80 },
		{ name = "C", x = 35, y = 0, w = 20, h = 40 },
	},
}
