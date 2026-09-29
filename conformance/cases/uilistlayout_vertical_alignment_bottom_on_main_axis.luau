--!strict
return {
	name = "UIListLayout VerticalAlignment Bottom pushes a vertical run down",
	provenance = "asserted",
	note = "Measurement S7, Bottom. Rows 20, 30 and 20 in a 100 tall panel: aligning the run to the "
		.. "bottom starts it at 30, ignoring the main axis leaves it at 0. Expected from "
		.. "UIGridStyleLayout's alignment documentation.",
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
					VerticalAlignment = { "Enum", "VerticalAlignment", "Bottom" },
				},
			},
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 60, 0, 30 } } },
			{ class = "Frame", name = "C", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "A", x = 0, y = 30, w = 60, h = 20 },
		{ name = "B", x = 0, y = 50, w = 60, h = 30 },
		{ name = "C", x = 0, y = 80, w = 60, h = 20 },
	},
}
