--!strict
--!tier math
--[=[
	spektr/aether · ScreenStack (was NavigationState until ms-53 D4).

	ONE CASE PER BEHAVIOUR, not one case for the module. This was a single
	`T.test` wrapping every assertion -- which is not a coverage gap, it covered
	exclusivity, categories, modal depth and the lifecycle, but it is a REPORTING
	one: the first failure named only "ScreenStack" and skipped everything after
	it, so one broken behaviour hid the state of the other eight.

	That matters more than it did. ms-53 D4 made both shipped screens depend on
	this, so a failure should say WHICH promise broke.

	Each case resets first. They shared one registry before, so a case could pass
	on state a previous one left behind, and the order they ran in was the order
	they happened to be written.
]=]
local T = require("@testkit")
local ScreenStack = require("../src/ScreenStack")

local function reset()
	ScreenStack.CloseAll()
end

local function testModuleExists()
	reset()
	assert(ScreenStack ~= nil, "ScreenStack module exists")
end

local function testRegisterOpenIsopen()
	reset()
	ScreenStack.Register("TestScreen", { Id = "TestScreen", Category = "Window" })
	assert(ScreenStack.IsOpen("TestScreen")() == false, "screen starts closed")

	ScreenStack.Open("TestScreen")
	assert(ScreenStack.IsOpen("TestScreen")() == true, "screen opens")
end

--- OPENS ITS OWN SCREEN. It asserted "has open screen after open" without
--- opening one -- it passed on a screen a previous block had left open, and the
--- split is what made that visible.
local function testHasopenscreen()
	reset()
	assert(ScreenStack.HasOpenScreen()() == false, "nothing open to begin with")
	ScreenStack.Open("TestScreen", { Category = "Window" })
	assert(ScreenStack.HasOpenScreen()() == true, "has open screen after open")
end

local function testGetopenscreens()
	reset()
	ScreenStack.Open("TestScreen", { Category = "Window" })
	local screens = ScreenStack.GetOpenScreens()()
	assert(#screens == 1, `one screen open, got {#screens}`)
	assert(screens[1] == "TestScreen", "correct screen id")
end

local function testClose()
	reset()
	ScreenStack.Open("TestScreen", { Category = "Window" })
	ScreenStack.Close("TestScreen")
	assert(ScreenStack.IsOpen("TestScreen")() == false, "screen closes")
	assert(ScreenStack.HasOpenScreen()() == false, "no open screens after close")
end

local function testToggle()
	reset()
	ScreenStack.Toggle("TestScreen")
	assert(ScreenStack.IsOpen("TestScreen")() == true, "toggle opens")
	ScreenStack.Toggle("TestScreen")
	assert(ScreenStack.IsOpen("TestScreen")() == false, "toggle closes")
end

local function testExclusiveOpeningBClosesAWhenSameCategoryExclusive()
	reset()
	ScreenStack.Register("ExclA", { Id = "ExclA", Category = "Window", Exclusive = true })
	ScreenStack.Register("ExclB", { Id = "ExclB", Category = "Window", Exclusive = true })
	ScreenStack.Open("ExclA")
	assert(ScreenStack.IsOpen("ExclA")() == true, "ExclA open")

	ScreenStack.Open("ExclB")
	assert(ScreenStack.IsOpen("ExclB")() == true, "ExclB open after exclusive")
	assert(ScreenStack.IsOpen("ExclA")() == false, "ExclA closed by exclusive ExclB")
	ScreenStack.Close("ExclB")
end

local function testNonExclusiveBothStayOpen()
	reset()
	ScreenStack.Register("HudA", { Id = "HudA", Category = "HUD" })
	ScreenStack.Register("HudB", { Id = "HudB", Category = "HUD" })
	ScreenStack.Open("HudA")
	ScreenStack.Open("HudB")
	assert(ScreenStack.IsOpen("HudA")() == true, "HudA stays open")
	assert(ScreenStack.IsOpen("HudB")() == true, "HudB also open")
end

local function testClosecategory()
	reset()
	ScreenStack.CloseCategory("HUD")
	assert(ScreenStack.IsOpen("HudA")() == false, "HudA closed by category")
	assert(ScreenStack.IsOpen("HudB")() == false, "HudB closed by category")
end

local function testHasopencategory()
	reset()
	ScreenStack.Open("ExclA")
	assert(ScreenStack.HasOpenCategory("Window")() == true, "Window category has open screen")
	assert(ScreenStack.HasOpenCategory("Modal")() == false, "Modal category is empty")
	ScreenStack.Close("ExclA")
end

local function testGetmodaldepth()
	reset()
	ScreenStack.Register("Modal1", { Id = "Modal1", Category = "Modal" })
	ScreenStack.Register("Modal2", { Id = "Modal2", Category = "Modal" })
	ScreenStack.Open("Modal1")
	ScreenStack.Open("Modal2")
	assert(ScreenStack.GetModalDepth()() == 2, "modal depth is 2")
	ScreenStack.Close("Modal1")
	assert(ScreenStack.GetModalDepth()() == 1, "modal depth is 1 after close")
end

local function testLifecycleCallbacks()
	reset()
	local openedId = nil
	local closedId = nil
	local unsub1 = ScreenStack.OnScreenOpened(function(id) openedId = id end)
	local unsub2 = ScreenStack.OnScreenClosed(function(id) closedId = id end)

	ScreenStack.Register("CallbackTest", { Id = "CallbackTest", Category = "Window" })
	ScreenStack.Open("CallbackTest")
	assert(openedId == "CallbackTest", "opened callback fired")

	ScreenStack.Close("CallbackTest")
	assert(closedId == "CallbackTest", "closed callback fired")
end

--- ITS OWN SUBSCRIPTIONS. It used to close over the lifecycle case's locals,
--- which only worked while both lived in one function -- the clearest evidence
--- that these were never independent cases.
local function testUnsubscribe()
	reset()
	local openedId = nil
	local unsub = ScreenStack.OnScreenOpened(function(id)
		openedId = id
	end)
	ScreenStack.Open("UnsubTest", { Category = "Window" })
	assert(openedId == "UnsubTest", "the callback fires while subscribed")

	unsub()
	openedId = nil
	ScreenStack.Close("UnsubTest")
	ScreenStack.Open("UnsubTest")
	assert(openedId == nil, "callback not fired after unsubscribe")

	ScreenStack.CloseAll()
	assert(ScreenStack.HasOpenScreen()() == false, "all screens closed after CloseAll")
end

--- PHASE IS THE READ, and `IsOpen` is derived from it (ms-53 D6).
---
--- A caller had two booleans to combine once `wait` existed -- "open" and "on its
--- way" -- and every consumer would have written the same three-way branch
--- slightly differently. One enum, the same shape `Presence.Phase()` already uses
--- an element down.
local function testPhaseReportsTheLifecycle()
	reset()
	assert(ScreenStack.Phase("Ph")() == "closed", "unknown screens read as closed")

	ScreenStack.Open("Ph", { Category = "Window" })
	assert(ScreenStack.Phase("Ph")() == "open", `open, got {ScreenStack.Phase("Ph")()}`)
	assert(ScreenStack.IsOpen("Ph")() == true, "and IsOpen agrees")

	--- CLOSING, not closed: the exit may still be running, and a switcher bar
	--- should not un-highlight a menu that is still on screen. With no
	--- orchestrator bound in this suite nothing settles it, which is exactly the
	--- state being asserted.
	ScreenStack.Close("Ph")
	assert(ScreenStack.Phase("Ph")() == "closing", `closing, got {ScreenStack.Phase("Ph")()}`)
	assert(ScreenStack.IsOpen("Ph")() == false, "and a closing screen is not open")

	ScreenStack._ExitSettled("Ph")
	assert(ScreenStack.Phase("Ph")() == "closed", `closed once the exit settles, got {ScreenStack.Phase("Ph")()}`)
end

--- `sync` is the default and overlaps: the incoming screen is open while the
--- outgoing one is still leaving.
local function testSyncOverlaps()
	reset()
	local cfg = { Category = "Window", Exclusive = true }
	ScreenStack.Open("A", cfg)
	ScreenStack.Open("B", cfg)
	assert(ScreenStack.Phase("A")() == "closing", `A should be leaving, got {ScreenStack.Phase("A")()}`)
	assert(ScreenStack.Phase("B")() == "open", `B should be open already, got {ScreenStack.Phase("B")()}`)
end

--- `wait` sequences: the incoming screen is PENDING until the outgoing one has
--- finished, and only then opens. This is Vue's `out-in` and Framer's `wait`.
local function testWaitSequences()
	reset()
	local cfg = { Category = "Window", Exclusive = true, SwitchMode = "wait" }
	ScreenStack.Open("A", cfg)
	ScreenStack.Open("B", cfg)
	assert(ScreenStack.Phase("A")() == "closing", `A should be leaving, got {ScreenStack.Phase("A")()}`)
	assert(ScreenStack.Phase("B")() == "pending", `B should be pending, got {ScreenStack.Phase("B")()}`)
	assert(ScreenStack.IsOpen("B")() == false, "a pending screen is not open")

	ScreenStack._ExitSettled("A")
	assert(ScreenStack.Phase("A")() == "closed", "A is gone")
	assert(ScreenStack.Phase("B")() == "open", `B opens once A has left, got {ScreenStack.Phase("B")()}`)
end

--- A CONFIG PASSED TO `Open` ALWAYS APPLIES. It used to be honoured only on the
--- first call, so a screen opened once with `sync` ignored `wait` forever after --
--- which is how the mode looked implemented and did nothing.
local function testOpenReappliesItsConfig()
	reset()
	ScreenStack.Open("Cfg", { Category = "Window", Exclusive = true, SwitchMode = "sync" })
	ScreenStack.Close("Cfg")
	ScreenStack._ExitSettled("Cfg")
	ScreenStack.Open("Cfg", { Category = "Window", Exclusive = true, SwitchMode = "wait" })
	local entry = ScreenStack.GetEntry("Cfg")
	assert(entry and entry.SwitchMode == "wait",
		`the second config should win, got {if entry then tostring(entry.SwitchMode) else "no entry"}`)
end

T.test("module exists", testModuleExists, "math")
T.test("Register + Open + IsOpen", testRegisterOpenIsopen, "math")
T.test("HasOpenScreen", testHasopenscreen, "math")
T.test("GetOpenScreens", testGetopenscreens, "math")
T.test("Close", testClose, "math")
T.test("Toggle", testToggle, "math")
T.test("Exclusive — opening B closes A when same category + exclusive", testExclusiveOpeningBClosesAWhenSameCategoryExclusive, "math")
T.test("Non-exclusive — both stay open", testNonExclusiveBothStayOpen, "math")
T.test("CloseCategory", testClosecategory, "math")
T.test("HasOpenCategory", testHasopencategory, "math")
T.test("GetModalDepth", testGetmodaldepth, "math")
T.test("Lifecycle callbacks", testLifecycleCallbacks, "math")
T.test("Unsubscribe", testUnsubscribe, "math")

T.test("Phase reports the lifecycle", testPhaseReportsTheLifecycle, "math")
T.test("sync overlaps the outgoing and incoming screens", testSyncOverlaps, "math")
T.test("wait sequences them", testWaitSequences, "math")
T.test("a config passed to Open always applies", testOpenReappliesItsConfig, "math")

return T.run("ScreenStack")