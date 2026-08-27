--!strict
--[[
	Aether · useSelection — one of N, locally owned (ms-53 D7)

	    local tabs = useSelection.new({
	        Items = { "general", "audio", "controls" },
	        Value = activeTab,                 -- a reactive getter
	        OnChange = function(id) activeTab(id) end,
	        SwitchMode = "wait",
	    })

	    tabs.Phase("audio")        -- closed | pending | open | closing
	    tabs.ShouldRender("audio") -- bind to Visible

	WHAT IT IS FOR. Tab panels, segmented controls, carousels, wizard steps —
	anything where exactly one of a set is current and the others animate out.

	WHY IT IS NOT `ScreenStack`. They look like the same problem: one-of-N,
	exclusive, with enter and exit. The OWNERSHIP is completely different. A
	screen stack is a global singleton with categories, modal depth and
	cross-screen arbitration; a selection belongs to ONE component instance, and
	two settings menus on screen have independent tabs. A global registry cannot
	express that without inventing scoped ids, and adding a second kind of member
	whose exclusivity is scoped is what would stop the stack being explicable.

	RADIX IS THE EVIDENCE. `Tabs` and `Dialog` both build on presence, and `Tabs`
	owns its own local `value` with no registry anywhere. The shared thing is the
	PRESENCE PRIMITIVE, not the stack — so this module is a few dozen lines over
	`Presence` rather than a second `ScreenStack`.

	IT IS CONTROLLED, AND ONLY CONTROLLED. `Value` is a reactive getter the caller
	owns; `Select` reports upward and mutates nothing here. That is not a
	simplification, it is the only shape that stays REACTIVE: a selection kept as
	a plain local would change without invalidating anything that read it, so a
	panel would swap on the next unrelated re-render rather than on the click.
	Every call site in this repo already holds the tab in a source, and Radix's
	`value` + `onValueChange` is the same split.

	THE VOCABULARY IS D6'S, DELIBERATELY. `closed | pending | open | closing` and
	`SwitchMode = "sync" | "wait"` mean here exactly what they mean for screens.
	A second set of names for the same two questions one layer down is how a
	framework becomes something you have to look up.
]]

local Presence = require("./Presence")

local useSelection = {}

export type Phase = "closed" | "pending" | "open" | "closing"

--- `sync` starts the incoming panel's enter while the outgoing one is still
--- leaving; `wait` holds it until the outgoing one has settled. Same two words,
--- same two meanings, as `ScreenStack`.
export type SwitchMode = "sync" | "wait"

export type Options = {
	--- Every id in the group, so a phase can be answered for one that is neither
	--- current nor requested.
	Items: { string },
	--- The requested selection, read reactively on every evaluation.
	Value: () -> string,
	--- Called when something in the group asks to change the selection. The
	--- caller updates whatever `Value` reads; nothing here is mutated.
	OnChange: ((id: string) -> ())?,
	SwitchMode: SwitchMode?,
	--- Is THIS item's exit animation still running? Same polled-predicate shape
	--- as `Presence`, and for the same reason: Flux is a sampled spring, not an
	--- event source. Omit and switching is instant.
	StillAnimating: ((id: string) -> boolean)?,
	--- The presence this whole group lives inside — the window, usually. When it
	--- leaves, every panel leaves with it.
	Inherit: Presence.Handle?,
}

export type Handle = {
	--- The CURRENT item: the one that is open. Under `wait` this lags `Value`
	--- until the outgoing panel has settled, which is the whole point of the mode.
	Value: () -> string,
	--- What was last asked for, which under `wait` can lead `Value`.
	Requested: () -> string,
	Select: (id: string) -> (),
	Phase: (id: string) -> Phase,
	ShouldRender: (id: string) -> boolean,
	--- The per-item presence, for a caller that wants to nest another group
	--- inside a panel.
	PresenceFor: (id: string) -> Presence.Handle,
}

function useSelection.new(options: Options): Handle
	assert(#options.Items > 0, "useSelection needs at least one item")
	assert(type(options.Value) == "function", "useSelection is controlled: Value must be a getter")

	local mode: SwitchMode = options.SwitchMode or "sync"
	local stillAnimating = options.StillAnimating
	local value = options.Value

	--- The item that is actually open. Under `sync` it tracks `Value` exactly;
	--- under `wait` it lags by one exit animation.
	local current = value()
	--- The last request seen, so a CHANGE in `Value` can be detected on read.
	local requested = current
	--- The item on its way out, if any. Explicit rather than derived: ms-53 D6
	--- found that waiting on a CATEGORY rather than on the specific thing being
	--- closed lets an unrelated stuck member block a promotion.
	local leaving: string? = nil

	local function exitSettled(id: string): boolean
		if not stillAnimating then
			return true
		end
		return not stillAnimating(id)
	end

	--- Advance the machine. Called from every read, which is what makes this work
	--- without a clock: the thing that asks "should I render?" is the thing that
	--- moves it along -- the same pull-based contract `Presence` documents.
	---
	--- IT IS ALSO WHAT MAKES IT REACTIVE. Both ways in are reactive reads: `Value`
	--- is the caller's source, and `exitSettled` reads the motion. So a promotion
	--- always happens inside an evaluation that already depends on whatever
	--- caused it.
	local function pump()
		local want = value()
		if want ~= requested then
			requested = want
			if want ~= current then
				leaving = current
				if mode == "sync" then
					--- The incoming panel enters immediately and the outgoing one
					--- animates out underneath it.
					current = want
				end
			end
		end

		if requested ~= current and (not leaving or exitSettled(leaving)) then
			leaving = nil
			current = requested
		end

		if leaving and exitSettled(leaving) then
			leaving = nil
		end
	end

	local function phase(id: string): Phase
		pump()
		--- LEAVING IS CHECKED FIRST, and it has to be. Under `wait` the outgoing
		--- item is still `current` -- that is what `wait` means -- so asking about
		--- `current` first would report it `open` for the whole of its own exit,
		--- and a bar reading the phase would show two items lit.
		if id == leaving then
			return "closing"
		end
		if id == current then
			return "open"
		end
		if id == requested then
			--- Asked for, not yet arrived. Only reachable under `wait`.
			return "pending"
		end
		return "closed"
	end

	--- One `Presence` per item, cached. Cached because a handle carries the
	--- `hasEntered` and `exitFinished` latches: rebuilding it per read would reset
	--- them every frame and delete every exit animation in the group.
	local presences: { [string]: Presence.Handle } = {}
	local function presenceFor(id: string): Presence.Handle
		local existing = presences[id]
		if existing then
			return existing
		end
		local handle = Presence.new({
			--- `open` ONLY -- not `open or pending`. A pending panel is one that
			--- has been asked for and is deliberately being held back; rendering it
			--- would make `wait` indistinguishable from `sync`, which is the exact
			--- defect ms-53 D6 found in the screen-level mode.
			Present = function()
				return phase(id) == "open"
			end,
			StillAnimating = if stillAnimating
				then function()
					return stillAnimating(id)
				end
				else nil,
			Inherit = options.Inherit,
		})
		presences[id] = handle
		return handle
	end

	--- BUILT AND PRIMED UP FRONT, not on first ask. `Presence` decides whether an
	--- element owes an exit animation from whether it has ever been seen present,
	--- and it can only see that on a READ. Built lazily, the item that was open at
	--- construction gets its handle only once something asks about it -- which, if
	--- the first ask comes after a switch, is a handle that never saw it open and
	--- so skips its exit entirely.
	---
	--- It cost two cases in this module's own suite to find, and in an application
	--- it would not have shown up at all: every panel binds `ShouldRender` to
	--- `Visible` at mount, so the first read always happens while the default item
	--- is still open. A latent trap that only fires for a caller who asks in a
	--- different order is exactly the kind this milestone keeps finding.
	for _, id in ipairs(options.Items) do
		presenceFor(id).ShouldRender()
	end

	return {
		Value = function(): string
			pump()
			return current
		end,
		Requested = function(): string
			pump()
			return requested
		end,
		Select = function(id: string)
			if options.OnChange then
				options.OnChange(id)
			end
		end,
		Phase = phase,
		ShouldRender = function(id: string): boolean
			return presenceFor(id).ShouldRender()
		end,
		PresenceFor = presenceFor,
	}
end

--[[
	THE CONTEXT — so a panel does not have to be handed the group by hand.

	`ThemeProvider` already establishes this idiom in the repo, and the reason to
	follow it here is the same reason Framer's orchestration works: a child that
	must be told its own identity by every call site is a child nobody wires up.
	Three stagger implementations went unused in this repo for exactly that.

	IT IS OPTIONAL IN BOTH DIRECTIONS. `use()` answers nil outside a provider, so
	a panel with no group renders unconditionally rather than disappearing — which
	is what keeps every existing flat-table call site working.
]]
local Deps = require("./Deps")
local vide = Deps.vide

local SelectionContext = if vide and vide.context then vide.context(nil :: any) else nil

--- Build `fn`'s children inside this group. Anything they create can find the
--- handle with `use()`, however deep.
function useSelection.Provide(handle: Handle, fn: () -> any): any
	if not SelectionContext then
		--- No reactive core (a host without vide). Children still build; they
		--- simply cannot find the group, which degrades to "render everything"
		--- rather than to an error.
		return fn()
	end
	return (SelectionContext :: any)(handle, fn)
end

--- The enclosing group, or nil.
function useSelection.use(): Handle?
	if not SelectionContext then
		return nil
	end
	return (SelectionContext :: any)()
end

return useSelection
