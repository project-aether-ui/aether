--!strict
--[[
	The complement, and the half that catches an implementation which grows the
	height for the wrong reason.

	With `TextWrapped = false` a string too long for its width OVERFLOWS rather
	than breaking. The element stays one line tall however long the text is, and
	`AutomaticSize.Y` therefore reports the same height as a short string.

	Without this, an implementation that measured height from the string's
	unwrapped width -- height growing with length whether or not wrapping was
	asked for -- would pass the case beside this one.
]]
local LONG = "The quick brown fox jumps over the lazy dog and keeps going well past the edge"

return {
	name = "TextWrapped off keeps a long string on one line",
	provenance = "roblox",
	verifiedAgainst = "0.736.0.7361346",
	requires = { "TextWrapped" },
	note = "Engine: exactly 1.0000. The negative half of wrapping, and the case that catches an "
		.. "implementation growing height with text length regardless of TextWrapped.",
	surface = { width = 400, height = 300 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "Short",
				props = {
					Text = "One line",
					TextSize = 18,
					TextWrapped = false,
					AutomaticSize = { "Enum", "AutomaticSize", "Y" },
					Size = { "UDim2", 0, 200, 0, 0 },
				},
			},
			{
				class = "TextLabel",
				name = "Overflowing",
				props = {
					Text = LONG,
					TextSize = 18,
					TextWrapped = false,
					AutomaticSize = { "Enum", "AutomaticSize", "Y" },
					Size = { "UDim2", 0, 200, 0, 0 },
					Position = { "UDim2", 0, 0, 0, 120 },
				},
			},
		},
	},

	expect = {},
	ratios = {
		{ of = "Overflowing", to = "Short", field = "h", expect = 1.0, tolerance = 0.05 },
	},
}
