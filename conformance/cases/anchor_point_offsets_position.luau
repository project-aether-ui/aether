--!strict
--[[
	`AnchorPoint` moves the point a Position refers to, from the top-left to a
	fraction of the element's own size. (0.5, 0.5) centres it on its Position.

	Worth pinning early because it is the one property where the element's own
	size feeds back into its own position, which is the shape of every layout bug
	that resolves in the wrong order.
]]
return {
	name = "anchor point shifts an element by a fraction of its own size",
	provenance = "roblox",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "Frame",
				name = "Centred",
				props = {
					AnchorPoint = { "Vector2", 0.5, 0.5 },
					Position = { "UDim2", 0.5, 0, 0.5, 0 },
					Size = { "UDim2", 0, 40, 0, 20 },
				},
			},
		},
	},

	expect = {
		-- Centre is (100, 50); half the element is (20, 10).
		{ name = "Centred", x = 80, y = 40, w = 40, h = 20 },
	},
}
