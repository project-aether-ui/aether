--!strict
return {
	name = "UIListLayout HorizontalFlex Fill shrinks overflowing children by an equal share",
	provenance = "asserted",
	note = "Measurement S21. Widths 60, 90 and 150 in 240 overflow by 60: an equal share gives 40, "
		.. "70, 130; shrinking in proportion to width as CSS does gives 48, 72, 120; no shrink "
		.. "leaves the overflow. The documentation is silent here, so this expectation is a guess "
		.. "for the Studio run to overwrite.",
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
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 90, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 150, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 40, h = 20 },
		{ name = "B", x = 40, y = 0, w = 70, h = 20 },
		{ name = "C", x = 110, y = 0, w = 130, h = 20 },
	},
}
