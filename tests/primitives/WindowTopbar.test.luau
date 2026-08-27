--!strict
--!tier math
local T = require("@testkit")
local WindowTopbar = require("../../src/primitives/WindowTopbar")

local function testWindowTopbarConstruction()
	local closed = false
	local topbar = WindowTopbar({
		Title = "Inspector",
		OnClose = function()
			closed = true
		end,
	})

	assert(topbar ~= nil, "WindowTopbar primitive constructed")
end

local function testWindowTopbarSlotOverride()
	local customBgRendered = false
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
end

T.test("window topbar construction", testWindowTopbarConstruction, "math")
T.test("window topbar slot override", testWindowTopbarSlotOverride, "math")

return T.run("WindowTopbarPrimitive")
