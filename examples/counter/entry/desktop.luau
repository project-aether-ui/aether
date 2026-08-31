--!strict
--[[
	The DESKTOP entry point, for the `aether` CLI and any other host with no
	engine under it.

	Everything that used to be here -- resolving the host, installing the value
	vocabulary, opening a reactive scope, opening a session -- is `Desktop.Mount`.
	It moved into the framework because every off-engine host was doing the same
	four things, and the one that forgot a step got a working-looking program that
	silently lost input or drew nothing.

	What is left is the two facts only this file knows: which component, and how
	big. Compare `roblox.client.luau` beside it, which knows the same two and
	nothing else either.
]]

local Desktop = require("@aether/host/Desktop")
local Counter = require("../src/Counter")

local WIDTH, HEIGHT = 240, 96

local mounted = Desktop.Mount(function()
	return Counter({ start = 0 })
end, WIDTH, HEIGHT)

return {
	Session = mounted.Session,
	--- The counter hands its increment back beside its tree, so a host can drive
	--- the component without reaching into it.
	Increment = mounted.Actions,
	Width = WIDTH,
	Height = HEIGHT,
}
