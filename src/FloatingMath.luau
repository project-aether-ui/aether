--!strict
--[=[
	FloatingMath — Pure spatial positioning engine for floating UI (popups, dropdowns, tooltips).
	Part of Aether.Engine (Layer 2.5/3 Headless Positioning).
	
	Features:
	- 12 cardinal placements (top, bottom, left, right + start/end variants).
	- Intelligent Auto-Flip (flips bottom <-> top, left <-> right when colliding with viewport edges).
	- Viewport Boundary Clamping & Padding.
	- 100% Pure mathematical calculation (Zero Roblox Instance dependencies, Lune testable).
]=]

export type Rect = {
	X: number,
	Y: number,
	Width: number,
	Height: number,
}

export type Side = "top" | "bottom" | "left" | "right"
export type Alignment = "start" | "center" | "end"

export type Placement =
	| "top"
	| "top-start"
	| "top-end"
	| "bottom"
	| "bottom-start"
	| "bottom-end"
	| "left"
	| "left-start"
	| "left-end"
	| "right"
	| "right-start"
	| "right-end"

export type ComputeOptions = {
	Offset: number?,
	CrossOffset: number?,
	AutoFlip: boolean?,
	ClampToViewport: boolean?,
	ViewportPadding: number?,
}

export type ComputeResult = {
	X: number,
	Y: number,
	Placement: Placement,
	Side: Side,
	Alignment: Alignment,
	DidFlip: boolean,
}

local FloatingMath = {}

local function parsePlacement(placement: Placement): (Side, Alignment)
	local parts = string.split(placement, "-")
	local side = parts[1] :: Side
	local alignment: Alignment = if parts[2] then (parts[2] :: Alignment) else "center"
	return side, alignment
end

local function formatPlacement(side: Side, alignment: Alignment): Placement
	if alignment == "center" then
		return side :: Placement
	end
	return `{side}-{alignment}` :: Placement
end

function FloatingMath.ComputePosition(
	anchor: Rect,
	floating: Rect,
	viewport: Rect?,
	options: ComputeOptions?
): ComputeResult
	local opts = options or {}
	local offset = opts.Offset or 4
	local crossOffset = opts.CrossOffset or 0
	local autoFlip = if opts.AutoFlip ~= nil then opts.AutoFlip else true
	local clamp = if opts.ClampToViewport ~= nil then opts.ClampToViewport else true
	local padding = opts.ViewportPadding or 8

	local initialPlacement: Placement = (opts :: any).Placement or "bottom-start"
	local currentSide, currentAlignment = parsePlacement(initialPlacement)
	local didFlip = false

	-- 1. Compute Primary Side (with auto-flip if requested)
	if autoFlip and viewport then
		if currentSide == "bottom" then
			local bottomEdge = anchor.Y + anchor.Height + offset + floating.Height
			local viewportBottom = viewport.Y + viewport.Height - padding
			if bottomEdge > viewportBottom then
				local topEdge = anchor.Y - offset - floating.Height
				local viewportTop = viewport.Y + padding
				-- Flip to top if top has enough room or more room than bottom
				if topEdge >= viewportTop or (anchor.Y - viewport.Y) > (viewportBottom - (anchor.Y + anchor.Height)) then
					currentSide = "top"
					didFlip = true
				end
			end
		elseif currentSide == "top" then
			local topEdge = anchor.Y - offset - floating.Height
			local viewportTop = viewport.Y + padding
			if topEdge < viewportTop then
				local bottomEdge = anchor.Y + anchor.Height + offset + floating.Height
				local viewportBottom = viewport.Y + viewport.Height - padding
				if bottomEdge <= viewportBottom or (viewportBottom - (anchor.Y + anchor.Height)) > (anchor.Y - viewport.Y) then
					currentSide = "bottom"
					didFlip = true
				end
			end
		elseif currentSide == "right" then
			local rightEdge = anchor.X + anchor.Width + offset + floating.Width
			local viewportRight = viewport.X + viewport.Width - padding
			if rightEdge > viewportRight then
				local leftEdge = anchor.X - offset - floating.Width
				local viewportLeft = viewport.X + padding
				if leftEdge >= viewportLeft or (anchor.X - viewport.X) > (viewportRight - (anchor.X + anchor.Width)) then
					currentSide = "left"
					didFlip = true
				end
			end
		elseif currentSide == "left" then
			local leftEdge = anchor.X - offset - floating.Width
			local viewportLeft = viewport.X + padding
			if leftEdge < viewportLeft then
				local rightEdge = anchor.X + anchor.Width + offset + floating.Width
				local viewportRight = viewport.X + viewport.Width - padding
				if rightEdge <= viewportRight or (viewportRight - (anchor.X + anchor.Width)) > (anchor.X - viewport.X) then
					currentSide = "right"
					didFlip = true
				end
			end
		end
	end

	-- 2. Compute Raw Coordinates based on resolved side and alignment
	local rawX = 0
	local rawY = 0

	if currentSide == "bottom" then
		rawY = anchor.Y + anchor.Height + offset
	elseif currentSide == "top" then
		rawY = anchor.Y - floating.Height - offset
	elseif currentSide == "right" then
		rawX = anchor.X + anchor.Width + offset
	elseif currentSide == "left" then
		rawX = anchor.X - floating.Width - offset
	end

	-- Cross-axis positioning
	if currentSide == "bottom" or currentSide == "top" then
		if currentAlignment == "start" then
			rawX = anchor.X + crossOffset
		elseif currentAlignment == "center" then
			rawX = anchor.X + (anchor.Width - floating.Width) / 2 + crossOffset
		elseif currentAlignment == "end" then
			rawX = anchor.X + anchor.Width - floating.Width - crossOffset
		end
	else -- "left" or "right"
		if currentAlignment == "start" then
			rawY = anchor.Y + crossOffset
		elseif currentAlignment == "center" then
			rawY = anchor.Y + (anchor.Height - floating.Height) / 2 + crossOffset
		elseif currentAlignment == "end" then
			rawY = anchor.Y + anchor.Height - floating.Height - crossOffset
		end
	end

	-- 3. Viewport Boundary Clamping
	local finalX = rawX
	local finalY = rawY

	if clamp and viewport then
		local minX = viewport.X + padding
		local maxX = viewport.X + viewport.Width - floating.Width - padding
		local minY = viewport.Y + padding
		local maxY = viewport.Y + viewport.Height - floating.Height - padding

		if maxX >= minX then
			finalX = math.clamp(finalX, minX, maxX)
		else
			finalX = minX
		end

		if maxY >= minY then
			finalY = math.clamp(finalY, minY, maxY)
		else
			finalY = minY
		end
	end

	return {
		X = finalX,
		Y = finalY,
		Placement = formatPlacement(currentSide, currentAlignment),
		Side = currentSide,
		Alignment = currentAlignment,
		DidFlip = didFlip,
	}
end

return FloatingMath
