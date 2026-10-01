--!strict
return {
	name = "UIGridLayout CellPadding scale resolves against the parent's size",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIGridLayout" },
	note = "CellPadding 0.1 scale, 50 cells, a 220 panel with UIPadding 10. The engine leaves a "
		.. "gap of 20 (B at 80): the scale resolves against the 200 content box, not the panel.",
	surface = { width = 220, height = 220 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 220, 0, 220 } },
		children = {
			{
				class = "UIPadding",
				name = "Inset",
				props = {
					PaddingTop = { "UDim", 0, 10 },
					PaddingBottom = { "UDim", 0, 10 },
					PaddingLeft = { "UDim", 0, 10 },
					PaddingRight = { "UDim", 0, 10 },
				},
			},
			{
				class = "UIGridLayout",
				name = "Grid",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					StartCorner = { "Enum", "StartCorner", "TopLeft" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					CellSize = { "UDim2", 0, 50, 0, 50 },
					CellPadding = { "UDim2", 0.1, 0, 0.1, 0 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 10, y = 10, w = 50, h = 50 },
		{ name = "B", x = 80, y = 10, w = 50, h = 50 },
		{ name = "C", x = 150, y = 10, w = 50, h = 50 },
	},
}
