--!strict
--!tier math
--[=[
	Tooltip actually reaches the tree, off-engine.

	WHY THIS SUITE EXISTS (milestone 55 sprint 3)
	A prior finding (Dew's own milestone 8, "tooltip-does-not-open-under-dew",
	2026-09-13) reported every internal predicate correct -- hovered, the
	machine's own IsOpen, both anchor type checks -- and no badge ever
	entering the tree regardless. Four real defects were found and fixed at
	the time; the render gap itself was left open, with no test written
	against it: "It needs a test, not a demo. A demo can only report that
	nothing appeared; a test inside Aether can ask whether Tooltip's own
	isOpen flipped."

	Re-testing against the current tree does not reproduce the failure --
	confirmed here AND live, in a real Dew window, with a real hover in and
	out. This suite is the missing test the prior finding called for, so a
	future regression is caught here rather than rediscovered by hand.

	THE AMBIENT HOST FOR SCENE/CLOCK, BUT `Deps.root`/`Deps.create` FOR
	ANYTHING REACTIVE -- and this is not a style choice, it is load bearing.
	`Deps.Host.root` and `Deps.vide.root` are DIFFERENT function objects
	(`Deps.Host.root == Deps.vide.root` is `false`, confirmed directly): the
	ambient host is assembled through a separate path than the one
	`Deps.effect`'s own scope tracking recognises, so a scope pushed by
	`Deps.Host.root` is invisible to `Deps.effect` -- which is exactly what
	`Tooltip.luau` calls internally, twice. Building the tree under
	`Deps.root` instead, while still reading `Deps.Host.Scene`/`.Clock` for
	the parts that are plain data rather than reactive graph state, is what
	makes `Tooltip`'s own effects (and its dwell timer, scheduled off this
	same `Deps.Host.Clock`) actually run.

	NOT `Live.Session`, AND NOT `Host.SetBounds`, EITHER -- a second, separate
	identity split. `Deps.Host` on this machine resolves to the sibling
	`luau-datamodel` package (`src/host/Host.luau`'s own `Host.LuauDataModel`,
	a name it happens to share with this framework's OWN pure-Luau test
	double), and it builds its OWN internal `vide` instance rather than taking
	the one `Deps.luau` resolved (`Deps.Host.vide == Deps.vide` is `false`).
	`Scene.Name` and the other read-only `Scene` functions duck-type over any
	instance shape and work fine on a `Deps.create`-built node (confirmed
	directly), but `Host.SetBounds` -- the one function that WRITES into that
	package's own native registry -- throws `invalid argument #1 to 'rawget'
	(table expected, got userdata)` the instant it is handed a node that
	package never created. `Live.Session` calls exactly this from its own
	`commitLayout`, and `src/HitTest.luau`'s own `RawContains` calls the exact
	same `Scene.Bounds` to answer `PointerRouter`'s hit test, so the crash
	follows a real hover into the router too, not only into `Live.Session`.

	So this suite drives geometry and frames by hand instead: `Layout.Solve`
	for the rectangles (read-only, confirmed safe on a `Deps.create` node),
	`PointerRouter._SimulateHover`/`_SimulateFrame` for the pointer and
	`useHover`'s poll, and `Deps.Host.Clock.Step` for the dwell timer.
	`Scene.Bounds` itself is patched for the duration of this test alone (and
	restored after, pass or fail) to fall back to reading the plain
	`AbsolutePosition`/`AbsoluteSize` fields `applySolvedBounds` below writes,
	exactly the shape `PointerRouter.test.luau`'s own fake surfaces already
	use, whenever the native path errors on a foreign instance. Nothing in
	`src/` changes; this is a test-local seam over a real, load-bearing
	function, not a fix to the function itself.

	THE `Child` FORM, NOT `Anchor` -- a third, independent gap this suite
	surfaced and is not the one it exists to catch. `Tooltip.luau`'s `Anchor`
	form only binds hover when `typeof(a) == "Instance"`; off-engine, NEITHER
	host on this machine satisfies that -- `Deps.Host.create`'s own instances
	report `typeof() == "table"` (confirmed directly, `IsA` still works via
	metamethod) and `Deps.create`'s report `typeof() == "userdata"` with no
	`IsA` at all. Both are real engines' actual answer (`Instance`) in a real
	Roblox or Dew session, which is why the earlier live Dew screenshots of
	this same `Anchor` form showed the badge correctly -- this is a testing-
	environment gap, not a shipped defect, and outside this sprint's scope to
	close. The `Child` form's own binding
	(`action(function(node) hoverHandle.Bind(node) end)`) carries no such
	guard, so it is what this suite exercises.
]=]
local T = require("@testkit")
local Deps = require("../../src/Deps")
local Aether = require("../../src/api")
local Layout = require("../../src/core/Layout")

local host = Deps.Host
local Scene = host.Scene
local V = host.Vocabulary
local create = Deps.create

local VIEWPORT = { X = 0, Y = 0, Width = 300, Height = 200 }

--- Stand-in for `Host.SetBounds`, which cannot accept a `Deps.create`-built
--- node on this host (see the header). Writes the plain fields the patched
--- `Scene.Bounds` below reads back.
local function applySolvedBounds(root: any)
	for _, item in ipairs(Layout.Solve(Scene, root, VIEWPORT)) do
		item.Node.AbsolutePosition = { X = item.Rect.X, Y = item.Rect.Y }
		item.Node.AbsoluteSize = { X = item.Rect.Width, Y = item.Rect.Height }
	end
end

--- See the header. Falls back to the plain fields only when the native path
--- errors, so a real engine host (where `Bounds` always succeeds) is untouched.
local function patchSceneBounds(): () -> ()
	local nativeBounds = Scene.Bounds
	Scene.Bounds = function(node: any): (number, number, number, number)
		local ok, bx, by, bw, bh = pcall(nativeBounds, node)
		if ok then
			return bx, by, bw, bh
		end
		local pos, size = node.AbsolutePosition, node.AbsoluteSize
		return pos.X, pos.Y, size.X, size.Y
	end
	return function()
		Scene.Bounds = nativeBounds
	end
end

local function tooltipIsInTheTree(root: any): boolean
	for _, item in ipairs(Layout.Solve(Scene, root, VIEWPORT)) do
		if Scene.Name(item.Node) == "AetherTooltip" then
			return true
		end
	end
	return false
end

local function testTooltipBadgeReachesTheTreeOnHoverDwell()
	local PointerRouter = Aether.PointerRouter
	local unpatchSceneBounds = patchSceneBounds()

	local ok, err = pcall(function()
		local destroy = Deps.root(function()
			local screen = create("ScreenGui")({ Name = "Screen", Enabled = true })
			local root = create("Frame")({
				Name = "Root",
				Parent = screen,
				Size = V.UDim2.fromScale(1, 1),
				Aether.Tooltip({
					Content = "hello",
					Delay = 0.05,
					Child = create("Frame")({
						Name = "Anchor",
						Size = V.UDim2.fromOffset(120, 40),
						Position = V.UDim2.fromOffset(20, 20),
					}),
				}),
			})

			applySolvedBounds(root)

			assert(not tooltipIsInTheTree(root), "no tooltip before any hover reaches the anchor")

			--- INSIDE THE ANCHOR'S OWN RECT (20,20)-(140,60).
			PointerRouter._SimulateHover(50, 30)

			--- ENOUGH FRAMES TO CLEAR BOTH the hover-settle pass and the tooltip's
			--- own 0.05s dwell delay -- ten sixtieths of a second is a sixth,
			--- comfortably past it.
			for _ = 1, 10 do
				PointerRouter._SimulateFrame()
				host.Clock.Step(1 / 60)
				applySolvedBounds(root)
			end

			assert(
				tooltipIsInTheTree(root),
				"the badge must actually reach the tree after a hover dwell, not merely report IsOpen"
			)

			--- CLEARLY OUTSIDE THE ANCHOR.
			PointerRouter._SimulateHover(250, 180)
			for _ = 1, 5 do
				PointerRouter._SimulateFrame()
				host.Clock.Step(1 / 60)
				applySolvedBounds(root)
			end

			assert(not tooltipIsInTheTree(root), "leaving the anchor must remove the badge again")
		end)
		destroy()
	end)

	unpatchSceneBounds()
	if not ok then
		error(err, 0)
	end
end

T.test("tooltip badge reaches the tree on hover dwell", testTooltipBadgeReachesTheTreeOnHoverDwell, "math")

return T.run("TooltipRendersLive")
