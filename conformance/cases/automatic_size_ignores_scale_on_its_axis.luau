--!strict
--[[
	THE CYCLE, and the rule that breaks it.

	A parent measuring an axis automatically depends on its children; a child
	sized in Scale on that axis depends on its parent. Roblox breaks the cycle by
	treating the child's scale as contributing NOTHING to the measurement — the
	parent measures only the offset part, and the child then resolves against the
	result.

	This repo already has a gate forbidding the construction (`verify_autosize_cycles`),
	which is the right response for our own code. The standard still has to say
	what happens when someone writes it anyway, because Roblox does something
	specific rather than erroring.
]]
return {
	name = "AutomaticSize measures only the offset of a Scale-sized child",
	provenance = "asserted",
	note = "Roblox treats a child's Scale on the automatic axis as zero for measurement, so the "
		.. "parent should measure the child's 20px offset. Measured here: the parent resolves to "
		.. "height 0 -- it excludes a scale-sized child from the measurement ENTIRELY rather than "
		.. "counting its offset. The child itself is correct at h=20 (scale against a zero parent, "
		.. "plus 20 offset). Verify in Studio before changing Layout.",
	surface = { width = 200, height = 200 },

	tree = {
		class = "Frame",
		name = "Auto",
		props = {
			Size = { "UDim2", 0, 100, 0, 0 },
			AutomaticSize = { "Enum", "AutomaticSize", "Y" },
		},
		children = {
			{ class = "UIListLayout", name = "Layout" },
			-- 0.5 scale on the measured axis, plus 20 offset.
			{ class = "Frame", name = "Mixed", props = { Size = { "UDim2", 1, 0, 0.5, 20 } } },
		},
	},

	expect = {
		-- Only the offset contributes, so the parent is 20 tall.
		{ name = "Auto", w = 100, h = 20 },
	},
}
