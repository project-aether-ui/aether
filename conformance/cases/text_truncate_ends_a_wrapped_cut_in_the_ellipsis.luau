--!strict
--[[
	A wrapped label with TextTruncate AtEnd whose text needs more lines than
	fit ends its last drawn line in the ellipsis.

	"Wide Wide Wide" at TextSize 20 in a 110 by 40 box wraps one word to a
	line, and only the first of the three lines fits. That line is drawn as
	"Wide" and the ellipsis, U+2026, which fit the box together. So its
	TextBounds.X is the width of "Wide" followed by U+2026, measured in the
	same face by an AutomaticSize label holding exactly that string. A label
	that drew the line without the ellipsis would read about 0.7 of it.

	RATIOS, never widths. Both labels are measured in the same face, so the
	ratio holds whatever that face's advances are. ContentText is the whole
	string and TextFits is false, as for a one line cut.
]]
local LONG = "Wide Wide Wide"

return {
	name = "TextTruncate ends a wrapped cut in the ellipsis",
	provenance = "asserted",
	requires = { "TextTruncate", "TextWrapped", "TextBounds", "TextFits", "ContentText" },
	note = "From a command-bar probe on 2026-10-02 against 0.741.19.7411056: a 200 by 36 label "
		.. "at TextSize 14 holding a long sentence was drawn as two lines, the second ending "
		.. "\"keeps running\" and U+2026, with TextFits false and ContentText the whole string. "
		.. "This case restates that with a string whose cut can be compared to a reference label.",
	surface = { width = 400, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "Cut",
				props = {
					Text = LONG,
					TextSize = 20,
					TextWrapped = true,
					TextTruncate = { "Enum", "TextTruncate", "AtEnd" },
					TextXAlignment = { "Enum", "TextXAlignment", "Left" },
					TextYAlignment = { "Enum", "TextYAlignment", "Top" },
					Size = { "UDim2", 0, 110, 0, 40 },
				},
			},
			{
				class = "TextLabel",
				name = "Reference",
				props = {
					Text = "Wide\u{2026}",
					TextSize = 20,
					AutomaticSize = { "Enum", "AutomaticSize", "XY" },
					Size = { "UDim2", 0, 0, 0, 0 },
					Position = { "UDim2", 0, 0, 0, 100 },
				},
			},
		},
	},

	expect = {
		{ name = "Cut", textFits = false, contentText = LONG },
	},
	ratios = {
		{ of = "Cut", to = "Reference", field = "textBoundsX", expect = 1.0, tolerance = 0.03 },
		--- One line drawn: as tall as the one line reference.
		{ of = "Cut", to = "Reference", field = "textBoundsY", expect = 1.0, tolerance = 0.02 },
	},
}
