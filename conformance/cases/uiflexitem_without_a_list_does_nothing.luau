--!strict
return {
	name = "UIFlexItem under a parent with no UIListLayout has no effect",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	note = "A Grow child of a plain panel. The engine keeps its own Position and Size.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 100 } },
		children = {
			{
				class = "Frame",
				name = "A",
				props = { Size = { "UDim2", 0, 40, 0, 20 }, Position = { "UDim2", 0, 10, 0, 10 } },
				children = {
					{
						class = "UIFlexItem",
						name = "Flex",
						props = {
							FlexMode = { "Enum", "UIFlexMode", "Grow" },
						},
					},
				},
			},
		},
	},

	expect = {
		{ name = "A", x = 10, y = 10, w = 40, h = 20 },
	},
}
