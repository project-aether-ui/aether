--!strict
--[[
	tests/support/runner/suite_results.luau — share ONE suite run between the test runner
	and the gates that assert on it (ms-47, 2026-08-08).

	THE PROBLEM. verify_37m4 and verify_37m5 each spawn full e2e suites of their own —
	CompoundFeel, HullJunction, ManifoldHull, HullAdjacency, CompoundPerf, and more. Those
	same suites also run in tests/run.luau. Verify everything before a push and the heavy
	physics work happens TWICE: once in the runner, at jobs=16, and again inside the gates,
	serially. Measured, that duplicated half is ~1200 s of the ~1340 s a full gate sweep
	costs. It is the single largest cost in verification, and it buys nothing.

	THE PART THAT IS EASY TO GET WRONG. The obvious fix — cache suite verdicts to a file and
	let gates read it — quietly converts a gate into a gate-shaped thing that asserts on
	history. A stale manifest means a gate passes because the suite passed BEFORE the change
	that broke it. That is precisely the failure mode this milestone has been unpicking:
	something that reads as coverage while enforcing nothing.

	Comparing git HEAD does not save it either, because the tree is usually dirty during
	development, and "dirty" says nothing about WHICH edits.

	THE CONTRACT. No cache, no staleness window, no expiry heuristics: a manifest is trusted
	ONLY inside the sweep that produced it.

	  * tests/gates/run.luau --with-suites mints a random token, runs tests/run.luau once
	    with --emit-results, and exports SPEKTR_SWEEP_TOKEN + SPEKTR_SUITE_RESULTS to every
	    gate it spawns.
	  * A gate asks verdictOf(path). The token in the file must equal the token in the
	    environment, or the answer is nil.
	  * nil means "I do not know" — and every caller must then run the suite itself.

	So the file is meaningless to anything but the live sweep that wrote it: a leftover
	manifest from an hour ago carries an old token and is ignored. A gate run on its own,
	with no token in the environment, behaves exactly as it always did. Reuse is an
	optimisation the orchestrator can offer, never an assumption a gate makes.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

export type SuiteRecord = { name: string, path: string, ok: boolean }
export type Manifest = { token: string, suites: { SuiteRecord } }

local SuiteResults = {}

SuiteResults.TOKEN_ENV = "SPEKTR_SWEEP_TOKEN"
SuiteResults.PATH_ENV = "SPEKTR_SUITE_RESULTS"

--- A token for one sweep. Not cryptographic — it only has to differ from the last one, so a
--- manifest left on disk by an earlier run can never be mistaken for this run's.
function SuiteResults.mintToken(): string
	return `{os.time()}-{math.random(100000, 999999)}`
end

function SuiteResults.write(path: string, token: string, suites: { SuiteRecord })
	local manifest: Manifest = { token = token, suites = suites }
	fs.writeFile(path, serde.encode("json", manifest, true))
end

--- The live manifest, or nil if there is not one for THIS sweep.
local function load(): Manifest?
	local token = process.env[SuiteResults.TOKEN_ENV]
	local path = process.env[SuiteResults.PATH_ENV]
	if not token or not path or token == "" or path == "" then
		return nil -- no sweep in progress: gates run their own suites, as always
	end
	if not fs.isFile(path) then
		return nil
	end
	local ok, decoded = pcall(function()
		return serde.decode("json", fs.readFile(path))
	end)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local m = decoded :: Manifest
	-- THE WHOLE GUARANTEE IS THIS COMPARISON. A manifest from any other run — an hour ago,
	-- or a sweep that crashed halfway — carries a different token and is refused.
	if m.token ~= token then
		return nil
	end
	return m
end

--- `true`/`false` if THIS sweep already ran the suite at `path`; nil if it did not, in which
--- case the caller MUST run it. Never guess from a nil — a missing record means unknown, not
--- passing.
function SuiteResults.verdictOf(path: string): boolean?
	local m = load()
	if not m then
		return nil
	end
	for _, s in ipairs(m.suites) do
		if s.path == path then
			return s.ok
		end
	end
	return nil
end

function SuiteResults.active(): boolean
	return load() ~= nil
end

return SuiteResults
