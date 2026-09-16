--!strict
--[[
	The DESKTOP entry point, for a host with no engine under it.

	What is here is the two facts only this file knows: which component, and how
	big. Compare `roblox.client.luau` beside it, which knows the same two and
	nothing else either. Resolving the host, installing the value vocabulary and
	opening a reactive scope are the framework's, and `Aether.mount` is all of
	them.
]]

local Aether = require("@aether/api")
local Counter = require("../src/Counter")

local WIDTH, HEIGHT = 240, 96

--- The counter hands its increment back beside its tree, so a host can drive the
--- component without reaching into it.
local increment: () -> ()

local tree = Aether.mount(function()
	local built, inc = Counter({ start = 0 })
	increment = inc
	return built
end)

return {
	Tree = tree,
	Increment = increment,
	Width = WIDTH,
	Height = HEIGHT,
}
