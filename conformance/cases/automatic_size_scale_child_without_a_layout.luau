--!strict
--[[
	THE ONE READING NO RULE EXPLAINS. The engine returned 30.

	This case was written to separate "the scale magnitude decides" from "a
	UIListLayout decides", predicting 120 for the first and 20 for the second. The
	engine said neither, and its sibling case answered the question anyway: content
	behind the child decides (see automatic_size_half_scale_child_with_content).
	Under that rule this child has no content, so it is measured, and measuring it
	gives `0.5 x 200 + 20 = 120`. We produce 120. The engine produced 30.

	WHY 30 LOOKS LIKE A SAMPLE RATHER THAN AN ANSWER. This is the degenerate cycle:
	the parent's height depends on the child's and the child's on the parent's,
	with no content to break it. Iterating from zero:

	    H0 = 0    H1 = 0.5(0)  + 20 = 20    H2 = 0.5(20) + 20 = 30
	    H3 = 35   H4 = 37.5    ...          -> 40, the fixed point of H = 0.5H + 20

	30 is exactly H2. A value that lands on the second step of a converging series,
	and matches no closed-form rule, is more likely a frame the runner sampled than
	a number the engine settled on. The fixed point would be 40 = offset / (1 - scale).

	THE EXPERIMENT THAT SETTLES IT: run this case again holding more frames before
	reading the rectangles. If it walks 30 -> 35 -> 37.5, it is convergence and the
	answer is 40. If it sits at 30 however long you wait, 30 is real, our 120 is
	wrong, and the measured branch needs to resolve against the offset rather than
	the offered space.

	`divergent` UNTIL THEN, and deliberately not `roblox`: recording 30 as the
	standard would commit the implementation to reproducing a specific iteration
	count, which is a race rather than a rule. Do not encode it without the second
	reading.
]]
return {
	name = "AutomaticSize with a Scale child and NO layout",
	provenance = "divergent",
	note = "Engine 0.736.0.7361346 returned h = 30; we produce 120. 30 is the second step of a "
		.. "fixed-point iteration converging on 40, so it is probably a sampled frame rather "
		.. "than a settled value. Needs a re-read with more frames held before it becomes roblox.",
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
