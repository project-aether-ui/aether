--!strict
--!tier math
--[=[
	aether · core/createSlotRecipe.

	SAME FAKE `Dom` SHAPE AS `createRecipe.test.luau`'S OWN -- a multi-slot
	recipe is a thin composition over `createRecipe`, so what it needs
	proven is the composition, not the cascade behaviour `createRecipe`'s
	own suite already pins.
]=]
local T = require("@testkit")
local createSlotRecipe = require("../../src/core/createSlotRecipe").createSlotRecipe

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
		tagsOf = function(instance: any): { [string]: boolean }
			return tagsByInstance[instance] or {}
		end,
	}
end

local function testEachSlotResolvesItsOwnIndependentRuleSet()
	local dom = fakeDom()
	local slots = createSlotRecipe({
		Tab = { base = { BackgroundTransparency = "$TabBackground" } },
		TabPanel = { base = { BackgroundColor3 = "$PanelBackground" } },
	}, { Dom = dom, Component = "Tabs" })

	local tab = slots.Slot("Tab").Resolve({})
	local panel = slots.Slot("TabPanel").Resolve({})

	assert(tab.Properties.BackgroundTransparency == "$TabBackground", "the Tab slot should resolve its own base")
	assert(tab.Properties.BackgroundColor3 == nil, "the Tab slot must never see the TabPanel slot's own properties")
	assert(panel.Properties.BackgroundColor3 == "$PanelBackground", "the TabPanel slot should resolve its own base")
	assert(panel.Properties.BackgroundTransparency == nil, "the TabPanel slot must never see the Tab slot's own properties")

	assert(dom.countOf("StyleRule") == 2, "two distinct slots should back two distinct rules")
	assert(dom.countOf("StyleSheet") == 1, "both slots should share the one Dom's own shared sheet")
end

--- THE REGRESSION THIS SUITE EXISTS TO GUARD (this milestone's own Traps
--- section): two slots whose base properties happen to be IDENTICAL (here,
--- both empty) must never collide on tag identity just because their
--- resolved property hash is the same -- the slot name has to be part of
--- what makes the tag distinct, not just an input the hash happens to fold
--- in identically.
local function testIdenticalPropertiesAcrossSlotsDoNotCollideOnTagIdentity()
	local dom = fakeDom()
	local slots = createSlotRecipe({
		Tab = {},
		TabPanel = {},
	}, { Dom = dom, Component = "Tabs" })

	local tab = slots.Slot("Tab").Resolve({})
	local panel = slots.Slot("TabPanel").Resolve({})

	assert(tab.Tag ~= panel.Tag, `identical-property slots must not collide on tag identity, got {tab.Tag} == {panel.Tag}`)
	assert(string.find(tab.Tag, "^Aether%-%-Tabs%-%-Tab%-%-") ~= nil, `the Tab slot's own tag should be namespaced, got {tab.Tag}`)
	assert(
		string.find(panel.Tag, "^Aether%-%-Tabs%-%-TabPanel%-%-") ~= nil,
		`the TabPanel slot's own tag should be namespaced, got {panel.Tag}`
	)
	assert(dom.countOf("StyleRule") == 2, "two distinct slots must back two distinct rules even with identical properties")
end

local function testTheSameSlotIsMemoisedAcrossCalls()
	local dom = fakeDom()
	local slots = createSlotRecipe({
		Tab = { base = { Padding = "$SpacingSm" } },
	}, { Dom = dom, Component = "Tabs" })

	assert(slots.Slot("Tab") == slots.Slot("Tab"), "asking for the same slot twice must answer the same Recipe")
end

local function testBindingTwoSlotsToTwoInstancesTagsEachSeparately()
	local dom = fakeDom()
	local slots = createSlotRecipe({
		Tab = { base = { BackgroundTransparency = "$TabBackground" } },
		TabPanel = { base = { BackgroundColor3 = "$PanelBackground" } },
	}, { Dom = dom, Component = "Tabs" })

	local tabInstance = { Name = "Tab" }
	local panelInstance = { Name = "TabPanel" }

	local tab = slots.Slot("Tab").Bind(tabInstance, {})
	local panel = slots.Slot("TabPanel").Bind(panelInstance, {})

	assert(dom.tagsOf(tabInstance)[tab.Tag] == true, "binding the Tab slot should tag the Tab instance")
	assert(dom.tagsOf(tabInstance)[panel.Tag] == nil, "the Tab instance must never carry the TabPanel slot's own tag")
	assert(dom.tagsOf(panelInstance)[panel.Tag] == true, "binding the TabPanel slot should tag the TabPanel instance")
	assert(dom.tagsOf(panelInstance)[tab.Tag] == nil, "the TabPanel instance must never carry the Tab slot's own tag")
end

local function testAnUnknownSlotNameRefusesRatherThanSilentlyMakingOne()
	local dom = fakeDom()
	local slots = createSlotRecipe({
		Tab = {},
	}, { Dom = dom, Component = "Tabs" })

	local ok = pcall(function()
		slots.Slot("Nope")
	end)
	assert(not ok, "an undeclared slot name must refuse rather than quietly creating an unnamed recipe")
end

local function testItRefusesToRunWithNoSlotDefinitions()
	local ok = pcall(function()
		createSlotRecipe({}, { Dom = fakeDom(), Component = "Tabs" })
	end)
	assert(not ok, "a slot recipe with no declared slots must say so rather than doing nothing quietly")
end

T.test("each slot resolves its own independent rule set", testEachSlotResolvesItsOwnIndependentRuleSet, "math")
T.test(
	"identical properties across slots do not collide on tag identity",
	testIdenticalPropertiesAcrossSlotsDoNotCollideOnTagIdentity,
	"math"
)
T.test("the same slot is memoised across calls", testTheSameSlotIsMemoisedAcrossCalls, "math")
T.test("binding two slots to two instances tags each separately", testBindingTwoSlotsToTwoInstancesTagsEachSeparately, "math")
T.test(
	"an unknown slot name refuses rather than silently making one",
	testAnUnknownSlotNameRefusesRatherThanSilentlyMakingOne,
	"math"
)
T.test("it refuses to run with no slot definitions", testItRefusesToRunWithNoSlotDefinitions, "math")

return T.run("createSlotRecipe")
