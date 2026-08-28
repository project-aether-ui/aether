--!strict
--[[
	The shape of an Aether application entry point, off-engine.

	THIS FILE IS THE PARITY CLAIM, MADE CONCRETE. Everything below the vocabulary
	install is ordinary Aether: `host.create` builds a tree, and the properties are
	named exactly as they are named on Roblox — `Size`, `Position`,
	`BackgroundColor3`, `Text`. A Roblox entry point differs only in that the
	engine mounts and drives, so it needs neither `InstallVocabulary` nor
	`Live.Session`.

	`host.InstallVocabulary()` is what makes `UDim2` and `Color3` exist as globals
	when there is no engine to supply them. It writes into `_G` (and `getfenv(0)`
	where that exists), so the component code below reads identically in both
	places rather than reaching through a host handle on one of them.
]]

local Host = require("@aether/host/Host")
local Live = require("@aether/host/Live")
local PointerRouter = require("@aether/PointerRouter")

local host = Host.detect()
host.InstallVocabulary()

local WIDTH, HEIGHT = 200, 80

local root = host.create("Frame")({
	Name = "Root",
	Size = UDim2.fromOffset(WIDTH, HEIGHT),
	Position = UDim2.fromOffset(0, 0),
	BackgroundColor3 = Color3.new(0.07, 0.09, 0.15),

	host.create("TextLabel")({
		Name = "Label",
		Size = UDim2.fromOffset(120, 24),
		Position = UDim2.fromOffset(20, 28),
		BackgroundColor3 = Color3.new(0.22, 0.74, 0.97),
		Text = "aether",
		TextSize = 16,
	}),
})

return {
	Session = Live.Session(host, root, PointerRouter, WIDTH, HEIGHT),
}
