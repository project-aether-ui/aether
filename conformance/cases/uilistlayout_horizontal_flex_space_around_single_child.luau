--!strict
return {
	name = "UIListLayout HorizontalFlex SpaceAround with a single child",
	provenance = "asserted",
	note = "Measurement S19, SpaceAround. One 60 wide child in 240 is centred at 90. Expected from "
		.. "the CSS meaning.",
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
				},
			},
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 0, 60, 0, 20 } } },
		},
	},

	expect = {
		{ name = "B", x = 90, y = 0, w = 60, h = 20 },
	},
}
