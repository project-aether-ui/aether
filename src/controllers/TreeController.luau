--!strict
-- Layer 1: Pure Headless State Controller — TreeController
-- Pure mathematical Luau data structure for tree expansion and virtual list flattening.

export type FlatTreeNode<T> = {
	Node: T,
	Id: any,
	Depth: number,
	IsExpanded: boolean,
	HasChildren: boolean,
}

export type TreeControllerOptions = {
	InitialExpanded: { any }?,
	OnExpandedChanged: ((expandedKeys: { any }) -> ())?,
}

export type TreeController = {
	IsExpanded: (id: any) -> boolean,
	Toggle: (id: any) -> (),
	Expand: (id: any) -> (),
	Collapse: (id: any) -> (),
	SetExpanded: (id: any, expanded: boolean) -> (),
	ExpandAll: (allIds: { any }) -> (),
	CollapseAll: () -> (),
	ExpandPath: (pathIds: { any }) -> (),
	GetExpandedKeys: () -> { any },
	GetExpandedCount: () -> number,
	ToSet: () -> { [any]: boolean },
	
	Flatten: <T>(
		roots: { T },
		getId: (item: T) -> any,
		getChildren: (item: T) -> { T }?
	) -> { FlatTreeNode<T> },
	
	Subscribe: (listener: (expandedKeys: { any }) -> ()) -> (() -> ()),
}

local isScriptInstance = typeof(script) == "Instance"
local Deps = if isScriptInstance
	then (function()
		local cur = script.Parent
		while cur and cur ~= game do
			if cur:FindFirstChild("Deps") then
				return require(cur.Deps)
			end
			cur = cur.Parent
		end
		return {}
	end)()
	else (function()
		local ok, res = pcall(require, "../Deps")
		if ok then return res end
		local ok2, res2 = pcall(require, "./Deps")
		return if ok2 then res2 else {}
	end)()

local source = Deps.source

local function new(options: TreeControllerOptions?): TreeController
	local opts = options or {}
	local expandedSet: { [any]: boolean } = {}
	local expandedCount = 0
	local listeners: { (expandedKeys: { any }) -> () } = {}
	local versionSource = if source then source(0) else nil

	if opts.OnExpandedChanged then
		table.insert(listeners, opts.OnExpandedChanged)
	end

	local function getExpandedKeys(): { any }
		local list = {}
		for k, v in pairs(expandedSet) do
			if v then
				table.insert(list, k)
			end
		end
		return list
	end

	local function notify()
		if versionSource then
			versionSource(versionSource() + 1)
		end
		local keys = getExpandedKeys()
		for _, listener in ipairs(listeners) do
			listener(keys)
		end
	end

	if opts.InitialExpanded then
		for _, id in ipairs(opts.InitialExpanded) do
			if not expandedSet[id] then
				expandedSet[id] = true
				expandedCount += 1
			end
		end
	end

	local self = {} :: TreeController

	function self.IsExpanded(id: any): boolean
		if versionSource then
			local _ = versionSource()
		end
		return expandedSet[id] == true
	end

	function self.GetExpandedKeys(): { any }
		return getExpandedKeys()
	end

	function self.GetExpandedCount(): number
		return expandedCount
	end

	function self.ToSet(): { [any]: boolean }
		local copy = {}
		for k, v in pairs(expandedSet) do
			copy[k] = v
		end
		return copy
	end

	function self.Expand(id: any)
		if id == nil or expandedSet[id] then return end
		expandedSet[id] = true
		expandedCount += 1
		notify()
	end

	function self.Collapse(id: any)
		if id == nil or not expandedSet[id] then return end
		expandedSet[id] = nil
		expandedCount -= 1
		notify()
	end

	function self.Toggle(id: any)
		if id == nil then return end
		if expandedSet[id] then
			expandedSet[id] = nil
			expandedCount -= 1
		else
			expandedSet[id] = true
			expandedCount += 1
		end
		notify()
	end

	function self.SetExpanded(id: any, expanded: boolean)
		if id == nil then return end
		local currently = expandedSet[id] == true
		if currently == expanded then return end
		if expanded then
			expandedSet[id] = true
			expandedCount += 1
		else
			expandedSet[id] = nil
			expandedCount -= 1
		end
		notify()
	end

	function self.ExpandAll(allIds: { any })
		local changed = false
		for _, id in ipairs(allIds) do
			if not expandedSet[id] then
				expandedSet[id] = true
				expandedCount += 1
				changed = true
			end
		end
		if changed then
			notify()
		end
	end

	function self.CollapseAll()
		if expandedCount > 0 then
			table.clear(expandedSet)
			expandedCount = 0
			notify()
		end
	end

	function self.ExpandPath(pathIds: { any })
		local changed = false
		for _, id in ipairs(pathIds) do
			if not expandedSet[id] then
				expandedSet[id] = true
				expandedCount += 1
				changed = true
			end
		end
		if changed then
			notify()
		end
	end

	function self.Flatten<T>(
		roots: { T },
		getId: (item: T) -> any,
		getChildren: (item: T) -> { T }?
	): { FlatTreeNode<T> }
		local flatList: { FlatTreeNode<T> } = {}

		local function walk(nodes: { T }, depth: number)
			for _, item in ipairs(nodes) do
				local id = getId(item)
				local children = getChildren(item)
				local hasChildren = children ~= nil and #children > 0
				local isExpanded = expandedSet[id] == true

				table.insert(flatList, {
					Node = item,
					Id = id,
					Depth = depth,
					IsExpanded = isExpanded,
					HasChildren = hasChildren,
				})

				if hasChildren and isExpanded and children then
					walk(children, depth + 1)
				end
			end
		end

		walk(roots, 0)
		return flatList
	end

	function self.Subscribe(listener: (expandedKeys: { any }) -> ()): () -> ()
		table.insert(listeners, listener)
		return function()
			local idx = table.find(listeners, listener)
			if idx then
				table.remove(listeners, idx)
			end
		end
	end

	return self
end

return {
	new = new,
}
