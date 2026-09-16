--!strict
--[[
	tests/gates/source_scan.luau — shared helpers for gates that scan SOURCE TEXT.

	WHY THIS EXISTS. `stripComments` had been written FIVE times (verify_35m5,
	verify_37m1, verify_no_versioned_vendor_paths, verify_test_inventory, and the gate
	runner). Two of those copies arrived only after the gate had already shipped a false
	positive, because the lesson does not travel with a copy — it has to be relearned per
	file, and it was, twice in one day (ms-47, 2026-08-08):

	  * verify_35m5 read the ms-44 header in prism-physics/src/init.luau, which QUOTES the
	    old versioned vendor path as the counter-example it documents removing, and reported
	    the fix as the defect. It took verify_36m1 red behind it.
	  * verify_37m1 read `-- ... (see ConvexSolver.HullFace)` in RayCast.luau and reported an
	    architecture-boundary breach over a cross-reference in prose.

	A gate that counts DOCUMENTATION as evidence is the specific failure this module exists
	to make unrepeatable: one implementation, one place to fix, and the reason attached to it.

	Deliberately NOT in pkgs/testkit: this is repo-shaped tooling for this repo's gates, and
	testkit's whole contract (Discover.luau) is that it knows no repo shape.
]]

local SourceScan = {}

--- Luau source with comments blanked out — long `--[[ ]]`, long-bracket `--[=[ ]=]`, and
--- line comments — so a text scan measures CODE.
---
--- Replaced with a space rather than deleted, so byte offsets do not collapse two tokens
--- into one (`a --[[x]] b` must not become `ab`).
---
--- Known limit, and it has never mattered here: a `--` inside a string literal is treated as
--- a comment. Every caller scans for require paths, identifiers or namespace prefixes, none
--- of which live in strings that contain `--`. If a gate ever needs that distinction it
--- wants a real lexer, not a bigger regex.
function SourceScan.stripComments(src: string): string
	local out = string.gsub(src, "%-%-%[%[.-%]%]", " ")
	out = string.gsub(out, "%-%-%[=%[.-%]=%]", " ")
	out = string.gsub(out, "%-%-[^\n]*", " ")
	return out
end

--- The same removal, with every line still where it was.
---
--- `stripComments` replaces a long comment with ONE space, which is right for a
--- scan that asks whether a pattern occurs anywhere in a file and wrong for one
--- that has to say where: a twenty-line header collapses to a single character
--- and every line number after it is off by twenty. A gate that reports evidence
--- needs the offsets to survive.
---
--- Kept beside `stripComments` rather than replacing it. The two differ only in
--- what they substitute, and the header above is the record of what five copies
--- of one scanner cost; this is a sixth call site, not a sixth implementation.
function SourceScan.blankComments(src: string): string
	local function blank(run: string): string
		return (string.gsub(run, "[^\n]", " "))
	end
	local out = string.gsub(src, "%-%-%[%[.-%]%]", blank)
	out = string.gsub(out, "%-%-%[=%[.-%]=%]", blank)
	out = string.gsub(out, "%-%-[^\n]*", blank)
	return out
end

--- String LITERALS blanked, so a scan measures code rather than data.
---
--- Same length out as in, so this composes with `blankComments` without moving
--- anything. A long string spanning lines keeps its newlines for the same reason.
function SourceScan.blankStrings(src: string): string
	local function blank(run: string): string
		return (string.gsub(run, "[^\n]", " "))
	end
	local out = string.gsub(src, "%[%[.-%]%]", blank)
	out = string.gsub(out, '"[^"\n]*"', blank)
	out = string.gsub(out, "'[^'\n]*'", blank)
	return out
end

return SourceScan
