--!strict
--[[
	THE CYCLE, and what Roblox actually does about it.

	A parent measuring an axis automatically depends on its children; a child
	sized in Scale on that axis depends on its parent. Something has to break the
	loop.

	VERIFIED IN STUDIO, and it is not what either party guessed. The surface is
	200 tall and the child is `{1,0, 0.5,20}`:

	    predicted   scale counts as zero, parent measures the 20 offset  →  20
	    ours        the scale-sized child is excluded entirely           →   0
	    ENGINE                                                           → 120

	120 is `0.5 × 200 + 20`. The child's scale resolves against the space
	AVAILABLE TO THE PARENT — the 200 the parent could have occupied — rather than
	against the parent's final measured height. The parent then fits the result.

	ONE DATA POINT DOES NOT FULLY DETERMINE THE RULE. "Available space" and
	"grandparent's height" are indistinguishable here because they are both 200. A
	case with a grandparent smaller than the surface would separate them, and is
	worth adding before anything relies on the mechanism rather than on this
	number.
]]
return {
	name = "AutomaticSize resolves a Scale-sized child against the available space",
	provenance = "roblox",
	--- The build these numbers came from. See conformance/README.md.
	verifiedAgainst = "0.728",
	note = "Our implementation produces 0 -- it excludes a scale-sized child from the measurement "
		.. "entirely. A genuine conformance bug in Layout.luau.",
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
			{ class = "Frame", name = "Mixed", props = { Size = { "UDim2", 1, 0, 0.5, 20 } } },
		},
	},

	expect = {
		{ name = "Auto", x = 0, y = 0, w = 100, h = 120 },
	},
}
