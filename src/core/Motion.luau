--!strict
--[[
	Aether · Motion — the seam a motion runtime registers itself into.

	WHY A SEAM RATHER THAN A DEPENDENCY (ms-51 M16)
	Aether's scrolling primitives want a spring: ScrollArea, Scrollbar and
	ScrollingFrame all smooth their offset, and es9 asked for that rather than
	stepping. Aether therefore declared spektr/flux — and that was the LAST
	upward edge in the milestone, because motion is Layer 3 and sits ABOVE the
	headless protocols it was being consumed by.

	It is also the one edge that could not be reversed the way the component seams
	were. Those were pure inversions: the package needed an authority and was
	forbidden to ask, so Aether depended on it purely to inject. Here Aether is a
	genuine CONSUMER. Reversing it would mean Flux driving Aether's internals,
	which is worse.

	So motion becomes optional instead, which it should always have been:

	  * A host with no motion runtime gets `nil` and steps instantly. That is the
	    same promise spektr/button makes about its press travel, and the reason
	    the button seam survived its own reversal.
	  * A host with Flux gets springs, because Flux registers itself on require —
	    Flux depends on Aether (rank 3 -> rank 1, downward), so it can.

	NEVER CLOBBER. `SetSpringDriver` refuses to replace a driver an application
	already installed, matching every other seam in the repo (ms-43 M29). An app
	composing its own motion authority wins over a package registering a default.
]]

local Motion = {}

--- Build a smoothed getter from a target getter.
---
--- The shape Flux.MotionDrivers.Spring already has, named here so the primitives
--- can depend on the CONTRACT rather than on Flux.
export type SpringDriver = (
	target: () -> number,
	options: { Period: number?, DampingRatio: number? }?
) -> () -> number

local springDriver: SpringDriver? = nil
local springOwner: string? = nil

--- Register the authority that turns a target into a smoothed value.
---
--- Returns whether it took. A caller that needs to know it lost — a package
--- registering a default behind an application's choice — can check rather than
--- assume.
function Motion.SetSpringDriver(driver: SpringDriver?, owner: string?): boolean
	if driver ~= nil and springDriver ~= nil then
		return false
	end
	springDriver = driver
	springOwner = if driver ~= nil then owner else nil
	return true
end

--- The driver in force, or nil when nothing registered one.
function Motion.GetSpringDriver(): SpringDriver?
	return springDriver
end

function Motion.HasSpringDriver(): boolean
	return springDriver ~= nil
end

--- Who registered it, for diagnostics. nil when unregistered.
function Motion.SpringOwner(): string?
	return springOwner
end

--- Smooth `target`, or hand it straight back.
---
--- The ONE call site the primitives use, so "is there a motion runtime" is
--- answered in a single place rather than re-guarded at each of the four
--- smoothing sites — which is where the `if isRoblox and Deps.Flux and
--- Deps.Flux.MotionDrivers` chains came from, and why they had drifted into
--- four slightly different spellings of the same question.
function Motion.Smooth(
	target: () -> number,
	options: { Period: number?, DampingRatio: number? }?
): () -> number
	local driver = springDriver
	if not driver then
		return target
	end
	return driver(target, options)
end

--- Testing seam: forget the registration so a suite can install its own.
function Motion._reset()
	springDriver = nil
	springOwner = nil
end

return Motion
