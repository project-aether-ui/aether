--!strict
--!tier math
--[=[
	The measurement cache, and the two ways it could become a correctness bug
	(ms-52 M14).

	WHY IT EXISTS
	Layout re-measures every string on every frame, and each painter that
	positions text measures again. On shop that is 82 nodes measured at least
	twice a frame -- 0.829 ms -- almost always to the same answer.

	WHY IT IS DANGEROUS
	A cache is only ever as correct as its invalidation, and this one sits under
	the seam that ms-52 M7 broke: that host measured with a bundled advance table
	while painting with Segoe UI Symbol, 21% out on a narrow run, with
	`AutomaticSize` sizing to a width nothing would draw. A cache that survived a
	provider swap would reintroduce exactly that, and no pixel check could see it
	-- the widths would be internally consistent and wrong.

	So most of what is asserted here is the cache MISSING when it must, not
	hitting when it can. A cache that never hits is merely slow; a cache that hits
	when it should not is broken.
]=]
local T = require("@testkit")
local Text = require("../src/host/Text")

local function testCacheStopsCallingTheProvider()
	Text._reset()
	local calls = 0
	Text.SetProvider(function(s: string, size: number): (number, number)
		calls += 1
		return #s * size, size * 2
	end, "test")

	local w1, h1 = Text.Measure("hello", 10, nil)
	assert(w1 == 50 and h1 == 20, `the provider's answer should come back, got {w1}x{h1}`)
	assert(calls == 1, `one measurement should call the provider once, got {calls}`)

	local w2, h2 = Text.Measure("hello", 10, nil)
	assert(w2 == 50 and h2 == 20, `a cached answer must match, got {w2}x{h2}`)
	assert(calls == 1, `the repeat must not reach the provider, but it was called {calls} times`)

	--- A different SIZE is a different measurement, not the same one scaled.
	Text.Measure("hello", 20, nil)
	assert(calls == 2, `a new size must be measured, provider called {calls} times`)

	Text.Measure("hell", 10, nil)
	assert(calls == 3, `a new string must be measured, provider called {calls} times`)
	Text._reset()
end

local function testSwappingTheProviderForgetsEverything()
	Text._reset()
	Text.SetProvider(function(s: string): (number, number)
		return #s * 100, 10
	end, "first")
	local before = Text.Measure("ab", 12, nil)
	assert(before == 200, `the first provider should answer 200, got {before}`)
	assert(Text.CacheSize() > 0, "the measurement should have been cached")

	--- `SetProvider` never clobbers an installed provider, so clearing it first is
	--- how a host actually swaps one -- and it is the path that must forget.
	Text.SetProvider(nil)
	assert(Text.CacheSize() == 0, `removing the provider must clear the cache, {Text.CacheSize()} left`)

	Text.SetProvider(function(s: string): (number, number)
		return #s * 7, 3
	end, "second")

	--- THE ASSERTION THIS SUITE EXISTS FOR. Same string, same size, different
	--- provider: the answer must come from the NEW one. A surviving cache returns
	--- 200 here, and every layout built on it is wrong in a way no pixel
	--- comparison could detect.
	local after = Text.Measure("ab", 12, nil)
	assert(after == 14, `after a provider swap the NEW metrics must answer, got {after}`)
	Text._reset()
end

local function testFontsDoNotShareAnEntry()
	Text._reset()
	Text.SetProvider(function(s: string, size: number, font: string?): (number, number)
		--- A face whose glyphs are twice as wide. Two fonts answering differently
		--- for one string is the whole reason `font` is part of the key.
		return (if font == "wide" then #s * 20 else #s * 10), size
	end, "test")

	local narrow = Text.Measure("abc", 12, nil)
	local wide = Text.Measure("abc", 12, "wide")
	assert(narrow == 30, `the default face should measure 30, got {narrow}`)
	assert(wide == 60, `the wide face should measure 60, got {wide}`)
	--- And back again, from the cache this time rather than the provider.
	local again = Text.Measure("abc", 12, nil)
	assert(again == 30, `the default face must not inherit the wide entry, got {again}`)
	Text._reset()
end

local function testAFailedProviderIsNotCached()
	Text._reset()
	local failing = true
	local calls = 0
	Text.SetProvider(function(): (number, number)
		calls += 1
		if failing then
			error("no font loaded yet")
		end
		return 999, 111
	end, "test")

	--- It falls back rather than propagating: a layout solve that threw because a
	--- font was unavailable would take down the frame.
	local fallback = Text.Measure("abc", 12, nil)
	assert(fallback ~= 999, "a throwing provider must not appear to have answered")
	assert(calls == 1, `the provider should have been attempted, called {calls} times`)

	--- AND IT MUST TRY AGAIN. Caching the fallback would freeze an approximation
	--- in for the life of the process, so a font that loads a moment later would
	--- never be measured with.
	failing = false
	local real = Text.Measure("abc", 12, nil)
	assert(real == 999, `once the provider works its answer must be used, got {real}`)
	assert(calls == 2, `the failed measurement must not have been cached; calls {calls}`)
	Text._reset()
end

local function testTheCacheIsBounded()
	Text._reset()
	Text.SetProvider(function(s: string): (number, number)
		return #s, 1
	end, "test")

	--- Text is not a closed set: a field being typed into produces a new string
	--- per keystroke, so an unbounded cache grows for as long as the program runs.
	for i = 1, 6000 do
		Text.Measure(`generated string number {i}`, 12, nil)
	end
	local held = Text.CacheSize()
	assert(held <= 4096, `the cache must be bounded, it holds {held}`)
	assert(held > 0, "a bounded cache should still be holding the recent entries")

	--- Still correct after a wholesale clear.
	local w = Text.Measure("abcd", 12, nil)
	assert(w == 4, `measurement must survive eviction, got {w}`)
	Text._reset()
end

local function testResetClearsTheCache()
	Text._reset()
	Text.SetProvider(function(): (number, number)
		return 42, 42
	end, "test")
	Text.Measure("x", 1, nil)
	assert(Text.CacheSize() > 0, "a measurement should be held before the reset")
	Text._reset()
	assert(Text.CacheSize() == 0, `_reset must clear the cache, {Text.CacheSize()} left`)
	--- Otherwise one suite's measurements leak into the next, and a test that
	--- installs its own provider silently reads the previous suite's numbers.
	assert(not Text.HasProvider(), "_reset must also clear the provider")
end

T.test("a repeated measurement does not reach the provider", testCacheStopsCallingTheProvider, "math")
T.test("swapping the provider forgets every measurement", testSwappingTheProviderForgetsEverything, "math")
T.test("two fonts do not share a cache entry", testFontsDoNotShareAnEntry, "math")
T.test("a provider that throws is not cached", testAFailedProviderIsNotCached, "math")
T.test("the cache is bounded", testTheCacheIsBounded, "math")
T.test("_reset clears the cache as well as the provider", testResetClearsTheCache, "math")

return T.run("TextMetricsCache")
