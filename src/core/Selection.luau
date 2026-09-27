--!strict
--[[
	Aether · core/Selection -- the keyboard/gamepad selection port's own
	types, shared by every Layer 1 machine that needs one.

	A TYPE MODULE, NOTHING ELSE, the same reason `createPressable`'s own
	`Router` type lives beside the machine that first needed it rather than
	inside `PointerRouter` itself: a port is an interface a machine declares
	and a binding satisfies, not a thing the real implementation owns the
	definition of. `createCheckbox` and `createRadioGroup` both take a
	`Selection`, and both need the SAME shape rather than two that could
	drift, which is the whole reason this file exists instead of one machine
	requiring the other's.
]]

--- The part of a keyboard/gamepad selection router a machine uses, and all
--- of it -- mirrors `createPressable`'s own `RouterHandle`.
export type SelectionHandle = {
	Bind: (element: any) -> (),
	Destroy: () -> (),
}

export type SelectableProps = {
	--- Called when an activation key is pressed while this element is the
	--- selected one. What counts as "selected" is the Selection
	--- implementation's own answer -- on a DataModel host,
	--- `GuiService.SelectedObject`.
	OnKeyActivate: (() -> ())?,
	--- Called on the "move forward" key -- Right or Down on a DataModel host.
	--- A checkbox has no use for this; a radio group's own roving focus is
	--- exactly this call.
	OnArrowNext: (() -> ())?,
	--- Called on the "move backward" key -- Left or Up.
	OnArrowPrevious: (() -> ())?,
	--- Which keys call `OnKeyActivate`, by KEYCODE NAME (`"Space"`,
	--- `"Return"`) rather than a real `Enum.KeyCode` value -- a machine
	--- naming this is still Layer 1, with no engine type in sight; turning
	--- the name into whatever the host's own keyboard actually reports is
	--- the real Selection implementation's job. Defaults to Space alone when
	--- omitted, a checkbox's own real engine convention, since not every
	--- consumer of this port wants the same activation keys a radio group
	--- does.
	ActivationKeys: { [string]: boolean }?,
}

export type Selection = {
	Selectable: (props: SelectableProps) -> SelectionHandle,
	--- Move keyboard/gamepad selection to `element` directly -- what a radio
	--- group's own arrow-key handling calls to rove focus onto a sibling
	--- without changing which option is CHECKED. A checkbox never calls this;
	--- its own selection is a fact about it being clicked or tabbed to, not
	--- something the checkbox machine decides on anyone's behalf.
	Select: (element: any) -> (),
}

return {}
