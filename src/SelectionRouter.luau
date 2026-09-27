--!strict
--[[
	Aether · SelectionRouter -- keyboard activation and roving focus, through
	GuiService's own SelectedObject and the same InputBegan a pointer press
	already reaches.

	MIRRORS PointerRouter'S OWN SHAPE ON PURPOSE: a table of factories reached
	through `Deps.Host.Services` rather than taken as an argument, so this
	file is what a real binding hands `createCheckbox`/`createRadioGroup` as
	their `Selection` port, and a test hands a fake with the identical
	`Selectable(props) -> handle` shape instead.

	WHAT "SELECTED" MEANS HERE, faithfully rather than invented: the real
	engine's own `GuiService.SelectedObject`, set by whatever drives keyboard
	or gamepad navigation, or by `Select` below -- this file does not decide
	who gets selected on its own initiative any more than `PointerRouter`
	decides who gets clicked. `Selectable = true` (set by `createCheckbox`'s
	own defaults) is what makes an element a legal candidate; assigning
	`SelectedObject`, here or from elsewhere, is what actually chooses one.

	ARROWS MOVE FOCUS; THEY DO NOT SELECT. `OnArrowNext`/`OnArrowPrevious` are
	answered independently of `OnKeyActivate` -- a radio group's own roving
	focus calls `Select` to move `SelectedObject` onto a sibling, and it takes
	a SEPARATE activation key press to change which option is actually
	checked. That split is a real behaviour decision, not an oversight: it
	matches a roving-tabindex listbox rather than a native HTML radio group,
	where an arrow key selects immediately. See createRadioGroup's own module
	comment for why.
]]

local Deps = require("./Deps")
local coreSelection = require("./core/Selection")

local UserInputService = Deps.Host.Services.UserInputService
local GuiService = Deps.Host.Services.GuiService

local SelectionRouter = {}

export type SelectableProps = coreSelection.SelectableProps
export type SelectionHandle = coreSelection.SelectionHandle

local DEFAULT_ACTIVATION_KEYS = { Space = true }

function SelectionRouter.Selectable(props: SelectableProps): SelectionHandle
	local bound: any = nil
	local activationKeys = props.ActivationKeys or DEFAULT_ACTIVATION_KEYS

	--- ABSENT ON A HOST THAT OFFERS NEITHER, the same as `PointerRouter`
	--- connecting nothing when `UserInputService` is nil -- a host reporting
	--- no keyboard service is telling the truth about what it cannot do
	--- rather than being handed a shim that would silently never fire.
	local connection: RBXScriptConnection? = nil
	if UserInputService then
		connection = UserInputService.InputBegan:Connect(function(input, gameProcessed: boolean?)
			if gameProcessed then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if not bound or not GuiService then
				return
			end
			--- `==` COMPARES REAL IDENTITY, the same handle `Bind` was called
			--- with against the same handle `GuiService` hands back -- proven
			--- on the DataModel host by `Instance` caching one userdata per
			--- id, and by the engine's own semantics natively.
			if GuiService.SelectedObject ~= bound then
				return
			end

			if activationKeys[input.KeyCode.Name] then
				if props.OnKeyActivate then
					props.OnKeyActivate()
				end
			elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.Down then
				if props.OnArrowNext then
					props.OnArrowNext()
				end
			elseif input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Up then
				if props.OnArrowPrevious then
					props.OnArrowPrevious()
				end
			end
		end)
	end

	return {
		Bind = function(element: any)
			bound = element
		end,
		Destroy = function()
			if connection then
				connection:Disconnect()
			end
		end,
	}
end

--- Move keyboard/gamepad selection to `element` directly. Absent a
--- `GuiService` (the host offers no selection concept at all), this is a
--- no-op rather than an error -- the same shape `PointerRouter` answers a
--- missing `UserInputService` with.
function SelectionRouter.Select(element: any)
	if GuiService then
		GuiService.SelectedObject = element
	end
end

return SelectionRouter
