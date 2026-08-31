--!strict
--[[
	`AnchorPoint` offsets by a fraction of the element's own size, and
	`AutomaticSize` decides that size from the content. So the two have an
	ordering, and getting it wrong is invisible until an auto-sized element is
	also anchored.

	Aether applied the anchor while resolving the element, using the AUTHORED
	size -- usually zero, because the whole point of `AutomaticSize` is that the
	content decides. The offset was therefore zero and the element landed as
	though anchored at the top-left, however it was written.

	Found writing an ordinary centred readout in a Dew widget: a container
	anchored at (0, 0.5) sat at the card's midpoint rather than straddling it,
	and its second line fell off the bottom.
]]
return {
	name = "AnchorPoint offsets by the size AutomaticSize produced",
	provenance = "asserted",
	note = "The ordering is size, then anchor. An implementation applying the anchor first offsets "
		.. "by the authored size, which for an auto-sized element is usually zero.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "Frame",
				name = "Centred",
				props = {
					AnchorPoint = { "Vector2", 0.5, 0.5 },
					Position = { "UDim2", 0.5, 0, 0.5, 0 },
					--- Height authored as zero. Whatever the anchor offsets by, it
					--- is not this.
					Size = { "UDim2", 0, 80, 0, 0 },
					AutomaticSize = { "Enum", "AutomaticSize", "Y" },
				},
				children = {
					{ class = "Frame", name = "Content", props = { Size = { "UDim2", 1, 0, 0, 40 } } },
				},
			},
		},
	},

	expect = {
		--- 40 tall from its content, centred on (100, 50): x = 100 - 40, and
		--- y = 50 - 20. Anchored against the authored zero height it would sit at
		--- y = 50 instead, with its content hanging below.
		{ name = "Centred", x = 60, y = 30, w = 80, h = 40 },
	},
}
