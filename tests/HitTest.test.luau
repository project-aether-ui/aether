--!strict
--!tier math
--[[
	HitTest suite — rounded-corner hit rejection (ms-43 M103).

	Self-executing: the runner judges by EXIT CODE, so a suite that only RETURNS
	a function passes without running an assertion.
]]

--- The value vocabulary, from the HOST (ms-52 M6).
---
--- This was a hand-written block per suite -- `local rbx = require("@lune/roblox")`
--- then five to nine global assignments -- which is the copy-per-file the repo
--- already carried, and which pinned every suite to Lune. On zune `@lune` is not
--- a valid alias, so these files could not load at all.
---
--- `InstallVocabulary` is the one place that answers this. It still resolves to
--- Lune's real Roblox types where they exist, so nothing about running under Lune
--- changes; on a runtime without them it installs the pure-Luau vocabulary.
require("../../../framework/Aether/src").Host.detect().InstallVocabulary()

local HitTest = require("../src/HitTest")

--- A stand-in GuiObject. Only the four members the rounded test reads.
local function fakeGui(x: number, y: number, w: number, h: number, radius: UDim?): any
	local corner = if radius then { ClassName = "UICorner", CornerRadius = radius } else nil
	return {
		AbsolutePosition = Vector2.new(x, y),
		AbsoluteSize = Vector2.new(w, h),
		FindFirstChildOfClass = function(_self: any, class: string): any
			return if class == "UICorner" then corner else nil
		end,
	}
end

local function run()
	print("[TEST] HitTest: a square element claims its whole rect...")
	do
		local plain = fakeGui(0, 0, 100, 40)
		assert(HitTest.RoundedContains(plain, 0, 0) == true, "top-left corner of a square element")
		assert(HitTest.RoundedContains(plain, 100, 40) == true, "and bottom-right")
	end
	print("  ✓ no UICorner, no rejection")

	print("[TEST] HitTest: a rounded element rejects its corner triangles...")
	do
		-- es9: the engine accounts for UICorner and we did not, so a control
		-- claimed its square corners — a pointer in the dead triangle outside a
		-- rounded button still hovered and still clicked it.
		local rounded = fakeGui(0, 0, 100, 40, UDim.new(0, 12))

		-- The exact corner is outside the arc: distance from the corner centre
		-- (12, 12) to (0, 0) is 12 * sqrt(2) ~= 17, well beyond r = 12.
		assert(HitTest.RoundedContains(rounded, 0, 0) == false, "the top-left point is OUTSIDE")
		assert(HitTest.RoundedContains(rounded, 100, 0) == false, "so is top-right")
		assert(HitTest.RoundedContains(rounded, 0, 40) == false, "and bottom-left")
		assert(HitTest.RoundedContains(rounded, 100, 40) == false, "and bottom-right")

		-- Inside the arc, and everywhere that is not a corner box.
		assert(HitTest.RoundedContains(rounded, 12, 12) == true, "the corner CENTRE is inside")
		assert(HitTest.RoundedContains(rounded, 50, 0) == true, "the middle of the top edge is inside")
		assert(HitTest.RoundedContains(rounded, 0, 20) == true, "the middle of the left edge is inside")
		assert(HitTest.RoundedContains(rounded, 50, 20) == true, "and the centre")

		-- Just inside the arc along the diagonal: 12 - 12/sqrt(2) ~= 3.5 from the
		-- edge on each axis puts it exactly on the arc, so 5 is comfortably in.
		assert(HitTest.RoundedContains(rounded, 5, 5) == true, "just inside the arc")
	end
	print("  ✓ corner triangles rejected, edges and centre kept")

	print("[TEST] HitTest: the radius is clamped to the element...")
	do
		-- UDim.new(1, 0) is a pill, not an error: scale resolves against the
		-- SMALLER dimension and can never exceed half of either.
		local pill = fakeGui(0, 0, 100, 40, UDim.new(1, 0))
		assert(HitTest.RoundedContains(pill, 0, 0) == false, "a pill rejects its corners")
		assert(HitTest.RoundedContains(pill, 50, 20) == true, "and keeps its middle")
		-- Radius clamps to 20 (half the height), so the left cap centre is (20, 20).
		assert(HitTest.RoundedContains(pill, 20, 20) == true, "the cap centre is inside")
		assert(HitTest.RoundedContains(pill, 1, 20) == true, "and the extreme left edge midpoint")

		-- An absurd offset radius clamps rather than inverting the test.
		local over = fakeGui(0, 0, 100, 40, UDim.new(0, 9999))
		assert(HitTest.RoundedContains(over, 50, 20) == true, "an oversized radius still keeps the centre")
	end
	print("  ✓ scale resolves to the smaller side, and clamps to half")

	print("[TEST] HitTest: a DECLARED shape beats a rendered one...")
	do
		-- The precedence that lets both worlds coexist (ms-43 M112).
		--
		-- Every control in the stack DECLARES its shape now, including Aether's
		-- own (M113). The fallback exists for third-party and not-yet-migrated
		-- code, not as a second supported way to express shape.
		--
		-- It is still pinned, because removing it would silently return anything
		-- that has not migrated to square hit-testing — a regression with no
		-- error and no visual tell.
		local rendered: any = {
			AbsolutePosition = Vector2.new(0, 0),
			AbsoluteSize = Vector2.new(100, 40),
			FindFirstChildOfClass = function(_s: any, c: string): any
				return if c == "UICorner" then { CornerRadius = UDim.new(0, 12) } else nil
			end,
		}
		assert(HitTest.RoundedContains(rendered, 0, 0) == false,
			"a control that only RENDERS a corner is still round to the router")

		-- And a declaration overrides it, so a widget can deliberately give
		-- itself a hit shape that differs from what it draws.
		local both: any = {
			AbsolutePosition = Vector2.new(0, 0),
			AbsoluteSize = Vector2.new(100, 40),
			GetAttribute = function(_s: any, k: string): any
				return if k == "SpektrHitCornerOffset" then 0
					elseif k == "SpektrHitCornerScale" then 0
					else nil
			end,
			FindFirstChildOfClass = function(_s: any, c: string): any
				return if c == "UICorner" then { CornerRadius = UDim.new(0, 12) } else nil
			end,
		}
		-- Declared zero is still a declaration of "square", and it wins.
		assert(HitTest.RoundedContains(both, 0, 0) == true,
			"a declared square beats a rendered corner")
	end
	print("  ✓ declared wins, rendered is the fallback that keeps Aether's controls correct")

	print("[TEST] HitTest tests passed successfully!")
end

-- ms-44: migrated onto testkit. This suite had no harness — bare asserts inside named
-- functions, invoked at the bottom of the file. That is the ms-43 M30 shape: delete an
-- invocation and the file still exits 0 and still reads as coverage. Registered tests
-- make that a VACUOUS failure instead, and give each one a name, a time and a tier in
-- the ##testkit JSON.
local T = require("@testkit")
T.test("HitTest", run, "math")

return T.run("HitTest")
