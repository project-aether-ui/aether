--!strict
--[[
	The DESKTOP entry point — `aether` CLI and Dew.

	Three things Roblox does not need, and each for a stated reason:

	  1. `InstallVocabulary`, because there is no engine to supply `UDim2` and
	     `Color3` as globals. The component names them; something has to define
	     them.
	  2. `Live.Session`, because nothing is driving frames. Roblox has a Heartbeat
	     and a renderer; here the host does both.
	  3. A size, because there is no ScreenGui to inherit one from.

	Everything else — the component itself — is shared, and that is the entire
	point of the file being this short.
]]

local Host = require("@aether/host/Host")
local Live = require("@aether/host/Live")
local PointerRouter = require("@aether/PointerRouter")

local Counter = require("../src/Counter")

local WIDTH, HEIGHT = 240, 96

local host = Host.detect()
host.InstallVocabulary()

local tree, increment = Counter({ start = 0 })

return {
	Session = Live.Session(host, tree, PointerRouter, WIDTH, HEIGHT),
	--- Exposed so a shell can drive the example without the component having to
	--- know what a keystroke or a timer is.
	Increment = increment,
	Width = WIDTH,
	Height = HEIGHT,
}
