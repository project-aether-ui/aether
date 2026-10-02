--!strict
--[[
	The Legacy half of the line height rule, with the face named.

	`one line of text is a fixed multiple of TextSize` measures 1.5 against the
	default face, which happens to be LegacyArial. This names the face, so the
	1.5 stays attached to it when the default is not what is being measured, and
	checks the multiple at three sizes rather than one.

	LegacyArial draws Arimo's glyphs at 1.5 x TextSize: its "Hamburgefonts" is
	1.5 x Arimo's (see `LegacyArial is Arimo at one and a half times the size`).
	So the 1.5 here is the face's scale, not extra space around a line.

	The family is set through the legacy `Font` enum, which the engine resolves
	to the same FontFace (`LegacyArial.json`, Regular) the probe set directly.
]]
local FONT = { "Enum", "Font", "Legacy" }

local function label(name: string, size: number, y: number): any
	return {
		class = "TextLabel",
		name = name,
		props = {
			Text = "Ay",
			Font = FONT,
			TextSize = size,
			AutomaticSize = { "Enum", "AutomaticSize", "Y" },
			Size = { "UDim2", 0, 200, 0, 0 },
			Position = { "UDim2", 0, 0, 0, y },
		},
	}
end

local function ruler(name: string, size: number, y: number): any
	return {
		class = "Frame",
		name = name,
		props = {
			Size = { "UDim2", 0, 40, 0, size },
			Position = { "UDim2", 0, 220, 0, y },
		},
	}
end

return {
	name = "one line of LegacyArial is one and a half TextSize tall",
	provenance = "roblox",
	verifiedAgainst = "0.741.19.7411056",
	requires = { "FontFace" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: TextBounds.Y of 21, 30 "
		.. "and 48 for one line at TextSize 14, 20 and 32. That the AutomaticSize height equals "
		.. "TextBounds.Y is the belief this case checks.",
	surface = { width = 400, height = 300 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			ruler("Ruler14", 14, 0),
			label("Line14", 14, 0),
			ruler("Ruler20", 20, 60),
			label("Line20", 20, 60),
			ruler("Ruler32", 32, 120),
			label("Line32", 32, 120),
		},
	},

	expect = {},
	ratios = {
		{ of = "Line14", to = "Ruler14", field = "h", expect = 1.5, tolerance = 0.02 },
		{ of = "Line20", to = "Ruler20", field = "h", expect = 1.5, tolerance = 0.02 },
		{ of = "Line32", to = "Ruler32", field = "h", expect = 1.5, tolerance = 0.02 },
	},
}
