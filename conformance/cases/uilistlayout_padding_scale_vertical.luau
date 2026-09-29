--!strict
return {
	name = "UIListLayout Padding scale resolves against the parent's height",
	provenance = "asserted",
	note = "Measurement S6, vertical. Panel 120 tall with UIPadding 10 top and bottom, Padding "
		.. "UDim(0.1, 4): a gap of 16 means scale of the panel, 14 means scale of the content box, 4 "
		.. "means the scale is dropped. Expected from the documentation's 'percentage of the "
		.. "parent's size'.",
	surface = { width = 200, height = 120 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 120 } },
		children = {
			{
				class = "UIPadding",
				name = "Inset",
				props = {
					PaddingTop = { "UDim", 0, 10 },
					PaddingBottom = { "UDim", 0, 10 },
				},
			},
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Vertical" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					Padding = { "UDim", 0.1, 4 },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 50, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 50, 0, 20 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 50, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 10, w = 50, h = 20 },
		{ name = "B", x = 0, y = 46, w = 50, h = 20 },
		{ name = "C", x = 0, y = 82, w = 50, h = 20 },
	},
}
