--!strict
--[[
	Aether · core/createRecipe -- given a variant combination a caller already
	chose, which `StyleRule` carries it, and has that rule already been made?

	Layer 1. No reactive library, no engine types, no `Instance.new` of its
	own -- unlike `styled-pressable.luau`'s own hand-built version of this same
	shape, this machine is handed a `Dom` PORT (the same way `createPressable`
	is handed a `Router` rather than resolving one) and drives it, so a test
	exercises this against a plain Luau table and a real host drives it against
	`Instance.new`/`CollectionService` without this file ever naming either.
	`verify_core_has_no_framework` enforces exactly this boundary over
	`src/core/`: naming `Instance` here would fail the gate this file lives
	under, not merely violate a style preference.

	    local recipe = createRecipe({
	        base = { BackgroundColor3 = "$AccentColor" },
	        variants = {
	            size = { sm = { Padding = "$SpacingSm" }, lg = { Padding = "$SpacingLg" } },
	            tone = { accent = { BorderColor3 = "$AccentColor" }, danger = { BorderColor3 = "$DangerColor" } },
	        },
	        compoundVariants = {
	            { variantValues = { size = "lg", tone = "danger" }, properties = { Padding = "$SpacingLgDanger" } },
	        },
	    }, { Dom = dom, Component = "Pressable" })

	    local resolved = recipe.Bind(instance, { size = "lg", tone = "danger" })
	    -- resolved.Tag   == "Aether--Pressable--<hash>"
	    -- resolved.Rule  == the real StyleRule for that combination
	    -- instance now carries resolved.Tag through dom.AddTag

	SHAPE, decided in A1 (`.artifacts/project/milestones/60_.../vision/overview.md`,
	open questions 1 and 2) and not re-derived here: `base` is a plain property
	table; `variants` is keyed by variant name, each value a table from variant
	value to a property table; `compoundVariants` is an array of
	`{ variantValues, properties }` overrides, panda/cva's own real shape.

	PRECEDENCE, stated exactly because two variant dimensions can set the same
	property and something has to win: `base`, then each variant dimension
	PRESENT IN THE SELECTION applied in ALPHABETICAL ORDER of the dimension
	name (Luau tables carry no declaration order to fall back on, so this
	picks the one order that is reproducible from the definition alone), then
	`compoundVariants` in ARRAY order (later entries win ties), which is why a
	compound entry always beats a plain variant table for the same property --
	it is applied after every one of them, never before.

	SEMANTIC, NOT ATOMIC (A1's resolved open question 1): one `StyleRule`
	carries every property a resolved combination declares. `resolve_full`
	(Dew's `cascade.rs:111-121`) tests every `StyleRule` reachable from an
	instance on every resolve, and that resolve is documented as not cheap on
	repeated calls (`cascade.rs` module doc, lines 37-43) -- so the rule count
	in the shared sheet is what a repeated `Resolve`/`Bind` call must not grow,
	which is the entire reason for the memoization below. A rule for a
	combination already requested is reused, never rebuilt.

	TOKEN STRINGS PASS THROUGH UNCHANGED. A `base`/variant/compound property
	value that starts with `$` is a token Dew's own `cascade.rs` `resolve_token`
	resolves at cascade time, against a `StyleSheet`'s own `StyleDerive` chain.
	This module never inspects, strips, or re-resolves such a string -- doing
	so would build a second, competing, untested resolution path.

	THE SHARED SHEET IS KEYED BY `Dom`, matching how `ScreenStack.luau` keeps
	its shared state as MODULE-LEVEL locals rather than a `.new()` per caller:
	every `createRecipe` call sharing one `Dom` (one real host, or one test's
	own fake) shares the one "Aether recipe" `StyleSheet` and its rule cache,
	created lazily on first use and never rebuilt after. Keying by `Dom` rather
	than being a single unconditional global keeps two independent tests (two
	different fake `Dom` tables in the same process) from bleeding rule counts
	into each other, which a single unconditional module-level sheet would.
]]

local safeWarn = require("./Warn")

--- The whole surface this module drives on a host, and all of it -- the same
--- "hand over a port, never resolve one" rule `createPressable`'s own
--- `Router` and `createDraggable`'s own `PointerMoveSource` already follow.
--- A real adapter backs this with `Instance.new`, `.Selector =`,
--- `:SetProperty`, `.Parent =`, and `CollectionService:AddTag`/`RemoveTag`
--- -- exactly what `styled-pressable.luau` already does by hand (lines 78-91,
--- 106) -- but that adapter is a host's to write, not this file's.
export type Dom = {
	New: (className: string) -> any,
	SetParent: (instance: any, parent: any) -> (),
	SetSelector: (rule: any, selector: string) -> (),
	SetProperty: (rule: any, name: string, value: any) -> (),
	AddTag: (instance: any, tag: string) -> (),
	RemoveTag: (instance: any, tag: string) -> (),
}

export type PropertyTable = { [string]: any }

export type CompoundVariant = {
	variantValues: { [string]: string },
	properties: PropertyTable,
}

export type RecipeDefinition = {
	base: PropertyTable?,
	variants: { [string]: { [string]: PropertyTable } }?,
	compoundVariants: { CompoundVariant }?,
}

export type Selection = { [string]: string }

export type Resolved = {
	Tag: string,
	Properties: PropertyTable,
	Rule: any,
}

export type Options = {
	Dom: Dom,
	--- Named in every generated tag (`"Aether--<component>--<hash>"`), so two
	--- components resolving the same selection shape never collide on one tag.
	Component: string,
}

export type Recipe = {
	--- Resolves `selection`, ensuring the backing `StyleRule` exists (memoized
	--- -- a second call with the same selection reuses it), WITHOUT touching
	--- any instance's own tags.
	Resolve: (selection: Selection) -> Resolved,
	--- `Resolve`, plus: applies the resulting tag to `instance` via
	--- `Dom.AddTag`, removing whatever tag this recipe last applied to that
	--- same instance first (a bound instance can only ever carry the ONE tag
	--- this recipe most recently resolved for it).
	Bind: (instance: any, selection: Selection) -> Resolved,
	--- Removes whatever tag this recipe last bound to `instance`, if any.
	Unbind: (instance: any) -> (),
}

--- Every `Dom` this module has ever been driven with gets exactly one shared
--- "Aether recipe" `StyleSheet` and one rule cache, created on first use.
--- Weak-keyed so a `Dom` (a whole test's own fake, or a real host adapter)
--- that goes out of scope takes its cache with it rather than pinning it
--- forever.
local sheetsByDom: { [Dom]: { Sheet: any, Rules: { [string]: any } } } = setmetatable({}, { __mode = "k" }) :: any

local function stateFor(dom: Dom): { Sheet: any, Rules: { [string]: any } }
	local state = sheetsByDom[dom]
	if not state then
		state = { Sheet = dom.New("StyleSheet"), Rules = {} }
		sheetsByDom[dom] = state
	end
	return state
end

--- FNV-1a, 32-bit, over the canonical selection string below. Not
--- cryptographic and does not need to be -- only stable across calls in one
--- process and short enough to read inside a generated tag, the same bar a
--- CSS-in-JS class hash clears.
local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619

local function fnv1a(input: string): string
	local hash = FNV_OFFSET
	for i = 1, #input do
		hash = bit32.bxor(hash, string.byte(input, i))
		hash = bit32.band(hash * FNV_PRIME, 0xFFFFFFFF)
	end
	return string.format("%08x", hash)
end

--- Every selection key that names a variant dimension this recipe does not
--- declare -- sorted, so the warning order (and any test reading it) is
--- reproducible rather than at the mercy of table iteration.
local function unknownVariantNames(definition: RecipeDefinition, selection: Selection): { string }
	local variants = definition.variants or {}
	local unknown = {}
	for key in pairs(selection) do
		if variants[key] == nil then
			table.insert(unknown, key)
		end
	end
	table.sort(unknown)
	return unknown
end

--- The selection, restricted to dimensions this recipe actually declares and
--- sorted by dimension name, as one string -- the key both the hash and the
--- property-resolution order below are built from, so "the same combination"
--- always means the same string.
local function canonicalKey(definition: RecipeDefinition, selection: Selection): (string, { string })
	local variants = definition.variants or {}
	local dims = {}
	for name in pairs(selection) do
		if variants[name] ~= nil then
			table.insert(dims, name)
		end
	end
	table.sort(dims)

	local parts = {}
	for _, name in ipairs(dims) do
		table.insert(parts, `{name}:{selection[name]}`)
	end
	return table.concat(parts, "|"), dims
end

--- `base`, then each present variant dimension (alphabetical), then every
--- matching `compoundVariants` entry (array order) -- see this file's own
--- header for why that order is the one that is reproducible and the one
--- that makes a compound override always win.
local function resolveProperties(definition: RecipeDefinition, selection: Selection, dims: { string }): PropertyTable
	local props: PropertyTable = {}

	if definition.base then
		for key, value in pairs(definition.base) do
			props[key] = value
		end
	end

	local variants = definition.variants or {}
	for _, name in ipairs(dims) do
		local value = selection[name]
		local forValue = variants[name][value]
		if forValue then
			for key, propValue in pairs(forValue) do
				props[key] = propValue
			end
		end
	end

	if definition.compoundVariants then
		for _, compound in ipairs(definition.compoundVariants) do
			local matches = true
			for key, value in pairs(compound.variantValues) do
				if selection[key] ~= value then
					matches = false
					break
				end
			end
			if matches then
				for key, propValue in pairs(compound.properties) do
					props[key] = propValue
				end
			end
		end
	end

	return props
end

local function createRecipe(definition: RecipeDefinition, options: Options): Recipe
	local dom = options.Dom
	if not dom or not dom.New then
		error("createRecipe needs a Dom with New/SetParent/SetSelector/SetProperty/AddTag/RemoveTag", 2)
	end
	local component = options.Component
	if not component or component == "" then
		error("createRecipe needs a Component name -- it is what every generated tag is namespaced under", 2)
	end

	--- Which tag this recipe most recently bound to a given instance, so
	--- `Bind`/`Unbind` can remove exactly that one rather than guessing. Weak
	--- keyed so a destroyed instance does not pin this table forever.
	local boundTags: { [any]: string } = setmetatable({}, { __mode = "k" }) :: any

	local function resolve(selection: Selection): Resolved
		for _, key in ipairs(unknownVariantNames(definition, selection)) do
			safeWarn(`createRecipe: "{key}" is not a variant "{component}" recognises and was ignored`)
		end

		local key, dims = canonicalKey(definition, selection)
		local tag = `Aether--{component}--{fnv1a(key)}`
		local properties = resolveProperties(definition, selection, dims)

		local state = stateFor(dom)
		local rule = state.Rules[tag]
		if not rule then
			rule = dom.New("StyleRule")
			dom.SetSelector(rule, `.{tag}`)
			for propName, propValue in pairs(properties) do
				dom.SetProperty(rule, propName, propValue)
			end
			dom.SetParent(rule, state.Sheet)
			state.Rules[tag] = rule
		end

		return { Tag = tag, Properties = properties, Rule = rule }
	end

	local function unbind(instance: any)
		local previous = boundTags[instance]
		if previous then
			dom.RemoveTag(instance, previous)
			boundTags[instance] = nil
		end
	end

	local function bind(instance: any, selection: Selection): Resolved
		local resolved = resolve(selection)
		local previous = boundTags[instance]
		if previous ~= resolved.Tag then
			if previous then
				dom.RemoveTag(instance, previous)
			end
			dom.AddTag(instance, resolved.Tag)
			boundTags[instance] = resolved.Tag
		end
		return resolved
	end

	return {
		Resolve = resolve,
		Bind = bind,
		Unbind = unbind,
	}
end

return {
	createRecipe = createRecipe,
}
