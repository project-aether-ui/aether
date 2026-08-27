--!strict
--!tier math
-- ms-43 M16: the arbitration half of InputScope is pure geometry + ordering, so
-- it runs headlessly. The Barrier/Bind half needs real GuiObjects and is covered
-- by verify_43's static gates plus the es9 playtest.
local InputScope = require("../src/InputScope")
local LayerManager = require("../src/LayerManager")

-- A stand-in for a bound content root. HitTest only reads Parent, Visible,
-- AbsolutePosition and AbsoluteSize, so a table with those fields is enough to
-- exercise the resolver without a DataModel.
local function fakeSurface(x: number, y: number, w: number, h: number): any
	return {
		Parent = { IsA = function() return false end },
		Visible = true,
		AbsolutePosition = { X = x, Y = y },
		AbsoluteSize = { X = w, Y = h },
		IsA = function(_self: any, class: string): boolean
			return class == "GuiObject"
		end,
		Active = false,
	}
end

local function reset()
	for _, entry in ipairs(InputScope._Dump()) do
		local _ = entry
	end
	LayerManager._ResetLayer("Windows")
end

local function testDepthOrdering()
	print("[TEST] InputScope: later scopes allocate greater depth...")
	reset()
	local a = InputScope.new({ Id = "A", Policy = "Block" })
	local b = InputScope.new({ Id = "B", Policy = "Block" })

	assert(b.Depth() > a.Depth(), `B ({b.Depth()}) should sit above A ({a.Depth()})`)
	-- The barrier must land between the two content roots, or a modal would
	-- either fail to occlude the scope below or occlude its own content.
	assert(b.BarrierDepth() > a.Depth(), "B's barrier must be above A's content")
	assert(b.BarrierDepth() < b.Depth(), "B's barrier must be below B's own content")

	a.Destroy()
	b.Destroy()
	print("  ✓ depth ordering")
end

local function testBringToFront()
	print("[TEST] InputScope: BringToFront re-orders reactively...")
	reset()
	local a = InputScope.new({ Id = "A", Policy = "Block" })
	local b = InputScope.new({ Id = "B", Policy = "Block" })
	assert(b.Depth() > a.Depth(), "baseline: B above A")

	a.BringToFront()
	assert(a.Depth() > b.Depth(), `A ({a.Depth()}) should now be above B ({b.Depth()})`)
	assert(a.IsTopmost(), "A should report itself topmost")
	assert(not b.IsTopmost(), "B should no longer be topmost")

	a.Destroy()
	b.Destroy()
	print("  ✓ BringToFront")
end

local function testHitTestResolvesTopmost()
	print("[TEST] InputScope: overlapping scopes resolve to the topmost...")
	reset()
	local lower = InputScope.new({ Id = "Lower", Policy = "Block" })
	local upper = InputScope.new({ Id = "Upper", Policy = "Block" })

	-- Fully overlapping surfaces — the ambiguity a refcount could never resolve.
	lower.Bind(fakeSurface(0, 0, 200, 200))
	upper.Bind(fakeSurface(50, 50, 100, 100))

	assert(InputScope.HitTest(100, 100) == "Upper", "inside both -> Upper wins")
	assert(InputScope.HitTest(10, 10) == "Lower", "inside Lower only -> Lower")
	assert(InputScope.HitTest(500, 500) == nil, "outside both -> nil")

	lower.Destroy()
	upper.Destroy()
	print("  ✓ topmost resolution")
end

local function testModalCoversEverything()
	print("[TEST] InputScope: a modal scope covers the whole screen...")
	reset()
	local panel = InputScope.new({ Id = "Panel", Policy = "Block" })
	panel.Bind(fakeSurface(0, 0, 100, 100))
	assert(InputScope.HitTest(800, 600) == nil, "baseline: nothing out there")

	local modal = InputScope.new({ Id = "Modal", Policy = "Modal" })
	-- No Bind: modal covers everything by policy, which is what makes its
	-- barrier answer for the empty space around the window.
	assert(InputScope.HitTest(800, 600) == "Modal", "modal claims empty space")
	assert(InputScope.HitTest(50, 50) == "Modal", "modal outranks the panel below it")

	modal.Destroy()
	assert(InputScope.HitTest(50, 50) == "Panel", "panel is reachable again once the modal is gone")

	panel.Destroy()
	print("  ✓ modal coverage")
end

local function testInvisibleAndPassScopesDoNotConsume()
	print("[TEST] InputScope: invisible and Pass scopes never consume...")
	reset()
	local hidden = InputScope.new({ Id = "Hidden", Policy = "Modal", Visible = function() return false end })
	assert(InputScope.HitTest(10, 10) == nil, "an invisible modal must not block")
	assert(InputScope.Topmost() == nil, "an invisible scope is not topmost")
	hidden.Destroy()

	local passthrough = InputScope.new({ Id = "Pass", Policy = "Pass" })
	passthrough.Bind(fakeSurface(0, 0, 100, 100))
	assert(InputScope.HitTest(10, 10) == nil, "a Pass scope participates in order but consumes nothing")
	passthrough.Destroy()
	print("  ✓ visibility and Pass")
end

-- The bug es9 hit twice: clicking panel whitespace inside the window closed it.
-- The barrier spans the WHOLE screen, including under the window, so "the
-- barrier was activated" is not the same claim as "the click was outside". The
-- first cut relied on Roblox occluding the barrier wherever the Active content
-- covered it; that did not hold in engine, so the check is geometric now.
local function testDismissalIsArbitrated()
	print("[TEST] InputScope: a click inside a bound surface is not a click-away...")
	reset()
	local modal = InputScope.new({ Id = "Window", Policy = "Modal" })
	modal.Bind(fakeSurface(100, 100, 400, 300)) -- the window rect

	assert(modal.ContainsPoint(300, 200), "a point inside the window is contained")
	assert(not modal.ContainsPoint(50, 50), "a point outside the window is not")
	assert(not modal.ContainsPoint(600, 500), "a point past the far corner is not")

	-- Exactly on the edge counts as inside: a click on the window's own border
	-- must not dismiss it.
	assert(modal.ContainsPoint(100, 100), "the top-left corner is inside")
	assert(modal.ContainsPoint(500, 400), "the bottom-right corner is inside")

	modal.Destroy()
	print("  ✓ arbitrated dismissal")
end

local function testDisposal()
	print("[TEST] InputScope: registration is released, idempotently...")
	reset()
	local before = InputScope._Count()
	local scope = InputScope.new({ Id = "Temp", Policy = "Modal" })
	assert(InputScope._Count() == before + 1, "scope should register")
	scope.Destroy()
	assert(InputScope._Count() == before, "Destroy should unregister")
	scope.Destroy()
	assert(InputScope._Count() == before, "Destroy should be idempotent")
	print("  ✓ disposal")
end

local function testNestedStack()
	print("[TEST] InputScope: ten stacked modals occlude strictly downward...")
	reset()
	local handles = {}
	for i = 1, 10 do
		table.insert(handles, InputScope.new({ Id = `Win{i}`, Policy = "Modal" }))
	end

	-- The whole point of the design: window N's barrier is above window N-1's
	-- content, so Roblox's own hit-test blocks every button underneath.
	for i = 2, 10 do
		assert(handles[i].BarrierDepth() > handles[i - 1].Depth(),
			`Win{i}'s barrier must sit above Win{i - 1}'s content`)
	end
	assert(InputScope.Topmost() == "Win10", "the last opened modal is topmost")

	handles[10].Destroy()
	assert(InputScope.Topmost() == "Win9", "closing the top reveals the one below")

	for i = 1, 9 do handles[i].Destroy() end
	print("  ✓ nested stack")
end

-- ms-44: migrated onto testkit. This suite had no harness — bare asserts inside named
-- functions, invoked at the bottom of the file. That is the ms-43 M30 shape: delete an
-- invocation and the file still exits 0 and still reads as coverage. Registered tests
-- make that a VACUOUS failure instead, and give each one a name, a time and a tier in
-- the ##testkit JSON.
local T = require("@testkit")
T.test("depth ordering", testDepthOrdering, "math")
T.test("bring to front", testBringToFront, "math")
T.test("hit test resolves topmost", testHitTestResolvesTopmost, "math")
T.test("modal covers everything", testModalCoversEverything, "math")
T.test("invisible and pass scopes do not consume", testInvisibleAndPassScopesDoNotConsume, "math")
T.test("dismissal is arbitrated", testDismissalIsArbitrated, "math")
T.test("disposal", testDisposal, "math")
T.test("nested stack", testNestedStack, "math")

return T.run("InputScope")
