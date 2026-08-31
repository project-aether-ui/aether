--!strict
--[[
	Aether · host/Text — how wide is this string, answered synchronously.

	WHY (ms-52 M1)
	`AutomaticSize`, `TextScaled` and `TextBounds` are used across spektr/button,
	spektr/scrollbar, VirtualList and spektr/surface. Off-engine an element sized by
	its content resolved to a ZERO rect, so a real menu rendered as a stack of empty
	rows and nothing downstream of that could be judged.

	THE CONSTRAINT THAT SHAPES ALL OF THIS: `Layout.Solve` runs inside a frame and
	returns synchronously. It cannot await. A provider that must round-trip to
	answer cannot answer during the solve that needs it — which rules out asking
	the browser mid-solve, however exact that would be.

	So: a synchronous default that is proportional, and a seam for something better.
	The web host registers a provider backed by a cache the browser FILLS
	asynchronously — an unmeasured string falls back to the table, and once the
	browser has reported it the exact value is used from then on. Layout never
	waits, and accuracy converges after the first frame that draws a given string.
	In Roblox the provider is the engine's own synchronous text bounds, so the table
	is never consulted there.

	WHAT THE TABLE IS, stated plainly because the honesty matters more than the
	numbers: per-glyph advance widths as a fraction of em, for a NOMINAL humanist
	sans. It is right to within a few percent for the faces this repo actually uses
	and wrong for anything else. It is NOT `#text * factor` — that was considered
	and rejected in D-text_metrics_provider, because a uniform factor reports a
	plausible width for every string while being wrong about all of them, and this
	milestone's output is a judgement about whether screens render faithfully.
]]

local Text = {}

export type Metrics = (text: string, size: number, font: string?) -> (number, number)

--- Advance width per character, as a fraction of the em square.
---
--- Grouped by the shapes that actually differ. The narrow set (i, l, punctuation)
--- and the wide set (m, w, M, W) are what make two strings of equal LENGTH
--- measure differently, which is the property layout needs and the property a
--- uniform factor cannot provide.
local ADVANCE: { [string]: number } = {}

do
	local function assign(chars: string, width: number)
		for i = 1, #chars do
			ADVANCE[string.sub(chars, i, i)] = width
		end
	end

	assign("ijl.,:;'`|!", 0.26)
	assign(" ", 0.26)
	assign("ftr()[]{}/\\-", 0.33)
	assign("abcdeghknopqsuvxyz0123456789$?+*=<>~^\"", 0.55)
	assign("mw", 0.85)
	assign("ABCDEFGHKLNOPQRSTUVXYZ&#@%", 0.68)
	assign("IJ", 0.32)
	assign("MW", 0.88)
end

--- The default advance for anything not in the table — CJK, emoji, box drawing.
--- One em, because those scripts are broadly square and guessing narrow would
--- collapse a layout that a wide guess merely loosens.
local DEFAULT_ADVANCE = 1.0

--- Line height as a multiple of the font size.
---
--- MEASURED, not assumed. An auto-sized single-line TextLabel at TextSize 20
--- resolves to exactly 30 in Roblox 0.736 -- see the conformance case
--- `one line of text is a fixed multiple of TextSize`.
---
--- This was 1.2 for the life of the file, with a comment asserting that "Roblox's
--- own text bounds report the same shape". Nobody had checked. Every auto-sized
--- TextLabel off-engine was twenty percent short, which is small enough to look
--- like a font difference and large enough to misplace everything below it in a
--- list.
---
--- Whether 1.5 is purely line height or includes something the engine adds is
--- not established. What is established is the resolved height, which is what
--- layout needs.
local LINE_HEIGHT = 1.5

--- Measure with the built-in table. Exposed so a richer provider can defer to it
--- for strings it has no exact answer for yet.
function Text.MeasureDefault(text: string, size: number, _font: string?): (number, number)
	if text == nil or text == "" then
		return 0, size * LINE_HEIGHT
	end

	local widest = 0
	local current = 0
	local lines = 1

	for i = 1, #text do
		local char = string.sub(text, i, i)
		if char == "\n" then
			widest = math.max(widest, current)
			current = 0
			lines += 1
		else
			current += (ADVANCE[char] or DEFAULT_ADVANCE) * size
		end
	end

	widest = math.max(widest, current)
	return widest, lines * size * LINE_HEIGHT
end

local provider: Metrics? = nil
local providerOwner: string? = nil

--- MEASURED STRINGS, REMEMBERED (ms-52 M14).
---
--- Layout re-measures every string on every frame, and so does each painter that
--- positions text. On shop that is 82 nodes measured at least twice a frame,
--- 0.829 ms of it, almost always to the same answer -- the strings on a menu do
--- not change 120 times a second.
---
--- Cached HERE, at the one seam every caller already goes through, rather than in
--- each of them: a per-painter cache would be three caches to invalidate and
--- three chances to answer with a stale width.
---
--- Nested by font, then size, then text, so a lookup costs three table indexes
--- and no string concatenation -- building a composite key would allocate on
--- every hit, which is the cost this exists to remove.
local cache: { [string]: { [number]: { [string]: { number } } } } = {}
local cached = 0

--- A CEILING, because text is not a closed set. A field being typed into produces
--- a new string per keystroke, and an unbounded cache would grow for as long as
--- the program runs. Cleared WHOLESALE rather than evicted least-recently-used:
--- the working set of a screen is small and re-measuring it costs one frame,
--- where tracking recency would cost something on every hit.
local CACHE_LIMIT = 4096

--- Dropped whenever the SOURCE of truth changes.
---
--- Not optional. `SetProvider` swaps the function that answers these questions --
--- GDI's metrics for vello's, say -- and a cache that survived that would serve
--- widths measured with a font nothing is drawing with any more. That is exactly
--- the M7 defect (measure with one font, paint with another: 21% out on a narrow
--- run) reintroduced through the back door.
local function forget()
	cache = {}
	cached = 0
end

--- Register a better source of metrics. Never clobbers one an application already
--- installed — the same rule as Aether.Motion and Aether.Cursor.
function Text.SetProvider(next: Metrics?, owner: string?): boolean
	if next ~= nil and provider ~= nil then
		return false
	end
	provider = next
	providerOwner = if next ~= nil then owner else nil
	forget()
	return true
end

function Text.HasProvider(): boolean
	return provider ~= nil
end

function Text.ProviderOwner(): string?
	return providerOwner
end

--- How wide and tall is this string, in pixels, at this size?
---
--- Always answers, always synchronously. A provider that errors falls back rather
--- than propagating: a layout solve that throws because a font was unavailable
--- would take down the frame, and a slightly wrong rectangle is recoverable where
--- no rectangle is not.
function Text.Measure(text: string, size: number, font: string?): (number, number)
	local fontKey = font or ""
	local byFont = cache[fontKey]
	if byFont then
		local bySize = byFont[size]
		if bySize then
			local hit = bySize[text]
			if hit then
				return hit[1], hit[2]
			end
		end
	end

	local w: number, h: number
	local p = provider
	local measured = false
	if p then
		local ok, pw, ph = pcall(p, text, size, font)
		if ok and type(pw) == "number" and type(ph) == "number" then
			w, h = pw, ph
			measured = true
		end
	end
	if not measured then
		w, h = Text.MeasureDefault(text, size, font)
	end

	--- A FAILED provider call is not cached. It fell back to the bundled table
	--- this time; the next call should get another chance at the real metrics
	--- rather than inherit an approximation for the life of the process.
	if measured or p == nil then
		if cached >= CACHE_LIMIT then
			forget()
		end
		byFont = cache[fontKey]
		if not byFont then
			byFont = {}
			cache[fontKey] = byFont
		end
		local bySize = byFont[size]
		if not bySize then
			bySize = {}
			byFont[size] = bySize
		end
		if bySize[text] == nil then
			cached += 1
		end
		bySize[text] = { w, h }
	end
	return w, h
end

--- How many distinct measurements are held. A test seam: "the cache is working"
--- and "the cache was cleared" are otherwise unobservable from outside.
function Text.CacheSize(): number
	return cached
end

--- Drop every remembered measurement. For a host that changes fonts underneath a
--- provider that has not itself changed.
function Text.ForgetMeasurements()
	forget()
end

--- Testing seam: forget the registration so a suite can install its own.
function Text._reset()
	provider = nil
	providerOwner = nil
	forget()
end

return Text
