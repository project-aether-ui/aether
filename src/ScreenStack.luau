--!strict
--[[
	ScreenStack: which screens are open, and which close which.

	The application registers screens, opens and closes them, and configures
	policies (Exclusive, Category). Components and game systems consume reactive
	getters rather than coupling to each other.

	IT IS NOT A ROUTER, and it was called `NavigationState` until ms-53 D4, which
	implied one. Routing on the web means URL, history, deep links and data
	loading; Roblox has no URL and there is nothing here to route. What this
	models -- named screens with categories (`Window | Modal | HUD`), exclusivity,
	modal depth and lifecycle hooks -- is what the web calls an OVERLAY STACK, and
	every headless library keeps that in-library: Radix has `DismissableLayer` and
	a dialog stack, Zag has dismissable and focus-trap machines. React Router is a
	separate package because URLs are, and none of that applies here.

	`ScreenStack` rather than `OverlayStack` because every id in this codebase is
	already a `screenId` and the stack holds HUDs as well as overlays.

	IT DOES NOT OWN TRANSITIONS OR RENDERING. `TransitionOrchestrator` binds a
	screen's animation; `Presence` decides whether any one element should be drawn
	while that animation runs. This only tracks what is logically open.
]]

local Deps = require("./Deps")
local vide = Deps.vide

local source = if vide then vide.source else function(defaultVal: any)
	local current = defaultVal
	return function(newVal: any?)
		if newVal ~= nil then
			current = newVal
		end
		return current
	end
end

export type ScreenCategory = "Window" | "Modal" | "HUD"

export type ScreenEntry = {
	Id: string,
	Category: ScreenCategory,
	--- How an exclusive open sequences against the screens it closes (ms-53 D6).
	---
	---     sync   both animate at once. The default, and what this always did.
	---     wait   the outgoing screens finish leaving before this one opens.
	---
	--- Framer Motion's names rather than Vue's `out-in`, because an exclusive
	--- open can close SEVERAL screens and `out-in` describes exactly two.
	SwitchMode: (("sync" | "wait"))?,
	Exclusive: boolean?,
}

export type LifecycleCallback = (screenId: string, entry: ScreenEntry?) -> ()

local ScreenStack = {}

-- Internal state
local registry: { [string]: ScreenEntry } = {}
local openScreens: { string } = {} -- ordered by open time
local openSet: { [string]: boolean } = {}

-- Reactive version counter — bumped on any open/close to trigger reactive getters
--- WHAT A SCREEN IS DOING, as one value (ms-53 D6).
---
---     closed   not up, nothing in flight
---     pending  asked for, waiting on another screen's exit (`SwitchMode = "wait"`)
---     open     up
---     closing  asked to close, its exit animation still running
---
--- ONE READ, not two booleans a caller has to combine. `IsOpen` alone cannot
--- express `pending`, and an `IsPending` beside it makes every consumer write the
--- same three-way branch -- differently. `Presence.Phase()` already uses this
--- shape at the element level, so this is the same idiom one layer up rather
--- than a second one.
local phases: { [string]: string } = {}

--- Screens waiting for an exit before they may open, by category. A queue rather
--- than a single slot: an exclusive open closes EVERY other screen in its
--- category, so what it waits on is a set.
local pending: { [string]: { id: string, config: any } } = {}

local version = source(0)
local function bump()
	version(version() + 1)
end

-- Lifecycle listeners
local onOpenedListeners: { LifecycleCallback } = {}
local onClosingListeners: { LifecycleCallback } = {}
local onClosedListeners: { LifecycleCallback } = {}

local function fireListeners(listeners: { LifecycleCallback }, screenId: string, entry: ScreenEntry?)
	for _, cb in ipairs(listeners) do
		pcall(cb, screenId, entry)
	end
end

--- Register a screen definition. Must be called before Open/Toggle for that screen.
--- Can be called multiple times (idempotent — last registration wins).
function ScreenStack.Register(screenId: string, config: ScreenEntry?)
	local entry: ScreenEntry = if config then config else {
		Id = screenId,
		Category = "Window" :: ScreenCategory,
	}
	entry.Id = screenId
	registry[screenId] = entry
end

--- Open a screen. If the screen's category is Exclusive, closes other screens in the same category first.
function ScreenStack.Open(screenId: string, config: ScreenEntry?)
	--- A CONFIG PASSED HERE ALWAYS APPLIES (ms-53 D6).
	---
	--- This only registered when the screen was UNKNOWN, so a second `Open` with
	--- different options silently kept the first ones -- which contradicts
	--- `Register`'s own contract ("idempotent, last registration wins") and is how
	--- `SwitchMode = "wait"` was ignored on every screen that had been opened once
	--- already.
	if config or not registry[screenId] then
		ScreenStack.Register(screenId, config)
	end

	if openSet[screenId] then
		return -- already open
	end

	local entry = registry[screenId]

	-- Enforce exclusivity: close other screens in the same category
	if entry.Exclusive then
		local toClose: { string } = {}
		for _, otherId in ipairs(openScreens) do
			local otherEntry = registry[otherId]
			if otherEntry and otherEntry.Category == entry.Category and otherId ~= screenId then
				table.insert(toClose, otherId)
			end
		end
		for _, closeId in ipairs(toClose) do
			ScreenStack.Close(closeId)
		end

		--- WAIT FOR THEM TO LEAVE, if the category asks for it (ms-53 D6).
		---
		--- The web calls this a transition MODE. Vue's `<Transition mode>` has
		--- `out-in`; Framer's `<AnimatePresence>` has `sync` and `wait`. Framer's
		--- names are taken here for one reason specific to a stack: `out-in`
		--- describes exactly two participants, and an exclusive open can close
		--- SEVERAL screens at once. `wait` scales to however many there are.
		---
		--- `sync` stays the default, which is what this always did -- both
		--- animations starting on the same frame.
		---
		--- The screen becomes `pending` rather than `open`, and the orchestrator
		--- promotes it when the last exit settles. That is why `Phase` exists: a
		--- caller that only had `IsOpen` could not tell "not up" from "on its way".
		if entry.SwitchMode == "wait" and #toClose > 0 then
			local stillLeaving = false
			for _, closeId in ipairs(toClose) do
				if phases[closeId] == "closing" then
					stillLeaving = true
				end
			end
			if stillLeaving then
				--- WAITS ON AN EXPLICIT SET, not on "is anything in this category
				--- still leaving". Scanning the category means an unrelated screen
				--- stuck mid-exit blocks a promotion that has nothing to do with
				--- it -- which is not hypothetical: it is what a suite with
				--- leftover `closing` screens produced immediately.
				local waitingOn: { [string]: boolean } = {}
				for _, closeId in ipairs(toClose) do
					if phases[closeId] == "closing" then
						waitingOn[closeId] = true
					end
				end
				pending[entry.Category] = { id = screenId, config = config, waitingOn = waitingOn }
				phases[screenId] = "pending"
				bump()
				return
			end
		end
	end

	openSet[screenId] = true
	phases[screenId] = "open"
	table.insert(openScreens, screenId)
	bump()

	fireListeners(onOpenedListeners, screenId, entry)
end

--- The exit for this screen has finished. Called BY the orchestrator, which is
--- the only thing that knows when an animation is over -- and which already
--- subscribes to this module, so pushing the answer back avoids a circular
--- require that pulling it would need.
---
--- A screen with no bound transition settles immediately; the orchestrator says
--- so on the same frame.
function ScreenStack._ExitSettled(screenId: string)
	if phases[screenId] ~= "closing" then
		return
	end
	phases[screenId] = "closed"

	--- Promote whatever was waiting on it. Checked against the CATEGORY rather
	--- than the screen, because what a pending screen waits for is the category
	--- being clear, not one particular occupant of it.
	local entry = registry[screenId]
	local category = if entry then entry.Category else nil
	local queued = if category then pending[category] else nil
	if queued and queued.waitingOn[screenId] then
		queued.waitingOn[screenId] = nil
		local stillWaiting = false
		for _ in pairs(queued.waitingOn) do
			stillWaiting = true
			break
		end
		if not stillWaiting then
			pending[category] = nil
			--- Cleared first, or `Open` sees a `pending` screen and could route
			--- back into the wait branch it is being promoted out of.
			phases[queued.id] = "closed"
			ScreenStack.Open(queued.id, queued.config)
			return
		end
	end
	bump()
end

--- Close a screen.
function ScreenStack.Close(screenId: string)
	if not openSet[screenId] then
		return -- not open
	end

	local entry = registry[screenId]
	fireListeners(onClosingListeners, screenId, entry)

	openSet[screenId] = nil
	--- CLOSING, not closed. The exit animation may still be running, and a caller
	--- asking `Phase` deserves to know the difference -- a switcher bar should not
	--- un-highlight a menu that is still on screen.
	phases[screenId] = "closing"
	local idx = table.find(openScreens, screenId)
	if idx then
		table.remove(openScreens, idx)
	end
	bump()

	fireListeners(onClosedListeners, screenId, entry)
end

--- Toggle a screen open/closed.
function ScreenStack.Toggle(screenId: string, config: ScreenEntry?)
	if openSet[screenId] then
		ScreenStack.Close(screenId)
	else
		ScreenStack.Open(screenId, config)
	end
end

--- Close all screens in a given category.
function ScreenStack.CloseCategory(category: ScreenCategory)
	local toClose: { string } = {}
	for _, screenId in ipairs(openScreens) do
		local entry = registry[screenId]
		if entry and entry.Category == category then
			table.insert(toClose, screenId)
		end
	end
	for _, screenId in ipairs(toClose) do
		ScreenStack.Close(screenId)
	end
end

--- Close all open screens.
function ScreenStack.CloseAll()
	local toClose = table.clone(openScreens)
	for _, screenId in ipairs(toClose) do
		ScreenStack.Close(screenId)
	end
end

-- ═══════════════════════════════════════════════════════════════════
-- Reactive Queries (Vide-compatible getters)
-- ═══════════════════════════════════════════════════════════════════

--- Returns a Vide-compatible getter that returns true when the given screen is open.
--- The screen's lifecycle state, reactive. See `phases` above.
function ScreenStack.Phase(screenId: string): () -> string
	return function(): string
		local _ = version() -- subscribe to reactive updates
		return phases[screenId] or "closed"
	end
end

--- Is it up RIGHT NOW? Derived from `Phase`, so there is one source of truth --
--- a `pending` screen is not open, and a `closing` one is no longer open.
---
--- Kept because most callers only need the boolean, and because every existing
--- one already reads it.
function ScreenStack.IsOpen(screenId: string): () -> boolean
	local phase = ScreenStack.Phase(screenId)
	return function(): boolean
		return phase() == "open"
	end
end

--- Returns true if any screen is currently open.
function ScreenStack.HasOpenScreen(): () -> boolean
	return function(): boolean
		local _ = version()
		return #openScreens > 0
	end
end

--- Returns true if any screen in the given category is open.
function ScreenStack.HasOpenCategory(category: ScreenCategory): () -> boolean
	return function(): boolean
		local _ = version()
		for _, screenId in ipairs(openScreens) do
			local entry = registry[screenId]
			if entry and entry.Category == category then
				return true
			end
		end
		return false
	end
end

--- Returns the list of currently open screen IDs (ordered by open time).
function ScreenStack.GetOpenScreens(): () -> { string }
	return function(): { string }
		local _ = version()
		return table.clone(openScreens)
	end
end

--- Returns the count of open Modal screens.
function ScreenStack.GetModalDepth(): () -> number
	return function(): number
		local _ = version()
		local count = 0
		for _, screenId in ipairs(openScreens) do
			local entry = registry[screenId]
			if entry and entry.Category == "Modal" then
				count += 1
			end
		end
		return count
	end
end

--- Returns the registered ScreenEntry for a given screen ID, or nil.
function ScreenStack.GetEntry(screenId: string): ScreenEntry?
	return registry[screenId]
end

-- ═══════════════════════════════════════════════════════════════════
-- Lifecycle Subscriptions
-- ═══════════════════════════════════════════════════════════════════

--- Subscribe to screen opened events. Returns an unsubscribe function.
function ScreenStack.OnScreenOpened(callback: LifecycleCallback): () -> ()
	table.insert(onOpenedListeners, callback)
	return function()
		local idx = table.find(onOpenedListeners, callback)
		if idx then table.remove(onOpenedListeners, idx) end
	end
end

--- Subscribe to screen closing events (fires before removal). Returns an unsubscribe function.
function ScreenStack.OnScreenClosing(callback: LifecycleCallback): () -> ()
	table.insert(onClosingListeners, callback)
	return function()
		local idx = table.find(onClosingListeners, callback)
		if idx then table.remove(onClosingListeners, idx) end
	end
end

--- Subscribe to screen closed events (fires after removal). Returns an unsubscribe function.
function ScreenStack.OnScreenClosed(callback: LifecycleCallback): () -> ()
	table.insert(onClosedListeners, callback)
	return function()
		local idx = table.find(onClosedListeners, callback)
		if idx then table.remove(onClosedListeners, idx) end
	end
end

return ScreenStack
