--!strict
--[[
	Aether · core/createCheckbox -- checked/unchecked state, activated by a
	pointer click or a keyboard press while selected.

	Layer 1, same shape as createPressable: no reactive library, no engine
	types, nothing host-specific reached directly. Composes createPressable
	for the pointer half rather than re-deriving press semantics -- a click is
	still "a press that began and ended on this element", and that question
	is already answered correctly -- and takes a second port, Selection, for
	the keyboard half, exactly as createPressable takes Router for the
	pointer half.

	    local machine = createCheckbox({
	        Router = PointerRouter,
	        Selection = SelectionRouter,
	        Checked = false,
	    })
	    return create("Frame")(machine.GetRootProps(props))

	Selection MIRRORS Router'S OWN SHAPE ON PURPOSE: a port the binding hands
	over, never reached for, so a test can supply a fake with the same
	`Selectable(props) -> handle` shape a real one has and never touch a real
	host at all -- the same reason Router is a parameter instead of a require.
]]

local corePressable = require("./createPressable")
local coreSelection = require("./Selection")
local createPressable = corePressable.createPressable

export type Source<T> = corePressable.Source<T>
export type SourceFactory = corePressable.SourceFactory
export type ActionFactory = corePressable.ActionFactory
export type Router = corePressable.Router

--- Re-exported from `core/Selection`, which is where the port's own type
--- lives now -- `createRadioGroup` takes the identical shape, and duplicating
--- it here would be two definitions one edit could quietly let drift apart.
export type SelectionHandle = coreSelection.SelectionHandle
export type SelectableProps = coreSelection.SelectableProps
export type Selection = coreSelection.Selection

export type Options = {
	Router: Router,
	Selection: Selection,
	Source: SourceFactory?,
	Action: ActionFactory?,

	--- Handed to the router untouched, the same as createPressable's own.
	Scope: any?,
	Layer: string?,
	Cursor: (string | () -> string)?,
	Disabled: (boolean | () -> boolean)?,
	HitTestable: boolean?,
	FollowContentMovement: boolean?,
	Priority: number?,

	--- Initial state. Defaults to unchecked.
	Checked: boolean?,

	--- Called after this machine has updated its own state, the same
	--- ordering guarantee createPressable's own handlers make.
	OnCheckedChanged: ((checked: boolean) -> ())?,
}

export type Checkbox = {
	Checked: Source<boolean>,
	IsHovered: Source<boolean>,
	IsPressed: Source<boolean>,
	GetRootProps: (overrides: { [any]: any }?) -> { [any]: any },
	Destroy: () -> (),
}

--- Options that belong to this machine and must not reach the element. See
--- createPressable's own doc comment on the identical list there for why
--- this is a deny list rather than an allow list.
local MACHINE_OPTIONS: { [string]: true } = {
	Router = true,
	Selection = true,
	Source = true,
	Action = true,
	Scope = true,
	Layer = true,
	Cursor = true,
	Disabled = true,
	HitTestable = true,
	FollowContentMovement = true,
	Priority = true,
	Checked = true,
	OnCheckedChanged = true,
}

local function defaults(): { [any]: any }
	return {
		Name = "Checkbox",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		--- A checkbox is exactly the kind of control keyboard/gamepad
		--- selection exists for. Roblox's own `Selectable` defaults to true
		--- for most classes; stating it here is what makes that true for
		--- whatever this ends up drawn onto regardless of that default.
		Selectable = true,
	}
end

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

local function createCheckbox(options: Options): Checkbox
	if not options.Router then
		error("createCheckbox needs a Router -- the binding has one, and hands it over", 2)
	end
	if not options.Selection then
		error("createCheckbox needs a Selection -- the binding has one, and hands it over", 2)
	end

	local newSource: SourceFactory = options.Source or plainSource
	local action: ActionFactory = options.Action or identityAction

	local checked = newSource(options.Checked == true)

	local disabled: (() -> boolean)? = nil
	if type(options.Disabled) == "function" then
		disabled = options.Disabled :: () -> boolean
	elseif options.Disabled ~= nil then
		disabled = function(): boolean
			return options.Disabled :: boolean
		end
	end

	--- ONE TOGGLE, REACHED BY EITHER INPUT FAMILY. A click and a Space press
	--- are two ways of asking the same question, and answering it in one
	--- place is what keeps them from drifting -- a disabled checkbox that
	--- only guarded the pointer path would still toggle from the keyboard.
	local function toggle()
		if disabled and disabled() then
			return
		end
		local resolved = not checked()
		checked(resolved)
		if options.OnCheckedChanged then
			options.OnCheckedChanged(resolved)
		end
	end

	local pressable = createPressable({
		Router = options.Router,
		Source = options.Source,
		Action = options.Action,
		Scope = options.Scope,
		Layer = options.Layer,
		Cursor = options.Cursor,
		Disabled = options.Disabled,
		HitTestable = options.HitTestable,
		FollowContentMovement = options.FollowContentMovement,
		Priority = options.Priority,
		OnActivated = toggle,
	})

	local selectionHandle = options.Selection.Selectable({
		OnKeyActivate = toggle,
	})

	local function getRootProps(overrides: { [any]: any }?): { [any]: any }
		local props = defaults()

		if overrides then
			for key, value in pairs(overrides) do
				--- Numbered entries are children and actions the caller
				--- wrote, kept in order by being appended rather than
				--- assigned -- see createPressable's own comment on the
				--- identical branch below.
				if type(key) == "number" then
					if value ~= nil then
						table.insert(props, value)
					end
				elseif MACHINE_OPTIONS[key :: any] or value == nil then
					continue
				elseif type(key) == "string" and string.match(key, "^On%u") then
					continue
				else
					props[key] = value
				end
			end
		end

		--- ONLY THE ARRAY PART, deliberately: `pressable`'s own defaults
		--- (`Name = "Pressable"`, its own `BackgroundTransparency`) are not
		--- wanted here, this machine has already set its own. `ipairs` never
		--- sees the string-keyed half of that table, so only the bound
		--- action it appended comes across.
		local pressableProps = pressable.GetRootProps()
		for _, entry in ipairs(pressableProps) do
			table.insert(props, entry)
		end

		table.insert(props, action(selectionHandle.Bind))
		return props
	end

	local destroyed = false
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		pressable.Destroy()
		selectionHandle.Destroy()
	end

	return {
		Checked = checked,
		IsHovered = pressable.IsHovered,
		IsPressed = pressable.IsPressed,
		GetRootProps = getRootProps,
		Destroy = destroy,
	}
end

return {
	createCheckbox = createCheckbox,
}
