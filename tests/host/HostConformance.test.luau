--!strict
--!tier math
--[[
	Shim conformance — the SAME assertions against the shim and against real vide.

	WHY (ms-44 M5, M5b)
	Six packages hand-rolled a headless vide stand-in and drifted to three fidelity levels:
	M76's "create records the class" reached 3 of 6, M43's "effect actually runs" reached 1
	of 6. Consolidating to one shim removed the drift. This file stops the ONE shim from
	regressing — and, since M5b, from LYING.

	Those are different failures. A suite that only ever sees the shim catches a REGRESSION
	(someone changes the shim) but never catches a MISCONCEPTION (the shim was always wrong,
	and every test written against it inherited the error). Only running the same assertions
	against the real thing catches the second.

	So: under lune this exercises `Aether.Host.Headless`; mounted into a Roblox place it
	exercises real vide. Every assertion below is something BOTH must satisfy — where the
	host is knowingly shallower (no layout, no spring dynamics, no rendering) there is simply
	no assertion, and Headless.luau states those limits.

	Mounting real vide needs NO hardcoded version: pesde's generated `vide.luau` resolves
	`.pesde/centau_vide@<version>/vide` by FindFirstChild at runtime and is rewritten on
	every install. `tests/run.luau` mounts the directory; this file just requires
	`vendor.vide`.
]]

local isRoblox = typeof(script) == "Instance"

local T, vide, classOf
if isRoblox then
	local RS = game:GetService("ReplicatedStorage")
	T = require(RS.testkit)
	vide = require(RS.vendor.vide)
	classOf = function(node: any): string?
		return if typeof(node) == "Instance" then node.ClassName else nil
	end
else
	T = require("@testkit")
	--- ms-51 M20: Aether's headless HOST, not testkit's VideShim, which is deleted.
	---
	--- The suite's ARGUMENT is unchanged and is why it still exists. A suite that
	--- only ever sees the stand-in catches a REGRESSION but never a MISCONCEPTION —
	--- the stand-in being wrong all along, with every test written against it
	--- inheriting the error. Only running the same assertions against the real
	--- thing catches the second, and M5b found exactly that.
	---
	--- What changed is that half the risk is gone by construction: the host takes
	--- vide's REAL reactive core, so `source`, `effect` and `derive` cannot
	--- disagree with the engine. What remains, and is what this now guards, is the
	--- half the host still supplies itself — `create` over mock instances against
	--- `create` over real Instances.
	local Aether = require("../../src")
	local host = Aether.Host.Headless.new()
	vide = host
	classOf = host.classOf
end

--- Real vide requires a reactive ROOT for create/effect/derive; the shim does not care.
--- Wrapping both makes the paths identical instead of special-casing one.
local function inRoot(body: () -> ())
	vide.root(function()
		body()
		return nil
	end)
end

T.describe("source", function()
	T.it("reads its default", { tier = "math" }, function()
		assert(vide.source(1)() == 1, "reads the default")
	end)

	T.it("writes, then reads back", { tier = "math" }, function()
		local s = vide.source(1)
		s(5)
		assert(s() == 5, `got {tostring(s())}`)
	end)

	T.it("ZERO arguments reads; a nil ARGUMENT writes", { tier = "math" }, function()
		-- FOUND BY M5b, and this assertion originally had it BACKWARDS — it asserted the
		-- shim's behaviour (`s(nil)` is a read) and the engine rejected it. Real vide uses
		-- `select("#", ...)`, so `s()` reads and `s(nil)` writes nil.
		--
		-- The distinction is not academic: a component calling `s(maybeNil)` cleared the
		-- source in-engine and silently did nothing headlessly, and no suite could have
		-- caught it because every suite was written against the shim.
		local s = vide.source("kept")
		assert(s() == "kept", "no arguments is a read")
		s(nil)
		assert(s() == nil, `a nil argument writes nil, got {tostring(s())}`)
	end)
end)

T.describe("derive", function()
	T.it("reflects later source writes", { tier = "math" }, function()
		inRoot(function()
			local s = vide.source(2)
			local d = vide.derive(function()
				return s() * 10
			end)
			assert(d() == 20, `initial, got {tostring(d())}`)
			s(3)
			assert(d() == 30, `after write, got {tostring(d())}`)
		end)
	end)
end)

T.describe("create", function()
	T.it("produces a node of the requested class (ms-43 M76)", { tier = "math" }, function()
		-- Three of six copies DISCARDED the class, so their suites could not assert what an
		-- element IS — and the outer-canvas jitter fix was exactly "this must be a
		-- ScrollingFrame, not a Frame".
		inRoot(function()
			local node = vide.create("ScrollingFrame")({})
			assert(classOf(node) == "ScrollingFrame", `got {tostring(classOf(node))}`)
		end)
	end)

	T.it("does not confuse two classes", { tier = "math" }, function()
		inRoot(function()
			local a = vide.create("Frame")({})
			local b = vide.create("TextLabel")({})
			assert(classOf(a) == "Frame" and classOf(b) == "TextLabel", "independent")
		end)
	end)

	T.it("applies the properties it is given", { tier = "math" }, function()
		inRoot(function()
			local node = vide.create("Frame")({ Name = "Applied" })
			assert((node :: any).Name == "Applied", `got {tostring((node :: any).Name)}`)
		end)
	end)
end)

T.describe("effect", function()
	T.it("RUNS its body (ms-43 M43)", { tier = "math" }, function()
		-- Five of six copies had no `effect` key at all. Its inertness is what let three
		-- use-before-declaration bugs reach Studio: the body never executed headlessly, so
		-- a closure reading a nil upvalue looked fine until it ran in-engine.
		local ran = false
		inRoot(function()
			vide.effect(function()
				ran = true
			end)
		end)
		assert(ran, "an inert effect hides every bug inside it")
	end)
end)

T.describe("spring", function()
	T.it("returns a getter", { tier = "math" }, function()
		inRoot(function()
			local get = vide.spring(vide.source(7))
			assert(type(get) == "function", `got {type(get)}`)
		end)
	end)

	T.it("SECOND RETURN VALUE — the shim claims a settings handle; does vide?", { tier = "math" }, function()
		-- THE ASSERTION THIS FILE EXISTS FOR (ms-44 M5b).
		--
		-- The shim returns `(getter, settingsHandle)` and its comment claims that matches
		-- "vide's real signature (ms-43 M46)". M46's seeding behaviour was built on that
		-- belief and nothing ever checked it against vide. If real vide returns only the
		-- getter, the shim is not merely shallow — it is WRONG, and a capability M46 depends
		-- on does not exist.
		--
		-- Asserted identically in both environments, so the answer is data rather than
		-- opinion. If this fails in-engine, that is the finding, not a broken test.
		inRoot(function()
			local _, second = vide.spring(vide.source(1))
			assert(
				type(second) == "function",
				`spring's second return is {type(second)}, not a function — `
					.. `the shim's two-value contract does not hold here`
			)
		end)
	end)
end)

T.describe("root", function()
	T.it("returns DESTROY first, then the body's results", { tier = "math" }, function()
		-- Also found by M5b with the assertion backwards. Real signature:
		--     root<T...>(fn: (destroy: () -> ()) -> T...): (() -> (), T...)
		-- The shim returned only the value, so `local x = vide.root(fn)` bound the value
		-- headlessly and the destroy function in-engine.
		local destroy, out = vide.root(function()
			return "built"
		end)
		assert(type(destroy) == "function", `destroy comes first, got {type(destroy)}`)
		assert(out == "built", `then the body's result, got {tostring(out)}`)
	end)
end)

return T.run(if isRoblox then "HostConformance(engine)" else "HostConformance(headless)")
