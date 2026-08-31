--!strict
--[[
	The most basic thing the standard has to say: what a Scale means.

	A child sized in Scale resolves against its PARENT's resolved size, not
	against the surface. Nest two and the inner one is a fraction of a fraction.
]]
return {
	name = "scale resolves against the parent, not the surface",
	provenance = "reference",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "Frame",
				name = "Half",
				props = { Size = { "UDim2", 0.5, 0, 0.5, 0 } },
				children = {
					{
						class = "Frame",
						name = "Quarter",
						props = { Size = { "UDim2", 0.5, 0, 0.5, 0 } },
					},
				},
			},
		},
	},

	expect = {
		{ name = "Root", x = 0, y = 0, w = 200, h = 100 },
		{ name = "Half", x = 0, y = 0, w = 100, h = 50 },
		{ name = "Quarter", x = 0, y = 0, w = 50, h = 25 },
	},
}
