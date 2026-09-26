--!strict
--[[
	Aether · SelectionRouter -- keyboard activation, through GuiService's own
	SelectedObject and the same InputBegan a pointer press already reaches.

	MIRRORS PointerRouter'S OWN SHAPE ON PURPOSE: a table of factories reached
	through `Deps.Host.Services` rather than taken as an argument, so this
	file is what a real binding hands `createCheckbox` as its `Selection`
	port, and a test hands a fake with the identical `Selectable(props) ->
	handle` shape instead.

	WHAT "SELECTED" MEANS HERE, faithfully rather than invented: the real
	engine's own `GuiService.SelectedObject`, set by whatever drives keyboard
	or gamepad navigation -- this file does not decide who gets selected, the
	same way `PointerRouter` does not decide who gets clicked. `Selectable =
	true` (set by `createCheckbox`'s own defaults) is what makes an element a
	legal candidate; something else assigning `SelectedObject` is what
	actually chooses one.

	ONE KEY, SPACE, and this is a real gap named rather than papered over.
	Roblox's own `GuiButton.Activated` also fires for Enter and for a
	gamepad's A button; this only answers Space, because that is this
	milestone's own stated scope for a checkbox. Widening it to match the
	engine's full activation set is later work, not assumed here.
]]

local Deps = require("./Deps")

local UserInputService = Deps.Host.Services.UserInputService
local GuiService = Deps.Host.Services.GuiService

local SelectionRouter = {}

export type SelectableProps = {
	OnKeyActivate: (() -> ())?,
}

export type SelectionHandle = {
	Bind: (element: any) -> (),
	Destroy: () -> (),
}

function SelectionRouter.Selectable(props: SelectableProps): SelectionHandle
	local bound: any = nil

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
			if input.KeyCode ~= Enum.KeyCode.Space then
				return
			end
			if not bound or not GuiService then
				return
			end
			--- `==` COMPARES REAL IDENTITY, the same handle `Bind` was
			--- called with against the same handle `GuiService` hands back --
			--- proven on the DataModel host by `Instance` caching one
			--- userdata per id, and by the engine's own semantics natively.
			if GuiService.SelectedObject == bound and props.OnKeyActivate then
				props.OnKeyActivate()
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

return SelectionRouter
