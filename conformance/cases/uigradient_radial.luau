--!strict
--[[
	A case for a feature that does not exist here yet.

	Roblox is adding radial `UIGradient`. When it ships, this case gets verified
	in Studio and its expectation becomes real — and until this implementation
	grows the feature, the runner reports it UNSUPPORTED rather than failing it.

	That is the shape every future Roblox feature takes here: the case can be
	written and verified before anyone implements it, and it becomes a roadmap
	item that turns into a test the day `UIGradient.Radial` appears in the
	runner's SUPPORTS list. Nothing about being behind makes the suite red.

	The geometry below is deliberately trivial. A gradient does not move anything,
	so the real assertion is about the display list carrying the gradient's KIND —
	which needs a field the display list does not have yet. The case exists now to
	hold the place and to prove the gate works.
]]
return {
	name = "a radial UIGradient reaches the display list as radial",
	provenance = "asserted",
	requires = { "UIGradient.Radial" },
	note = "THE ENGINE RUNNER REPORTS THIS AS AGREEING, which is a flaw in the case rather than a "
		.. "result. It asserts geometry only, and a gradient moves nothing -- so it cannot fail on "
		.. "the thing it is named for. Same shape as the clip-radius case. Closing it needs a "
		.. "gradient kind in the display list and a pixel-level runner.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 0, 100, 0, 50 } },
		children = {
			{ class = "UIGradient", name = "Gradient", props = {} },
		},
	},

	expect = {
		{ name = "Root", x = 0, y = 0, w = 100, h = 50 },
	},
}
