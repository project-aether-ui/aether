--!strict
--[[
	The ceremony a host performs when there is no engine.

	Roblox supplies three things that nothing else does: the value vocabulary as
	globals, a reactive scope around a mounted tree, and a Heartbeat driving
	frames. Off-engine each has to be arranged by hand, and every host was
	arranging them identically -- the `aether` CLI in its entry point, Dew in a
	prelude of its own, and each free to forget one.

	FORGETTING ONE DOES NOT FAIL LOUDLY, which is why this is here rather than in
	each host. Skip `InstallVocabulary` and `UDim2` is nil at the first call site.
	Skip the reactive root and `derive` throws from somewhere unrelated. Skip the
	session and nothing draws. The same argument put the layer root inside
	`Live.Session`: a step every host needs identically, whose omission produces a
	working-looking program, does not belong to the hosts.

	    local mounted = Desktop.Mount(function()
	        return MyComponent({ start = 0 })
	    end, 240, 96)

	    return { Session = mounted.Session }
]]

local Host = require("./Host")
local Live = require("./Live")
local PointerRouter = require("../PointerRouter")

local Desktop = {}

export type Mounted = {
	--- The resolved host, for anything that needs `Clock` or `Scene`.
	Host: any,
	--- What the frame loop drives.
	Session: any,
	--- The tree itself, for a host that wants to inspect it.
	Tree: any,
	--- Whatever `build` returned beside its tree: the transitions a host may
	--- drive from a hotkey, a click or a timer. An empty table if it returned
	--- none, so a caller never has to check.
	Actions: any,
}

--- Build a tree and open a session over it.
---
--- `build` is called ONCE, inside a reactive scope, with whatever extra
--- arguments were passed after `height`. It returns a tree, and optionally a
--- second value carried through as `Actions`.
---
--- THE SCOPE IS WHY THIS TAKES A FUNCTION rather than a finished tree. vide
--- refuses `derive` and `effect` outside a stable scope, so a caller that built
--- its tree first and handed it over would have built it outside one. Passing
--- the builder in means the scope is always there and no caller has to know.
function Desktop.Mount(build: (...any) -> (any, any?), width: number, height: number, ...: any): Mounted
	local host = Host.detect()

	--- A no-op on Roblox, where the engine defines these. Called unconditionally
	--- so this function behaves the same on every host rather than branching on
	--- one.
	host.InstallVocabulary()

	local tree: any
	local actions: any
	local args = table.pack(...)

	host.root(function()
		tree, actions = build(table.unpack(args, 1, args.n))
		return tree
	end)

	return {
		Host = host,
		Session = Live.Session(host, tree, PointerRouter, width, height),
		Tree = tree,
		Actions = actions or {},
	}
end

return Desktop
