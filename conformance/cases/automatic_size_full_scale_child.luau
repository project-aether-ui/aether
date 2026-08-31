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

	The second is what `tests/host/LayoutAutomaticSize.test.luau` asserted for a
	milestone, during which it could not run. It is not obviously wrong: an engine
	could reasonably treat a child that asks for ALL of an axis differently from
	one asking for half of it, since the former is the degenerate case of the
	cycle rather than a partial constraint on it.

	Nothing here relies on the answer yet -- the implementation follows the rule,
	which is the conservative choice because it is the one two verified cases
	support. This case exists so that a Studio pass settles it rather than a user
	noticing months later that every automatically sized button is full width.
]]
return {
	name = "AutomaticSize with a FULL scale-sized child",
	provenance = "asserted",
	note = "Predicts the verified rule generalises to scale 1. If the engine returns 90, full "
		.. "scale is a special case and Layout.luau's grow() needs to say so.",
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
		{ name = "Outer", x = 0, y = 0, w = 200, h = 40 },
		{ name = "Face", x = 0, y = 0, w = 200, h = 40 },
		{ name = "Inner", x = 0, y = 0, w = 90, h = 40 },
	},
}
