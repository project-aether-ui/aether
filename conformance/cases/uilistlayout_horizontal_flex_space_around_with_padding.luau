--!strict
return {
	name = "UIListLayout HorizontalFlex SpaceAround keeps Padding as a fixed gap",
	provenance = "asserted",
	note = "Measurement S18, SpaceAround. Padding 6 as a fixed gap leaves 108, 36 per child: A 18, B "
		.. "80, C 162. Ignoring Padding gives 20, 100, 160; adding it after distributing gives 20, "
		.. "106, 192. The documentation is silent here, so this expectation is a guess for the "
		.. "Studio run to overwrite.",
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
					HorizontalFlex = { "Enum", "UIFlexAlignment", "SpaceAround" },
					Padding = { "UDim", 0, 6 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 20, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 18, y = 0, w = 20, h = 20 },
		{ name = "B", x = 80, y = 0, w = 40, h = 20 },
		{ name = "C", x = 162, y = 0, w = 60, h = 20 },
	},
}
