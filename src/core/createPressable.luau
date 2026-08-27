--!strict
-- Layer 2: Headless Interaction Protocol — createPressable
-- Platform-agnostic behavioral contract (0 Roblox Instance coupling).

export type GeometryBounds = {
	X: number,
	Y: number,
	Width: number,
	Height: number,
}

export type GeometrySource = {
	GetBounds: () -> GeometryBounds,
	GetZIndex: (() -> number)?,
	IsVisible: (() -> boolean)?,
	GetParent: (() -> any)?,
}

export type PressableOptions = {
	Disabled: (boolean | (() -> boolean))?,
	Priority: number?,
	OnClick: (() -> ())?,
	OnActivated: (() -> ())?,
	OnHoverChanged: ((isHovered: boolean) -> ())?,
	OnPressedChanged: ((isPressed: boolean) -> ())?,
	PointerRouter: any?,
}

export type PressableInstance = {
	IsHovered: () -> boolean,
	IsPressed: () -> boolean,
	BindTarget: (geometry: GeometrySource) -> (() -> ()),
	Destroy: () -> (),
}

local function createPressable(options: PressableOptions): PressableInstance
	local opts = options or {}
	local router = opts.PointerRouter
	
	-- Defensive fallback resolution for PointerRouter if not passed
	if not router then
		local ok, res = pcall(require, "../PointerRouter")
		if ok and res then
			router = res
		end
	end

	local isHovered = false
	local isPressed = false
	local currentRegistration: any = nil

	local function getDisabled(): boolean
		local d = opts.Disabled
		if type(d) == "function" then
			return (d :: any)() == true
		end
		return d == true
	end

	local self = {} :: PressableInstance

	function self.IsHovered(): boolean
		return isHovered
	end

	function self.IsPressed(): boolean
		return isPressed
	end

	function self.BindTarget(geometry: GeometrySource): () -> ()
		if not router or not router.Pressable then
			return function() end
		end

		local fakeSurface = {
			Visible = if geometry.IsVisible then geometry.IsVisible() else true,
			ZIndex = if geometry.GetZIndex then geometry.GetZIndex() else 1,
			AbsolutePosition = {
				X = geometry.GetBounds().X,
				Y = geometry.GetBounds().Y,
			},
			AbsoluteSize = {
				X = geometry.GetBounds().Width,
				Y = geometry.GetBounds().Height,
			},
			Parent = if geometry.GetParent then geometry.GetParent() else nil,
			IsA = function(_s: any, className: string): boolean
				return className == "GuiObject"
			end,
		}

		local p = router.Pressable({
			Disabled = getDisabled,
			Priority = opts.Priority,
			OnActivated = opts.OnActivated or opts.OnClick,
			OnHoverChanged = function(h: boolean)
				isHovered = h
				if opts.OnHoverChanged then
					opts.OnHoverChanged(h)
				end
			end,
			OnPressedChanged = function(pr: boolean)
				isPressed = pr
				if opts.OnPressedChanged then
					opts.OnPressedChanged(pr)
				end
			end,
		})

		p.Bind(fakeSurface)
		currentRegistration = p

		return function()
			p.Destroy()
			if currentRegistration == p then
				currentRegistration = nil
			end
		end
	end

	function self.Destroy()
		if currentRegistration then
			currentRegistration.Destroy()
			currentRegistration = nil
		end
	end

	return self
end

return {
	createPressable = createPressable,
}
