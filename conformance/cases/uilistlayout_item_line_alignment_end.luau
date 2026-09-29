--!strict
return {
	name = "UIListLayout ItemLineAlignment End on a single line",
	provenance = "asserted",
	note = "Measurement S22, End. Heights 20, 30 and 40 in a 60 tall panel, no Wraps: A 40, B 30, C "
		.. "20 if the line is the panel's 60; 20, 10, 0 if the line is the tallest child. The guess "
		.. "is that a single line spans the panel, as in CSS. The documentation does not say how "
		.. "tall the one line is.",
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
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
					ItemLineAlignment = { "Enum", "ItemLineAlignment", "End" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 40, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 40, 0, 40 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 40, w = 40, h = 20 },
		{ name = "B", x = 40, y = 30, w = 40, h = 30 },
		{ name = "C", x = 80, y = 20, w = 40, h = 40 },
	},
}
