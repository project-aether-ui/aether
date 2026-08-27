--!strict
local Deps = require("./Deps")
local vide = Deps.vide

local ScopeContext = if vide and vide.context then vide.context(nil :: any) else function(val: any?, fn: (() -> any)?)
	if fn then return fn() end
	return val
end

local function useScope(): any
	if type(ScopeContext) == "function" then
		return ScopeContext()
	end
	return nil
end

local function ScopeProvider(propsOrScope: any, maybeChildren: (() -> any)?): any
	local scope: any
	local childrenFn: (() -> any)?

	if type(propsOrScope) == "table" and propsOrScope.Children and type(propsOrScope.Children) == "function" then
		scope = propsOrScope.Scope
		childrenFn = propsOrScope.Children
	elseif type(maybeChildren) == "function" then
		scope = propsOrScope
		childrenFn = maybeChildren
	elseif type(propsOrScope) == "function" then
		scope = nil
		childrenFn = propsOrScope
	end

	if not childrenFn then
		return nil
	end

	if type(ScopeContext) == "function" then
		local ok, res = pcall(ScopeContext, scope, childrenFn)
		if ok then
			return res
		end
	end
	return childrenFn()
end

return {
	ScopeContext = ScopeContext,
	useScope = useScope,
	ScopeProvider = ScopeProvider,
}
