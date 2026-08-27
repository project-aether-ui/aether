--!strict
--!tier math
--[=[
	The layout cache, and the two ways a cache test passes while proving nothing
	(ms-52 M15.2).

	`Layout.Solve` re-solved every node on every frame. On shop only 16 of 287
	nodes change a layout input per frame, so the other 271 were re-derived to the
	same answer -- 2.31 ms of a ~7 ms frame.

	THE TWO TRAPS THIS SUITE IS SHAPED AROUND, both of which produce a green test.

	A cache test passes trivially when NOTHING WAS CACHED: solve twice, compare,
	they match, done -- and they would match with the cache ripped out. So every
	case here asserts on the HIT COUNT as well as the rectangles, and hit counts
	come from a counter rather than from timing, because a cache that never hits
	is merely slow and a slow test still passes on a fast machine.

	And it passes when EVERYTHING was cached but nothing was asked to change: a
	cache that never invalidates returns last frame's answer forever and agrees
	with itself perfectly. So the cases that matter here are the ones where
	something moves, and the comparison is always against a solve with the cache
	switched OFF -- never against the cache's own previous answer.
]=]
local T = require("@testkit")
local Aether = require("../../src")
local Layout = require("../../src/host/Layout")

local VIEWPORT = { X = 0, Y = 0, Width = 400, Height = 300 }

--- The cache ships OFF (it does not pay yet -- see `Layout.luau`), so every case
--- here turns it on explicitly. Without this the whole suite would compare an
--- uncached solve with another uncached solve and pass while testing nothing.
Layout.SetCacheEnabled(true)

local function fixture()
	local host = Aether.Host.Headless.new()
	local V = host.Vocabulary
	local create = host.create

	local rows = {}
	for i = 1, 4 do
		rows[i] = create("TextLabel")({
			Name = `Row{i}`,
			Text = `row {i}`,
			TextSize = 14,
			Size = V.UDim2.new(1, 0, 0, 30),
			LayoutOrder = i,
		})
	end

	local moving = create("Frame")({
		Name = "Moving",
		Size = V.UDim2.fromOffset(60, 40),
		Position = V.UDim2.fromOffset(10, 10),
	})

	local root = create("Frame")({
		Name = "Root",
		Size = V.UDim2.fromScale(1, 1),
		create("Frame")({
			Name = "Static",
			Size = V.UDim2.new(1, 0, 0, 150),
			ClipsDescendants = true,
			create("UIPadding")({ PaddingLeft = V.UDim.new(0, 8), PaddingTop = V.UDim.new(0, 8) }),
			create("UIListLayout")({ Padding = V.UDim.new(0, 4) }),
			rows[1], rows[2], rows[3], rows[4],
		}),
		create("Frame")({
			Name = "Holder",
			Size = V.UDim2.new(1, 0, 0, 100),
			Position = V.UDim2.fromOffset(0, 160),
			moving,
		}),
	})

	return host, root, moving
end

--- Every rectangle, keyed by name, as plain numbers. Comparing the flat arrays
--- directly would also compare `Order`, which is what a splice re-stamps -- the
--- rectangles are the thing that must not change.
local function rects(solved: { any }, Scene: any): { [string]: { number } }
	local out: { [string]: { number } } = {}
	for _, item in ipairs(solved) do
		local name = Scene.Name(item.Node) or "?"
		out[name] = { item.Rect.X, item.Rect.Y, item.Rect.Width, item.Rect.Height }
	end
	return out
end

local function differences(a: { [string]: { number } }, b: { [string]: { number } }): { string }
	local diffs = {}
	for name, ra in pairs(a) do
		local rb = b[name]
		if rb == nil then
			table.insert(diffs, `{name} missing`)
		else
			for i = 1, 4 do
				if math.abs(ra[i] - rb[i]) > 0.0001 then
					table.insert(diffs, `{name}[{i}] {ra[i]} vs {rb[i]}`)
					break
				end
			end
		end
	end
	for name in pairs(b) do
		if a[name] == nil then
			table.insert(diffs, `{name} unexpected`)
		end
	end
	return diffs
end

--- Solve the SAME tree with the cache off, from a clean slate. This is the
--- reference every case compares against: comparing a cached solve to a previous
--- cached solve would let a cache that never invalidates agree with itself.
local function uncached(Scene: any, root: any, host: any): { [string]: { number } }
	Layout.SetCacheEnabled(false)
	local solved = Layout.Solve(Scene, root, VIEWPORT, host)
	local snapshot = rects(solved, Scene)
	Layout.SetCacheEnabled(true)
	return snapshot
end

local function testASecondSolveHitsAndAgrees()
	local host, root = fixture()
	local Scene = host.Scene
	Layout.ClearCache()

	--- First solve populates; nothing can hit yet.
	Layout.ResetCacheStats()
	local first = rects(Layout.Solve(Scene, root, VIEWPORT, host), Scene)
	local cold = Layout.CacheStats()
	assert(cold.Hits == 0, `a cold solve cannot hit, it reported {cold.Hits}`)
	assert(cold.Misses > 4, `a cold solve should visit every node, it reported {cold.Misses} misses`)

	--- Second solve, nothing touched.
	Layout.ResetCacheStats()
	local second = rects(Layout.Solve(Scene, root, VIEWPORT, host), Scene)
	local warm = Layout.CacheStats()

	--- THE ASSERTION THAT STOPS THIS BEING VACUOUS. Without it the comparison
	--- below passes with the cache removed entirely.
	assert(warm.Hits > 0,
		"the second solve of an untouched tree hit the cache zero times, so everything below"
			.. " this compares an uncached solve with another uncached solve")
	assert(warm.Misses < cold.Misses / 2,
		`an untouched tree re-solved {warm.Misses} of the {cold.Misses} nodes a cold solve does;`
			.. " the cache is barely reusing anything")

	local diffs = differences(first, second)
	assert(#diffs == 0, `a cached solve moved rectangles: {table.concat(diffs, "; ")}`)
end

local function testAChangedNodeInvalidatesItAndItsAncestors()
	local host, root, moving = fixture()
	local Scene = host.Scene
	local V = host.Vocabulary
	Layout.ClearCache()

	local before = rects(Layout.Solve(Scene, root, VIEWPORT, host), Scene)

	--- MOVE ONE NODE. A cache that never invalidates passes every other case in
	--- this file; this is the one it cannot.
	moving.Position = V.UDim2.fromOffset(90, 55)

	Layout.ResetCacheStats()
	local cached = rects(Layout.Solve(Scene, root, VIEWPORT, host), Scene)
	local stats = Layout.CacheStats()

	local truth = uncached(Scene, root, host)
	local diffs = differences(cached, truth)
	assert(#diffs == 0,
		`after moving a node the cached solve disagrees with an uncached one: {table.concat(diffs, "; ")}`)

	--- It must have MOVED, or this compared two identical pictures. Compared
	--- against its own previous rectangle rather than the authored offset --
	--- `Moving` sits inside `Holder`, so its absolute position is never the number
	--- written into `Position`, and asserting on that number tested arithmetic
	--- nobody was doing.
	assert(before.Moving[1] ~= truth.Moving[1] or before.Moving[2] ~= truth.Moving[2],
		`the fixture did not move: Moving stayed at {truth.Moving[1]},{truth.Moving[2]}`)
	--- And the untouched half must still have been reused, or invalidation is
	--- simply "throw everything away", which is correct and worthless.
	assert(stats.Hits > 0,
		"changing one node invalidated the entire tree; nothing was reused")
end

local function testResizingAParentReflowsItsChildren()
	local host, root = fixture()
	local Scene = host.Scene
	local V = host.Vocabulary
	Layout.ClearCache()
	Layout.Solve(Scene, root, VIEWPORT, host)

	--- A node whose own inputs are UNCHANGED but whose offered box shrinks. Its
	--- children must re-solve even though nothing about them changed -- which is
	--- why the box is part of the key and not just the inputs.
	local static: any = nil
	for _, item in ipairs(Layout.Solve(Scene, root, VIEWPORT, host)) do
		if Scene.Name(item.Node) == "Static" then
			static = item.Node
		end
	end
	assert(static, "the fixture should contain Static")
	static.Size = V.UDim2.new(0.5, 0, 0, 150)

	local cached = rects(Layout.Solve(Scene, root, VIEWPORT, host), Scene)
	local truth = uncached(Scene, root, host)
	local diffs = differences(cached, truth)
	assert(#diffs == 0,
		`resizing a parent left stale child rectangles: {table.concat(diffs, "; ")}`)
	assert(truth.Row1[3] < 400,
		`the fixture did not actually narrow: Row1 width is {truth.Row1[3]}`)
end

local function testAddingAndRemovingChildren()
	local host, root = fixture()
	local Scene = host.Scene
	local V = host.Vocabulary
	Layout.ClearCache()
	Layout.Solve(Scene, root, VIEWPORT, host)

	local holder: any = nil
	for _, item in ipairs(Layout.Solve(Scene, root, VIEWPORT, host)) do
		if Scene.Name(item.Node) == "Holder" then
			holder = item.Node
		end
	end
	assert(holder, "the fixture should contain Holder")

	--- STRUCTURE, not properties. Every watched value on Holder is unchanged; only
	--- its child list moved, which is why the child list is part of the key.
	local extra = host.create("Frame")({
		Name = "Extra",
		Size = V.UDim2.fromOffset(20, 20),
		Position = V.UDim2.fromOffset(5, 60),
	})
	extra.Parent = holder

	local cached = rects(Layout.Solve(Scene, root, VIEWPORT, host), Scene)
	local truth = uncached(Scene, root, host)
	assert(truth.Extra ~= nil, "the fixture did not actually add a node")
	local diffs = differences(cached, truth)
	assert(#diffs == 0,
		`adding a child produced a stale solve: {table.concat(diffs, "; ")}`)

	extra.Parent = nil
	local afterCached = rects(Layout.Solve(Scene, root, VIEWPORT, host), Scene)
	local afterTruth = uncached(Scene, root, host)
	assert(afterTruth.Extra == nil, "the fixture did not actually remove the node")
	local afterDiffs = differences(afterCached, afterTruth)
	assert(#afterDiffs == 0,
		`removing a child produced a stale solve: {table.concat(afterDiffs, "; ")}`)
end

local function testAScaledSubtreeDoesNotCompound()
	local host = Aether.Host.Headless.new()
	local V = host.Vocabulary
	local create = host.create
	Layout.ClearCache()

	local inner = create("Frame")({ Name = "Inner", Size = V.UDim2.fromOffset(50, 50) })
	local root = create("Frame")({
		Name = "Root",
		Size = V.UDim2.fromScale(1, 1),
		create("Frame")({
			Name = "Scaled",
			Size = V.UDim2.fromOffset(100, 100),
			Position = V.UDim2.fromOffset(20, 20),
			create("UIScale")({ Scale = 1.5 }),
			inner,
		}),
	})
	local Scene = host.Scene

	--- `applyScales` MUTATES rectangles in place after the walk. A reused entry
	--- carries the SCALED rectangle, so scaling it again every frame grows it
	--- without bound -- while every input stays perfectly still, which is exactly
	--- the case the rest of this suite would call "unchanged" and reuse.
	local first = rects(Layout.Solve(Scene, root, VIEWPORT, host), Scene)
	for _ = 1, 5 do
		Layout.Solve(Scene, root, VIEWPORT, host)
	end
	local sixth = rects(Layout.Solve(Scene, root, VIEWPORT, host), Scene)

	local diffs = differences(first, sixth)
	assert(#diffs == 0,
		`a scaled subtree drifted across repeated solves: {table.concat(diffs, "; ")}`)

	local truth = uncached(Scene, root, host)
	local vsTruth = differences(sixth, truth)
	assert(#vsTruth == 0,
		`a scaled subtree disagrees with an uncached solve: {table.concat(vsTruth, "; ")}`)
	assert(truth.Scaled[3] > 100.5,
		`the fixture is not actually scaled: Scaled width is {truth.Scaled[3]}`)
end

local function testTheViewportIsPartOfTheKey()
	local host, root = fixture()
	local Scene = host.Scene
	Layout.ClearCache()
	Layout.Solve(Scene, root, VIEWPORT, host)

	--- Nothing in the TREE changed; the window did.
	local narrow = { X = 0, Y = 0, Width = 200, Height = 300 }
	local cached = rects(Layout.Solve(Scene, root, narrow, host), Scene)

	Layout.SetCacheEnabled(false)
	local truth = rects(Layout.Solve(Scene, root, narrow, host), Scene)
	Layout.SetCacheEnabled(true)

	local diffs = differences(cached, truth)
	assert(#diffs == 0,
		`a resized viewport served stale rectangles: {table.concat(diffs, "; ")}`)
	assert(truth.Root[3] == 200, `the fixture did not resize: Root width is {truth.Root[3]}`)
end

T.test("a second solve of an untouched tree hits, and agrees", testASecondSolveHitsAndAgrees, "math")
T.test("a changed node invalidates it without invalidating everything", testAChangedNodeInvalidatesItAndItsAncestors, "math")
T.test("resizing a parent reflows children whose own inputs did not change", testResizingAParentReflowsItsChildren, "math")
T.test("adding and removing a child is caught", testAddingAndRemovingChildren, "math")
T.test("a scaled subtree does not compound across solves", testAScaledSubtreeDoesNotCompound, "math")
T.test("the viewport is part of the key", testTheViewportIsPartOfTheKey, "math")

return T.run("LayoutCache")
