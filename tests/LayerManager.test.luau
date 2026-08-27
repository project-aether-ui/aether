--!strict
--!tier math
local LayerManager = require("../src/LayerManager")

local function testLayerManager()
	print("[TEST] Testing LayerManager.GetDisplayOrder...")
	assert(LayerManager.GetDisplayOrder("GameHUD") == 100, "GameHUD display order should be 100")
	assert(LayerManager.GetDisplayOrder("Windows") == 1000, "Windows display order should be 1000")
	assert(LayerManager.GetDisplayOrder("Topbar") == 5000, "Topbar display order should be 5000")
	assert(LayerManager.GetDisplayOrder("Cursor") == 10000, "Cursor display order should be 10000")
	assert(LayerManager.GetDisplayOrder(1234) == 1234, "Numeric display order should return as-is")

	print("[TEST] Testing LayerManager.CreateStack...")
	local stack = LayerManager.CreateStack(100, 10)

	local w1_z = 0
	local w2_z = 0
	local w3_z = 0

	local unreg1 = stack.Register("win1", function(z) w1_z = z end)
	local unreg2 = stack.Register("win2", function(z) w2_z = z end)
	local unreg3 = stack.Register("win3", function(z) w3_z = z end)

	assert(w1_z == 100, `win1 expected 100, got {w1_z}`)
	assert(w2_z == 110, `win2 expected 110, got {w2_z}`)
	assert(w3_z == 120, `win3 expected 120, got {w3_z}`)

	print("[TEST] Testing BringToFront...")
	stack.BringToFront("win1")
	assert(w2_z == 100, `win2 expected 100 after win1 brought to front, got {w2_z}`)
	assert(w3_z == 110, `win3 expected 110 after win1 brought to front, got {w3_z}`)
	assert(w1_z == 120, `win1 expected 120 after win1 brought to front, got {w1_z}`)

	print("[TEST] Testing Unregister...")
	unreg3()
	assert(w2_z == 100, `win2 expected 100 after win3 removed, got {w2_z}`)
	assert(w1_z == 110, `win1 expected 110 after win3 removed, got {w1_z}`)

	unreg1()
	unreg2()

	print("[TEST] LayerManager tests passed successfully!")
end

-- ms-44: migrated onto testkit. This suite had no harness — bare asserts inside named
-- functions, invoked at the bottom of the file. That is the ms-43 M30 shape: delete an
-- invocation and the file still exits 0 and still reads as coverage. Registered tests
-- make that a VACUOUS failure instead, and give each one a name, a time and a tier in
-- the ##testkit JSON.
local T = require("@testkit")
T.test("layer manager", testLayerManager, "math")

return T.run("LayerManager")
