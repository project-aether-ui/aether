--!strict
return {
	name = "UIFlexItem Grow under HorizontalFlex Fill grows alongside its siblings",
	provenance = "asserted",
	note = "Measurement F9, Fill. Three 40 wide children in 240, A Grow, list Fill: if the list's "
		.. "Fill still grows the others, each gains 40 (80 wide); if one flex item switches Fill off "
		.. "for the rest, A alone becomes 160. The documentation is silent here, so this expectation "
		.. "is a guess for the Studio run to overwrite.",
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
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 40, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Grow" },
						},
					},
				},
			},
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 80, h = 20 },
		{ name = "B", x = 80, y = 0, w = 80, h = 20 },
		{ name = "C", x = 160, y = 0, w = 80, h = 20 },
	},
}
