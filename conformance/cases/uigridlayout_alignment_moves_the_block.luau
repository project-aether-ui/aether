--!strict
return {
	name = "UIGridLayout alignment moves the grid as a block, not each row",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIGridLayout" },
	note = "Four 60 cells, three per row, in a 220 panel with HorizontalAlignment Center and "
		.. "VerticalAlignment Bottom. The engine centres the block, not each row (D at x 15), and "
		.. "puts it on the bottom edge (D at y 160).",
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
					StartCorner = { "Enum", "StartCorner", "TopLeft" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Center" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Bottom" },
					CellSize = { "UDim2", 0, 60, 0, 60 },
					CellPadding = { "UDim2", 0, 5, 0, 5 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "D", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 15, y = 95, w = 60, h = 60 },
		{ name = "B", x = 80, y = 95, w = 60, h = 60 },
		{ name = "C", x = 145, y = 95, w = 60, h = 60 },
		{ name = "D", x = 15, y = 160, w = 60, h = 60 },
	},
}
