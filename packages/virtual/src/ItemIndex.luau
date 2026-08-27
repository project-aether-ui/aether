--!strict
--[[
	ItemIndex — maps scroll offset to item range, for items of DIFFERENT sizes.

	WHY THIS SHAPE (ms-43 M70)
	The obvious virtual list takes one `ItemSize` and multiplies. es9 killed that
	design before it was written:

	    "I can imagine cases where it's not as simple, or there are mixed item
	     types and sizes in the same scrollingframe? this would be a good
	     foundation for a functioning demo, but far too brittle."

	Correct, and the showcase is its own counter-example: section 11 alone mixes a
	heading, a caption, a button row and a grid of 150px swatches. A uniform
	ItemSize would make this useless on precisely the surfaces worth virtualising.

	So size is PER ITEM, and comes from one of three places:

	  * DECLARED — the caller knows it. Exact, free, no measurement.
	  * ESTIMATED — the caller does not know it yet. Used until the item mounts.
	  * MEASURED — what it turned out to be. Replaces the estimate.

	THE HARD PART IS NOT THE LOOKUP, IT IS THE CORRECTION.
	When a measurement lands for an item ABOVE the current scroll offset, every
	offset below it shifts. Do nothing and the content visibly jumps under the
	user, which is the classic virtual-list bug: scroll down through estimated
	content and it twitches as each row is measured. `Measure` returns the shift
	so the caller can add it to the scroll offset and hold the view still.

	COMPLEXITY. Prefix sums in a flat array: O(n) to rebuild, O(log n) to query.
	A Fenwick tree would make updates O(log n) too, and is NOT used, because the
	rebuild only happens when the item list itself changes and the constant
	factor here is a single pass over an array of numbers. Revisit if a list ever
	changes shape every frame; nothing in this repo does.
]]

export type Item = {
	--- Extent along the scroll axis. Nil means "not known yet" — the index uses
	--- `Estimate` until a measurement replaces it.
	Size: number?,
	--- Anything the renderer needs. Never read here.
	[any]: any,
}

export type ItemIndex = {
	--- Total extent of all items.
	TotalSize: () -> number,
	--- Item count.
	Count: () -> number,
	--- Offset of an item's leading edge.
	OffsetOf: (index: number) -> number,
	--- Size currently assumed for an item.
	SizeOf: (index: number) -> number,
	--- Which items intersect `[offset, offset + extent)`, widened by `overscan`
	--- items on each side. Returns first and last inclusive; first > last means
	--- nothing is visible.
	Range: (offset: number, extent: number, overscan: number) -> (number, number),
	--- Record an item's real size. Returns how much the content ABOVE `offset`
	--- shifted, which the caller adds to the scroll offset to keep the view
	--- still. Zero when the item is at or below the current offset.
	Measure: (index: number, size: number, offset: number) -> number,
	--- Re-read the item list. Measurements are kept per identity, not per index,
	--- so inserting at the top does not invalidate what is already known.
	Refresh: () -> (),
}

local ItemIndex = {}

--- `identify` exists because measurements must survive reordering.
---
--- Keying a measurement cache by INDEX is the bug that makes a virtual list
--- appear to work and then misbehave the moment the list changes: insert one row
--- at the top and every cached height silently belongs to the wrong item. The
--- default identity is the item table itself, which is stable for as long as the
--- caller keeps it.
function ItemIndex.new(
	getItems: () -> { Item },
	estimate: number,
	identify: ((item: Item, index: number) -> any)?
): ItemIndex
	local items: { Item } = {}
	--- identity -> measured size
	local measured: { [any]: number } = {}
	--- prefix[i] is the offset of item i's leading edge; prefix[n+1] is the total.
	local prefix: { number } = { 0 }

	local function idOf(item: Item, index: number): any
		return if identify then identify(item, index) else item
	end

	local function sizeAt(index: number): number
		local item = items[index]
		if not item then
			return 0
		end
		-- DECLARED BEATS MEASURED. The doc at the top of this module has always
		-- said a declared size is exact and needs no measurement; the code said
		-- the opposite, and measurement silently overwrote the caller's answer.
		--
		-- es9 found it as a one-row divergence between the two section 12 panes:
		-- items declared 22 (a 20px row plus a 2px gap, matching the other pane's
		-- layout padding) and rendered a 20px label, so the index was rewritten to
		-- 20, rows got shorter, and more of them fitted above the same offset.
		--
		-- Anyone who wants a size measured omits it. A declaration that gets
		-- overwritten is not a declaration.
		if item.Size then
			return item.Size
		end
		local m = measured[idOf(item, index)]
		if m then
			return m
		end
		return estimate
	end

	local function rebuild()
		items = getItems()
		prefix = table.create(#items + 1)
		prefix[1] = 0
		for i = 1, #items do
			prefix[i + 1] = prefix[i] + sizeAt(i)
		end
	end

	rebuild()

	--- Largest i with prefix[i] <= offset. Binary search rather than a scan: at
	--- 10,000 items a linear probe every frame is the cost this whole exercise
	--- exists to avoid.
	local function indexAt(offset: number): number
		local lo, hi = 1, #items
		if hi == 0 then
			return 1
		end
		while lo < hi do
			local mid = (lo + hi + 1) // 2
			if prefix[mid] <= offset then
				lo = mid
			else
				hi = mid - 1
			end
		end
		return lo
	end

	local self: ItemIndex
	self = {
		TotalSize = function(): number
			return prefix[#items + 1] or 0
		end,
		Count = function(): number
			return #items
		end,
		OffsetOf = function(index: number): number
			return prefix[math.clamp(index, 1, #items + 1)] or 0
		end,
		SizeOf = sizeAt,

		Range = function(offset: number, extent: number, overscan: number): (number, number)
			local n = #items
			if n == 0 then
				return 1, 0
			end
			local first = indexAt(math.max(0, offset))
			local last = first
			-- Walk forward until the viewport is covered. Bounded by what FITS,
			-- not by the list length, so a 10,000-item list costs the same as a
			-- 40-item one.
			local edge = offset + extent
			while last < n and prefix[last + 1] < edge do
				last += 1
			end
			return math.max(1, first - overscan), math.min(n, last + overscan)
		end,

		Measure = function(index: number, size: number, offset: number): number
			local item = items[index]
			if not item or size <= 0 then
				return 0
			end
			-- Nothing to learn: the caller already told us, and recording it would
			-- leave a stale entry to surface if the declaration were ever removed.
			if item.Size then
				return 0
			end
			local id = idOf(item, index)
			local before = sizeAt(index)
			if math.abs(before - size) < 0.5 then
				return 0
			end
			measured[id] = size

			local delta = size - before
			-- Only content ABOVE the viewport's top edge moves the view. An item
			-- at or below it grows downward, which the user cannot see happen.
			local leadingEdge = prefix[index] or 0
			local shift = if leadingEdge < offset then delta else 0

			-- Patch the tail rather than rebuilding: the sizes of items 1..index
			-- have not changed, and this runs once per item as it mounts.
			for i = index + 1, #items + 1 do
				prefix[i] += delta
			end
			return shift
		end,

		Refresh = rebuild,
	}
	return self
end

return ItemIndex
