--!strict
--[[
	Aether · core/VirtualWindow -- which rows of a list are worth mounting?

	Layer 1. Arithmetic over a scroll offset and a viewport, with no reactive
	library, no engine types and nothing to mount.

	WHY IT IS SEPARATE (milestone 7 step F)
	This lived inside `primitives/VirtualList` as a closure over the item list,
	which meant the only way to ask whether the window was right was to render a
	list and count what appeared. Windowing is the arithmetic most prone to being
	off by one in a way nobody notices: a row missing at the top of a fast scroll
	reads as a rendering stutter rather than as a wrong answer.

	    local w = VirtualWindow.uniform(1000, 24)
	    local first, last = w.Range(0, 100, 2)   -- offset, viewport, overscan

	THE EMPTY LIST RETURNS 1, 0, which is an empty range under Luau's numeric for
	rather than a special case every caller has to check. `for i = first, last`
	over 1, 0 runs zero times.
]]

export type Window = {
	Count: () -> number,
	TotalSize: () -> number,
	OffsetOf: (index: number) -> number,
	SizeOf: (index: number) -> number,
	Range: (offset: number, extent: number, overscan: number) -> (number, number),
	SetCount: (count: number) -> (),
}

--- Every row the same height, which is what a list knows before it has measured
--- anything. A list that later measures its rows replaces this with something
--- that records them; the contract above is what both answer.
local function uniform(count: number, itemSize: number): Window
	local n = math.max(count, 0)
	local size = if itemSize > 0 then itemSize else 1

	local self = {} :: Window

	function self.Count(): number
		return n
	end

	function self.TotalSize(): number
		return n * size
	end

	function self.OffsetOf(index: number): number
		return (index - 1) * size
	end

	function self.SizeOf(_index: number): number
		return size
	end

	function self.Range(offset: number, extent: number, overscan: number): (number, number)
		if n == 0 then
			return 1, 0
		end
		--- CLAMPED AT BOTH ENDS, because a negative offset happens: an elastic
		--- scroll overshoots past the top and reports it, and `floor` of a
		--- negative divided by a size is a negative index.
		local first = math.clamp(math.floor(offset / size) + 1 - overscan, 1, n)
		local last = math.clamp(math.ceil((offset + extent) / size) + overscan, 1, n)
		return first, last
	end

	function self.SetCount(count: number)
		n = math.max(count, 0)
	end

	return self
end

return { uniform = uniform }
