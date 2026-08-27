--!strict
--[[
	ScreenCoords: Agnostic screen and viewport coordinate space transformations.

	Centralizes coordinate space conversions between:
	1. Screen Space (Physical Device Pixels):
	   - Origin: (0, 0) at the top-left corner of the OS client window.
	   - Used by: IgnoreGuiInset=true containers, UserInputService:GetMouseLocation(), GuiObject.AbsolutePosition.

	2. Viewport / Safe-Area Space:
	   - Origin: (0, 0) directly below the topbar / notch inset.
	   - Used by: IgnoreGuiInset=false containers, InputObject.Position.
]]

local isRoblox = typeof(game) == "Instance"
local UserInputService = if isRoblox then (game :: any):GetService("UserInputService") else nil
local GuiService = if isRoblox then (game :: any):GetService("GuiService") else nil

--- ms-51 M16: resolved here purely for the value vocabulary below.
local Deps = require("./Deps")

--- The value vocabulary, from the HOST rather than from Roblox globals
--- (ms-51 M16). Bound as locals so every call site below is unchanged.
local UDim2, Vector2 =
	Deps.Vocabulary.UDim2, Deps.Vocabulary.Vector2

local ScreenCoords = {}

--- Returns the top and bottom GuiInset vectors (topbar / notch insets) safely.
function ScreenCoords.GetGuiInset(): (Vector2, Vector2)
	if not isRoblox or not GuiService then
		return Vector2.zero, Vector2.zero
	end
	local ok, topInset, bottomInset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and topInset then
		return topInset, bottomInset or Vector2.zero
	end
	return Vector2.zero, Vector2.zero
end

--- Converts a physical screen space coordinate to a viewport safe-area coordinate (subtracts topbar inset).
function ScreenCoords.ScreenToViewport(screenPos: Vector2): Vector2
	local topInset = ScreenCoords.GetGuiInset()
	return screenPos - topInset
end

--- Converts a viewport safe-area coordinate to a physical screen space coordinate (adds topbar inset).
function ScreenCoords.ViewportToScreen(viewportPos: Vector2): Vector2
	local topInset = ScreenCoords.GetGuiInset()
	return viewportPos + topInset
end

--- Returns the pointer/input position in Viewport / Safe-Area space (Y=0 is below topbar).
--- Guaranteed to return Viewport Space coordinates regardless of input type.
function ScreenCoords.GetViewportPosition(input: (InputObject | Vector3 | Vector2)?): Vector2
	if not isRoblox then
		return Vector2.zero
	end

	if typeof(input) == "Instance" and input:IsA("InputObject") then
		return Vector2.new(input.Position.X, input.Position.Y)
	elseif typeof(input) == "Vector3" or typeof(input) == "Vector2" then
		local v = if typeof(input) == "Vector3" then Vector2.new(input.X, input.Y) else input
		return ScreenCoords.ScreenToViewport(v)
	end
	if UserInputService then
		return ScreenCoords.ScreenToViewport(UserInputService:GetMouseLocation())
	end
	return Vector2.zero
end

--- Returns the true physical screen coordinates of the pointer/input (Y=0 is top of OS window).
--- Matches GuiObject.AbsolutePosition 1:1.
--- Guaranteed to return Screen Space coordinates regardless of input type.
function ScreenCoords.GetScreenPosition(input: (InputObject | Vector3 | Vector2)?): Vector2
	if not isRoblox then
		return Vector2.zero
	end

	if typeof(input) == "Instance" and input:IsA("InputObject") then
		return ScreenCoords.ViewportToScreen(Vector2.new(input.Position.X, input.Position.Y))
	elseif typeof(input) == "Vector3" or typeof(input) == "Vector2" then
		return if typeof(input) == "Vector3" then Vector2.new(input.X, input.Y) else input
	end
	if UserInputService then
		return UserInputService:GetMouseLocation()
	end
	return Vector2.zero
end

--- Converts an element's AbsolutePosition (Physical Screen Space) into the local UDim2 offset
--- required for positioning inside a target ScreenGui based on its IgnoreGuiInset setting.
function ScreenCoords.AbsoluteToGuiPosition(absPos: Vector2, ignoreGuiInset: boolean): UDim2
	if ignoreGuiInset then
		return UDim2.fromOffset(absPos.X, absPos.Y)
	else
		local vpPos = ScreenCoords.ScreenToViewport(absPos)
		return UDim2.fromOffset(vpPos.X, vpPos.Y)
	end
end

--- Computes the relative offset of a screen position inside a specific container Frame.
function ScreenCoords.GetContainerRelativePosition(screenPos: Vector2, container: GuiObject): Vector2
	return screenPos - container.AbsolutePosition
end

return ScreenCoords
