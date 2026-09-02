--!strict
--[[
	ANSWERED: CONTENT DECIDES, NOT THE SCALE MAGNITUDE.

	The engine returns 80 -- the height of the Inner behind the child -- and not
	the 120 that resolving `0.5 x 200 + 20` against the available space would give.
	So a HALF-scale child with content behind it is passed through exactly as the
	full-scale one was, and `Layout.luau` was discriminating on the wrong property
	while still passing every case that existed.

	The rule this establishes, across all four cases that fit it:

	    a scale-sized child WITHOUT content   measured, `offered x scale + offset`
	    a scale-sized child WITH content      passed through to what is behind it

	which is the cycle broken at the only two places it can be broken. The scale
	magnitude never mattered; `>= 1` fitted the three cases available because the
	one full-scale case happened to be the one with content.

	See automatic_size_scale_child_without_a_layout for the single reading this
	rule does not explain.
]]
return {
	name = "AutomaticSize with a half-Scale child that HAS content",
	provenance = "roblox",
	verifiedAgainst = "0.736.0.7361346",
	note = "Separated 'scale magnitude decides' from 'content behind the child decides'. The "
		.. "engine chose content: 80, not 120. This is what replaced the scale-magnitude "
		.. "discriminator in grow().",
	surface = { width = 200, height = 200 },

	tree = {
		class = "Frame",
		name = "Auto",
		props = {
			Size = { "UDim2", 0, 100, 0, 0 },
			AutomaticSize = { "Enum", "AutomaticSize", "Y" },
		},
		children = {
			{
				class = "Frame",
				name = "Mixed",
				props = { Size = { "UDim2", 1, 0, 0.5, 20 } },
				children = {
					{ class = "Frame", name = "Inner", props = { Size = { "UDim2", 1, 0, 0, 80 } } },
				},
			},
		},
	},

	expect = {
		{ name = "Auto", x = 0, y = 0, w = 100, h = 80 },
	},
}
