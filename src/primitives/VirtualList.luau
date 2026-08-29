--!strict
--[=[
	VirtualList — Headless Virtualized List Primitive
	Part of Aether.Primitives (Layer 2A).

	Mounts ONLY the items visible within the viewport window plus an overscan
	buffer, scaling cleanly to 10,000+ items with O(1) active DOM nodes.

	Key Features:
	- Uses `spektr/virtual.ItemIndex` for prefix-sum offset lookups and variable height estimation.
	- Reconciled instance pooling: Reuses already mounted instances and repositions them on scroll.
	- Viewport-relative positioning (`UDim2.fromOffset(0, itemOffset - scrollOffset)`) so ancestors
	  using `AutomaticCanvasSize` never over-measure hidden content.
	- One-frame-late measurement feedback to eliminate jump drift on variable-sized rows.
	- 100% offline testable in Lune.
]=]

local isRoblox = typeof(game) == "Instance"
local Deps = require("../Deps")

local ScrollController = require("../controllers/ScrollController")

-- ItemIndex from spektr/virtual, or nil.
--
-- ONE SOURCE, NOT FIVE. This used to fall back through an upward Instance walk
-- and four guessed relative paths — three of them into the monorepo layout this
-- package no longer lives in, so they could not have resolved and their failure
-- was silent. `Deps.Virtual` is the declared dependency; if it is absent the
-- answer is nil, which this module already handles by windowing nothing.
local ItemIndex = if Deps.Virtual then (Deps.Virtual.ItemIndex or Deps.Virtual) else nil

--- `mountedCount` is a change-guard, not a reactive value — nothing derives from
--- it — but `reconcile` runs inside the props.Items effect, so a plain read would
--- subscribe that effect to a source it writes two lines later. See Deps.peek.
--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2 =
	Deps.Vocabulary.UDim2

local peek = Deps.peek

local create = Deps.create
local source = Deps.source
local effect = Deps.effect
local action = Deps.action
local cleanup = Deps.cleanup
local RunService = if isRoblox and game:GetService("RunService") then game:GetService("RunService") else nil

export type VirtualListProps<T> = {
	Name: string?,
	Scope: any?,
	Size: any?,
	Position: any?,
	AnchorPoint: any?,
	Visible: any?,
	ZIndex: number?,
	LayoutOrder: any?,

	-- Virtualization Data
	Items: (() -> { T }) | { T },
	RenderItem: (item: T, index: number) -> any,
	Estimate: number,
	Overscan: number?,
	Identify: ((item: T, index: number) -> any)?,

	-- Controller Integration
	Controller: any?,
	OnScrolled: ((offset: number) -> ())?,
	_MountedForTest: (({ [number]: any }) -> ())?,
	[any]: any,
}

local function resolve<V>(v: ((() -> V) | V)?): V?
	if type(v) == "function" then
		return (v :: any)()
	end
	return v :: any
end

local function udim2New(xs: number, xo: number, ys: number, yo: number): any
	if isRoblox and typeof(UDim2) == "table" and UDim2.new then
		return UDim2.new(xs, xo, ys, yo)
	end
	return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
end

local function createFallbackIndex(getItems: () -> { any }, est: number)
	local items = getItems()
	return {
		TotalSize = function(): number
			return #items * est
		end,
		Count = function(): number
			return #items
		end,
		OffsetOf = function(index: number): number
			return (index - 1) * est
		end,
		SizeOf = function(index: number): number
			return est
		end,
		Range = function(offset: number, extent: number, overscan: number): (number, number)
			local n = #items
			if n == 0 then return 1, 0 end
			local first = math.clamp(math.floor(offset / est) + 1 - overscan, 1, n)
			local last = math.clamp(math.ceil((offset + extent) / est) + overscan, 1, n)
			return first, last
		end,
		Refresh = function()
			items = getItems()
		end,
		Record = function() end,
	}
end

local function VirtualList<T>(props: VirtualListProps<T>): any
	local overscan = props.Overscan or 2
	local estimate = props.Estimate or 30

	local getRawItems = function(): { T }
		local items = resolve(props.Items)
		return if type(items) == "table" then items else {}
	end

	local index = if ItemIndex
		then (if type(ItemIndex.new) == "function" then ItemIndex.new(getRawItems, estimate, props.Identify) else ItemIndex(getRawItems, estimate, props.Identify))
		else createFallbackIndex(getRawItems, estimate)

	local controller = props.Controller or (if ScrollController then ScrollController.new({
		Orientation = "Vertical",
	}) else nil)

	local identify = props.Identify or function(item: any, idx: number): any
		if typeof(item) == "Instance" then
			return item
		elseif type(item) == "table" then
			return item.Id or item.Key or item.EntityId or item.UID or item.Guid or idx
		end
		return item or idx
	end

	type MountedRecord = {
		Inst: any,
		Scope: (() -> ())?,
		Index: number,
		Item: any,
	}

	local clipRef = source(nil :: any)
	local contentRef = source(nil :: any)
	local mounted: { [any]: MountedRecord } = {}
	local mountedCount = source(0)

	local function destroyKey(key: any)
		local record = mounted[key]
		if not record then return end
		mounted[key] = nil

		if record.Scope then
			pcall(record.Scope)
			record.Scope = nil
		end

		local inst = record.Inst
		if type(inst) == "table" or typeof(inst) == "Instance" then
			local d = (inst :: any).Destroy
			if type(d) == "function" then
				pcall(function()
					(inst :: any):Destroy()
				end)
			end
		end
	end

	local function getCurrentScrollOffset(): number
		if props.SmoothOffset then
			local so = resolve(props.SmoothOffset)
			if type(so) == "number" then return so end
		end
		if controller and controller.GetOffset then
			local off = controller.GetOffset()
			if type(off) == "number" then
				return off
			elseif type(off) == "table" and off.Y then
				return off.Y
			elseif typeof(off) == "Vector2" then
				return off.Y
			end
		end
		return 0
	end

	local function getViewportHeight(): number
		if controller and controller.GetViewportSize then
			local v = controller.GetViewportSize()
			if v > 0 then return v end
		end
		local clip = clipRef()
		if clip then
			local abs = (clip :: any).AbsoluteSize
			if typeof(abs) == "Vector2" and abs.Y > 0 then
				return abs.Y
			end
		end
		return 300
	end

	local function positionOf(i: number): any
		local itemOffset = if index then index.OffsetOf(i) else (i - 1) * estimate
		local scrollY = getCurrentScrollOffset()
		return udim2New(0, 0, 0, itemOffset - scrollY)
	end

	local rootFn = Deps.root or (if Deps.vide then Deps.vide.root else nil)

	local function reconcile(first: number, last: number)
		local items = getRawItems()
		local container = contentRef() or clipRef()
		local activeKeys: { [any]: boolean } = {}
		local live = 0

		-- 1. Mount or update items in visible range [first..last]
		for i = first, last do
			local item = items[i]
			if not item then continue end

			local key = identify(item, i)
			activeKeys[key] = true
			live += 1

			local record = mounted[key]
			if not record then
				local inst: any = nil
				local dispose: (() -> ())? = nil

				if rootFn then
					dispose = rootFn(function()
						inst = props.RenderItem(item, i)
					end)
				else
					inst = props.RenderItem(item, i)
				end

				record = {
					Inst = inst,
					Scope = dispose,
					Index = i,
					Item = item,
				}
				mounted[key] = record
			else
				record.Index = i
				record.Item = item
			end

			if record and record.Inst then
				local built: any = record.Inst
				built.Position = positionOf(i)
				if container and built.Parent ~= container then
					pcall(function()
						built.Parent = container
					end)
				end
			end
		end

		-- 2. Destroy any mounted item no longer in visible window
		for key in pairs(mounted) do
			if not activeKeys[key] then
				destroyKey(key)
			end
		end

		if live ~= peek(mountedCount) then
			mountedCount(live)
		end

		if props._MountedForTest then
			local testMap = {}
			for _, rec in pairs(mounted) do
				testMap[rec.Index] = rec.Inst
			end
			props._MountedForTest(testMap)
		end
	end

	local function updateWindow()
		if not index then return end
		local items = getRawItems()
		local n = #items

		if n == 0 then
			for k in pairs(mounted) do
				destroyKey(k)
			end
			if peek(mountedCount) ~= 0 then
				mountedCount(0)
			end
			if controller and controller.SetDimensions then
				local curVp = if controller.GetViewportSize then controller.GetViewportSize() else nil
				local curCs = if controller.GetContentSize then controller.GetContentSize() else nil
				local vp = getViewportHeight()
				if curVp ~= vp or curCs ~= 0 then
					controller.SetDimensions(vp, 0)
				end
			end
			return
		end

		local scrollY = getCurrentScrollOffset()
		local vpHeight = getViewportHeight()
		local totalHeight = index.TotalSize()

		if controller and controller.SetDimensions then
			local curVp = if controller.GetViewportSize then controller.GetViewportSize() else nil
			local curCs = if controller.GetContentSize then controller.GetContentSize() else nil
			if curVp ~= vpHeight or curCs ~= totalHeight then
				controller.SetDimensions(vpHeight, totalHeight)
			end
		end

		local first, last = index.Range(scrollY, vpHeight, overscan)
		reconcile(first, last)
	end

	-- Measurement correction feedback for variable-sized items
	local function measureMounted()
		if not index then return end
		local scrollY = getCurrentScrollOffset()
		local drift = 0

		for _, record in pairs(mounted) do
			local inst = record.Inst
			local i = record.Index
			if inst and i then
				local abs = (inst :: any).AbsoluteSize
				if typeof(abs) == "Vector2" and abs.Y > 0 then
					drift += index.Measure(i, abs.Y, scrollY + drift)
				end
			end
		end

		if drift ~= 0 and controller and controller.ScrollBy then
			controller.ScrollBy(drift)
		end
	end

	-- Reactive update when items source changes
	if effect then
		effect(function()
			local _ = resolve(props.Items)
			if index then
				index.Refresh()
			end
			updateWindow()
		end)
	end

	-- Controller offset reaction
	if controller and controller.Subscribe then
		local unsub = controller.Subscribe(function()
			updateWindow()
			if props.OnScrolled then
				props.OnScrolled(getCurrentScrollOffset())
			end
		end)
		if cleanup then
			cleanup(unsub)
		end
	end

	if effect and props.SmoothOffset then
		effect(function()
			local _ = resolve(props.SmoothOffset)
			updateWindow()
		end)
	end

	-- Heartbeat measurement in Roblox runtime
	if RunService and RunService.Heartbeat then
		local conn = RunService.Heartbeat:Connect(function()
			measureMounted()
		end)
		if cleanup then
			cleanup(function()
				conn:Disconnect()
			end)
		end
	end

	if cleanup then
		cleanup(function()
			for k in pairs(mounted) do
				destroyKey(k)
			end
		end)
	end

	-- Initial window calculation
	updateWindow()

	return create("Frame")({
		Name = props.Name or "VirtualList",
		Size = props.Size or udim2New(1, 0, 1, 0),
		Position = props.Position or udim2New(0, 0, 0, 0),
		AnchorPoint = props.AnchorPoint,
		Visible = props.Visible,
		ZIndex = props.ZIndex or 1,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,

		action(function(ref: any)
			clipRef(ref)
			if controller and controller.SetViewportSize and typeof(ref.AbsoluteSize) == "Vector2" then
				controller.SetViewportSize(ref.AbsoluteSize.Y)
			end
			updateWindow()
		end),

		create("Frame")({
			Name = "Content",
			Size = udim2New(1, 0, 1, 0),
			Position = udim2New(0, 0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			action(function(ref: any)
				contentRef(ref)
				updateWindow()
			end),
		}),
	})
end

return VirtualList
