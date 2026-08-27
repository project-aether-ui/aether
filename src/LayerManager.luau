--!strict
--[[
	LayerManager: Unified Global Layer & Scoped Z-Index Management.

	TWO TIERS OF ORDERING
	  * LAYERS are coarse and fixed: Background < GameHUD < Windows < Topbar <
	    Overlays < Tooltips < Cursor. Each is a DisplayOrder band, so a tooltip is
	    always over a window regardless of what either does internally.
	  * STACKS are fine and dynamic: within one layer, windows reorder as they
	    open and focus. That is `CreateStack` / `Allocate`.

	DEPTH IS ALLOCATED, NOT WRITTEN (ms-43 M16). Before this, ordering was a
	fiction: LayerManager had zero call sites and every component hardcoded its
	own ZIndex — the Showcase menu wrote `ZIndex = 30` on its root and hand-tuned
	5/6/7/10/11/12 on its children. Nothing could reason about what was on top,
	which is why input occlusion could not be solved (see InputScope).

	Each allocation owns a SLOT of `SLOT_SIZE` consecutive ZIndex values:

	    slot base + 0        the scope's input barrier   (InputScope)
	    slot base + 1        the scope's content root
	    slot base + 2..9     that content's own children

	so window N's barrier always sits above window N-1's content, and Roblox's
	own hit-test does the occluding.
]]

local Deps = require("./Deps")
local source = Deps.source

export type LayerName =
	| "Background"
	| "GameHUD"
	| "Windows"
	| "Topbar"
	| "Overlays"
	| "Tooltips"
	| "Cursor"

export type LayerStack = {
	Register: (id: any, onZIndexChanged: ((newZ: number) -> ())?) -> () -> (),
	BringToFront: (id: any) -> (),
	SendToBack: (id: any) -> (),
	GetZIndex: (id: any) -> number?,
	GetMaxZIndex: () -> number,
}

local LayerManager = {}

-- Defined Global Layers with isolated DisplayOrders
LayerManager.Layers = {
	Background = 10,
	GameHUD    = 100,
	Windows    = 1000,
	Topbar     = 5000,
	Overlays   = 8000,
	Tooltips   = 9000,
	Cursor     = 10000,
} :: { [string]: number }

-- Resolve a layer name or DisplayOrder value
function LayerManager.GetDisplayOrder(layer: string | number): number
	if type(layer) == "number" then
		return layer
	end

	local displayOrder = LayerManager.Layers[layer]
	if displayOrder then
		return displayOrder
	end

	local num = tonumber(layer)
	if num then
		return num
	end

	warn(`[LayerManager] Unknown layer '{layer}', defaulting DisplayOrder to 1000`)
	return 1000
end

-- Create a scoped Z-Index stack manager for intra-layer ordering (e.g. windows inside Windows layer)
function LayerManager.CreateStack(baseOffset: number?, step: number?): LayerStack
	local base = baseOffset or 100
	local stepVal = step or 10
	
	local stackList: { { id: any, callback: ((newZ: number) -> ())? } } = {}

	local function notifyAll()
		for index, entry in ipairs(stackList) do
			local calculatedZIndex = base + ((index - 1) * stepVal)
			if entry.callback then
				entry.callback(calculatedZIndex)
			end
		end
	end

	local function findIndex(id: any): number?
		for idx, entry in ipairs(stackList) do
			if entry.id == id then
				return idx
			end
		end
		return nil
	end

	local stackApi = {}

	function stackApi.Register(id: any, onZIndexChanged: ((newZ: number) -> ())?): () -> ()
		local existing = findIndex(id)
		if existing then
			stackList[existing].callback = onZIndexChanged
		else
			table.insert(stackList, { id = id, callback = onZIndexChanged })
		end
		notifyAll()

		return function()
			local idx = findIndex(id)
			if idx then
				table.remove(stackList, idx)
				notifyAll()
			end
		end
	end

	function stackApi.BringToFront(id: any)
		local idx = findIndex(id)
		if idx and idx ~= #stackList then
			local entry = table.remove(stackList, idx)
			if entry then
				table.insert(stackList, entry)
				notifyAll()
			end
		end
	end

	function stackApi.SendToBack(id: any)
		local idx = findIndex(id)
		if idx and idx ~= 1 then
			local entry = table.remove(stackList, idx)
			if entry then
				table.insert(stackList, 1, entry)
				notifyAll()
			end
		end
	end

	function stackApi.GetZIndex(id: any): number?
		local idx = findIndex(id)
		if idx then
			return base + ((idx - 1) * stepVal)
		end
		return nil
	end

	function stackApi.GetMaxZIndex(): number
		if #stackList == 0 then
			return base
		end
		return base + ((#stackList - 1) * stepVal)
	end

	return stackApi
end

-- ═══════════════════════════════════════════════════════════════
-- Depth allocation (ms-43 M16)
--
-- One shared stack per layer, so every component in a layer participates in the
-- same ordering instead of inventing its own ZIndex. `Allocate` hands back a
-- REACTIVE depth: bringing a window to front re-derives every dependent ZIndex
-- through vide rather than requiring a manual re-render.
-- ═══════════════════════════════════════════════════════════════

--- ZIndex values reserved per allocation. A scope's barrier takes the base and
--- its content the next value up, leaving 8 for that content's own children.
--- Raising this widens the per-window child budget; it does not change ordering.
LayerManager.SLOT_SIZE = 10

--- The first ZIndex a layer's allocations occupy. Kept well above 1 so ad-hoc
--- decorative ZIndex on unmanaged siblings still sorts below managed windows.
LayerManager.STACK_BASE = 100

export type DepthHandle = {
	--- Reactive ZIndex for the scope's CONTENT root.
	Depth: () -> number,
	--- Reactive ZIndex for the scope's input barrier — always Depth() - 1, i.e.
	--- above every lower allocation's content and below this one's.
	BarrierDepth: () -> number,
	--- Raise this allocation above its siblings in the layer.
	BringToFront: () -> (),
	--- Drop the allocation and re-pack the layer.
	Release: () -> (),
}

local layerStacks: { [string]: LayerStack } = {}

--- The shared stack for a layer, created on first use.
---
--- BASED AT THE LAYER'S OWN BAND, not at one global constant. Every layer used
--- to start at STACK_BASE, which made the Layers table decorative: a Topbar
--- allocation and a Windows allocation both got ~100, so "the topbar is above
--- windows" was true for DisplayOrder and false for everything that reasoned
--- about depth. A modal window's barrier therefore outranked the topbar button
--- that opened it, swallowed the click, and closed the menu by dismissal instead
--- — which is how clicking the topbar came to play the click-away sound.
function LayerManager.GetStack(layerName: string): LayerStack
	local existing = layerStacks[layerName]
	if existing then
		return existing
	end
	local band = LayerManager.Layers[layerName] or LayerManager.STACK_BASE
	local created = LayerManager.CreateStack(band + LayerManager.STACK_BASE, LayerManager.SLOT_SIZE)
	layerStacks[layerName] = created
	return created
end

--- The depth a control sits at when it declares a LAYER but no scope — a topbar
--- button, say, which belongs to a layer but is not a window.
function LayerManager.GetLayerDepth(layerName: string?): number
	if not layerName then return 0 end
	local band = LayerManager.Layers[layerName]
	if not band then return 0 end
	return band + LayerManager.STACK_BASE
end

--- Claim a depth slot in a layer. The returned getters are reactive.
---
--- `id` is the caller's own identity (a screen id, usually). Allocating twice
--- with the same id in the same layer re-uses the slot rather than stacking two,
--- so a component that re-mounts does not leak ordering.
function LayerManager.Allocate(layerName: string, id: any): DepthHandle
	local stack = LayerManager.GetStack(layerName)
	local slotBase = source(stack.GetZIndex(id) or LayerManager.STACK_BASE)

	local unregister = stack.Register(id, function(newZ: number)
		slotBase(newZ)
	end)

	local released = false
	return {
		Depth = function(): number
			return slotBase() + 1
		end,
		BarrierDepth = function(): number
			return slotBase()
		end,
		BringToFront = function()
			if released then return end
			stack.BringToFront(id)
		end,
		Release = function()
			-- Idempotent: a manual Release and a scope cleanup may both fire.
			if released then return end
			released = true
			unregister()
		end,
	}
end

--- Drop every allocation in a layer. Test/teardown helper — an application
--- should Release its own handles.
function LayerManager._ResetLayer(layerName: string)
	layerStacks[layerName] = nil
end

return LayerManager
