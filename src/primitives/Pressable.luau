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
]=]

local isRoblox = typeof(game) == "Instance"
local Deps = require("../Deps")
local PointerRouter = require("../PointerRouter")
local ScopeContext = require("../ScopeContext")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local Enum =
	Deps.Vocabulary.Enum

local vide = Deps.vide
local create = vide.create
local action = vide.action
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
	local disabledGetter = if type(props.Disabled) == "function"
		then props.Disabled
		elseif props.Disabled ~= nil
		then function() return props.Disabled :: boolean end
		else nil

	local activeScope = if props.Scope ~= nil then props.Scope else useScope()

	local pressable = PointerRouter.Pressable({
		Scope = activeScope,
		Layer = props.Layer,
		Cursor = props.Cursor,
		Disabled = disabledGetter,
		HitTestable = if props.HitTestable ~= nil then props.HitTestable else false,
		OnActivated = props.OnActivated,
		OnPressed = props.OnPressed,
		OnReleased = props.OnReleased,
		OnHoverChanged = props.OnHoverChanged,
		FollowContentMovement = props.FollowContentMovement,
	})

	cleanup(pressable.Destroy)

	-- Separate props from children / array entries
	local frameProps: { [any]: any } = {
		Name = props.Name or "Pressable",
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		BackgroundColor3 = props.BackgroundColor3,
		BackgroundTransparency = props.BackgroundTransparency or 1,
		BorderSizePixel = props.BorderSizePixel or 0,
		BorderColor3 = props.BorderColor3,
		ClipsDescendants = props.ClipsDescendants,
		AutomaticSize = props.AutomaticSize,

		action(pressable.Bind),
	}

	-- Pass through numbered children and custom actions/instances
	for k, v in pairs(props) do
		if type(k) == "number" and v ~= nil then
			table.insert(frameProps, v)
		end
	end

	return create("Frame")(frameProps)
end

return Pressable
