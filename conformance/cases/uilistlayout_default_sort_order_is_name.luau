--!strict
return {
	name = "UIListLayout with SortOrder unset orders children by Name",
	provenance = "asserted",
	note = "Measurement S2, the geometric half of S1. SortOrder is left unset and children are "
		.. "declared C, A, B with equal LayoutOrder, so a Name default puts A first and declaration "
		.. "order puts C first. Expected from the reflection default of Name.",
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
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
				},
			},
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 80, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 80, h = 30 },
		{ name = "B", x = 0, y = 30, w = 40, h = 20 },
		{ name = "C", x = 0, y = 50, w = 60, h = 20 },
	},
}
