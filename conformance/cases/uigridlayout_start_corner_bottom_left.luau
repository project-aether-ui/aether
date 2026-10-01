--!strict
return {
	name = "UIGridLayout StartCorner BottomLeft",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIGridLayout" },
	note = "Three 100 cells in a 220 panel, alignment Left and Top. The engine starts at the "
		.. "bottom of the two row block, not the panel: A (0, 105), B (105, 105), C (0, 0).",
	surface = { width = 220, height = 220 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 220, 0, 220 } },
		children = {
			{
				class = "UIGridLayout",
				name = "Grid",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					StartCorner = { "Enum", "StartCorner", "BottomLeft" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					CellSize = { "UDim2", 0, 100, 0, 100 },
					CellPadding = { "UDim2", 0, 5, 0, 5 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 105, w = 100, h = 100 },
		{ name = "B", x = 105, y = 105, w = 100, h = 100 },
		{ name = "C", x = 0, y = 0, w = 100, h = 100 },
	},
}
