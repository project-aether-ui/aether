--!strict
--[[
	LineHeight spaces the lines of a block; it does not pad a single line.

	Two claims, each asserted as a ratio against the same text at LineHeight 1:

	- ONE LINE is the same height at LineHeight 2. The extra space goes
	  between lines, so a block of one line has nowhere to put it.
	- THREE LINES grow by at least half. "one two three four five six" wraps
	  to three lines in 120 px at TextSize 20. Whether LineHeight 2 doubles
	  every line or only the gaps after the first is not settled, and the two
	  give 2.0 and 1.67, so the case asks for at least 1.5. An implementation
	  ignoring LineHeight reports 1.0.
]]
local LONG = "one two three four five six"

local function label(name: string, text: string, lineHeight: number, y: number): any
	return {
		class = "TextLabel",
		name = name,
		props = {
			Text = text,
			TextSize = 20,
			LineHeight = lineHeight,
			TextWrapped = true,
			AutomaticSize = { "Enum", "AutomaticSize", "Y" },
			Size = { "UDim2", 0, 120, 0, 0 },
			Position = { "UDim2", 0, 0, 0, y },
		},
	}
end

return {
	name = "LineHeight spaces lines and leaves one line alone",
	provenance = "asserted",
	requires = { "LineHeight", "TextWrapped" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: the long string in a "
		.. "fixed 120 x 64 label read TextBounds 117 x 60 at LineHeight 1 (two lines fit) and "
		.. "117 x 30 at LineHeight 2 (one line fits), so a first line is 30 tall either way.",
	surface = { width = 400, height = 400 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			label("OneAt1", "one", 1, 0),
			label("OneAt2", "one", 2, 50),
			label("ThreeAt1", LONG, 1, 120),
			label("ThreeAt2", LONG, 2, 240),
		},
	},

	expect = {},
	ratios = {
		{ of = "OneAt2", to = "OneAt1", field = "h", expect = 1.0, tolerance = 0.02 },
		{ of = "ThreeAt2", to = "ThreeAt1", field = "h", min = 1.5 },
	},
}
