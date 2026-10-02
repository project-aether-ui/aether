--!strict
--[[
	TextTruncate shortens what is drawn, and TextBounds with it, while
	ContentText keeps the whole string.

	"A long label that cannot fit" in a 100 px box with TextTruncate AtEnd is
	drawn as a prefix and an ellipsis. Its TextBounds.X is the width of that,
	so it is no wider than the box, and well short of the same string measured
	whole. TextFits is false: the string did not fit, which is why it was cut.
	ContentText is the string as written, not the cut one.

	RATIOS, never widths. Where the cut falls belongs to the face, so the case
	asserts only "inside the box" and "much shorter than the whole string".
]]
local LONG = "A long label that cannot fit"

return {
	name = "TextTruncate shortens the bounds and keeps the content",
	provenance = "roblox",
	verifiedAgainst = "0.741.19.7411056",
	requires = { "TextTruncate", "TextBounds", "TextFits", "ContentText" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: TextBounds 89 x 30 in a "
		.. "100 x 64 box, TextFits false, ContentText the whole string, at TextSize 20 in the default "
		.. "face. The screenshot showed \"A lon...\". The whole string's width was not probed.",
	surface = { width = 500, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "Truncated",
				props = {
					Text = LONG,
					TextSize = 20,
					TextTruncate = { "Enum", "TextTruncate", "AtEnd" },
					Size = { "UDim2", 0, 100, 0, 64 },
				},
			},
			{
				class = "TextLabel",
				name = "Whole",
				props = {
					Text = LONG,
					TextSize = 20,
					AutomaticSize = { "Enum", "AutomaticSize", "X" },
					Size = { "UDim2", 0, 0, 0, 30 },
					Position = { "UDim2", 0, 0, 0, 100 },
				},
			},
		},
	},

	expect = {
		{ name = "Truncated", textFits = false, contentText = LONG },
		{ name = "Whole", textFits = true, contentText = LONG },
	},
	ratios = {
		{ of = "Truncated", to = "Truncated", field = "textBoundsX", toField = "w", max = 1.0 },
		--- About 0.3 in the engine's default face. Half is far from both that
		--- and the 1.0 of an implementation that ignores TextTruncate.
		{ of = "Truncated", to = "Whole", field = "textBoundsX", max = 0.5 },
	},
}
