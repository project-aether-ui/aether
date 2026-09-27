--!strict
--!tier math
--[=[
	aether · primitives/Checkbox.

	NO PRIMITIVE-LEVEL SUITE EXISTED FOR THIS FILE BEFORE MILESTONE 54 SPRINT
	2 -- `tests/core/createCheckbox.test.luau` already pins the machine
	against a fake Router/Selection pair, and every other Checkbox behaviour
	is inherited from there. What that suite cannot prove is this sprint's
	own success criterion: "a Primitive built after Sprint 2 lands mounts and
	responds to a real click with no call site anywhere naming PointerRouter
	or SelectionRouter."

	`Checkbox.luau`'s own source no longer requires `PointerRouter` or
	`SelectionRouter` at all (it reads both through `RouterContext` now,
	verified directly against `RouterContext.useRouter()`/`useSelection()`
	below). What is left to prove is that the ambient default those calls
	answer is the REAL router, not a stand-in, and that the real router's own
	`_SimulatePress`/`_SimulateRelease` seam -- the one `tests/PointerRouter
	.test.luau` already exercises headlessly -- genuinely activates a machine
	bound through it. The bind target here is a plain fake surface, the same
	shape `tests/PointerRouter.test.luau`'s own `fakeSurface` is, because
	mounting through `vide.create` against this toolchain's installed native
	host double is its own separate, pre-existing fragility (`tests/host/
	SecondHost.test.luau` and its neighbours already carry that risk, and it
	is not this sprint's to fix) -- the point being pinned here is the router
	identity and its real activation path, not `vide`'s own instance plumbing.
]=]
local T = require("@testkit")
local RouterContext = require("../../src/RouterContext")
local PointerRouter = require("../../src/PointerRouter")
local SelectionRouter = require("../../src/SelectionRouter")
local createCheckbox = require("../../src/core/createCheckbox").createCheckbox

local function fakeSurface(x: number, y: number, w: number, h: number): any
	return {
		Parent = { IsA = function() return false end },
		Visible = true,
		ZIndex = 1,
		AbsolutePosition = { X = x, Y = y },
		AbsoluteSize = { X = w, Y = h },
		IsA = function(_self: any, class: string): boolean
			return class == "GuiObject"
		end,
		Active = false,
	}
end

local function testTheAmbientDefaultIsTheRealSingletons()
	assert(RouterContext.useRouter() == PointerRouter, "Checkbox reads Router through this, and the default must be real")
	assert(RouterContext.useSelection() == SelectionRouter, "same for Selection")
end

local function testARealClickThroughTheRealRouterTogglesTheMachine()
	local checked: boolean? = nil

	local machine = createCheckbox({
		Router = RouterContext.useRouter(),
		Selection = RouterContext.useSelection(),
		Checked = false,
		OnCheckedChanged = function(v: boolean)
			checked = v
		end,
	})

	local surface = fakeSurface(0, 0, 40, 40)
	for _, entry in ipairs(machine.GetRootProps()) do
		if type(entry) == "function" then
			entry(surface)
		end
	end

	PointerRouter._SimulatePress(20, 20)
	PointerRouter._SimulateRelease(20, 20)
	assert(checked == true, "a real press-then-release through the real PointerRouter singleton should check it")

	PointerRouter._SimulatePress(20, 20)
	PointerRouter._SimulateRelease(20, 20)
	assert(checked == false, "and a second one should uncheck it")

	machine.Destroy()
end

T.test("the ambient default is the real singletons", testTheAmbientDefaultIsTheRealSingletons, "math")
T.test(
	"a real click through the real router toggles the machine",
	testARealClickThroughTheRealRouterTogglesTheMachine,
	"math"
)

return T.run("primitives/Checkbox")
