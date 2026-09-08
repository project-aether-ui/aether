--!strict
--[[
	Aether · core/TooltipMachine -- when is a tooltip open?

	Layer 1. No reactive library, no engine types, no scheduler of its own.

	WHY IT IS SEPARATE (milestone 7 step D)
	The rule "hover, wait, show; leave, hide, and cancel anything pending" is not
	about vide and not about Roblox. It was written inside `primitives/Tooltip`
	as a `Deps.effect` closing over a `task.delay` thread, which meant the only
	way to ask whether the rule was right was to mount a component.

	This is the shape `@zag-js/*` keeps from `@ark-ui/react`: the machine owns the
	states and the transitions, the binding owns the reactive graph and the tree.

	THE DELAY IS A PORT, NOT A DEPENDENCY. A machine that called `task.delay`
	would be untestable without waiting in real time, and would decide for its
	consumer which scheduler to use. `Schedule` is passed in, returns a cancel
	function, and a test supplies one that fires when it says so. That is the same
	reason a Zag machine declares effects and lets its binding implement them.

	    local m = TooltipMachine.new({ Delay = 0.35, Schedule = schedule })
	    m.Enter()          -- arms the delay
	    m.Leave()          -- cancels it, or closes if it already fired
	    m.IsOpen()         -- false until the delay elapses
	    m.Subscribe(fn)    -- called on every change, with the new state
]]

export type State = "closed" | "waiting" | "open"

--- Arrange for `fn` to run after `seconds`, and return a function that cancels
--- it. A binding passes `task.delay`; a test passes something it controls.
export type Schedule = (seconds: number, fn: () -> ()) -> (() -> ())

export type Options = {
	Delay: number?,
	Schedule: Schedule?,
}

export type TooltipMachine = {
	Enter: () -> (),
	Leave: () -> (),
	IsOpen: () -> boolean,
	GetState: () -> State,
	Subscribe: (listener: (state: State) -> ()) -> (() -> ()),
	Destroy: () -> (),
}

local DEFAULT_DELAY = 0.35

--- WITHOUT A SCHEDULER THE DELAY IS ZERO, and that is a decision rather than an
--- oversight: a caller who supplies none is saying it has no way to wait, and
--- the useful behaviour then is to open rather than to never open.
local function immediate(_seconds: number, fn: () -> ()): () -> ()
	fn()
	return function() end
end

local function new(options: Options?): TooltipMachine
	local opts = options or {}
	local delay = opts.Delay or DEFAULT_DELAY
	local schedule: Schedule = opts.Schedule or immediate

	local state: State = "closed"
	local cancelPending: (() -> ())? = nil
	local listeners: { (state: State) -> () } = {}
	local destroyed = false

	local function notify()
		--- SNAPSHOT, because a listener may unsubscribe itself or a sibling while
		--- being called. The same reason `Motion` snapshots its frame listeners.
		local snapshot = table.clone(listeners)
		for _, listener in ipairs(snapshot) do
			listener(state)
		end
	end

	local function moveTo(next: State)
		if state == next then
			return
		end
		state = next
		notify()
	end

	local function clearPending()
		if cancelPending then
			cancelPending()
			cancelPending = nil
		end
	end

	local self = {} :: TooltipMachine

	function self.Enter()
		if destroyed or state == "open" then
			return
		end
		clearPending()
		moveTo("waiting")
		cancelPending = schedule(delay, function()
			cancelPending = nil
			--- A LATE TIMER MUST NOT OPEN A CLOSED TOOLTIP. `Leave` cancels, but a
			--- scheduler that has already handed the callback to a queue cannot
			--- always be cancelled, so the state is checked again here.
			if not destroyed and state == "waiting" then
				moveTo("open")
			end
		end)
	end

	function self.Leave()
		if destroyed then
			return
		end
		clearPending()
		moveTo("closed")
	end

	function self.IsOpen(): boolean
		return state == "open"
	end

	function self.GetState(): State
		return state
	end

	function self.Subscribe(listener: (state: State) -> ()): () -> ()
		table.insert(listeners, listener)
		return function()
			local i = table.find(listeners, listener)
			if i then
				table.remove(listeners, i)
			end
		end
	end

	function self.Destroy()
		destroyed = true
		clearPending()
		table.clear(listeners)
	end

	return self
end

return { new = new }
