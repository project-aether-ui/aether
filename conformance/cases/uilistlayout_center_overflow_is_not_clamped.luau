--!strict
return {
	name = "UIListLayout centres an overflowing run past the top edge",
	provenance = "asserted",
	note = "Measurement S9. 70 of rows in a 60 tall panel with VerticalAlignment Center: an "
		.. "unclamped centre starts the run at -5, a clamped one at 0. The documentation is silent "
		.. "here, so this expectation is a guess for the Studio run to overwrite.",
	surface = { width = 200, height = 60 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 60 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Vertical" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Center" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 60, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = -5, w = 60, h = 20 },
		{ name = "B", x = 0, y = 15, w = 60, h = 30 },
		{ name = "C", x = 0, y = 45, w = 60, h = 20 },
	},
}
