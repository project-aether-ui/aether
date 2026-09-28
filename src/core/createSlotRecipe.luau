--!strict
--[[
	Aether · core/createSlotRecipe -- a component with more than one real
	part (Tabs's own `Tab` and `TabPanel`) gets one `createRecipe` per named
	slot, sharing the one `Dom` those slots are ultimately bound against.

	Layer 1, same discipline as `createRecipe.luau` itself (see that file's
	own header): no reactive library, no engine types, no `Instance.new` of
	its own. This module is a thin composition OVER `createRecipe` -- it
	does not touch `dom.New`/`dom.AddTag` itself, it hands each slot's own
	definition to a real `createRecipe` call and returns a way to reach the
	slot back out.

	    local slots = createSlotRecipe({
	        Tab = { base = { BackgroundTransparency = "$TabBackground" } },
	        TabPanel = { base = { BackgroundColor3 = "$PanelBackground" } },
	    }, { Dom = dom, Component = "Tabs" })

	    local tabRecipe = slots.Slot("Tab")
	    local panelRecipe = slots.Slot("TabPanel")
	    tabRecipe.Bind(tabInstance, {})
	    panelRecipe.Bind(panelInstance, {})

	WHY THIS NEEDS NO CHANGE TO `createRecipe.luau`'S OWN API (and A2's own
	8 tests stay unmodified): `createRecipe`'s shared-sheet cache
	(`stateFor`/`sheetsByDom`) is already keyed by `Dom` alone, and its own
	generated tag is already namespaced by the `Component` string handed to
	it (`Aether--<component>--<hash>`, this file's own header cites the
	exact lines). Handing each slot its OWN `Component` string --
	`"<component>--<slotName>"`, e.g. `"Tabs--Tab"` vs `"Tabs--TabPanel"`
	-- is enough on its own to keep two slots that resolve to an identical
	property set (the empty-selection collision case named in this
	milestone's own Traps section) from ever generating the same tag,
	because the slot name is baked into the tag BEFORE the hash runs, not
	folded into the hash alongside it. Two slots sharing one `Dom` still
	share the one "Aether recipe" `StyleSheet` `createRecipe` already
	creates lazily per `Dom` -- nothing here asks for a second one.

	INTEGRATION POINT THIS MODULE ITSELF DECIDES NOTHING ABOUT. Whether a
	real `Dom.AddTag` call ever reaches an instance is entirely up to
	whoever calls `.Slot(name).Bind(instance, selection)` -- see
	`createTabs.luau`'s own header for why THAT call is legal from Layer 1
	despite the "no `Instance`, no `Dom`" rule `verify_core_has_no_framework`
	enforces: it is a port method call, the same shape `options.Selection
	.Select(element)` already is there, not a place this file or
	`createTabs.luau` names `Instance`/`CollectionService` itself.
]]

local coreRecipe = require("./createRecipe")
local createRecipe = coreRecipe.createRecipe

export type Dom = coreRecipe.Dom
export type RecipeDefinition = coreRecipe.RecipeDefinition
export type Selection = coreRecipe.Selection
export type Recipe = coreRecipe.Recipe

export type SlotDefinitions = { [string]: RecipeDefinition }

export type Options = {
	Dom: Dom,
	--- Named in every slot's own generated tag (`"Aether--<component>--
	--- <slotName>--<hash>"`), the same field `createRecipe`'s own
	--- `Options.Component` already is, one level up.
	Component: string,
}

export type SlotRecipe = {
	--- The `Recipe` for one named slot, created (and memoized) on first
	--- request -- a second call for the same slot name reuses the same
	--- `Recipe`, matching `createRecipe`'s own instance-per-call shape
	--- rather than rebuilding one per `Bind`.
	Slot: (name: string) -> Recipe,
}

local function createSlotRecipe(definitions: SlotDefinitions, options: Options): SlotRecipe
	if not definitions or next(definitions) == nil then
		error("createSlotRecipe needs at least one named slot definition", 2)
	end
	local component = options.Component
	if not component or component == "" then
		error("createSlotRecipe needs a Component name -- every slot's own tag is namespaced under it", 2)
	end

	local recipesByName: { [string]: Recipe } = {}

	local function slot(name: string): Recipe
		local existing = recipesByName[name]
		if existing then
			return existing
		end

		local definition = definitions[name]
		if not definition then
			error(`createSlotRecipe: "{name}" is not a slot this recipe declares`, 2)
		end

		local recipe = createRecipe(definition, { Dom = options.Dom, Component = `{component}--{name}` })
		recipesByName[name] = recipe
		return recipe
	end

	return { Slot = slot }
end

return {
	createSlotRecipe = createSlotRecipe,
}
