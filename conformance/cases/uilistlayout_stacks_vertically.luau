--!strict
--[[
	`UIListLayout` is the first case where the PARENT rearranges its children,
	rather than each child positioning itself. A child's own `Position` is
	ignored; the layout assigns one.

	This is the boundary between "resolve a UDim2" and "run a layout algorithm",
	and it is where an independent implementation starts genuinely guessing at
	Roblox's behaviour rather than doing arithmetic. First candidate for
	verification in Studio.
]]
return {
	name = "UIListLayout stacks children and ignores their Position",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.728",
	note = "VERIFIED IN STUDIO: the engine produces exactly this. Our implementation does not -- "
		.. "Layout allocates slot 0 to First and First then ignores it, keeping its own Position, "
		.. "while Second and Third take slots 1 and 2 correctly. So the stacking works and the "
		.. "override does not. This is a genuine conformance bug in Layout.luau.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "List",
		props = { Size = { "UDim2", 0, 100, 0, 90 } },
		children = {
			{ class = "UIListLayout", name = "Layout", props = { Padding = { "UDim", 0, 4 } } },
			{
				class = "Frame",
				name = "First",
				-- Deliberately set, and deliberately expected to be ignored.
				props = { Position = { "UDim2", 0, 50, 0, 50 }, Size = { "UDim2", 1, 0, 0, 20 } },
			},
			{ class = "Frame", name = "Second", props = { Size = { "UDim2", 1, 0, 0, 20 } } },
			{ class = "Frame", name = "Third", props = { Size = { "UDim2", 1, 0, 0, 20 } } },
		},
	},

	expect = {
		{ name = "First", x = 0, y = 0, w = 100, h = 20 },
		{ name = "Second", x = 0, y = 24, w = 100, h = 20 },
		{ name = "Third", x = 0, y = 48, w = 100, h = 20 },
	},
}
