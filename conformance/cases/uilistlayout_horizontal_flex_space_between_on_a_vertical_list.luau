--!strict
return {
	name = "UIListLayout HorizontalFlex SpaceBetween on a vertical list moves nothing",
	provenance = "asserted",
	note = "Measurement S20, SpaceBetween. On a vertical list without Wraps each row is alone on the "
		.. "cross axis, so the guess is no effect: widths and x unchanged. The documentation is "
		.. "silent here, so this expectation is a guess for the Studio run to overwrite.",
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
					HorizontalFlex = { "Enum", "UIFlexAlignment", "SpaceBetween" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 80, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 60, h = 20 },
		{ name = "B", x = 0, y = 20, w = 80, h = 20 },
		{ name = "C", x = 0, y = 40, w = 40, h = 20 },
	},
}
