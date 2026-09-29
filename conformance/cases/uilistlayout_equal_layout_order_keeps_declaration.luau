--!strict
return {
	name = "UIListLayout breaks an equal LayoutOrder by declaration order",
	provenance = "asserted",
	note = "Measurement S3. SortOrder is LayoutOrder and every child has LayoutOrder 0, declared C, "
		.. "A, B, so a declaration tie-break puts C first and a Name tie-break puts A first. The "
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
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 80, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "C", x = 0, y = 0, w = 60, h = 20 },
		{ name = "A", x = 0, y = 20, w = 80, h = 30 },
		{ name = "B", x = 0, y = 50, w = 40, h = 20 },
	},
}
