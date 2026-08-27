--!strict
--[=[
	useFloating — Reactive hook for positioning floating elements (dropdown popups, tooltips, context menus).
	Part of Aether.Engine (Layer 2.5/3 Headless Positioning).
]=]

local isRoblox = typeof(game) == "Instance"

local FloatingMath = require("./FloatingMath")
local ScreenCoords = require("./ScreenCoords")
local Deps = require("./Deps")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below reads exactly as it
--- did — what changed is who provides them, not how they are spelled.
--- The scene contract, not the engine (ms-51 M16 part 3). Anchor geometry is
--- the same question hit-testing asks, so it goes through the same door.
local Scene = Deps.Host.Scene

local UDim2 =
	Deps.Vocabulary.UDim2

local source = Deps.source
local effect = Deps.effect
local scopedCleanup = Deps.cleanup

local Workspace = if isRoblox then (game :: any):GetService("Workspace") else nil
local RunService = if isRoblox then (game :: any):GetService("RunService") else nil

export type Placement = FloatingMath.Placement
export type ComputeOptions = FloatingMath.ComputeOptions
export type Rect = FloatingMath.Rect

export type FloatingProps = {
	Anchor: any, -- GuiObject | (() -> Vector2) | (() -> Rect) | Rect
	Floating: any?, -- GuiObject | (() -> Vector2) | (() -> Rect) | Rect
	Placement: Placement?,
	Offset: number?,
	CrossOffset: number?,
	AutoFlip: boolean?,
	ClampToViewport: boolean?,
	ViewportPadding: number?,
	IsOpen: (boolean | (() -> boolean))?,
	CustomViewport: (() -> Rect)?,
}

export type FloatingHandle = {
	Position: () -> UDim2,
	Placement: () -> Placement,
	DidFlip: () -> boolean,
	Update: () -> (),
}

local function toRect(target: any): Rect
	if not target then
		return { X = 0, Y = 0, Width = 0, Height = 0 }
	end

	if typeof(target) == "Vector2" then
		return { X = target.X, Y = target.Y, Width = 0, Height = 0 }
	end

	if typeof(target) == "function" then
		local val = target()
		if typeof(val) == "Vector2" then
			return { X = val.X, Y = val.Y, Width = 0, Height = 0 }
		elseif typeof(val) == "table" and val.X and val.Width then
			return val :: Rect
		elseif Scene.IsSurface(val) then
			local x, y, w, h = Scene.Bounds(val)
			return { X = x, Y = y, Width = w, Height = h }
		end
		return { X = 0, Y = 0, Width = 0, Height = 0 }
	end

	if typeof(target) == "table" and target.X and target.Width then
		return target :: Rect
	end

	if Scene.IsSurface(target) then
		local x, y, w, h = Scene.Bounds(target)
		return {
			X = x,
			Y = y,
			Width = w,
			Height = h,
		}
	end

	return { X = 0, Y = 0, Width = 0, Height = 0 }
end

local function getViewportRect(customGetter: (() -> Rect)?): Rect
	if customGetter then
		return customGetter()
	end

	if isRoblox and Workspace then
		local cam = Workspace.CurrentCamera
		if cam then
			local vSize = cam.ViewportSize
			local inset = ScreenCoords.GetGuiInset()
			return {
				X = inset.X,
				Y = inset.Y,
				Width = vSize.X,
				Height = vSize.Y,
			}
		end
	end

	return { X = 0, Y = 0, Width = 1920, Height = 1080 }
end

local function useFloating(props: FloatingProps): FloatingHandle
	local position = source(UDim2.new(0, 0, 0, 0))
	local resolvedPlacement = source(props.Placement or "bottom-start")
	local didFlip = source(false)

	local function update()
		local isOpen = if props.IsOpen == nil
			then true
			elseif typeof(props.IsOpen) == "function"
			then props.IsOpen()
			else props.IsOpen

		if not isOpen then
			return
		end

		local anchorRect = toRect(props.Anchor)
		local floatingRect = toRect(props.Floating)
		local viewportRect = getViewportRect(props.CustomViewport)

		local result = FloatingMath.ComputePosition(anchorRect, floatingRect, viewportRect, {
			Placement = props.Placement or "bottom-start",
			Offset = props.Offset,
			CrossOffset = props.CrossOffset,
			AutoFlip = props.AutoFlip,
			ClampToViewport = props.ClampToViewport,
			ViewportPadding = props.ViewportPadding,
		} :: any)

		position(UDim2.new(0, result.X, 0, result.Y))
		resolvedPlacement(result.Placement)
		didFlip(result.DidFlip)
	end

	-- Initial calculation
	update()

	-- Reactive update on reactive prop changes
	effect(function()
		update()
	end)

	-- Frame bus update for moving anchors
	if isRoblox and RunService and RunService:IsClient() then
		local conn = RunService.RenderStepped:Connect(update)
		if scopedCleanup then
			scopedCleanup(function()
				conn:Disconnect()
			end)
		end
	end

	return {
		Position = position,
		Placement = resolvedPlacement,
		DidFlip = didFlip,
		Update = update,
	}
end

return useFloating
