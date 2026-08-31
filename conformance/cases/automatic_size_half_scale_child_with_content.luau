--!strict
--[[
	DOES CONTENT BEHIND A PARTIAL SCALE CHILD COUNT TOO?

	The verified pass-through case has content behind the face (a 90-wide Inner)
	and the verified available-space cases have none. So "a scale-sized child with
	children is passed through, one without is resolved" fits the evidence just as
	well as the scale magnitude does -- and would mean `Layout.luau` discriminates
	on the wrong property while still passing every case.

	This puts content behind a 0.5-scale child, where the two hypotheses split:

	    if the scale magnitude is the rule    Auto = 120  (0.5 x 200 + 20; the
	                                                       80 of content is behind
	                                                       a measured child and is
	                                                       not reached)
	    if having content is the rule         Auto =  80  (pass-through to Inner)

	`asserted` at the first, which is what is implemented. Note that both readings
	are defensible: the engine has to break the cycle somewhere, and "resolve the
	child" and "measure its content" are the only two places to break it.
]]
return {
	name = "AutomaticSize with a half-Scale child that HAS content",
	provenance = "asserted",
	note = "Separates 'scale magnitude decides' from 'the presence of content behind the child "
		.. "decides'. The verified pass-through case has content; the available-space cases do not.",
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
		{ name = "Auto", x = 0, y = 0, w = 100, h = 120 },
	},
}
