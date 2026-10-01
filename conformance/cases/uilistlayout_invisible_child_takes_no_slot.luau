--!strict
return {
	name = "UIListLayout gives an invisible child no slot and no Padding",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	note = "The middle of three children is Visible false, Padding 5. The engine skips it "
		.. "entirely, slot and Padding both, so C is at 35.",
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
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					Padding = { "UDim", 0, 5 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 60, 0, 20 }, Visible = false } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 60, h = 30 },
		{ name = "C", x = 0, y = 35, w = 60, h = 20 },
	},
}
