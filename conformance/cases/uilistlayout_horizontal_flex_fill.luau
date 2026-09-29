--!strict
return {
	name = "UIListLayout HorizontalFlex Fill grows every child by an equal share",
	provenance = "asserted",
	note = "Measurement S17, Fill. Widths 20, 40 and 60 in 240: an equal share of the 120 free gives "
		.. "60, 80, 100; equal final widths would give 80 each; growth in proportion to width would "
		.. "give 40, 80, 120. The documentation says siblings fill the space but not how it is "
		.. "divided, so the equal share is a guess.",
	surface = { width = 240, height = 40 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 240, 0, 40 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					HorizontalFlex = { "Enum", "UIFlexAlignment", "Fill" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 20, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 60, h = 20 },
		{ name = "B", x = 60, y = 0, w = 80, h = 20 },
		{ name = "C", x = 140, y = 0, w = 100, h = 20 },
	},
}
