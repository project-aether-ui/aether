--!strict
--[[
	The Builder Sans half of `one line of Source Sans Pro is one TextSize tall`,
	and the face Roblox's own UI is set in.

	Separate from the Source Sans Pro case, and gated on its own name, because
	Builder Sans may not be redistributed. An implementation can honour every
	open face and still have no Builder Sans to draw; that is a missing face,
	not a wrong line height, and it should report as unsupported rather than
	fail the open faces' case with it.

	The family is set through the legacy `Font` enum, which the engine resolves
	to the same FontFace (`BuilderSans.json`, Regular) the probe set directly.
]]
local FONT = { "Enum", "Font", "BuilderSans" }

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
	name = "one line of Builder Sans is one TextSize tall",
	provenance = "asserted",
	requires = { "FontFace", "FontFace.BuilderSans" },
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
