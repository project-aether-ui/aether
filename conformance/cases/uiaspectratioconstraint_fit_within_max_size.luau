--!strict
return {
	name = "UIAspectRatioConstraint FitWithinMaxSize fits the ratio inside the element's own size",
	provenance = "asserted",
	requires = { "UIAspectRatioConstraint" },
	note = "A 100 by 20 frame at (10, 10) with AspectRatio 2, FitWithinMaxSize and no layout. Asserted: "
		.. "the largest 2 to 1 size inside 100 by 20, 40 by 20. Keeping the width would give 100 by "
		.. "50, and fitting the 300 by 200 parent 300 by 150. Needs a Studio pass.",
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
							AspectType = { "Enum", "AspectType", "FitWithinMaxSize" },
							DominantAxis = { "Enum", "DominantAxis", "Width" },
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
