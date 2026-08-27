--!strict
--[[
	Aether · useDisclosure — an open/closed boolean with its verbs (ms-53 D4).

	    local shop = useDisclosure(false)
	    shop.Open()  shop.Close()  shop.Toggle()
	    Visible = shop.Opened

	MANTINE'S SHAPE, DELIBERATELY. It is the one borrowing from that library the
	consolidation named first, and the reason is not elegance: a boolean plus
	three closures is what every menu writes by hand, slightly differently, and
	`Toggle` is where the differences hide. One place to write it is one place to
	get it right.

	Zag's `presence` machine is the model for `Presence`; this is the other half
	of the split -- the machine for the framework, the ergonomics for the call
	site.

	IT IS NOT A SCREEN. This is a local boolean with no knowledge of other
	elements: no exclusivity, no modal depth, no arbitration. A screen that must
	close its siblings belongs in `ScreenStack`, and reaching for this instead is
	how two menus end up open at once.
]]

local Deps = require("./Deps")

local source = Deps.source

export type Disclosure = {
	Opened: () -> boolean,
	Open: () -> (),
	Close: () -> (),
	Toggle: () -> (),
	--- Set it directly, for a caller wiring an external boolean through.
	Set: (boolean) -> (),
}

local function useDisclosure(initial: boolean?): Disclosure
	local opened = source(initial == true)

	return {
		Opened = function(): boolean
			return opened()
		end,
		Open = function()
			opened(true)
		end,
		Close = function()
			opened(false)
		end,
		--- READ THEN WRITE, not `opened(not opened())` inline at each call site.
		--- The inline form is where a caller reaches for a stale captured value,
		--- and it is the reason this exists at all.
		Toggle = function()
			opened(not opened())
		end,
		Set = function(value: boolean)
			opened(value == true)
		end,
	}
end

return useDisclosure
