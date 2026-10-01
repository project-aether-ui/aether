--!strict
return {
	name = "UIListLayout with SortOrder unset orders children by Name",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.SortOrder" },
	note = "SortOrder unset, children declared C, A, B with equal LayoutOrder. The engine puts A "
		.. "first: the default is Name.",
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
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
				},
			},
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 80, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 80, h = 30 },
		{ name = "B", x = 0, y = 30, w = 40, h = 20 },
		{ name = "C", x = 0, y = 50, w = 60, h = 20 },
	},
}
