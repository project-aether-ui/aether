--!strict
return {
	name = "UIAspectRatioConstraint reshapes the size before AnchorPoint reads it",
	provenance = "roblox",
	verifiedAgainst = "0.741.19.7411056",
	requires = { "UIAspectRatioConstraint" },
	note = "A 100 by 20 frame at (150, 100) with AnchorPoint (0.5, 0.5), AspectRatio 2 and "
		.. "FitWithinMaxSize. Asserted: it becomes 40 by 20 and the anchor centres that on the "
		.. "Position, x 130. An anchor applied to the authored 100 would put it at x 100. Needs a "
		.. "Studio pass.",
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
					Position = { "UDim2", 0, 150, 0, 100 },
					AnchorPoint = { "Vector2", 0.5, 0.5 },
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
		{ name = "A", x = 130, y = 90, w = 40, h = 20 },
	},
}
