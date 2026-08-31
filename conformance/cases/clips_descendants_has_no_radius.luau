--!strict
--[[
	A DOCUMENTED GAP, not a passing test.

	On Roblox, `ClipsDescendants` on a frame carrying a `UICorner` clips its
	children to the ROUNDED shape — a titlebar inside a rounded card gets rounded
	top corners. Off-engine it does not: `Layout` honours ClipsDescendants and
	intersects the rectangles, but the display list carries a clip as a bare
	rectangle with no radius, so a painter has nothing to round to.

	Found by building a virtual window manager whose titlebars squared off the
	corners of the cards they sat in.

	The expectation below records the CURRENT behaviour so the gap is visible and
	regressions are caught. When the display list grows a clip radius this case
	becomes `roblox` and gains a `clipRadius` assertion.
]]
return {
	name = "clip rectangles carry no corner radius",
	provenance = "divergent",
	note = "Roblox rounds a clip to the parent's UICorner; the display list has no radius field",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Card",
		props = {
			Size = { "UDim2", 0, 120, 0, 60 },
			ClipsDescendants = true,
		},
		children = {
			{ class = "UICorner", name = "Corner", props = { CornerRadius = { "UDim", 0, 14 } } },
			{
				class = "Frame",
				name = "Titlebar",
				props = { Size = { "UDim2", 1, 0, 0, 20 } },
			},
		},
	},

	expect = {
		-- The titlebar is clipped to the card's RECTANGLE, corners included.
		{ name = "Titlebar", x = 0, y = 0, w = 120, h = 20 },
	},
}
