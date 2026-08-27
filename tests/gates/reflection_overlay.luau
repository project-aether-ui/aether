--!strict
--[[
	Properties the LIVE ENGINE has and lune's bundled reflection database does not.

	WHY THIS EXISTS (ms-44)
	`verify_property_names` opens with "Roblox's own reflection database is the authority,
	and lune ships it." The second half is true; the first is not. lune ships a SNAPSHOT,
	and the engine moves. When the snapshot lags, the gate reports properties that exist as
	defects — and this repo has already paid for that:

	  ms-43 M64 recorded "16 real defects in StudioInterfaceSuite ... UICorner has exactly
	  ONE property, CornerRadius — those blocks throw whenever they mount."

	They do not throw. ms-44's engine tier asked Roblox directly:

	    CornerRadius       read=true write=true
	    TopLeftRadius      read=true write=true
	    TopRightRadius     read=true write=true
	    BottomLeftRadius   read=true write=true
	    BottomRightRadius  read=true write=true

	All five. The code was correct the whole time. Worse, the gate SKIPPED both Studio
	packages because of those readings, so an entire layer went unguarded on a false
	premise — a gate that is wrong in the permissive direction is worse than no gate,
	because it is trusted.

	HOW TO ADD AN ENTRY, and the rule is strict: **engine evidence only.** Never add a
	property because it looks right or because a doc page mentions it. Ask the engine:

	    lune run tests/run.luau --env=engine reflection

	and pin the result in `tests/engine/reflection/init.luau` in the same change. That
	suite is the PROOF for every row below; this file is only the lookup. If the two ever
	disagree, the engine wins and this file is stale.

	This overlay only ever ADDS. It cannot mask a genuinely bad property name, because a
	name absent from both the database and this table still fails.
]]

return {
	--- Per-corner radii. Verified against the live engine 2026-08-03 (ms-44 M6c); pinned
	--- by `tests/engine/reflection` -> "UICorner DOES have per-corner radii".
	UICorner = {
		TopLeftRadius = true,
		TopRightRadius = true,
		BottomLeftRadius = true,
		BottomRightRadius = true,
	},
}
