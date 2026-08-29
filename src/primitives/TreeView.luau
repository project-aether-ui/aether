--!strict
--[=[
	TreeView — Headless Hierarchical Tree Primitive
	Part of Aether.Primitives (Layer 2B).

	Coordinates `TreeController` state machines with `VirtualList` to render
	deeply nested hierarchies (such as Explorer trees, Scene Graphs, or nested
	categories) with O(1) active instances regardless of total tree size.

	Key Features:
	- Pure separation: Layout, indentation math, and expansion state are headless.
	- Linear virtual flattening: Uses `TreeController.Flatten` to project trees to 1D stream.
	- Keyboard roving and ARIA tree accessibility contracts.
]=]

local isRoblox = typeof(game) == "Instance"
local Deps = require("../Deps")

local TreeControllerMod = require("../controllers/TreeController")
local VirtualList = require("./VirtualList")
local ScrollController = require("../controllers/ScrollController")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2, Enum =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.Enum

local create = Deps.create
local source = Deps.source
local effect = Deps.effect
local cleanup = Deps.cleanup

export type FlatTreeNode<T> = {
	Node: T,
	Id: any,
	Depth: number,
	IsExpanded: boolean,
	HasChildren: boolean,
}

export type TreeViewProps<T> = {
	Name: string?,
	Scope: any?,
	Size: any?,
	Position: any?,
	AnchorPoint: any?,
	Visible: any?,
	ZIndex: number?,
	LayoutOrder: any?,

	-- Tree Data & State
	Roots: (() -> { T }) | { T },
	GetId: ((item: T) -> any)?,
	GetChildren: ((item: T) -> { T }?)?,
	Controller: any?,
	InitialExpanded: { any }?,

	-- Rendering & Node Builder
	RenderNode: (nodeInfo: FlatTreeNode<T>, controller: any) -> any,
	Estimate: number?,
	Overscan: number?,
	Virtualize: boolean?,

	-- Scroll Integration
	ScrollController: any?,
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

local function TreeView<T>(props: TreeViewProps<T>): any
	local controller = props.Controller or (if TreeControllerMod and TreeControllerMod.new
		then TreeControllerMod.new({ InitialExpanded = props.InitialExpanded })
		else nil)

	local getId = props.GetId or function(item: any): any
		if type(item) == "table" then
			return item.Id or item.Key or item.Name or item
		end
		return item
	end

	local getChildren = props.GetChildren or function(item: any): { T }?
		if type(item) == "table" then
			return item.Children or item.children
		end
		return nil
	end

	local shouldVirtualize = if props.Virtualize ~= nil then props.Virtualize else true
	local estimate = props.Estimate or 24
	local overscan = props.Overscan or 3

	local flattenedStream = source({} :: { FlatTreeNode<T> })

	local function updateFlattened()
		if not controller or not controller.Flatten then return end
		local rawRoots = resolve(props.Roots)
		local rootsList: { T } = if type(rawRoots) == "table" then rawRoots else {}
		local flat = controller.Flatten(rootsList, getId, getChildren)
		flattenedStream(flat)
	end

	-- Subscribe to expansion changes
	if controller and controller.Subscribe then
		local unsub = controller.Subscribe(function()
			updateFlattened()
		end)
		if cleanup then
			cleanup(unsub)
		end
	end

	-- Re-flatten when roots source changes
	if effect then
		effect(function()
			local _ = resolve(props.Roots)
			updateFlattened()
		end)
	end

	updateFlattened()

	if shouldVirtualize and VirtualList then
		return VirtualList({
			Name = props.Name or "TreeView",
			Size = props.Size or udim2New(1, 0, 1, 0),
			Position = props.Position or udim2New(0, 0, 0, 0),
			AnchorPoint = props.AnchorPoint,
			Visible = props.Visible,
			ZIndex = props.ZIndex or 1,
			LayoutOrder = props.LayoutOrder,
			Controller = props.ScrollController,
			Items = flattenedStream,
			Estimate = estimate,
			Overscan = overscan,
			Identify = function(flatNode: FlatTreeNode<T>)
				return flatNode.Id
			end,
			RenderItem = function(flatNode: FlatTreeNode<T>, index: number)
				return props.RenderNode(flatNode, controller)
			end,
		})
	else
		-- Fallback standard declarative layout
		local For = Deps.For
		return create("Frame")({
			Name = props.Name or "TreeView",
			Size = props.Size or udim2New(1, 0, 1, 0),
			Position = props.Position or udim2New(0, 0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			create("UIListLayout")({
				SortOrder = if isRoblox and typeof(Enum) == "table" and Enum.SortOrder then Enum.SortOrder.LayoutOrder else 0,
			}),

			if For then For({
				Each = flattenedStream,
				Render = function(flatNodeSrc: any, flatNode: FlatTreeNode<T>, indexSrc: any)
					return props.RenderNode(flatNode, controller)
				end,
			}) else nil,
		})
	end
end

return TreeView
