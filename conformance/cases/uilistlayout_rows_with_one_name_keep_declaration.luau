--!strict
return {
	name = "UIListLayout with SortOrder unset and identical names keeps declaration order",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.741.19.7411056",
	note = "Three children all named Row, heights 10, 20 and 30, SortOrder unset. The engine keeps "
		.. "declaration order for the tie. Each Row carries a full size marker so the runner can "
		.. "tell them apart.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Panel",
		props = { Size = { "UDim2", 0, 200, 0, 100 } },
		children = {
			{
				class = "UIListLayout",
				name = "Layout",
				props = {
					FillDirection = { "Enum", "FillDirection", "Vertical" },
					HorizontalAlignment = { "Enum", "HorizontalAlignment", "Left" },
					VerticalAlignment = { "Enum", "VerticalAlignment", "Top" },
				},
			},
			{
				class = "Frame",
				name = "Row",
				props = { Size = { "UDim2", 0, 50, 0, 10 } },
				children = {
					{ class = "Frame", name = "M10", props = { Size = { "UDim2", 1, 0, 1, 0 } } },
				},
			},
			{
				class = "Frame",
				name = "Row",
				props = { Size = { "UDim2", 0, 50, 0, 20 } },
				children = {
					{ class = "Frame", name = "M20", props = { Size = { "UDim2", 1, 0, 1, 0 } } },
				},
			},
			{
				class = "Frame",
				name = "Row",
				props = { Size = { "UDim2", 0, 50, 0, 30 } },
				children = {
					{ class = "Frame", name = "M30", props = { Size = { "UDim2", 1, 0, 1, 0 } } },
				},
			},
		},
	},

	expect = {
		{ name = "M10", x = 0, y = 0, w = 50, h = 10 },
		{ name = "M20", x = 0, y = 10, w = 50, h = 20 },
		{ name = "M30", x = 0, y = 30, w = 50, h = 30 },
	},
}
