--!strict
--[[
	DOES A UILISTLAYOUT REALLY SWITCH THE RESOLUTION TO THE OFFERED SPACE?

	Without a layout the engine resolves a scale child against the content size
	counting offsets only: a childless `{1,0, 0.5,20}` measures `0.5 x 20 + 20 = 30`.
	With a layout the same child measures 120, which is `0.5 x 200 + 20` -- the space
	offered to the parent. So a layout appears to change what the scale resolves
	against.

	THAT REST ON TWO READINGS THAT SHARE ONE SCALE AND ONE OFFSET, which is the exact
	shape of confound that produced two wrong rules already: `0.5 x 200 + 20 = 120`
	and `0.5 x 20 + 20 = 30` are both consistent with other arithmetic on the same
	two numbers. Changing the scale separates them and nothing else does.

	    if a layout resolves against the offered space   Auto = 70  (0.25 x 200 + 20)
	    if the content rule holds under a layout too     Auto = 25  (0.25 x  20 + 20)

	`asserted` at the first, which is what is implemented. Answer this BEFORE
	reworking grow(): the rework's whole design is which of these two it is.
]]
return {
	name = "AutomaticSize with a quarter-Scale child under a layout",
	provenance = "roblox",
	verifiedAgainst = "0.736.0.7361346",
	note = "ANSWERED: the engine returns 70, so a layout really does resolve against the offered "
		.. "space and 0.5 was not doing the work. Separates 'a UIListLayout resolves against the offered space' from 'the content rule "
		.. "holds under a layout too'. Both verified layout cases use scale 0.5, where the two "
		.. "readings are confounded; 0.25 splits them 70 against 25.",
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
			{ class = "Frame", name = "Mixed", props = { Size = { "UDim2", 1, 0, 0.25, 20 } } },
		},
	},

	expect = {
		{ name = "Auto", x = 0, y = 0, w = 100, h = 70 },
	},
}
