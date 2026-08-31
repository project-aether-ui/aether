--!strict
--[[
	Two strings of the same LENGTH measure differently, because an advance width
	belongs to a glyph rather than to a character count.

	This is the property that rules out the cheapest possible implementation.
	`#text * factor` reports a plausible width for every string while being wrong
	about all of them, and it passes any test that only checks a width is
	non-zero. "WW" and "ll" are two characters each and are nowhere near the same
	width in any real face.

	The RATIO is provider-specific -- how much wider W is than l depends on the
	font -- so this asserts only that the wide pair is substantially wider, with
	tolerance wide enough to hold for any humanist sans.
]]
return {
	name = "text measurement is per glyph, not per character",
	provenance = "asserted",
	note = "The engine runner reported AGREES on this vacuously, before it understood ratios. Re-run "
		.. "once it checks them; the observed ratio it prints is also how this tolerance gets "
		.. "tightened from 3.2 +/- 1.2 to something that means anything.",
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
		--- Four W against four l. In any humanist sans this is somewhere near
		--- three; the tolerance covers everything from a condensed face to a wide
		--- one without admitting a per-character implementation, which would
		--- report exactly 1.0.
		{ of = "Wide", to = "Narrow", field = "w", expect = 3.2, tolerance = 1.2 },
	},
}
