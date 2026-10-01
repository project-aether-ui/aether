--!strict
return {
	name = "UIAspectRatioConstraint ScaleWithParentSize with DominantAxis Width keeps the width",
	provenance = "asserted",
	requires = { "UIAspectRatioConstraint" },
	note = "A 100 by 20 frame at (10, 10) with AspectRatio 2, ScaleWithParentSize and DominantAxis "
		.. "Width. Asserted: the width stays 100 and the height follows the ratio, 100 by 50, "
		.. "growing past the 20 it was given. FitWithinMaxSize would give 40 by 20, and taking the "
		.. "300 wide parent's width 300 by 150. Needs a Studio pass.",
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
					Size = { "UDim2", 0, 100, 0, 20 },
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
							DominantAxis = { "Enum", "DominantAxis", "Width" },
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 10, y = 10, w = 100, h = 50 },
	},
}
