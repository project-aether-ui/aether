--!strict
--!tier math
--[=[
	Aether.Host.LuauDataModel — the Layer 2.5 resolver that replaced testkit's VideShim.

	Two things are being pinned here, and they fail for different reasons.

	FIDELITY. The whole point of the host is that `effect` and `derive` are vide's
	real ones rather than stand-ins, so the first test asserts that the reactive
	core actually loaded and actually tracks. If VideCore ever silently stops
	resolving an installed vide, `Headless.new()` raises — but a future "helpful"
	fallback to a stand-in would make every other suite in the monorepo quietly
	weaker, so the tracking behaviour is asserted directly rather than assumed.

	COMPATIBILITY. Suites across the monorepo were written against VideShim, whose
	`create` returned the props table. The mock instance keeps that access shape on
	purpose (properties by name, children by array index, `_ClassName`), and that
	is load-bearing for ~30 files — so it is pinned, not left to convention.
]=]
local T = require("@testkit")
local Headless = require("../../src/host/LuauDataModel")
local VideCore = require("../../src/host/VideCore")

local function testCoreIsRealVide()
	local core = VideCore.load()
	assert(core ~= nil, "an installed vide must be reachable; run pesde install in Aether")

	--- The exact capability VideShim lacked: dependency tracking. Its `effect` ran
	--- once and never again, which is why no suite written against it could observe
	--- a re-render. Note that both `effect` and `derive` require an enclosing scope
	--- here — itself a fidelity signal, since the shim accepted them anywhere.
	local runs = 0
	local computes = 0
	local seen: string? = nil
	local n = (core :: any).source("a")

	local destroy = (core :: any).root(function()
		(core :: any).effect(function()
			runs += 1
			seen = n()
		end)

		local afterFirst = runs
		assert(afterFirst > 0, "effect runs on creation")
		assert(seen == "a", "effect observed the initial value")

		n("b")
		assert(runs > afterFirst, "effect RE-RAN when its source changed (vide, not a shim)")
		assert(seen == "b", "effect observed the new value")

		--- derive memoises in real vide; the shim returned the function itself,
		--- so every read recomputed.
		local d = (core :: any).derive(function()
			computes += 1
			return n() .. "!"
		end)
		local first = d()
		local afterOne = computes
		local second = d()
		assert(first == "b!" and second == "b!", "derive returns the computed value")
		assert(computes == afterOne, "derive MEMOISED: a second read did not recompute")
	end)

	destroy()
end

local function testPropsTableAccessShape()
	local host = Headless.new()
	local frame = host.create("Frame")({
		Name = "Root",
		ZIndex = 4,
		host.create("TextLabel")({ Name = "Label" }),
		host.create("UIPadding")({}),
	})

	-- The three shapes ~30 shim-era suites depend on.
	assert(frame._ClassName == "Frame", "_ClassName answers, as the shim's props table did")
	assert(frame.ClassName == "Frame", "ClassName answers, as a real Instance does")
	assert(frame.ZIndex == 4, "properties read back by name")
	assert(#frame == 2, `children live in the array part, got #{#frame}`)
	assert(frame[1]._ClassName == "TextLabel", "children indexable by position")

	local walked = {}
	for _, child in ipairs(frame) do
		table.insert(walked, child._ClassName)
	end
	assert(table.concat(walked, ",") == "TextLabel,UIPadding", "ipairs walks children in order")

	assert(host.classOf(frame) == "Frame", "classOf resolves the class")
	assert(frame[1].Parent == frame, "children know their parent")
	assert(frame:FindFirstChildOfClass("UIPadding") ~= nil, "FindFirstChildOfClass finds it")
	assert(frame:IsA("GuiObject") and frame:IsA("Instance"), "IsA walks the ancestry")
	assert(not frame:IsA("ScrollingFrame"), "IsA does not over-claim")
end

local function testReactiveProperties()
	local host = Headless.new()
	local text = host.source("hello")
	local frame = host.create("Frame")({
		host.create("TextLabel")({ Name = "Label", Text = text }),
	})
	local label = frame[1]

	assert(label.Text == "hello", "function-valued property resolved at construction")
	text("world")
	assert(label.Text == "world", "and RE-RESOLVED when the source changed")

	--- Destroy tears the instance's scope down, so the binding must go quiet.
	frame:Destroy()
	text("ignored")
	assert(label.Text == "world", "binding stopped after Destroy")
end

--- REGRESSION. vide's `cleanup` REGISTERS a teardown against the current scope;
--- it does not run it. An earlier draft of the host ran it immediately, and
--- because VirtualList does `cleanup(unsub)` on its scroll subscription, the list
--- unsubscribed from its own controller during construction and then never
--- re-rendered on scroll.
---
--- VideShim could not have caught this: its cleanup was `function() end`, and
--- registering nothing looks exactly like running nothing until something depends
--- on the teardown being deferred.
local function testCleanupRegistersRatherThanRuns()
	local host = Headless.new()
	local ran = false

	host.cleanup(function()
		ran = true
	end)
	assert(ran == false, "cleanup must NOT run the teardown when registering it")

	--- Registered against a live scope, it runs when that scope is destroyed.
	local scopedRan = false
	local destroy = host.root(function()
		host.cleanup(function()
			scopedRan = true
		end)
	end)
	assert(scopedRan == false, "still not run while the scope is alive")
	destroy()
	assert(scopedRan == true, "run when the owning scope is destroyed")
end

local function testGeometryContract()
	local host = Headless.new()
	local frame = host.create("Frame")({ Name = "Panel", ZIndex = 7 })

	host.SetBounds(frame, 40, 60, 200, 120)
	local geo = host.Resolve(frame)
	local b = geo.GetBounds()

	assert(b.X == 40 and b.Y == 60, `bounds origin, got {b.X},{b.Y}`)
	assert(b.Width == 200 and b.Height == 120, `bounds extent, got {b.Width}x{b.Height}`)
	assert(geo.GetZIndex() == 7, "GetZIndex reads the node")
	assert(geo.IsVisible() == true, "a node with no Visible set is visible")

	frame.Visible = false
	assert(geo.IsVisible() == false, "Resolve reads LIVE, not a snapshot taken at Resolve time")
end

--- THE CLOCK (ms-51 M16).
---
--- Simulated rather than faked: `Step(dt)` advances every listener by exactly dt
--- and `Now()` accumulates, so a spring's trajectory is reproducible frame for
--- frame. The same assertion against a real Heartbeat is a race.
local function testClock()
	local host = Headless.new()
	assert(host.Clock.Name == "Simulated", "the headless clock identifies itself")

	local ticks, seen = 0, 0
	local unsubscribe = host.Clock.OnFrame(function(dt: number)
		ticks += 1
		seen += dt
	end)

	assert(host.Clock._ListenerCount() == 1, "the listener is registered")
	host.Clock.Step(1 / 60)
	host.Clock.Step(1 / 60)
	assert(ticks == 2, `two steps ran two frames, got {ticks}`)
	assert(math.abs(seen - 2 / 60) < 1e-9, "each frame carried its own dt")
	assert(math.abs(host.Clock.Now() - 2 / 60) < 1e-9, "Now accumulates the simulated time")

	unsubscribe()
	host.Clock.Step(1 / 60)
	assert(ticks == 2, "an unsubscribed listener stops receiving frames")
	assert(host.Clock._ListenerCount() == 0, "and is no longer counted")
end

--- THE VALUE VOCABULARY (ms-51 M16).
---
--- REAL implementations, so headless arithmetic is the engine's arithmetic. A
--- stand-in that rounded differently would make every motion assertion lie,
--- because a spring interpolating a UDim2 does real work on these values.
local function testVocabulary()
	local host = Headless.new()
	local V = host.Vocabulary

	for _, name in
		ipairs({
			"UDim",
			"UDim2",
			"Vector2",
			"Color3",
			"Rect",
			"NumberSequence",
			"NumberSequenceKeypoint",
			"ColorSequence",
			"Font",
			"Enum",
		})
	do
		assert((V :: any)[name] ~= nil, `the host provides {name}`)
	end

	local u = V.UDim2.fromScale(0.25, 1)
	assert(u.X.Scale == 0.25 and u.Y.Scale == 1, "UDim2 arithmetic is real, not a stub")
	local c = V.Color3.fromRGB(255, 128, 0)
	assert(math.abs(c.R - 1) < 1e-6 and math.abs(c.G - 128 / 255) < 1e-6, "Color3 converts as the engine does")
end

--- THE POINT OF ALL OF IT (ms-51 M16).
---
--- Aether reads NO Roblox global. This suite never assigns `UDim2`, `Color3` or
--- `Vector2` — most suites in the repo do, near the top, which is exactly how the
--- coupling stayed invisible: the modules read globals and the test file happened
--- to have set them. Building a real compound primitive with none of them defined
--- is the assertion that the vocabulary genuinely comes from the host.
---
--- If someone reintroduces a bare `UDim2.new` in an Aether module, this fails.
local function testNoGlobalVocabularyNeeded()
	local core = VideCore.load()
	local destroy = (core :: any).root(function()
		local Aether = require("../../src/api")
		local scroll = Aether.ScrollController.new({ Orientation = "Vertical", ViewportSize = 300 })
		local frame = Aether.ScrollingFrame({
			Controller = scroll,
			Presentation = "Inset",
			ScrollBarWidth = 8,
			AutoHide = true,
		})

		assert(frame ~= nil, "a compound primitive builds with no global vocabulary in scope")
		assert(scroll.GetViewportSize() == 300, "and it wired its controller")
	end)
	destroy()
end

--- LAYER 2 ASKS THE HOST, NOT THE ENGINE (ms-51 M16 part 3).
---
--- `GeometrySource` was three members and nothing used it. Measured against what
--- the algorithms actually do — 28 parent traversals, 23 visibility reads, 13
--- ZIndex, 9 class queries, 9 DisplayOrder, 7 LayerCollector — a rectangle was
--- never going to be enough: occlusion, clipping and render order are questions
--- about a TREE. `Host.Scene` describes one.
---
--- It is STATELESS on purpose. Hit-testing walks every candidate on every pointer
--- move, so a wrapper object per node would allocate a table per query; `Bounds`
--- returns four numbers rather than a rectangle for the same reason.
local function testSceneContract()
	local host = Headless.new()
	local S = host.Scene

	local screen = host.create("ScreenGui")({ Name = "Layer", DisplayOrder = 5 })
	local clip = host.create("ScrollingFrame")({ Name = "Clip", Parent = screen })
	local card = host.create("Frame")({ Name = "Card", ZIndex = 3, Parent = clip })

	host.SetBounds(clip, 0, 0, 200, 100)
	host.SetBounds(card, 10, 20, 50, 40)

	local x, y, w, h = S.Bounds(card)
	assert(x == 10 and y == 20 and w == 50 and h == 40, "Bounds returns four numbers, not a rectangle")
	assert(S.ZIndex(card) == 3, "ZIndex reads through")
	assert(S.IsVisible(card) == true, "a node with no Visible set is visible")
	assert(S.Parent(card) == clip, "Parent walks the tree")
	assert(S.ChildIndex(card) == 1, "ChildIndex is declaration order within the parent")

	--- A ScrollingFrame clips whatever ClipsDescendants says, because it bounds
	--- its own canvas. That rule is the whole reason M20 existed.
	assert(S.Clips(clip) == true, "a ScrollingFrame clips regardless of the flag")
	assert(S.Clips(card) == false, "a plain Frame does not")

	assert(S.IsLayerRoot(screen) == true, "a ScreenGui is a layer root")
	assert(S.IsLayerRoot(card) == false, "a Frame is not")
	assert(S.IsSurface(card) == true, "a Frame is a surface")
	assert(S.DisplayOrder(screen) == 5, "DisplayOrder reads through")
	assert(S.IsEnabled(screen) == true, "a layer root with no Enabled set is enabled")

	card:SetAttribute("SpektrHitCornerScale", 0.5)
	assert(S.Attribute(card, "SpektrHitCornerScale") == 0.5, "attributes read through")
	assert(S.Attribute(card, "Absent") == nil, "and an absent one is nil, not an error")
end

--- HitTest runs on the contract, with the CLIPPING RULE intact.
---
--- The bug M20 fixed: a card scrolled out of its ScrollingFrame still reported
--- the pointer as over it, because a raw rect test says where an element WOULD be
--- if nothing clipped it. That rule is host-independent — it is true of any
--- compositor — and this asserts it still holds now that the walk asks
--- `Host.Scene` rather than the engine.
local function testHitTestOnTheContract()
	local host = Headless.new()
	local HitTest = require("../../src/HitTest")

	local screen = host.create("ScreenGui")({ Name = "Layer", Enabled = true })
	local clip = host.create("ScrollingFrame")({ Name = "Clip", Parent = screen })
	local card = host.create("Frame")({ Name = "Card", Parent = clip })

	host.SetBounds(clip, 0, 100, 200, 100)
	host.SetBounds(card, 0, 120, 200, 40)

	assert(HitTest.RawContains(card, 50, 130) == true, "the raw rect contains the point")
	assert(HitTest.ContainsVisible(card, 50, 130) == true, "and it is genuinely visible there")

	--- Scroll the card up, out of the clip. Its OWN rectangle still covers the
	--- point; the clipped one does not.
	host.SetBounds(card, 0, 20, 200, 40)
	assert(HitTest.RawContains(card, 50, 30) == true, "the raw rect still says yes — that was the bug")
	assert(HitTest.ContainsVisible(card, 50, 30) == false, "but clipped away it is untouchable")

	--- Visibility is transitive, and nothing exposes that for us.
	host.SetBounds(card, 0, 120, 200, 40)
	clip.Visible = false
	assert(HitTest.ContainsVisible(card, 50, 130) == false, "an invisible ancestor hides it")
	assert(HitTest.IsEffectivelyVisible(card) == false, "and IsEffectivelyVisible agrees")
end

--- THE CURSOR SEAM (ms-51 M19).
---
--- PointerRouter CHOOSES a cursor; it does not WRITE one, because spektr/mouse
--- owns UserInputService.MouseIcon through a priority stack that caches and
--- restores the player's default. That division is unchanged. What changed is the
--- direction: Aether used to DEPEND on spektr/coreinput to reach
--- `Mouse.PushCursor`, which was the last cycle in the UI graph and the reason
--- spektr/mouse could never take a real headless vide.
local function testCursorSeam()
	local Cursor = require("../../src/Cursor")
	Cursor._reset()

	--- Unregistered, pushing is a NO-OP rather than an error. A host with no
	--- cursor owner simply has no cursor, which is the right answer.
	assert(Cursor.HasProvider() == false, "nothing registered by default")
	assert(Cursor.Push("Pointer") == nil, "pushing without a provider does nothing")

	local pushed: { any } = {}
	local popped = 0
	assert(
		Cursor.SetProvider({
			PushCursor = function(payload: any, priority: number?)
				table.insert(pushed, { Payload = payload, Priority = priority })
				return function()
					popped += 1
				end
			end,
			GetCursorToken = function(name: any)
				return if name == "Pointer" then { Image = "rbxasset://pointer", Priority = 7 } else { Image = name }
			end,
		}, "test") == true,
		"a provider registers"
	)
	assert(Cursor.ProviderOwner() == "test", "and names its owner")

	local pop = Cursor.Push("Pointer", 1)
	assert(#pushed == 1, "the push reached the provider")
	assert(pushed[1].Payload == "rbxasset://pointer", "the semantic name resolved through the pack")
	assert(pushed[1].Priority == 7, "the token's own priority beats the caller's default")
	assert(type(pop) == "function", "and a pop was handed back")
	pop()
	assert(popped == 1, "which withdraws exactly this entry")

	--- A pack may render either way per token; a Node beats an Image, because a
	--- pack supplying one is asking to draw the cursor itself.
	Cursor._reset()
	local seen: any = nil
	Cursor.SetProvider({
		PushCursor = function(payload: any)
			seen = payload
			return function() end
		end,
		GetCursorToken = function()
			return { Image = "an-image", Node = "a-node" }
		end,
	}, "test")
	Cursor.Push("whatever")
	assert(seen == "a-node", "Node wins when a token carries both")

	--- Never clobber, matching every other seam in the repo.
	assert(Cursor.SetProvider({ PushCursor = function() return nil end }, "second") == false,
		"a second provider does not displace the first")
	assert(Cursor.ProviderOwner() == "test", "the original owner stands")
	Cursor._reset()
end

T.test("headless host runs vide's real reactive core", testCoreIsRealVide, "math")
T.test("the cursor seam resolves, pops, and never clobbers", testCursorSeam, "math")
T.test("the scene contract answers what Layer 2 asks", testSceneContract, "math")
T.test("HitTest runs on the contract, clipping rule intact", testHitTestOnTheContract, "math")
T.test("the simulated clock steps exactly and unsubscribes", testClock, "math")
T.test("the value vocabulary is real, not stubbed", testVocabulary, "math")
T.test("Aether builds with no Roblox global in scope", testNoGlobalVocabularyNeeded, "math")
T.test("mock instances keep the shim's props-table access shape", testPropsTableAccessShape, "math")
T.test("function-valued properties are live reactive bindings", testReactiveProperties, "math")
T.test("cleanup registers a teardown rather than running it", testCleanupRegistersRatherThanRuns, "math")
T.test("Resolve yields a live GeometrySource", testGeometryContract, "math")

return T.run("AetherHost")
