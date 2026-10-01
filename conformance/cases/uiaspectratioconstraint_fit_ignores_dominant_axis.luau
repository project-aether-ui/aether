--!strict
return {
	name = "UIAspectRatioConstraint FitWithinMaxSize ignores DominantAxis",
	provenance = "asserted",
	requires = { "UIAspectRatioConstraint" },
	note = "A 40 by 100 frame at (10, 10) with AspectRatio 2, FitWithinMaxSize and DominantAxis Height. "
		.. "Asserted: DominantAxis counts only under ScaleWithParentSize, so the frame fits inside "
		.. "its own size at 40 by 20. If Height were honoured here it would keep its height, 200 "
		.. "by 100. Needs a Studio pass.",
	surface = { width = 300, height = 200 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 300, 0, 200 } },
		children = {
			{
				class = "Frame",
				name = "A",
				props = {
					Size = { "UDim2", 0, 40, 0, 100 },
					Position = { "UDim2", 0, 10, 0, 10 },
					AnchorPoint = { "Vector2", 0, 0 },
				},
				children = {
					{
						class = "UIAspectRatioConstraint",
						name = "Aspect",
						props = {
							AspectRatio = 2,
							AspectType = { "Enum", "AspectType", "FitWithinMaxSize" },
							DominantAxis = { "Enum", "DominantAxis", "Height" },
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 10, y = 10, w = 40, h = 20 },
	},
}
