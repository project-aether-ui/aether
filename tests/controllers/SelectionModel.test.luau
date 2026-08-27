--!strict
--!tier math
local SelectionModel = require("../../src/controllers/SelectionModel")
local T = require("@testkit")

local function testSingleSelection()
	local model = SelectionModel.new({ Mode = "single" })
	assert(model.GetSelectedCount() == 0, "starts empty")

	model.Select("item-1")
	assert(model.IsSelected("item-1"), "item-1 is selected")
	assert(model.GetSelectedCount() == 1, "count is 1")

	model.Select("item-2")
	assert(not model.IsSelected("item-1"), "item-1 is deselected on single mode")
	assert(model.IsSelected("item-2"), "item-2 is selected")
	assert(model.GetSelectedCount() == 1, "count remains 1")

	model.Toggle("item-2")
	assert(not model.IsSelected("item-2"), "item-2 toggled off")
	assert(model.GetSelectedCount() == 0, "count is 0 after toggle off")
end

local function testMultiSelection()
	local model = SelectionModel.new({ Mode = "multiple" })
	
	model.Select("a")
	model.Select("b")
	model.Select("c")
	assert(model.GetSelectedCount() == 3, "count is 3")
	assert(model.IsSelected("a") and model.IsSelected("b") and model.IsSelected("c"), "all 3 selected")

	model.Deselect("b")
	assert(model.GetSelectedCount() == 2, "count is 2")
	assert(not model.IsSelected("b"), "b is deselected")

	model.Toggle("c")
	assert(not model.IsSelected("c"), "c toggled off")
	model.Toggle("d")
	assert(model.IsSelected("d"), "d toggled on")

	model.Clear()
	assert(model.GetSelectedCount() == 0, "cleared")
end

local function testRangeSelection()
	local model = SelectionModel.new({ Mode = "multiple" })
	local keys = { "row-1", "row-2", "row-3", "row-4", "row-5" }

	model.Select("row-2")
	assert(model.GetAnchorKey() == "row-2", "anchor is row-2")

	model.SelectRange("row-4", keys)
	assert(model.IsSelected("row-2"), "row-2 in range")
	assert(model.IsSelected("row-3"), "row-3 in range")
	assert(model.IsSelected("row-4"), "row-4 in range")
	assert(not model.IsSelected("row-1"), "row-1 not in range")
	assert(not model.IsSelected("row-5"), "row-5 not in range")
	assert(model.GetSelectedCount() == 3, "count is 3")
end

local function testSubscriptionNotification()
	local lastKeys: { any } = {}
	local calls = 0

	local model = SelectionModel.new({
		Mode = "multiple",
		OnSelectionChanged = function(keys)
			lastKeys = keys
			calls += 1
		end,
	})

	model.Select("k1")
	assert(calls == 1, "callback fired on select")
	assert(#lastKeys == 1 and lastKeys[1] == "k1", "received k1")

	local unsub = model.Subscribe(function(keys)
		calls += 10
	end)

	model.Select("k2")
	assert(calls == 12, "both listeners fired")

	unsub()
	model.Clear()
	assert(calls == 13, "only first listener fired after unsub")
end

T.test("single selection behavior", testSingleSelection, "math")
T.test("multi selection behavior", testMultiSelection, "math")
T.test("contiguous range selection", testRangeSelection, "math")
T.test("subscription notification", testSubscriptionNotification, "math")

return T.run("SelectionModel")
