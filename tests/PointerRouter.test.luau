--!strict
--!tier math
-- ms-43 M17: press resolution and click semantics are pure logic, so they run
-- headlessly through the router's _Simulate seams. The UserInputService and
-- MouseIcon halves need an engine and are covered by verify_43 + the playtest.
local PointerRouter = require("../src/PointerRouter")
local InputScope = require("../src/InputScope")
local LayerManager = require("../src/LayerManager")

local function fakeSurface(x: number, y: number, w: number, h: number, z: number?): any
	return {
		Parent = { IsA = function() return false end },
		Visible = true,
		ZIndex = z or 1,
		AbsolutePosition = { X = x, Y = y },
		AbsoluteSize = { X = w, Y = h },
		IsA = function(_self: any, class: string): boolean
			return class == "GuiObject"
		end,
		Active = false,
	}
end

--- A surface parented to a real LayerCollector at `displayOrder`, which is what
--- the router now derives a scope-less control's depth from.
local function fakeSurfaceIn(displayOrder: number, x: number, y: number, w: number, h: number): any
	local screen: any = { Name = "Screen", Enabled = true, DisplayOrder = displayOrder }
	screen.IsA = function(_self: any, class: string): boolean
		return class == "LayerCollector"
	end
	screen.GetChildren = function() return {} end
	local surface = fakeSurface(x, y, w, h)
	surface.Parent = screen
	return surface
end

local function press(props: any, surface: any)
	local p = PointerRouter.Pressable(props)
	p.Bind(surface)
	return p
end

local function testActivationRequiresSameElement()
	print("[TEST] PointerRouter: activation needs press AND release on one element...")
	local fired = 0
	local p = press({ OnActivated = function() fired += 1 end }, fakeSurface(0, 0, 100, 100))

	PointerRouter._SimulatePress(50, 50)
	PointerRouter._SimulateRelease(50, 50)
	assert(fired == 1, `press+release on the element should activate once, got {fired}`)

	-- Released elsewhere: this is the contract GuiButton.Activated gave us for
	-- free and the part hand-rolled InputEnded handlers usually get wrong.
	PointerRouter._SimulatePress(50, 50)
	PointerRouter._SimulateRelease(500, 500)
	assert(fired == 1, `release off the element must NOT activate, got {fired}`)

	-- Press began outside: a release that drifts onto the element is not a click.
	PointerRouter._SimulatePress(500, 500)
	PointerRouter._SimulateRelease(50, 50)
	assert(fired == 1, `press that began elsewhere must NOT activate, got {fired}`)

	p.Destroy()
	print("  ✓ activation semantics")
end

local function testPressStateTracks()
	print("[TEST] PointerRouter: IsPressed brackets the gesture...")
	local p = press({}, fakeSurface(0, 0, 100, 100))
	assert(not p.IsPressed(), "starts released")
	PointerRouter._SimulatePress(10, 10)
	assert(p.IsPressed(), "pressed after press")
	PointerRouter._SimulateRelease(10, 10)
	assert(not p.IsPressed(), "released after release")

	-- A release that lands elsewhere must still clear the pressed state, or the
	-- control sticks visually depressed forever.
	PointerRouter._SimulatePress(10, 10)
	PointerRouter._SimulateRelease(900, 900)
	assert(not p.IsPressed(), "released even when the release lands off-element")
	p.Destroy()
	print("  ✓ press state")
end

local function testTopmostWins()
	print("[TEST] PointerRouter: overlapping elements resolve by priority...")
	local lowFired, highFired = 0, 0
	local low = press({ Priority = 0, OnActivated = function() lowFired += 1 end }, fakeSurface(0, 0, 200, 200))
	local high = press({ Priority = 5, OnActivated = function() highFired += 1 end }, fakeSurface(0, 0, 200, 200))

	PointerRouter._SimulatePress(100, 100)
	PointerRouter._SimulateRelease(100, 100)
	assert(highFired == 1 and lowFired == 0, `higher priority should win, got low={lowFired} high={highFired}`)

	low.Destroy()
	high.Destroy()
	print("  ✓ priority resolution")
end

local function testBarrierLosesToControls()
	print("[TEST] PointerRouter: a scope's barrier never outranks its own controls...")
	LayerManager._ResetLayer("TestLayer")
	local scope = InputScope.new({ Id = "TestWindow", Layer = "TestLayer", Policy = "Modal" })

	local barrierFired, buttonFired = 0, 0
	-- The barrier registers at Priority -1 exactly so this cannot happen.
	local barrier = press({ Scope = scope, Priority = -1, OnActivated = function() barrierFired += 1 end },
		fakeSurface(0, 0, 2000, 2000))
	local button = press({ Scope = scope, OnActivated = function() buttonFired += 1 end },
		fakeSurface(100, 100, 80, 30))

	PointerRouter._SimulatePress(120, 110)
	PointerRouter._SimulateRelease(120, 110)
	assert(buttonFired == 1 and barrierFired == 0,
		`a click on the button must not reach the backdrop, got button={buttonFired} barrier={barrierFired}`)

	-- Outside the button, the barrier is the only candidate.
	PointerRouter._SimulatePress(900, 900)
	PointerRouter._SimulateRelease(900, 900)
	assert(barrierFired == 1, `a click on empty space should reach the backdrop, got {barrierFired}`)

	barrier.Destroy()
	button.Destroy()
	scope.Destroy()
	print("  ✓ barrier ranks below its controls")
end

local function testLowerScopeIsBlocked()
	print("[TEST] PointerRouter: a control under a modal is not a candidate...")
	LayerManager._ResetLayer("TestLayer")
	local lower = InputScope.new({ Id = "Lower", Layer = "TestLayer", Policy = "Block" })
	local lowerFired = 0
	local lowerBtn = press({ Scope = lower, OnActivated = function() lowerFired += 1 end },
		fakeSurface(0, 0, 100, 100))
	lower.Bind(fakeSurface(0, 0, 100, 100))

	PointerRouter._SimulatePress(50, 50)
	PointerRouter._SimulateRelease(50, 50)
	assert(lowerFired == 1, "baseline: the lower control is clickable on its own")

	local modal = InputScope.new({ Id = "Modal", Layer = "TestLayer", Policy = "Modal" })
	PointerRouter._SimulatePress(50, 50)
	PointerRouter._SimulateRelease(50, 50)
	assert(lowerFired == 1, `a modal above must block the lower control, got {lowerFired}`)

	modal.Destroy()
	PointerRouter._SimulatePress(50, 50)
	PointerRouter._SimulateRelease(50, 50)
	assert(lowerFired == 2, "closing the modal makes it clickable again")

	lowerBtn.Destroy()
	lower.Destroy()
	print("  ✓ cross-scope blocking")
end

-- ms-43 M20: the bug es9 hit — the Shop's close button sits visually above a
-- carousel card, but the card ate the click.
--
-- Cause: registration order was the final tie-break, and ShopMenu creates the
-- close button's Pressable at the top of its component function while ItemCards
-- create theirs as the carousel renders — LATER. "Declared later" is not "on
-- top". Ranking now compares the real ancestor chains.
local function testRenderOrderBeatsRegistrationOrder()
	print("[TEST] PointerRouter: visual stacking outranks registration order...")

	-- A minimal tree with real parent/child semantics:
	--   Window
	--     Content  (ZIndex 1)  -> Card     registered SECOND, lower ZIndex
	--     Header   (ZIndex 5)  -> CloseBtn registered FIRST,  higher ZIndex
	local function node(name: string, zindex: number, parent: any?): any
		local n: any = {
			Name = name,
			ZIndex = zindex,
			Visible = true,
			Children = {},
			Parent = parent,
			AbsolutePosition = { X = 0, Y = 0 },
			AbsoluteSize = { X = 500, Y = 500 },
		}
		n.IsA = function(_self: any, class: string): boolean
			return class == "GuiObject"
		end
		n.GetChildren = function(_self: any)
			return n.Children
		end
		if parent then
			table.insert(parent.Children, n)
		end
		return n
	end

	-- A real chain terminates at a LayerCollector; isEffectivelyVisible checks for
	-- one, so the fixture needs it or nothing resolves at all.
	local screen: any = {
		Name = "ScreenGui",
		Enabled = true,
		DisplayOrder = 0,
		Children = {},
		Parent = nil,
	}
	screen.IsA = function(_self: any, class: string): boolean
		return class == "LayerCollector"
	end
	screen.GetChildren = function(_self: any) return screen.Children end

	local window = node("Window", 1, screen)
	local content = node("Content", 1, window)
	local header = node("Header", 5, window)
	local card = node("Card", 1, content)
	local closeBtn = node("CloseBtn", 1, header)

	-- Registered in the order ShopMenu actually registers them.
	local closeFired, cardFired = 0, 0
	local close = press({ OnActivated = function() closeFired += 1 end }, closeBtn)
	local cardP = press({ OnActivated = function() cardFired += 1 end }, card)

	PointerRouter._SimulatePress(100, 100)
	PointerRouter._SimulateRelease(100, 100)
	assert(closeFired == 1 and cardFired == 0,
		`the close button is above the card and must win, got close={closeFired} card={cardFired}`)

	-- Flip the visual order; the same registration order must now favour the card.
	header.ZIndex = 0
	PointerRouter._SimulatePress(100, 100)
	PointerRouter._SimulateRelease(100, 100)
	assert(cardFired == 1, `with the header sent behind, the card should win, got {cardFired}`)

	close.Destroy()
	cardP.Destroy()
	print("  ✓ render order beats registration order")
end

-- ms-43 M20: the real cause of es9's Shop report. A carousel card scrolled up
-- under the header is CLIPPED out of sight by the ScrollingFrame — but its
-- AbsolutePosition/AbsoluteSize still cover that area, so a raw rect test called
-- it a hit. The ScrollingFrame and the header are siblings at equal ZIndex and
-- the ScrollingFrame is declared later, so it legitimately renders above; the
-- invisible card therefore outranked the close button and ate the click.
--
-- Nothing about the ordering was wrong. The element was not there.
local function testClippedElementsAreNotHit()
	print("[TEST] PointerRouter: an element clipped away is not clickable...")

	local function node(name: string, z: number, parent: any?, x: number, y: number, w: number, h: number, class: string?): any
		local n: any = {
			Name = name,
			ZIndex = z,
			Visible = true,
			Children = {},
			Parent = parent,
			ClipsDescendants = false,
			AbsolutePosition = { X = x, Y = y },
			AbsoluteSize = { X = w, Y = h },
		}
		n.IsA = function(_self: any, c: string): boolean
			return c == "GuiObject" or c == class
		end
		n.GetChildren = function(_self: any) return n.Children end
		if parent then table.insert(parent.Children, n) end
		return n
	end

	local screen: any = { Name = "Gui", Enabled = true, DisplayOrder = 0, Children = {}, Parent = nil }
	screen.IsA = function(_self: any, c: string) return c == "LayerCollector" end
	screen.GetChildren = function(_self: any) return screen.Children end

	-- Window 0..400 tall. Header owns the top 56px; the scroll frame the rest.
	local window = node("Window", 2, screen, 0, 0, 400, 400)
	local header = node("Header", 2, window, 0, 0, 400, 56)
	local scroll = node("Scroll", 2, window, 0, 56, 400, 344, "ScrollingFrame")
	local closeBtn = node("Close", 1, header, 350, 10, 36, 36)
	-- Scrolled up: the card's own rect reaches y=0, overlapping the close button,
	-- but the ScrollingFrame clips everything above y=56.
	local card = node("Card", 1, scroll, 300, -20, 120, 160)

	local closeFired, cardFired = 0, 0
	local close = press({ OnActivated = function() closeFired += 1 end }, closeBtn)
	local cardP = press({ OnActivated = function() cardFired += 1 end }, card)

	-- (360, 24) is inside BOTH raw rects, but the card is clipped there.
	PointerRouter._SimulatePress(360, 24)
	PointerRouter._SimulateRelease(360, 24)
	assert(closeFired == 1 and cardFired == 0,
		`clipped card must not steal the close button's click, got close={closeFired} card={cardFired}`)

	-- Below the clip line the card is genuinely visible and does win.
	PointerRouter._SimulatePress(360, 100)
	PointerRouter._SimulateRelease(360, 100)
	assert(cardFired == 1, `the card is clickable where it is actually drawn, got {cardFired}`)

	-- es9's follow-up, and the important one: clipping must not be what SAVES
	-- the close button. Turn the clipping off entirely so the card genuinely
	-- overlaps, and the header's higher ZIndex must still carry it.
	--
	-- This is why ShopMenu/SettingsMenu now put HeaderBar at ZIndex 3. At the old
	-- equal-ZIndex-2 the later-declared scroll frame renders on top, so the card
	-- would have won here — correctly, per the engine — and the button would have
	-- been unclickable the moment anything scrolled behind it without clipping.
	scroll.IsA = function(_self: any, c: string): boolean
		return c == "GuiObject" -- no longer a ScrollingFrame: nothing clips
	end
	header.ZIndex = 3
	scroll.ZIndex = 2

	local beforeClose = closeFired
	PointerRouter._SimulatePress(360, 24)
	PointerRouter._SimulateRelease(360, 24)
	assert(closeFired == beforeClose + 1,
		`unclipped, the header's higher ZIndex must still win, got close={closeFired} card={cardFired}`)

	close.Destroy()
	cardP.Destroy()
	print("  ✓ clipping is honoured, and stacking wins without it")
end

-- ms-43 M21: hover must follow GEOMETRY, not input events.
--
-- Roblox's MouseEnter/MouseLeave only fire in response to POINTER movement, so
-- an element that scrolls out from under a still cursor stays lit until the
-- mouse twitches, and one that slides UNDER a still cursor never lights up. The
-- router polls, so both cases resolve — and LiveHover = false opts out.
local function testLiveHoverFollowsMovingContent()
	print("[TEST] PointerRouter: hover tracks content moving under a still pointer...")

	local surface = fakeSurface(0, 0, 100, 100)
	local live = 0
	local p = press({ OnHoverChanged = function(h) live = if h then 1 else 0 end }, surface)

	-- Pointer parked at (50, 50); the element is under it.
	PointerRouter._SimulateHover(50, 50)
	assert(live == 1, "baseline: hovered where the element is")

	-- The CONTENT moves away. The pointer has not moved at all — this is the
	-- case Roblox never reports.
	surface.AbsolutePosition = { X = 400, Y = 400 }
	PointerRouter._SimulateGeometryChange(50, 50)
	assert(live == 0, "hover must end when the element slides out from under the pointer")

	-- And back: sliding UNDER a stationary pointer must light it up.
	surface.AbsolutePosition = { X = 0, Y = 0 }
	PointerRouter._SimulateGeometryChange(50, 50)
	assert(live == 1, "hover must begin when the element slides under the pointer")

	p.Destroy()
	print("  ✓ live hover")
end

local function testLiveHoverCanBeDisabled()
	print("[TEST] PointerRouter: LiveHover = false ignores content movement...")

	local surface = fakeSurface(0, 0, 100, 100)
	local state = 0
	local p = press({
		LiveHover = false,
		OnHoverChanged = function(h) state = if h then 1 else 0 end,
	}, surface)

	PointerRouter._SimulateHover(50, 50)
	assert(state == 1, "a real pointer move still sets hover")

	surface.AbsolutePosition = { X = 400, Y = 400 }
	PointerRouter._SimulateGeometryChange(50, 50)
	assert(state == 1, "content movement alone must NOT clear an opted-out element")

	-- It still updates on genuine pointer movement, which is the fallback
	-- contract: Roblox's own behaviour, opted into deliberately.
	PointerRouter._SimulateHover(50, 50)
	assert(state == 0, "a real pointer move re-evaluates and clears it")

	p.Destroy()
	print("  ✓ live hover opt-out")
end

-- ms-43 M22: Resolve runs every frame and the registry grows with the UI — the
-- Showcase's live-hover lanes alone add 48 controls. The cost that matters is
-- ANCESTOR WALKS, not the loop itself, so the budget is asserted in walks rather
-- than in wall time (which would be flaky and machine-dependent).
--
-- The property: deep work scales with how many elements OVERLAP the pointer,
-- not with how many are registered.
local function testResolveScales()
	print("[TEST] PointerRouter: deep work scales with overlap, not registry size...")
	local HitTest = require("../src/HitTest")

	local COUNT = 500
	local handles = {}
	for i = 1, COUNT do
		-- Laid out in a distant column so none of them covers the probe point.
		table.insert(handles, press({}, fakeSurface(5000 + i, 5000, 40, 40)))
	end
	-- Exactly one element under the probe. Identified by its callback, because
	-- Resolve returns an internal record rather than the public handle.
	local hovered = false
	local target = press({ OnHoverChanged = function(h) hovered = h end }, fakeSurface(0, 0, 50, 50))

	HitTest._ResetStats()
	PointerRouter._SimulateHover(10, 10)
	local rawTests, walks = HitTest._Stats()

	assert(hovered, "the one overlapping element must win")
	assert(rawTests >= COUNT, `every record should get the cheap test, got {rawTests}`)
	-- The whole point: only the overlapping element pays for a walk.
	assert(walks <= 4, `deep walks must not scale with registry size, got {walks} for {COUNT + 1} records`)

	for _, h in ipairs(handles) do h.Destroy() end
	target.Destroy()
	print(`  ✓ {COUNT + 1} records -> {rawTests} cheap tests, {walks} ancestor walks`)
end

-- ms-43 M24: closing the Showcase played a hover sound.
--
-- Live hover is right that a control passing under the pointer is hovered — but
-- while a WINDOW animates itself off screen, its controls sweep past a
-- stationary cursor under their own power, and firing hover feedback for that is
-- reporting motion the user did not cause. Hover answers intent.
local function testUnsettledScopeSuppressesGeometryHover()
	print("[TEST] PointerRouter: a transitioning window does not fire hover as it flies past...")
	LayerManager._ResetLayer("TestLayer")

	local settled = true
	local scope = InputScope.new({
		Id = "Animating",
		Layer = "TestLayer",
		Policy = "Block",
		IsSettled = function() return settled end,
	})

	local surface = fakeSurface(400, 400, 100, 100)
	local hoverEvents = 0
	local p = press({
		Scope = scope,
		OnHoverChanged = function(h) if h then hoverEvents += 1 end end,
	}, surface)

	-- Mid-transition: the control slides under a stationary pointer.
	settled = false
	surface.AbsolutePosition = { X = 0, Y = 0 }
	PointerRouter._SimulateGeometryChange(50, 50)
	assert(hoverEvents == 0, `an animating window must not fire hover, got {hoverEvents}`)

	-- A REAL pointer move still resolves: the user genuinely pointed at it.
	PointerRouter._SimulateHover(50, 50)
	assert(hoverEvents == 1, `a real pointer move must still hover, got {hoverEvents}`)

	-- Once settled, geometry-driven hover works again — Section 10 depends on it.
	PointerRouter._SimulateHover(900, 900)
	settled = true
	surface.AbsolutePosition = { X = 880, Y = 880 }
	PointerRouter._SimulateGeometryChange(900, 900)
	assert(hoverEvents == 2, `a settled scope resumes live hover, got {hoverEvents}`)

	p.Destroy()
	scope.Destroy()
	print("  ✓ transition suppresses self-inflicted hover")
end

-- ms-43 M26: clicking the topbar while a modal was open activated the modal's
-- BARRIER, not the topbar button.
--
-- The menu still closed — by dismissal rather than by toggle — so it looked
-- correct, but the click-away sound played and the button's own Activated never
-- fired. Traced from a real traceback, after two wrong diagnoses by reasoning:
--     MotionShowcaseMenuUI  function close
--     InputScope:354        function OnActivated   <- the barrier
--     PointerRouter         function onInputEnded
--
-- Cause: scope depth is compared before Priority, and a control with no scope
-- fell through to depth 0. A topbar button therefore lost to every modal, and
-- its `Priority = 1` was never reached. It declares its LAYER now, which places
-- it in the same coordinate system as the windows it sits above.
local function testLayerBeatsModalBarrier()
	print("[TEST] PointerRouter: a topbar control outranks an open modal's barrier...")
	LayerManager._ResetLayer("Windows")
	LayerManager._ResetLayer("Topbar")

	local modal = InputScope.new({ Id = "Window", Layer = "Windows", Policy = "Modal" })

	local barrierFired, topbarFired = 0, 0
	local barrier = press({
		Scope = modal, Priority = -1,
		OnActivated = function() barrierFired += 1 end,
	}, fakeSurface(0, 0, 2000, 2000))

	-- No Scope: it is not a window. It belongs to the Topbar LAYER.
	local topbar = press({
		Layer = "Topbar",
		OnActivated = function() topbarFired += 1 end,
	}, fakeSurface(0, 0, 40, 40))

	-- Click the topbar button while the modal is open. Both cover the point.
	PointerRouter._SimulatePress(20, 20)
	PointerRouter._SimulateRelease(20, 20)
	assert(topbarFired == 1 and barrierFired == 0,
		`the topbar button must win, got topbar={topbarFired} barrier={barrierFired}`)

	-- Away from the topbar, the barrier still owns the click — dismissal works.
	PointerRouter._SimulatePress(900, 900)
	PointerRouter._SimulateRelease(900, 900)
	assert(barrierFired == 1, `click-away must still reach the barrier, got {barrierFired}`)

	barrier.Destroy()
	topbar.Destroy()
	modal.Destroy()
	print("  ✓ layer bands outrank a modal barrier")
end

-- ms-43 M27: the same win, DERIVED — no Layer, no Priority, nothing declared.
--
-- es9's question after M26: if the topbar were simply parented above the barrier,
-- would arbitration follow on its own? It has to, or "what is on top" is stated
-- twice and the two can disagree. Depth now falls back to the DisplayOrder of the
-- ScreenGui a control renders in, so TopbarButton declares neither.
local function testRenderPlacementBeatsModalBarrier()
	print("[TEST] PointerRouter: a control parented above a modal wins with nothing declared...")
	LayerManager._ResetLayer("Windows")

	local modal = InputScope.new({ Id = "Window", Layer = "Windows", Policy = "Modal" })

	local barrierFired, topbarFired = 0, 0
	local barrier = press({
		Scope = modal, Priority = -1,
		OnActivated = function() barrierFired += 1 end,
	}, fakeSurface(0, 0, 2000, 2000))

	local topbar = press({
		OnActivated = function() topbarFired += 1 end,
	}, fakeSurfaceIn(LayerManager.Layers.Topbar, 0, 0, 40, 40))

	PointerRouter._SimulatePress(20, 20)
	PointerRouter._SimulateRelease(20, 20)
	assert(topbarFired == 1 and barrierFired == 0,
		`placement alone must win the click, got topbar={topbarFired} barrier={barrierFired}`)

	-- And the converse, which is what stops this becoming a free pass: a control
	-- in a LOWER band is still occluded by the modal that covers it.
	local hudFired = 0
	local hud = press({
		OnActivated = function() hudFired += 1 end,
	}, fakeSurfaceIn(LayerManager.Layers.GameHUD, 800, 800, 60, 60))

	PointerRouter._SimulatePress(820, 820)
	PointerRouter._SimulateRelease(820, 820)
	assert(hudFired == 0 and barrierFired == 1,
		`a HUD control under the modal must stay occluded, got hud={hudFired} barrier={barrierFired}`)

	barrier.Destroy()
	topbar.Destroy()
	hud.Destroy()
	modal.Destroy()
	print("  ✓ render placement decides arbitration, both directions")
end

-- ms-43 M28: hover for surfaces that are NOT controls.
--
-- A tilt card sinks nothing and claims no click, so it is not in the registry —
-- and Flux answered its own hover with a raw rect test. es9 found both ways that
-- diverges from the truth: the card lit up through the topbar drawn OVER it, and
-- through the ScrollingFrame edge that clipped it AWAY (hovering empty space
-- above the menu tilted cards scrolled out of view).
local function testIsPointerOverRespectsCoverAndClipping()
	print("[TEST] PointerRouter: IsPointerOver honours cover and clipping...")
	LayerManager._ResetLayer("Windows")

	-- A card inside a clipping viewport, extending past its bottom edge.
	local viewport: any = fakeSurfaceIn(LayerManager.Layers.Windows, 0, 0, 400, 200)
	viewport.ClipsDescendants = true
	local card: any = fakeSurface(0, 100, 400, 400)
	card.Parent = viewport

	assert(PointerRouter.IsPointerOver(card, 200, 150),
		"the visible half of the card is reachable")
	assert(not PointerRouter.IsPointerOver(card, 200, 300),
		"the clipped half is not, even though the raw rect contains the point")

	-- Now cover the visible half with a topbar-band control.
	local topbar = press({
		OnActivated = function() end,
	}, fakeSurfaceIn(LayerManager.Layers.Topbar, 0, 120, 400, 60))

	assert(not PointerRouter.IsPointerOver(card, 200, 150),
		"a control drawn above the card takes the pointer from it")
	-- The card's visible band is y 100..200 and the cover spans y 120..180, so
	-- y=190 is the strip that is visible AND uncovered.
	assert(PointerRouter.IsPointerOver(card, 200, 190),
		"and only where it actually covers")

	topbar.Destroy()

	-- A control INSIDE the card is not something covering it: the card keeps
	-- tilting while you reach for its own button.
	local ownBtn = press({ OnActivated = function() end }, (function()
		local s = fakeSurface(10, 110, 80, 30)
		s.Parent = card
		return s
	end)())
	assert(PointerRouter.IsPointerOver(card, 40, 120),
		"the card's own control does not occlude the card")
	ownBtn.Destroy()

	print("  ✓ cover, clipping, and self-descendants")
end

-- ms-43 M32: es9 asked whether these primitives compose at scale without
-- redundancy. This is the assertion behind the answer.
--
-- useHover opened a Heartbeat connection PER BOUND ELEMENT, which contradicts the
-- rule stated at the top of this very file. The router owns one frame loop and
-- everything pointer-derived rides it.
local function testFrameBusIsShared()
	print("[TEST] PointerRouter: observers share one loop and release cleanly...")
	local before = PointerRouter._ObserverCount()

	local ticks = { 0, 0, 0 }
	local stops = {}
	for i = 1, 3 do
		stops[i] = PointerRouter.OnFrame(function()
			ticks[i] += 1
		end)
	end
	assert(PointerRouter._ObserverCount() == before + 3,
		`three observers registered, got {PointerRouter._ObserverCount() - before}`)

	PointerRouter._SimulateFrame()
	assert(ticks[1] == 1 and ticks[2] == 1 and ticks[3] == 1,
		`every observer runs once per frame, got {ticks[1]}/{ticks[2]}/{ticks[3]}`)

	-- A throwing observer must not take the others down with it: hover for the
	-- whole screen would die with it otherwise.
	local afterThrow = 0
	local stopBad = PointerRouter.OnFrame(function() error("boom") end)
	local stopGood = PointerRouter.OnFrame(function() afterThrow += 1 end)
	PointerRouter._SimulateFrame()
	assert(afterThrow == 1, `a throwing observer must not stop the rest, got {afterThrow}`)
	stopBad()
	stopGood()

	for _, stop in ipairs(stops) do
		stop()
	end
	assert(PointerRouter._ObserverCount() == before,
		`unsubscribing releases every observer, got {PointerRouter._ObserverCount() - before}`)
	print("  ✓ one shared loop, isolated failures, clean release")
end

local function testDisabledAndDisposal()
	print("[TEST] PointerRouter: disabled elements are inert; disposal deregisters...")
	local fired = 0
	local disabled = false
	local before = PointerRouter._Count()
	local p = press({
		Disabled = function() return disabled end,
		OnActivated = function() fired += 1 end,
	}, fakeSurface(0, 0, 100, 100))
	assert(PointerRouter._Count() == before + 1, "registers")

	disabled = true
	PointerRouter._SimulatePress(50, 50)
	PointerRouter._SimulateRelease(50, 50)
	assert(fired == 0, "a disabled element does not activate")

	disabled = false
	PointerRouter._SimulatePress(50, 50)
	PointerRouter._SimulateRelease(50, 50)
	assert(fired == 1, "re-enabling restores it")

	p.Destroy()
	assert(PointerRouter._Count() == before, "Destroy deregisters")
	p.Destroy()
	assert(PointerRouter._Count() == before, "Destroy is idempotent")
	print("  ✓ disabled + disposal")
end

local function testHoverIsExclusive()
	print("[TEST] PointerRouter: hover moves cleanly between elements...")
	local aHover, bHover = false, false
	local a = press({ OnHoverChanged = function(h) aHover = h end }, fakeSurface(0, 0, 100, 100))
	local b = press({ OnHoverChanged = function(h) bHover = h end }, fakeSurface(200, 0, 100, 100))

	PointerRouter._SimulateHover(50, 50)
	assert(aHover and not bHover, "hovering A sets only A")
	PointerRouter._SimulateHover(250, 50)
	assert(not aHover and bHover, "moving to B clears A")
	PointerRouter._SimulateHover(900, 900)
	assert(not aHover and not bHover, "moving to empty space clears both")

	a.Destroy()
	b.Destroy()
	print("  ✓ exclusive hover")
end

-- ms-44: migrated onto testkit. This suite had no harness — bare asserts inside named
-- functions, invoked at the bottom of the file. That is the ms-43 M30 shape: delete an
-- invocation and the file still exits 0 and still reads as coverage. Registered tests
-- make that a VACUOUS failure instead, and give each one a name, a time and a tier in
-- the ##testkit JSON.
local T = require("@testkit")
T.test("activation requires same element", testActivationRequiresSameElement, "math")
T.test("press state tracks", testPressStateTracks, "math")
T.test("topmost wins", testTopmostWins, "math")
T.test("barrier loses to controls", testBarrierLosesToControls, "math")
T.test("lower scope is blocked", testLowerScopeIsBlocked, "math")
T.test("render order beats registration order", testRenderOrderBeatsRegistrationOrder, "math")
T.test("clipped elements are not hit", testClippedElementsAreNotHit, "math")
T.test("live hover follows moving content", testLiveHoverFollowsMovingContent, "math")
T.test("live hover can be disabled", testLiveHoverCanBeDisabled, "math")
T.test("resolve scales", testResolveScales, "math")
T.test("unsettled scope suppresses geometry hover", testUnsettledScopeSuppressesGeometryHover, "math")
T.test("layer beats modal barrier", testLayerBeatsModalBarrier, "math")
T.test("render placement beats modal barrier", testRenderPlacementBeatsModalBarrier, "math")
T.test("is pointer over respects cover and clipping", testIsPointerOverRespectsCoverAndClipping, "math")
T.test("frame bus is shared", testFrameBusIsShared, "math")
T.test("disabled and disposal", testDisabledAndDisposal, "math")
T.test("hover is exclusive", testHoverIsExclusive, "math")

return T.run("PointerRouter")
