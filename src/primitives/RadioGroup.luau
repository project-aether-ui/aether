--!strict
--[=[
	RadioGroup — exactly one of N options selected, arrow-key roving focus
	between them. Part of Aether.Primitives (Layer 2A).

	NAMED FOR THE BEHAVIOUR, THE SAME AS Checkbox and Tabs. `core/createRadioGroup`
	decides what is true and hands back `GetOption`; this file supplies the
	two routers, vide's `source`, and vide's `action`, so a caller never has
	to name `PointerRouter` or `SelectionRouter` to get a radio group working.

	NO SINGLE ELEMENT IS CREATED HERE, the same reason `Tabs.luau` creates
	none: a group is N options laid out however the caller likes, so this
	stays a factory, exactly the shape `createRadioGroup` itself already has.

	`Source`/`Action` ARE OVERRIDABLE TOO, the same reason `Tabs.luau`'s own
	are -- see that file's own comment. A host with its own vide package
	must be able to hand its own reactive graph over, since a source only
	notifies the graph that created it.
]=]

local Deps = require("../Deps")
local PointerRouter = require("../PointerRouter")
local SelectionRouter = require("../SelectionRouter")

local coreRadioGroup = require("../core/createRadioGroup")
local createRadioGroup = coreRadioGroup.createRadioGroup

local vide = Deps.vide

export type Options = {
	--- Overridable the same way `Checkbox`'s own `Scope` is.
	Router: coreRadioGroup.Router?,
	Selection: coreRadioGroup.Selection?,
	Source: coreRadioGroup.SourceFactory?,
	Action: coreRadioGroup.ActionFactory?,

	Options: { any },
	InitialValue: any?,

	Disabled: (boolean | () -> boolean)?,
	Cursor: (string | () -> string)?,

	OnValueChanged: ((value: any?) -> ())?,
}

local function RadioGroup(options: Options): coreRadioGroup.RadioGroup
	return createRadioGroup({
		Router = if options.Router ~= nil then options.Router else PointerRouter,
		Selection = if options.Selection ~= nil then options.Selection else SelectionRouter,
		Source = if options.Source ~= nil then options.Source else vide.source,
		Action = if options.Action ~= nil then options.Action else vide.action,

		Options = options.Options,
		InitialValue = options.InitialValue,
		Disabled = options.Disabled,
		Cursor = options.Cursor,
		OnValueChanged = options.OnValueChanged,
	})
end

return RadioGroup
