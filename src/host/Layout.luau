--!strict
--[[
	Aether · host/Layout — scale-and-offset layout, solved without an engine.

	WHY THIS EXISTS (ms-51 M21)
	It is the LAST engine service Aether does not model. Everything else a
	non-Roblox host needs is already here: construction (`create`), the scene
	contract (`Scene`), time (`Clock`), values (`Vocabulary`). But bounds were
	always somebody else's answer — in Roblox the layout system computes
	`AbsolutePosition`/`AbsoluteSize`, and headlessly they are whatever a test
	sets. Nothing could compute them.

	That gap is why the headless host can build a tree and not SHOW one, and
	showing one is the point: es9 asked how to tell which parts of what renders in
	Studio actually flow through Aether. A second host answers it by construction —
	whatever appears there went through `create` and the Scene contract, and
	whatever is missing did not.

	WHAT IS MODELLED, and it is deliberately the Roblox rules rather than an
	invention, because the whole tree is authored against them:

	  * UDim2 as scale-of-parent plus pixel offset, on each axis independently.
	  * AnchorPoint as a fraction of the element's OWN size, subtracted after
	    position resolves — which is what makes `AnchorPoint 0.5` centre.
	  * UIPadding insetting the CONTAINING box before children resolve against it.
	  * UIListLayout stacking children on one axis, in LayoutOrder then
	    declaration order, with Padding between them.
	  * ClipsDescendants intersecting a child's visible rect with its ancestor's.

	WHAT IS NOT, stated rather than discovered later: no UIAspectRatioConstraint, no
	UIGridLayout, no UIScale. Each is a real feature; none is needed to answer the
	question this was built for, and a layout engine that silently guessed at them
	would make the audit lie.

	TEXT MEASUREMENT ARRIVED IN ms-52 M1 and this note no longer excludes it.
	`AutomaticSize` resolves through `host.Text`, which is synchronous by contract
	because this function runs inside a frame. Only TEXT is measured: an element
	auto-sizing to its CHILDREN would need their rects, which are solved after it,
	and none of the four call sites in this repo use it that way.
]]

local Layout = {}

--- EVERYTHING THE SOLVER LOOKS AT (ms-52 M15.1).
---
--- Declared here, and gated: `LayoutReadSet.test.luau` records every property and
--- accessor an actual solve touches and fails if this list does not cover them.
---
--- WHY THIS EXISTS BEFORE ANY CACHE. A layout cache is exactly as correct as the
--- set of things it watches, and a MISSING entry is silent: that node keeps last
--- frame's rectangle, the frame stays internally consistent, and every pixel
--- check still passes because they compare the painter against the frame it was
--- GIVEN. It surfaces later as the ms-43 M20 stale-geometry bug -- the router
--- arbitrating against last frame's rectangle, so what can be clicked and what
--- can be seen disagree.
---
--- The gate maintains itself: a future solver that reads something new fails
--- rather than quietly holing the cache's assumptions.
Layout.Inputs = {
	--- Names passed to `Scene.Raw`.
	Properties = {
		"AnchorPoint", "AutomaticSize", "CanvasPosition", "FillDirection",
		"LayoutOrder", "Padding", "PaddingBottom", "PaddingLeft", "PaddingRight",
		"PaddingTop", "Position", "Scale", "Size", "Text", "TextSize", "Visible",
	},
	--- Derived accessors, which read layout-affecting state WITHOUT going through
	--- `Raw` -- `ClassOf` reads a class name, `Clips` a `ClipsDescendants`,
	--- `Children` the child list and its order. These are the entries most easily
	--- forgotten, because grepping for `Raw` does not show them.
	Accessors = {
		"Children", "ClassOf", "Clips", "Parent", "Raw", "ZIndex",
	},
}


--- Measured canvas extents, keyed weakly by node.
---
--- Kept beside the solve rather than written onto the instance because a mock is
--- a plain table and `AbsoluteCanvasSize` is a property the ENGINE owns -- the
--- host should report it, not let application code set it and be believed.
local CANVAS_EXTENT: { [any]: { X: number, Y: number } } = setmetatable({}, { __mode = "k" }) :: any

--- The host that is doing the solving, so the solver can report what it measured
--- without requiring the host module (a `require` yields, and this runs inside
--- reactive getters). Set by `Layout.Solve`, which already receives it.
Layout._Host = nil :: any

function Layout.SetCanvasExtent(node: any, x: number, y: number)
	CANVAS_EXTENT[node] = { X = x, Y = y }
	--- AND REPORTED ONTO THE NODE (ms-53 D8), so `Scene.CanvasExtent` can answer
	--- without reaching back into this module.
	---
	--- The note above says `AbsoluteCanvasSize` is the ENGINE's to own and that
	--- application code must not set it and be believed. That still holds -- and
	--- the SOLVER is not application code, it is the host doing the measuring the
	--- engine would do. Keeping the number only in a side table meant the host had
	--- no way to report it: spektr/scrollbar read the property, got `{0, 0}`, and
	--- hid the entire scrollbar off-engine while drawing it in a place.
	---
	--- Written here rather than fetched lazily because the fetch has to happen
	--- inside a reactive getter, and `require` YIELDS -- "attempt to yield in
	--- reactive scope" took the whole scrollbar down on the first try.
	if type(node) == "table" then
		local prev = rawget(node, "AbsoluteCanvasSize")
		local changed = not prev or prev.X ~= x or prev.Y ~= y
		rawset(node, "AbsoluteCanvasSize", { X = x, Y = y })
		--- AND ANNOUNCED. `spektr/scrollbar` re-reads its extents from
		--- `GetPropertyChangedSignal("AbsoluteCanvasSize")`, so a measurement that
		--- is written but not announced reaches nobody -- the bar keeps the numbers
		--- it saw at construction, which is 100 against 100, and stays hidden
		--- (ms-53 D8).
		if changed then
			local host = Layout._Host
			if host and host.FirePropertyChanged then
				host.FirePropertyChanged(node, "AbsoluteCanvasSize")
			end
		end
	end
end

--- How tall/wide the content inside this scroller measured, after the last solve.
--- Zero if it has never been solved or holds nothing.
function Layout.CanvasExtent(node: any): (number, number)
	local e = CANVAS_EXTENT[node]
	if not e then
		return 0, 0
	end
	return e.X, e.Y
end

export type Rect = { X: number, Y: number, Width: number, Height: number }

--- A resolved node: the element, its absolute rect, and the clip it inherits.
export type Solved = {
	Node: any,
	Rect: Rect,
	--- The intersection of every clipping ancestor, or nil when nothing clips.
	--- Kept separate from `Rect` because an element that is clipped AWAY still has
	--- a rectangle — that distinction is the whole of ms-43 M20.
	Clip: Rect?,
	Depth: number,
	ZIndex: number,
	Order: number,
}

local function readUDim(u: any): (number, number)
	if u == nil then
		return 0, 0
	end
	return u.Scale or 0, u.Offset or 0
end

local function readUDim2(v: any): (number, number, number, number)
	if v == nil then
		return 0, 0, 0, 0
	end
	local xs, xo = readUDim(v.X)
	local ys, yo = readUDim(v.Y)
	return xs, xo, ys, yo
end

local function intersect(a: Rect?, b: Rect?): Rect?
	if not a then
		return b
	end
	if not b then
		return a
	end
	local x1 = math.max(a.X, b.X)
	local y1 = math.max(a.Y, b.Y)
	local x2 = math.min(a.X + a.Width, b.X + b.Width)
	local y2 = math.min(a.Y + a.Height, b.Y + b.Height)
	if x2 <= x1 or y2 <= y1 then
		return { X = x1, Y = y1, Width = 0, Height = 0 }
	end
	return { X = x1, Y = y1, Width = x2 - x1, Height = y2 - y1 }
end

--- Which axes does `AutomaticSize` cover? Returns two booleans.
---
--- Accepts the Enum, its `.Name`, or a plain string, because a host that does not
--- carry Roblox's Enum table still has to express the same intent — and the
--- headless vocabulary's Enum is Lune's, not the engine's.
local function automaticAxes(value: any): (boolean, boolean)
	if value == nil then
		return false, false
	end
	local name = if type(value) == "string" then value else tostring((value :: any).Name or value)
	if string.find(name, "XY", 1, true) then
		return true, true
	end
	local hasX = string.find(name, "X", 1, true) ~= nil
	local hasY = string.find(name, "Y", 1, true) ~= nil
	return hasX, hasY
end

--- Solve one element against the box its parent offers it.
---
--- `laidOut` marks an element whose parent has already decided where it goes —
--- a `UIListLayout` child. Its own `Position` is then IGNORED rather than
--- resolved inside the slot it was given.
---
--- Verified in Studio: a list child cannot position itself. Before this, the
--- slot was passed as the child's containing box and the child's own Position
--- offset it inside — indistinguishable from correct for the overwhelming
--- majority of children, which set no Position at all, and wrong for every one
--- that does.
local function solveRect(Scene: any, node: any, parent: Rect, host: any?, laidOut: boolean?): Rect
	local sxs, sxo, sys, syo = readUDim2(Scene.Raw(node, "Size"))
	local pxs, pxo, pys, pyo = readUDim2(Scene.Raw(node, "Position"))
	if laidOut then
		pxs, pxo, pys, pyo = 0, 0, 0, 0
	end

	local width = parent.Width * sxs + sxo
	local height = parent.Height * sys + syo

	--- AUTOMATICSIZE (ms-52 M1): the element is sized BY its content, so the
	--- authored Size is a floor rather than the answer.
	---
	--- Only TEXT is measured here, because children are solved after this. An
	--- element auto-sizing to its CHILDREN is handled by `grow` after they are
	--- placed -- see there, and see ms-53 D1 for why this note used to say it was
	--- not worth doing.
	---
	--- What that note said: "a two-pass solver, and not what any of the four call
	--- sites in this repo actually use it for". Both halves had gone stale.
	--- THIRTEEN non-test source files use `AutomaticSize` today, Button among
	--- them -- and Button rendered at zero width off-engine for a whole milestone
	--- because of this. The second pass turned out to be needed only for subtrees
	--- containing a scale-sized descendant, which is one re-place rather than a
	--- solver rewrite.
	local autoX, autoY = automaticAxes(Scene.Raw(node, "AutomaticSize"))
	if (autoX or autoY) and host and host.Text then
		local text = Scene.Raw(node, "Text")
		if type(text) == "string" and text ~= "" then
			local size = Scene.Raw(node, "TextSize") or 14
			local tw, th = host.Text.Measure(text, size, nil)
			--- Padding on the element itself widens what its content needs.
			local padX, padY = 0, 0
			for _, child in ipairs(Scene.Children(node)) do
				if Scene.ClassOf(child) == "UIPadding" then
					local _, l = readUDim(Scene.Raw(child, "PaddingLeft"))
					local _, r = readUDim(Scene.Raw(child, "PaddingRight"))
					local _, t = readUDim(Scene.Raw(child, "PaddingTop"))
					local _, b = readUDim(Scene.Raw(child, "PaddingBottom"))
					padX, padY = l + r, t + b
					break
				end
			end
			if autoX then
				width = math.max(width, tw + padX)
			end
			if autoY then
				height = math.max(height, th + padY)
			end
		end
	end
	local x = parent.X + parent.Width * pxs + pxo
	local y = parent.Y + parent.Height * pys + pyo

	--- AnchorPoint is a fraction of the element's OWN size, applied after the
	--- position resolves. Centring is `0.5`, not a special case.
	local anchor = Scene.Raw(node, "AnchorPoint")
	if anchor then
		x -= width * (anchor.X or 0)
		y -= height * (anchor.Y or 0)
	end

	return { X = x, Y = y, Width = math.max(width, 0), Height = math.max(height, 0) }
end

--- The UIPadding on a node, as four offsets.
---
--- Read DIRECTLY rather than derived from the content box, because that box is
--- clamped at zero: an auto-sizing element starts at width 0, so
--- `(rect.X + rect.Width) - (box.X + box.Width)` answers -12 for a 12px right
--- padding and the two sides cancel. The padding a container needs is a property
--- of the container, not a difference between two rectangles.
local function paddingOf(Scene: any, node: any): (number, number, number, number)
	for _, child in ipairs(Scene.Children(node)) do
		if Scene.ClassOf(child) == "UIPadding" then
			local _, l = readUDim(Scene.Raw(child, "PaddingLeft"))
			local _, r = readUDim(Scene.Raw(child, "PaddingRight"))
			local _, t = readUDim(Scene.Raw(child, "PaddingTop"))
			local _, b = readUDim(Scene.Raw(child, "PaddingBottom"))
			return l, t, r, b
		end
	end
	return 0, 0, 0, 0
end

--- The box a container offers its children: its own rect, inset by any UIPadding.
local function contentBox(Scene: any, node: any, own: Rect): Rect
	local box = { X = own.X, Y = own.Y, Width = own.Width, Height = own.Height }
	for _, child in ipairs(Scene.Children(node)) do
		if Scene.ClassOf(child) == "UIPadding" then
			local _, l = readUDim(Scene.Raw(child, "PaddingLeft"))
			local _, r = readUDim(Scene.Raw(child, "PaddingRight"))
			local _, t = readUDim(Scene.Raw(child, "PaddingTop"))
			local _, b = readUDim(Scene.Raw(child, "PaddingBottom"))
			box.X += l
			box.Y += t
			box.Width = math.max(box.Width - l - r, 0)
			box.Height = math.max(box.Height - t - b, 0)
			break
		end
	end
	return box
end

--- The UIListLayout a container carries, if any.
local function listLayoutOf(Scene: any, node: any): any
	for _, child in ipairs(Scene.Children(node)) do
		if Scene.ClassOf(child) == "UIListLayout" then
			return child
		end
	end
	return nil
end

--- Is this child a LAYOUT MODIFIER rather than a drawn element?
---
--- UIPadding, UIListLayout, UICorner and friends are configuration attached to
--- their parent. They occupy no space and render nothing, so a solver that
--- treated them as children would stack empty boxes between the real ones.
local function isModifier(class: string?): boolean
	if class == nil then
		return false
	end
	return string.sub(class, 1, 2) == "UI"
end


--------------------------------------------------------------------------------
-- The solve cache (ms-52 M15.2).
--------------------------------------------------------------------------------

--- WHY A CACHE AT ALL. `Layout.Solve` was 2.31 ms of a ~7 ms frame and re-solved
--- all 185 nodes every frame with no memory of the previous one. Measured on
--- shop, only 16 of 287 nodes change a layout INPUT per frame -- the other 271
--- are re-derived to the same answer.
---
--- WHY COMPARE VALUES RATHER THAN TRACK WRITES. Notifying on every property
--- write would need a hook in each host. It is also unnecessary: property reads
--- cost 0.029 us and a whole solve reads 957 of them, so detecting change costs
--- 0.03 ms against the 2.31 ms of rebuilding. The cheap thing is looking; the
--- expensive thing is rebuilding.
---
--- WHY `==` IS ENOUGH. It is identity for the vocabulary's tables, so it reports
--- change whenever a value object is replaced -- even by an identical one. That
--- is CONSERVATIVE: a false positive costs a re-solve, never a wrong rectangle.
--- Measured, it flags the same 16 nodes a string fingerprint does, so the
--- conservatism costs nothing here and cannot cost correctness anywhere.
local WATCHED = Layout.Inputs.Properties

type CacheEntry = {
	--- The watched property values, compared by identity.
	inputs: { any },
	--- The children this node had, so an add, a removal or a reorder is caught.
	kids: { any },
	--- The box this subtree was solved INTO, and the clip it inherited. Identical
	--- inputs under a different box produce different rectangles.
	bx: number, by: number, bw: number, bh: number,
	cx: number, cy: number, cw: number, ch: number,
	clipped: boolean,
	depth: number,
	--- Where this subtree's entries sit in the PREVIOUS solve's array. Two numbers
	--- rather than a per-node array: storing a slice for each of 287 nodes would
	--- allocate exactly what this exists to avoid.
	first: number,
	count: number,
}

local cache: { [any]: CacheEntry } = setmetatable({}, { __mode = "k" }) :: any
local previous: { Solved }? = nil
local previousRoot: any = nil
--- THE HOST IS AN INPUT TOO, and not one the read-set gate can see.
---
--- `Layout.Inputs` covers what the solver reads from the SCENE. The host is a
--- separate argument, and it decides text measurement -- so the same tree solved
--- with a host and without it produces different rectangles for every
--- `AutomaticSize` node. Reusing across that difference returned measured widths
--- for a solve that was asked not to measure, which `SecondHost.test.luau` caught
--- on the first run: it solves one tree both ways on purpose.
local previousHost: any = nil
local hits, misses = 0, 0

--- OFF BY DEFAULT, because measured it does not pay yet.
---
--- On shop: 5.801 ms with the cache off, 6.487 ms with it on. It reuses 29% of
--- subtrees and is still 0.686 ms SLOWER, and the reason is exact -- the dirty
--- pass costs 0.735 ms, which is what the reuse fails to recover.
---
--- WHY THE REUSE IS WORTH SO LITTLE. The subtrees that stay clean are mostly
--- LEAVES, and skipping a leaf saves one `solveRect` while the pass that proved
--- it clean read sixteen properties to do it. The saving scales with subtree
--- size; the cost scales with node count.
---
--- WHAT WOULD FIX IT, and it is not tuning. The dirty pass is O(every node) every
--- frame because nothing tells the solver what changed. Only 16 of 287 nodes
--- change an input per frame, so a host that STAMPED A VERSION on write -- and
--- propagated it to ancestors -- would turn that walk into one comparison per
--- skip, O(writes x depth) instead of O(nodes x properties). `Headless` already
--- has the `__newindex` to hang it on; Roblox would need `Changed`. That is a
--- host-contract addition and its own sprint.
---
--- The machinery and its gates are kept rather than reverted because that sprint
--- needs exactly this, and it is verified: six cases, each poisoned.
local enabled = false

--- OFF FOR THE GATE THAT VERIFIES IT. `LayoutCache.test.luau` solves the same
--- tree with the cache on and off and requires byte-identical rectangles; without
--- a switch it could only compare the cache with itself.
function Layout.SetCacheEnabled(on: boolean)
	enabled = on
end

function Layout.ClearCache()
	cache = setmetatable({}, { __mode = "k" }) :: any
	previous = nil
	previousRoot = nil
	previousHost = nil
end

--- Hits and misses since the last reset. The gate asserts on these rather than on
--- TIMING: a cache that never hits is merely slow, and a timing assertion would
--- pass for it on a fast machine.
function Layout.CacheStats(): { Hits: number, Misses: number }
	return { Hits = hits, Misses = misses }
end

function Layout.ResetCacheStats()
	hits, misses = 0, 0
end

--- Solve a whole tree into a flat, PAINT-ORDERED list.
---
--- Flat rather than nested because that is what a renderer wants: one pass, back
--- to front. Order is ZIndex, then depth, then declaration — the same rules
--- HitTest.RendersAbove arbitrates by, so what a second host DRAWS on top is what
--- the router would consider on top. Two answers that could disagree would make
--- the whole instrument untrustworthy.
--- `host` is optional so every existing caller keeps working; without it,
--- AutomaticSize simply does not resolve, which is exactly the behaviour before
--- ms-52 M1 rather than a silent wrong answer.
--- Auto-size cases from the LAST solve that measured NOTHING, newest solve
--- replacing the last.
---
--- Exposed rather than thrown. Aether's promise is that a screen behaves
--- off-engine as it does in Roblox, and Roblox handles this case, so erroring
--- would break a screen that is fine in the engine. Returning nothing at all is
--- what let ms-53 D1 live for a milestone. A list a caller can read is the
--- middle.
local warnings: { string } = {}

function Layout.Warnings(): { string }
	return table.clone(warnings)
end


function Layout.Solve(Scene: any, root: any, viewport: Rect, host: any?): { Solved }
	--- Remembered so `SetCanvasExtent` can announce what it measured (ms-53 D8).
	Layout._Host = host or Layout._Host
	table.clear(warnings)
	local out: { Solved } = {}
	local order = 0

	--- REUSABLE ONLY AGAINST THE SAME TREE. A different root has different node
	--- identities, and the stored indices into `previous` would mean nothing.
	local prev = previous
	local canReuse = enabled and prev ~= nil and previousRoot == root and previousHost == host

	--- WHICH SUBTREES ARE UNCHANGED.
	---
	--- Walked before the solve rather than decided during it, because a node can
	--- only be skipped when EVERY descendant is also unchanged -- and that is not
	--- known until the descent the skip is trying to avoid.
	local dirty: { [any]: boolean } = {}
	local function markDirty(node: any): boolean
		local entry = cache[node]
		local changed = entry == nil
		if entry then
			for i, prop in ipairs(WATCHED) do
				if entry.inputs[i] ~= Scene.Raw(node, prop) then
					changed = true
					break
				end
			end
		end

		local kids = Scene.Children(node)
		if not changed then
			local was = (entry :: any).kids
			if #was ~= #kids then
				changed = true
			else
				for i = 1, #kids do
					if was[i] ~= kids[i] then
						changed = true
						break
					end
				end
			end
		end

		--- Descend regardless of the verdict so far: every node needs its own
		--- recorded, and a clean parent over a dirty child is still dirty.
		for _, child in ipairs(kids) do
			if markDirty(child) then
				changed = true
			end
		end
		dirty[node] = changed
		return changed
	end
	if canReuse then
		markDirty(root)
	end

	--- WRITTEN STRAIGHT INTO THE CACHE ENTRY, which persists across frames.
	---
	--- The first version kept three side tables -- span, box and clip per node --
	--- and rebuilt the inputs array on every miss. That is roughly a thousand
	--- table allocations a frame, and it made the cache SLOWER than no cache at
	--- all: 6.689 ms against 5.333 ms on shop. The bookkeeping cost more than the
	--- skipping saved.
	---
	--- Entries are now allocated once per node and MUTATED in place, so a steady
	--- frame allocates nothing for a node it re-solves and nothing for one it
	--- skips.
	local touched: { any } = {}

	--- Grow an already-emitted entry to contain the SUBTREE placed after it
	--- (ms-53 D1).
	---
	--- `solveRect` measures TEXT for an `AutomaticSize` node and stops, because
	--- children are solved after it. That left `Button` at zero width off-engine:
	--- it auto-sizes to its Content, its Content to its label, and only the label
	--- had text. Two nodes, no ink, for a whole milestone -- no screen mounts a
	--- bare Button and the suites assert on the tree it BUILDS, never on the
	--- rectangle it is given.
	---
	--- DESCENDANTS, not direct children, and that distinction is the whole fix.
	--- `Button > Face > Content > Label` with Face at `UDim2.fromScale(1, 1)`: a
	--- direct-children rule sees one scale-sized child, refuses, and leaves the
	--- button at zero. The engine plainly does not do that -- ms-43 M93 fixed "the
	--- buttons came out all too small" by making the button measure Content
	--- THROUGH that Face, and that fix works in Studio.
	---
	--- A SCALE-SIZED NODE CONTRIBUTES NOTHING ITSELF, because its size comes from
	--- the parent's -- the number being computed. Its descendants are placed at
	--- offsets from an origin that does not depend on the parent's size, so their
	--- extent is well defined. Skip the node, keep walking through it.
	---
	--- The extent is measured from the CONTENT ORIGIN and converted back into a
	--- size by adding the padding on both sides; measuring from the node's own
	--- edge would count the leading padding twice.
	local function grow(
		Scene: any,
		entry: any,
		out: { Solved },
		from: number,
		box: Rect,
		growX: boolean,
		growY: boolean,
		padL: number,
		padT: number,
		padR: number,
		padB: number,
		--- The box this element was OFFERED by its own parent, which is not the
		--- box it currently occupies. A scale-sized child resolves against this.
		offered: Rect
	): (boolean, boolean)
		if not growX and not growY then
			return false, false
		end
		--- A SKIPPED NODE'S TRAILING PADDING TRAVELS WITH ITS SUBTREE.
		---
		--- `docs/ui/explanation/automatic-size-cycles.md` states the rule the whole
		--- pattern rests on: "UIPadding works because it is applied AFTER
		--- measurement -- it adds to the width". Button puts its horizontal inset
		--- on the Face for exactly that reason.
		---
		--- The Face is scale-sized, so it is skipped and contributes no rect of its
		--- own -- but its right padding is still an inset its content must clear.
		--- Without carrying it, a button measured 64 where it wanted 76 and drew
		--- 12px of padding on the left and none on the right: a correct-looking
		--- button that is visibly lopsided.
		---
		--- Entries are in DFS order, so a parent always sets the figure its
		--- children read before they are reached.
		local right, bottom = -math.huge, -math.huge
		local inheritX: { [number]: number } = { [out[from + 1] and out[from + 1].Depth or 0] = 0 }
		local inheritY: { [number]: number } = { [out[from + 1] and out[from + 1].Depth or 0] = 0 }
		--- Immediate children resolve scale against the offered box; deeper
		--- descendants keep the old behaviour. Verified evidence covers one level
		--- of nesting and nothing below it, and inventing a rule past the data is
		--- how the first attempt at this got it wrong.
		local childDepth = out[from + 1] and out[from + 1].Depth or 0

		for i = from + 1, #out do
			local item = out[i]
			local xs, xo, ys, yo = readUDim2(Scene.Raw(item.Node, "Size"))
			local r = item.Rect
			local d = item.Depth
			local gotX, gotY = inheritX[d] or 0, inheritY[d] or 0
			local _, _, ownR, ownB = paddingOf(Scene, item.Node)
			--- The flat list is in depth order, so the next entry being deeper is
			--- exactly "this node has children".
			local hasContent = out[i + 1] ~= nil and out[i + 1].Depth > d

			--- A SCALE-SIZED CHILD IS MEASURED ONLY IF IT HAS NO CONTENT AND ASKS
			--- FOR LESS THAN THE WHOLE AXIS. Both halves are needed; each one alone
			--- was tried and was wrong.
			---
			--- The cycle is real -- the parent's size depends on the child and the
			--- child's on the parent -- and there are only two places to break it:
			--- resolve the child, or measure past it to what it contains.
			---
			--- CONTENT WINS WHEN THERE IS ANY. A `fromScale(1,1)` face over 90 of
			--- content measures 90 rather than the 200 on offer, and a `{1,0, 0.5,20}`
			--- face over 80 of content measures 80 rather than 120. The face is then
			--- placed at whatever the parent grew to.
			---
			--- WITHOUT CONTENT, A PARTIAL SCALE RESOLVES against the space the
			--- auto-sizing element was OFFERED: `{1,0, 0.5,20}` on a 200-tall surface
			--- makes the frame 120, and 60 under an 80-tall grandparent. Skipping the
			--- child instead produced 0 and collapsed it out of the display list.
			---
			--- WITHOUT CONTENT, A FULL SCALE RESOLVES TO NOTHING. `H = 1 x H + 0` is
			--- true of every H, so there is no size to derive and the element keeps
			--- what it was authored with. That is the "collapsed to its padding"
			--- symptom, and it is reported through Warnings() rather than left silent.
			---
			--- NEITHER CONDITION IS THE RULE ON ITS OWN, and both were believed to be
			--- in turn. `xs < 1` alone passed every case that existed because the only
			--- full-scale case was also the only one with content; the half-scale case
			--- with content then separated them. Replacing it with the content test
			--- alone immediately broke the full-scale childless case above. A rule that
			--- fits every case you have is not thereby the rule.
			---
			--- ONE READING IS STILL UNEXPLAINED: a childless `{1,0, 0.5,20}` under no
			--- layout measures 30 in Studio where this produces 120. See
			--- conformance/cases/automatic_size_scale_child_without_a_layout.luau --
			--- 30 is the second step of an iteration converging on 40, so it may be a
			--- sampled frame rather than a settled value. Do not encode it without a
			--- second engine reading.
			if growX then
				if xs == 0 then
					right = math.max(right, r.X + r.Width + gotX)
					inheritX[d + 1] = gotX
				elseif d == childDepth and not hasContent and xs < 1 then
					right = math.max(right, r.X + (offered.Width * xs + xo) + gotX)
					inheritX[d + 1] = gotX
				else
					inheritX[d + 1] = gotX + ownR
				end
			end
			if growY then
				if ys == 0 then
					bottom = math.max(bottom, r.Y + r.Height + gotY)
					inheritY[d + 1] = gotY
				elseif d == childDepth and not hasContent and ys < 1 then
					bottom = math.max(bottom, r.Y + (offered.Height * ys + yo) + gotY)
					inheritY[d + 1] = gotY
				else
					inheritY[d + 1] = gotY + ownB
				end
			end
		end

		local rect = entry.Rect
		local didX, didY = false, false
		if growX and right ~= -math.huge then
			--- The authored size is a FLOOR. AutomaticSize grows an element to fit
			--- its content; it does not shrink it.
			rect.Width = math.max(rect.Width, (right - box.X) + padL + padR)
			didX = true
		end
		if growY and bottom ~= -math.huge then
			rect.Height = math.max(rect.Height, (bottom - box.Y) + padT + padB)
			didY = true
		end
		return didX, didY
	end

	--- An auto axis that measured nothing kept its authored size, which is worth
	--- saying out loud: it is the "collapsed to its padding" symptom ms-43 M93
	--- spent a session on, and silence about it is what let D1 live.
	local function reportAuto(Scene: any, node: any, wantX: boolean, wantY: boolean, didX: boolean, didY: boolean)
		if (wantX and didX) or (wantY and didY) or (not wantX and not wantY) then
			if (not wantX or didX) and (not wantY or didY) then
				return
			end
		end

		--- A LEAF IS NOT A FAILURE. A TextLabel with `AutomaticSize.X` and no
		--- children is sized by its TEXT in `solveRect`, which is the case this
		--- solver always handled -- warning about it would fire on every label on
		--- every screen and teach people to ignore the list.
		local children = Scene.Children(node)
		local hasRealChild = false
		for _, child in ipairs(children) do
			if not isModifier(Scene.ClassOf(child)) then
				hasRealChild = true
				break
			end
		end
		if not hasRealChild then
			return
		end

		--- DEDUPED, because a node inside an auto-sized ancestor is visited twice
		--- -- once to measure, once after the re-place -- and the same warning
		--- twice reads like two problems.
		local name = Scene.Name(node) or "?"
		local function note(text: string)
			for _, existing in ipairs(warnings) do
				if existing == text then
					return
				end
			end
			table.insert(warnings, text)
		end
		if wantX and not didX then
			note(`{name}: AutomaticSize.X measured nothing -- every descendant is sized by scale on X, `
				.. "so it kept its authored width")
		end
		if wantY and not didY then
			note(`{name}: AutomaticSize.Y measured nothing -- every descendant is sized by scale on Y, `
				.. "so it kept its authored height")
		end
	end

	local function visit(node: any, parentBox: Rect, clip: Rect?, depth: number, laidOut: boolean?)
		if Scene.Raw(node, "Visible") == false then
			return
		end

		--- THE SKIP. Unchanged inputs are not enough on their own: the same node
		--- laid out into a different box, under a different clip, or at a different
		--- depth resolves differently, so each of those is part of the key.
		if canReuse and dirty[node] == false then
			local e = cache[node]
			local p = prev :: { Solved }
			if e ~= nil
				and e.bx == parentBox.X and e.by == parentBox.Y
				and e.bw == parentBox.Width and e.bh == parentBox.Height
				and e.depth == depth
				and e.clipped == (clip ~= nil)
				and (clip == nil or (e.cx == clip.X and e.cy == clip.Y
					and e.cw == clip.Width and e.ch == clip.Height))
			then
				for i = 0, e.count - 1 do
					local item: any = p[e.first + i]
					--- RESTORED FROM THE PRE-SCALE VALUES. `applyScales` MUTATES
					--- these rects in place after the walk, so an entry reused
					--- across frames would be scaled again on every one of them --
					--- a button under a UIScale would grow without bound while
					--- every one of its inputs stayed still.
					item.Rect.X, item.Rect.Y = item.BaseX, item.BaseY
					item.Rect.Width, item.Rect.Height = item.BaseW, item.BaseH
					order += 1
					item.Order = order
					table.insert(out, item)
				end
				hits += 1
				return
			end
		end
		misses += 1

		--- ALL OF THIS IS BOOKKEEPING FOR THE NEXT SOLVE, so a disabled cache must
		--- not pay for it. It did at first: sixteen property reads and a
		--- `Scene.Children` per node were still running with the feature off, which
		--- cost shop 16 fps for a cache nothing was using.
		local e: CacheEntry? = nil
		if enabled then
		local entry = cache[node]
		if entry == nil then
			entry = {
				inputs = table.create(#WATCHED),
				kids = {},
				bx = 0, by = 0, bw = 0, bh = 0,
				cx = 0, cy = 0, cw = 0, ch = 0,
				clipped = false, depth = 0, first = 0, count = 0,
			} :: any
			cache[node] = entry
		end
		local cur = entry :: CacheEntry
		cur.bx, cur.by, cur.bw, cur.bh = parentBox.X, parentBox.Y, parentBox.Width, parentBox.Height
		cur.depth = depth
		cur.clipped = clip ~= nil
		if clip then
			cur.cx, cur.cy, cur.cw, cur.ch = clip.X, clip.Y, clip.Width, clip.Height
		end
		for i, prop in ipairs(WATCHED) do
			cur.inputs[i] = Scene.Raw(node, prop)
		end
		cur.kids = Scene.Children(node)
		table.insert(touched, node)
		e = cur
		end

		local firstIndex = #out + 1
		local rect = solveRect(Scene, node, parentBox, host, laidOut)
		order += 1
		local entry = {
			Node = node,
			Rect = rect,
			Clip = clip,
			Depth = depth,
			ZIndex = Scene.ZIndex(node),
			Order = order,
		}
		table.insert(out, entry)

		local box = contentBox(Scene, node, rect)

		--- A SCROLLING FRAME IS THE ENGINE'S JOB, SO IT IS THE HOST'S (ms-52 M5).
		---
		--- Nothing here knew what a ScrollingFrame was, so off-engine it behaved as
		--- a plain clipping Frame: content past its edge was cut off with no way to
		--- reach it. ShopUI's body is a native ScrollingFrame with
		--- AutomaticCanvasSize, so half that screen was unreachable -- and it
		--- looked exactly like UI that had not been ported, which is what `--audit`
		--- was built to tell apart.
		---
		--- Aether's own ScrollArea/ScrollingFrame primitives do their own
		--- virtualisation and do NOT rely on this; this is for the raw engine
		--- class, which real screens use directly.
		---
		--- Two halves, both of which Roblox does for free:
		---   * children are displaced by -CanvasPosition;
		---   * with AutomaticCanvasSize the canvas grows to the content, which is
		---     what makes the scroll range non-zero in the first place.
		local isScroller = Scene.ClassOf(node) == "ScrollingFrame"
		if isScroller then
			local canvasPos = Scene.Raw(node, "CanvasPosition")
			local cx = if canvasPos then (canvasPos.X or 0) else 0
			local cy = if canvasPos then (canvasPos.Y or 0) else 0
			box = { X = box.X - cx, Y = box.Y - cy, Width = box.Width, Height = box.Height }
		end

		--- A scroller ALWAYS clips, whatever ClipsDescendants says: that is what
		--- makes it a viewport rather than a list that overflows its parent.
		local childClip = if Scene.Clips(node) or isScroller then intersect(clip, rect) else clip

		--- A list layout REPLACES scale-and-offset positioning for its siblings:
		--- each child is placed after the last, on one axis.
		--- PADDING, so an extent measured from the content origin can be turned
		--- back into a SIZE (ms-53 D1).
		local padL, padT, padR, padB = paddingOf(Scene, node)
		local growX, growY = automaticAxes(Scene.Raw(node, "AutomaticSize"))
		local childrenFrom = #out

		--- PLACING THE CHILDREN IS A FUNCTION, because an auto-sized node may have
		--- to do it TWICE.
		---
		--- The first pass measures. If the node then grows, any descendant sized by
		--- SCALE on the grown axis was solved against the old, smaller box and is
		--- now wrong: `Button`'s Face is `UDim2.fromScale(1, 1)` and stayed at zero
		--- width while the button around it grew to 64 -- which is the "mounted and
		--- painted nothing" the story reported, with the button now the right size
		--- and its only visible part still empty.
		---
		--- The second pass is a RE-PLACE, not a patch: discard what the first one
		--- emitted and run the same code against the grown box. Reusing the solve
		--- path is the point -- a hand-rolled reflow would be a second
		--- implementation of sizing, and the first is subtle enough.
		local function placeChildren(box: Rect)
			local list = listLayoutOf(Scene, node)
			if list then
				local _, padding = readUDim(Scene.Raw(list, "Padding"))
				local horizontal = tostring(Scene.Raw(list, "FillDirection") or ""):find("Horizontal") ~= nil

				local kids = {}
				for _, child in ipairs(Scene.Children(node)) do
					if not isModifier(Scene.ClassOf(child)) then
						table.insert(kids, child)
					end
				end
				--- LayoutOrder, then declaration order. `table.sort` is not stable, so
				--- the index is part of the key rather than relied upon.
				local index: { [any]: number } = {}
				for i, k in ipairs(kids) do
					index[k] = i
				end
				table.sort(kids, function(a, b)
					local la = Scene.Raw(a, "LayoutOrder") or 0
					local lb = Scene.Raw(b, "LayoutOrder") or 0
					if la ~= lb then
						return la < lb
					end
					return index[a] < index[b]
				end)

				local cursor = 0
				for _, child in ipairs(kids) do
					local slot = if horizontal
						then { X = box.X + cursor, Y = box.Y, Width = box.Width, Height = box.Height }
						else { X = box.X, Y = box.Y + cursor, Width = box.Width, Height = box.Height }
					local before = #out
					--- `true`: the slot IS this child's position. See solveRect.
					visit(child, slot, childClip, depth + 1, true)
					--- Advance by what the child actually resolved to, so a stack of
					--- differently-sized rows lays out correctly.
					if #out > before then
						local placed = out[before + 1].Rect
						cursor += (if horizontal then placed.Width else placed.Height) + padding
					end
				end
				return
			end

			for _, child in ipairs(Scene.Children(node)) do
				if not isModifier(Scene.ClassOf(child)) then
					visit(child, box, childClip, depth + 1)
				end
			end
		end

		placeChildren(box)

		--- Re-place only when growing changed something AND a descendant actually
		--- depends on that size. Most subtrees have neither and pay one scan.
		local beforeW, beforeH = entry.Rect.Width, entry.Rect.Height
		local didX, didY =
			grow(Scene, entry, out, childrenFrom, box, growX, growY, padL, padT, padR, padB, parentBox)

		--- ANCHORPOINT IS APPLIED BEFORE AUTOMATICSIZE KNOWS THE SIZE.
		---
		--- `solveRect` subtracts `width * anchor.X` from the position, and for an
		--- auto-sized element the width it has at that moment is the AUTHORED one
		--- -- usually zero, because the whole point is that the content decides.
		--- So the anchor offset was zero and the element landed as though anchored
		--- at the top-left, however it was written.
		---
		--- Found writing an ordinary centred readout: a container anchored at
		--- (0, 0.5) sat at the card's midpoint instead of straddling it, and its
		--- second line fell off the bottom.
		---
		--- The children are already placed against the old rectangle, so they move
		--- with it. Shifting is enough; nothing about their own layout changed.
		if didX or didY then
			local anchor = Scene.Raw(node, "AnchorPoint")
			local ax = if anchor then (anchor.X or 0) else 0
			local ay = if anchor then (anchor.Y or 0) else 0
			local dx = if didX then (entry.Rect.Width - beforeW) * ax else 0
			local dy = if didY then (entry.Rect.Height - beforeH) * ay else 0
			if dx ~= 0 or dy ~= 0 then
				entry.Rect.X -= dx
				entry.Rect.Y -= dy
				for i = childrenFrom + 1, #out do
					out[i].Rect.X -= dx
					out[i].Rect.Y -= dy
				end
			end
		end

		if didX or didY then
			local dependent = false
			for i = childrenFrom + 1, #out do
				local xs, _, ys, _ = readUDim2(Scene.Raw(out[i].Node, "Size"))
				if (didX and xs ~= 0) or (didY and ys ~= 0) then
					dependent = true
					break
				end
			end
			if dependent then
				for i = #out, childrenFrom + 1, -1 do
					out[i] = nil
				end
				placeChildren(contentBox(Scene, node, entry.Rect))
			end
		end
		reportAuto(Scene, node, growX, growY, didX, didY)


		--- BOTH EXITS RECORD. The list-layout branch returns early, and a count
		--- recorded on only one path means those subtrees are silently never
		--- cacheable -- a performance hole no correctness gate would show.
		if e then
			e.count = #out - firstIndex + 1
		end
	end

	--- UISCALE, APPLIED AS A TRANSFORM OVER A SUBTREE (ms-52 M2).
	---
	--- UIScale is not a sizing property, it is a scale about the element's own
	--- anchor that takes its DESCENDANTS with it -- spektr/button uses one for
	--- press and hover feedback, and scaling the button without its label would
	--- look worse than not scaling at all.
	---
	--- So it runs after the walk, over rects that are already placed, rather than
	--- being folded into `solveRect`. Outermost first (the walk emits parents
	--- before children, so `out` is already in that order before the paint sort),
	--- which makes nested scales compound the way they do in-engine.
	---
	--- NOT SCALED: the clip rectangles. A scaled element's clip should shrink with
	--- it, and this does not do that -- stated because it is a real limit, and a
	--- wrong clip is more misleading than none. No screen in this repo scales a
	--- clipping element today.
	local function applyScales()
		local scaled: { { node: any, s: number } } = {}
		for _, item in ipairs(out) do
			local find = (item.Node :: any).FindFirstChildOfClass
			if type(find) == "function" then
				local ok, us = pcall(find, item.Node, "UIScale")
				if ok and us then
					local value = Scene.Raw(us, "Scale")
					if type(value) == "number" and math.abs(value - 1) > 0.0001 then
						table.insert(scaled, { node = item.Node, s = value })
					end
				end
			end
		end
		if #scaled == 0 then
			return
		end

		local rectOf: { [any]: Rect } = {}
		for _, item in ipairs(out) do
			rectOf[item.Node] = item.Rect
		end

		for _, entry in ipairs(scaled) do
			local base = rectOf[entry.node]
			if base then
				--- The fixed point is the element's ANCHOR, which is what the engine
				--- scales about: a centred button grows from its middle, a
				--- top-left-anchored one grows to the right and down.
				local ax, ay = 0, 0
				local anchor = Scene.Raw(entry.node, "AnchorPoint")
				if anchor then
					ax, ay = anchor.X or 0, anchor.Y or 0
				end
				local ox = base.X + ax * base.Width
				local oy = base.Y + ay * base.Height
				local s = entry.s

				for _, item in ipairs(out) do
					--- Is this node inside the scaled one? Walk up rather than
					--- collecting a subtree, because the same node may be under
					--- several scaled ancestors and each must apply.
					local n: any = item.Node
					local inside = false
					while n do
						if n == entry.node then
							inside = true
							break
						end
						n = if Scene.Parent then Scene.Parent(n) else nil
					end
					if inside then
						local r = item.Rect
						item.Rect = {
							X = ox + (r.X - ox) * s,
							Y = oy + (r.Y - oy) * s,
							Width = r.Width * s,
							Height = r.Height * s,
						}
					end
				end
			end
		end
	end

	--- The canvas extent of every scroller, measured from what was actually
	--- placed inside it. Written back after the walk rather than during it,
	--- because a parent's canvas depends on descendants it has not visited yet.
	local function measureCanvases()
		local scrollers: { [any]: { top: number, bottom: number, left: number, right: number } } = {}
		local rectOf: { [any]: Rect } = {}
		for _, item in ipairs(out) do
			rectOf[item.Node] = item.Rect
		end
		for _, item in ipairs(out) do
			if Scene.ClassOf(item.Node) == "ScrollingFrame" then
				scrollers[item.Node] = { top = 0, bottom = 0, left = 0, right = 0 }
			end
		end
		if next(scrollers) == nil then
			return
		end
		--- Walk each placed node up to its nearest scrolling ancestor and grow
		--- that scroller's extent to contain it.
		for _, item in ipairs(out) do
			local ancestor = Scene.Parent and Scene.Parent(item.Node) or nil
			while ancestor do
				local acc = scrollers[ancestor]
				if acc then
					local host_ = rectOf[ancestor]
					if host_ then
						local relBottom = (item.Rect.Y + item.Rect.Height) - host_.Y
						local relRight = (item.Rect.X + item.Rect.Width) - host_.X
						if relBottom > acc.bottom then
							acc.bottom = relBottom
						end
						if relRight > acc.right then
							acc.right = relRight
						end
					end
					break
				end
				ancestor = Scene.Parent and Scene.Parent(ancestor) or nil
			end
		end
		for node, acc in pairs(scrollers) do
			local rect = rectOf[node]
			local canvasPos = Scene.Raw(node, "CanvasPosition")
			local cy = if canvasPos then (canvasPos.Y or 0) else 0
			local cx = if canvasPos then (canvasPos.X or 0) else 0
			--- Extents are measured in DISPLACED space, so the current scroll
			--- offset has to be added back to get the canvas in its own terms.
			Layout.SetCanvasExtent(node, acc.right + cx, acc.bottom + cy)
		end
	end

	visit(root, viewport, nil, 0)

	--- THE PRE-SCALE RECTANGLE, snapshotted BEFORE `applyScales` mutates it.
	---
	--- Four numbers written onto the record that already exists, so this allocates
	--- nothing. A reused entry is restored from these on the way back in, which is
	--- what stops a scaled subtree compounding its own scale every frame.
	if enabled then
		for _, item in ipairs(out) do
			local any: any = item
			any.BaseX, any.BaseY = item.Rect.X, item.Rect.Y
			any.BaseW, any.BaseH = item.Rect.Width, item.Rect.Height
		end
	end

	--- Scale BEFORE measuring canvases: a scaled child changes the extent its
	--- scrolling ancestor has to cover.
	applyScales()
	measureCanvases()

	--- PAINT ORDER IS HIERARCHICAL, NOT GLOBAL (ms-52 M5).
	---
	--- This sorted by ZIndex, then depth, then declaration -- treating ZIndex as a
	--- global layer. That is Roblox's LEGACY `ZIndexBehavior.Global`. Modern
	--- Roblox defaults to SIBLING, where a child always renders above its parent
	--- and ZIndex only orders siblings within one parent.
	---
	--- The difference is not academic. SettingsUI's `Window` carries a higher
	--- ZIndex than the rows inside it, so under a global sort the opaque 600x480
	--- window painted AFTER 25 of its own descendants and covered every one of
	--- them. Both real screens rendered as chrome around an empty interior, which
	--- read as content that had never been ported -- and `--audit` could not see
	--- it either, because every one of those nodes WAS delivered and WAS visible.
	--- They were just painted over.
	---
	--- Worse, `HitTest.RendersAbove` has always implemented Sibling correctly, so
	--- what could be CLICKED and what could be SEEN were ordered by different
	--- rules. This is now the same rule, deliberately spelled the same way:
	--- diverge along the shared path, compare ZIndex there, then child index; and
	--- if one is an ancestor of the other, the deeper one is on top.
	local pathOf: { [any]: { any } } = {}
	local childIndexOf: { [any]: number } = {}
	do
		for _, item in ipairs(out) do
			--- APPEND THEN REVERSE, never insert-at-front.
			---
			--- `table.insert(path, 1, n)` shifts the entire array on every
			--- ancestor, making each path O(depth^2). Appending is O(1) per step
			--- and one reverse costs depth/2 swaps, so the whole thing is O(depth)
			--- -- and the comparator below still gets the root-first array it wants,
			--- unchanged.
			local path = {}
			local n: any = item.Node
			while n do
				table.insert(path, n)
				n = if Scene.Parent then Scene.Parent(n) else nil
			end
			local lo, hi = 1, #path
			while lo < hi do
				path[lo], path[hi] = path[hi], path[lo]
				lo += 1
				hi -= 1
			end
			pathOf[item.Node] = path
		end
		--- Declaration index among siblings, read from the tree rather than from
		--- visit order: a list layout visits children in LayoutOrder, which is a
		--- POSITION concern and must not decide what paints on top.
		local seen: { [any]: boolean } = {}
		for _, item in ipairs(out) do
			local parent = if Scene.Parent then Scene.Parent(item.Node) else nil
			if parent and not seen[parent] then
				seen[parent] = true
				for i, child in ipairs(Scene.Children(parent)) do
					childIndexOf[child] = i
				end
			end
		end
	end

	table.sort(out, function(a, b)
		local pa, pb = pathOf[a.Node], pathOf[b.Node]
		local shared = math.min(#pa, #pb)
		for i = 1, shared do
			if pa[i] ~= pb[i] then
				local za, zb = Scene.ZIndex(pa[i]), Scene.ZIndex(pb[i])
				if za ~= zb then
					return za < zb
				end
				return (childIndexOf[pa[i]] or 0) < (childIndexOf[pb[i]] or 0)
			end
		end
		--- One contains the other: the ancestor paints first, so the descendant
		--- ends up on top.
		if #pa ~= #pb then
			return #pa < #pb
		end
		return a.Order < b.Order
	end)


	--- REMEMBER WHERE EACH SUBTREE ENDED UP.
	---
	--- Only the nodes actually re-solved this frame need their index refreshed;
	--- a skipped subtree was spliced in at a position the sort treats identically,
	--- and its stored `first` is corrected here alongside the others.
	---
	--- Done AFTER the paint-order sort, because the sort reorders `out` and the
	--- stored index has to describe the array as it is handed back.
	if enabled then
		local indexOf: { [any]: number } = {}
		for i, item in ipairs(out) do
			indexOf[item.Node] = i
		end
		--- EVERY node in the result, not only the ones re-solved: a skipped
		--- subtree can move within the array when a sibling before it grows or
		--- shrinks, and a stale `first` would splice the wrong entries next frame.
		for _, item in ipairs(out) do
			local e = cache[item.Node]
			if e then
				e.first = indexOf[item.Node]
			end
		end
		--- A node whose subtree is no longer contiguous after sorting cannot be
		--- spliced. Hierarchical paint order keeps a parent immediately before its
		--- descendants, but a sibling with a lower ZIndex can interleave, so this
		--- is verified rather than assumed.
		for _, node in ipairs(touched) do
			local e = cache[node]
			if e and (e.first + e.count - 1) > #out then
				cache[node] = nil
			end
		end
		previous = out
		previousRoot = root
		previousHost = host
	end

	return out
end

Layout.Intersect = intersect

return Layout
