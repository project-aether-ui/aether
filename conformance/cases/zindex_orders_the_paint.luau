--!strict
--[[
	Paint order is ZIndex, then depth, then declaration order.

	A PROPERTY OF THE LIST, not of any node in it, which is why this is the only
	case that asserts a sequence. `Layout.Solve` returns a flat list in the order
	a renderer should walk it, back to front.

	CANNOT BE VERIFIED AGAINST THE ENGINE. Roblox exposes no display list and no
	painted sequence: two overlapping frames look different but report identical
	geometry. So this case is `reference` -- it pins what this implementation does
	and makes no claim about what Roblox does -- and the engine runner reports it
	as unobservable rather than agreeing with it.

	It joins the clip radius and the gradient kind as things a geometric runner
	cannot see. All three need the same missing instrument, which is a runner that
	compares rendered pixels.
]]
return {
	name = "ZIndex orders the paint, then depth, then declaration",
	provenance = "reference",
	note = "Unverifiable against the engine. Three gaps now wait on a pixel-level runner: this, the "
		.. "clip radius, and the gradient kind.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 }, ZIndex = 1 },
		children = {
			--- Declared last, painted first: a lower ZIndex outranks declaration.
			{
				class = "Frame",
				name = "Behind",
				props = { Size = { "UDim2", 0, 80, 0, 80 }, ZIndex = 1 },
			},
			{
				class = "Frame",
				name = "Front",
				props = { Size = { "UDim2", 0, 80, 0, 80 }, ZIndex = 5 },
			},
			{
				class = "Frame",
				name = "Middle",
				props = { Size = { "UDim2", 0, 80, 0, 80 }, ZIndex = 3 },
			},
		},
	},

	expect = {},
	--- Back to front. Declaration order is Behind, Front, Middle; ZIndex reorders
	--- them, so a run that returns declaration order has not sorted at all.
	order = { "Root", "Behind", "Middle", "Front" },
}
