--!strict
--[[
	`AutomaticSize` inverts the usual direction: instead of a child resolving
	against its parent, the parent measures its children.

	This is where an independent implementation stops doing arithmetic and starts
	reproducing an algorithm, and it is the single most likely place for two
	implementations of the standard to disagree.
]]
return {
	name = "AutomaticSize Y grows a frame to fit its children",
	provenance = "roblox",
	surface = { width = 200, height = 200 },

	tree = {
		class = "Frame",
		name = "Auto",
		props = {
			Size = { "UDim2", 0, 100, 0, 0 },
			AutomaticSize = { "Enum", "AutomaticSize", "Y" },
		},
		children = {
			{ class = "UIListLayout", name = "Layout" },
			{ class = "Frame", name = "A", props = { Size = { "UDim2", 1, 0, 0, 30 } } },
			{ class = "Frame", name = "B", props = { Size = { "UDim2", 1, 0, 0, 20 } } },
		},
	},

	expect = {
		-- Width is fixed at 100; height is measured from the two children.
		{ name = "Auto", w = 100, h = 50 },
	},
}
