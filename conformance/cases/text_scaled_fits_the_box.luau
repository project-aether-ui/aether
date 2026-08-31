--!strict
--[[
	`TextScaled` inverts the relationship. Everywhere else the box is measured
	from the text; here the text is chosen to fit the box, and `TextSize` stops
	being the answer.

	WHICH MAKES IT HARD TO OBSERVE. The element's size is what the case set, so no
	geometric field reports what changed. What changed is the size the text is
	RENDERED at, which Roblox exposes as `TextBounds` and the display list carries
	as `textSize`. Those are proportional rather than equal, so this asserts a
	ratio over the derived `textHeight` field and never a value.

	NOT IMPLEMENTED HERE. `TextScaled` is named in one comment in Text.luau and
	read by nothing, so this is gated and reports unsupported off-engine while
	remaining verifiable against the engine.
]]
return {
	name = "TextScaled chooses the text size from the box",
	provenance = "asserted",
	requires = { "TextScaled" },
	note = "Two identical strings in boxes of 1x and 2x height. If the text is chosen from the box, "
		.. "the rendered size doubles with it. If TextScaled is ignored, both render at TextSize and "
		.. "the ratio is 1.0.",
	surface = { width = 400, height = 300 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "Small",
				props = {
					Text = "Fit",
					TextScaled = true,
					--- Ignored when TextScaled is on, and set deliberately: an
					--- implementation that honours it here is not scaling.
					TextSize = 12,
					Size = { "UDim2", 0, 120, 0, 40 },
				},
			},
			{
				class = "TextLabel",
				name = "Large",
				props = {
					Text = "Fit",
					TextScaled = true,
					TextSize = 12,
					Size = { "UDim2", 0, 240, 0, 80 },
					Position = { "UDim2", 0, 0, 0, 100 },
				},
			},
		},
	},

	expect = {},
	ratios = {
		--- Twice the box, twice the text. A little slack because the fit is
		--- constrained by width as well as height and may round to a whole size.
		{ of = "Large", to = "Small", field = "textHeight", expect = 2.0, tolerance = 0.15 },
	},
}
