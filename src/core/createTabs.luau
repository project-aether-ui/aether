--!strict
--[[
	Aether · core/createTabs -- a tab list and its panels, exactly one active
	at a time, arrow-key roving focus that switches the active tab as it
	moves.

	Layer 1, same discipline as createCheckbox and createRadioGroup: no
	reactive library, no engine types, nothing host-specific reached
	directly. Reuses `controllers/SelectionModel` in its "single" mode for
	the one-of-N invariant, the same as createRadioGroup, and the same two
	ports, Router and Selection, for the pointer and keyboard halves.

	    local tabs = createTabs({
	        Router = PointerRouter,
	        Selection = SelectionRouter,
	        Tabs = { "profile", "settings", "billing" },
	        InitialActive = "profile",
	    })
	    local tab = tabs.GetTab("settings")
	    local panel = tabs.GetPanel("settings")
	    return create("Frame")({
	        create("Frame")(tab.GetRootProps(props)),
	        create("Frame")(panel.GetRootProps({ Visible = panel.IsVisible })),
	    })

	AUTOMATIC ACTIVATION, UNLIKE createRadioGroup'S MANUAL ONE, AND THIS IS A
	REAL DECISION STATED RATHER THAN LEFT TO BE DISCOVERED. A radio group
	splits "arrow moves focus" from "an activation key selects" because a
	native `<input type=radio>` group does not confirm a choice until one is
	made on purpose. A tab list on the real engine, and on the web the ARIA
	pattern is modelled on, does the opposite: moving between tabs with the
	arrow keys switches the active one immediately, because a tab bar has no
	separate "confirm" step in ordinary use -- what a tab shows is a preview
	of its own content, not a choice with consequences a pending state would
	protect. So `OnArrowNext`/`OnArrowPrevious` here call `SelectionModel
	.Select` directly, and keyboard focus follows the newly active tab rather
	than sitting apart from it.

	TABS AND PANELS ARE TWO SEPARATE MACHINES SHARING ONE MODEL. A tab is a
	pressable, selectable button; a panel is a plain visibility source with
	no interaction of its own. Keeping them separate is what lets a caller
	lay the two out however it likes -- side by side, panel below, tabs in a
	sidebar -- rather than this file assuming one arrangement.
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

	--- Every tab key, in navigation order. Required and non-empty, the same
	--- as createRadioGroup's own `Options` field.
	Tabs: { any },
	--- Which tab starts active. Omit for none active at all. Ignored when
	--- `Active` is given.
	InitialActive: any?,

	--- CONTROLLED, the same shape `createContextMenu`'s own `IsOpen` already
	--- is: a getter, read through rather than copied. When given, a click or
	--- an arrow press calls `OnActiveChanged` with the key it would have
	--- activated WITHOUT changing what any tab's `IsActive` or panel's
	--- `IsVisible` reports -- the caller's own state is what actually has to
	--- move for either to change.
	Active: (() -> any)?,

	--- Handed to each tab's own `createPressable`.
	Disabled: (boolean | () -> boolean)?,
	Cursor: (string | () -> string)?,

	--- Called after `SelectionModel` has updated, with the newly active key
	--- (or nil if cleared).
	OnActiveChanged: ((active: any?) -> ())?,
}

export type Tab = {
	IsActive: () -> boolean,
	IsHovered: Source<boolean>,
	IsPressed: Source<boolean>,
	GetRootProps: (overrides: { [any]: any }?) -> { [any]: any },
	--- The bound actions and nothing else -- see `createPressable`'s own
	--- identical field. Milestone 54 sprint 3.
	GetActionProps: () -> { [any]: any },
	Destroy: () -> (),
}

export type Panel = {
	IsVisible: () -> boolean,
	GetRootProps: (overrides: { [any]: any }?) -> { [any]: any },
	--- A panel has no bound ACTION at all, unlike a tab -- it is a plain
	--- visibility source with no interaction of its own (see this file's own
	--- module comment). What this returns instead is the one piece of state
	--- that is not a cosmetic default either: `Visible` itself, so a caller
	--- with an already-styled frame gets the binding without `Name` or any
	--- other default `GetRootProps` would have supplied. Milestone 54 sprint 3.
	GetActionProps: () -> { [any]: any },
	Destroy: () -> (),
}

export type Tabs = {
	Active: () -> any?,
	GetTab: (key: any) -> Tab,
	GetPanel: (key: any) -> Panel,
	Destroy: () -> (),
}

local TAB_MACHINE_OPTIONS: { [string]: true } = {
	Disabled = true,
	Cursor = true,
}

local function tabDefaults(): { [any]: any }
	return {
		Name = "Tab",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = true,
	}
end

local function panelDefaults(): { [any]: any }
	return {
		Name = "TabPanel",
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

local function createTabs(options: Options): Tabs
	if not options.Router then
		error("createTabs needs a Router -- the binding has one, and hands it over", 2)
	end
	if not options.Selection then
		error("createTabs needs a Selection -- the binding has one, and hands it over", 2)
	end
	if not options.Tabs or #options.Tabs == 0 then
		error("createTabs needs at least one tab key in Tabs", 2)
	end

	local newSource: SourceFactory = options.Source or plainSource
	local action: ActionFactory = options.Action or identityAction

	local orderedKeys = options.Tabs

	--- CONTROLLED WHEN `Active` IS GIVEN, the same test `createCheckbox`'s
	--- own `Checked` and `createRadioGroup`'s own `Value` already use.
	local controlled: (() -> any)? = options.Active

	local active = newSource(if controlled then controlled() else options.InitialActive)

	local disabled: (() -> boolean)? = nil
	if type(options.Disabled) == "function" then
		disabled = options.Disabled :: () -> boolean
	elseif options.Disabled ~= nil then
		disabled = function(): boolean
			return options.Disabled :: boolean
		end
	end

	local initialActive = if controlled then controlled() else options.InitialActive
	local model = SelectionModel.new({
		Mode = "single",
		InitialSelection = if initialActive ~= nil then { initialActive } else nil,
	})

	local tabState: {
		[any]: {
			boundElement: any,
			isActive: Source<boolean>,
		},
	} = {}
	local panelState: {
		[any]: {
			isVisible: Source<boolean>,
		},
	} = {}
	local tabMachines: { [any]: Tab } = {}
	local panelMachines: { [any]: Panel } = {}

	local function keyIndex(key: any): number?
		for i, k in ipairs(orderedKeys) do
			if k == key then
				return i
			end
		end
		return nil
	end

	model.Subscribe(function()
		for key, state in pairs(tabState) do
			state.isActive(model.IsSelected(key))
		end
		for key, state in pairs(panelState) do
			state.isVisible(model.IsSelected(key))
		end
		active(model.GetSelectedKeys()[1])
		if options.OnActiveChanged then
			options.OnActiveChanged(model.GetSelectedKeys()[1])
		end
	end)

	--- GATED HERE, THE SAME REASON createRadioGroup'S OWN `selectKey` IS: a
	--- click and an arrow press are two different callers of this one
	--- function.
	---
	--- CONTROLLED: THE MODEL NEVER WRITES -- see `createRadioGroup`'s own
	--- `selectKey`'s identical comment. `OnActiveChanged` still fires with
	--- the key this tab list believes should be active next.
	local function activateKey(key: any)
		if disabled and disabled() then
			return
		end
		if controlled then
			if options.OnActiveChanged then
				options.OnActiveChanged(key)
			end
			return
		end
		model.Select(key)
	end

	--- READ THROUGH, NOT COPIED, when controlled -- see `createCheckbox`'s
	--- own `isChecked`'s identical comment.
	local function currentActive(): any
		if controlled then
			return controlled()
		end
		return active()
	end

	--- Switches the active tab AND moves keyboard focus to it, in that
	--- order -- see this file's own module comment on why activation is
	--- immediate here, unlike createRadioGroup's roving-only arrows.
	local function moveAndActivate(fromKey: any, delta: number)
		local idx = keyIndex(fromKey)
		if not idx then
			return
		end
		local n = #orderedKeys
		local nextIdx = ((idx - 1 + delta) % n) + 1
		local nextKey = orderedKeys[nextIdx]
		activateKey(nextKey)
		local nextState = tabState[nextKey]
		if nextState and nextState.boundElement then
			options.Selection.Select(nextState.boundElement)
		end
	end

	local function getTab(key: any): Tab
		if tabMachines[key] then
			return tabMachines[key]
		end

		tabState[key] = {
			boundElement = nil,
			isActive = newSource(model.IsSelected(key)),
		}
		local state = tabState[key]

		local pressable = createPressable({
			Router = options.Router,
			Source = options.Source,
			Action = options.Action,
			Disabled = options.Disabled,
			Cursor = options.Cursor,
			OnActivated = function()
				activateKey(key)
			end,
		})

		local selectionHandle = options.Selection.Selectable({
			OnArrowNext = function()
				moveAndActivate(key, 1)
			end,
			OnArrowPrevious = function()
				moveAndActivate(key, -1)
			end,
		})

		local function getRootProps(overrides: { [any]: any }?): { [any]: any }
			local props = tabDefaults()

			if overrides then
				for k, v in pairs(overrides) do
					if type(k) == "number" then
						if v ~= nil then
							table.insert(props, v)
						end
					elseif TAB_MACHINE_OPTIONS[k :: any] or v == nil then
						continue
					elseif type(k) == "string" and string.match(k, "^On%u") then
						--- LOUD NOW, NOT SILENT (milestone 54 sprint 5) --
						--- see createPressable's own identical comment.
						warn(`createTabs: "{k}" is not a handler this machine recognises and was dropped`)
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

		--- READ THROUGH `controlled` WHEN CONTROLLED -- see `createRadioGroup`'s
		--- own per-option `isSelected`'s identical comment.
		local function isActive(): boolean
			if controlled then
				return controlled() == key
			end
			return state.isActive()
		end

		local tab: Tab = {
			IsActive = isActive,
			IsHovered = pressable.IsHovered,
			IsPressed = pressable.IsPressed,
			GetRootProps = getRootProps,
			GetActionProps = getActionProps,
			Destroy = destroy,
		}
		tabMachines[key] = tab
		return tab
	end

	local function getPanel(key: any): Panel
		if panelMachines[key] then
			return panelMachines[key]
		end

		panelState[key] = { isVisible = newSource(model.IsSelected(key)) }
		local state = panelState[key]

		--- READ THROUGH `controlled` WHEN CONTROLLED -- see the sibling tab's
		--- own `isActive`'s identical comment.
		local function isVisible(): boolean
			if controlled then
				return controlled() == key
			end
			return state.isVisible()
		end

		local function getRootProps(overrides: { [any]: any }?): { [any]: any }
			local props = panelDefaults()
			props.Visible = isVisible

			if overrides then
				for k, v in pairs(overrides) do
					if type(k) == "number" then
						if v ~= nil then
							table.insert(props, v)
						end
					elseif v == nil then
						continue
					else
						props[k] = v
					end
				end
			end

			return props
		end

		local function getActionProps(): { [any]: any }
			return { Visible = isVisible }
		end

		local panel: Panel = {
			IsVisible = isVisible,
			GetRootProps = getRootProps,
			GetActionProps = getActionProps,
			Destroy = function() end,
		}
		panelMachines[key] = panel
		return panel
	end

	return {
		Active = currentActive,
		GetTab = getTab,
		GetPanel = getPanel,
		Destroy = function()
			for _, tab in pairs(tabMachines) do
				tab.Destroy()
			end
			model.Clear()
		end,
	}
end

return {
	createTabs = createTabs,
}
