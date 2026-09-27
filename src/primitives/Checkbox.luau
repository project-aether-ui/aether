--!strict
--[=[
	Checkbox — a checked/unchecked control, activated by a click or a Space
	press while selected.
	Part of Aether.Primitives (Layer 2A).

	NAMED FOR THE BEHAVIOUR, THE SAME AS Pressable. What this owns is narrow
	and fully abstract: is it checked, is the pointer over it, is it held,
	did a click or a keyboard press activate it. Appearance -- a box, a
	checkmark glyph, a label -- is a Layer 4 expression built on top of this,
	the same relationship Pressable has to a presentational Button.

	WHAT IS LEFT HERE IS THE TREE, the same as `Pressable.luau`:
	`core/createCheckbox` decides what is true and returns the props for it;
	this file supplies the four things the machine cannot have -- the two
	routers, vide's `source`, vide's `action` -- and creates one element out
	of what comes back.

	ROUTER AND SELECTION ARE AMBIENT (milestone 54 sprint 2), read through
	`RouterContext` the same way `Scope` is read through `ScopeContext` --
	an explicit `Router`/`Selection` prop still wins when a caller passes
	one, exactly the precedence `Scope` already has.
]=]

local Deps = require("../Deps")
local RouterContext = require("../RouterContext")
local ScopeContext = require("../ScopeContext")

local createCheckbox = require("../core/createCheckbox").createCheckbox

local vide = Deps.vide
local create = vide.create
local cleanup = vide.cleanup
local useScope = ScopeContext.useScope
local useRouter = RouterContext.useRouter
local useSelection = RouterContext.useSelection

export type CheckboxProps = {
	--- Overridable the same way `Scope` is; omit to use whatever is ambient.
	Router: any?,
	Selection: any?,

	--- PointerRouter semantics, the same as `Pressable`'s own.
	Scope: any?,
	Layer: string?,
	Cursor: (string | () -> string)?,
	Disabled: (boolean | () -> boolean)?,
	HitTestable: boolean?,
	FollowContentMovement: boolean?,
	Priority: number?,

	--- createCheckbox semantics
	Checked: boolean?,
	OnCheckedChanged: ((checked: boolean) -> ())?,

	--- GuiObject Frame properties
	Name: string?,
	Size: (UDim2 | () -> UDim2)?,
	Position: (UDim2 | () -> UDim2)?,
	AnchorPoint: (Vector2 | () -> Vector2)?,
	LayoutOrder: (number | () -> number)?,
	ZIndex: (number | () -> number)?,
	Visible: (boolean | () -> boolean)?,
	BackgroundColor3: (Color3 | () -> Color3)?,
	BackgroundTransparency: (number | () -> number)?,
	BorderSizePixel: (number | () -> number)?,
	BorderColor3: (Color3 | () -> Color3)?,

	--- Children and actions
	[any]: any,
}

local function Checkbox(props: CheckboxProps)
	local machine = createCheckbox({
		Router = if props.Router ~= nil then props.Router else useRouter(),
		Selection = if props.Selection ~= nil then props.Selection else useSelection(),
		Source = vide.source,
		Action = vide.action,

		Scope = if props.Scope ~= nil then props.Scope else useScope(),
		Layer = props.Layer,
		Cursor = props.Cursor,
		Disabled = props.Disabled,
		HitTestable = props.HitTestable,
		FollowContentMovement = props.FollowContentMovement,
		Priority = props.Priority,
		Checked = props.Checked,
		OnCheckedChanged = props.OnCheckedChanged,
	})

	cleanup(machine.Destroy)

	return create("Frame")(machine.GetRootProps(props))
end

return Checkbox
