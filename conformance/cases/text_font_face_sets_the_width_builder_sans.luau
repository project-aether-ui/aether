--!strict
--[[
	The Builder Sans half of `the font face sets the width of a string`.

	Separate, and gated on its own name, because Builder Sans may not be
	redistributed. An implementation that honours every open face but has no
	Builder Sans to draw reports this unsupported instead of failing the open
	faces' case with it.

	Builder Sans is about a tenth wider than Source Sans Pro for this string; an
	implementation drawing both in one font reports 1.0.

	The families are set through the legacy `Font` enum, which the engine
	resolves to `BuilderSans.json` and `SourceSansPro.json`, Regular.
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
	name = "Builder Sans sets its own width",
	provenance = "roblox",
	verifiedAgainst = "0.741.19.7411056",
	requires = { "FontFace", "FontFace.BuilderSans" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: TextBounds.X of 120 "
		.. "(BuilderSans) and 108 (SourceSansPro) for this string at TextSize 20, giving 1.111. "
		.. "Glyph ink on screen agreed within 2 px (118 and 107).",
	surface = { width = 400, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			label("Builder", "BuilderSans", 0),
			label("SourceSans", "SourceSans", 50),
		},
	},

	expect = {},
	ratios = {
		{ of = "Builder", to = "SourceSans", field = "w", expect = 1.111, tolerance = 0.03 },
	},
}
