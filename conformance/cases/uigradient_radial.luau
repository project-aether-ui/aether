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
	note = "A radial UIGradient renders as a radial ramp centred on the container, rather than a linear "
		.. "ramp or flat fill. Centre probes red (#ff0000) and corners probe blue (#0000ff).",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 0, 100, 0, 50 } },
		children = {
			{
				class = "UIGradient",
				name = "Gradient",
				props = {
					Type = { "Enum", "GradientType", "Radial" },
					Color = { "ColorSequence", { "Color3", 1, 0, 0 }, { "Color3", 0, 0, 1 } },
				},
			},
		},
	},

	expect = {
		{ name = "Root", x = 0, y = 0, w = 100, h = 50 },
	},

	pixels = {
		--- Centre of the 100x50 frame is red (t = 0 of the radial ramp).
		--- Half-pixel rasterizer center sampling (50.5, 25.5) gives small delta from pure red.
		{ x = 50, y = 25, color = "#ff0000", tolerance = 8 },
		--- Corners are blue (t = 1 of the radial ramp).
		{ x = 2, y = 2, color = "#0000ff" },
		{ x = 98, y = 48, color = "#0000ff" },
	},
}
