--!strict
--[[
	Two strings of the same LENGTH measure differently, because an advance width
	belongs to a glyph rather than to a character count.

	This is the property that rules out the cheapest possible implementation.
	`#text * factor` reports a plausible width for every string while being wrong
	about all of them, and it passes any test that only checks a width is
	non-zero. "WW" and "ll" are two characters each and are nowhere near the same
	width in any real face.

	THE RATIO IS PROVIDER-SPECIFIC and the measured spread proves it: Roblox
	reports 4.4286 for four W against four l, and Aether's off-engine table
	reports about 3.39. Both are correct for their own face.

	So the case asserts a MINIMUM rather than a value. Its claim is "not per
	character", and any per-character implementation reports exactly 1.0. A
	tolerance fitted around either observed number would make the case assert a
	font instead of asserting the rule, and would fail the other host for being
	right.
]]
return {
	name = "text measurement is per glyph, not per character",
	provenance = "roblox",
	verifiedAgainst = "0.736.0.7361346",
	note = "Engine 4.4286, Aether about 3.39. Both conform: the rule is that measurement is per "
		.. "glyph, and a per-character implementation would report exactly 1.0.",
	surface = { width = 400, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "Narrow",
				props = {
					Text = "llll",
					TextSize = 24,
					AutomaticSize = { "Enum", "AutomaticSize", "X" },
					Size = { "UDim2", 0, 0, 0, 30 },
				},
			},
			{
				class = "TextLabel",
				name = "Wide",
				props = {
					Text = "WWWW",
					TextSize = 24,
					AutomaticSize = { "Enum", "AutomaticSize", "X" },
					Size = { "UDim2", 0, 0, 0, 30 },
					Position = { "UDim2", 0, 0, 0, 40 },
				},
			},
		},
	},

	expect = {},
	ratios = {
		--- Two, comfortably below both observed values and comfortably above the
		--- 1.0 a per-character implementation reports. The bound expresses the
		--- claim; it is not fitted to either font.
		{ of = "Wide", to = "Narrow", field = "w", min = 2.0 },
	},
}
