--!strict
--[[
	THE BUTTON SHAPE, and whether it can work at all.

	`automatic_size_with_a_scale_sized_child` and
	`automatic_size_scale_child_under_a_small_parent` between them establish the
	rule: a scale-sized child is measured, with its scale resolved against the
	space AVAILABLE to its parent. Both are Studio-verified.

	Applied to a FULL scale child the rule has an uncomfortable consequence. This
	is Aether's `Button > Face > Content > Label` shape reduced to its bones: an
	AutomaticSize.X frame whose only child is `fromScale(1, 1)`, with real content
	behind it. If the Face resolves against the 200 on offer, the button fills its
	container instead of hugging its label -- on every host, including Roblox, and
	always has.

	    if the rule holds       Outer = 200, Face = 200, Inner = 90
	    if full scale is special    Outer =  90 (measurement passes through)
	    ENGINE                                90

	SO THE SECOND, and the prediction recorded here was wrong. Measurement passes
	through a full-scale child to the content behind it, and the face is then
	placed at whatever the parent grew to. `Button` hugs its label after all.

	This is exactly what `tests/host/LayoutAutomaticSize.test.luau` had asserted
	for a milestone, during which it could not run -- and those assertions were
	rewritten to match the prediction before this case was answered. The suite was
	right and the reasoning that overruled it was wrong. Restored.

	WHAT SEPARATES THIS FROM THE 0.5 CASES IS NOT YET KNOWN. Four things differ at
	once, and any of them could be the rule:

	    scale magnitude   0.5 versus 1
	    a UIListLayout    both verified cases have one; this has none
	    grandchildren     this has content behind the face; they have none
	    axis              Y versus X

	`automatic_size_scale_child_without_a_layout` and
	`automatic_size_half_scale_child_with_content` separate the first two, which
	are the likeliest. Until they are answered, treating scale >= 1 as the
	discriminator is a fit to two points rather than a rule.
]]
return {
	name = "AutomaticSize with a FULL scale-sized child",
	provenance = "roblox",
	verifiedAgainst = "0.736.0.7361346",
	note = "ANSWERED, AGAINST THE PREDICTION: the engine returns 90. Full scale does NOT resolve "
		.. "against the available space -- measurement passes through the face to the content "
		.. "behind it, and the face is then placed at the size the parent grew to. Our "
		.. "implementation returns 200, which is a genuine conformance bug in Layout.luau's "
		.. "grow(). The rule that separates this from the 0.5 cases is not yet known; see the "
		.. "cases named below.",
	surface = { width = 200, height = 200 },

	tree = {
		class = "Frame",
		name = "Outer",
		props = {
			Size = { "UDim2", 0, 0, 0, 40 },
			AutomaticSize = { "Enum", "AutomaticSize", "X" },
		},
		children = {
			{
				class = "Frame",
				name = "Face",
				props = { Size = { "UDim2", 1, 0, 1, 0 } },
				children = {
					{ class = "Frame", name = "Inner", props = { Size = { "UDim2", 0, 90, 0, 40 } } },
				},
			},
		},
	},

	expect = {
		{ name = "Outer", x = 0, y = 0, w = 90, h = 40 },
		{ name = "Face", x = 0, y = 0, w = 90, h = 40 },
		{ name = "Inner", x = 0, y = 0, w = 90, h = 40 },
	},
}
