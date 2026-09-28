--!strict
--[[
	Aether · core/createDialog -- is it open, what closes it, and which of the
	caller's own elements gets keyboard focus while it is?

	Layer 1. No reactive library, no engine types, no hit-testing of its own,
	same discipline as createPressable/createContextMenu.

	    local dialog = createDialog({ Router = ..., Keys = ..., Source = ... })
	    dialog.RegisterFocusable("close-button", closeButtonElement)
	    dialog.RegisterFocusable("confirm-button", confirmButtonElement)
	    dialog.Open(triggerElement)
	    return create("Frame")(dialog.GetBackdropProps({ ... }))

	RESOLVING OPEN QUESTION 3 (milestone 60 vision doc), BEFORE ANY OF THE
	TRAP LOGIC BELOW WAS WRITTEN: the focus trap lives entirely in Aether's
	own core/, not behind a new Dew host capability, and this is a fact found
	by reading `host/src/datamodel/mod.rs` and `host/src/datamodel/input.rs`
	directly, not assumed from commit subjects.

	`GuiService.SelectedObject` IS REAL AND SETTABLE (`mod.rs:578`
	`set_selected_object`, the setter at `mod.rs:1695-1732` firing
	`SelectionLost`/`SelectionGained` in the engine's own order) -- so a real
	"move keyboard/gamepad selection to X" capability already exists, and
	Aether already has a working, tested binding to it: `SelectionRouter.luau`
	(`Select(element)` sets `GuiService.SelectedObject`, already used by
	`createRadioGroup`/`createTabs`'s own roving focus). That answers the
	"does it need a NEW host capability" half of the question: no, and one
	genuinely does not need building here.

	BUT THIS MACHINE DOES NOT CALL THAT CAPABILITY ITSELF. Two separate
	reasons, both real:

	  1. `core/Selection.luau`'s own `SelectableProps` (`OnKeyActivate`,
	     `OnArrowNext`/`OnArrowPrevious`, `ActivationKeys`) has no Tab/Shift
	     -Tab/Escape vocabulary at all -- it was built for roving arrow-key
	     focus among a flat option list (`createRadioGroup`, `createTabs`),
	     not a trap that cycles a caller-registered set and has to hear Tab
	     specifically. Bending that port to fit would either overload arrow
	     semantics that already mean something else, or grow the shared file
	     two more consumers never asked for -- this sprint's own instruction
	     not to touch shared code without a real, single-consumer-justified
	     need.
	  2. Layer 1 HAS NO DOM TO WALK (confirmed empty by this milestone's own
	     vision doc: zero `*focus*` hits outside vendored packages before this
	     file). It cannot discover which of a caller's elements are
	     focusable, so it needs an explicit registration API regardless of
	     which host capability eventually moves real focus -- see
	     `RegisterFocusable`/`UnregisterFocusable` below.

	So the trap's OWN bookkeeping -- which registered key is "current", Tab/
	Shift-Tab cycling with wraparound, remembering the trigger and restoring
	it on close -- is pure Luau, keyed by the CALLER's own opaque element
	values, exactly the shape `createContextMenu`'s `FocusItem`/`FocusNext`/
	`FocusPrevious` already proved out for a flat list. `OnFocusChanged` is
	the one place a real host capability re-enters: a binding's own callback
	is free to call `SelectionRouter.Select(element)` (or nothing at all, on
	a host offering no selection concept -- `Select` is already a no-op
	there) whenever this machine says "move host focus to `element`". This
	machine never reaches for `SelectionRouter`/`GuiService` itself, the same
	"handed over, never resolved" discipline `createPressable`'s own header
	states for `Router`.

	WHAT "REMEMBERS AND RESTORES" CAN MEAN, GIVEN LAYER 1'S OWN CONSTRAINTS.
	There is no getter anywhere in this codebase for "what has keyboard focus
	right now" independent of this machine's own bookkeeping (`Selection`'s
	own port exposes `Select`, a setter, and nothing that reads
	`GuiService.SelectedObject` back as a Layer-1-legal value). So this
	cannot capture "whatever the OS-level focus happened to be" the instant
	`Open()` ran. What it CAN do, and does, is the real-world standard for an
	accessible dialog anyway: the CALLER hands `Open(trigger)` the element
	that caused the dialog to open (a button's own bound element, typically),
	and `OnFocusChanged(trigger)` fires on close -- returning focus to the
	thing that opened the dialog, not to an unknowable prior global state.

	ESCAPE AND TAB NEED A REAL KEYBOARD SIGNAL LAYER 1 CANNOT SYNTHESISE ON
	ITS OWN, so `Options.Keys` is a small optional capability port, gated the
	same "ask for the capability, not the vendor" way `PointerRouter`'s own
	`setGuiState` gates on `typeof(surface.SetGuiState) == "function"` --
	`type(keys.OnKeyDown) == "function"` here, since `Keys` is a plain table
	this machine was handed rather than a host userdata `typeof` exists to
	distinguish further than `type` already does. Absent or malformed, this
	machine runs with no keyboard trap at all rather than erroring, degrading
	gracefully on a host (or a test) that supplies none. A binding wires
	`Options.Keys.OnKeyDown` to `desktop.Input.InputBegan` on Dew or
	`UserInputService.InputBegan` on real Roblox, filtered to
	`UserInputType.Keyboard` and handing over `input.KeyCode.Name` plus
	whether Shift is held -- the same "plain key name, not a real
	`Enum.KeyCode`" choice `core/Selection.luau` already made and states its
	own reason for (still Layer 1, with no engine type in sight).

	A DIALOG SURFACE VS. A BACKDROP, THE SAME SHAPE `InputSink.luau` ALREADY
	PROVED OUT for a single modal region: the backdrop is the one thing that
	registers a real `Pressable` with the router, at `Priority = -1` (`Input
	Sink.luau`'s own comment: "Priority -1 puts the sink below every control
	inside the window it covers, so a button click never reads as a
	dismiss"). Content inside the dialog registers its OWN pressables at the
	router's default priority through whatever it is (a button, a field),
	which already outranks -1 without this machine doing anything extra --
	so `GetRootProps` is a plain, non-interactive prop set (`Visible`,
	nothing else), and only `GetBackdropProps` reaches the router at all.
]]

local safeWarn = require("./Warn")

--- Read with no arguments, write with one. `vide.source` is exactly this, which
--- is why the binding passes it straight in.
export type Source<T> = ((T) -> T) & (() -> T)

export type SourceFactory = <T>(initial: T) -> Source<T>

--- Wraps a callback so the host runs it against whatever it creates. The result
--- travels in the array part of the prop table.
export type ActionFactory = (callback: (element: any) -> ()) -> any

--- The part of a pointer router this machine uses, and all of it -- the exact
--- shape `createPressable`'s own `Router` already is.
export type RouterHandle = {
	Bind: (element: any) -> (),
	Destroy: () -> (),
}

export type Router = {
	Pressable: (props: { [string]: any }) -> RouterHandle,
}

--- The one keyboard capability this machine needs and cannot synthesise:
--- hearing a named key go down while the dialog is open. `shift` is whether
--- the modifier is held, since Tab and Shift+Tab cycle in opposite
--- directions and this machine has no way to ask a host for modifier state
--- itself.
export type Keys = {
	--- Subscribe for as long as the returned unsubscribe function is not
	--- called. A binding wires this once, globally -- this machine only ever
	--- listens while it considers itself open (see `subscribeKeysIfPossible`).
	OnKeyDown: (callback: (name: string, shift: boolean) -> ()) -> (() -> ()),
}

export type Options = {
	Router: Router,
	Source: SourceFactory?,
	Action: ActionFactory?,

	--- ABSENT ON A HOST (OR A TEST) THAT OFFERS NONE. Escape-to-close and
	--- Tab-cycling both go through this; without it, `Open`/`Close`/
	--- `RegisterFocusable`/`FocusNext`/`FocusPrevious` still work exactly as
	--- documented, called by hand.
	Keys: Keys?,

	--- CONTROLLED, the same shape `createContextMenu`'s own `IsOpen` already
	--- is: a getter, read through rather than copied.
	IsOpen: (() -> boolean)?,
	InitiallyOpen: boolean?,
	OnOpenChanged: ((open: boolean) -> ())?,
	--- Called whenever the dialog stops being open, by Escape, by a backdrop
	--- click, or by a caller's own `Close()`.
	OnClose: (() -> ())?,

	--- Defaults true. A caller building an alert dialog (no dismiss but the
	--- confirm/cancel buttons themselves) sets this false.
	CloseOnBackdropClick: boolean?,
	--- Defaults true, same reason.
	CloseOnEscape: boolean?,

	--- Fires whenever this machine decides real keyboard focus should move
	--- to `element` -- the element most recently registered as current, or
	--- the remembered trigger on close, or nil when nothing registered is
	--- left to focus. A binding's own handler is the one place a real host
	--- capability (`SelectionRouter.Select`, or nothing at all) re-enters;
	--- this machine never reaches for one itself.
	OnFocusChanged: ((element: any?) -> ())?,
}

export type Dialog = {
	IsOpen: () -> boolean,
	--- `trigger`, if given, is what regains focus when this dialog closes --
	--- typically the element whose activation opened it.
	Open: (trigger: any?) -> (),
	Close: () -> (),
	Toggle: () -> (),

	--- LAYER 1 HAS NO DOM TO WALK, so a caller registers each of its own
	--- elements that should take part in the tab order, in the order it
	--- wants them cycled. Re-registering an already-known key updates its
	--- element in place rather than duplicating an entry.
	RegisterFocusable: (key: any, element: any) -> (),
	--- Removes a key from the tab order. If it was the current one, focus
	--- moves to nothing (fires `OnFocusChanged(nil)`) rather than guessing at
	--- a neighbour -- an element unregistering itself is usually being
	--- destroyed, and handing focus to whatever happens to sit next to it in
	--- the list is not this machine's decision to make quietly.
	UnregisterFocusable: (key: any) -> (),
	FocusNext: () -> (),
	FocusPrevious: () -> (),
	--- Which registered key currently holds the trap's own notion of focus,
	--- or nil. Exposed for a test (and a binding) to read without having to
	--- infer it from `OnFocusChanged` calls.
	CurrentFocusKey: Source<any?>,

	GetRootProps: (overrides: { [any]: any }?) -> { [any]: any },
	GetBackdropProps: (overrides: { [any]: any }?) -> { [any]: any },
	Destroy: () -> (),
}

--- Options that belong to this machine and must not reach the element -- the
--- same deny-list-over-allow-list reasoning `createPressable`'s own comment
--- states.
local MACHINE_OPTIONS: { [string]: true } = {
	Router = true,
	Source = true,
	Action = true,
	Keys = true,
	IsOpen = true,
	InitiallyOpen = true,
	OnOpenChanged = true,
	OnClose = true,
	CloseOnBackdropClick = true,
	CloseOnEscape = true,
	OnFocusChanged = true,
}

local function plainSource<T>(initial: T): Source<T>
	local value = initial
	return (
		function(...): T
			if select("#", ...) > 0 then
				value = (select(1, ...) :: any) :: T
			end
			return value
		end :: any
	) :: Source<T>
end

local function identityAction(callback: (element: any) -> ()): any
	return callback
end

--- Shared by `GetRootProps` and `GetBackdropProps` -- the same merge
--- `createContextMenu.luau`'s own `merge` already is.
local function merge(defaults: { [any]: any }, overrides: { [any]: any }?): { [any]: any }
	if not overrides then
		return defaults
	end
	for key, value in pairs(overrides) do
		if type(key) == "number" then
			if value ~= nil then
				table.insert(defaults, value)
			end
		elseif MACHINE_OPTIONS[key :: any] or value == nil then
			continue
		elseif type(key) == "string" and string.match(key, "^On%u") then
			safeWarn(`createDialog: "{key}" is not a handler this machine recognises and was dropped`)
			continue
		else
			defaults[key] = value
		end
	end
	return defaults
end

local function createDialog(options: Options): Dialog
	local router = options.Router
	if not router or not router.Pressable then
		error("createDialog needs a Router -- the binding has one, and hands it over", 2)
	end

	local newSource: SourceFactory = options.Source or plainSource
	local action: ActionFactory = options.Action or identityAction

	local controlled = options.IsOpen
	local openSource = newSource(options.InitiallyOpen == true)
	local currentFocusKey: Source<any?> = newSource(nil :: any)

	local focusables: { { Key: any, Element: any } } = {}
	local trigger: any = nil
	local keysUnsubscribe: (() -> ())? = nil

	local function isOpen(): boolean
		if controlled then
			return controlled() == true
		end
		return openSource()
	end

	local function indexOfKey(key: any): number?
		for index, entry in ipairs(focusables) do
			if entry.Key == key then
				return index
			end
		end
		return nil
	end

	local function elementForKey(key: any?): any
		if key == nil then
			return nil
		end
		local index = indexOfKey(key)
		if not index then
			return nil
		end
		return focusables[index].Element
	end

	local function setFocusKey(key: any?)
		if currentFocusKey() == key then
			return
		end
		currentFocusKey(key)
		if options.OnFocusChanged then
			options.OnFocusChanged(elementForKey(key))
		end
	end

	local function focusFirst()
		if #focusables == 0 then
			setFocusKey(nil)
			return
		end
		setFocusKey(focusables[1].Key)
	end

	--- Tab (`step = 1`) or Shift+Tab (`step = -1`), wrapping either way -- the
	--- same "no focusable is a dead end" standard `createContextMenu`'s own
	--- `move` already holds arrow-key navigation to.
	local function move(step: number)
		if #focusables == 0 then
			return
		end
		local from = indexOfKey(currentFocusKey())
		local nextIndex: number
		if from == nil then
			nextIndex = if step > 0 then 1 else #focusables
		else
			nextIndex = (from - 1 + step) % #focusables + 1
		end
		setFocusKey(focusables[nextIndex].Key)
	end

	local close: () -> ()

	local function onKeyDown(name: string, shift: boolean)
		if not isOpen() then
			return
		end
		if name == "Escape" then
			if options.CloseOnEscape ~= false then
				close()
			end
			return
		end
		if name == "Tab" then
			move(if shift then -1 else 1)
		end
	end

	local function unsubscribeKeys()
		if keysUnsubscribe then
			keysUnsubscribe()
			keysUnsubscribe = nil
		end
	end

	local function subscribeKeysIfPossible()
		if keysUnsubscribe then
			return
		end
		local keys = options.Keys
		if keys and type(keys.OnKeyDown) == "function" then
			keysUnsubscribe = keys.OnKeyDown(onKeyDown)
		end
	end

	local function setOpen(wantOpen: boolean, openTrigger: any?)
		local was = isOpen()
		if not controlled then
			openSource(wantOpen)
		end

		if wantOpen then
			if openTrigger ~= nil then
				trigger = openTrigger
			end
			subscribeKeysIfPossible()
			focusFirst()
		else
			unsubscribeKeys()
			local restoreTo = trigger
			trigger = nil
			--- Silent, not through `setFocusKey`: there is nothing left to
			--- register `OnFocusChanged` against inside a closed dialog, and
			--- the restore call below is the one that matters here.
			currentFocusKey(nil)
			if options.OnFocusChanged then
				options.OnFocusChanged(restoreTo)
			end
		end

		if was == wantOpen then
			return
		end
		if options.OnOpenChanged then
			options.OnOpenChanged(wantOpen)
		end
		if not wantOpen and options.OnClose then
			options.OnClose()
		end
	end

	local function open(openTrigger: any?)
		setOpen(true, openTrigger)
	end

	close = function()
		setOpen(false)
	end

	local function toggle()
		setOpen(not isOpen())
	end

	local function registerFocusable(key: any, element: any)
		if key == nil then
			safeWarn("createDialog: RegisterFocusable needs a key, got nil")
			return
		end
		local index = indexOfKey(key)
		if index then
			focusables[index].Element = element
			return
		end
		table.insert(focusables, { Key = key, Element = element })
		if isOpen() and currentFocusKey() == nil then
			setFocusKey(key)
		end
	end

	local function unregisterFocusable(key: any)
		local index = indexOfKey(key)
		if not index then
			return
		end
		table.remove(focusables, index)
		if currentFocusKey() == key then
			setFocusKey(nil)
		end
	end

	--- REGISTERED ONCE, AT CONSTRUCTION -- the same moment `createPressable`
	--- calls `router.Pressable` in its own body rather than inside
	--- `GetRootProps`. Doing it inside `getBackdropProps` would re-register
	--- (and leak a handle) every time a binding re-renders and asks for the
	--- backdrop's props again.
	local backdropHandle = router.Pressable({
		--- THE SAME `Priority = -1` `InputSink.luau` ALREADY PROVED OUT: a
		--- control inside the dialog registers its own pressable at the
		--- router's default priority, which already outranks this without
		--- `createDialog` doing anything else to arrange it.
		Priority = -1,
		HitTestable = true,
		OnActivated = function()
			if options.CloseOnBackdropClick ~= false then
				close()
			end
		end,
	})

	local function getRootProps(overrides: { [any]: any }?): { [any]: any }
		return merge({
			Name = "Dialog",
			Visible = isOpen,
		}, overrides)
	end

	local function getBackdropProps(overrides: { [any]: any }?): { [any]: any }
		local props = merge({
			Name = "DialogBackdrop",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = isOpen,
		}, overrides)
		table.insert(props, action(backdropHandle.Bind))
		return props
	end

	local destroyed = false
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		unsubscribeKeys()
		backdropHandle.Destroy()
		focusables = {}
		trigger = nil
		currentFocusKey(nil)
		if not controlled then
			openSource(false)
		end
	end

	return {
		IsOpen = isOpen,
		Open = open,
		Close = close,
		Toggle = toggle,

		RegisterFocusable = registerFocusable,
		UnregisterFocusable = unregisterFocusable,
		FocusNext = function()
			move(1)
		end,
		FocusPrevious = function()
			move(-1)
		end,
		CurrentFocusKey = currentFocusKey,

		GetRootProps = getRootProps,
		GetBackdropProps = getBackdropProps,
		Destroy = destroy,
	}
end

return {
	createDialog = createDialog,
}
