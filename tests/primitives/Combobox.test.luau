--!strict
--!tier math
local T = require("@testkit")
local SelectionModel = require("../../src/controllers/SelectionModel")
local FloatingMath = require("../../src/FloatingMath")

-- Unit test for Combobox pure logic (filtering & keyboard selection mechanics)
local function testComboboxFilter()
	local items = {
		{ Id = "apple", Label = "Apple" },
		{ Id = "banana", Label = "Banana" },
		{ Id = "apricot", Label = "Apricot" },
		{ Id = "orange", Label = "Orange" },
	}

	local function filterItems(query: string)
		local out = {}
		for _, item in ipairs(items) do
			if query == "" or string.find(string.lower(item.Label), string.lower(query), 1, true) ~= nil then
				table.insert(out, item)
			end
		end
		return out
	end

	local resEmpty = filterItems("")
	assert(#resEmpty == 4, "empty query returns all items")

	local resAp = filterItems("ap")
	assert(#resAp == 2, "query 'ap' returns Apple and Apricot")
	assert(resAp[1].Id == "apple" and resAp[2].Id == "apricot", "matching items correct")

	local resZ = filterItems("z")
	assert(#resZ == 0, "non-matching query returns 0")
end

local function testComboboxKeyboardRoving()
	local items = { "ItemA", "ItemB", "ItemC" }
	local selection = SelectionModel.new({ Mode = "single" })
	selection.Select(items[1])

	assert(selection.IsSelected("ItemA"), "starts on first item")

	local currentIndex = 1
	local function move(delta: number)
		currentIndex = math.clamp(currentIndex + delta, 1, #items)
		selection.Select(items[currentIndex])
	end

	move(1)
	assert(selection.IsSelected("ItemB"), "moved down to ItemB")

	move(1)
	assert(selection.IsSelected("ItemC"), "moved down to ItemC")

	move(1)
	assert(selection.IsSelected("ItemC"), "clamped at end of list")

	move(-1)
	assert(selection.IsSelected("ItemB"), "moved up to ItemB")
end

local function testComboboxFloatingAnchor()
	local anchor = { X = 200, Y = 150, Width = 200, Height = 32 }
	local floating = { X = 0, Y = 0, Width = 200, Height = 150 }
	local viewport = { X = 0, Y = 0, Width = 1920, Height = 1080 }

	local pos = FloatingMath.ComputePosition(anchor, floating, viewport, {
		Placement = "bottom-start",
		Offset = 4,
	} :: any)

	assert(pos.X == 200, "aligned to anchor X")
	assert(pos.Y == 186, "positioned below anchor (150 + 32 + 4 = 186)")
	assert(pos.Placement == "bottom-start", "placement preserved")
end

T.test("combobox filtering logic", testComboboxFilter, "math")
T.test("combobox keyboard roving", testComboboxKeyboardRoving, "math")
T.test("combobox floating anchor calculation", testComboboxFloatingAnchor, "math")

return T.run("Combobox")
