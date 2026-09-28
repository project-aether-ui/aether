--!strict
--[=[
	A fake router, shared by every `core/` suite that needs one: NO VIDE, NO
	ROUTER, NO TREE, matching the shape `createPressable.test.luau` proved
	out first.

	TWO FAMILIES OF CONSUMER, ONE FIXTURE. `createPressable`/`createDialog`
	register a `Pressable`; `createDraggable`/`createSlider` register an
	`OnPointerMove`. Each pair had grown its own inline copy with its own
	small differences before this extraction (`createDialog`'s own reads
	only `activateBackdrop()`, never `hover`/`press`/`release`; `createSlider`'s
	own never asked whether it had been unsubscribed). Rather than choose one
	pair's shape and hope the other never notices what is missing, this
	fixture is the union of both: every method any of the four suites' own
	inline `router()` exposed, on one object. A suite that never calls
	`unsubscribed()` or `activateBackdrop()` simply never reads it -- an
	unused method on a fake is not a leak the way an unclaimed prop on a
	real element would be.
]=]

local function router()
	local registered: { [string]: any } = {}
	local pressableDestroyed = false
	local bound: any = nil

	local pointerMoveCallback: ((number, number) -> ())? = nil
	local pointerMoveUnsubscribed = false

	return {
		--- Registers exactly what a `Pressable` binding would: the machine's
		--- own prop table, and a `Bind`/`Destroy` pair. `createPressable.test
		--- .luau` and `createDialog.test.luau` both register through this.
		Pressable = function(props: { [string]: any })
			registered = props
			return {
				Bind = function(element: any)
					bound = element
				end,
				Destroy = function()
					pressableDestroyed = true
				end,
			}
		end,

		--- What the machine registered with the router, for asserting "the
		--- router was told" rather than inferring it from state that follows.
		props = function(): { [string]: any }
			return registered
		end,

		hover = function(hovered: boolean)
			registered.OnHoverChanged(hovered)
		end,
		press = function(x: number, y: number)
			registered.OnPressed(x, y)
		end,
		release = function()
			registered.OnReleased()
		end,

		--- `createDialog`'s own single registered `Pressable` is its backdrop;
		--- this fires it the way a real activation would.
		activateBackdrop = function()
			registered.OnActivated()
		end,

		destroyed = function(): boolean
			return pressableDestroyed
		end,
		bound = function(): any
			return bound
		end,

		--- Registers a pointer-move source the way `createDraggable`/
		--- `createSlider` expect: `move(x, y)` drives it, and the returned
		--- unsubscribe is tracked so `Destroy` can be asserted.
		OnPointerMove = function(fn: (number, number) -> ())
			pointerMoveCallback = fn
			return function()
				pointerMoveUnsubscribed = true
			end
		end,
		move = function(x: number, y: number)
			if pointerMoveCallback then
				pointerMoveCallback(x, y)
			end
		end,
		unsubscribed = function(): boolean
			return pointerMoveUnsubscribed
		end,
	}
end

return { router = router }
