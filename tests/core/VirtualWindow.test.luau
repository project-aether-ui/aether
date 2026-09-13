--!strict
--!tier math
--[=[
	spektr/aether · core/VirtualWindow (milestone 7 step F).

	NO VIDE, NO HOST, NO LIST. Windowing is arithmetic, and this file asks it
	directly instead of rendering rows and counting what appeared.

	THE CASES THAT MATTER are the ones a wrong implementation still looks right
	for: an offset that lands mid-row must include that row, a negative offset
	must not produce a negative index, and an empty list must return a range that
	iterates zero times rather than one.
]=]
local T = require("@testkit")
local VirtualWindow = require("../../src/core/VirtualWindow")

local function testItCoversTheViewport()
	local w = VirtualWindow.uniform(1000, 20)
	local first, last = w.Range(0, 100, 0)

	assert(first == 1, `the first row should be 1 at offset 0, got {first}`)
	--- Five rows of 20 fill 100, and `ceil` gives the fifth rather than a sixth.
	assert(last == 5, `a 100 tall viewport over 20 tall rows shows 5, got {last}`)
end

local function testAnOffsetMidRowStillIncludesThatRow()
	local w = VirtualWindow.uniform(1000, 20)
	--- Scrolled ten pixels into row 1: it is half visible and must be mounted.
	local first = w.Range(10, 100, 0)

	assert(first == 1, `a partly scrolled row must stay in the window, got {first}`)
end

local function testOverscanWidensBothEnds()
	local w = VirtualWindow.uniform(1000, 20)
	local firstNone, lastNone = w.Range(200, 100, 0)
	local firstTwo, lastTwo = w.Range(200, 100, 2)

	assert(firstTwo == firstNone - 2, `overscan should widen the top, got {firstTwo} against {firstNone}`)
	assert(lastTwo == lastNone + 2, `overscan should widen the bottom, got {lastTwo} against {lastNone}`)
end

local function testItClampsAtBothEnds()
	local w = VirtualWindow.uniform(10, 20)

	--- An elastic scroll overshoots past the top and reports a negative offset.
	--- `floor` of a negative over a size is a negative index, which indexes
	--- nothing and mounts nothing.
	local first = w.Range(-500, 100, 2)
	assert(first == 1, `a negative offset must clamp to the first row, got {first}`)

	local _, last = w.Range(10000, 100, 2)
	assert(last == 10, `past the end must clamp to the last row, got {last}`)
end

local function testAnEmptyListIteratesZeroTimes()
	local w = VirtualWindow.uniform(0, 20)
	local first, last = w.Range(0, 100, 2)

	assert(first == 1 and last == 0,
		`an empty list should return 1, 0 so a numeric for runs zero times; got {first}, {last}`)

	local ran = 0
	for _ = first, last do
		ran += 1
	end
	assert(ran == 0, `the returned range iterated {ran} time(s) over an empty list`)
end

local function testGeometryAgreesWithTheRange()
	local w = VirtualWindow.uniform(50, 24)

	assert(w.Count() == 50, "count")
	assert(w.TotalSize() == 50 * 24, `total size should be count times item size, got {w.TotalSize()}`)
	assert(w.OffsetOf(1) == 0, "the first row starts at zero")
	assert(w.OffsetOf(3) == 48, `the third row starts after two, got {w.OffsetOf(3)}`)
	assert(w.SizeOf(7) == 24, "a uniform window reports one size")
end

local function testTheCountCanChange()
	local w = VirtualWindow.uniform(4, 10)
	local _, lastBefore = w.Range(0, 1000, 0)
	assert(lastBefore == 4, `precondition, got {lastBefore}`)

	w.SetCount(9)
	local _, lastAfter = w.Range(0, 1000, 0)
	assert(lastAfter == 9, `the window should follow the list growing, got {lastAfter}`)

	w.SetCount(-3)
	assert(w.Count() == 0, "a negative count is empty rather than negative")
end

T.test("it covers the viewport", testItCoversTheViewport, "math")
T.test("an offset mid row still includes that row", testAnOffsetMidRowStillIncludesThatRow, "math")
T.test("overscan widens both ends", testOverscanWidensBothEnds, "math")
T.test("it clamps at both ends", testItClampsAtBothEnds, "math")
T.test("an empty list iterates zero times", testAnEmptyListIteratesZeroTimes, "math")
T.test("geometry agrees with the range", testGeometryAgreesWithTheRange, "math")
T.test("the count can change", testTheCountCanChange, "math")

return T.run("VirtualWindow")
