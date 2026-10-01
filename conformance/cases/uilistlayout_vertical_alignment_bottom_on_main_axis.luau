--!strict
return {
	name = "UIListLayout VerticalAlignment Bottom pushes a vertical run down",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.MainAxisAlignment" },
	note = "Rows 20, 30 and 20 in a 100 tall panel. The engine aligns the run to the bottom on the "
		.. "main axis, starting it at 30.",
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
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Bottom" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 60, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 30, w = 60, h = 20 },
		{ name = "B", x = 0, y = 50, w = 60, h = 30 },
		{ name = "C", x = 0, y = 80, w = 60, h = 20 },
	},
}
