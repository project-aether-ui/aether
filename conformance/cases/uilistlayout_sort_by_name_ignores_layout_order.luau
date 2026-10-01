--!strict
return {
	name = "UIListLayout with SortOrder Name ignores LayoutOrder",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.SortOrder" },
	note = "SortOrder Name with LayoutOrder C=1, B=2, A=3, declared C, B, A. The engine puts A "
		.. "first: LayoutOrder is ignored.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 100 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Vertical" },
					SortOrder = { "Enum", "SortOrder", "Name" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
				},
			},
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 }, LayoutOrder = 1 } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 }, LayoutOrder = 2 } },
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 80, 0, 30 }, LayoutOrder = 3 } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 80, h = 30 },
		{ name = "B", x = 0, y = 30, w = 40, h = 20 },
		{ name = "C", x = 0, y = 50, w = 60, h = 20 },
	},
}
