--!strict
return {
	name = "UIListLayout Padding scale resolves against the parent's height",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.PaddingScale" },
	note = "Panel 120 tall with UIPadding 10 top and bottom, Padding UDim(0.1, 4). The engine "
		.. "leaves a gap of 14: the scale resolves against the 100 tall content box, not the "
		.. "panel.",
	surface = { width = 200, height = 120 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 120 } },
		children = {
			{
				class = "UIPadding",
				name = "Inset",
				props = {
					PaddingTop = { "UDim", 0, 10 },
					PaddingBottom = { "UDim", 0, 10 },
				},
			},
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Vertical" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					Padding = { "UDim", 0.1, 4 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 50, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 50, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 50, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 10, w = 50, h = 20 },
		{ name = "B", x = 0, y = 44, w = 50, h = 20 },
		{ name = "C", x = 0, y = 78, w = 50, h = 20 },
	},
}
