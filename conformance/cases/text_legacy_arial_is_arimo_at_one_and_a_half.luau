--!strict
--[[
	LegacyArial is Arimo, drawn at one and a half times the TextSize.

	Its family file names "Arimo (Legacy)" and points at the same Arimo files as
	the Arimo family. What makes it Legacy is the scale: the same string is 1.5 x
	as wide and 1.5 x as tall. That is why the default face's line is 1.5 x
	TextSize while every modern face's is 1.0 x, and it is the rule an
	implementation needs in order to draw the default face at all: draw Arimo,
	at 1.5 x.

	A RATIO BETWEEN TWO FACES, never a width. A measured width moves with the
	display configuration (LAYOUT.md section 7), and a ratio of two strings
	measured on the same display cancels that out. An implementation that ignores
	the face reports 1.0 on both axes.

	The families are set through the legacy `Font` enum, which the engine
	resolves to `LegacyArial.json` and `Arimo.json`, Regular.
]]
local TEXT = "Hamburgefonts"

return {
	name = "LegacyArial is Arimo at one and a half times the size",
	provenance = "asserted",
	requires = { "FontFace" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: TextBounds 187 x 30 for "
		.. "LegacyArial and 125 x 20 for Arimo at TextSize 20, a width ratio of 1.496. Glyph ink "
		.. "on screen agreed within 2 px (184 and 123).",
	surface = { width = 400, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "Legacy",
				props = {
					Text = TEXT,
					Font = { "Enum", "Font", "Legacy" },
					TextSize = 20,
					AutomaticSize = { "Enum", "AutomaticSize", "XY" },
					Size = { "UDim2", 0, 0, 0, 0 },
				},
			},
			{
				class = "TextLabel",
				name = "Arimo",
				props = {
					Text = TEXT,
					Font = { "Enum", "Font", "Arimo" },
					TextSize = 20,
					AutomaticSize = { "Enum", "AutomaticSize", "XY" },
					Size = { "UDim2", 0, 0, 0, 0 },
					Position = { "UDim2", 0, 0, 0, 60 },
				},
			},
		},
	},

	expect = {},
	ratios = {
		--- Slack for whole-pixel rounding of thirteen advances at two scales,
		--- and still nowhere near the 1.0 of an implementation ignoring the face.
		{ of = "Legacy", to = "Arimo", field = "w", expect = 1.5, tolerance = 0.03 },
		{ of = "Legacy", to = "Arimo", field = "h", expect = 1.5, tolerance = 0.02 },
	},
}
