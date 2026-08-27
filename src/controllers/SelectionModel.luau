--!strict
-- Layer 1: Pure Headless State Controller — SelectionModel
-- Pure mathematical Luau data structure (0 IO, 0 Roblox Instance dependencies).

export type SelectionMode = "none" | "single" | "multiple"

export type SelectionModelOptions = {
	Mode: SelectionMode?,
	InitialSelection: { any }?,
	OnSelectionChanged: ((selectedKeys: { any }) -> ())?,
}

export type SelectionModel = {
	GetMode: () -> SelectionMode,
	SetMode: (mode: SelectionMode) -> (),
	IsSelected: (key: any) -> boolean,
	GetSelectedKeys: () -> { any },
	GetSelectedCount: () -> number,
	GetAnchorKey: () -> any?,
	SetAnchorKey: (key: any?) -> (),
	ToSet: () -> { [any]: boolean },
	
	Select: (key: any) -> (),
	Deselect: (key: any) -> (),
	Toggle: (key: any) -> (),
	SelectRange: (targetKey: any, orderedKeys: { any }) -> (),
	SelectAll: (keys: { any }) -> (),
	Clear: () -> (),
	SetSelection: (keys: { any }) -> (),
	
	Subscribe: (listener: (selectedKeys: { any }) -> ()) -> (() -> ()),
}

local function new(options: SelectionModelOptions?): SelectionModel
	local opts = options or {}
	local mode: SelectionMode = opts.Mode or "multiple"
	local selectedSet: { [any]: boolean } = {}
	local selectedCount = 0
	local anchorKey: any? = nil
	local listeners: { (selectedKeys: { any }) -> () } = {}

	if opts.OnSelectionChanged then
		table.insert(listeners, opts.OnSelectionChanged)
	end

	local function getSelectedKeys(): { any }
		local list = {}
		for k, v in pairs(selectedSet) do
			if v then
				table.insert(list, k)
			end
		end
		return list
	end

	local function notify()
		local keys = getSelectedKeys()
		for _, listener in ipairs(listeners) do
			listener(keys)
		end
	end

	if opts.InitialSelection then
		for _, key in ipairs(opts.InitialSelection) do
			if mode == "none" then
				break
			elseif mode == "single" then
				table.clear(selectedSet)
				selectedSet[key] = true
				selectedCount = 1
				anchorKey = key
				break
			else
				if not selectedSet[key] then
					selectedSet[key] = true
					selectedCount += 1
				end
				anchorKey = key
			end
		end
	end

	local self = {} :: SelectionModel

	function self.GetMode(): SelectionMode
		return mode
	end

	function self.SetMode(newMode: SelectionMode)
		if mode == newMode then return end
		mode = newMode
		if mode == "none" then
			if selectedCount > 0 then
				table.clear(selectedSet)
				selectedCount = 0
				anchorKey = nil
				notify()
			end
		elseif mode == "single" and selectedCount > 1 then
			local firstKey = anchorKey or next(selectedSet)
			table.clear(selectedSet)
			selectedCount = 0
			if firstKey ~= nil then
				selectedSet[firstKey] = true
				selectedCount = 1
				anchorKey = firstKey
			end
			notify()
		end
	end

	function self.IsSelected(key: any): boolean
		return selectedSet[key] == true
	end

	function self.GetSelectedKeys(): { any }
		return getSelectedKeys()
	end

	function self.GetSelectedCount(): number
		return selectedCount
	end

	function self.GetAnchorKey(): any?
		return anchorKey
	end

	function self.SetAnchorKey(key: any?)
		anchorKey = key
	end

	function self.ToSet(): { [any]: boolean }
		local copy = {}
		for k, v in pairs(selectedSet) do
			copy[k] = v
		end
		return copy
	end

	function self.Select(key: any)
		if mode == "none" or key == nil then return end

		if mode == "single" then
			if selectedSet[key] and selectedCount == 1 then return end
			table.clear(selectedSet)
			selectedSet[key] = true
			selectedCount = 1
			anchorKey = key
			notify()
		else
			if not selectedSet[key] then
				selectedSet[key] = true
				selectedCount += 1
				anchorKey = key
				notify()
			end
		end
	end

	function self.Deselect(key: any)
		if key == nil or not selectedSet[key] then return end
		selectedSet[key] = nil
		selectedCount -= 1
		if anchorKey == key then
			anchorKey = next(selectedSet)
		end
		notify()
	end

	function self.Toggle(key: any)
		if mode == "none" or key == nil then return end

		if mode == "single" then
			if selectedSet[key] then
				table.clear(selectedSet)
				selectedCount = 0
				anchorKey = nil
			else
				table.clear(selectedSet)
				selectedSet[key] = true
				selectedCount = 1
				anchorKey = key
			end
			notify()
		else
			if selectedSet[key] then
				selectedSet[key] = nil
				selectedCount -= 1
				if anchorKey == key then
					anchorKey = next(selectedSet)
				end
			else
				selectedSet[key] = true
				selectedCount += 1
				anchorKey = key
			end
			notify()
		end
	end

	function self.SelectRange(targetKey: any, orderedKeys: { any })
		if mode == "none" or targetKey == nil then return end

		if mode == "single" or #orderedKeys == 0 then
			self.Select(targetKey)
			return
		end

		local effectiveAnchor = anchorKey or orderedKeys[1]
		if effectiveAnchor == nil then
			self.Select(targetKey)
			return
		end

		local anchorIdx: number? = nil
		local targetIdx: number? = nil

		for i, key in ipairs(orderedKeys) do
			if key == effectiveAnchor then anchorIdx = i end
			if key == targetKey then targetIdx = i end
			if anchorIdx and targetIdx then break end
		end

		if not anchorIdx or not targetIdx then
			self.Select(targetKey)
			return
		end

		local startIdx = math.min(anchorIdx, targetIdx)
		local endIdx = math.max(anchorIdx, targetIdx)

		local changed = false
		for i = startIdx, endIdx do
			local k = orderedKeys[i]
			if not selectedSet[k] then
				selectedSet[k] = true
				selectedCount += 1
				changed = true
			end
		end

		if changed then
			notify()
		end
	end

	function self.SelectAll(keys: { any })
		if mode ~= "multiple" then return end
		local changed = false
		for _, k in ipairs(keys) do
			if not selectedSet[k] then
				selectedSet[k] = true
				selectedCount += 1
				changed = true
			end
		end
		if changed then
			notify()
		end
	end

	function self.Clear()
		if selectedCount > 0 then
			table.clear(selectedSet)
			selectedCount = 0
			anchorKey = nil
			notify()
		end
	end

	function self.SetSelection(keys: { any })
		if mode == "none" then return end
		table.clear(selectedSet)
		selectedCount = 0
		anchorKey = nil

		if mode == "single" then
			if #keys > 0 then
				local k = keys[1]
				selectedSet[k] = true
				selectedCount = 1
				anchorKey = k
			end
		else
			for _, k in ipairs(keys) do
				if not selectedSet[k] then
					selectedSet[k] = true
					selectedCount += 1
					anchorKey = k
				end
			end
		end
		notify()
	end

	function self.Subscribe(listener: (selectedKeys: { any }) -> ()): () -> ()
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
