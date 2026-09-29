--!strict
return {
	name = "UIListLayout HorizontalFlex SpaceBetween keeps Padding as a fixed gap",
	provenance = "asserted",
	note = "Measurement S18, SpaceBetween. Padding 6 as a minimum gap or ignored both give 0, 80, "
		.. "180; adding it after distributing gives 0, 86, 192. Only that last reading is separated "
		.. "here. The documentation is silent here, so this expectation is a guess for the Studio "
		.. "run to overwrite.",
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
					HorizontalFlex = { "Enum", "UIFlexAlignment", "SpaceBetween" },
					Padding = { "UDim", 0, 6 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 20, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 20, h = 20 },
		{ name = "B", x = 80, y = 0, w = 40, h = 20 },
		{ name = "C", x = 180, y = 0, w = 60, h = 20 },
	},
}
