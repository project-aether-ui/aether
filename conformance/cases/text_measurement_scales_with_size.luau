--!strict
--[[
	Text measurement is a HOST SERVICE, so this case asserts a ratio rather than a
	width.

	Roblox answers with the engine's own text bounds. Off-engine Aether answers
	from a per-glyph advance table for a nominal humanist sans, the web host from
	a browser cache, and Dew from real font metrics through skrifa. Four
	providers, four answers, and a case claiming "this string is 71.4 pixels wide"
	would be describing one of them.

	What every correct provider agrees on is that measurement is LINEAR IN
	TEXTSIZE. Doubling the size doubles the advance, because an advance width is a
	fraction of the em square and the em square is the size.
]]
return {
	name = "text measurement is linear in TextSize",
	provenance = "asserted",
	note = "A relationship rather than a number, because the absolute width is a property of "
		.. "whichever provider answered. Verify in Studio: the engine should agree, and if it does "
		.. "not, linearity is not something an implementation may assume.",
	surface = { width = 400, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "Small",
				props = {
					Text = "Hello world",
					TextSize = 14,
					AutomaticSize = { "Enum", "AutomaticSize", "XY" },
					Size = { "UDim2", 0, 0, 0, 0 },
				},
			},
			{
				class = "TextLabel",
				name = "Big",
				props = {
					Text = "Hello world",
					TextSize = 28,
					AutomaticSize = { "Enum", "AutomaticSize", "XY" },
					Size = { "UDim2", 0, 0, 0, 0 },
					Position = { "UDim2", 0, 0, 0, 60 },
				},
			},
		},
	},

	expect = {},
	ratios = {
		{ of = "Big", to = "Small", field = "w", expect = 2.0, tolerance = 0.05 },
		{ of = "Big", to = "Small", field = "h", expect = 2.0, tolerance = 0.05 },
	},
}
