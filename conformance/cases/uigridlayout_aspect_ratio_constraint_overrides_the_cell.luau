--!strict
return {
	name = "UIGridLayout lets a UIAspectRatioConstraint reshape a child within its cell",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIGridLayout", "UIAspectRatioConstraint" },
	note = "A carries a UIAspectRatioConstraint of 2 in a 100 cell. The engine makes it 100 by 50 "
		.. "and centres it vertically in its cell at y 25; B keeps its own cell.",
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
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					CellSize = { "UDim2", 0, 100, 0, 100 },
					CellPadding = { "UDim2", 0, 5, 0, 5 },
				},
			},
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 30, 0, 30 } },
				children = {
					{ class = "UIAspectRatioConstraint", name = "Aspect", props = { AspectRatio = 2 } },
				},
			},
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 25, w = 100, h = 50 },
		{ name = "B", x = 105, y = 0, w = 100, h = 100 },
	},
}
