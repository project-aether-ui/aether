--!strict
--[[
	`TextWrapped` breaks a string that does not fit the element's width, and
	`AutomaticSize.Y` then grows the element to hold the lines.

	NOT IMPLEMENTED HERE. Aether has no wrapping at all -- `TextWrapped` is read
	by nothing -- so this reports unsupported off-engine while still being
	verifiable against the engine. That is what `requires` is for: a case can know
	the right answer before anything implements it, and becomes a test the day
	`TextWrapped` appears in the runner's SUPPORTS list.

	ASSERTED AS A MINIMUM, because where the breaks fall is provider-specific and
	the line count follows from it. What every implementation must agree on is
	that a string too long for its width occupies more than one line. An
	implementation that ignores `TextWrapped` reports exactly 1.0.
]]
local LONG = "The quick brown fox jumps over the lazy dog and keeps going well past the edge"

return {
	name = "TextWrapped grows the height past one line",
	provenance = "asserted",
	requires = { "TextWrapped" },
	note = "Aether implements no wrapping. Verify in Studio, then this is a roadmap item with a "
		.. "verified expectation rather than a guess.",
	surface = { width = 400, height = 300 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "TextLabel",
				name = "Single",
				props = {
					Text = "One line",
					TextSize = 18,
					TextWrapped = true,
					AutomaticSize = { "Enum", "AutomaticSize", "Y" },
					Size = { "UDim2", 0, 200, 0, 0 },
				},
			},
			{
				class = "TextLabel",
				name = "Wrapped",
				props = {
					Text = LONG,
					TextSize = 18,
					TextWrapped = true,
					AutomaticSize = { "Enum", "AutomaticSize", "Y" },
					Size = { "UDim2", 0, 200, 0, 0 },
					Position = { "UDim2", 0, 0, 0, 120 },
				},
			},
		},
	},

	expect = {},
	ratios = {
		--- Two lines at the very least. The string is roughly four times the
		--- width it is given, so any real implementation produces more, and one
		--- that ignores wrapping produces exactly 1.0.
		{ of = "Wrapped", to = "Single", field = "h", min = 1.9 },
	},
}
