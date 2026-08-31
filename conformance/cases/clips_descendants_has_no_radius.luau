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

	THE ENGINE RUNNER REPORTED THIS AS AGREEING, and that is a flaw in the case
	rather than evidence the gap is closed. What it asserts is the titlebar's
	RECTANGLE, and the rectangle conforms — clipping to a rounded parent does not
	move a child, it changes which of its pixels survive. The divergence is in the
	display list's clip representation, which `AbsolutePosition` cannot see and
	the engine runner therefore cannot measure.

	So this case now carries what it can honestly assert, and the gap is recorded
	beside it as something no geometric assertion will ever catch. Closing it
	needs a clip radius in the display list AND a pixel-level comparison, which is
	a different kind of runner.
]]
return {
	name = "a clipped child keeps its rectangle (the radius gap is invisible here)",
	provenance = "divergent",
	note = "Roblox rounds a clip to the parent's UICorner; our display list carries a clip as a bare "
		.. "rectangle with no radius. NOT DETECTABLE GEOMETRICALLY -- the rectangle below conforms, "
		.. "and the engine runner confirmed it. Needs a clip radius in the display list and a "
		.. "pixel-level runner to catch.",
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
