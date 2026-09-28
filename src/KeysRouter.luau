--!strict
--[[
	Aether · KeysRouter — the real `Options.Keys` capability `core/createDialog`
	asks for and cannot synthesise itself, wired to `UserInputService.InputBegan`
	the same way `SelectionRouter.luau` wires `OnKeyActivate`/`OnArrowNext` to it.

	MIRRORS SelectionRouter'S OWN SHAPE ON PURPOSE: an Engine-layer module,
	sibling to `PointerRouter`/`SelectionRouter`, reached through `Deps.Host
	.Services` rather than taken as an argument — this file exists so a
	Primitive (`Dialog.luau`) never names `UserInputService`/`InputBegan`
	itself, which is exactly what `tests/gates/verify_primitives_bind_machines
	.luau` forbids a Primitive from doing directly ("listens to host input" is
	one of its four named signals).

	SHIFT HAS NO RELEASE SIGNAL ON THIS HOST YET, confirmed by reading
	`host/src/services.rs` directly (`key_down`'s own doc comment: "PRESS
	ONLY, NO RELEASE... `InputEnded` has no keyboard side yet"). So Shift held
	is latched by `LeftShift`/`RightShift` going down and consumed (cleared)
	the moment the next key is handled — right for the ordinary case (a
	physical Shift+Tab fires "LeftShift" then "Tab" in that order) and
	honestly degraded, not silently wrong, for a Shift held across several
	bare Tab presses with no repeated `LeftShift` event, which this host
	cannot observe without a keyboard `InputEnded` it does not yet fire.
]]

local Deps = require("./Deps")

local UserInputService = Deps.Host.Services.UserInputService

local KeysRouter = {}

export type Keys = {
	OnKeyDown: (callback: (name: string, shift: boolean) -> ()) -> (() -> ()),
}

export type Options = {
	--- Gates whether a given keystroke reaches `callback` at all. Absent,
	--- every keystroke reaches it — the plain case, one dialog, one trap.
	--- A caller managing several stacked traps (`Dialog.luau`'s own use)
	--- passes "is my own trap the one that should currently answer", so an
	--- older trap can go quiet while a newer one is active without this
	--- file knowing anything about what "stacked" means for its caller.
	IsActive: (() -> boolean)?,
}

--- ABSENT ON A HOST THAT OFFERS NONE, the same as `SelectionRouter.Selectable`
--- connecting nothing when `UserInputService` is nil — a host reporting no
--- keyboard service is telling the truth about what it cannot do rather than
--- being handed a shim that would silently never fire.
function KeysRouter.Keys(options: Options?): Keys?
	if not UserInputService then
		return nil
	end

	local isActive = options and options.IsActive

	return {
		OnKeyDown = function(callback: (name: string, shift: boolean) -> ())
			local shiftHeld = false
			local connection = UserInputService.InputBegan:Connect(function(input: any, gameProcessed: boolean?)
				if gameProcessed then
					return
				end
				if input.UserInputType ~= Enum.UserInputType.Keyboard then
					return
				end
				local name = input.KeyCode.Name
				if name == "LeftShift" or name == "RightShift" then
					shiftHeld = true
					return
				end
				if isActive and not isActive() then
					return
				end
				callback(name, shiftHeld)
				--- CONSUMED, not latched forever — see this file's own header
				--- on why this host cannot tell a held Shift apart from a
				--- tapped one past this single key.
				shiftHeld = false
			end)
			return function()
				connection:Disconnect()
			end
		end,
	}
end

return KeysRouter
