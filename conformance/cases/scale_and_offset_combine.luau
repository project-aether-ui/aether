--!strict
--[[
	`UDim2` is {scale, offset} per axis and the two ADD. Offset is applied after
	the scale resolves, so a negative offset insets a full-width child — which is
	the idiom every padded container uses.
]]
return {
	name = "scale and offset combine additively",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.728",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Root",
		props = { Size = { "UDim2", 1, 0, 1, 0 } },
		children = {
			{
				class = "Frame",
				name = "Inset",
				props = {
					Position = { "UDim2", 0, 10, 0, 10 },
					Size = { "UDim2", 1, -20, 1, -20 },
				},
			},
		},
	},

	expect = {
		{ name = "Inset", x = 10, y = 10, w = 180, h = 80 },
	},
}
