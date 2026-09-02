--!strict
--[[
	SETTLED AT 30, AND IT IS NOT CONVERGENCE.

	Held for 120 frames -- two seconds -- and the engine still returns 30. The
	earlier reading at the default three heartbeats returned the same number, so
	30 is where the engine settles and not a frame caught mid-iteration. The
	fixed-point story (30 as H2 of a series walking to 40) is dead.

	WHAT 30 ACTUALLY IS. The child is `{1,0, 0.5,20}` with nothing behind it. Take
	the content size of the subtree counting OFFSETS ONLY -- the child contributes
	its own 20 and nothing else -- and then resolve the child against THAT:

	    C = 20                      offsets only, no scale resolved
	    0.5 x C + 20 = 30           the child resolved against the content
	    max(C, 30) = 30             what the parent grows to

	This single rule reproduces every reading we have, which is what makes it worth
	writing down rather than another fit:

	    this case      C = 20   0.5(20) + 20 = 30   -> 30   (engine 30)
	    ...with content C = 80   0.5(80) + 20 = 60   -> 80   (engine 80)
	    full scale     C = 90   1.0(90) +  0 = 90   -> 90   (engine 90)
	    full, childless C = 0   1.0(0)  +  0 =  0   -> 0    (unmeasurable, warns)

	A SCALE CHILD RESOLVES AGAINST THE CONTENT, NOT AGAINST THE OFFERED SPACE --
	except under a UIListLayout, where the two verified cases give `0.5 x 200 + 20
	= 120` and `0.5 x 80 + 20 = 60`, both of which are the space OFFERED to the
	parent. Two readings is thin evidence for that branch and both share one scale
	and one offset; treat "a layout switches the resolution to the offered space"
	as the least-verified part of this.

	WHY THIS STAYS `divergent`. We produce 120 here because grow() resolves a
	childless scale child against the offered space whether or not there is a
	layout. Closing it means resolving against the content-derived size instead,
	which is a rework of grow() and not a condition change. Documented as a gap
	until that happens, so the number is not silently forgotten.
]]
return {
	name = "AutomaticSize with a Scale child and NO layout",
	provenance = "divergent",
	note = "Engine 0.736.0.7361346 settles at h = 30 over 120 frames; we produce 120. The engine "
		.. "resolves the scale against the offset-only content size (0.5 x 20 + 20), not against "
		.. "the offered space. Closing this is a rework of grow(), not a condition change.",

	--- KEPT AT 120 DELIBERATELY. It is the evidence that 30 is settled rather than
	--- sampled, and dropping back to the default would throw that away.
	settleFrames = 120,

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
