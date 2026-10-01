--!strict
return {
	name = "UIListLayout Wraps with HorizontalAlignment Center centres each row on its own width",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIListLayout.Wraps", "UIListLayout.MainAxisAlignment" },
	note = "Rows of 140 and 40 in a 150 wide panel with HorizontalAlignment Center. The engine "
		.. "centres each row on its own width, putting C at 55.",
	surface = { width = 150, height = 60 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 150, 0, 60 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Center" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					Wraps = true,
					Padding = { "UDim", 0, 5 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 75, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 5, y = 0, w = 60, h = 20 },
		{ name = "B", x = 70, y = 0, w = 75, h = 30 },
		{ name = "C", x = 55, y = 35, w = 40, h = 20 },
	},
}
