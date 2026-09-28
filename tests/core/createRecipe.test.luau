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
	--- Every `SetProperty` call the recipe layer makes on an ALREADY-CREATED
	--- rule, by that rule's own reference -- this is what the theming test
	--- below asserts stays at zero across a `SetThemeSource` call, the
	--- negative assertion the milestone's own "no per-instance mutation"
	--- constraint needs to be checked structurally rather than by reading
	--- the source and trusting it.
	local propertyWritesByRule: { [any]: number } = {}

	return {
		New = function(className: string)
			counts[className] = (counts[className] or 0) + 1
			local instance = { ClassName = className, Properties = {}, Selector = nil, Parent = nil, StyleSheet = nil }
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
			propertyWritesByRule[rule] = (propertyWritesByRule[rule] or 0) + 1
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
		--- The A4 port addition: an ORDINARY instance property write on a
		--- `StyleDerive`, distinct from `SetProperty` above (which is a
		--- `StyleRule`-only cascaded-property call in the real host). Never
		--- touches `propertyWritesByRule` -- a re-point is not a rule write.
		SetDeriveSource = function(derive: any, source: any)
			derive.StyleSheet = source
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
		propertyWriteCountOf = function(rule: any): number
			return propertyWritesByRule[rule] or 0
		end,
		--- The most recent instance of `className` this Dom has created --
		--- how the theming test below recovers the derive it did not create
		--- itself, the same "read it back through reflection" discipline
		--- the module header asks for, without reaching into module
		--- internals.
		lastCreated = function(className: string): any
			for i = #created, 1, -1 do
				if created[i].ClassName == className then
					return created[i]
				end
			end
			return nil
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

--- A4'S OWN COMPLETION TEST. Binds a real instance so a real `StyleRule`
--- referencing a `$Name` token exists, then re-points the theme source and
--- confirms, against the mock `Dom`, both halves of the milestone's own
--- "done when": the derive's own `.StyleSheet` property changed, AND no
--- `SetProperty` call landed on the already-existing rule during the
--- re-point (the negative assertion -- re-pointing is the only mechanism,
--- never a per-instance/per-rule property write).
local function testSetThemeSourceRepointsTheSharedDeriveWithoutTouchingExistingRules()
	local dom = fakeDom()
	local recipe = createRecipe({
		base = { BackgroundColor3 = "$AccentColor" },
	}, { Dom = dom, Component = "Pressable" })

	local instance = { Name = "Button" }
	local resolved = recipe.Bind(instance, {})
	assert(resolved.Rule.Properties.BackgroundColor3 == "$AccentColor", "the rule should carry the token string unresolved")

	local propertyWritesBeforeRepoint = dom.propertyWriteCountOf(resolved.Rule)
	assert(propertyWritesBeforeRepoint > 0, "the rule should have received its properties once, at creation")

	local sunrise = { Name = "Sunrise" }
	recipe.SetThemeSource(sunrise)

	assert(dom.countOf("StyleDerive") == 1, "SetThemeSource should create exactly one StyleDerive")
	local derive = dom.lastCreated("StyleDerive")
	assert(derive ~= nil, "a StyleDerive should have been created")
	assert(derive.Parent == dom.lastCreated("StyleSheet"), "the derive should be parented on the shared Aether recipe StyleSheet")
	assert(derive.StyleSheet == sunrise, "the derive's own StyleSheet property should point at the requested source")
	assert(
		propertyWritesBeforeRepoint == dom.propertyWriteCountOf(resolved.Rule),
		"re-pointing the theme source must not write any property onto an already-existing rule"
	)

	local dusk = { Name = "Dusk" }
	recipe.SetThemeSource(dusk)
	assert(dom.countOf("StyleDerive") == 1, "a second SetThemeSource call must re-point the same derive, not create a second one")
	assert(derive.StyleSheet == dusk, "a second call should re-point the SAME derive at the new source")
	assert(
		propertyWritesBeforeRepoint == dom.propertyWriteCountOf(resolved.Rule),
		"a second re-point must still write no property onto the already-existing rule"
	)
end

local function testSetThemeSourceRequiresADomThatSupportsIt()
	local dom = fakeDom()
	dom.SetDeriveSource = nil :: any
	local recipe = createRecipe({ base = {} }, { Dom = dom, Component = "Pressable" })

	local ok = pcall(function()
		recipe.SetThemeSource({ Name = "Sunrise" })
	end)
	assert(not ok, "SetThemeSource on a Dom that never implemented SetDeriveSource must say so, not do nothing quietly")
end

local function testTwoRecipesSharingADomShareTheOneDerive()
	local dom = fakeDom()
	local buttonRecipe = createRecipe({ base = { BackgroundColor3 = "$AccentColor" } }, { Dom = dom, Component = "Pressable" })
	local labelRecipe = createRecipe({ base = { TextColor3 = "$TextColor" } }, { Dom = dom, Component = "Label" })

	buttonRecipe.SetThemeSource({ Name = "Sunrise" })
	local dusk = { Name = "Dusk" }
	labelRecipe.SetThemeSource(dusk)

	assert(dom.countOf("StyleDerive") == 1, "two recipes sharing one Dom must share the one derive, not one each")
	assert(dom.lastCreated("StyleDerive").StyleSheet == dusk, "the second recipe's call should re-point the shared derive")
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
T.test(
	"SetThemeSource re-points the shared derive without touching existing rules",
	testSetThemeSourceRepointsTheSharedDeriveWithoutTouchingExistingRules,
	"math"
)
T.test("SetThemeSource requires a Dom that supports it", testSetThemeSourceRequiresADomThatSupportsIt, "math")
T.test("two recipes sharing a Dom share the one derive", testTwoRecipesSharingADomShareTheOneDerive, "math")

return T.run("createRecipe")
