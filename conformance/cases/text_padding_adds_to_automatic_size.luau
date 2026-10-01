--!strict
--[[
	A UIPadding inside an auto-sized TextLabel is added to the text's extent.

	The label grows to hold its text AND its own padding, so the padding insets
	the text rather than eating into it. Uneven on purpose: top 8 and bottom 24,
	so an implementation that counts one side twice, or only one side, lands on
	a different height.

	HEIGHT AGAINST A RULER. One line of the default face is 1.5 x TextSize, 30
	at 20 (`one line of text is a fixed multiple of TextSize`), so the padded
	label is 8 + 30 + 24 = 62 and the ruler is 62 tall.

	WIDTH AS A MINIMUM. How wide "H" is belongs to the face, so no width is
	asserted. Left and right padding of 16 each add 32 to a glyph about 20 wide,
	so the padded label is at least twice the bare one for any "H" up to 32
	wide. An implementation ignoring the padding reports 1.0.
]]
local function padding(left: number, right: number, top: number, bottom: number): any
	return {
		class = "UIPadding",
		name = "Padding",
		props = {
			PaddingLeft = { "UDim", 0, left },
			PaddingRight = { "UDim", 0, right },
			PaddingTop = { "UDim", 0, top },
			PaddingBottom = { "UDim", 0, bottom },
		},
	}
end

return {
	name = "UIPadding adds to an auto-sized label's text extent",
	provenance = "asserted",
	requires = { "TextPadding" },
	note = "A command-bar probe on 2026-10-01 read TextBounds 20 x 30 for \"H\" at TextSize 20 with "
		.. "a UIPadding of 16 inside a fixed-size label, and drew the glyph 16 px in from the "
		.. "left and top. That AutomaticSize adds the padding to those bounds is the belief this "
		.. "case checks; nothing has run it in the engine yet.",
	surface = { width = 300, height = 200 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "Bare",
				props = {
					Text = "H",
					TextSize = 20,
					AutomaticSize = { "Enum", "AutomaticSize", "XY" },
					Size = { "UDim2", 0, 0, 0, 0 },
				},
			},
			{
				class = "TextLabel",
				name = "Padded",
				props = {
					Text = "H",
					TextSize = 20,
					AutomaticSize = { "Enum", "AutomaticSize", "XY" },
					Size = { "UDim2", 0, 0, 0, 0 },
					Position = { "UDim2", 0, 0, 0, 50 },
				},
				children = { padding(16, 16, 8, 24) },
			},
			{
				class = "Frame",
				name = "Ruler",
				props = {
					Size = { "UDim2", 0, 40, 0, 62 },
					Position = { "UDim2", 0, 120, 0, 50 },
				},
			},
		},
	},

	expect = {},
	ratios = {
		{ of = "Padded", to = "Ruler", field = "h", expect = 1.0, tolerance = 0.02 },
		{ of = "Padded", to = "Bare", field = "w", min = 2.0 },
	},
}
