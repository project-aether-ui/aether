--!strict
return {
	name = "UIAspectRatioConstraint ScaleWithParentSize with DominantAxis Height keeps the height",
	provenance = "asserted",
	requires = { "UIAspectRatioConstraint" },
	note = "A 40 by 100 frame at (10, 10) with AspectRatio 2, ScaleWithParentSize and DominantAxis "
		.. "Height. Asserted: the height stays 100 and the width follows the ratio, 200 by 100. "
		.. "FitWithinMaxSize would give 40 by 20, and taking the 200 tall parent's height 400 "
		.. "by 200. Needs a Studio pass.",
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
							AspectType = { "Enum", "AspectType", "ScaleWithParentSize" },
							DominantAxis = { "Enum", "DominantAxis", "Height" },
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 10, y = 10, w = 200, h = 100 },
	},
}
