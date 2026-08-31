--!strict
--[[
	How tall is one line of text, as a multiple of `TextSize`?

	Off-engine Aether answers 1.2, a constant written into `host/Text.luau` and
	relied on by every `AutomaticSize.Y` on a `TextLabel`. Whether Roblox agrees
	has never been checked, and it is exactly the kind of number that is wrong by
	a few percent everywhere without anyone noticing.

	MEASURED AGAINST A RULER. A ratio between two text elements cancels the line
	height out, so this compares an auto-sized label against a Frame of a fixed
	height equal to its `TextSize`. The frame is 20 tall because the text is 20
	tall; whatever multiple the label comes back as is the line height.
]]
return {
	name = "one line of text is a fixed multiple of TextSize",
	provenance = "roblox",
	verifiedAgainst = "0.736.0.7361346",
	note = "ENGINE: 1.5000 exactly. Aether used 1.2, so every auto-sized TextLabel was 20 percent "
		.. "short. What is measured is the RESOLVED HEIGHT of a single-line auto-sized label as a "
		.. "multiple of TextSize; whether that is purely line height or includes something else is "
		.. "not established by this case.",
	surface = { width = 300, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			--- THE RULER. Exactly as tall as the text is nominally sized, so the
			--- ratio below reads directly as a multiple of TextSize.
			{
				class = "Frame",
				name = "Ruler",
				props = { Size = { "UDim2", 0, 40, 0, 20 } },
			},
			{
				class = "TextLabel",
				name = "OneLine",
				props = {
					Text = "Ay",
					TextSize = 20,
					AutomaticSize = { "Enum", "AutomaticSize", "Y" },
					Size = { "UDim2", 0, 200, 0, 0 },
					Position = { "UDim2", 0, 0, 0, 40 },
				},
			},
		},
	},

	expect = {},
	ratios = {
		{ of = "OneLine", to = "Ruler", field = "h", expect = 1.5, tolerance = 0.02 },
	},
}
