--!strict
--[[
	PointerRouter: press, hover and cursor semantics owned by us, not by GuiButton.

	WHY (ms-43 M17)
	`GuiButton.Activated` is the only reason the engine ever needs a GuiButton in
	our tree — and a GuiButton drags the engine's own hover behaviour with it,
	including the forced cursor icon. There is no property that turns that off.
	So the button goes, and we reimplement the two things it was giving us:

	  1. CLICK SEMANTICS. `Activated` means "press began on me AND released on
	     me" — not "a click happened somewhere". That distinction is the whole
	     value of the event and is easy to get wrong by hand.
	  2. HOVER. MouseEnter/MouseLeave on a GuiObject fire when the pointer crosses
	     onto a CHILD, which is why usePointerTilt had to re-test the real pointer
	     position 0.05s later. A single resolver has no such problem: it asks
	     which element is topmost at a point, and children are not a special case.

	ONE GLOBAL LISTENER, NOT ONE PER ELEMENT
	Every Active GuiObject under the pointer receives InputBegan, so per-element
	handlers cannot tell who "owns" a press without comparing notes. The router
	instead connects UserInputService once and resolves the winner itself:

	    pointer -> topmost InputScope at that point   (cross-menu arbitration)
	            -> topmost registered surface in it   (intra-menu arbitration)

	which means a press can never be claimed by two elements, and an element
	under a modal barrier is simply never a candidate.

	CURSOR
	Because nothing in the tree is a GuiButton, the engine has no opinion, and the
	router sets UserInputService.MouseIcon from the hovered element's declared
	Cursor. Elements that declare none leave it alone.
]]

local isRoblox = typeof(game) == "Instance"

local Deps = require("./Deps")
local InputScope = require("./InputScope")
local HitTest = require("./HitTest")
local LayerManager = require("./LayerManager")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local Enum =
	Deps.Vocabulary.Enum

local source = Deps.source
local scopedCleanup = Deps.cleanup

local UserInputService = if isRoblox then (game :: any):GetService("UserInputService") else nil
local RunService = if isRoblox then (game :: any):GetService("RunService") else nil

export type PressableProps = {
	--- The InputScope this element lives in. Supplies depth and cross-menu
	--- arbitration; omit for an element outside any managed scope.
	Scope: any?,
	--- LayerManager layer name for a control that belongs to a layer but is NOT a
	--- window — a topbar button, a HUD affordance. Supplies depth when there is no
	--- Scope, so such a control ranks against menus by the same ordering
	--- everything else uses instead of falling to zero and losing to every modal.
	Layer: string?,
	--- SEMANTIC cursor name resolved through CoreInput.CursorPackProvider —
	--- "Pointer", "Grab", "Disabled", … — not an asset id. Omit to leave the
	--- cursor untouched while this element is hovered.
	---
	--- May be a getter, so a control can swap cursor with its own state (a
	--- disabled button asking for "Disabled", a track asking for "Grabbing"
	--- while held).
	Cursor: (string | () -> string)?,
	--- Fired when a press begins AND ends on this element.
	OnActivated: (() -> ())?,
	--- WHERE the press landed, in the same space the host lays out in (ms-53 D8).
	---
	--- Passed rather than looked up. A gesture that begins on a press needs the
	--- position to begin FROM, and every caller that had to fetch it separately
	--- reached for `InputScope.GetPointerPosition` -- a second source of truth for
	--- something this function already has in hand, and one that resolved
	--- differently under zune than under lune.
	---
	--- Additive: an `OnPressed` that ignores its arguments is unchanged.
	OnPressed: ((x: number, y: number) -> ())?,
	--- Also receive presses that land on a DESCENDANT (ms-53 D8).
	---
	--- The router resolves ONE record -- the topmost thing under the pointer --
	--- which is right for a click and wrong for a gesture that owns a REGION. A
	--- carousel is dragged from anywhere inside it, including from on top of the
	--- cards it contains; with single resolution the card wins and the carousel
	--- only ever saw the gaps between them.
	---
	--- Roblox gives this away for free: `InputBegan` propagates to every Active
	--- ancestor, so the same code dragged from anywhere in a place and only from
	--- the gaps in the native window. es9 found the difference immediately and
	--- named the standard it violates -- behaviour must be identical in both hosts
	--- or exist in neither.
	---
	--- OPT-IN, not automatic. A button inside a panel must NOT hand its press to
	--- the panel; only something that genuinely owns the region asks for this.
	ReceivesDescendantPress: boolean?,
	OnReleased: (() -> ())?,
	OnHoverChanged: ((hovered: boolean) -> ())?,
	--- Reactive. A disabled element is inert but still occludes, exactly like a
	--- greyed-out button.
	Disabled: (() -> boolean)?,
	--- INERT since ms-53 D8, and kept only so existing call sites still typecheck.
	---
	--- It used to decide whether `Bind` set `Active = true`. Nothing sets Active
	--- any more -- es9's rule, without exception -- so this now says nothing.
	--- Arbitration never depended on it: the router resolves geometrically from
	--- one global listener.
	HitTestable: boolean?,
	--- Should hover update when the CONTENT moves under a stationary pointer?
	--- Default true.
	---
	--- Roblox's MouseEnter/MouseLeave only fire in response to pointer movement,
	--- so an element that scrolls or animates out from under a still cursor stays
	--- "hovered" until the mouse twitches — and an element that slides UNDER the
	--- cursor never lights up at all. The router polls each frame instead, so
	--- hover follows geometry rather than input events.
	---
	--- Set false for an element that should only change hover state on a real
	--- pointer move: a drag handle whose highlight should not flicker as the
	--- thing it is dragging moves beneath it, for instance.
	LiveHover: boolean?,
	--- Rank within a scope. Higher wins. Defaults to 0; a scope's own barrier
	--- registers at -1 so every control inside the window outranks it.
	---
	--- This exists because raw ZIndex cannot be compared across different
	--- parents: under ZIndexBehavior.Sibling a child's ZIndex only orders it
	--- against its own siblings, so a button at ZIndex 10 inside a window is not
	--- "below" a barrier at ZIndex 100 in any meaningful sense.
	Priority: number?,
}

type PressRecord = {
	Seq: number,
	Scope: any?,
	Cursor: string?,
	Props: PressableProps,
	Surface: GuiObject?,
	IsHovered: any, -- source<boolean>
	IsPressed: any, -- source<boolean>
}

local records: { [PressRecord]: true } = {}
local seqCounter = 0

local pressedRecord: PressRecord? = nil
local hoveredRecord: PressRecord? = nil

-- Cursor authority. CoreInput.Mouse owns UserInputService.MouseIcon via a
-- priority stack (it caches and restores the player's default), so hover cursors
-- are pushed onto that stack rather than written directly — one writer, no
-- fighting. Above ordinary app pushes, below anything a drag or capture asserts.
local CURSOR_PRIORITY = 100
--- ms-51 M19: the cursor SEAM, not spektr/coreinput.
---
--- The division below is unchanged and still right — the router CHOOSES a cursor
--- and does not WRITE one, because Mouse owns UserInputService.MouseIcon through
--- a priority stack. What changed is the direction: Aether declared coreinput to
--- reach `Mouse.PushCursor`, and that edge was the last thing keeping VideShim
--- alive, since spektr/mouse could never depend on Aether for a real headless
--- vide without closing a cycle. CoreInput registers itself now. See Cursor.luau.
local Cursor = require("./Cursor")
local popCursor: (() -> ())? = nil

local PointerRouter = {}

-- Path cache, valid for ONE Resolve pass.
--
-- Ranking is pairwise, so without this a candidate's ancestor chain is rebuilt
-- once per comparison it takes part in. Candidates are few, but their paths are
-- the deepest thing we touch, and rebuilding them was pure waste.
local clearPathCache = HitTest.InvalidatePathCache
local pathOf = HitTest.PathOf
local rendersAbove = HitTest.RendersAbove

--- Sort key: scope depth, then explicit Priority, then ACTUAL RENDER ORDER.
---
--- Registration order used to be the final tie-break, on the assumption that
--- "declared later" means "on top". It does not, and es9 found where: ShopMenu
--- creates its close button's Pressable at the top of the component function,
--- while ItemCards create theirs while the carousel renders its children —
--- later. So a card underneath the close button outranked it and ate the click.
---
--- Registration order is not visual order, and no amount of per-element ZIndex
--- comparison fixes it either: under ZIndexBehavior.Sibling a child's ZIndex
--- orders it only against its own SIBLINGS. The only correct answer is to
--- compare the ancestor chains the way the engine does.
--- The DisplayOrder of the LayerCollector a control lives under.
---
--- This is what makes depth follow what is ACTUALLY on screen. LayerManager's
--- bands are DisplayOrder values, and a scope's depth is `band + STACK_BASE + n`,
--- so the two live in one number line by construction: a control in a
--- DisplayOrder 5000 ScreenGui reads 5000 and outranks a Windows modal's barrier
--- at 1101, exactly as it renders.
local function collectorDepth(rec: PressRecord): number
	local surface = rec.Surface
	if not surface then return 0 end
	-- pcall for the same reason `rendersAbove` uses one: an unparented element or
	-- a test double must fall through rather than take the resolver down.
	local ok, _, collector = pcall(pathOf, surface)
	if not ok or not collector then return 0 end
	local order = collector.DisplayOrder
	return if type(order) == "number" then order else 0
end

--- Ranking tier 1. A scope wins outright — it is the finest-grained answer, and
--- the only one that can order two windows in the same layer. Failing that, an
--- explicitly declared Layer. Failing THAT, where the control actually renders.
---
--- The fallback used to be 0, which meant "no scope" was read as "at the bottom".
--- A topbar button therefore lost to every open modal even though it rendered
--- above one, and the modal's barrier ate its click (M26). Declaring `Layer` on
--- the button fixed that case by hand; deriving the depth fixes the class, and a
--- control that is visibly on top now wins the click without being told to.
local function depthOf(rec: PressRecord): (number, number)
	local depth: number
	if rec.Scope then
		depth = rec.Scope.Depth()
	elseif rec.Props.Layer then
		depth = LayerManager.GetLayerDepth(rec.Props.Layer)
	else
		depth = collectorDepth(rec)
	end
	local priority = rec.Props.Priority or 0
	return depth, priority
end

local function outranks(a: PressRecord, b: PressRecord): boolean
	local ad, ap = depthOf(a)
	local bd, bp = depthOf(b)
	if ad ~= bd then return ad > bd end
	if ap ~= bp then return ap > bp end

	if a.Surface and b.Surface then
		-- pcall: an unparented element, or a test double without GetChildren,
		-- must fall through rather than take the resolver down.
		local ok, above = pcall(rendersAbove, a.Surface, b.Surface)
		if ok then
			return above
		end
	end

	-- Last resort only: nothing renderable to compare.
	return a.Seq > b.Seq
end

--- The element that owns this point, or nil.
--- The element that owns this point, or nil.
---
--- ORDERED CHEAPEST-TEST-FIRST. The registry grows with the UI — the Showcase's
--- live-hover lanes alone add 48 controls — and this runs every frame, so the
--- work per non-candidate has to stay near zero:
---
---   1. nil / unparented          field reads
---   2. raw rect                  4 comparisons, NO ancestor walk. Sound as an
---                                early-out because clipping only shrinks the
---                                hit area, so a raw miss is a definite miss.
---                                This is what rejects almost everything.
---   3. Disabled()                one call, only for things under the pointer
---   4. visibility + clipping     ONE fused ancestor walk (it was two)
---   5. scope ownership           only for survivors
---   6. ranking                   pairwise, over the handful that remain, with
---                                ancestor paths cached for the pass
---
--- The deep work is therefore proportional to how many elements actually overlap
--- the pointer — typically one to three — not to how many are registered.
function PointerRouter.Resolve(x: number, y: number): PressRecord?
	clearPathCache()

	-- Gather candidates before consulting InputScope: the scope query walks its
	-- own registry, and there is no reason to pay for it when nothing is under
	-- the pointer at all.
	local candidates: { PressRecord }? = nil

	for rec in pairs(records) do
		local surface = rec.Surface
		if not surface or not surface.Parent then continue end
		if not HitTest.RawContains(surface, x, y) then continue end
		if rec.Props.Disabled and rec.Props.Disabled() then continue end
		if not HitTest.ContainsVisible(surface, x, y) then continue end

		if not candidates then
			candidates = {}
		end
		table.insert(candidates :: { PressRecord }, rec)
	end

	if not candidates then
		return nil
	end

	local list = candidates :: { PressRecord }
	local owningScope = InputScope.HitTest(x, y)

	if #list == 1 then
		local only = list[1]
		-- Still has to clear cross-menu arbitration: a lone control beneath an
		-- open modal must not win.
		if owningScope then
			if only.Scope then
				if only.Scope.Id ~= owningScope then
					return nil
				end
			elseif only.Surface and not InputScope.IsSurfaceInScope(only.Surface, owningScope) then
				return nil
			end
		end
		return only
	end

	local best: PressRecord? = nil
	for _, rec in ipairs(list) do
		if owningScope then
			if rec.Scope then
				if rec.Scope.Id ~= owningScope then continue end
			elseif rec.Surface and not InputScope.IsSurfaceInScope(rec.Surface, owningScope) then
				continue
			end
		end
		if not best or outranks(rec, best) then
			best = rec
		end
	end
	return best
end

-- ═══════════════════════════════════════════════════════════════
-- "Is the pointer really over this?" — for surfaces that are NOT controls
-- ═══════════════════════════════════════════════════════════════
-- A display card is not Pressable: it sinks nothing and claims no click. But it
-- still reacts to hover, and anything that reacts to hover needs the same answer
-- a control gets, or it lights up through a topbar drawn over it and through the
-- edge of the ScrollingFrame that clips it.
--
-- Both of those were live. Flux's usePointerTilt tested a RAW RECT — pointer
-- inside my bounds? — which is the question `RawContains` exists to answer
-- cheaply and never to answer alone.

--- Per-frame memo. Every tilt card polls the same pointer position on the same
--- Heartbeat, so without this the Showcase's eighteen cards each pay for a full
--- Resolve. Stamped rather than merely coordinate-keyed, so a frame where the
--- pointer has not moved but the CONTENT has still re-resolves.
local frameStamp = 0
local ownerStamp = -1
local ownerX, ownerY = math.huge, math.huge
local ownerRec: PressRecord? = nil

--- Drop the memo. Called on every registry mutation as well as every frame: a
--- control that registers or disposes MID-frame changes the answer, and a memo
--- keyed on time alone would happily serve the pre-registration result. Found by
--- the M28 test, which registers a covering control between two queries at the
--- same point — exactly what a window opening under a still pointer does.
local function invalidateOwnerMemo()
	ownerStamp = -1
end

local function resolveOwner(x: number, y: number): PressRecord?
	if ownerStamp == frameStamp and ownerX == x and ownerY == y then
		return ownerRec
	end
	ownerRec = PointerRouter.Resolve(x, y)
	ownerStamp, ownerX, ownerY = frameStamp, x, y
	return ownerRec
end

local function isDescendantOf(node: any, ancestor: any): boolean
	local cur = node
	while cur do
		if cur == ancestor then return true end
		cur = cur.Parent
	end
	return false
end

--- Per-frame callbacks for things that derive state from the pointer but are not
--- controls — hover on a display surface, most obviously.
---
--- ms-43 M32. THE ONE-GLOBAL-LISTENER RULE IN THIS FILE'S HEADER APPLIES TO
--- POLLING TOO, and useHover broke it: it opened a Heartbeat connection per bound
--- element, so a board of fifty cards meant fifty connections and fifty
--- independent frame callbacks, against the router's one. es9 asked whether these
--- primitives compose without redundancy at scale; they did not, and this is the
--- gap.
---
--- Observers also land AFTER the router's own hover pass, which means every
--- IsPointerOver they call in the same frame hits the resolve memo instead of
--- re-resolving. Fifty cards therefore cost fifty rect tests and ONE resolve.
local frameObservers: { [any]: () -> () } = {}

--- Register a callback to run once per frame. Returns an unsubscribe.
function PointerRouter.OnFrame(fn: () -> ()): () -> ()
	local key = {}
	frameObservers[key] = fn
	return function()
		frameObservers[key] = nil
	end
end

--- Run one frame of the observer bus. Test seam: headless there is no Heartbeat,
--- and the bus is exactly the part that must be provably shared.
function PointerRouter._SimulateFrame()
	frameStamp += 1
	for _, fn in pairs(frameObservers) do
		pcall(fn)
	end
end

--- How many observers are registered. Test seam.
function PointerRouter._ObserverCount(): number
	local n = 0
	for _ in pairs(frameObservers) do
		n += 1
	end
	return n
end

--- Does the pointer reach `surface` at this point — visible, unclipped, and not
--- covered by anything that renders above it?
---
--- Exposed for surfaces outside the router's own registry; Flux registers it as
--- its hover resolver so tilt cards answer hover the same way controls do,
--- without Flux depending on Aether (the seam, not the package).
function PointerRouter.IsPointerOver(surface: GuiObject?, x: number, y: number): boolean
	if not surface or not surface.Parent then return false end
	local owningScope = InputScope.HitTest(x, y)
	if owningScope and not InputScope.IsSurfaceInScope(surface, owningScope) then
		return false
	end

	-- Clipping and visibility, one fused ancestor walk. This alone fixes a card
	-- scrolled out of its ScrollingFrame still tilting when you hover the empty
	-- space where it would have been.
	if not HitTest.ContainsVisible(surface, x, y) then return false end

	local owner = resolveOwner(x, y)
	local ownerSurface = owner and owner.Surface
	if not ownerSurface or ownerSurface == surface then return true end
	-- A control INSIDE the card (its own button) is not something covering the
	-- card — the card should keep tilting while you reach for it.
	if isDescendantOf(ownerSurface, surface) then return true end

	local ok, above = pcall(rendersAbove, ownerSurface, surface)
	return not (ok and above)
end

local hoveredRecord: PressRecord? = nil
local hoveredSet: { [PressRecord]: boolean } = {}

local function setHovered(rec: PressRecord?)
	if rec == hoveredRecord then return end
	hoveredRecord = rec

	-- Build active hover set: topmost leaf + all ancestor PressRecords whose surface contains the leaf
	local newSet: { [PressRecord]: boolean } = {}
	if rec then
		newSet[rec] = true
		if rec.Surface then
			for otherRec in pairs(records) do
				if otherRec ~= rec and otherRec.Surface and otherRec.Surface.Parent then
					if isDescendantOf(rec.Surface, otherRec.Surface) then
						newSet[otherRec] = true
					end
				end
			end
		end
	end

	-- Deactivate records that are no longer in newSet
	for prevRec in pairs(hoveredSet) do
		if not newSet[prevRec] then
			prevRec.IsHovered(false)
			if prevRec.Props.OnHoverChanged then
				prevRec.Props.OnHoverChanged(false)
			end
		end
	end

	-- Activate records that newly entered newSet
	for nextRec in pairs(newSet) do
		if not hoveredSet[nextRec] then
			nextRec.IsHovered(true)
			if nextRec.Props.OnHoverChanged then
				nextRec.Props.OnHoverChanged(true)
			end
		end
	end

	hoveredSet = newSet

	-- Cursor is ours to CHOOSE because nothing here is a GuiButton, but not ours
	-- to WRITE: CoreInput.Mouse owns UserInputService.MouseIcon through a
	-- priority stack that caches and restores the player's default, so a second
	-- direct writer would fight it. The router resolves a SEMANTIC name through
	-- the active cursor pack and pushes the result like any other client.
	if popCursor then
		popCursor()
		popCursor = nil
	end
	if rec and Cursor.HasProvider() then
		local name: any = rec.Cursor
		-- If leaf has no cursor declared, check ancestors from bottom up
		if name == nil and rec.Surface then
			local cur = rec.Surface.Parent
			while cur do
				for ancestorRec in pairs(newSet) do
					if ancestorRec.Surface == cur and ancestorRec.Cursor ~= nil then
						name = ancestorRec.Cursor
						break
					end
				end
				if name ~= nil then break end
				cur = cur.Parent
			end
		end

		if name ~= nil then
			if type(name) == "function" then
				local ok, resolved = pcall(name)
				name = if ok then resolved else nil
			end
			if name ~= nil then
				-- Pack resolution, the node-vs-image choice and the priority default
				-- all moved into the seam, which is where they belong: they are the
				-- cursor OWNER's rules, not the router's.
				popCursor = Cursor.Push(name, CURSOR_PRIORITY)
			end
		end
	end
end

local function pointerPosition(input: any): (number, number)
	if input and input.Position then
		local x, y = InputScope.GetPointerPosition()
		-- Touch reports absolute screen coordinates like the mouse; reuse the
		-- inset-corrected path so both agree.
		if input.UserInputType == Enum.UserInputType.Touch then
			return input.Position.X, input.Position.Y
		end
		return x, y
	end
	return InputScope.GetPointerPosition()
end
--- Hand the press up to any ANCESTOR that asked for it (ms-53 D8).
---
--- Walks the surface chain from the resolved target upward. Registration order
--- is irrelevant: the walk is over the TREE, so a region receives its
--- descendants' presses however late either was registered.
---
--- The scope check is deliberately not repeated here -- the target already
--- cleared arbitration in `Resolve`, and an ancestor of something in scope is in
--- the same scope by construction.
local function dispatchAncestorPress(target: PressRecord, x: number, y: number)
	local surface = target.Surface
	if not surface then
		return
	end
	local Scene = Deps.Host and Deps.Host.Scene
	if not Scene or not Scene.Parent then
		return
	end
	local cur: any = Scene.Parent(surface)
	while cur do
		for rec in pairs(records) do
			if rec ~= target and rec.Surface == cur and rec.Props.ReceivesDescendantPress then
				if not (rec.Props.Disabled and rec.Props.Disabled()) and rec.Props.OnPressed then
					rec.Props.OnPressed(x, y)
				end
			end
		end
		cur = Scene.Parent(cur)
	end
end


local function onInputBegan(input: any, gameProcessed: boolean)
	local _ = gameProcessed
	if not (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch) then
		return
	end

	local x, y = pointerPosition(input)
	local target = PointerRouter.Resolve(x, y)
	if not target then return end

	pressedRecord = target
	target.IsPressed(true)
	if target.Props.OnPressed then
		target.Props.OnPressed(x, y)
	end
	dispatchAncestorPress(target, x, y)
end

--- THE GLOBAL RELEASE, for gestures that outlive the element they began on.
---
--- WHY (ms-52 M5)
--- `OnReleased` on a Pressable is the right answer for a BUTTON: it fires on the
--- record the press began on, wherever the release lands. A swipe is different --
--- ShopUI's carousels track a drag across the whole screen and only care where
--- the pointer came up -- and every one of them answered that with its own
--- `UserInputService.InputEnded` connection.
---
--- Same shape as OnPointerMove and OnWheel: the router already owns the single
--- engine connection, so this exposes a signal that existed rather than adding a
--- source of truth.
local releaseObservers: { [any]: (x: number, y: number) -> () } = {}

--- Register a callback for pointer RELEASE, anywhere. Returns an unsubscribe.
function PointerRouter.OnPointerUp(fn: (x: number, y: number) -> ()): () -> ()
	local key = {}
	releaseObservers[key] = fn
	return function()
		releaseObservers[key] = nil
	end
end

local function notifyRelease(x: number, y: number)
	for _, fn in pairs(releaseObservers) do
		pcall(fn, x, y)
	end
end

--- How many release observers are registered. Test seam.
function PointerRouter._ReleaseObserverCount(): number
	local n = 0
	for _ in pairs(releaseObservers) do
		n += 1
	end
	return n
end

local function onInputEnded(input: any)
	if not (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch) then
		return
	end

	--- Observers first, and unconditionally: a swipe that began on nothing still
	--- ends, and returning early when no element was pressed would drop it.
	do
		local rx, ry = pointerPosition(input)
		notifyRelease(rx, ry)
	end

	local target = pressedRecord
	pressedRecord = nil
	if not target then return end

	target.IsPressed(false)
	if target.Props.OnReleased then
		target.Props.OnReleased()
	end

	-- Activation requires the release to land on the SAME element the press
	-- began on — the actual contract of GuiButton.Activated, and the part a
	-- hand-rolled InputEnded handler usually gets wrong.
	local x, y = pointerPosition(input)
	if PointerRouter.Resolve(x, y) == target and target.Props.OnActivated then
		target.Props.OnActivated()
	end
end

--- Re-resolve which element the pointer is over.
---
--- `fromMovement` distinguishes the two reasons hover can change: the pointer
--- moved, or the CONTENT moved. Roblox only ever reports the first, which is why
--- an element that scrolls out from under a still cursor stays lit and one that
--- slides under it never does. Polling covers the second — and `LiveHover =
--- false` is how an element opts out of it.
--- WHERE THE POINTER IS, for the things that need it BETWEEN press and release.
---
--- WHY (ms-52 M2)
--- Press and release are discrete and the router already arbitrates both. DRAG is
--- neither: a scrollbar thumb, a slider and a window titlebar all need to know
--- where the pointer went while it was held, and every one of them answered that
--- by opening its OWN `UserInputService.InputChanged` connection.
---
--- That made drag the one interaction that was NOT portable. The second host
--- caught it exactly as intended: a real ScrollingFrame's thumb registered with
--- the router, hit-tested correctly, pressed correctly -- and then did not move,
--- because off-engine `UserInputService` is nil and the whole drag path was
--- behind `if UserInputService then`. Press flowed through Aether; drag never had.
---
--- The router is already the single input authority in Roblox (it connects
--- UserInputService ONCE, above) so this is not a new source of truth -- it is the
--- existing one, finally exposed. A primitive that reads pointer movement from
--- here behaves identically in both hosts, and costs one shared connection rather
--- than one per draggable element.
local pointerObservers: { [any]: (x: number, y: number) -> () } = {}

--- Register a callback for pointer MOVEMENT. Returns an unsubscribe.
---
--- Only genuine movement, not the geometry-driven poll: a drag tracks the
--- POINTER, and firing it when content moved underneath would feed the element
--- its own motion back as input.
function PointerRouter.OnPointerMove(fn: (x: number, y: number) -> ()): () -> ()
	local key = {}
	pointerObservers[key] = fn
	return function()
		pointerObservers[key] = nil
	end
end

--- THE WHEEL, for the same reason as OnPointerMove (ms-52 M3).
---
--- ScrollArea opened its own `UserInputService.InputChanged` and filtered for
--- MouseWheel, so wheel scrolling was the second interaction that existed only in
--- Roblox. Its target RESOLUTION was already portable -- topmost scrollable under
--- the pointer -- which is what made the omission invisible: everything around
--- the input was host-agnostic except the input.
---
--- `delta` is in SCROLL STEPS, positive meaning the content should move up (the
--- direction a user calls "scrolling down"). Roblox reports `Position.Z` with the
--- opposite sign and a browser reports pixels in `deltaY`; both are normalised at
--- their edge, so nothing downstream has to know which host it is in.
local wheelObservers: { [any]: (x: number, y: number, delta: number) -> () } = {}

--- Register a callback for wheel input. Returns an unsubscribe.
function PointerRouter.OnWheel(fn: (x: number, y: number, delta: number) -> ()): () -> ()
	local key = {}
	wheelObservers[key] = fn
	return function()
		wheelObservers[key] = nil
	end
end

--- Feed one wheel event. Hosts call this; in Roblox the router's own listener does.
function PointerRouter._SimulateWheel(x: number, y: number, delta: number)
	InputScope.SetPointerPosition(x, y)
	for _, fn in pairs(wheelObservers) do
		pcall(fn, x, y, delta)
	end
end

--- How many wheel observers are registered. Test seam.
function PointerRouter._WheelObserverCount(): number
	local n = 0
	for _ in pairs(wheelObservers) do
		n += 1
	end
	return n
end

--- How many movement observers are registered. Test seam.
function PointerRouter._PointerObserverCount(): number
	local n = 0
	for _ in pairs(pointerObservers) do
		n += 1
	end
	return n
end

local function refreshHover(fromMovement: boolean?, atX: number?, atY: number?)
	local x, y = atX, atY
	if not x or not y then
		x, y = InputScope.GetPointerPosition()
	end
	if fromMovement and x >= 0 then
		--- pcall: a listener that throws must not take down hover arbitration for
		--- every other element on the screen.
		for _, fn in pairs(pointerObservers) do
			pcall(fn, x, y)
		end
	end
	if x < 0 then
		setHovered(nil)
		return
	end

	local resolved = PointerRouter.Resolve(x, y)

	if not fromMovement and resolved ~= hoveredRecord then
		-- A geometry-driven change. Either side may refuse it.
		--
		-- LiveHover = false: the element opted out entirely.
		--
		-- An UNSETTLED scope: the window is mid enter/exit, so its controls are
		-- sweeping past a stationary pointer under their own power. Reporting each
		-- as hovered is technically true and practically wrong — it fires hover
		-- feedback the user never asked for, which is how closing the Showcase
		-- came to play a hover sound as it flew off the cursor. Hover answers user
		-- intent; a window animating itself across the pointer is not intent.
		local function refuses(rec: PressRecord?): boolean
			if not rec then return false end
			if rec.Props.LiveHover == false then return true end
			return rec.Scope ~= nil and not rec.Scope.IsSettled()
		end
		if refuses(hoveredRecord) or refuses(resolved) then
			return
		end
	end

	setHovered(resolved)
end

if UserInputService then
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	UserInputService.InputChanged:Connect(function(input: any)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			refreshHover(true) -- the pointer moved: every element listens
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			--- One connection for every scrollable on screen, and the sign
			--- normalised here so no primitive has to know Roblox's convention.
			local wx, wy = InputScope.GetPointerPosition()
			PointerRouter._SimulateWheel(wx, wy, -input.Position.Z)
		end
	end)
end

if RunService then
	-- LIVE HOVER. Movement alone is not enough: a list can scroll, a card can
	-- animate, a window can open or close under a completely stationary cursor,
	-- and the element under the pointer changes with no input event to announce
	-- it. Roblox's own MouseEnter/MouseLeave never fire in that case, which is
	-- why UI built on them "sticks" hovered until you jiggle the mouse.
	--
	-- Polling makes hover a function of geometry rather than of input events.
	-- Cost is one Resolve per frame — a rect test per registered control, with
	-- an early-out when nothing is registered.
	RunService.Heartbeat:Connect(function()
		-- Advance first, and unconditionally: IsPointerOver's memo must expire
		-- even on frames where nothing is registered and hover does no work.
		frameStamp += 1

		if next(records) ~= nil then
			refreshHover(false)
		end

		-- Observers run even when no CONTROL is registered: a screen may be
		-- nothing but display surfaces. They run AFTER refreshHover so they share
		-- its resolve memo for this frame rather than forcing a second pass.
		for _, fn in pairs(frameObservers) do
			-- pcall so one bad observer cannot take hover down for everything
			-- else. Cheap next to the hit test it is about to do.
			pcall(fn)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════
-- Registration
-- ═══════════════════════════════════════════════════════════════

export type PressableHandle = {
	--- Vide.action target. Marks the element Active and registers it.
	Bind: (rbx: GuiObject?) -> (),
	IsHovered: () -> boolean,
	IsPressed: () -> boolean,
	Destroy: () -> (),
}

function PointerRouter.Pressable(props: PressableProps): PressableHandle
	seqCounter += 1
	local record: PressRecord = {
		Seq = seqCounter,
		Scope = props.Scope,
		Cursor = props.Cursor,
		Props = props,
		Surface = nil,
		IsHovered = source(false),
		IsPressed = source(false),
	}
	records[record] = true
	invalidateOwnerMemo()

	local destroyed = false
	local function destroy()
		if destroyed then return end
		destroyed = true
		records[record] = nil
		invalidateOwnerMemo()
		if hoveredRecord == record or hoveredSet[record] then
			hoveredSet[record] = nil
			if hoveredRecord == record then
				hoveredRecord = nil
			end
			record.IsHovered(false)
			if record.Props.OnHoverChanged then
				record.Props.OnHoverChanged(false)
			end
		end
		if pressedRecord == record then pressedRecord = nil end
	end
	scopedCleanup(destroy)

	return {
		Bind = function(rbx: GuiObject?)
			if not rbx then return end
			--- NOTHING IS EVER `Active` (ms-53 D8). es9's rule, stated without
			--- exception: `Active` must never be used, in any circumstance.
			---
			--- The old comment here argued Active was "only for CONTROLS", to sink
			--- input away from the 3D world and from any GuiButton beneath. Both
			--- are the ENGINE's arbitration, and this framework does its own: the
			--- router resolves geometrically from one global listener, so it never
			--- needed the engine to deliver an event to a particular Instance.
			---
			--- What Active actually bought was a second, invisible arbiter with
			--- different rules -- it changes the cursor, marks input
			--- `gameProcessed`, and decides which Instance receives `InputBegan`.
			--- Every remaining consumer of that last behaviour has moved to the
			--- router: the slider, the carousel, the hero banner, and
			--- `useGestureMotion.BindTrack`, which needed it and now does not.
			record.Surface = rbx
		end,
		IsHovered = function(): boolean
			return record.IsHovered()
		end,
		IsPressed = function(): boolean
			return record.IsPressed()
		end,
		Destroy = destroy,
	}
end

--- Live registration count. For gates and diagnostics.
--- WHY DID NOTHING RESOLVE HERE? (ms-53 D8)
---
--- `Resolve` drops a candidate at one of three places -- the raw rect, the
--- rounded corner, or the visibility walk that intersects every clipping
--- ancestor and must terminate at an enabled layer root -- and from OUTSIDE the
--- router all three are indistinguishable from the record not existing.
---
--- That is not only a debugging convenience. Three rounds of diagnosing a
--- Roblox-only input failure from off-engine produced three wrong answers,
--- because the only observable was "resolved: false". A router that can explain
--- itself turns that into one round.
---
--- Returns one entry per registered surface whose RECT contains the point, most
--- recently registered first, with the ancestor chain named.
function PointerRouter._Explain(x: number, y: number): { any }
	local Scene = Deps.Host and Deps.Host.Scene
	local out = {}
	for rec in pairs(records) do
		local surface = rec.Surface
		if surface and HitTest.RawContains(surface, x, y) then
			local chain = {}
			if Scene and Scene.Parent then
				local cur: any = surface
				while cur and #chain < 8 do
					table.insert(chain, tostring(Scene.Name(cur) or "?"))
					cur = Scene.Parent(cur)
				end
			end
			table.insert(out, {
				Name = Scene and Scene.Name(surface) or "?",
				Parented = surface.Parent ~= nil,
				Rounded = HitTest.RoundedContains(surface, x, y),
				Visible = HitTest.ContainsVisible(surface, x, y),
				Disabled = rec.Props.Disabled ~= nil and rec.Props.Disabled() or false,
				Chain = table.concat(chain, " < "),
			})
		end
	end
	return out
end

--- Every registered record, as an array. Test seam, and the seam a HOST needs to
--- explain itself: from outside the engine there is no way to ask why a press
--- resolved to nothing, and the three stages `Resolve` drops a candidate at are
--- indistinguishable from their absence (ms-53 D8).
function PointerRouter._Records(): { any }
	local out = {}
	for rec in pairs(records) do
		table.insert(out, rec)
	end
	return out
end

function PointerRouter._Count(): number
	local n = 0
	for _ in pairs(records) do n += 1 end
	return n
end

--- Test seam: drive the router without a DataModel.
function PointerRouter._SimulatePress(x: number, y: number)
	InputScope.SetPointerPosition(x, y)
	local target = PointerRouter.Resolve(x, y)
	if not target then return end
	pressedRecord = target
	target.IsPressed(true)
	if target.Props.OnPressed then target.Props.OnPressed(x, y) end
	dispatchAncestorPress(target, x, y)
end

function PointerRouter._SimulateRelease(x: number, y: number)
	InputScope.SetPointerPosition(x, y)
	notifyRelease(x, y)
	local target = pressedRecord
	pressedRecord = nil
	if not target then return end
	target.IsPressed(false)
	if target.Props.OnReleased then target.Props.OnReleased() end
	if PointerRouter.Resolve(x, y) == target and target.Props.OnActivated then
		target.Props.OnActivated()
	end
end

--- A genuine pointer move: every element re-evaluates.
function PointerRouter._SimulateHover(x: number, y: number)
	InputScope.SetPointerPosition(x, y)
	refreshHover(true, x, y)
end

--- The pointer did NOT move, but the content did — one Heartbeat tick's worth of
--- live-hover polling. This is the case Roblox never reports and the reason the
--- router polls at all.
function PointerRouter._SimulateGeometryChange(x: number, y: number)
	refreshHover(false, x, y)
end

--- THE HOST INPUT SURFACE (ms-51 M22).
---
--- The four functions above have carried a `_Simulate` prefix since they were
--- written, because for a long time a test harness was the only thing that could
--- call them. That was never true of the ROUTER: it has no opinion about where a
--- coordinate came from, which is exactly what makes it host-agnostic.
---
--- With a second host actually driving real input, the prefix became misleading —
--- it reads as scaffolding, and scaffolding gets deleted. This is the same
--- functions under the name that describes what they now are. The `_Simulate`
--- spellings stay so the suites do not churn, and because in a SUITE they really
--- are simulating.
PointerRouter.Input = {
	Move = PointerRouter._SimulateHover,
	Press = PointerRouter._SimulatePress,
	Release = PointerRouter._SimulateRelease,
	--- The pointer did not move but the content did. Roblox never reports this,
	--- which is why the router polls; a host that drives frames must pump it.
	Settle = PointerRouter._SimulateGeometryChange,
	Frame = PointerRouter._SimulateFrame,
	--- Wheel input, in scroll steps; positive scrolls the content up.
	Wheel = PointerRouter._SimulateWheel,
}

return PointerRouter
