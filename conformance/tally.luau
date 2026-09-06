--!strict
--[[
	The shared module tally.luau is the source both runners read to produce their
	suite summaries, with native Rust retained in Dew as an explicit fallback when
	running detached from Aether.
]]

export type CaseResult = {
	name: string,
	provenance: string,
	ok: boolean,
	unsupported: boolean?,
	divergent: boolean?,
	undecodable: boolean?,
	detail: string?,
	note: string?,
}

export type SuiteSummary = {
	total: number,
	passed: number,
	executable: number,
	verified_against_roblox: number,
	divergent: number,
	open_questions: number,
	unsupported: number,
	failed: number,
	disagreed_open: number,
	undecodable: number,
	formatted: string,
}

local tally = {}

function tally.summarize(results: { CaseResult }): SuiteSummary
	local total = #results
	local unsupported = 0
	local failed = 0
	local divergent = 0
	local disagreed_open = 0
	local passed = 0
	local undecodable = 0

	for _, r in ipairs(results) do
		if r.undecodable then
			undecodable += 1
		elseif r.unsupported or r.note == "unsupported" then
			unsupported += 1
		elseif r.ok then
			passed += 1
			if r.divergent or r.provenance == "divergent" then
				divergent += 1
			end
		elseif r.provenance == "asserted" then
			disagreed_open += 1
		else
			failed += 1
		end
	end

	local verified_against_roblox = 0
	local open_questions = 0

	for _, r in ipairs(results) do
		local is_unsupported = r.unsupported or r.note == "unsupported"
		if not is_unsupported and not r.undecodable then
			if r.provenance == "roblox" then
				verified_against_roblox += 1
			elseif r.provenance == "asserted" then
				open_questions += 1
			end
		end
	end

	local executable = total - unsupported
	local undec_str = if undecodable > 0 then `, {undecodable} undecodable` else ""
	local formatted = string.format(
		"CONFORMANCE: %d of %d passing (%d verified against Roblox, %d documented gaps, %d open questions, %d unsupported%s)",
		passed,
		executable,
		verified_against_roblox,
		divergent,
		open_questions,
		unsupported,
		undec_str
	)

	return {
		total = total,
		passed = passed,
		executable = executable,
		verified_against_roblox = verified_against_roblox,
		divergent = divergent,
		open_questions = open_questions,
		unsupported = unsupported,
		failed = failed,
		disagreed_open = disagreed_open,
		undecodable = undecodable,
		formatted = formatted,
	}
end

function tally.open_questions_note(summary: SuiteSummary): string?
	if summary.open_questions == 0 then
		return nil
	end
	local disagree_str = if summary.disagreed_open > 0
		then string.format(", %d of which this implementation disagrees with", summary.disagreed_open)
		else ""
	return string.format(
		"  %d case(s) state a belief nobody has checked in Studio%s. See conformance/README.md for how to verify one.",
		summary.open_questions,
		disagree_str
	)
end

return tally
