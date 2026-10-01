--!strict
--[[
	The face decides how wide a string is.

	The same string at the same TextSize, in three faces, measures three
	different widths. An implementation that draws every face in one font
	reports 1.0 for every pair, which is exactly what this rules out.

	RATIOS AGAINST ONE FACE, never widths. A measured width moves with the
	display configuration (LAYOUT.md section 7); a ratio of two strings measured
	on the same display does not. Source Sans Pro is the denominator because it
	is the narrowest of the three.

	Builder Sans is in its own case, `Builder Sans sets its own width`, because
	it may not be redistributed and an implementation can lack it while
	honouring every face here.

	The families are set through the legacy `Font` enum, which the engine
	resolves to `LegacyArial.json`, `Arimo.json` and `SourceSansPro.json`,
	Regular.
]]
local TEXT = "Hamburgefonts"

local function label(name: string, font: string, y: number): any
	return {
		class = "TextLabel",
		name = name,
		props = {
			Text = TEXT,
			Font = { "Enum", "Font", font },
			TextSize = 20,
			AutomaticSize = { "Enum", "AutomaticSize", "XY" },
			Size = { "UDim2", 0, 0, 0, 0 },
			Position = { "UDim2", 0, 0, 0, y },
		},
	}
end

return {
	name = "the font face sets the width of a string",
	provenance = "asserted",
	requires = { "FontFace" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: TextBounds.X of 187 "
		.. "(LegacyArial), 125 (Arimo) and 108 (SourceSansPro) for this string at TextSize 20, "
		.. "giving 1.731 and 1.157. Glyph ink on screen agreed within 2 px (184, 123, 107).",
	surface = { width = 400, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			label("Legacy", "Legacy", 0),
			label("Arimo", "Arimo", 50),
			label("SourceSans", "SourceSans", 100),
		},
	},

	expect = {},
	ratios = {
		{ of = "Legacy", to = "SourceSans", field = "w", expect = 1.731, tolerance = 0.04 },
		{ of = "Arimo", to = "SourceSans", field = "w", expect = 1.157, tolerance = 0.03 },
	},
}
