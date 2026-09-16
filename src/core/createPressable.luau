--!strict
--[[
	Aether · core/createPressable -- is the pointer over it, is it held, and what
	does the thing being drawn look like while that is true?

	Layer 1. No reactive library, no engine types, no hit-testing of its own.

	WHAT A MACHINE HANDS BACK IS PROPS, NOT FLAGS. A component that asks
	`IsHovered()` and then assembles its own properties from the answer is a
	component with rules in it, and ten such components are ten different files
	that have to be reviewed separately. This returns the table the binding
	spreads, so the binding is the tree and nothing else, and so the same output
	spreads onto a frame on either host.

	    local machine = createPressable({ Router = ..., Source = ..., Action = ... })
	    return create("Frame")(machine.GetRootProps(props))

	EVERY PLATFORM THING IS A PORT.

	  Router   the thing that knows where the pointer is. HANDED OVER, never
	           reached for. A machine that resolves its own router cannot be
	           driven by a test that has none, and a require behind a `pcall`
	           hides the dependency from the boundary rather than removing it.
	  Source   a container that can be read and written. `vide.source` fits
	           exactly; so does the eight-line closure below, which is what runs
	           when nobody supplies one. State is a source rather than a getter
	           because a binding DERIVES from it -- a getter is something a
	           component has to remember to poll.
	  Action   how the host attaches a callback to the element it creates. vide
	           spells it `action`; a test spells it whatever it likes and reads
	           the callback back out.

	The router's own handle already exposes hover and press. They are mirrored
	into sources here anyway: the handle's are the router's private graph, and a
	machine that hands out its supplier's internals cannot later change what
	"pressed" means.
]]

--- Read with no arguments, write with one. `vide.source` is exactly this, which
--- is why the binding passes it straight in.
export type Source<T> = ((T) -> T) & (() -> T)

export type SourceFactory = <T>(initial: T) -> Source<T>

--- Wraps a callback so the host runs it against whatever it creates. The result
--- travels in the array part of the prop table.
export type ActionFactory = (callback: (element: any) -> ()) -> any

--- The part of a pointer router this machine uses, and all of it.
export type RouterHandle = {
	Bind: (element: any) -> (),
	Destroy: () -> (),
}

export type Router = {
	Pressable: (props: { [string]: any }) -> RouterHandle,
}

export type Options = {
	Router: Router,
	Source: SourceFactory?,
	Action: ActionFactory?,

	--- Handed to the router untouched: which scope arbitrates the hit, which
	--- layer supplies depth, which cursor to show, whether the element is inert.
	Scope: any?,
	Layer: string?,
	Cursor: (string | () -> string)?,
	Disabled: (boolean | () -> boolean)?,
	HitTestable: boolean?,
	FollowContentMovement: boolean?,
	Priority: number?,

	--- The caller's handlers. Called after this machine has updated its own
	--- state, so anything reading a source from inside one sees the new value.
	OnActivated: (() -> ())?,
	OnPressed: ((x: number, y: number) -> ())?,
	OnReleased: (() -> ())?,
	OnHoverChanged: ((hovered: boolean) -> ())?,
}

export type Pressable = {
	IsHovered: Source<boolean>,
	IsPressed: Source<boolean>,
	GetRootProps: (overrides: { [any]: any }?) -> { [any]: any },
	Destroy: () -> (),
}

--- Options that belong to this machine and must not reach the element.
---
--- A DENY LIST RATHER THAN AN ALLOW LIST. The binding used to enumerate the
--- properties it would pass through, which quietly dropped every property nobody
--- had thought of yet -- and the list of things a host can draw is longer than
--- the list of things this decides. What this owns is right here, in the same
--- file as the table, so the two cannot drift.
local MACHINE_OPTIONS: { [string]: true } = {
	Router = true,
	Source = true,
	Action = true,
	Scope = true,
	Layer = true,
	Cursor = true,
	Disabled = true,
	HitTestable = true,
	FollowContentMovement = true,
	Priority = true,
	OnActivated = true,
	OnPressed = true,
	OnReleased = true,
	OnHoverChanged = true,
}

--- What the element looks like before anyone styles it: invisible, borderless,
--- and named after what it is. A press is a behaviour and has no appearance of
--- its own, so every one of these is a value a caller overrides rather than a
--- decision this makes.
local function defaults(): { [any]: any }
	return {
		Name = "Pressable",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}
end

--- The fallback `Source`, for a caller with no reactive library -- a test, or a
--- host that has not got one yet. Reads and writes with the same shape vide
--- uses, and notifies nobody, which is all a machine needs to stay correct.
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

local function createPressable(options: Options): Pressable
	local router = options.Router
	if not router or not router.Pressable then
		error("createPressable needs a Router -- the binding has one, and hands it over", 2)
	end

	local newSource: SourceFactory = options.Source or plainSource
	local action: ActionFactory = options.Action or identityAction

	local isHovered = newSource(false)
	local isPressed = newSource(false)

	--- `Disabled` arrives as a value or as a getter and leaves as a getter,
	--- because the router reads it whenever it likes.
	local disabled: (() -> boolean)? = nil
	if type(options.Disabled) == "function" then
		disabled = options.Disabled :: () -> boolean
	elseif options.Disabled ~= nil then
		disabled = function(): boolean
			return options.Disabled :: boolean
		end
	end

	local handle = router.Pressable({
		Scope = options.Scope,
		Layer = options.Layer,
		Cursor = options.Cursor,
		Disabled = disabled,
		HitTestable = if options.HitTestable ~= nil then options.HitTestable else false,
		FollowContentMovement = options.FollowContentMovement,
		Priority = options.Priority,
		OnHoverChanged = function(hovered: boolean)
			isHovered(hovered)
			if options.OnHoverChanged then
				options.OnHoverChanged(hovered)
			end
		end,
		OnPressed = function(x: number, y: number)
			isPressed(true)
			if options.OnPressed then
				options.OnPressed(x, y)
			end
		end,
		OnReleased = function()
			isPressed(false)
			if options.OnReleased then
				options.OnReleased()
			end
		end,
		OnActivated = options.OnActivated,
	})

	local function getRootProps(overrides: { [any]: any }?): { [any]: any }
		local props = defaults()

		if overrides then
			for key, value in pairs(overrides) do
				--- Numbered entries are children and actions the caller wrote,
				--- and they keep their order by being appended rather than
				--- assigned.
				if type(key) == "number" then
					if value ~= nil then
						table.insert(props, value)
					end
				elseif MACHINE_OPTIONS[key :: any] or value == nil then
					continue
				elseif type(key) == "string" and string.match(key, "^On%u") then
					--- A HANDLER THIS MACHINE DOES NOT IMPLEMENT IS NOT A
					--- PROPERTY OF THE ELEMENT. `On` names a behaviour, and
					--- behaviour is this half; no host spells a drawable
					--- property that way. Handing such a key on would ask the
					--- host to set something it has never heard of, which fails
					--- at the furthest possible point from the caller who wrote
					--- the typo.
					continue
				else
					props[key] = value
				end
			end
		end

		table.insert(props, action(handle.Bind))
		return props
	end

	local destroyed = false
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		handle.Destroy()
		isHovered(false)
		isPressed(false)
	end

	return {
		IsHovered = isHovered,
		IsPressed = isPressed,
		GetRootProps = getRootProps,
		Destroy = destroy,
	}
end

return {
	createPressable = createPressable,
}
