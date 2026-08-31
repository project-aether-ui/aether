--!strict
--!tier math
--[=[
	spektr/aether · useSelection (ms-53 D7).

	One of N, locally owned. NO CLOCK AND NO FLUX: the exit predicate is a table
	of booleans this file writes, which is the same seam `Presence` takes and for
	the same reason -- a sampled spring cannot be stepped from a suite.

	WHAT THESE CASES ARE FOR. Three of them exist because the equivalent bug has
	already shipped at the screen level:

	  * `wait` behaving identically to `sync` (D6 found exactly that, twice --
	    once from a config that was applied only on first registration, once from
	    a pending open that waited on the wrong thing).
	  * a panel that renders while PENDING, which makes `wait` a no-op in the one
	    way a phase assertion alone would not notice.
	  * a group whose parent has left still rendering, which is the whole reason
	    `Inherit` exists.

	READS ADVANCE THE MACHINE. `useSelection` is pull-based like `Presence`, so a
	case that mutates without reading has not moved it. The `Presence` suite was
	caught by this in D4; the fixture here reads on every step for the same reason.
]=]
local T = require("@testkit")
local Aether = require("../src/api")

local host = Aether.Host.detect()
host.InstallVocabulary()

local useSelection = require("../src/useSelection")
local Presence = require("../src/Presence")

--- A group over three items whose exits are driven by hand.
local function fixture(mode: string?, inherit: Presence.Handle?)
	local animating: { [string]: boolean } = {}
	local value = host.source("a")
	local group = useSelection.new({
		Items = { "a", "b", "c" },
		Value = value,
		OnChange = function(id: string)
			value(id)
		end,
		SwitchMode = mode :: any,
		StillAnimating = function(id: string): boolean
			return animating[id] == true
		end,
		Inherit = inherit,
	})
	return {
		Group = group,
		--- Selecting through the handle, which reports upward and lets the
		--- caller's source move -- the controlled path every real call site takes.
		Select = function(id: string)
			group.Select(id)
			group.Value()
		end,
		Animating = function(id: string, v: boolean)
			animating[id] = v
			group.Value()
		end,
	}
end

local function testTheDefaultIsOpenAndTheOthersAreNot()
	local f = fixture()
	assert(f.Group.Phase("a") == "open", `a should be open, got {f.Group.Phase("a")}`)
	assert(f.Group.Phase("b") == "closed", `b should be closed, got {f.Group.Phase("b")}`)
	assert(f.Group.ShouldRender("a") == true, "the open item renders")
	assert(f.Group.ShouldRender("b") == false, "a closed item does not")
end

--- SYNC: the incoming item opens at once, and the outgoing one is still on
--- screen animating out underneath it. BOTH render, which is what `sync` means.
local function testSyncOverlaps()
	local f = fixture("sync")
	f.Animating("a", true)
	f.Select("b")

	assert(f.Group.Phase("b") == "open", `b should be open at once, got {f.Group.Phase("b")}`)
	assert(f.Group.Phase("a") == "closing", `a should be closing, got {f.Group.Phase("a")}`)
	assert(f.Group.ShouldRender("a") == true, "the outgoing item keeps rendering while it animates")
	assert(f.Group.ShouldRender("b") == true, "and the incoming one is already rendering")

	f.Animating("a", false)
	assert(f.Group.Phase("a") == "closed", `a should be closed once settled, got {f.Group.Phase("a")}`)
	assert(f.Group.ShouldRender("a") == false, "and it stops rendering")
end

--- WAIT: the incoming item is held until the outgoing one has finished. This is
--- the case D6 found shipped-but-inert at the screen level, and the assertion
--- that separates the two modes is that `b` is NOT open here.
local function testWaitSequences()
	local f = fixture("wait")
	f.Animating("a", true)
	f.Select("b")

	assert(f.Group.Phase("a") == "closing", `a should be closing, got {f.Group.Phase("a")}`)
	assert(f.Group.Phase("b") == "pending", `b should be PENDING under wait, got {f.Group.Phase("b")}`)
	--- THE ONE THAT MAKES THE MODE REAL. A pending panel that renders is a
	--- `wait` that looks sequenced in the phase and overlaps on screen.
	assert(f.Group.ShouldRender("b") == false, "a pending item must NOT render yet")
	assert(f.Group.ShouldRender("a") == true, "and the outgoing one still does")

	f.Animating("a", false)
	assert(f.Group.Phase("b") == "open", `b should promote once a settles, got {f.Group.Phase("b")}`)
	assert(f.Group.ShouldRender("b") == true, "and now it renders")
	assert(f.Group.ShouldRender("a") == false, "while a is gone")
end

--- The two modes must actually DIFFER. Asserting each alone is satisfiable by an
--- implementation that ignores the option entirely -- which is precisely how D6's
--- `wait` shipped inert and looked implemented.
local function testTheModesDiffer()
	local s = fixture("sync")
	s.Animating("a", true)
	s.Select("b")

	local w = fixture("wait")
	w.Animating("a", true)
	w.Select("b")

	assert(s.Group.Phase("b") ~= w.Group.Phase("b"),
		`sync and wait must differ; both reported {s.Group.Phase("b")}`)
end

--- BACK AND FORTH. A one-way switch passes every case above.
local function testItSwitchesBothWays()
	local f = fixture("sync")
	f.Select("b")
	assert(f.Group.Phase("b") == "open", "b opened")
	f.Select("a")
	assert(f.Group.Phase("a") == "open", `a should reopen, got {f.Group.Phase("a")}`)
	assert(f.Group.ShouldRender("a") == true, "and render again -- the exit latch must clear")
end

--- INHERITANCE. A panel inside a window that has left must leave with it, no
--- matter what the selection says.
local function testAPanelLeavesWithItsParent()
	local parentOpen = host.source(true)
	local parentAnimating = false
	local parent = Presence.new({
		Present = function()
			return parentOpen()
		end,
		StillAnimating = function()
			return parentAnimating
		end,
	})
	local f = fixture("sync", parent)

	assert(f.Group.ShouldRender("a") == true, "open inside an open parent")

	--- The window starts closing. The panel is still on screen, sliding out with
	--- it -- NOT gone, which is the case a naive `parent and mine` would get wrong.
	parentAnimating = true
	parentOpen(false)
	assert(f.Group.ShouldRender("a") == true, "while the window animates out, its panel is still drawn")

	parentAnimating = false
	assert(f.Group.ShouldRender("a") == false, "once the window has gone, so has the panel")

	--- AND IT COMES BACK. Without clearing the child's latch, a menu could be
	--- opened exactly once per lifetime.
	parentOpen(true)
	assert(f.Group.ShouldRender("a") == true, "reopening the window brings its panel back")
end

--- Selecting the item that is already open must not start an exit. Without the
--- guard the group would close and reopen the same panel on every click.
local function testReselectingIsANoOp()
	local f = fixture("sync")
	f.Animating("a", true)
	f.Select("a")
	assert(f.Group.Phase("a") == "open", `re-selecting the open item kept it open, got {f.Group.Phase("a")}`)
end

T.test("the default is open and the others are not", testTheDefaultIsOpenAndTheOthersAreNot, "math")
T.test("sync overlaps the outgoing and incoming panels", testSyncOverlaps, "math")
T.test("wait sequences them", testWaitSequences, "math")
T.test("sync and wait actually differ", testTheModesDiffer, "math")
T.test("it switches both ways", testItSwitchesBothWays, "math")
T.test("a panel leaves with its parent, and comes back", testAPanelLeavesWithItsParent, "math")
T.test("re-selecting the open item is a no-op", testReselectingIsANoOp, "math")

return T.run("useSelection")
