--!strict
--[[
	Aether's public surface.

	THE TABLE ITSELF IS IN `api.luau`, and this file only forwards to it. That is
	not organisation for its own sake — it is the one shape that is reachable from
	every host:

	  * ROBLOX resolves a folder require to its `init`, so `require(Aether)` lands
	    here and gets the same table.
	  * A STRING RESOLVER cannot reach this file through an alias. Pointing an
	    alias at the `src` directory loads this module but keeps `src` as its
	    IDENTITY, so every `./x` inside it resolves one level too high; and
	    `@aether/init` never resolves at all, because a require whose last
	    component is `init` deliberately skips the extension search that would
	    find `init.luau`.
	  * `@aether/api` has neither problem: an ordinary named module, with an
	    ordinary directory.

	Found by an off-engine host failing on `./Icon/src/Icon` — a path that is
	correct, from a file that could not tell where it was.
]]

return require("./api")
