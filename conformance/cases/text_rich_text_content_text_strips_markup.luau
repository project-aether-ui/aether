--!strict
--[[
	ContentText is the text a label shows: with RichText on, the markup is
	removed; with it off, the string is shown as written, tags and all.

	This is the string an implementation measures and draws, so getting it
	wrong makes every RichText width wrong too.
]]
local MARKUP = "<b>bold</b> plain"

return {
	name = "ContentText strips RichText markup",
	provenance = "roblox",
	verifiedAgainst = "0.741.19.7411056",
	requires = { "RichText", "ContentText" },
	note = "From a command-bar probe on 2026-10-01, not yet from this runner: ContentText \"bold "
		.. "plain\" for this markup with RichText on. The RichText off half follows from the "
		.. "property's definition and was not probed.",
	surface = { width = 400, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "Rich",
				props = {
					Text = MARKUP,
					RichText = true,
					TextSize = 20,
					AutomaticSize = { "Enum", "AutomaticSize", "X" },
					Size = { "UDim2", 0, 0, 0, 30 },
				},
			},
			{
				class = "TextLabel",
				name = "Literal",
				props = {
					Text = MARKUP,
					RichText = false,
					TextSize = 20,
					AutomaticSize = { "Enum", "AutomaticSize", "X" },
					Size = { "UDim2", 0, 0, 0, 30 },
					Position = { "UDim2", 0, 0, 0, 50 },
				},
			},
		},
	},

	expect = {
		{ name = "Rich", contentText = "bold plain" },
		{ name = "Literal", contentText = MARKUP },
	},
}
