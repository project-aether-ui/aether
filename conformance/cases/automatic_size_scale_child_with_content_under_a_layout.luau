--!strict
--[[
	DOES A LAYOUT OVERRIDE THE CONTENT RULE, OR SIT UNDER IT?

	Two rules are now established on their own, and nothing tests them together.
	Content behind a scale child wins without a layout: `{1,0, 0.5,20}` over an
	80-tall Inner measures 80, not the 120 that resolving against the offered space
	gives. And a layout appears to resolve against the offered space: the same child
	with no content and a UIListLayout measures 120, not the 30 the content rule
	gives.

	This is both at once. The child has content AND a layout, and the two rules
	point at different numbers:

	    if content still wins under a layout    Auto =  80  (pass through to Inner)
	    if a layout forces the offered space    Auto = 120  (0.5 x 200 + 20)

	`asserted` at the first, which is what is implemented -- grow() passes a child
	with content through without consulting the layout at all. If the engine says
	120, that assumption is wrong and the layout takes precedence over content,
	which changes the order the rework has to apply them in.
]]
return {
	name = "AutomaticSize with a Scale child that has content, under a layout",
	provenance = "asserted",
	note = "Tests the two established rules against each other for the first time. Content wins "
		.. "without a layout; a layout resolves against the offered space without content. "
		.. "Which takes precedence when both apply is unknown and decides the rework's order.",
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
