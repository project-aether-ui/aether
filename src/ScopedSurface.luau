--!strict
local Deps = require("./Deps")
local vide = Deps.vide
local create = vide.create
local cleanup = vide.cleanup
local action = vide.action

local InputScope = require("./InputScope")
local ScopeContext = require("./ScopeContext")
local ScopeProvider = ScopeContext.ScopeProvider

local nextId = 0
local function generateScopeId(prefix: string?): string
	nextId += 1
	return (prefix or "Surface") .. "_" .. tostring(nextId)
end

export type ScopedSurfaceProps = {
	Id: string?,
	Policy: ("Block" | "Modal" | "Pass")?,
	Priority: (number | () -> number)?,
	Visible: (boolean | () -> boolean)?,
	OnDismiss: (() -> ())?,
	DimTransparency: (number | () -> number)?,
	DimColor: (Color3 | () -> Color3)?,
	IsSettled: (() -> boolean)?,

	-- Frame styling & layout properties
	Name: string?,
	Size: any?,
	Position: any?,
	AnchorPoint: any?,
	ZIndex: any?,
	LayoutOrder: any?,
	BackgroundTransparency: any?,
	BackgroundColor3: any?,
	BorderSizePixel: any?,
	ClipsDescendants: any?,
	AutomaticSize: any?,

	--- CHILDREN BUILT INSIDE THIS SURFACE'S SCOPE, rather than before it.
	---
	--- A child written in the array part is CONSTRUCTED AT THE CALL SITE, which
	--- is outside the `ScopeProvider` below -- so anything it registers with the
	--- pointer router carries no scope, and a modal surface's own barrier, which
	--- IS in the scope, outranks it. That is a control inside a menu losing its
	--- click to the backdrop drawn under the menu, and it is invisible in the
	--- tree: the child is in the right place and is arbitrated as though it were
	--- somewhere else. A function here is called where the context is set.
	Children: (() -> any)?,

	-- Handles & callbacks
	OutScope: ((handle: any) -> ())?,
	SurfaceRef: ((ref: GuiObject) -> ())?,

	[any]: any,
}

--- ScopedSurface: The universal macro container surface primitive.
---
--- Owns the InputScope lifecycle, perimeter binding, engine game input sinking,
--- and ScopeProvider context propagation for all children inside it.
local function ScopedSurface(props: ScopedSurfaceProps)
	local scopeId = props.Id or generateScopeId(props.Name)
	local scope = InputScope.new({
		Id = scopeId,
		Layer = props.Layer,
		Policy = props.Policy or "Block",
		Priority = props.Priority,
		Visible = props.Visible,
		OnDismiss = props.OnDismiss,
		DimTransparency = props.DimTransparency,
		DimColor = props.DimColor,
		IsSettled = props.IsSettled,
	})

	cleanup(scope.Destroy)

	if props.OutScope then
		props.OutScope(scope)
	end

	local children: { any } = {}
	local passProps: { [any]: any } = {}

	local RESERVED_SURFACE_PROPS: { [string]: boolean } = {
		Id = true,
		Children = true,
		Layer = true,
		Policy = true,
		Priority = true,
		Visible = true,
		OnDismiss = true,
		DimTransparency = true,
		DimColor = true,
		IsSettled = true,
		OutScope = true,
		SurfaceRef = true,
	}

	for k, v in pairs(props) do
		if type(k) == "number" then
			table.insert(children, v)
		elseif not RESERVED_SURFACE_PROPS[k] then
			passProps[k] = v
		end
	end

	return ScopeProvider(scope, function()
		--- INSIDE THE PROVIDER AND OUTSIDE THE `create`. The context is set here,
		--- and the scope is still the caller's stable one -- a child built as a
		--- vide dynamic child would run in a reactive scope instead, where the
		--- effects a keyed list creates are not allowed to exist.
		local scoped = if props.Children then props.Children() else nil

		return create("Frame")({
			Name = props.Name or "ScopedSurface",
			--- A HIDDEN SURFACE IS HIDDEN. `Visible` reached the scope, which
			--- stopped it taking input, and never reached the frame, which went
			--- on drawing -- so a closed menu was a menu you could see and could
			--- not click. The scope and the picture disagreed, and only the scope
			--- was tested.
			Visible = props.Visible,
			Size = props.Size or UDim2.fromScale(1, 1),
			Position = props.Position or UDim2.fromScale(0, 0),
			AnchorPoint = props.AnchorPoint,
			ZIndex = props.ZIndex,
			LayoutOrder = props.LayoutOrder,
			BackgroundTransparency = if props.BackgroundTransparency ~= nil then props.BackgroundTransparency else 1,
			BackgroundColor3 = props.BackgroundColor3,
			BorderSizePixel = props.BorderSizePixel or 0,
			ClipsDescendants = props.ClipsDescendants,
			AutomaticSize = props.AutomaticSize,

			action(function(ref)
				if ref then
					scope.Bind(ref)
					if props.SurfaceRef then
						props.SurfaceRef(ref)
					end
				end
			end),

			-- For modal policy, automatically render the backdrop barrier
			if props.Policy == "Modal" then scope.Barrier() else nil,

			passProps,
			scoped,
			table.unpack(children),
		})
	end)
end

return ScopedSurface
