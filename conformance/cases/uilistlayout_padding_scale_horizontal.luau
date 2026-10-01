--!strict
return {
	name = "UIListLayout Padding scale resolves against the parent's width",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.PaddingScale" },
	note = "Panel 120 wide with UIPadding 10 left and right, Padding UDim(0.1, 4). The engine "
		.. "leaves a gap of 14: the scale resolves against the 100 wide content box, not the "
		.. "panel.",
	surface = { width = 120, height = 60 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 120, 0, 60 } },
		children = {
			{
				class = "UIPadding",
				name = "Inset",
				props = {
					PaddingLeft = { "UDim", 0, 10 },
					PaddingRight = { "UDim", 0, 10 },
				},
			},
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					Padding = { "UDim", 0.1, 4 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 20, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 20, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 20, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 10, y = 0, w = 20, h = 30 },
		{ name = "B", x = 44, y = 0, w = 20, h = 30 },
		{ name = "C", x = 78, y = 0, w = 20, h = 30 },
	},
}
