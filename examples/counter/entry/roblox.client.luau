--!strict
--[[
	The ROBLOX entry point.

	Shorter than the desktop one, and the difference is exactly the three things
	the engine already provides: the value vocabulary is global, the renderer
	paints, and the Heartbeat drives frames. So this mounts and gets out of the
	way.

	`host.mount` is the same call the desktop side would make — on Roblox it is
	vide's own, headlessly it parents into a mock — which is why neither entry
	point has to branch on environment to attach its tree.
]]

local Players = game:GetService("Players")

local Aether = require(script.Parent.Parent.roblox_packages.Aether)
local Counter = require(script.Parent.Parent.src.Counter)

local host = Aether.Host.detect()

local screen = Instance.new("ScreenGui")
screen.Name = "AetherCounter"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local increment: () -> ()

host.mount(function()
	local tree, inc = Counter({ start = 0 })
	increment = inc
	return tree
end, screen)

--- The same transition the desktop shell drives from its own loop, driven here
--- by the engine's. Once a second, so the two hosts can be compared side by side
--- without either racing ahead.
task.spawn(function()
	while true do
		task.wait(1)
		increment()
	end
end)
