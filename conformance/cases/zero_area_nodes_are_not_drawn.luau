--!strict
--[[
	A node solved to zero width or height produces nothing to paint, and is
	absent from the display list rather than present with an empty rectangle.

	Worth pinning because it is a rule of the DISPLAY LIST rather than of layout —
	the node exists, was measured, and has a place in the tree. Any implementation
	must drop it at the same point, or a consumer diffing two frames sees nodes
	appear and disappear for reasons the tree does not explain.
]]
return {
	name = "a node with zero area is absent from the display list",
	provenance = "reference",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{ class = "Frame", name = "Visible", props = { Size = { "UDim2", 0, 40, 0, 20 } } },
			{ class = "Frame", name = "Flat", props = { Size = { "UDim2", 0, 40, 0, 0 } } },
		},
	},

	expect = {
		{ name = "Visible", w = 40, h = 20 },
	},
	--- Absence is the half of this case that matters; presence alone would pass
	--- against an implementation that drew the flat node anyway.
	expectAbsent = { "Visible" },
}
