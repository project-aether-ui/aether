--!strict
--[[
	HitTest: does a point actually land on this element, as drawn?

	WHY THIS EXISTS (ms-43 M20). Both the pointer router and the input-scope
	registry were testing a raw AbsolutePosition/AbsoluteSize rectangle. That
	rectangle is where an element WOULD be if nothing clipped it — and inside a
	ScrollingFrame, plenty does.

	The bug es9 found: the Shop's carousel cards live in a ScrollingFrame that
	sits directly under the header. Scroll a card up and it is clipped out of
	sight behind the header — but its AbsolutePosition/AbsoluteSize still covers
	that area, so the raw rect test said "the pointer is over this card". Since
	the ScrollingFrame and the header are siblings at equal ZIndex and the
	ScrollingFrame is declared later, it legitimately renders above — so the
	invisible, clipped card outranked the close button and ate the click.

	Nothing about the ordering was wrong. The element simply was not there.

	An element's real hit area is its own rect INTERSECTED with the rect of every
	clipping ancestor. Empty intersection means untouchable, however large the
	element's own bounds are.
]]

--- ms-51 M16: resolved here purely for the value vocabulary below.
local Deps = require("./Deps")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below is unchanged.
local UDim =
	Deps.Vocabulary.UDim

--- THE SCENE CONTRACT (ms-51 M16 part 3).
---
--- Every engine question this file asks now goes through Layer 2.5: bounds,
--- visibility, clipping, parentage, declaration order, layer roots, attributes
--- and the rendered corner. Nothing below names `Instance`, `IsA`,
--- `AbsolutePosition` or `LayerCollector`.
---
--- The algorithms are UNCHANGED. What they encode was never Roblox-specific — an
--- element's real hit area is its own rect intersected with every clipping
--- ancestor's, and that is true of any compositor. It only read as Roblox code
--- because the only way to ask the questions was to ask the engine.
local Scene = Deps.Host.Scene

local HitTest = {}

export type Rect = { MinX: number, MinY: number, MaxX: number, MaxY: number }

--- Does this container clip what it contains?
---
--- ScrollingFrame and CanvasGroup clip regardless of the ClipsDescendants flag —
--- a ScrollingFrame with ClipsDescendants off still bounds its canvas, and a
--- CanvasGroup renders its subtree to a texture the size of itself.
local function clips(gui: any): boolean
	return Scene.Clips(gui)
end

-- Instrumentation. Ancestor walks are the expensive part of hit testing, so the
-- conformance gate asserts a budget on them rather than on wall time, which
-- would be flaky. Reset by _ResetStats.
local walkCount = 0
local rawTestCount = 0

function HitTest._Stats(): (number, number)
	return rawTestCount, walkCount
end

function HitTest._ResetStats()
	walkCount = 0
	rawTestCount = 0
end

--- Is (x, y) inside the element's OWN rectangle, ignoring clipping?
---
--- Four comparisons, no ancestor walk. Sound as an early-out because clipping
--- only ever SHRINKS the hit area: a point outside the raw rect cannot be inside
--- the clipped one. Rejecting here is what keeps a large registry cheap.
function HitTest.RawContains(gui: any, x: number, y: number): boolean
	rawTestCount += 1
	local bx, by, bw, bh = Scene.Bounds(gui)
	return x >= bx and x <= bx + bw and y >= by and y <= by + bh
end

--- Is (x, y) inside the element's ROUNDED shape (ms-43 M103)?
---
--- es9: the engine's own hit-testing accounts for UICorner, and ours did not —
--- our controls claimed their square corners, so a pointer in the dead triangle
--- outside a rounded button still hovered and still clicked it. On a pill-shaped
--- button that is a lot of area, and it reads as the cursor "catching" on
--- nothing.
---
--- Only the four corner SQUARES need testing: everywhere else in the rect is
--- inside the rounded shape by definition, so this costs one distance check for
--- the small fraction of points that land in a corner box, and nothing at all
--- otherwise.
local function cornerRadiusOf(gui: any, sizeX: number, sizeY: number): number
	--- A DECLARED radius wins over a rendered one (ms-43 M104).
	---
	--- es9, on the button's invisible root: should it carry a real UICorner, or
	--- should the rounding be "stored virtually in a way that is resolved
	--- internally"? Virtually, and their own reason is the strongest one — we are
	--- moving off Active for cursor effects, so the ENGINE never needs to know
	--- our hit shape.
	---
	--- Adding a UICorner to an invisible frame would create a rendering Instance
	--- purely to carry a number to our own hit test, and it would weld hit shape
	--- to a rendering artifact: a control could then never have a hit radius that
	--- differs from its visual one. An attribute costs no Instance, renders
	--- nothing, and crosses package boundaries without a registry.
	---
	--- Scale and offset are stored separately because a UDim is not an attribute
	--- type, and because a pill (scale 1) has to keep working when the element
	--- resizes.
	local scale = Scene.Attribute(gui, "SpektrHitCornerScale")
	local offset = Scene.Attribute(gui, "SpektrHitCornerOffset")
	local sv = if type(scale) == "number" then scale else nil
	local ov = if type(offset) == "number" then offset else nil
	if sv or ov then
		local resolved = (sv or 0) * math.min(sizeX, sizeY) + (ov or 0)
		return math.max(0, math.min(resolved, sizeX / 2, sizeY / 2))
	end

	-- GUARDED. Not every caller hands us a real Instance — the InputScope and
	-- PointerRouter suites pass minimal stand-ins with only the geometry fields,
	-- and adding this unguarded broke both of them. A stand-in with no corner is
	-- a square element, which is the right answer anyway.
	local rScale, rOffset = Scene.RenderedCorner(gui)
	if rScale == nil and rOffset == nil then
		return 0
	end
	local r = { Scale = rScale or 0, Offset = rOffset or 0 }
	-- Scale resolves against the SMALLER dimension, and the radius can never
	-- exceed half of either — that is what makes UDim.new(1, 0) a pill rather
	-- than an error.
	local resolved = r.Scale * math.min(sizeX, sizeY) + r.Offset
	return math.max(0, math.min(resolved, sizeX / 2, sizeY / 2))
end

function HitTest.RoundedContains(gui: any, x: number, y: number): boolean
	local bx, by, bw, bh = Scene.Bounds(gui)
	local radius = cornerRadiusOf(gui, bw, bh)
	if radius <= 0 then
		return true
	end

	-- Distance from the nearest corner CENTRE, but only when the point is inside
	-- that corner's square. `cx`/`cy` are how far the point lies into the corner
	-- box on each axis; both positive means it is in the box.
	local cx = math.max(bx + radius - x, x - (bx + bw - radius), 0)
	local cy = math.max(by + radius - y, y - (by + bh - radius), 0)
	if cx <= 0 or cy <= 0 then
		return true
	end
	return (cx * cx + cy * cy) <= radius * radius
end

--- Visibility and clipping in ONE ancestor walk.
---
--- Both questions need the same traversal, and asking them separately walked the
--- tree twice for every candidate. Returns false as soon as either fails.
function HitTest.ContainsVisible(gui: any, x: number, y: number): boolean
	-- Cheap rejection first: no walk at all for the overwhelming majority.
	if not HitTest.RawContains(gui, x, y) then
		return false
	end
	-- Rounded corners, before the ancestor walk: it is a rejection like the rect
	-- test, and rejecting early is what keeps a large registry cheap (M103).
	if not HitTest.RoundedContains(gui, x, y) then
		return false
	end

	walkCount += 1

	local bx, by, bw, bh = Scene.Bounds(gui)
	local minX, minY = bx, by
	local maxX, maxY = bx + bw, by + bh

	if not Scene.IsVisible(gui) then
		return false
	end

	local cur: any = Scene.Parent(gui)
	while cur and Scene.IsSurface(cur) do
		if not Scene.IsVisible(cur) then
			return false
		end
		if clips(cur) then
			local cx, cy, cw, ch = Scene.Bounds(cur)
			minX = math.max(minX, cx)
			minY = math.max(minY, cy)
			maxX = math.min(maxX, cx + cw)
			maxY = math.min(maxY, cy + ch)
			if x < minX or x > maxX or y < minY or y > maxY then
				return false
			end
		end
		cur = Scene.Parent(cur)
	end

	-- Must terminate at an enabled layer root to be on screen at all.
	if cur and Scene.IsLayerRoot(cur) then
		return Scene.IsEnabled(cur)
	end
	return cur ~= nil
end

--- The element's visible rectangle: its own bounds, cut down by every clipping
--- ancestor. Returns nil when the intersection is empty (fully clipped away).
function HitTest.VisibleRect(gui: any): Rect?
	walkCount += 1
	local bx, by, bw, bh = Scene.Bounds(gui)
	local rect: Rect = {
		MinX = bx,
		MinY = by,
		MaxX = bx + bw,
		MaxY = by + bh,
	}

	local cur: any = Scene.Parent(gui)
	while cur and Scene.IsSurface(cur) do
		if clips(cur) then
			local cx, cy, cw, ch = Scene.Bounds(cur)
			rect.MinX = math.max(rect.MinX, cx)
			rect.MinY = math.max(rect.MinY, cy)
			rect.MaxX = math.min(rect.MaxX, cx + cw)
			rect.MaxY = math.min(rect.MaxY, cy + ch)
			if rect.MinX > rect.MaxX or rect.MinY > rect.MaxY then
				return nil
			end
		end
		cur = Scene.Parent(cur)
	end

	return rect
end

--- Is (x, y) on this element as it is actually drawn?
function HitTest.Contains(gui: any, x: number, y: number): boolean
	local rect = HitTest.VisibleRect(gui)
	if not rect then return false end
	if x < rect.MinX or x > rect.MaxX or y < rect.MinY or y > rect.MaxY then
		return false
	end
	-- The clipped rect says the point is on screen; the element's own corner
	-- radius says whether it is on the ELEMENT (M103).
	return HitTest.RoundedContains(gui, x, y)
end

--- Is the element and every ancestor visible? No compositor exposes this
--- transitively, so walk it.
function HitTest.IsEffectivelyVisible(gui: any): boolean
	walkCount += 1
	local cur: any = gui
	while cur and Scene.IsSurface(cur) do
		if not Scene.IsVisible(cur) then
			return false
		end
		cur = Scene.Parent(cur)
	end
	if cur and Scene.IsLayerRoot(cur) then
		return Scene.IsEnabled(cur)
	end
	return cur ~= nil
end

local pathCache: { [any]: { any } } = {}
local layerCache: { [any]: any } = {}

function HitTest.InvalidatePathCache()
	table.clear(pathCache)
	table.clear(layerCache)
end

--- Root-first ancestor chain, plus the LayerCollector it lives under.
function HitTest.PathOf(gui: any): ({ any }, any)
	local cached = pathCache[gui]
	if cached then
		return cached, layerCache[gui]
	end

	local chain: { any } = {}
	local cur: any = gui
	while cur and not Scene.IsLayerRoot(cur) do
		table.insert(chain, 1, cur)
		cur = Scene.Parent(cur)
	end

	pathCache[gui] = chain
	layerCache[gui] = cur
	return chain, cur
end

function HitTest.ChildIndex(gui: any): number
	return Scene.ChildIndex(gui)
end

--- Does `a` render ABOVE `b`? Mirrors how ZIndexBehavior.Sibling resolves the
--- screen: DisplayOrder across LayerCollectors, then — at the first point the
--- two ancestor chains diverge — ZIndex between those siblings, then declaration
--- order (insertion index in parent's children). If one is an ancestor of the other,
--- the descendant is on top.
function HitTest.RendersAbove(a: any, b: any): boolean
	if a == b then return false end
	local pathA, layerA = HitTest.PathOf(a)
	local pathB, layerB = HitTest.PathOf(b)

	if layerA ~= layerB then
		local orderA = if layerA then Scene.DisplayOrder(layerA) else 0
		local orderB = if layerB then Scene.DisplayOrder(layerB) else 0
		if orderA ~= orderB then
			return orderA > orderB
		end
	end

	local shared = math.min(#pathA, #pathB)
	for i = 1, shared do
		if pathA[i] ~= pathB[i] then
			local za, zb = Scene.ZIndex(pathA[i]), Scene.ZIndex(pathB[i])
			if za ~= zb then
				return za > zb
			end
			return HitTest.ChildIndex(pathA[i]) > HitTest.ChildIndex(pathB[i])
		end
	end

	return #pathA > #pathB
end

return HitTest
