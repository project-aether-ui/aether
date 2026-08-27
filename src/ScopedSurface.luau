--!strict
local Deps = require("./Deps")
--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
local UDim2 =
	Deps.Vocabulary.UDim2

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
		return create("Frame")({
			Name = props.Name or "ScopedSurface",
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
			table.unpack(children),
		})
	end)
end

return ScopedSurface
