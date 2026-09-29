--!strict
return {
	name = "UIListLayout ItemLineAlignment Automatic defers to VerticalAlignment",
	provenance = "asserted",
	note = "Measurement S22, Automatic. Heights 20, 30 and 40 in a 60 tall panel with "
		.. "VerticalAlignment Bottom: the documentation says Automatic defers to the alignment "
		.. "property, so each child sits on the bottom edge.",
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
					VerticalAlignment = { "Enum", "VerticalAlignment", "Bottom" },
					ItemLineAlignment = { "Enum", "ItemLineAlignment", "Automatic" },
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
