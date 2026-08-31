--!strict
--!tier math
-- Roblox datatypes, same bootstrap the physics suites use (ms-43 M30). Needed
-- because this suite had never actually executed: it returned an uninvoked
-- function, so nothing ever touched Color3 or UDim2 to discover they were nil.
--- The value vocabulary, from the HOST (ms-52 M6).
---
--- This was a hand-written block per suite -- `local rbx = require("@lune/roblox")`
--- then five to nine global assignments -- which is the copy-per-file the repo
--- already carried, and which pinned every suite to Lune. On zune `@lune` is not
--- a valid alias, so these files could not load at all.
---
--- `InstallVocabulary` is the one place that answers this. It still resolves to
--- Lune's real Roblox types where they exist, so nothing about running under Lune
--- changes; on a runtime without them it installs the pure-Luau vocabulary.
require("../src/api").Host.detect().InstallVocabulary()
local InputSink = require("../src/InputSink")

-- Self-executing: the runner spawns `lune run <suite>` and judges by EXIT CODE
-- alone, so a suite that merely RETURNS a function passes without running a
-- single assertion (ms-43 M30).
local function run()
	assert(InputSink ~= nil, "InputSink module exists")

	-- A smoke test, and it is worth being clear about what it can and cannot
	-- prove. Headless there is no engine, so this asserts nothing about layout or
	-- hit-testing — only that the module LOADS and its component function runs to
	-- completion. That is a low bar the suite was not clearing: it built a sink,
	-- asserted nothing, and could not have run at all (vide.create was absent
	-- from the shim), which no one discovered because it never executed.
	local sink = InputSink({
		Modal = true,
		OnDismiss = function() end,
	})
	assert(sink ~= nil, "InputSink constructs without an engine")

	-- Real behaviour lives in InputScope (M16), which supersedes this primitive
	-- and has a suite that resolves arbitration headlessly.
end

-- ms-44: migrated onto testkit. This suite had no harness — bare asserts inside named
-- functions, invoked at the bottom of the file. That is the ms-43 M30 shape: delete an
-- invocation and the file still exits 0 and still reads as coverage. Registered tests
-- make that a VACUOUS failure instead, and give each one a name, a time and a tier in
-- the ##testkit JSON.
local T = require("@testkit")
T.test("InputSink", run, "math")

return T.run("InputSink")
