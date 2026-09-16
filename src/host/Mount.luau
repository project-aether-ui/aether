--!strict
--[[
	Mounting: open a reactive scope, build a tree in it, attach it.

	    Aether.mount(function()
	        return Aether.create "Frame" { ... }
	    end, root)

	THE SCOPE IS WHY THIS TAKES A FUNCTION rather than a finished tree. vide
	refuses `derive` and `effect` outside a stable scope, so a caller that built
	its tree first and handed it over would have built it outside one. Passing the
	builder in means the scope is always there and no caller has to know.

	`parent` is optional: a caller that wants to place the tree itself, or is
	building one that is never parented, gets it back and does as it likes.
]]

local Deps = require("../Deps")

local Mount = {}

--- Build a tree inside a reactive scope and parent it into `parent`.
---
--- `build` is called ONCE, with whatever arguments follow `parent`, and the tree
--- it returns is the return value here.
function Mount.mount(build: (...any) -> any, parent: any?, ...: any): any
	local tree: any
	local args = table.pack(...)

	Deps.root(function()
		tree = build(table.unpack(args, 1, args.n))
		return tree
	end)

	if parent ~= nil then
		tree.Parent = parent
	end

	return tree
end

return Mount
