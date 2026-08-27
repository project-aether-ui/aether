--!strict
--[[
	Aether · host/Checks — what is wrong with this frame? (ms-53 P3)

	    local Checks = require(".../host/Checks")
	    local findings, coverage = Checks.Run(frame, measure)

	WHY THIS EXISTS RATHER THAN A PIXEL DIFF.

	The obvious way to catch a visual regression is to compare pixels against a
	baseline. This renderer cannot support that cheaply, and the numbers are
	already in: ms-52 measured 76% bit-identical between its own two vello
	backends and 1% of glyph pixels moved by one upstream flag; ms-53 P2 added a
	third axis, because a Linux run and a Windows run load different FONTS. A
	baseline is therefore per-backend, per-version AND per-platform, and a diff
	that flags any of those is a diff people learn to re-run rather than read.

	Owning the display list makes a better question available. These check
	PROPERTIES of the frame, need no baseline at all, run in milliseconds, and
	survive every one of those three axes -- because "this label is wider than its
	box" is true or false regardless of which rasteriser drew it.

	WHAT IS DELIBERATELY NOT CHECKED, and this was measured before it was decided.
	Two obvious candidates are pure noise on real content:

	    entirely outside its clip     128 of shop's 185 nodes
	    entirely off-screen            80 of shop's 185 nodes

	Neither is a defect. A scroll area's content legitimately lives outside its
	clip and outside the viewport -- that is what scrolling means -- and `Live.Frame`
	carries no scroll extent, so nothing here can tell "below the fold" from
	"unreachable". A check that fires 128 times on the flagship screen does not get
	fixed; it gets disabled, and takes the honest checks with it.

	COVERAGE IS REPORTED, NOT IMPLIED. `contrast` can only judge a node whose
	background it can resolve, and on shop that is 38 of 82 text nodes. A checker
	that silently skips half its subjects and announces "0 problems" is the vacuous
	gate this repo keeps finding; the second return value says how much was
	actually looked at.
]]

local Checks = {}

export type Finding = {
	Check: string,
	Node: string,
	Text: string?,
	Detail: string,
}

export type Coverage = {
	Nodes: number,
	Text: number,
	--- Text nodes whose background could be resolved, so `contrast` had something
	--- to judge. The gap between this and `Text` is what the check could not see.
	ContrastJudged: number,
}

export type Options = {
	--- Multiply every string's MEASURED width by this before checking overflow.
	---
	--- The localisation stress test, and it is a multiplier rather than real
	--- translations because the failure it looks for is structural: a box sized to
	--- fit English. German and Russian commonly run 1.3-2x, so 1.5 is the usual
	--- rule of thumb and 1.0 (the default) means "check what is actually there".
	Expand: number?,
	--- Minimum acceptable contrast ratio. 4.5 is WCAG AA for body text; 3.0 is AA
	--- for large text and the honest floor for game UI at 18px and up.
	MinContrast: number?,
	--- Check names to skip, for a subject that violates one on purpose.
	Allow: { string }?,
}

--- WCAG relative luminance. The curve matters: a naive (r+g+b)/3 rates yellow and
--- blue as equally bright and would clear white-on-sky-blue, which is precisely
--- the 2.14:1 case this found on ShopUI.
local function luminance(c: { number }): number
	local function channel(v: number): number
		local s = v / 255
		return if s <= 0.03928 then s / 12.92 else ((s + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(c[1]) + 0.7152 * channel(c[2]) + 0.0722 * channel(c[3])
end

local function contrastRatio(a: { number }, b: { number }): number
	local la, lb = luminance(a), luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

local function hasText(n: any): boolean
	return type(n.text) == "string" and n.text ~= ""
end

--- The colour BEHIND a node, or nil when it cannot be resolved.
---
--- Walks the display list backwards from the node's own index, because the list
--- is in PAINT ORDER: the last opaque thing drawn before it, under its centre, is
--- what a reader actually sees it against.
---
--- OPAQUE ONLY. A translucent panel blends with whatever is under it, and
--- resolving that means compositing the whole stack -- at which point the honest
--- answer is a pixel, and this is not a rasteriser. Returning nil is the correct
--- answer to a question this cannot answer, and the coverage number makes the gap
--- visible instead of letting it read as a pass.
local function backgroundUnder(nodes: { any }, index: number): { number }?
	local n = nodes[index]
	local cx, cy = n.x + n.w / 2, n.y + n.h / 2
	for j = index - 1, 1, -1 do
		local m = nodes[j]
		if
			m.fill
			and (m.alpha or 1) >= 0.999
			and m.gradient == nil
			and cx >= m.x
			and cx <= m.x + m.w
			and cy >= m.y
			and cy <= m.y + m.h
		then
			return m.fill
		end
	end
	return nil
end

--- Run every check over one frame.
---
--- `measure(text, size)` must be the SAME measurement layout used, or the
--- overflow check compares a box laid out with one font against text measured
--- with another -- which is the ms-52 M7 drift, restated as a false positive.
function Checks.Run(frame: any, measure: (string, number, string?) -> (number, number), options: Options?)
	local opts = options or {}
	local expand = opts.Expand or 1
	local minContrast = opts.MinContrast or 4.5
	local skip: { [string]: boolean } = {}
	for _, name in ipairs(opts.Allow or {}) do
		skip[name] = true
	end

	local findings: { Finding } = {}
	local coverage: Coverage = { Nodes = #frame.Nodes, Text = 0, ContrastJudged = 0 }

	for i, n in ipairs(frame.Nodes) do
		if not hasText(n) then
			continue
		end
		coverage.Text += 1
		local size = n.textSize or 14
		local tw, th = measure(n.text, size, nil)
		local wanted = tw * expand

		--- HALF A PIXEL of slack, not zero. Layout and measurement agree to
		--- floating point, not exactly, and a check that fires on 0.0001 px is a
		--- check that fires on everything.
		if not skip.overflow and wanted > n.w + 0.5 then
			table.insert(findings, {
				Check = "overflow",
				Node = n.name,
				Text = n.text,
				Detail = if expand == 1
					then `needs {string.format("%.0f", tw)} px, box is {string.format("%.0f", n.w)}`
					else `at {string.format("%.1f", expand)}x needs {string.format("%.0f", wanted)} px, `
						.. `box is {string.format("%.0f", n.w)}`,
			})
		end

		if not skip.vertical and th > n.h + 0.5 then
			table.insert(findings, {
				Check = "vertical",
				Node = n.name,
				Text = n.text,
				Detail = `line is {string.format("%.0f", th)} px, box is {string.format("%.0f", n.h)}`,
			})
		end

		if not skip.contrast and n.textColour then
			local bg = backgroundUnder(frame.Nodes, i)
			if bg then
				coverage.ContrastJudged += 1
				local ratio = contrastRatio(n.textColour, bg)
				if ratio < minContrast then
					table.insert(findings, {
						Check = "contrast",
						Node = n.name,
						Text = n.text,
						Detail = `{string.format("%.2f", ratio)}:1 -- rgb({n.textColour[1]},`
							.. `{n.textColour[2]},{n.textColour[3]}) on rgb({bg[1]},{bg[2]},{bg[3]}), `
							.. `wanted {minContrast}:1`,
					})
				end
			end
		end
	end

	return findings, coverage
end

return Checks
