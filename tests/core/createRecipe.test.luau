--!strict
--!tier math
--[=[
	aether · core/createRecipe.

	NO VIDE, NO ENGINE TYPES, matching createDraggable.test.luau's own shape --
	there is no pointer/input surface here, so unlike createPressable.test.luau
	there is no fake router either. What stands in for the engine is a fake
	`Dom`: plain tables recording what `Instance.new("StyleRule")`,
	`:SetProperty`, `.Parent =`, and `CollectionService:AddTag`/`RemoveTag`
	would have done, so "one StyleRule" and "the exact properties on it" are
	asserted against a real produced table rather than inferred.
]=]
local T = require("@testkit")
local createRecipe = require("../../src/core/createRecipe").createRecipe

--- A `Dom` that never touches an engine. `newCount("StyleRule")` is how
--- "exactly one rule was created for this combination" gets asserted rather
--- than assumed from behaviour alone -- the memoization regression this
--- machine exists to guard.
local function fakeDom()
	local created: { any } = {}
	local counts: { [string]: number } = {}
	local tagsByInstance: { [any]: { [string]: boolean } } = {}

	return {
		New = function(className: string)
			counts[className] = (counts[className] or 0) + 1
			local instance = { ClassName = className, Properties = {}, Selector = nil, Parent = nil }
			table.insert(created, instance)
			return instance
		end,
		SetParent = function(instance: any, parent: any)
			instance.Parent = parent
		end,
		SetSelector = function(rule: any, selector: string)
			rule.Selector = selector
		end,
		SetProperty = function(rule: any, name: string, value: any)
			rule.Properties[name] = value
		end,
		AddTag = function(instance: any, tag: string)
			local tags = tagsByInstance[instance]
			if not tags then
				tags = {}
				tagsByInstance[instance] = tags
			end
			tags[tag] = true
		end,
		RemoveTag = function(instance: any, tag: string)
			local tags = tagsByInstance[instance]
			if tags then
				tags[tag] = nil
			end
		end,
		countOf = function(className: string): number
			return counts[className] or 0
		end,
		createdCount = function(): number
			return #created
		end,
		tagsOf = function(instance: any): { [string]: boolean }
			return tagsByInstance[instance] or {}
		end,
	}
end

local function testAResolvedCombinationProducesTheExactExpectedRule()
	local dom = fakeDom()
	local recipe = createRecipe({
		base = { BackgroundColor3 = "$AccentColor" },
		variants = {
			size = { sm = { Padding = "$SpacingSm" }, lg = { Padding = "$SpacingLg" } },
			tone = { accent = { BorderColor3 = "$AccentColor" }, danger = { BorderColor3 = "$DangerColor" } },
		},
	}, { Dom = dom, Component = "Pressable" })

	local resolved = recipe.Resolve({ size = "lg", tone = "danger" })

	assert(resolved.Properties.BackgroundColor3 == "$AccentColor", "base properties should survive")
	assert(resolved.Properties.Padding == "$SpacingLg", "the chosen size's own properties should apply")
	assert(resolved.Properties.BorderColor3 == "$DangerColor", "the chosen tone's own properties should apply")

	assert(resolved.Rule.ClassName == "StyleRule", "a real StyleRule shape should back the resolved combination")
	assert(resolved.Rule.Selector == `.{resolved.Tag}`, "the rule's own selector should be a bare tag selector")
	assert(resolved.Rule.Properties.BackgroundColor3 == "$AccentColor", "the rule itself should carry the base property")
	assert(resolved.Rule.Properties.Padding == "$SpacingLg", "the rule itself should carry the variant property")
	assert(resolved.Rule.Properties.BorderColor3 == "$DangerColor", "the rule itself should carry the tone property")
	assert(string.find(resolved.Tag, "^Aether%-%-Pressable%-%-") ~= nil, `the tag should be namespaced, got {resolved.Tag}`)

	assert(dom.countOf("StyleSheet") == 1, "exactly one shared StyleSheet should back this Dom")
	assert(dom.countOf("StyleRule") == 1, "exactly one StyleRule should exist for this one combination")
end

--- THE REGRESSION THIS MACHINE EXISTS TO GUARD (the milestone's own Traps
--- section): `cascade.rs`'s own resolve is documented as not cheap on
--- repeated calls, so requesting the SAME combination twice must reuse the
--- one rule rather than building a second. Removing the memoization in
--- `createRecipe.luau` (deleting the `state.Rules[tag]` check and always
--- calling `dom.New("StyleRule")`) makes this assertion fail -- checked by
--- hand during this sprint, then reverted.
local function testRequestingTheSameCombinationTwiceDoesNotDuplicateTheRule()
	local dom = fakeDom()
	local recipe = createRecipe({
		base = { BackgroundColor3 = "$AccentColor" },
		variants = { size = { sm = {}, lg = { Padding = "$SpacingLg" } } },
	}, { Dom = dom, Component = "Pressable" })

	local first = recipe.Resolve({ size = "lg" })
	local second = recipe.Resolve({ size = "lg" })

	assert(dom.countOf("StyleRule") == 1, `a repeated combination must not duplicate its rule, got {dom.countOf("StyleRule")}`)
	assert(first.Rule == second.Rule, "the same combination should hand back the identical rule instance")
	assert(first.Tag == second.Tag, "the same combination should hash to the identical tag")
end

--- A second, DIFFERENT combination is not the same rule -- proving the dedup
--- above is real memoization by combination, not an accident of always
--- returning the first rule ever made.
local function testADifferentCombinationGetsItsOwnRule()
	local dom = fakeDom()
	local recipe = createRecipe({
		variants = { size = { sm = { Padding = "$SpacingSm" }, lg = { Padding = "$SpacingLg" } } },
	}, { Dom = dom, Component = "Pressable" })

	local sm = recipe.Resolve({ size = "sm" })
	local lg = recipe.Resolve({ size = "lg" })

	assert(sm.Rule ~= lg.Rule, "different combinations must get different rules")
	assert(sm.Tag ~= lg.Tag, "different combinations must get different tags")
	assert(dom.countOf("StyleRule") == 2, "two distinct combinations should back two distinct rules")
end

local function testAnUnknownVariantNameDoesNotThrowAndIsIgnored()
	local dom = fakeDom()
	local recipe = createRecipe({
		base = { BackgroundColor3 = "$AccentColor" },
		variants = { size = { lg = { Padding = "$SpacingLg" } } },
	}, { Dom = dom, Component = "Pressable" })

	--- `warn` ITSELF IS NOT CAPTURED HERE, matching createPressable.test.luau's
	--- own documented reason: Luau resolves it as a VM builtin rather than a
	--- mutable global this suite can intercept, and this repository ships no
	--- Warn.luau test of its own with a different mechanism to borrow. What IS
	--- asserted, the same bar that suite already set for an unrecognised
	--- handler key, is the actual promise: a typo'd variant name never throws
	--- and never quietly reshapes the resolved properties.
	local ok, resolved = pcall(function()
		return recipe.Resolve({ size = "lg", sizee = "lg" })
	end)

	assert(ok, "an unrecognised variant name must warn, not throw")
	assert((resolved :: any).Properties.Padding == "$SpacingLg", "the recognised variant should still resolve")
	assert((resolved :: any).Properties.sizee == nil, "an unrecognised variant name must never become a property")
end

local function testCompoundVariantsOverrideThePlainVariantTables()
	local dom = fakeDom()
	local recipe = createRecipe({
		base = { Padding = "$SpacingBase" },
		variants = {
			size = { lg = { Padding = "$SpacingLg" } },
			tone = { danger = { Padding = "$SpacingDanger" } },
		},
		compoundVariants = {
			{ variantValues = { size = "lg", tone = "danger" }, properties = { Padding = "$SpacingLgDanger" } },
		},
	}, { Dom = dom, Component = "Pressable" })

	local resolved = recipe.Resolve({ size = "lg", tone = "danger" })

	assert(
		resolved.Properties.Padding == "$SpacingLgDanger",
		`a matching compound variant should win over both plain variant tables, got {resolved.Properties.Padding}`
	)

	--- Without the matching compound (a different tone), the plain variant
	--- tables' own last-applied-wins order still holds -- proving the
	--- compound path is an OVERRIDE and not the only thing setting Padding.
	local noCompound = recipe.Resolve({ size = "lg", tone = "accent" })
	assert(noCompound.Properties.Padding == "$SpacingLg", "with no matching compound, the plain variant should stand")
end

local function testBindAppliesAndSwapsTheTagOnAnInstance()
	local dom = fakeDom()
	local recipe = createRecipe({
		variants = { size = { sm = { Padding = "$SpacingSm" }, lg = { Padding = "$SpacingLg" } } },
	}, { Dom = dom, Component = "Pressable" })

	local instance = { Name = "Button" }

	local sm = recipe.Bind(instance, { size = "sm" })
	assert(dom.tagsOf(instance)[sm.Tag] == true, "Bind should add the resolved tag to the instance")

	local lg = recipe.Bind(instance, { size = "lg" })
	assert(dom.tagsOf(instance)[sm.Tag] == nil, "swapping selection should remove the previous tag")
	assert(dom.tagsOf(instance)[lg.Tag] == true, "swapping selection should add the new tag")

	recipe.Unbind(instance)
	assert(dom.tagsOf(instance)[lg.Tag] == nil, "Unbind should remove whatever tag was last applied")
end

local function testDifferentDomsGetIndependentSheetsAndRuleCounts()
	local domA = fakeDom()
	local domB = fakeDom()
	local recipeA = createRecipe({
		variants = { size = { lg = { Padding = "$SpacingLg" } } },
	}, { Dom = domA, Component = "Pressable" })
	local recipeB = createRecipe({
		variants = { size = { lg = { Padding = "$SpacingLg" } } },
	}, { Dom = domB, Component = "Pressable" })

	recipeA.Resolve({ size = "lg" })
	recipeA.Resolve({ size = "lg" })
	recipeB.Resolve({ size = "lg" })

	assert(domA.countOf("StyleRule") == 1, "domA's own rule count should reflect only domA's own calls")
	assert(domB.countOf("StyleRule") == 1, "domB's own rule count should reflect only domB's own calls")
	assert(domA.countOf("StyleSheet") == 1 and domB.countOf("StyleSheet") == 1, "each Dom should get its own shared sheet")
end

local function testItRefusesToRunWithoutADom()
	local ok = pcall(function()
		createRecipe({}, { Dom = nil :: any, Component = "Pressable" })
	end)
	assert(not ok, "a recipe with no Dom must say so rather than doing nothing quietly")
end

T.test("a resolved combination produces the exact expected rule", testAResolvedCombinationProducesTheExactExpectedRule, "math")
T.test(
	"requesting the same combination twice does not duplicate the rule",
	testRequestingTheSameCombinationTwiceDoesNotDuplicateTheRule,
	"math"
)
T.test("a different combination gets its own rule", testADifferentCombinationGetsItsOwnRule, "math")
T.test("an unknown variant name does not throw and is ignored", testAnUnknownVariantNameDoesNotThrowAndIsIgnored, "math")
T.test("compound variants override the plain variant tables", testCompoundVariantsOverrideThePlainVariantTables, "math")
T.test("Bind applies and swaps the tag on an instance", testBindAppliesAndSwapsTheTagOnAnInstance, "math")
T.test("different Doms get independent sheets and rule counts", testDifferentDomsGetIndependentSheetsAndRuleCounts, "math")
T.test("it refuses to run without a Dom", testItRefusesToRunWithoutADom, "math")

return T.run("createRecipe")
