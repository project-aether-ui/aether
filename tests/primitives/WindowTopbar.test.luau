--!strict
--!tier math
local T = require("@testkit")
local Aether = require("../../src/api")
local host = Aether.Host.detect()
local WindowTopbar = require("../../src/primitives/WindowTopbar")

local function testWindowTopbarConstruction()
	local closed = false
	local destroy = host.root(function()
		local topbar = WindowTopbar({
			Title = "Inspector",
			OnClose = function()
				closed = true
			end,
		})

		assert(topbar ~= nil, "WindowTopbar primitive constructed")
	end)
	destroy()
end

local function testWindowTopbarSlotOverride()
	local customBgRendered = false
	local destroy = host.root(function()
		local topbar = WindowTopbar({
			Title = "Settings",
			Parts = {
				Background = function(props)
					customBgRendered = true
					return { Name = "CustomBg" }
				end,
			},
		})

		assert(topbar ~= nil, "WindowTopbar with custom slots constructed")
		assert(customBgRendered == true, "custom background slot rendered")
	end)
	destroy()
end

T.test("window topbar construction", testWindowTopbarConstruction, "math")
T.test("window topbar slot override", testWindowTopbarSlotOverride, "math")

return T.run("WindowTopbarPrimitive")
