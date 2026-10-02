--!strict
--[[
	With RichText on, a label is measured from its content, not its markup.

	"<b>bold</b> plain" is seventeen characters of source and ten of content.
	An auto-sized label with RichText on is as wide as "bold plain" with the
	first word in bold; with RichText off it is as wide as the tags drawn
	literally, which is far wider.

	TWO MINIMUMS, because both widths belong to the face:

	- The literal label is at least 1.4 x the rich one. An implementation that
	  ignores RichText measures the tags in both and reports 1.0.
	- The rich label is at least 0.9 x a plain "bold plain". Bold is no narrower
	  than regular, so this only fails for an implementation that strips the
	  tags together with the text inside them.
]]
local MARKUP = "<b>bold</b> plain"

local function label(name: string, text: string, rich: boolean, y: number): any
	return {
		class = "TextLabel",
		name = name,
		props = {
			Text = text,
			RichText = rich,
			TextSize = 20,
			AutomaticSize = { "Enum", "AutomaticSize", "X" },
			Size = { "UDim2", 0, 0, 0, 30 },
			Position = { "UDim2", 0, 0, 0, y },
		},
	}
end

return {
	name = "RichText measures the content, not the markup",
	provenance = "roblox",
	verifiedAgainst = "0.741.19.7411056",
	requires = { "RichText" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: TextBounds.X of 116 for "
		.. "this markup with RichText on, at TextSize 20 in the default face, and ContentText "
		.. "\"bold plain\". The literal and plain widths were not probed.",
	surface = { width = 400, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			label("Rich", MARKUP, true, 0),
			label("Literal", MARKUP, false, 50),
			label("Plain", "bold plain", false, 100),
		},
	},

	expect = {},
	ratios = {
		{ of = "Literal", to = "Rich", field = "w", min = 1.4 },
		{ of = "Rich", to = "Plain", field = "w", min = 0.9 },
	},
}
