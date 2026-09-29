--!strict
return {
	name = "UIListLayout HorizontalFlex Fill keeps Padding as a fixed gap",
	provenance = "asserted",
	note = "Measurement S18, Fill. Padding 6 leaves 108 free, 36 each: widths 56, 76, 96. Ignoring "
		.. "Padding would give 60, 80, 100. The documentation is silent here, so this expectation is "
		.. "a guess for the Studio run to overwrite.",
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
					Padding = { "UDim", 0, 6 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 20, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 56, h = 20 },
		{ name = "B", x = 62, y = 0, w = 76, h = 20 },
		{ name = "C", x = 144, y = 0, w = 96, h = 20 },
	},
}
