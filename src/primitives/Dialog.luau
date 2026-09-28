--!strict
--[=[
	Aether · primitives/Dialog — a real, instance-creating composition of
	three already-real machines, none of which knows about the other two:

	    core/createDialog     -- IS IT OPEN, and the keyboard focus trap
	                              (RegisterFocusable/FocusNext/FocusPrevious,
	                              Escape, a backdrop Pressable at Priority -1)
	    core/Presence          -- should this element still be RENDERED right
	                              now, given it may be mid-exit-animation
	    ScreenStack             -- WHICH screens are open, so a second Dialog
	                              opened while this one is up stacks over it
	                              instead of the two fighting for the same
	                              backdrop/trap

	Part of Aether.Primitives (Layer 2B Composite), the same tier
	`ContextMenu.luau` occupies: `core/createDialog` decides what is true
	and hands back props for it; this file supplies the reactive graph,
	the router, the real host services a Layer 1 machine cannot have, and
	draws the tree.

	    local isOpen = vide.source(false)
	    Dialog({
	        Id = "confirm-delete",
	        IsOpen = isOpen,
	        OnClose = function() isOpen(false) end,
	        Title = "Delete this?",
	        Children = function(dialog)
	            return create("TextButton")(dialog.RegisterFocusable...)
	        end,
	    })

	THE CONTROLLED STATE IS THE CALLER'S, the same shape every other
	Primitive's own `IsOpen` already is (`ContextMenu`, `Combobox`). What is
	NOT the caller's: which of `createDialog`'s own machinery reacts to a
	given keystroke when TWO dialogs are open at once, and when the
	backdrop dims versus when the surface actually leaves the tree. Both
	are this file's job, argued below.

	ONE INTERNAL SOURCE OF TRUTH, NOT TWO KEPT IN SYNC BY HAND. `createDialog`
	is left UNCONTROLLED here (no `Options.IsOpen`) so it owns one boolean of
	its own, and this file only ever pushes `props.IsOpen()` INTO it with
	`dialog.Open()`/`dialog.Close()` — reading `dialog.IsOpen()` first (via
	`Deps.peek`, a GUARD read, not one the surrounding effect should react to)
	to skip a call that would be a no-op. WHY THE GUARD MATTERS: `createDialog`
	itself runs its own focus-restore bookkeeping UNCONDITIONALLY inside
	`Close()` (it clears `trigger` and fires `OnFocusChanged` every call, not
	only on an actual open→closed edge) — so calling `Close()` a second time
	after Escape or a backdrop click already closed it would fire
	`OnFocusChanged(nil)` right after the real one restored the trigger,
	wiping out the restore this same keystroke just performed. Escape, a
	backdrop click and the close button all close the dialog by calling
	`dialog.Close()` DIRECTLY (not by asking the caller first), so
	`OnOpenChanged`/`OnClose` (below) are the one seam that tells both
	`ScreenStack` and the caller a transition happened, whichever side
	started it, and the guard above is what keeps this file's own sync
	effect from replaying a transition `createDialog` already ran.

	STACKING, ARGUED RATHER THAN ASSUMED. `ScreenStack.Register` puts every
	Dialog instance in the `"Modal"` category, NOT `Exclusive` — two dialogs
	genuinely can be open at once (a confirm dialog over a form dialog), so
	opening a second must not silently close the first. But `createDialog`'s
	own Keys port is subscribed by EVERY open instance independently
	(`subscribeKeysIfPossible` runs on each one's own `Open()`), so with two
	open at once an unguarded `UserInputService.InputBegan` handler here
	would let one Escape press close BOTH and one Tab press cycle BOTH
	traps' bookkeeping on the same keystroke — the exact defect this
	sprint's own success criterion (keyboard focus must never escape the
	backdrop) would produce for the OLDER dialog the instant a newer one
	opened on top of it. `isTopmostModal` below is the fix: it asks
	`ScreenStack` — which both instances already register with, with no
	coordination between them beyond that — whether THIS instance's own
	`screenId` is the last `"Modal"`-category entry in the open list, and
	the real `InputBegan` handler drops the keystroke on the floor for
	every dialog that answers no. The older dialog's trap goes quiet the
	moment a newer one opens, and answers again the instant the newer one
	closes, with no explicit hand-off between the two.

	SHIFT HAS NO RELEASE SIGNAL ON THIS HOST YET, confirmed by reading
	`host/src/services.rs` directly (`key_down`'s own doc comment: "PRESS
	ONLY, NO RELEASE... `InputEnded` has no keyboard side yet"). So a real
	Shift+Tab is detected the only way this host's own capability allows:
	`LeftShift`/`RightShift` going down latches a flag, consumed (cleared)
	the moment the next key is handled — right for the ordinary case (a
	physical Shift+Tab fires "LeftShift" then "Tab" in that order) and
	honestly degraded rather than silently wrong for a Shift held across
	SEVERAL bare Tab presses with no repeated `LeftShift` event, which this
	host cannot observe without a keyboard `InputEnded` it does not yet
	fire. Reported here rather than routed around with an invented signal.
]=]

local Deps = require("../Deps")
local RouterContext = require("../RouterContext")
local Presence = require("../core/Presence")
local ScreenStack = require("../ScreenStack")
local TransitionOrchestrator = require("../TransitionOrchestrator")
local SelectionRouter = require("../SelectionRouter")
local KeysRouter = require("../KeysRouter")
local Pressable = require("./Pressable")

local coreDialog = require("../core/createDialog")
local createDialog = coreDialog.createDialog

local vide = Deps.vide
local create = vide.create
local action = vide.action
local cleanup = vide.cleanup
local peek = Deps.peek
local useRouter = RouterContext.useRouter

local nextId = 0
local function generateScreenId(): string
	nextId += 1
	return "Dialog_" .. tostring(nextId)
end

--- Is `screenId` the LAST `"Modal"`-category screen `ScreenStack` currently
--- has open? The one question that lets several Dialog instances share one
--- real `KeysRouter` subscription without coordinating with each other
--- directly — see this file's own header for why an unguarded Escape/Tab
--- handler would otherwise answer to every open dialog at once, not only
--- the topmost.
local function isTopmostModal(screenId: string): boolean
	local openScreens = peek(ScreenStack.GetOpenScreens())
	for index = #openScreens, 1, -1 do
		local otherId = openScreens[index]
		local entry = ScreenStack.GetEntry(otherId)
		if entry and entry.Category == "Modal" then
			return otherId == screenId
		end
	end
	return false
end

--- THE ONE PLACE `ScreenStack` LEARNS THIS DIALOG MOVED, whichever side
--- started it — an external `IsOpen` flip or an internal Escape/backdrop
--- /close-button call, both funnel through `createDialog`'s own `setOpen`,
--- which calls `Options.OnOpenChanged` exactly once per real open→closed
--- or closed→open edge. Named and hoisted, rather than written inline in
--- the `createDialog` options table below, so that table stays a plain
--- reference (`OnOpenChanged = onScreenOpenChanged(...)`) rather than a
--- press-handler literal.
local function onScreenOpenChanged(screenId: string, forwardTo: ((boolean) -> ())?): (boolean) -> ()
	return function(open: boolean)
		if open then
			ScreenStack.Open(screenId)
		else
			ScreenStack.Close(screenId)
		end
		if forwardTo then
			forwardTo(open)
		end
	end
end

export type DialogProps = {
	--- `ScreenStack` identity. Auto-generated when omitted — only worth
	--- naming when a caller wants to reach this dialog by id elsewhere
	--- (`ScreenStack.GetEntry`, a category close-all).
	Id: string?,
	Name: string?,

	--- CONTROLLED, the same shape `ContextMenu`'s own `IsOpen` already is.
	IsOpen: () -> boolean,
	--- Fires whenever this machine (Escape, a backdrop click, the close
	--- button, or a caller's own request) decides the dialog should close.
	--- A controlled caller's own handler is expected to flip whatever
	--- source `IsOpen` reads from — the same contract `ContextMenu`'s
	--- `OnClose` already carries.
	OnClose: (() -> ())?,
	OnOpenChanged: ((open: boolean) -> ())?,

	--- The element that caused this dialog to open — regains real keyboard
	--- focus when it closes. Read once, at the moment `IsOpen` flips true.
	Trigger: (() -> any)?,

	CloseOnBackdropClick: boolean?,
	CloseOnEscape: boolean?,

	Router: coreDialog.Router?,
	Keys: coreDialog.Keys?,

	Title: string?,
	Size: UDim2?,
	Position: UDim2?,
	ZIndex: number?,

	--- The dialog's own real content. Handed the machine so a caller can
	--- `dialog.RegisterFocusable(key, element)` its own controls into the
	--- same tab order the close button already joins.
	Children: ((dialog: coreDialog.Dialog) -> any)?,

	--- Escapes with the real machine the instant it exists, for a caller
	--- that wants to drive it directly (register more focusables outside
	--- `Children`, read `CurrentFocusKey`, ...).
	OutDialog: ((dialog: coreDialog.Dialog) -> ())?,

	[any]: any,
}

local function Dialog(props: DialogProps): any
	local screenId = props.Id or generateScreenId()
	ScreenStack.Register(screenId, { Category = "Modal" })
	--- ONE PRESET FOR EVERY DIALOG, for now — the same "no per-consumer
	--- knob until a real one asks for it" restraint `createSlider`'s own
	--- clamp defaults hold to.
	TransitionOrchestrator.Bind(screenId, TransitionOrchestrator.Presets.FadeScale)

	local router = if props.Router ~= nil then props.Router else useRouter()
	local keys = if props.Keys ~= nil
		then props.Keys
		else KeysRouter.Keys({
			IsActive = function(): boolean
				return isTopmostModal(screenId)
			end,
		})

	local dialog = createDialog({
		Router = router,
		Keys = keys,
		Source = vide.source,
		Action = action,

		CloseOnBackdropClick = props.CloseOnBackdropClick,
		CloseOnEscape = props.CloseOnEscape,

		OnOpenChanged = onScreenOpenChanged(screenId, props.OnOpenChanged),
		OnClose = props.OnClose,

		--- THE ONE SEAM A REAL HOST CAPABILITY RE-ENTERS THROUGH, exactly
		--- as `createDialog.luau`'s own header states: this machine never
		--- reaches for `SelectionRouter`/`GuiService` itself. A direct
		--- reference, not a wrapping closure — `SelectionRouter.Select`'s
		--- own signature is already `(element: any) -> ()`.
		OnFocusChanged = SelectionRouter.Select,
	})

	if props.OutDialog then
		props.OutDialog(dialog)
	end

	--- PUSHES THE CALLER'S OWN STATE IN, never reads `createDialog`'s state
	--- back out to decide whether to push — see this file's own header for
	--- why: `dialog.Close()`'s focus-restore runs unconditionally, and
	--- calling it a second time after Escape/a backdrop click already ran
	--- it would clobber the restore that call just performed. `peek`
	--- because this is a GUARD read, not a value this effect should itself
	--- react to.
	vide.effect(function()
		local open = props.IsOpen()
		if peek(dialog.IsOpen) == open then
			return
		end
		if open then
			dialog.Open(if props.Trigger then props.Trigger() else nil)
		else
			dialog.Close()
		end
	end)

	cleanup(function()
		dialog.Destroy()
		TransitionOrchestrator.Unbind(screenId)
		if peek(ScreenStack.IsOpen(screenId)) then
			ScreenStack.Close(screenId)
		end
	end)

	--- SHOULD THIS STILL BE IN THE TREE — open, or still mid-exit-animation?
	--- `IsOpen` alone would unmount the instant `ScreenStack` says closed,
	--- snapping rather than animating out; this is the latch that survives
	--- the exit, the same pairing `TransitionOrchestrator`'s own header
	--- states every screen needs.
	local presence = Presence.new({
		Present = ScreenStack.IsOpen(screenId),
		StillAnimating = function(): boolean
			return not TransitionOrchestrator.IsSettled(screenId)
		end,
	})
	local transition = TransitionOrchestrator.UseTransition(screenId)

	return create("Frame")(dialog.GetRootProps({
		Name = props.Name or "Dialog",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		--- OVERRIDES `createDialog`'s OWN `Visible = isOpen` default — see
		--- above for why this needs to stay mounted through its own exit.
		Visible = presence.ShouldRender,
		ZIndex = props.ZIndex or 100,

		create("Frame")(dialog.GetBackdropProps({
			Name = "Backdrop",
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			--- DIMS WITH THE SAME PROGRESS THE SURFACE ANIMATES ON, rather
			--- than snapping to its final transparency the instant `IsOpen`
			--- flips — the one visible tell that this composes `Presence`'s
			--- transition rather than merely gating on it.
			BackgroundTransparency = function(): number
				return 1 - (0.55 * transition.Progress())
			end,
			BorderSizePixel = 0,
			ZIndex = 1,
		})),

		create("Frame")({
			Name = "Surface",
			Size = props.Size or UDim2.fromOffset(360, 220),
			Position = props.Position or UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(28, 32, 44),
			BorderSizePixel = 0,
			ZIndex = 2,

			create("UICorner")({ CornerRadius = UDim.new(0, 8) }),
			create("UIStroke")({ Color = Color3.fromRGB(60, 70, 95), Thickness = 1, Transparency = 0.3 }),

			if props.Title
				then create("TextLabel")({
					Name = "Title",
					Size = UDim2.new(1, -44, 0, 32),
					Position = UDim2.new(0, 16, 0, 8),
					BackgroundTransparency = 1,
					Text = props.Title,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = Color3.fromRGB(240, 240, 240),
					Font = Enum.Font.GothamBold,
					TextSize = 14,
				})
				else nil,

			Pressable({
				Router = router,
				Name = "CloseButton",
				Position = UDim2.new(1, -32, 0, 8),
				Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = Color3.fromRGB(50, 55, 70),
				--- DIRECT REFERENCE, not a wrapping `function() dialog.Close()
				--- end` — this button decides nothing about what a press
				--- means, it hands the activation straight to the machine's
				--- own close, the same "no interaction logic of its own"
				--- standard `tests/gates/verify_primitives_bind_machines.luau`
				--- holds every non-`PENDING` Primitive to.
				OnActivated = dialog.Close,

				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				create("TextLabel")({
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					Text = "x",
					TextColor3 = Color3.fromRGB(220, 220, 220),
					TextSize = 16,
					Font = Enum.Font.GothamBold,
				}),

				action(function(ref: any)
					if ref then
						dialog.RegisterFocusable("close", ref)
					end
				end),
			}),

			if props.Children then props.Children(dialog) else nil,
		}),
	}))
end

return Dialog
