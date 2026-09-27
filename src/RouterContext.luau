--!strict
--[[
	RouterContext -- PointerRouter and SelectionRouter as ambient values,
	threaded the same way `ScopeContext` already threads `Scope`. Milestone 54
	sprint 2.

	WHY (milestone 54)
	Every Primitive used to open with `require("../PointerRouter")` and
	`require("../SelectionRouter")` as module-level singletons with no way to
	hand a Primitive anything else -- fine for the real engine, but it meant a
	Primitive's own source always named both modules even though a consumer
	never had to. `ScopeContext` already proves the alternative: a
	`vide.context`-based ambient value, read with `useScope()`, overridable
	per call with an explicit `Scope` prop. This file is the same shape for
	the two ports that actually caused Primitives to name a module a consumer
	never touches.

	DEFAULTS TO THE REAL SINGLETONS, NOT TO NIL, unlike `ScopeContext`'s own
	default. `nil` is a legitimate `Scope` (no scope at all); it is never a
	legitimate `Router` or `Selection` -- every Core machine `error()`s
	immediately if either is nil. So the context itself is built with the real
	module already installed as its default value, and `useRouter()`/
	`useSelection()` only exist as thin readers rather than nil-coalescing
	wrappers.

	A CORE MACHINE CALLED DIRECTLY IS UNCHANGED. `createCheckbox`,
	`createPressable`, `createTabs`, `createRadioGroup` still take `Router`/
	`Selection` as required fields on their own `Options`, and
	`tests/core/*.test.luau`'s fake doubles still work exactly as they do
	today -- this file is read by Primitives, not by Core.
]]

local Deps = require("./Deps")
local vide = Deps.vide
local PointerRouter = require("./PointerRouter")
local SelectionRouter = require("./SelectionRouter")

local RouterContext = if vide and vide.context
	then vide.context(PointerRouter :: any)
	else function(val: any?, fn: (() -> any)?)
		if fn then
			return fn()
		end
		return val
	end

local SelectionContext = if vide and vide.context
	then vide.context(SelectionRouter :: any)
	else function(val: any?, fn: (() -> any)?)
		if fn then
			return fn()
		end
		return val
	end

local function useRouter(): any
	if type(RouterContext) == "function" then
		return RouterContext()
	end
	return PointerRouter
end

local function useSelection(): any
	if type(SelectionContext) == "function" then
		return SelectionContext()
	end
	return SelectionRouter
end

--- Provides `Router` and/or `Selection` for everything `Children` mounts,
--- the same three calling shapes `ScopeContext.ScopeProvider` already
--- accepts: a props table, `(router, fn)`, or `(router, selection, fn)`.
--- Either value left out (or nil) falls through to whatever is already
--- ambient -- a test overriding only `Selection` does not have to also name
--- the real `PointerRouter` just to pass it through unchanged.
local function RouterProvider(propsOrRouter: any, maybeSelectionOrChildren: any, maybeChildren: (() -> any)?): any
	local router: any = nil
	local selection: any = nil
	local childrenFn: (() -> any)? = nil

	if type(propsOrRouter) == "table" and type(propsOrRouter.Children) == "function" then
		router = propsOrRouter.Router
		selection = propsOrRouter.Selection
		childrenFn = propsOrRouter.Children
	elseif type(maybeChildren) == "function" then
		router = propsOrRouter
		selection = maybeSelectionOrChildren
		childrenFn = maybeChildren
	elseif type(maybeSelectionOrChildren) == "function" then
		router = propsOrRouter
		childrenFn = maybeSelectionOrChildren
	end

	if not childrenFn then
		return nil
	end

	local function withSelection(): any
		if selection ~= nil and type(SelectionContext) == "function" then
			local ok, res = pcall(SelectionContext, selection, childrenFn)
			if ok then
				return res
			end
		end
		return (childrenFn :: () -> any)()
	end

	if router ~= nil and type(RouterContext) == "function" then
		local ok, res = pcall(RouterContext, router, withSelection)
		if ok then
			return res
		end
	end
	return withSelection()
end

return {
	RouterContext = RouterContext,
	SelectionContext = SelectionContext,
	useRouter = useRouter,
	useSelection = useSelection,
	RouterProvider = RouterProvider,
}
