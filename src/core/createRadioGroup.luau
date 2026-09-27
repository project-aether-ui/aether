--!strict
--[[
	Aether · core/createRadioGroup -- exactly one of N options selected,
	arrow-key roving focus between them, a click or an activation key
	confirming whichever one currently holds focus.

	Layer 1, same discipline as createCheckbox: no reactive library, no
	engine types, nothing host-specific reached directly. Reuses
	`controllers/SelectionModel` in its "single" mode for the one-of-N
	invariant rather than re-deriving it -- that mode already clears every
	other key the instant one is selected, which is the entire rule a radio
	group enforces. Reuses `createPressable` per option for the pointer half,
	exactly as `createCheckbox` does.

	    local group = createRadioGroup({
	        Router = PointerRouter,
	        Selection = SelectionRouter,
	        Options = { "small", "medium", "large" },
	        InitialValue = "medium",
	    })
	    local option = group.GetOption("large")
	    return create("Frame")(option.GetRootProps(props))

	ARROWS MOVE FOCUS; THEY DO NOT SELECT. Right/Down and Left/Up rove
	`Selection.Select` onto the next or previous option's own bound element
	WITHOUT touching `SelectionModel` at all -- moving focus across three
	options with the arrow keys and never pressing Space leaves the original
	one still checked. Only `OnKeyActivate` (Space or Return, both, since a
	radio group answers to either on the real engine) calls `SelectionModel
	.Select` and changes what is actually checked. This is a real decision,
	not an oversight: it is the shape a roving-tabindex listbox has, and it
	is not the shape the real engine's native `<input type=radio>` has, where
	an arrow key selects immediately. Widening or narrowing that gap is a
	later call for whoever composes this into a component; this file states
	which one it made rather than leaving it to be discovered by testing.

	WRAPPING, ON PURPOSE. Arrow-key navigation from the last option moves to
	the first, and from the first moves to the last -- the standard a native
	radio group and most listbox implementations already hold themselves to,
	named here so it reads as a decision rather than a modulo left
	unexplained.
]]

local corePressable = require("./createPressable")
local coreSelection = require("./Selection")
local SelectionModel = require("../controllers/SelectionModel")
local createPressable = corePressable.createPressable

export type Source<T> = corePressable.Source<T>
export type SourceFactory = corePressable.SourceFactory
export type ActionFactory = corePressable.ActionFactory
export type Router = corePressable.Router
export type SelectionHandle = coreSelection.SelectionHandle
export type SelectableProps = coreSelection.SelectableProps
export type Selection = coreSelection.Selection

export type Options = {
	Router: Router,
	Selection: Selection,
	Source: SourceFactory?,
	Action: ActionFactory?,

	--- Every option key, in navigation order. Required and non-empty: a
	--- radio group with nothing to choose between is a caller's mistake, not
	--- a machine this file can make sense of.
	Options: { any },
	--- Which key starts selected. Omit for none selected at all -- a valid
	--- starting state the real engine itself allows.
	InitialValue: any?,

	--- Handed to each option's own `createPressable`, the same as
	--- createCheckbox's own pass-through.
	Disabled: (boolean | () -> boolean)?,
	Cursor: (string | () -> string)?,

	--- Called after `SelectionModel` has updated, with the newly selected
	--- key (or nil if the selection was cleared).
	OnValueChanged: ((value: any?) -> ())?,
}

export type RadioOption = {
	IsSelected: Source<boolean>,
	IsHovered: Source<boolean>,
	IsPressed: Source<boolean>,
	GetRootProps: (overrides: { [any]: any }?) -> { [any]: any },
	--- The bound actions and nothing else -- see `createPressable`'s own
	--- identical field. Milestone 54 sprint 3.
	GetActionProps: () -> { [any]: any },
	Destroy: () -> (),
}

export type RadioGroup = {
	Value: Source<any?>,
	GetOption: (key: any) -> RadioOption,
	Destroy: () -> (),
}

--- Options that belong to an OPTION's own root props and must not reach the
--- element -- the same deny-list shape createPressable and createCheckbox
--- both already use.
local OPTION_MACHINE_OPTIONS: { [string]: true } = {
	Disabled = true,
	Cursor = true,
}

local function defaults(): { [any]: any }
	return {
		Name = "RadioOption",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
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

local function createRadioGroup(options: Options): RadioGroup
	if not options.Router then
		error("createRadioGroup needs a Router -- the binding has one, and hands it over", 2)
	end
	if not options.Selection then
		error("createRadioGroup needs a Selection -- the binding has one, and hands it over", 2)
	end
	if not options.Options or #options.Options == 0 then
		error("createRadioGroup needs at least one option key in Options", 2)
	end

	local newSource: SourceFactory = options.Source or plainSource
	local action: ActionFactory = options.Action or identityAction

	local orderedKeys = options.Options
	local value = newSource(options.InitialValue)

	--- Resolved once, the same as createCheckbox's own identical block: a
	--- value or a getter arrives, a getter always leaves, because
	--- `selectKey` reads it on every call rather than once at construction.
	local disabled: (() -> boolean)? = nil
	if type(options.Disabled) == "function" then
		disabled = options.Disabled :: () -> boolean
	elseif options.Disabled ~= nil then
		disabled = function(): boolean
			return options.Disabled :: boolean
		end
	end

	local model = SelectionModel.new({
		Mode = "single",
		InitialSelection = if options.InitialValue ~= nil then { options.InitialValue } else nil,
	})

	--- Every option's own bound element and per-option `IsSelected` source,
	--- built lazily -- a radio group is asked for its options one at a time
	--- by whatever is creating the elements, not handed a fixed list of
	--- machines up front.
	local optionState: {
		[any]: {
			boundElement: any,
			isSelected: Source<boolean>,
		},
	} = {}
	--- The finished machine per key, so a second `GetOption(key)` answers the
	--- same one -- see `getOption`'s own comment on why rebuilding would be
	--- wrong rather than merely wasteful.
	local optionMachines: { [any]: RadioOption } = {}

	local function keyIndex(key: any): number?
		for i, k in ipairs(orderedKeys) do
			if k == key then
				return i
			end
		end
		return nil
	end

	--- Every subscribed `IsSelected` source follows the model directly,
	--- rather than each option polling it -- the same reason
	--- `SelectionModel.Subscribe` exists at all.
	model.Subscribe(function()
		for key, state in pairs(optionState) do
			state.isSelected(model.IsSelected(key))
		end
		value(model.GetSelectedKeys()[1])
		if options.OnValueChanged then
			options.OnValueChanged(model.GetSelectedKeys()[1])
		end
	end)

	--- GATED HERE, NOT LEFT TO THE ROUTER, the same reason createCheckbox's
	--- own `toggle` checks `disabled()` itself: a click and a key activation
	--- are two different callers of this one function, and checking in both
	--- places is how the two could disagree about it later.
	local function selectKey(key: any)
		if disabled and disabled() then
			return
		end
		model.Select(key)
	end

	--- Roves `Selection.Select` onto the option `delta` steps from `fromKey`,
	--- WRAPPING at either end. Does not touch `model` -- see this file's own
	--- module comment on why moving focus and changing the checked option
	--- are two different acts here.
	local function moveFocus(fromKey: any, delta: number)
		local idx = keyIndex(fromKey)
		if not idx then
			return
		end
		local n = #orderedKeys
		local nextIdx = ((idx - 1 + delta) % n) + 1
		local nextKey = orderedKeys[nextIdx]
		local nextState = optionState[nextKey]
		if nextState and nextState.boundElement then
			options.Selection.Select(nextState.boundElement)
		end
	end

	local function getOption(key: any): RadioOption
		--- MEMOISED, NOT REBUILT. A second call for a key already asked
		--- about must answer the SAME machine -- a fresh one would connect a
		--- second `Selectable` and a second `Pressable` for one element,
		--- doubling every future press and leaking the first pair's
		--- connections forever, since nothing would ever call their
		--- `Destroy`.
		if optionMachines[key] then
			return optionMachines[key]
		end

		optionState[key] = {
			boundElement = nil,
			isSelected = newSource(model.IsSelected(key)),
		}
		local state = optionState[key]

		local pressable = createPressable({
			Router = options.Router,
			Source = options.Source,
			Action = options.Action,
			Disabled = options.Disabled,
			Cursor = options.Cursor,
			OnActivated = function()
				selectKey(key)
			end,
		})

		local selectionHandle = options.Selection.Selectable({
			--- BOTH KEYS, BY NAME, unlike createCheckbox's Space-only
			--- default -- the real engine answers a radio group's own
			--- confirmation to either, and `ActivationKeys` exists on the
			--- port precisely so this file can ask for that without
			--- widening every OTHER consumer of `Selectable` to match. Named
			--- rather than a real `Enum.KeyCode`, the same reason every
			--- other type in this file is engine-free: turning a name into
			--- whatever the host reports is the real Selection
			--- implementation's job, not this one's.
			ActivationKeys = { Space = true, Return = true },
			OnKeyActivate = function()
				selectKey(key)
			end,
			OnArrowNext = function()
				moveFocus(key, 1)
			end,
			OnArrowPrevious = function()
				moveFocus(key, -1)
			end,
		})

		local function getRootProps(overrides: { [any]: any }?): { [any]: any }
			local props = defaults()

			if overrides then
				for k, v in pairs(overrides) do
					if type(k) == "number" then
						if v ~= nil then
							table.insert(props, v)
						end
					elseif OPTION_MACHINE_OPTIONS[k :: any] or v == nil then
						continue
					elseif type(k) == "string" and string.match(k, "^On%u") then
						--- LOUD NOW, NOT SILENT (milestone 54 sprint 5) --
						--- see createPressable's own identical comment.
						warn(`createRadioGroup: "{k}" is not a handler this machine recognises and was dropped`)
						continue
					else
						props[k] = v
					end
				end
			end

			local pressableProps = pressable.GetRootProps()
			for _, entry in ipairs(pressableProps) do
				table.insert(props, entry)
			end

			table.insert(
				props,
				action(function(element: any)
					state.boundElement = element
					selectionHandle.Bind(element)
				end)
			)
			return props
		end

		--- THE ARRAY PART, BUILT DIRECTLY -- see `createCheckbox`'s own
		--- identical getter.
		local function getActionProps(): { [any]: any }
			local props = {}
			for _, entry in ipairs(pressable.GetActionProps()) do
				table.insert(props, entry)
			end
			table.insert(
				props,
				action(function(element: any)
					state.boundElement = element
					selectionHandle.Bind(element)
				end)
			)
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

		local radioOption: RadioOption = {
			IsSelected = state.isSelected,
			IsHovered = pressable.IsHovered,
			IsPressed = pressable.IsPressed,
			GetRootProps = getRootProps,
			GetActionProps = getActionProps,
			Destroy = destroy,
		}
		optionMachines[key] = radioOption
		return radioOption
	end

	return {
		Value = value,
		GetOption = getOption,
		Destroy = function()
			for _, radioOption in pairs(optionMachines) do
				radioOption.Destroy()
			end
			model.Clear()
		end,
	}
end

return {
	createRadioGroup = createRadioGroup,
}
