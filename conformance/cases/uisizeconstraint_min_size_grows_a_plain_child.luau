--!strict
return {
	name = "UISizeConstraint MinSize grows a child past its Size",
	provenance = "asserted",
	note = "Measurement C1. A 40 by 20 frame with MinSize 60 by 50 and no layout becomes 60 by 50 at "
		.. "its own Position. Expected from the UISizeConstraint documentation.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 100 } },
		children = {
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 40, 0, 20 }, Position = { "UDim2", 0, 10, 0, 10 } },
				children = {
					{
						class = "UISizeConstraint",
						name = "Constraint",
						props = {
							MinSize = { "Vector2", 60, 50 },
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 10, y = 10, w = 60, h = 50 },
	},
}
