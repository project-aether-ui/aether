--!strict
--[[
	IS IT THE SCALE, OR IS IT THE UILISTLAYOUT?

	Two cases established that a `{1,0, 0.5,20}` child resolves against the space
	available to its parent (120 on a 200-tall surface, 60 under an 80-tall
	grandparent). A third established that a `fromScale(1, 1)` child does not --
	measurement passes through it to the content behind.

	`Layout.luau` discriminates on the scale magnitude, which fits all three. But
	BOTH available-space cases contain a UIListLayout and the pass-through case
	does not, so the layout fits them equally well: a UIListLayout computes content
	size itself, and could plausibly resolve a child's scale where a plain parent
	measuring its own children would not.

	This is the first case with a partial scale and NO layout.

	    if the scale magnitude is the rule    Auto = 120  (0.5 x 200 + 20)
	    if the UIListLayout is the rule       Auto =  20  (pass-through: the child
	                                                       has no content, so only
	                                                       its offset remains)

	`asserted` at the first, which is what is implemented. If the engine says 20,
	the discriminator in grow() is wrong and it is only luck that the suite is
	green.
]]
return {
	name = "AutomaticSize with a Scale child and NO layout",
	provenance = "asserted",
	note = "Separates 'scale magnitude decides' from 'a UIListLayout decides'. Both verified "
		.. "available-space cases have a layout; the verified pass-through case does not.",
	surface = { width = 200, height = 200 },

	tree = {
		class = "Frame",
		name = "Auto",
		props = {
			Size = { "UDim2", 0, 100, 0, 0 },
			AutomaticSize = { "Enum", "AutomaticSize", "Y" },
		},
		children = {
			{ class = "Frame", name = "Mixed", props = { Size = { "UDim2", 1, 0, 0.5, 20 } } },
		},
	},

	expect = {
		{ name = "Auto", x = 0, y = 0, w = 100, h = 120 },
	},
}
