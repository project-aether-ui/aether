--!strict
--[[
	The smallest interactive thing: one Pressable, one counter.

	This exists because pressables render and do not respond in a desktop host,
	and no test anywhere drives a press through a real session — the router's own
	suites call `PointerRouter.Input` directly against hand-registered records,
	which skips everything between a tree and a hit.
]]

local Host = require("@aether/host/Host")
local Live = require("@aether/host/Live")
local PointerRouter = require("@aether/PointerRouter")
local Aether = require("@aether/api")

local host = Host.detect()
host.InstallVocabulary()

local WIDTH, HEIGHT = 200, 100

local presses = 0
local activations = 0
local hovers = 0

local tree
host.root(function()
	tree = Aether.create "Frame" {
		Name = "Root",
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		BackgroundColor3 = Color3.new(0.1, 0.1, 0.1),

		Aether.Pressable({
			Name = "Button",
			Position = UDim2.fromOffset(20, 20),
			Size = UDim2.fromOffset(100, 40),
			BackgroundColor3 = Color3.new(0.2, 0.7, 1),
			BackgroundTransparency = 0,

			OnPressed = function()
				presses += 1
			end,
			--- Press AND release inside. What a button should use: a press that
			--- leaves before releasing must not count.
			OnActivated = function()
				activations += 1
			end,
			OnHoverChanged = function(hovered: boolean)
				if hovered then
					hovers += 1
				end
			end,
		}),
	}
	return tree
end)

return {
	Session = Live.Session(host, tree, PointerRouter, WIDTH, HEIGHT),
	Width = WIDTH,
	Height = HEIGHT,
	--- Read back by the test. Functions rather than values so the test sees the
	--- current count rather than a copy taken at module load.
	Presses = function()
		return presses
	end,
	Activations = function()
		return activations
	end,
	Hovers = function()
		return hovers
	end,

}
