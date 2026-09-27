--!strict
--!tier math
--[=[
	aether · RouterContext.

	Mirrors the shape `ScopeContext` itself has no dedicated suite for --
	Router and Selection are new ambient values (milestone 54 sprint 2), so
	this suite pins the two things a Primitive now depends on: the default is
	the real singleton, not nil (unlike `ScopeContext`'s own, where nil is a
	legitimate Scope), and `RouterProvider` actually swaps what `useRouter`/
	`useSelection` answer inside its own `Children`, then hands control back
	to the ambient default once that scope ends.
]=]
local T = require("@testkit")
local Deps = require("../src/Deps")
local RouterContext = require("../src/RouterContext")
local PointerRouter = require("../src/PointerRouter")
local SelectionRouter = require("../src/SelectionRouter")

local vide = Deps.vide

--- `vide.context`'s own "set" mode errors outside a vide scope ("attempt to
--- set context outside of a vide scope"), so every override test below runs
--- its body through `vide.root`, the same way a real Primitive is always
--- mounted inside one -- a bare test frame is not itself a vide scope.
local function withRoot(fn: () -> ())
	local dispose = vide.root(fn)
	if dispose then
		dispose()
	end
end

local function testTheDefaultIsTheRealSingletonNotNil()
	assert(RouterContext.useRouter() == PointerRouter, "useRouter with no provider must answer the real PointerRouter")
	assert(
		RouterContext.useSelection() == SelectionRouter,
		"useSelection with no provider must answer the real SelectionRouter"
	)
end

local function testAProviderOverridesBothInsideItsOwnChildren()
	local fakeRouter = { tag = "fake-router" }
	local fakeSelection = { tag = "fake-selection" }
	local seenRouter, seenSelection

	withRoot(function()
		RouterContext.RouterProvider({
			Router = fakeRouter,
			Selection = fakeSelection,
			Children = function()
				seenRouter = RouterContext.useRouter()
				seenSelection = RouterContext.useSelection()
				return nil
			end,
		})
	end)

	assert(seenRouter == fakeRouter, "a provided Router must be what useRouter answers inside Children")
	assert(seenSelection == fakeSelection, "a provided Selection must be what useSelection answers inside Children")
end

local function testTheDefaultReturnsOnceTheProviderScopeEnds()
	local fakeRouter = { tag = "fake-router-2" }

	withRoot(function()
		RouterContext.RouterProvider(fakeRouter, function()
			assert(RouterContext.useRouter() == fakeRouter)
		end)
	end)

	assert(RouterContext.useRouter() == PointerRouter, "the real singleton must be back once the provider's scope ends")
end

local function testOverridingOnlyOneLeavesTheOtherAmbient()
	local fakeSelection = { tag = "fake-selection-only" }

	withRoot(function()
		RouterContext.RouterProvider({
			Selection = fakeSelection,
			Children = function()
				assert(RouterContext.useRouter() == PointerRouter, "Router was not overridden and must still be the real one")
				assert(RouterContext.useSelection() == fakeSelection)
				return nil
			end,
		})
	end)
end

T.test("the default is the real singleton, not nil", testTheDefaultIsTheRealSingletonNotNil, "math")
T.test("a provider overrides both inside its own Children", testAProviderOverridesBothInsideItsOwnChildren, "math")
T.test("the default returns once the provider scope ends", testTheDefaultReturnsOnceTheProviderScopeEnds, "math")
T.test("overriding only one leaves the other ambient", testOverridingOnlyOneLeavesTheOtherAmbient, "math")

return T.run("RouterContext")
