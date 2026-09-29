--!strict
return {
	name = "UISizeConstraint MaxSize shrinks a child below its Size",
	provenance = "asserted",
	note = "Measurement C2. A 100 by 100 frame with MaxSize 50 by 60 and no layout becomes 50 by 60 "
		.. "at its own Position. Expected from the UISizeConstraint documentation.",
	surface = { width = 200, height = 200 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 200 } },
		children = {
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 100, 0, 100 }, Position = { "UDim2", 0, 10, 0, 10 } },
				children = {
					{
						class = "UISizeConstraint",
						name = "Constraint",
						props = {
							MaxSize = { "Vector2", 50, 60 },
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 10, y = 10, w = 50, h = 60 },
	},
}
