--!strict
--[[
	safeWarn: `warn`, where a host has one.

	WHY (milestone 56 sprint 1)
	`warn` does not exist under Dew's real VM -- confirmed directly, `type(warn)`
	is `nil` there. `createPressable`/`createRadioGroup`/`createTabs`/
	`createCheckbox`'s own "loud now, not silent" feature (milestone 54 sprint 5)
	calls it unconditionally when a prop matches `^On%u` but is not a handler the
	machine recognises, which means the ONE THING that feature exists to avoid --
	a caller's mistake going unreported -- instead crashes the whole construction
	under Dew. Confirmed live: `dew test` reported "attempt to call a nil value"
	at every one of these call sites, for `createPressable`, `createRadioGroup`
	and `createTabs` alike, and found a second, real bug on the way in --
	`WindowTopbar.luau`'s own `OnPress` typo (fixed alongside this file, in the
	same sprint) -- masked until this crash was fixed, since a crash and a
	warning both make a test suite red.

	NOT `Deps`-ROUTED. This file lives under `src/core/`, inside the boundary
	`verify_core_has_no_framework` enforces: a Layer 1 module reaches no
	framework, and `Deps.luau` is exactly that framework's own resolver. Every
	one of Roblox, Dew's pure-Luau double, and (once this ships) real Dew has
	SOME way to report a warning without crashing; this asks the AMBIENT
	environment directly, the same way every other Layer 1 module already
	reads `typeof`/`UDim2` as globals a conforming host provides, rather than
	reaching across the boundary for one.
]]

return function(message: string)
	if type(warn) == "function" then
		(warn :: any)(message)
	elseif type(print) == "function" then
		print(message)
	end
end
