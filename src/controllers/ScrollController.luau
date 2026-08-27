--!strict
--[[
	Aether.Controllers.ScrollController — Pure 1D/2D Scroll State Machine & Mathematics

	Layer 1 in the Aether universal architecture:
	Zero engine dependency, zero reactive framework dependency.
	Can be instantiated headlessly in Lune, CLI tools, or browser WASM.
]]

export type ScrollOptions = {
	InitialOffset: number?,
	ViewportSize: number?,
	ViewportHeight: number?,
	ContentSize: number?,
	ContentHeight: number?,
	ItemCount: number?,
	ItemHeight: number?,
	StepSize: number?,
	PageStepRatio: number?,
	MinThumbRatio: number?,
}

export type ScrollController = {
	GetOffset: () -> number,
	GetMaxScroll: () -> number,
	GetViewportSize: () -> number,
	GetContentSize: () -> number,
	GetThumbRatio: () -> number,
	GetThumbOffset: (trackLength: number) -> number,
	GetThumbSize: (trackLength: number) -> number,
	ScrollTo: (target: number) -> number,
	ScrollBy: (delta: number) -> number,
	PageUp: () -> number,
	PageDown: () -> number,
	ScrollToStart: () -> number,
	ScrollToEnd: () -> number,
	SetDimensions: (viewportSize: number, contentSize: number) -> (),
	Subscribe: (listener: (number) -> ()) -> () -> (),
}

local ScrollController = {}

--- Computes the ratio of the thumb size relative to the track (0 to 1).
function ScrollController.computeThumbRatio(viewportSize: number, contentSize: number, minRatio: number?): number
	local min = minRatio or 0.1
	if contentSize <= 0 or viewportSize <= 0 then
		return 1
	end
	if viewportSize >= contentSize then
		return 1
	end
	local ratio = viewportSize / contentSize
	if ratio < min then
		return min
	elseif ratio > 1 then
		return 1
	end
	return ratio
end

--- Computes the offset of the thumb on the track in pixels.
function ScrollController.computeThumbOffset(
	scrollOffset: number,
	maxScroll: number,
	trackLength: number,
	thumbLength: number
): number
	if maxScroll <= 0 or trackLength <= 0 or thumbLength >= trackLength then
		return 0
	end
	local availableTrack = trackLength - thumbLength
	local progress = scrollOffset / maxScroll
	if progress < 0 then
		progress = 0
	elseif progress > 1 then
		progress = 1
	end
	return progress * availableTrack
end

--- Computes the scroll offset given a dragged thumb position on the track.
function ScrollController.computeScrollFromThumb(
	thumbOffset: number,
	trackLength: number,
	thumbLength: number,
	maxScroll: number
): number
	if maxScroll <= 0 or trackLength <= 0 or thumbLength >= trackLength then
		return 0
	end
	local availableTrack = trackLength - thumbLength
	local progress = thumbOffset / availableTrack
	if progress < 0 then
		progress = 0
	elseif progress > 1 then
		progress = 1
	end
	return progress * maxScroll
end

--- Clamps a scroll offset between 0 and maxScroll.
function ScrollController.clampOffset(offset: number, maxScroll: number): number
	if maxScroll <= 0 or offset <= 0 then
		return 0
	end
	if offset > maxScroll then
		return maxScroll
	end
	return offset
end

--- Creates a new pure ScrollController instance.
function ScrollController.new(options: ScrollOptions?): ScrollController
	local opts = (options or {}) :: any
	local viewportSize = opts.ViewportSize or opts.ViewportHeight or 0
	local contentSize = opts.ContentSize or opts.ContentHeight or (if opts.ItemCount and opts.ItemHeight then opts.ItemCount * opts.ItemHeight else 0)
	local stepSize = opts.StepSize or 40
	local pageStepRatio = opts.PageStepRatio or 0.85
	local minThumbRatio = opts.MinThumbRatio or 0.1

	local offset = opts.InitialOffset or 0
	local listeners: { (number) -> () } = {}

	local function getMaxScroll(): number
		local max = contentSize - viewportSize
		return if max > 0 then max else 0
	end

	offset = ScrollController.clampOffset(offset, getMaxScroll())

	local function notify()
		for _, listener in ipairs(listeners) do
			listener(offset)
		end
	end

	local function scrollTo(target: number): number
		local clamped = ScrollController.clampOffset(target, getMaxScroll())
		if clamped ~= offset then
			offset = clamped
			notify()
		end
		return offset
	end

	local function scrollBy(delta: number): number
		return scrollTo(offset + delta)
	end

	local controller: ScrollController = {
		GetOffset = function(): number
			return offset
		end,

		GetMaxScroll = function(): number
			return getMaxScroll()
		end,

		GetViewportSize = function(): number
			return viewportSize
		end,

		GetContentSize = function(): number
			return contentSize
		end,

		GetThumbRatio = function(): number
			return ScrollController.computeThumbRatio(viewportSize, contentSize, minThumbRatio)
		end,

		GetThumbSize = function(trackLength: number): number
			local ratio = ScrollController.computeThumbRatio(viewportSize, contentSize, minThumbRatio)
			return math.max(ratio * trackLength, minThumbRatio * trackLength)
		end,

		GetThumbOffset = function(trackLength: number): number
			local thumbSize = math.max(
				ScrollController.computeThumbRatio(viewportSize, contentSize, minThumbRatio) * trackLength,
				minThumbRatio * trackLength
			)
			return ScrollController.computeThumbOffset(offset, getMaxScroll(), trackLength, thumbSize)
		end,

		ScrollTo = scrollTo,
		ScrollBy = scrollBy,

		PageUp = function(): number
			local pageDelta = viewportSize * pageStepRatio
			if pageDelta <= 0 then
				pageDelta = stepSize * 4
			end
			return scrollBy(-pageDelta)
		end,

		PageDown = function(): number
			local pageDelta = viewportSize * pageStepRatio
			if pageDelta <= 0 then
				pageDelta = stepSize * 4
			end
			return scrollBy(pageDelta)
		end,

		ScrollToStart = function(): number
			return scrollTo(0)
		end,

		ScrollToEnd = function(): number
			return scrollTo(getMaxScroll())
		end,

		SetDimensions = function(newViewportSize: number, newContentSize: number)
			local newVp = math.max(newViewportSize, 0)
			local newCs = math.max(newContentSize, 0)
			if newVp == viewportSize and newCs == contentSize then
				return
			end
			viewportSize = newVp
			contentSize = newCs
			local max = getMaxScroll()
			if offset > max then
				offset = max
			end
			notify()
		end,

		Subscribe = function(listener: (number) -> ()): () -> ()
			table.insert(listeners, listener)
			return function()
				local index = table.find(listeners, listener)
				if index then
					table.remove(listeners, index)
				end
			end
		end,
	}

	return controller
end

return ScrollController
