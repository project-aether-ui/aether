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

	    local dialog: coreDialog.Dialog
	    Dialog({
	        OutDialog = function(d) dialog = d end,
	        Title = "Delete this?",
	        Children = function(d)
	            return Pressable({ OnActivated = function() ... end, ... })
	        end,
	    })
	    ...
	    button's OnActivated = function() dialog.Open(triggerElement) end

	UNCONTROLLED, THE SAME SHAPE `createDialog.luau`'s OWN TEST SUITE ALREADY
	USES throughout (`tests/core/createDialog.test.luau` never passes
	`Options.IsOpen` once) — `Open()`/`Close()`/`Toggle()` are the real API,
	not a boolean prop pushed in from outside, and `OutDialog` is how a
	caller reaches them (the button that OPENS a dialog necessarily lives
	OUTSIDE it, so it needs a handle). A CONTROLLED shape was tried first, a
	`vide.effect` watching a caller's own `IsOpen` source and pushing it
	into `dialog.Open()`/`dialog.Close()` — and it produced a real,
	reproducible fault: `dialog.Open()`'s own `OnOpenChanged` calls
	`ScreenStack.Open`, whose `bump()` writes a vide source that a
	`Visible`/`Presence` binding elsewhere in the same tree reads, and doing
	that FROM INSIDE an effect that is itself mid-run because ITS OWN source
	just changed is exactly the reentrancy `Deps.luau`'s own `peek` doc
	comment warns about ("a scope, that should rerun due to the update of a
	source, is already active") — confirmed live, not assumed, the first
	time `examples/aether/dialog-demo` clicked its own open button under
	`dew test`. Every mutation below now happens only from a REAL event
	handler (a press, a keystroke) exactly the way `createPressable`/
	`createRadioGroup` already do it, never from a reactive scope watching a
	prop.

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
	the real `KeysRouter` handler drops the keystroke on the floor for
	every dialog that answers no. The older dialog's trap goes quiet the
	moment a newer one opens, and answers again the instant the newer one
	closes, with no explicit hand-off between the two. Verified live under
	`dew test`, driving a real click through the real host, in
	`examples/aether/dialog-demo/dialog-demo.test.luau`: opening a second
	dialog over the first leaves the first still `Visible`, and closing the
	second's own close button leaves the first untouched.

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

--- THE ONE PLACE `ScreenStack` LEARNS THIS DIALOG MOVED — `createDialog`'s
--- own `setOpen` calls `Options.OnOpenChanged` exactly once per real
--- open→closed or closed→open edge, whether that edge came from `Open()`/
--- `Close()` called directly (this file's own close button) or from
--- Escape/a backdrop click (`createDialog`'s own internal `close()`).
--- Named and hoisted, rather than written inline in the `createDialog`
--- options table below, so that table stays a plain reference
--- (`OnOpenChanged = onScreenOpenChanged(...)`) rather than a
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

	--- Opened the moment this Primitive first draws, rather than needing an
	--- explicit `dialog.Open()` call for the ordinary "starts open" case.
	InitiallyOpen: boolean?,

	--- Fires whenever this machine (Escape, a backdrop click, the close
	--- button, or a caller's own `dialog.Close()`) decides the dialog
	--- should close.
	OnClose: (() -> ())?,
	OnOpenChanged: ((open: boolean) -> ())?,

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
	--- same tab order the close button already joins, and call
	--- `dialog.Open()`/`Close()` on itself (an "open nested dialog" button
	--- living INSIDE this dialog's own content, for instance).
	Children: ((dialog: coreDialog.Dialog) -> any)?,

	--- Escapes with the real machine the instant it exists — the one way a
	--- caller reaches `dialog.Open(trigger)` from OUTSIDE this component
	--- (the button that opens a dialog necessarily lives outside it).
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

	if props.InitiallyOpen then
		dialog.Open()
	end

	if props.OutDialog then
		props.OutDialog(dialog)
	end

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
