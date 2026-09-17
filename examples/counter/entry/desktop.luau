--!strict
--[[
	The DESKTOP entry point, for a host with no engine under it.

	What is here is the two facts only this file knows: which component, and how
	big. Compare `roblox.client.luau` beside it, which knows the same two and
	nothing else either. Resolving the host, installing the value vocabulary and
	opening a reactive scope are the framework's, and `vide.mount` is all of them.
]]

local Counter = require("../src/Counter")
local vide = require("../../../roblox_packages/vide")

local WIDTH, HEIGHT = 240, 96

--- The counter hands its increment back beside its tree, so a host can drive the
--- component without reaching into it. `vide.mount` returns its dispose closure
--- rather than the tree, so the tree is captured from inside the builder instead.
local increment: () -> ()
local tree: any

vide.mount(function()
	local built, inc = Counter({ start = 0 })
	increment = inc
	tree = built
	return built
end)

return {
	Tree = tree,
	Increment = increment,
	Width = WIDTH,
	Height = HEIGHT,
}
