--!strict
return {
	name = "UIFlexItem GrowRatio is ignored when FlexMode is None",
	provenance = "asserted",
	note = "Measurement F5. A has FlexMode None with GrowRatio 2, B is Custom with GrowRatio 1: if "
		.. "A's ratio is ignored B takes all 120 free (A 40, B 160); honoured it would give A 120, B "
		.. "80. Expected from the documentation's 'applies only if FlexMode is Custom'.",
	surface = { width = 200, height = 40 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 40 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Horizontal" },
					SortOrder = { "Enum", "SortOrder", "LayoutOrder" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
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
							FlexMode = { "Enum", "UIFlexMode", "None" },
							GrowRatio = 2,
						},
					},
				},
			},
			{
				class = "Frame",
				name = "B",
				props = { Size = { "UDim2", 0, 40, 0, 20 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Custom" },
							GrowRatio = 1,
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 0, y = 0, w = 40, h = 20 },
		{ name = "B", x = 40, y = 0, w = 160, h = 20 },
	},
}
