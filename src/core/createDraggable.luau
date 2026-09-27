--!strict
--[[
	Aether · core/createDraggable -- given a press that already happened
	somewhere else, how far has the pointer moved along one axis since, and
	what should whoever asked about it do with that.

	Layer 1. No reactive library, no engine types, no hit-testing, no
	element of its own to bind to.

	EXTRACTED FROM `Scrollbar.luau` (milestone 58 sprint 1), not designed
	ahead of a need: the thumb drag there already computed exactly this --
	`isDragging`/`dragStartPos`/`dragStartOffset` as plain locals, a
	`PointerRouter.OnPointerMove` subscription reading
	`delta = currentPos - dragStartPos`, called into
	`props.OnThumbDrag(delta, dragStartOffset)`. This machine is that logic,
	generalised only as far as `Scrollbar`'s own real call site needed.

	    local drag = createDraggable({ Router = PointerRouter, Source = ...,
	        Axis = "Vertical", OnDrag = function(delta, startValue) ... end })
	    -- from whatever OnPressed(x, y) already fires on the caller's own
	    -- press handle:
	    drag.Start(currentOffset, x, y)
	    -- from OnReleased:
	    drag.Stop()

	DOES NOT CREATE A PRESS. `Scrollbar.luau` already gets `OnPressed`/
	`OnReleased` two different ways depending on whether the thumb is the
	default one (through the `Pressable` primitive) or a caller-supplied one
	(through a raw `PointerRouter.Pressable` handle bound by hand) -- and
	both already carry the `(x, y)` this machine needs. A machine that made
	its own `Pressable` registration would have to pick one of those two
	paths, or reimplement both; a machine that is TOLD when a drag starts
	and stops fits either one without knowing they are different.

	NO `GetRootProps`, deliberately, unlike `createPressable`. That exists
	because `createPressable` binds an element itself; this machine binds
	nothing -- it rides on whatever press already bound one.

	CLAMPING IS NOT THIS MACHINE'S JOB (the milestone's own open question,
	resolved here): `Scrollbar.luau`'s own clamp
	(`ScrollController.computeScrollFromThumb`, called from inside
	`OnThumbDrag`) already lives outside the drag-tracking logic today, the
	same way `createPressable` does not decide a control's color. `OnDrag`
	hands back a raw delta and the value dragging started from; what a
	caller does with either is domain knowledge this machine must not have.
]]

--- Read with no arguments, write with one. `vide.source` is exactly this.
export type Source<T> = ((T) -> T) & (() -> T)

export type SourceFactory = <T>(initial: T) -> Source<T>

--- The part of a pointer router this machine uses, and all of it: a way to
--- hear about movement, the same free function `Scrollbar.luau` already
--- calls directly (`PointerRouter.OnPointerMove`).
export type PointerMoveSource = {
	OnPointerMove: (callback: (x: number, y: number) -> ()) -> () -> (),
}

export type Options = {
	Router: PointerMoveSource,
	Source: SourceFactory?,

	--- Which coordinate a delta is measured along. Fixed per machine,
	--- matching `Scrollbar.luau`'s own `isVertical`, which never changes
	--- for a given scrollbar instance.
	Axis: "Vertical" | "Horizontal",

	OnDragStart: (() -> ())?,
	OnDragEnd: (() -> ())?,
	--- Fired on every pointer move while dragging. `startValue` is
	--- whatever was passed to `Start` -- this machine never interprets it,
	--- only hands it back beside the delta, the same pairing
	--- `Scrollbar.luau`'s own `OnThumbDrag(delta, dragStartOffset)` already
	--- relies on.
	OnDrag: ((delta: number, startValue: number) -> ())?,
}

export type Draggable = {
	IsDragging: Source<boolean>,
	--- Call from the caller's own press handler. `x`/`y` are exactly what
	--- `PointerRouter.Pressable`'s own `OnPressed(x, y)` already supplies
	--- at all three of its call sites -- no `InputScope.GetPointerPosition`
	--- re-query needed, unlike `Scrollbar.luau`'s own pre-extraction
	--- version.
	Start: (startValue: number, x: number, y: number) -> (),
	--- Call from the caller's own release handler.
	Stop: () -> (),
	Destroy: () -> (),
}

--- The fallback `Source`, for a caller with no reactive library -- a test,
--- or a host that has not got one yet. Reads and writes with the same shape
--- vide uses, and notifies nobody, which is all a machine needs to stay
--- correct.
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

local function createDraggable(options: Options): Draggable
	local router = options.Router
	if not router or not router.OnPointerMove then
		error("createDraggable needs a Router with OnPointerMove -- the binding has one, and hands it over", 2)
	end

	local newSource: SourceFactory = options.Source or plainSource
	local isVertical = options.Axis == "Vertical"

	local isDragging = newSource(false)
	local dragStartPos = 0
	local dragStartValue = 0

	local unsubscribeMove = router.OnPointerMove(function(x: number, y: number)
		if not isDragging() then return end
		local currentPos = if isVertical then y else x
		local delta = currentPos - dragStartPos
		if options.OnDrag then
			options.OnDrag(delta, dragStartValue)
		end
	end)

	local function start(startValue: number, x: number, y: number)
		isDragging(true)
		dragStartPos = if isVertical then y else x
		dragStartValue = startValue
		if options.OnDragStart then
			options.OnDragStart()
		end
	end

	local function stop()
		if not isDragging() then return end
		isDragging(false)
		if options.OnDragEnd then
			options.OnDragEnd()
		end
	end

	local destroyed = false
	local function destroy()
		if destroyed then return end
		destroyed = true
		unsubscribeMove()
		isDragging(false)
	end

	return {
		IsDragging = isDragging,
		Start = start,
		Stop = stop,
		Destroy = destroy,
	}
end

return {
	createDraggable = createDraggable,
}
