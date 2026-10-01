--!strict
--[[
	One line of a modern face is exactly TextSize tall, not 1.5 x TextSize.

	`one line of text is a fixed multiple of TextSize` measures 1.5, and is right
	for the face it uses: the default, LegacyArial. The multiple belongs to the
	FACE. Source Sans Pro, like every family that is not one of the Legacy ones,
	comes back at 1.0, so an implementation that hard codes 1.5 for every face is
	half again too tall the moment it honours a face.

	Same ruler as the Legacy case, at three sizes so a fixed offset cannot hide
	inside a ratio: each label is compared against a Frame exactly TextSize tall.

	The family is set through the legacy `Font` enum, which the engine resolves
	to the same FontFace (`SourceSansPro.json`, Regular) the probe set directly.
]]
local FONT = { "Enum", "Font", "SourceSans" }

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
	name = "one line of Source Sans Pro is one TextSize tall",
	provenance = "asserted",
	requires = { "FontFace" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: TextBounds.Y of 14, 20 "
		.. "and 32 for one line at TextSize 14, 20 and 32. That the AutomaticSize height equals "
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
		{ of = "Line14", to = "Ruler14", field = "h", expect = 1.0, tolerance = 0.02 },
		{ of = "Line20", to = "Ruler20", field = "h", expect = 1.0, tolerance = 0.02 },
		{ of = "Line32", to = "Ruler32", field = "h", expect = 1.0, tolerance = 0.02 },
	},
}
