--!strict
return {
	name = "UIGridLayout defaults to 100 pixel cells, 5 pixel padding, filling across",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIGridLayout" },
	note = "Only SortOrder is set. The engine's default CellSize 100, CellPadding 5 and "
		.. "FillDirection Horizontal put three children at (0, 0), (105, 0) and (0, 105).",
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
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 30, 0, 30 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 100, h = 100 },
		{ name = "B", x = 105, y = 0, w = 100, h = 100 },
		{ name = "C", x = 0, y = 105, w = 100, h = 100 },
	},
}
