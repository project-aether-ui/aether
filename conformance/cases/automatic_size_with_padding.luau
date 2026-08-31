--!strict
--[[
	`UIPadding` adds to what `AutomaticSize` measures — the parent grows to fit
	its children PLUS its own padding, rather than the children being inset into
	a size that was already decided.

	The ordering is what makes this worth a case: measure, then pad, then commit.
	An implementation that pads first measures the padding twice.
]]
return {
	name = "AutomaticSize includes UIPadding in the measured size",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.728",
	surface = { width = 200, height = 200 },

	tree = {
		class = "Frame",
		name = "Padded",
		props = {
			Size = { "UDim2", 0, 100, 0, 0 },
			AutomaticSize = { "Enum", "AutomaticSize", "Y" },
		},
		children = {
			{
				class = "UIPadding",
				name = "Padding",
				props = {
					PaddingTop = { "UDim", 0, 8 },
					PaddingBottom = { "UDim", 0, 8 },
				},
			},
			{ class = "UIListLayout", name = "Layout" },
			{ class = "Frame", name = "Only", props = { Size = { "UDim2", 1, 0, 0, 24 } } },
		},
	},

	expect = {
		-- 24 of child, plus 8 above and 8 below.
		{ name = "Padded", w = 100, h = 40 },
	},
}
