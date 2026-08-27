--!strict
--[[
	spektr/virtual — which subset of a large collection do you pay for?

	ONE QUESTION, ASKED TWICE. Everything here answers "given N things, which
	small subset costs anything, in a way that does not grow with N":

	  * `ItemIndex`  — given a scroll offset, which slice do you RENDER?
	  * `InterestSet`— given a set of keys, which slice do you KEEP ALIVE?  (M1)

	They look like different problems and are the same one. `ItemIndex` bounds
	instances against the viewport; `InterestSet` bounds state and subscriptions
	against whatever someone is actually observing. Missing the second is what
	let PrismStudio cost 1160 KB per entity against a 28 KB baseline — the rows
	unmounted correctly and their reactive scopes never did.

	WHY THIS IS NOT A UI PACKAGE, given its only consumer today is one.
	`ItemIndex` names no Roblox type and requires no reactive library; its whole
	interface is numbers and opaque item tables ("Anything the renderer needs.
	Never read here"). It was written that way inside `spektr/scrollbar` and only
	the address was wrong. The constraint has to be structural rather than
	habitual, because the moment this can see vide, a profiler surface with no UI
	at all can no longer use it — and that consumer is the reason the second
	member exists.

	So: no vide, no Roblox types, no engine. Fully headless-testable, and its
	suite runs in plain lune with no shim.
]]

local isScriptInstance = typeof(script) == "Instance"
local ItemIndex = if isScriptInstance
	then require((script :: any).ItemIndex)
--- `@self/X`, NOT `./X` (ms-53 D8). From an INIT file `./` means the PACKAGE
--- FOLDER -- in Roblox, because Rojo collapses `src/init.luau` into a ModuleScript
--- named `src`, and in lune too, measured. `@self/X` names a child in both.
	else require("@self/ItemIndex")
local InterestSet = if isScriptInstance
	then require((script :: any).InterestSet)
	else require("@self/InterestSet")

return {
	--- Offset ↔ index over items of DIFFERENT sizes, with measurement correction.
	--- Re-exported by `spektr/scrollbar` for compatibility; this is its home.
	ItemIndex = ItemIndex,

	--- Which keys are worth keeping state alive for. Epoch/diff, so release is
	--- derived rather than remembered.
	InterestSet = InterestSet,
}
