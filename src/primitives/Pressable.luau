--!strict
--[=[
	Pressable — the atomic press/hover/activate primitive.
	Part of Aether.Primitives (Layer 2A).

	NAMED FOR THE BEHAVIOUR, NOT THE WIDGET (ms-51 M14). This was `PressableFrame`,
	and Aether also shipped a `Button` primitive above it. Both names carried
	presentational freight that Layer 2 has no business asserting: "Frame" names a
	Roblox host class in a layer that is supposed to be host-agnostic, and "Button"
	implies a visual affordance — a label, padding, a background — none of which
	this decides. What this primitive actually owns is narrower and fully abstract:
	is the pointer over it, is it held down, did it activate, and which scope wins
	the hit.

	A Button is therefore a Layer 4 EXPRESSION that embeds a Pressable, not a
	primitive. The presentational one lives in the components tier (`spektr/button`).

	`PressableFrame` remains exported as an alias — Layer 4 consumers across
	StudioUI, StudioWindowing and prism-studio still spell it that way.

	WHAT IS LEFT HERE IS THE TREE. `core/createPressable` decides what is true and
	returns the props for it; this file supplies the three things a machine cannot
	have — the router, vide's `source`, vide's `action` — and creates one element
	out of what comes back. There is no press state on this side to disagree with
	the machine's.
]=]

local Deps = require("../Deps")
local PointerRouter = require("../PointerRouter")
local ScopeContext = require("../ScopeContext")

local createPressable = require("../core/createPressable").createPressable

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local Enum =
	Deps.Vocabulary.Enum

local vide = Deps.vide
local create = vide.create
local cleanup = vide.cleanup
local useScope = ScopeContext.useScope

export type PressableProps = {
	--- PointerRouter semantics
	Scope: any?,
	Layer: string?,
	Cursor: (string | () -> string)?,
	Disabled: (boolean | () -> boolean)?,
	HitTestable: boolean?,
	OnActivated: (() -> ())?,
	OnPressed: (() -> ())?,
	OnReleased: (() -> ())?,
	OnHoverChanged: ((hovered: boolean) -> ())?,
	FollowContentMovement: boolean?,

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
	ClipsDescendants: (boolean | () -> boolean)?,
	AutomaticSize: (Enum.AutomaticSize | () -> Enum.AutomaticSize)?,

	--- Children and actions
	[any]: any,
}

local function Pressable(props: PressableProps)
	local machine = createPressable({
		Router = PointerRouter,
		Source = vide.source,
		Action = vide.action,

		Scope = if props.Scope ~= nil then props.Scope else useScope(),
		Layer = props.Layer,
		Cursor = props.Cursor,
		Disabled = props.Disabled,
		HitTestable = props.HitTestable,
		FollowContentMovement = props.FollowContentMovement,
		OnActivated = props.OnActivated,
		OnPressed = props.OnPressed :: any,
		OnReleased = props.OnReleased,
		OnHoverChanged = props.OnHoverChanged,
	})

	cleanup(machine.Destroy)

	return create("Frame")(machine.GetRootProps(props))
end

return Pressable
