--!strict
--!tier math
--[[
	ItemIndex suite.

	This module is pure arithmetic over a list of numbers, which makes it the one
	part of virtualisation that headless testing can cover COMPLETELY — no
	Instances, no engine, no stand-ins that accept anything. Every bug a virtual
	list has in the field is in here: wrong range at an edge, drift after
	measurement, cached sizes belonging to the wrong item after a reorder.
]]

local ItemIndex = require("../src/ItemIndex")

local function run()
	-- ── 1. Heterogeneous sizes, which is the entire point ────────────────────
	print("[TEST] ItemIndex: items of different declared sizes...")
	do
		-- A heading, two cards, a row. Deliberately unequal: a uniform-size
		-- implementation passes a same-size test and fails every real menu.
		local items = { { Size = 40 }, { Size = 150 }, { Size = 150 }, { Size = 20 } }
		local idx = ItemIndex.new(function() return items end, 999)

		assert(idx.Count() == 4, "counts items")
		assert(idx.TotalSize() == 360, `total is the SUM, got {idx.TotalSize()}`)
		assert(idx.OffsetOf(1) == 0, "first item starts at 0")
		assert(idx.OffsetOf(2) == 40, "second starts after the heading")
		assert(idx.OffsetOf(3) == 190, "third accumulates")
		assert(idx.OffsetOf(4) == 340, "fourth accumulates")
		-- The estimate must not leak in when every size is declared.
		assert(idx.SizeOf(2) == 150, "declared size wins over the estimate")
	end
	print("  ✓ offsets accumulate per-item sizes, not index * constant")

	-- ── 2. Range ─────────────────────────────────────────────────────────────
	print("[TEST] ItemIndex: the visible range...")
	do
		local items = {}
		for _ = 1, 100 do
			table.insert(items, { Size = 20 })
		end
		local idx = ItemIndex.new(function() return items end, 20)

		local first, last = idx.Range(0, 100, 0)
		assert(first == 1, `at the top the first item is 1, got {first}`)
		assert(last == 5, `a 100px viewport over 20px rows shows 5, got {last}`)

		-- Scrolled to exactly a boundary.
		first, last = idx.Range(200, 100, 0)
		assert(first == 11, `offset 200 starts at item 11, got {first}`)
		assert(last == 15, `and ends at 15, got {last}`)

		-- Overscan widens both sides and CLAMPS rather than going out of bounds —
		-- an unclamped overscan indexes nil and renders nothing at the edges,
		-- which looks like the list ending early.
		first, last = idx.Range(0, 100, 3)
		assert(first == 1, `overscan clamps at the start, got {first}`)
		assert(last == 8, `overscan extends the end, got {last}`)

		first, last = idx.Range(1900, 100, 3)
		assert(last == 100, `overscan clamps at the end, got {last}`)

		-- The cost claim: range is bounded by what FITS, not by list length.
		local big = {}
		for _ = 1, 10000 do
			table.insert(big, { Size = 20 })
		end
		local bigIdx = ItemIndex.new(function() return big end, 20)
		local bf, bl = bigIdx.Range(100000, 100, 2)
		assert(bl - bf <= 10, `10,000 items still yields a small window, got {bl - bf + 1}`)
	end
	print("  ✓ range is bounded by what fits, and clamps at both edges")

	-- ── 3. Estimation and measurement ────────────────────────────────────────
	print("[TEST] ItemIndex: estimated items get corrected by measurement...")
	do
		local items = { { Size = 40 }, {}, {}, { Size = 40 } } -- two unknown
		local idx = ItemIndex.new(function() return items end, 100)

		assert(idx.SizeOf(2) == 100, "an unknown item uses the estimate")
		assert(idx.TotalSize() == 280, `estimate feeds the total, got {idx.TotalSize()}`)

		-- Item 2 turns out to be 250, not 100.
		idx.Measure(2, 250, 0)
		assert(idx.SizeOf(2) == 250, "measurement replaces the estimate")
		assert(idx.TotalSize() == 430, `and the total follows, got {idx.TotalSize()}`)
		assert(idx.OffsetOf(3) == 290, `as do the offsets below it, got {idx.OffsetOf(3)}`)
		assert(idx.OffsetOf(1) == 0, "offsets ABOVE it are untouched")

		-- Re-measuring the same value is a no-op rather than repeated drift.
		local again = idx.Measure(2, 250, 0)
		assert(again == 0, "re-measuring the same size shifts nothing")
		assert(idx.TotalSize() == 430, "and does not double-count")
	end
	print("  ✓ measurement replaces the estimate and only moves what is below it")

	-- ── 3b. A DECLARED size is authoritative ─────────────────────────────────
	print("[TEST] ItemIndex: measurement must not override a declared size...")
	do
		-- es9, section 12: "the virtual scrolling frame scrolls roughly 1 row
		-- further than the FromScrollingFrame one every time."
		--
		-- The demo declares Size = 22 per row — a 20px label plus a 2px gap,
		-- matching the other pane's UIListLayout padding — and renders a 20px
		-- label. Measurement then rewrote 22 to 20, so rows got shorter in the
		-- index and MORE of them fitted above the same offset: at 160px, 20px rows
		-- put row 9 at the top where 22px rows leave row 8 peeking. Exactly the
		-- reported off-by-one.
		--
		-- Declared means the caller knows. It is the documented contract at the
		-- top of this module, and the implementation contradicted it. Anyone who
		-- wants a size measured omits it.
		local items = { { Size = 22 }, { Size = 22 }, {} }
		local idx = ItemIndex.new(function() return items end, 50)

		local shift = idx.Measure(1, 20, 999)
		assert(idx.SizeOf(1) == 22, `a declared size survives measurement, got {idx.SizeOf(1)}`)
		assert(shift == 0, `and reports no shift, got {shift}`)
		assert(idx.OffsetOf(2) == 22, `so offsets are unchanged, got {idx.OffsetOf(2)}`)

		-- The undeclared one is still measured, which is the whole point of the
		-- split: this must not become "never measure anything".
		idx.Measure(3, 80, 0)
		assert(idx.SizeOf(3) == 80, `an UNdeclared size is still measured, got {idx.SizeOf(3)}`)
		assert(idx.TotalSize() == 124, `total = 22 + 22 + 80, got {idx.TotalSize()}`)
	end
	print("  ✓ declared wins over measured; undeclared is still measured")

	-- ── 4. Scroll compensation — the bug this exists to prevent ──────────────
	print("[TEST] ItemIndex: measuring above the viewport reports the shift...")
	do
		local items = {}
		for _ = 1, 50 do
			table.insert(items, {})
		end
		local idx = ItemIndex.new(function() return items end, 100)

		-- Viewing from offset 1000, i.e. around item 11.
		-- Item 3 is ABOVE that. It turns out 60px taller than estimated, so
		-- everything the user is looking at slides down by 60 — the classic
		-- twitch. The caller adds this to the scroll offset to cancel it.
		local shift = idx.Measure(3, 160, 1000)
		assert(shift == 60, `a taller item above the viewport shifts it, got {shift}`)

		-- Item 40 is BELOW the viewport. It grows downward, where nothing the
		-- user can see moves, so no compensation is owed. Returning a shift here
		-- would scroll the view for no reason.
		local none = idx.Measure(40, 300, 1000)
		assert(none == 0, `an item below the viewport shifts nothing, got {none}`)

		-- Shrinking above the viewport shifts the other way.
		local up = idx.Measure(4, 40, 1000)
		assert(up == -60, `a shorter item above the viewport shifts back, got {up}`)
	end
	print("  ✓ compensation is owed only for content above the viewport, with sign")

	-- ── 5. Identity, not index ───────────────────────────────────────────────
	print("[TEST] ItemIndex: measurements survive a reorder...")
	do
		-- Keying the cache by INDEX is the bug that makes a virtual list look
		-- correct until the list changes: insert one row at the top and every
		-- remembered height belongs to the wrong item.
		local a, b = { Name = "a" }, { Name = "b" }
		local items = { a, b }
		local idx = ItemIndex.new(function() return items end, 100)

		idx.Measure(1, 30, 0) -- a is 30
		idx.Measure(2, 70, 0) -- b is 70
		assert(idx.TotalSize() == 100, `sanity, got {idx.TotalSize()}`)

		-- Insert at the FRONT, so both existing items shift index.
		local c = { Name = "c" }
		items = { c, a, b }
		idx.Refresh()

		assert(idx.SizeOf(2) == 30, `a keeps its measurement at its new index, got {idx.SizeOf(2)}`)
		assert(idx.SizeOf(3) == 70, `so does b, got {idx.SizeOf(3)}`)
		assert(idx.SizeOf(1) == 100, "the new item falls back to the estimate")
		assert(idx.TotalSize() == 200, `total recomputes, got {idx.TotalSize()}`)
	end
	print("  ✓ sizes are remembered per item, not per position")

	-- ── 6. Degenerate cases ──────────────────────────────────────────────────
	print("[TEST] ItemIndex: empty and single-item lists...")
	do
		local empty = ItemIndex.new(function() return {} end, 50)
		assert(empty.Count() == 0 and empty.TotalSize() == 0, "empty list is empty")
		local f, l = empty.Range(0, 500, 2)
		assert(f > l, `an empty list yields an EMPTY range, got {f}..{l}`)

		local one = ItemIndex.new(function() return { { Size = 10 } } end, 50)
		local f2, l2 = one.Range(0, 500, 5)
		assert(f2 == 1 and l2 == 1, `one item, viewport far larger, got {f2}..{l2}`)

		-- Scrolled past the end: still a valid range rather than an error.
		local f3, l3 = one.Range(9999, 500, 0)
		assert(f3 >= 1 and l3 <= 1, `past the end stays in bounds, got {f3}..{l3}`)
	end
	print("  ✓ empty, single-item and scrolled-past-the-end stay in bounds")

	print("[TEST] ItemIndex tests passed successfully!")
end

-- ms-44: migrated onto testkit. This suite had no harness — bare asserts inside named
-- functions, invoked at the bottom of the file. That is the ms-43 M30 shape: delete an
-- invocation and the file still exits 0 and still reads as coverage. Registered tests
-- make that a VACUOUS failure instead, and give each one a name, a time and a tier in
-- the ##testkit JSON.
local T = require("@testkit")
T.test("ItemIndex", run, "math")

return T.run("ItemIndex")
