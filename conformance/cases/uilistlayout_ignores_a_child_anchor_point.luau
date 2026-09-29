--!strict
return {
	name = "UIListLayout places a child with AnchorPoint as though it had none",
	provenance = "asserted",
	note = "Measurement S10. The first child has AnchorPoint (0.5, 0.5): ignored gives (0, 0), "
		.. "applied on both axes gives (-30, -10), applied on the main axis only gives (0, -10). The "
		.. "documentation is silent here, so this expectation is a guess for the Studio run to "
		.. "overwrite.",
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
				},
			},
			{
				class = "Frame",
				name = "A",
				props = {
					Size = { "UDim2", 0, 60, 0, 20 },
					AnchorPoint = { "Vector2", 0.5, 0.5 },
				},
			},
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 60, h = 20 },
		{ name = "B", x = 0, y = 20, w = 60, h = 20 },
	},
}
