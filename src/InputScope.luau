--!strict
--[[
	InputScope: layered pointer arbitration for stacked and nested UI.

	THE PROBLEM (ms-43 M16)
	Roblox only hit-tests a GuiObject if it is a GuiButton or has Active = true.
	A window built out of plain Frames is therefore INVISIBLE to the hit-test:
	clicks on its "empty" areas fall straight through to whatever sits behind it.
	The Showcase menu made that visible — it wants click-the-backdrop-to-close, so
	every click on a panel closed the window.

	The old InputSink could not fix this. It reported hover into a module-scope
	REFCOUNT (`InputContextManager.mouseOverCount`), which answers "is the pointer
	over some UI?" but never "WHICH UI owns this click?". Occlusion is an ordering
	question, and a counter has no order. Worse, three notions of "on top"
	coexisted and none agreed: LayerManager's DisplayOrder/stacks (which had zero
	call sites), Roblox's own hit-test, and that refcount.

	THE APPROACH: one ordering, and answer every question from it geometrically.

	LayerManager.Allocate gives each scope a depth slot. A MODAL scope renders a
	full-screen barrier at `BarrierDepth`, immediately below its own content and
	above every lower scope, and registers its content bounds here. Every question
	is then resolved from that registry rather than from the engine:

	    did this click land outside the window?  ContainsPoint
	    should the GAME process this input?      IsPointerOverUI
	    which menu owns this point?              HitTest  (PointerRouter uses it
	                                             to discard controls under a modal)

	NOTHING HERE IS Active (ms-43 M17). An earlier cut relied on `Active = true`
	to make the engine occlude the barrier under the window; it did not hold in
	engine, and Active also sinks input away from the 3D world, which a backdrop
	or a window body has no business doing. Only real controls are Active now —
	see PointerRouter — and arbitration does not depend on it either way.

	POLICIES
	  Modal  barrier + surface. Blocks the whole stack below. Dismissable.
	  Block  surface only. Consumes its own bounds; the world behind stays live.
	  Pass   registration only. Participates in ordering, consumes nothing —
	         for a HUD element that should never eat a click.
]]

local isRoblox = typeof(game) == "Instance"

local Deps = require("./Deps")
local LayerManager = require("./LayerManager")
local HitTest = require("./HitTest")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, Vector2, Color3, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.Vector2, Deps.Vocabulary.Color3, Deps.Vocabulary.Enum

local vide = Deps.vide
local scopedCleanup = Deps.cleanup

local UserInputService = if isRoblox then (game :: any):GetService("UserInputService") else nil
local GuiService = if isRoblox then (game :: any):GetService("GuiService") else nil
local ContextActionService = if isRoblox then (game :: any):GetService("ContextActionService") else nil

export type ScopePolicy = "Modal" | "Block" | "Pass"

export type ValueOrGetter<T> = T | (() -> T)

export type InputScopeProps = {
	--- Stable identity. Reusing an id re-uses its depth slot.
	Id: string,
	--- LayerManager layer name. Defaults to "Windows".
	Layer: string?,
	--- Defaults to "Block".
	Policy: ScopePolicy?,
	--- Reactive visibility. An invisible scope neither blocks nor consumes.
	Visible: ValueOrGetter<boolean>?,
	--- Modal only: called when the barrier is clicked.
	OnDismiss: (() -> ())?,
	--- Is this scope at rest, i.e. NOT mid enter/exit transition? Default: always.
	---
	--- While a window animates, its controls sweep past a stationary pointer, and
	--- live hover faithfully reports each one as hovered — firing hover feedback
	--- the user never asked for. Hover should answer user intent; a window flying
	--- itself across the cursor is not intent. The router suppresses
	--- GEOMETRY-driven hover changes for an unsettled scope, while a real pointer
	--- move still resolves normally.
	IsSettled: (() -> boolean)?,
	--- Modal only: barrier tint. Reactive, so an entrance transition can fade the
	--- dim in without a second overlapping Frame. Omit for a clear barrier.
	DimTransparency: ValueOrGetter<number>?,
	DimColor: ValueOrGetter<Color3>?,
	--- Optional explicit priority override.
	Priority: ValueOrGetter<number>?,
}

type ScopeRecord = {
	Id: string,
	Policy: ScopePolicy,
	Depth: () -> number,
	Priority: (() -> number)?,
	IsVisible: () -> boolean,
	Surfaces: { GuiObject },
}

-- The registry. Module-scope by necessity: pointer arbitration is a property of
-- the whole screen, not of any one component. Keyed by record so a scope can be
-- removed in O(1) without disturbing the others' identities.
local records: { [ScopeRecord]: true } = {}

local InputScope = {}

local function resolve<T>(val: ValueOrGetter<T>?, fallback: T): T
	if type(val) == "function" then
		local v = (val :: any)()
		return if v == nil then fallback else v
	end
	return if val == nil then fallback else (val :: any)
end

--- Does this scope consume pointer input where it covers?
local function consumes(rec: ScopeRecord): boolean
	return rec.Policy == "Modal" or rec.Policy == "Block"
end

--- Does scope A outrank scope B at the tested point?
local function scopeOutranks(
	recA: ScopeRecord,
	hitSurfaceA: GuiObject?,
	recB: ScopeRecord,
	hitSurfaceB: GuiObject?
): boolean
	-- 1. Explicit priority override
	local prioA = if recA.Priority then recA.Priority() else nil
	local prioB = if recB.Priority then recB.Priority() else nil
	if prioA and prioB and prioA ~= prioB then
		return prioA > prioB
	elseif prioA and not prioB then
		return true
	elseif prioB and not prioA then
		return false
	end

	-- 2. Visual DOM Render Order comparison (DisplayOrder -> divergence sibling ZIndex -> sibling childIndex -> descendant)
	if hitSurfaceA and hitSurfaceB and hitSurfaceA ~= hitSurfaceB then
		local ok, above = pcall(HitTest.RendersAbove, hitSurfaceA, hitSurfaceB)
		if ok then
			local okRev, revAbove = pcall(HitTest.RendersAbove, hitSurfaceB, hitSurfaceA)
			if okRev and (above or revAbove) then
				return above
			end
		end
	end

	-- 3. Fallback to LayerManager allocated depth
	return recA.Depth() > recB.Depth()
end

-- ═══════════════════════════════════════════════════════════════
-- Arbitration
-- ═══════════════════════════════════════════════════════════════

--- The topmost scope whose surface covers (x, y), or nil.
---
--- A Modal scope covers the WHOLE screen regardless of its surfaces: that is
--- what modal means, and it is why a modal window's barrier answers for the
--- empty space around it.
--- One step up the scene tree, through the host.
local function parentOf(node: any): any
	local Scene = Deps.Host and Deps.Host.Scene
	if not Scene or not Scene.Parent then
		return nil
	end
	return Scene.Parent(node)
end

--- Is `ancestor` above `node` in the scene tree? Walks through the HOST, so it
--- answers the same question in a place and in a headless host (ms-53 D8).
local function isAncestorOf(ancestor: any, node: any): boolean
	if ancestor == nil or node == nil then
		return false
	end
	local Scene = Deps.Host and Deps.Host.Scene
	if not Scene or not Scene.Parent then
		return false
	end
	local cur: any = Scene.Parent(node)
	local guard = 0
	while cur and guard < 64 do
		if cur == ancestor then
			return true
		end
		cur = Scene.Parent(cur)
		guard += 1
	end
	return false
end

function InputScope.HitTest(x: number, y: number): string?
	local bestRec: ScopeRecord? = nil
	local bestSurface: GuiObject? = nil

	for rec in pairs(records) do
		if not rec.IsVisible() then continue end
		if not consumes(rec) then continue end

		local hit = false
		local hitSurface: GuiObject? = nil

		if rec.Policy == "Modal" then
			hit = true
			hitSurface = rec.Surfaces[1]
		else
			for _, surface in ipairs(rec.Surfaces) do
				-- ContainsVisible does the raw-rect early-out itself and fuses the
				-- visibility and clipping walks into one (ms-43 M22).
				if surface.Parent and HitTest.ContainsVisible(surface, x, y) then
					hit = true
					hitSurface = surface
					break
				end
			end
		end

		if hit then
			if not bestRec or scopeOutranks(rec, hitSurface, bestRec, bestSurface) then
				bestRec = rec
				bestSurface = hitSurface
			end
		end
	end

	return if bestRec then bestRec.Id else nil
end

--- Does the given surface belong to or sit inside the specified scope?
function InputScope.IsSurfaceInScope(surface: any, scopeId: string): boolean
	for rec in pairs(records) do
		if rec.Id == scopeId then
			if rec.Policy == "Modal" then
				return true
			end
			for _, s in ipairs(rec.Surfaces) do
				if surface == s then
					return true
				end
				--- ANCESTRY THROUGH THE HOST, not `IsDescendantOf` (ms-53 D8).
				---
				--- The old test was `typeof(surface) == "Instance" and ...`, so
				--- OFF-ENGINE IT WAS SKIPPED ENTIRELY and only an exact match could
				--- put a surface in scope. Every control inside a scoped window
				--- therefore answered "not in scope" headlessly -- which nothing
				--- noticed, because the sink that registers the scope was ALSO
				--- engine-gated, so no scope was ever hit off-engine and the
				--- question was never asked.
				---
				--- Two gates in different files, each hiding the other. Removing
				--- one turns a silent no-op into a total input failure; both had to
				--- go together, and the suite that proves it could not exist until
				--- they did.
				if isAncestorOf(s, surface) then
					return true
				end
				--- A BACKDROP OWNS THE CONTAINER IT SITS IN, not just its own
				--- descendants -- and it has none, which is the whole defect.
				---
				--- An `InputSink` is a frame sized to fill its parent, drawn behind
				--- that parent's content so clicks do not reach what is behind the
				--- window. Its scope therefore covers the parent's area, and every
				--- control in that area is in it. Asking only "is this a descendant
				--- of the backdrop?" answers no for all of them, which is why every
				--- control in a menu was unclickable in Roblox while the switcher
				--- bar outside the window still worked.
				local container = parentOf(s)
				if container and (surface == container or isAncestorOf(container, surface)) then
					return true
				end
			end
		end
	end
	return false
end

--- Is the point over any consuming scope? This is what gates GAME input.
function InputScope.IsPointerOverUI(x: number, y: number): boolean
	return InputScope.HitTest(x, y) ~= nil
end

--- Pointer position in the same space as GuiObject.AbsolutePosition (i.e. with
--- the topbar inset removed).
--- Last pointer position reported by a host that has no engine to ask (ms-52 M2).
---
--- In Roblox the engine is queried directly below and this is never read: the
--- engine's answer is authoritative and always current, where a cached one lags
--- by however long it has been since the last event.
---
--- Off-engine there is nothing to query, and returning (-1, -1) silently broke
--- every interaction that reads the pointer OUTSIDE an event callback -- the
--- scrollbar thumb captured -1 as its drag origin before the move loop ran, so
--- even a correct move loop would have dragged from the wrong place.
local fedX, fedY = -1, -1

--- Report where the pointer is. Called by the router for every move and press, so
--- a host only has to feed input once, in one place.
function InputScope.SetPointerPosition(x: number, y: number)
	fedX, fedY = x, y
end

function InputScope.GetPointerPosition(): (number, number)
	if not UserInputService then return fedX, fedY end
	local loc = UserInputService:GetMouseLocation()
	local insetX, insetY = 0, 0
	if GuiService then
		local ok, inset = pcall(function()
			return GuiService:GetGuiInset()
		end)
		if ok and inset then
			insetX, insetY = inset.X, inset.Y
		end
	end
	return loc.X - insetX, loc.Y - insetY
end

--- Live answer for "is the mouse over UI right now?". Registered into
--- CoreInput.InputContextManager by the application so CoreInput never has to
--- depend on Aether (same seam as Flux.SetProgressResolver).
function InputScope.IsMouseOverUI(): boolean
	local x, y = InputScope.GetPointerPosition()
	if x < 0 then return false end
	return InputScope.IsPointerOverUI(x, y)
end

local isSinkBound = false
local function ensureGameInputSink()
	if isSinkBound or not ContextActionService then return end
	isSinkBound = true

	local function sinkAction(_actionName: string, _inputState: Enum.UserInputState, _inputObject: InputObject)
		if InputScope.IsMouseOverUI() then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end

	pcall(function()
		ContextActionService:BindActionAtPriority(
			"Spektr_GameInputSink",
			sinkAction,
			false,
			100000,
			Enum.UserInputType.MouseWheel,
			Enum.UserInputType.MouseButton1,
			Enum.UserInputType.MouseButton2,
			Enum.UserInputType.MouseButton3
		)
	end)
end

--- The highest visible consuming scope, ignoring position. This is what an
--- Escape key should dismiss.
function InputScope.Topmost(): string?
	local bestId: string? = nil
	local bestDepth = -math.huge
	for rec in pairs(records) do
		if rec.IsVisible() and consumes(rec) and rec.Depth() > bestDepth then
			bestDepth = rec.Depth()
			bestId = rec.Id
		end
	end
	return bestId
end

--- Registered scopes, deepest last. Diagnostics and gates.
function InputScope._Dump(): { { Id: string, Policy: ScopePolicy, Depth: number, Visible: boolean } }
	local out = {}
	for rec in pairs(records) do
		table.insert(out, { Id = rec.Id, Policy = rec.Policy, Depth = rec.Depth(), Visible = rec.IsVisible() })
	end
	table.sort(out, function(a, b) return a.Depth < b.Depth end)
	return out
end

function InputScope._Count(): number
	local n = 0
	for _ in pairs(records) do n += 1 end
	return n
end

-- ═══════════════════════════════════════════════════════════════
-- The scope handle
-- ═══════════════════════════════════════════════════════════════

export type ScopeHandle = {
	Id: string,
	--- False while the scope is mid-transition. See InputScopeProps.IsSettled.
	IsSettled: () -> boolean,
	Depth: () -> number,
	BarrierDepth: () -> number,
	--- Is (x, y) inside any surface bound to this scope?
	ContainsPoint: (x: number, y: number) -> boolean,
	--- Vide component: the modal barrier. Parent it as a SIBLING of your content,
	--- before it in the child list. Returns nil for non-modal policies.
	Barrier: () -> any,
	--- Vide.action target for the content root: marks it hit-testable and
	--- registers its bounds with the arbiter.
	Bind: (rbx: GuiObject?) -> (),
	BringToFront: () -> (),
	IsTopmost: () -> boolean,
	Destroy: () -> (),
}

function InputScope.new(props: InputScopeProps): ScopeHandle
	ensureGameInputSink()
	local policy: ScopePolicy = props.Policy or "Block"
	local layer = props.Layer or "Windows"
	local slot = LayerManager.Allocate(layer, props.Id)

	local function isVisible(): boolean
		return resolve(props.Visible, true) == true
	end

	local priorityGetter = if type(props.Priority) == "function"
		then props.Priority
		elseif props.Priority ~= nil
		then function() return props.Priority :: number end
		else nil

	local record: ScopeRecord = {
		Id = props.Id,
		Policy = policy,
		Depth = slot.Depth,
		Priority = priorityGetter,
		IsVisible = isVisible,
		Surfaces = {},
	}
	records[record] = true

	local destroyed = false
	local function destroy()
		-- Idempotent: manual Destroy and scope cleanup may both fire.
		if destroyed then return end
		destroyed = true
		records[record] = nil
		slot.Release()
	end
	scopedCleanup(destroy)

	--- Geometric containment against this scope's own bound surfaces.
	local function containsPoint(x: number, y: number): boolean
		for _, surface in ipairs(record.Surfaces) do
			if surface.Parent and HitTest.ContainsVisible(surface, x, y) then
				return true
			end
		end
		return false
	end

	local function isSettled(): boolean
		if not props.IsSettled then return true end
		local ok, settled = pcall(props.IsSettled)
		return not ok or settled == true
	end

	local handle: ScopeHandle
	handle = {
		Id = props.Id,
		IsSettled = isSettled,
		Depth = slot.Depth,
		BarrierDepth = slot.BarrierDepth,
		ContainsPoint = containsPoint,
		BringToFront = slot.BringToFront,

		IsTopmost = function(): boolean
			return InputScope.Topmost() == props.Id
		end,

		Bind = function(rbx: GuiObject?)
			if not rbx then return end
			-- Registers the surface's BOUNDS. It deliberately does NOT set Active:
			-- a window root is a container, not a control, and es9's rule is that
			-- nothing but a control is Active.
			--
			-- Nothing depends on it any more. Since M16 every question that used
			-- to lean on the engine's hit-test is answered from these bounds:
			-- click-away via ContainsPoint, game-input gating via
			-- IsPointerOverUI, cross-menu blocking via HitTest inside the router.
			table.insert(record.Surfaces, rbx)
			scopedCleanup(function()
				local idx = table.find(record.Surfaces, rbx)
				if idx then
					table.remove(record.Surfaces, idx)
				end
			end)
		end,

		Barrier = function(): any
			if policy ~= "Modal" then
				return nil
			end

			-- Required lazily: PointerRouter requires THIS module at load, and a
			-- Barrier is only ever built during render, long after both are
			-- resolved. Requiring at load here would make the pair cyclic.
			local PointerRouter = require("./PointerRouter")

			-- A Frame, NOT a TextButton (ms-43 M17). GuiButton is what makes the
			-- engine take over the cursor on hover, and there is no property to
			-- opt out — so the barrier gets its press semantics from the router
			-- instead. `Active` still puts it in the engine's hit-test, which is
			-- what stops clicks reaching menus underneath.
			local press = PointerRouter.Pressable({
				Scope = handle,
				-- Below every control in its own window, so a click on a button
				-- resolves to the button and never to the backdrop.
				Priority = -1,
				-- A backdrop is not a control, so it stays transparent to the
				-- engine. Click-away still works: the router resolves it
				-- geometrically, not through the engine's hit-test.
				HitTestable = false,
				OnActivated = function()
					if not isVisible() or not props.OnDismiss then return end
					local x, y = InputScope.GetPointerPosition()
					if x >= 0 and containsPoint(x, y) then
						return -- inside our own window; not a click-away
					end
					props.OnDismiss()
				end,
			})

			return vide.create "Frame" {
				vide.action(function(rbx: GuiObject)
					press.Bind(rbx)
				end),
				Name = `InputBarrier_{props.Id}`,
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0, 0),
				AnchorPoint = Vector2.zero,
				BorderSizePixel = 0,
				BackgroundColor3 = function(): Color3
					return resolve(props.DimColor, Color3.fromRGB(0, 0, 0))
				end,
				BackgroundTransparency = function(): number
					return resolve(props.DimTransparency, 1)
				end,
				Visible = isVisible,
				ZIndex = slot.BarrierDepth,
			}
		end,

		Destroy = destroy,
	}
	return handle
end

return InputScope
