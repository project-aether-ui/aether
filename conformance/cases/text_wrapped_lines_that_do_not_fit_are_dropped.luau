--!strict
--[[
	A wrapped label of fixed height draws only the lines that fit, and its
	TextBounds counts only those.

	"one two three four five six" wraps to three lines in 120 px at TextSize 20.
	In a box 64 tall only two lines of 30 fit, so the third is not drawn at all:
	not clipped halfway, not overflowing the box. TextBounds.Y is two lines and
	TextFits is false. Auto-sized to the same width, all three are drawn and
	TextFits is true.

	LINES ARE COUNTED AGAINST A ONE-LINE LABEL, never in pixels: TextBounds.Y of
	"one" is one line in this face, so the ratio is the number of lines drawn.
	Where the breaks fall is not asserted. Two lines fit in 64 whatever the
	breaks are, and the auto-sized label draws more lines than the clipped one
	whatever its count.

	"the quick brown fox jumps over" in 110 x 64 is the same rule with longer
	words, and its TextBounds.X is no wider than its box.
]]
local LONG = "one two three four five six"

return {
	name = "a wrapped label drops the lines that do not fit",
	provenance = "roblox",
	verifiedAgainst = "0.741.19.7411056",
	requires = { "TextBounds", "TextFits", "TextWrapped" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: TextBounds 117 x 60 and "
		.. "TextFits false for the long string in 120 x 64, and 110 x 60, TextFits false, for "
		.. "\"the quick brown fox jumps over\" in 110 x 64, both at TextSize 20 in the default face. "
		.. "The screenshots showed two lines drawn in each and nothing below.",
	surface = { width = 400, height = 400 },

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
				name = "Clipped",
				props = {
					Text = LONG,
					TextSize = 20,
					TextWrapped = true,
					TextYAlignment = { "Enum", "TextYAlignment", "Top" },
					Size = { "UDim2", 0, 120, 0, 64 },
					Position = { "UDim2", 0, 0, 0, 50 },
				},
			},
			{
				class = "TextLabel",
				name = "Whole",
				props = {
					Text = LONG,
					TextSize = 20,
					TextWrapped = true,
					TextYAlignment = { "Enum", "TextYAlignment", "Top" },
					AutomaticSize = { "Enum", "AutomaticSize", "Y" },
					Size = { "UDim2", 0, 120, 0, 0 },
					Position = { "UDim2", 0, 200, 0, 50 },
				},
			},
			{
				class = "TextLabel",
				name = "Breaks",
				props = {
					Text = "the quick brown fox jumps over",
					TextSize = 20,
					TextWrapped = true,
					TextYAlignment = { "Enum", "TextYAlignment", "Top" },
					Size = { "UDim2", 0, 110, 0, 64 },
					Position = { "UDim2", 0, 0, 0, 200 },
				},
			},
		},
	},

	expect = {
		{ name = "OneLine", textFits = true },
		{ name = "Clipped", textFits = false },
		{ name = "Whole", textFits = true },
		{ name = "Breaks", textFits = false },
	},
	ratios = {
		--- Two lines drawn, the third dropped.
		{ of = "Clipped", to = "OneLine", field = "textBoundsY", expect = 2.0, tolerance = 0.02 },
		--- And what is drawn stays inside the box.
		{ of = "Clipped", to = "Clipped", field = "textBoundsY", toField = "h", max = 1.0 },
		--- With room, every line is drawn: a whole number of them, more than
		--- the clipped label shows.
		{ of = "Whole", to = "OneLine", field = "textBoundsY", integral = true },
		{ of = "Whole", to = "Clipped", field = "textBoundsY", min = 1.4 },
		{ of = "Breaks", to = "OneLine", field = "textBoundsY", expect = 2.0, tolerance = 0.02 },
		{ of = "Breaks", to = "Breaks", field = "textBoundsX", toField = "w", max = 1.0 },
	},
}
