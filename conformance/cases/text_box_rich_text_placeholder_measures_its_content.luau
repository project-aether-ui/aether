--!strict
--[[
	A RichText TextBox with empty Text measures its placeholder's content, not
	its markup. This is where Dew parts from the engine on purpose.

	"<b>Bold</b> hint" as the PlaceholderText of a TextBox with RichText on is
	measured, here, as "Bold hint" would be: its TextBounds.X is about that of
	a plain label reading "Bold hint" in the same face and size. The engine does
	not apply markup to a placeholder. It draws the tags as written and reports
	TextBounds of 140 x 20 with Enum.Font.Arial at TextSize 20, about twice the
	stripped width, so this case is `divergent` and the engine disagrees with it.

	A RANGE, not 1.0 exactly. A host that draws the bold word in a bold face
	measures a little wider than the plain reference, which is still the
	behaviour this case records. The engine's 2.0 is far outside it.
]]
local FONT = { "Enum", "Font", "Arial" }

return {
	name = "a RichText placeholder measures its content, not its markup",
	provenance = "divergent",
	requires = { "RichText", "TextBounds", "PlaceholderText" },
	note = "Dew chose this deliberately. Measured in Studio, the engine draws a placeholder's markup "
		.. "as written: TextBounds 140 x 20 for this PlaceholderText with Enum.Font.Arial (LegacyArial) "
		.. "at TextSize 20, about 2.0 times the width of the stripped text, where this case expects "
		.. "about 1.0.",
	surface = { width = 320, height = 120 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextBox",
				name = "Placeholder",
				props = {
					Text = "",
					PlaceholderText = "<b>Bold</b> hint",
					RichText = true,
					ClearTextOnFocus = false,
					Font = FONT,
					TextSize = 20,
					TextXAlignment = { "Enum", "TextXAlignment", "Left" },
					Size = { "UDim2", 0, 260, 0, 30 },
					Position = { "UDim2", 0, 20, 0, 10 },
				},
			},
			{
				class = "TextLabel",
				name = "Reference",
				props = {
					Text = "Bold hint",
					Font = FONT,
					TextSize = 20,
					TextXAlignment = { "Enum", "TextXAlignment", "Left" },
					Size = { "UDim2", 0, 260, 0, 30 },
					Position = { "UDim2", 0, 20, 0, 60 },
				},
			},
		},
	},

	expect = {},
	ratios = {
		{ of = "Placeholder", to = "Reference", field = "textBoundsX", min = 0.9, max = 1.2 },
	},
}
