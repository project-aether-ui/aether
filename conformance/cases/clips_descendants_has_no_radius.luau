--!strict
--[[
	A CLIPPED CHILD IS MASKED TO ITS PARENT'S ROUNDED CORNER.

	On Roblox, `ClipsDescendants` on a frame carrying a `UICorner` clips its
	children to the ROUNDED shape -- a titlebar inside a rounded card gets
	rounded top corners. Dew did not: the display list carried a clip as a bare
	rectangle with no radius, so a painter had nothing to round to, and the
	corner pixels leaked.

	Found by building a virtual window manager whose titlebars squared off the
	corners of the cards they sat in. Recorded as an observable divergence in
	milestone 3 because closing it needed a clip radius in the display list AND a
	pixel-level comparison, which is a different kind of runner.

	CLOSED in milestone 4: `Node` carries `clip_radius`, `ar_clip_push_rounded`
	masks to a rounded path on both backends, and `clip_cuts` stopped eliding the
	mask for a shape that sits inside the clip RECTANGLE but crosses its corner
	arc.

	THE FILE NAME IS NOW HISTORICAL. It is kept because milestone 4's completion
	test names it, and renaming a case renames its golden.

	PROVENANCE IS `asserted`, NOT `roblox`, and the distinction matters. The
	GEOMETRIC half was verified in Studio -- the engine runner reported the
	titlebar's rectangle as agreeing, and it still does, because clipping to a
	rounded parent does not move a child. The PIXEL half was reasoned from
	documented behaviour and has never been rendered in Studio and compared. Only
	the in-engine runner produces `roblox`, so this says what it can honestly
	say and counts as an open question until somebody checks it.
]]
return {
	name = "a clipped child is masked to its parent's rounded corner",
	provenance = "asserted",
	note = "The corner at (2, 2) is inside the titlebar's rectangle and outside the card's "
		.. "radius-14 arc, so a rounded clip masks it. Believed to match Roblox and not yet "
		.. "rendered in Studio and compared.",
	surface = { width = 200, height = 100 },

	tree = {
		class = "Frame",
		name = "Card",
		props = {
			Size = { "UDim2", 0, 120, 0, 60 },
			ClipsDescendants = true,
			BackgroundColor3 = { "Color3", 0.2, 0.2, 0.2 },
		},
		children = {
			{ class = "UICorner", name = "Corner", props = { CornerRadius = { "UDim", 0, 14 } } },
			{
				class = "Frame",
				name = "Titlebar",
				props = {
					Size = { "UDim2", 1, 0, 0, 20 },
					BackgroundColor3 = { "Color3", 1, 0, 0 },
				},
			},
		},
	},

	expect = {
		-- The titlebar is clipped to the card's RECTANGLE, corners included.
		{ name = "Titlebar", x = 0, y = 0, w = 120, h = 20 },
	},

	pixels = {
		--- Inside the Titlebar and safely within the card's rounded corner:
		{ x = 20, y = 10, color = "#ff0000" },
		--- At (2, 2): inside Titlebar rect [0..120, 0..20], and OUTSIDE the
		--- card's radius-14 corner. Masked, so the surface shows through.
		--- Dew leaked Titlebar red here until milestone 4.
		{ x = 2, y = 2, color = "#00000000" },
	},
}
