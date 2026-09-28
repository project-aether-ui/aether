--!strict
--[[
	Aether · core/createSlider -- a number, held between a `Min` and a `Max`,
	moved by a drag along one axis and optionally snapped to a `Step`.

	Layer 1, same discipline as createPressable/createCheckbox: no reactive
	library, no engine types, nothing host-specific reached directly. Composes
	`createDraggable` (milestone 58) DIRECTLY for the pointer-tracking half --
	`Start(startValue, x, y)`/`Stop()`, fed by whatever press mechanism the
	caller already has (a `createPressable`, a raw `PointerRouter.Pressable`,
	`Scrollbar.luau`'s own default-thumb-vs-slot-thumb split, or a test) --
	rather than reimplementing press/move plumbing `createDraggable` already
	owns.

	    local slider = createSlider({
	        Router = PointerRouter, -- needs OnPointerMove; a Pressable factory
	                                -- is only required if a caller wires the
	                                -- thumb's own press through this machine
	        Min = 0,
	        Max = 100,
	        Step = 5,
	        TrackLength = 200,
	        OnChange = function(value) ... end,
	    })
	    local thumb = slider.GetThumbProps()
	    -- from whatever OnPressed(x, y) the thumb's own press handle fires:
	    thumb.OnPressed(x, y)
	    -- from OnReleased:
	    thumb.OnPressed and thumb.OnReleased()

	UNLIKE `createDraggable`'s OWN "clamping is the caller's job" precedent,
	THIS MACHINE OWNS THE CLAMP. That precedent was never "no machine ever
	clamps" -- `createDraggable`'s own design note named exactly this shape: a
	range-owning primitive should hold its own clamp, and `Slider` is that
	primitive. `createDraggable` stays range-agnostic; pushing `Min`/`Max`/
	`Step` down into it "for consistency" would be re-deciding something the
	milestone plan already settled, elsewhere, on purpose.

	CLAMP, THEN STEP, THEN CLAMP AGAIN. A raw drag position can land outside
	`[Min, Max]` (a drag continues past either end of the track), so it is
	clamped BEFORE stepping. Snapping to the nearest multiple of `Step` from
	`Min` can itself land just outside `[Min, Max]` again -- `Min = 0, Max = 9,
	Step = 5` dragged to the clamped edge `9` snaps to `10` (`round(9/5) = 2`,
	`0 + 2*5 = 10`), one whole step past `Max` -- so the result is clamped a
	second time after stepping. Skipping either pass is the bug this file's
	own test suite exists to catch.

	`OnChange` NEVER SEES A RAW DELTA, OR AN INTERMEDIATE UNCLAMPED VALUE --
	only the same fully clamped-and-stepped number `Value()` would report
	right after. A caller reading `OnChange` mid-drag must never see anything
	outside `[Min, Max]`, even transiently.

	CONTROLLED WHEN `Value` IS A GETTER, the same test `createCheckbox`'s own
	`Checked` and `createRadioGroup`/`createTabs`'s own `Value`/`Active`
	already use: hand over a getter and this machine reads it and never
	writes it, calling `OnChange` with what it WOULD move to next; hand over
	nothing (or `InitialValue`) and this machine owns the value itself.

	NO `GetRootProps`/`GetThumbProps` SHAPED LIKE `createPressable`'s OWN,
	DELIBERATELY. `createPressable`'s `GetRootProps` spreads onto an element
	because that machine binds one (`action(handle.Bind)`). This machine, like
	`createDraggable`, binds nothing -- the track and the thumb are real
	instances only `Slider.luau` (a later, separate sprint) creates. What a
	Layer 1 range machine can honestly hand back before that exists is DATA
	(the current value, so a track can report it) and BEHAVIOUR HOOKS (the
	thumb's own press-driven `Start`/`Stop`, pre-wired to this machine's own
	clamp/step pipeline) -- so `GetRootProps`/`GetThumbProps` return plain
	records of exactly those, not spreadable prop arrays with nothing of this
	machine's own to bind.
]]

local coreDraggable = require("./createDraggable")
local createDraggable = coreDraggable.createDraggable
local safeWarn = require("./Warn")

export type Source<T> = coreDraggable.Source<T>
export type SourceFactory = coreDraggable.SourceFactory

--- The union of what this machine's two composed halves need: `createDraggable`'s
--- own `OnPointerMove`, and (only if a caller wants the thumb's press wired
--- through this machine's own `Router.Pressable` rather than supplied by
--- hand) a `Pressable` factory matching `createPressable`'s own `Router`.
--- `PointerRouter` itself already satisfies both, the same object
--- `Scrollbar.luau` hands to both `createDraggable` and its own thumb press.
export type Router = coreDraggable.PointerMoveSource & {
	Pressable: ((props: { [string]: any }) -> { Bind: (element: any) -> (), Destroy: () -> () })?,
}

export type Options = {
	Router: coreDraggable.PointerMoveSource,
	Source: SourceFactory?,

	--- Which coordinate a drag is measured along, handed straight to
	--- `createDraggable`. Fixed per machine, the same as `createDraggable`'s
	--- own `Axis`.
	Axis: ("Vertical" | "Horizontal")?,

	--- The range this slider owns. `Min` must not exceed `Max` -- a machine
	--- with an inverted range has no value it could ever report honestly.
	Min: number,
	Max: number,
	--- The smallest movement a value is allowed to take, snapped to the
	--- nearest multiple of `Step` counted from `Min`. `nil` or `<= 0` means
	--- continuous -- clamped, never snapped.
	Step: number?,

	--- How many pixels the full `[Min, Max]` span covers, the same number
	--- `Scrollbar.luau`'s own `TrackLength` measures from a real instance. A
	--- plain number for a fixed track, a getter for one that can resize.
	--- Layer 1 knows nothing about instances, so this is handed over rather
	--- than measured.
	TrackLength: (number | (() -> number))?,

	--- CONTROLLED, the same shape `createCheckbox`'s own `Checked` and
	--- `createRadioGroup`/`createTabs`'s own `Value`/`Active` already are: a
	--- getter, read through rather than copied. When given, a drag calls
	--- `OnChange` with the value it would have moved to WITHOUT changing what
	--- `Value()` reports -- the caller's own state is what actually has to
	--- move for that to change.
	Value: (() -> number)?,
	--- Where an UNCONTROLLED slider starts. Ignored when `Value` is given.
	--- Clamped and stepped the same as any other value this machine ever
	--- reports, so a caller cannot start it somewhere it could never drag to.
	InitialValue: number?,

	OnDragStart: (() -> ())?,
	OnDragEnd: (() -> ())?,
	--- Fired with the fully clamped-and-stepped value on every pointer move
	--- while dragging -- never the raw delta, never an intermediate
	--- unclamped or unstepped number.
	OnChange: ((value: number) -> ())?,
}

export type Slider = {
	Value: () -> number,
	IsDragging: Source<boolean>,
	GetRootProps: () -> { Min: number, Max: number, Step: number?, Value: () -> number },
	GetThumbProps: () -> {
		IsDragging: Source<boolean>,
		OnPressed: (x: number, y: number) -> (),
		OnReleased: () -> (),
	},
	Destroy: () -> (),
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

local function createSlider(options: Options): Slider
	if not options.Router or not options.Router.OnPointerMove then
		error("createSlider needs a Router with OnPointerMove -- the binding has one, and hands it over", 2)
	end
	if type(options.Min) ~= "number" or type(options.Max) ~= "number" then
		error("createSlider needs Min and Max, both numbers", 2)
	end
	if options.Min > options.Max then
		error(`createSlider needs Min ({options.Min}) <= Max ({options.Max})`, 2)
	end
	if options.Step ~= nil and options.Step < 0 then
		safeWarn(`createSlider: Step ({options.Step}) is negative and will be treated as continuous (no snapping)`)
	end

	local Min = options.Min
	local Max = options.Max
	local Step = options.Step

	local newSource: SourceFactory = options.Source or plainSource

	--- CONTROLLED WHEN `Value` IS A FUNCTION -- see this module's own doc
	--- comment, and `createCheckbox`'s own `Checked`/`controlled` for the
	--- identical test.
	local controlled: (() -> number)? = options.Value

	--- Clamps to `[Min, Max]`, THEN snaps to the nearest multiple of `Step`
	--- counted from `Min`, THEN re-clamps -- see this module's own doc
	--- comment for why the second clamp is not optional.
	local function resolveValue(raw: number): number
		local clampedRaw = math.clamp(raw, Min, Max)
		if not Step or Step <= 0 then
			return clampedRaw
		end
		local steps = math.floor((clampedRaw - Min) / Step + 0.5)
		local stepped = Min + steps * Step
		return math.clamp(stepped, Min, Max)
	end

	local initialValue = resolveValue(if controlled then controlled() else (options.InitialValue or Min))
	local value = newSource(initialValue)

	--- READ THROUGH, NOT COPIED, when controlled -- see `createCheckbox`'s
	--- own `isChecked`'s identical comment: a controlled caller's own state
	--- can change without anything here being told, and a mirrored copy
	--- would be one render behind on every read.
	local function currentValue(): number
		if controlled then
			return resolveValue(controlled())
		end
		return value()
	end

	--- CONTROLLED: `value` NEVER WRITES. `OnChange` still fires with the
	--- fully resolved value this slider believes should be next -- the
	--- caller's own state is what actually has to move for `Value()` to
	--- agree, the same way `createCheckbox`'s own controlled `toggle` never
	--- writes either.
	local function setValue(resolved: number)
		if not controlled then
			value(resolved)
		end
		if options.OnChange then
			options.OnChange(resolved)
		end
	end

	local function resolveTrackLength(): number
		local tl = options.TrackLength
		if type(tl) == "function" then
			return (tl :: () -> number)()
		end
		return (tl :: number?) or 100
	end

	local drag = createDraggable({
		Router = options.Router,
		Source = options.Source,
		Axis = options.Axis or "Horizontal",
		OnDragStart = options.OnDragStart,
		OnDragEnd = options.OnDragEnd,
		OnDrag = function(delta: number, startValue: number)
			local trackLength = resolveTrackLength()
			local range = Max - Min
			local raw = if trackLength > 0 then startValue + (delta / trackLength) * range else startValue
			setValue(resolveValue(raw))
		end,
	})

	local function onThumbPressed(x: number, y: number)
		drag.Start(currentValue(), x, y)
	end

	local function getRootProps(): { Min: number, Max: number, Step: number?, Value: () -> number }
		return {
			Min = Min,
			Max = Max,
			Step = Step,
			Value = currentValue,
		}
	end

	local function getThumbProps(): {
		IsDragging: Source<boolean>,
		OnPressed: (x: number, y: number) -> (),
		OnReleased: () -> (),
	}
		return {
			IsDragging = drag.IsDragging,
			OnPressed = onThumbPressed,
			OnReleased = drag.Stop,
		}
	end

	local destroyed = false
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		drag.Destroy()
	end

	return {
		Value = currentValue,
		IsDragging = drag.IsDragging,
		GetRootProps = getRootProps,
		GetThumbProps = getThumbProps,
		Destroy = destroy,
	}
end

return {
	createSlider = createSlider,
}
