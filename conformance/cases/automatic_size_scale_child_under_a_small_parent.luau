--!strict
--[[
	THE DISCRIMINATING CASE. It exists to separate two hypotheses that the
	verified data cannot.

	`automatic_size_with_a_scale_sized_child` established that a frame with
	`AutomaticSize.Y` containing a child sized `{1,0, 0.5,20}` measures to 120 on
	a 200-tall surface. 120 is `0.5 × 200 + 20`, which is consistent with BOTH of:

	    A. the child's scale resolves against the space AVAILABLE to the parent
	    B. the child's scale resolves against the SURFACE

	They were indistinguishable there because the parent's available space WAS the
	surface. Here the auto-sizing frame sits inside a grandparent only 80 tall:

	    A predicts   0.5 × 80  + 20  =  60
	    B predicts   0.5 × 200 + 20  = 120

	Whatever Studio reports is the rule. Until then this is `asserted` at A, which
	is the more principled of the two and the one being implemented — so if the
	answer is B, this case is what catches it rather than a user noticing months
	later that nested auto-sizing is wrong.
]]
return {
	name = "AutomaticSize with a Scale child under a smaller grandparent",
	provenance = "roblox",
	verifiedAgainst = "0.736.0.7361346",
	note = "ANSWERED: the engine produces 60, so the scale resolves against the space AVAILABLE to "
		.. "the parent (80) and not against the surface (200). The rule in LAYOUT.md is confirmed "
		.. "rather than assumed.",
	surface = { width = 200, height = 200 },

	tree = {
		class = "Frame",
		name = "Grandparent",
		props = { Size = { "UDim2", 0, 150, 0, 80 } },
		children = {
			{
				class = "Frame",
				name = "Auto",
				props = {
					Size = { "UDim2", 0, 100, 0, 0 },
					AutomaticSize = { "Enum", "AutomaticSize", "Y" },
				},
				children = {
					{ class = "UIListLayout", name = "Layout" },
					{ class = "Frame", name = "Mixed", props = { Size = { "UDim2", 1, 0, 0.5, 20 } } },
				},
			},
		},
	},

	expect = {
		{ name = "Auto", w = 100, h = 60 },
	},
}
