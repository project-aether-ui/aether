--!strict
return {
	name = "UISizeConstraint clamps a list child and the list advances by the clamped size",
	provenance = "asserted",
	note = "Measurement C5. A 40 tall child capped at 20 in a vertical list: A is 20 tall and B "
		.. "follows at y 20, not 40. Expected from the documentation's 'overwrites any size the "
		.. "layout would apply'.",
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
				props = { Size = { "UDim2", 0, 100, 0, 40 } },
				children = {
					{
						class = "UISizeConstraint",
						name = "Constraint",
						props = {
							MaxSize = { "Vector2", 1000, 20 },
						},
					},
				},
			},
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 50, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 100, h = 20 },
		{ name = "B", x = 0, y = 20, w = 50, h = 20 },
	},
}
