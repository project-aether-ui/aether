--!strict
--[[
	LineHeight decides how many wrapped lines fit, and the rest are dropped.

	The same 120 x 64 box that shows two lines of "one two three four five six"
	at LineHeight 1 (`a wrapped label drops the lines that do not fit`) shows
	one at LineHeight 2: the second line now starts too low to fit. TextBounds
	counts the one line drawn, and TextFits is false.

	One line, counted against a one-line label at LineHeight 1, so the ratio
	is the number of lines drawn and no pixel value is asserted.
]]
return {
	name = "LineHeight 2 leaves one wrapped line where two fitted",
	provenance = "roblox",
	verifiedAgainst = "0.741.19.7411056",
	requires = { "LineHeight", "TextBounds", "TextFits", "TextWrapped" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: TextBounds 117 x 30 and "
		.. "TextFits false at LineHeight 2 in 120 x 64, TextSize 20, default face. The screenshot "
		.. "showed one line.",
	surface = { width = 400, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "OneLine",
				props = {
					Text = "one",
					TextSize = 20,
					AutomaticSize = { "Enum", "AutomaticSize", "XY" },
					Size = { "UDim2", 0, 0, 0, 0 },
				},
			},
			{
				class = "TextLabel",
				name = "Spaced",
				props = {
					Text = "one two three four five six",
					TextSize = 20,
					LineHeight = 2,
					TextWrapped = true,
					TextYAlignment = { "Enum", "TextYAlignment", "Top" },
					Size = { "UDim2", 0, 120, 0, 64 },
					Position = { "UDim2", 0, 0, 0, 50 },
				},
			},
		},
	},

	expect = {
		{ name = "Spaced", textFits = false },
	},
	ratios = {
		{ of = "Spaced", to = "OneLine", field = "textBoundsY", expect = 1.0, tolerance = 0.02 },
		{ of = "Spaced", to = "Spaced", field = "textBoundsX", toField = "w", max = 1.0 },
	},
}
