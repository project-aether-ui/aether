--!strict
--[[
	Aether.For — declarative keyed collection reconciliation primitive.
	
	WHY: Fine-grained reactive frameworks (like Vide) provide raw `indexes` and
	`values` primitives. Using `indexes` on animated or stateful items causes
	"Transient State Cross-Contamination" (where shifting array items reuses existing
	springs and local state across distinct entities).
	
	`Aether.For` provides a foolproof declarative interface:
	- Automatically reconciles collections by stable semantic identity (Key).
	- Preserves component instances and local state across order changes.
	- Seamlessly updates `itemSource()` data reactively without remounting.
	- Accurately tracks `indexSource()` for LayoutOrder.
	- Isolates lifecycle springs: newly mounted items begin fresh without dirty state.
]]

local Deps = require("./Deps")

local vide = Deps.vide
local source = vide.source
local effect = vide.effect
local values = vide.values

export type ForProps<T, K, Obj> = {
	--- A reactive source or getter returning an array of items: () -> { T }
	Each: () -> { T },
	--- Optional key extractor. Can be a property name (e.g. "Id", "Name", "Key")
	--- or a function `(item: T, index: number) -> K`. Defaults to item.Id or item.Name or item.Key or item.
	Key: (string | ((item: T, index: number) -> K))?,
	--- Render function for each keyed item.
	--- `itemSource`: reactive getter returning the latest item data for this key.
	--- `key`: the stable identity key.
	--- `indexSource`: reactive getter returning the current 1-based index (for LayoutOrder).
	Render: (itemSource: () -> T, key: K, indexSource: () -> number) -> Obj,
}

local function defaultKeyExtractor<T>(item: T, index: number): any
	if type(item) == "table" then
		local t = item :: any
		return t.Id or t.id or t.Name or t.name or t.Key or t.key or item
	end
	return item
end

local function For<T, K, Obj>(props: ForProps<T, K, Obj>): () -> { Obj }
	local keyExtractor: (item: T, index: number) -> K
	if type(props.Key) == "function" then
		keyExtractor = props.Key :: any
	elseif type(props.Key) == "string" then
		local propName = props.Key :: string
		keyExtractor = function(item: T, _index: number): K
			if type(item) == "table" then
				return (item :: any)[propName]
			end
			return item :: any
		end
	else
		keyExtractor = defaultKeyExtractor
	end

	local itemSignals: { [K]: (T?) -> T } = {}
	local indexSignals: { [K]: (number?) -> number } = {}
	local keysListSource = source({} :: { K })

	effect(function()
		local items = props.Each()
		local newKeys: { K } = table.create(#items)
		local seenKeys: { [K]: boolean } = {}

		for i, item in ipairs(items) do
			local k = keyExtractor(item, i)
			if k ~= nil and not seenKeys[k] then
				seenKeys[k] = true
				table.insert(newKeys, k)

				local itemSig = itemSignals[k]
				if not itemSig then
					itemSig = source(item)
					itemSignals[k] = itemSig
				else
					itemSig(item)
				end

				local idxSig = indexSignals[k]
				if not idxSig then
					idxSig = source(i)
					indexSignals[k] = idxSig
				else
					idxSig(i)
				end
			end
		end

		-- Clean up signals for keys that disappeared
		for k, _ in pairs(itemSignals) do
			if not seenKeys[k] then
				itemSignals[k] = nil
				indexSignals[k] = nil
			end
		end

		keysListSource(newKeys)
	end)

	return values(keysListSource, function(key: K, _unusedVideIndex)
		local itemSig = itemSignals[key] or function() return nil :: any end
		local idxSig = indexSignals[key] or function() return 1 end

		vide.cleanup(function()
			itemSignals[key] = nil
			indexSignals[key] = nil
		end)

		return props.Render(itemSig :: any, key, idxSig :: any)
	end)
end

return For
