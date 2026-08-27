--!strict
--[[
	The native painter — the same frames, drawn by GDI (ms-52 M7).

	WHY THIS IS SMALL
	It consumes `Live.Frame`, which the browser page already consumes: rectangles
	in paint order carrying fill, stroke, corner radius, clip and text. The
	framework does not know or care that this exists. That is the whole point of
	having had a display protocol before having a second display — the work of a
	new rendering environment is a painter, not a port.

	It is also why the two hosts are worth keeping side by side: they are fed
	byte-identical frames, so a disagreement between them is a PAINTER bug by
	construction, and an agreement that is wrong is a framework bug. Neither
	conclusion is available with one display.

	WHAT GDI CANNOT DO HERE, stated rather than approximated:
	  * ALPHA. `Rectangle` has no opacity; real blending needs `AlphaBlend` and an
	    off-screen 32-bit surface. Nodes below the visibility threshold are
	    skipped and everything else draws opaque, so a translucent panel reads
	    heavier here than in the browser.
	  * GRADIENTS. `GradientFill` wants a TRIVERTEX array, which is the struct
	    marshalling this milestone otherwise avoided entirely. Deferred; the node
	    draws its flat fill, exactly as the pre-M2 canvas did.
	Both are omissions the audit can see, not silent approximations.
]]

local Win32 = require("./Win32")
local TextOrigin = require("./TextOrigin")

local NativePainter = {}

local gdi = Win32.gdi32

--- Below this, a node is treated as not painted at all. GDI cannot blend, so the
--- honest choice is to draw a nearly-invisible thing not at all rather than
--- draw it fully opaque.
--- Stock brush index for "no fill". Stock objects are never deleted, which is
--- why they are safe to park on between nodes.
local NULL_BRUSH = 5

--- FONTS, CACHED BY SIZE (ms-52 M7).
---
--- Nothing here selected a font, so GDI used the default STOCK font: a small
--- fixed-size face that ignores `textSize` entirely and carries a narrow glyph
--- repertoire. Two symptoms, one cause -- every label rendered at the same tiny
--- size whatever the frame asked for, and the arrow glyphs came out as fallback
--- marks because the default face has no `◀`.
---
--- Cached because `CreateFontA` on every node of every frame at 60Hz is both slow
--- and a GDI handle leak; the set of distinct sizes on a screen is small.
---
--- Height is NEGATIVE on purpose: a positive height is the CELL height including
--- leading, a negative one is the character height, which is what `TextSize`
--- means everywhere else in this framework.
local DEFAULT_CHARSET = 1
local CLEARTYPE_QUALITY = 5

--- "Segoe UI Symbol" rather than "Segoe UI": it carries the arrows, ticks and
--- geometric shapes this repo uses as icons, and falls back to ordinary Latin
--- shapes for everything else. A UI face without the symbol block draws the icons
--- as boxes, which is what "the arrows show as vertical lines" was.
local FACE = "Segoe UI Symbol"

local fontCache: { [number]: any } = {}

--- EXPERIMENT (ms-52): cache brushes and pens by colour, the way fonts are
--- cached by size. The painter created and destroyed one of each PER NODE PER
--- FRAME -- 148 nodes on ShopUI at 60Hz.
local brushCache: { [number]: any } = {}
local penCache: { [string]: any } = {}
local function brushFor(c: number): any
	local b = brushCache[c]
	if not b then
		b = gdi.CreateSolidBrush(c)
		brushCache[c] = b
	end
	return b
end
local function penFor(c: number, w: number): any
	local key = `{c}|{w}`
	local p = penCache[key]
	if not p then
		p = gdi.CreatePen(0, w, c)
		penCache[key] = p
	end
	return p
end

local function fontFor(size: number): any
	local key = math.max(8, math.floor(size + 0.5))
	local cached = fontCache[key]
	if cached then
		return cached
	end
	local f = gdi.CreateFontA(
		-key, 0, 0, 0,
		400, 0, 0, 0,
		DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0,
		Win32.cstr(FACE)
	)
	fontCache[key] = f
	return f
end

--- Exported so `--profile` can time font selection in isolation. The profiler
--- must exercise the SAME cache the painter uses, or it measures a different
--- program than the one being optimised.
NativePainter.FontFor = fontFor

local ALPHA_FLOOR = 0.15

--- How far past the damage rect a repaint reaches. A stroke straddles its node's
--- edge and an anti-aliased corner writes a fraction of a pixel outside the exact
--- rectangle, so an exact repaint leaves a hairline of the previous frame behind.
--- Exported because the host's blit MUST use the same number: repainting a ring
--- the blit does not copy is a band of stale pixels around everything that moves.
local PAD = 2
NativePainter.DamagePad = PAD

--- Does this node's box touch the damaged region?
---
--- Padded by two pixels: a stroke straddles its node's edge, so an exact test
--- leaves a hairline of the previous frame behind.
local function touches(n: any, d: { number }?): boolean
	if d == nil then
		return true
	end
	return not (n.x + n.w < d[1] - 2 or n.x > d[1] + d[3] + 2
		or n.y + n.h < d[2] - 2 or n.y > d[2] + d[4] + 2)
end

local function colorOf(c: { number }?): number?
	if c == nil then
		return nil
	end
	return Win32.colorref(c[1], c[2], c[3])
end

--- MEASURE WITH THE FONT WE ACTUALLY PAINT WITH.
---
--- `Host.Text` had no host-supplied provider here, so layout measured every
--- string with Aether's bundled advance table while GDI drew with Segoe UI
--- Symbol. Measured against real metrics: 5% out on ordinary labels, 21% on a
--- narrow-glyph run. Anything sized by its content -- `AutomaticSize`,
--- `TextScaled` -- was therefore sized to a width nothing would draw.
---
--- Shares `fontFor`, deliberately. Measuring with one font and painting with
--- another is the bug this exists to remove, so the two must not be able to drift
--- apart -- the same reason the framework has ONE text seam rather than one per
--- call site.
---
--- `GetTabbedTextExtentW` returns the width packed in a DWORD, which is how this
--- avoids a SIZE out-param; see Win32.luau.
local measureDC: any = nil

function NativePainter.Metrics(text: string, size: number, _font: string?): (number, number)
	if text == "" then
		return 0, size * 1.2
	end
	if measureDC == nil then
		measureDC = gdi.CreateCompatibleDC(Win32.user32.GetDC(Win32.null))
	end
	gdi.SelectObject(measureDC, fontFor(size))
	local wide, wlen = Win32.wstr(text)
	local packed = Win32.user32.GetTabbedTextExtentW(measureDC, wide, wlen, 0, Win32.null)
	local width = bit32.band(packed, 0xFFFF)
	local height = bit32.band(bit32.rshift(packed, 16), 0xFFFF)
	if width == 0 then
		--- The call failed. Fall back rather than report zero: a zero width
		--- collapses the element, which is far more destructive than an
		--- approximate one.
		return #text * size * 0.55, size * 1.2
	end
	return width, if height > 0 then height else size * 1.2
end

--- ONE TEXT IMPLEMENTATION, used by both the combined pass and the raster
--- backend's text-only pass. They must not be able to drift in font, size or
--- baseline -- the same reason the framework has one text seam rather than one
--- per call site.
---
--- `st` carries the DC state this has already set, so it can be skipped when it
--- is already correct. Profiled rather than guessed: of shop's 2.35 ms text pass,
--- the UTF-16 conversion was 0.14 ms and DC state calls were 0.97 ms -- 41% of
--- the budget re-setting state that was usually already right.
---
--- The obvious optimisation -- caching rasterised runs as bitmaps, the way a
--- glyph atlas works -- would have targeted the remaining 1.25 ms and carries a
--- real fidelity cost: ClearType anti-aliases against the BACKGROUND, so a run
--- cached over one backdrop and blitted over another fringes. Measuring said the
--- cheap safe fix was the bigger one.
type TextState = { colour: number?, size: number?, bk: boolean }

--- WHERE A RUN STARTS, given its box, its measured width and its alignment.
---
--- Exported because all three painters need the identical rule and they had the
--- identical BUG: each hardcoded `n.x + 10`, a left inset with nothing behind it
--- (no text node on these screens carries a UIPadding), so every centred label
--- rendered left. On `✕` -- a 19px box holding an 11px glyph -- the inset alone
--- pushed the glyph past its own box.
---
--- Takes the measured width rather than measuring itself: each host measures with
--- the font IT paints with, and that pairing must not be broken here.
--- `leftalign` replays the invented `n.x + 10` inset that left-aligned every
--- centred label across all three painters. Set by `--poison=leftalign`.
local poison: string? = nil

function NativePainter.SetPoison(name: string?)
	--- Forwarded, so the shared rule is poisoned by the same flag that poisons
	--- this painter. A poison that only reached one of two call sites would make
	--- the matrix report a gate as able to fail when it is not.
	TextOrigin.SetPoison(name)
	poison = name
end

function NativePainter.Poison(): string?
	return poison
end

--- Delegated to `TextOrigin`, which is where the rule lives now (ms-53 P2). Kept
--- as a method here because callers and gates name it, and because a painter
--- answering "where does this text start" is the right shape even when the answer
--- comes from elsewhere.
function NativePainter.TextOrigin(n: any, measuredWidth: number, lineHeight: number): (number, number)
	return TextOrigin.Resolve(n, measuredWidth, lineHeight)
end

local function drawTextNode(hdc: any, n: any, st: TextState)
	if not st.bk then
		gdi.SetBkMode(hdc, Win32.TRANSPARENT)
		st.bk = true
	end
	local tc = colorOf(n.textColour) or Win32.colorref(230, 232, 238)
	if tc ~= st.colour then
		gdi.SetTextColor(hdc, tc)
		st.colour = tc
	end
	local size = n.textSize or 14
	if size ~= st.size then
		gdi.SelectObject(hdc, fontFor(size))
		st.size = size
	end
	local wide, wlen = Win32.wstr(n.text)
	--- Measured with the same font this is about to draw with; `Metrics` shares
	--- `fontFor`, which is the pairing M7 broke.
	local w, h = NativePainter.Metrics(n.text, size, nil)
	local tx, ty = NativePainter.TextOrigin(n, w, h)
	gdi.TextOutW(hdc, math.floor(tx), math.floor(ty), wide, wlen)
end

--- Paint one frame onto a device context.
---
--- Returns how many nodes were drawn, so a caller can assert the painter did
--- something rather than trusting that it did.
function NativePainter.Paint(hdc: any, frame: any, background: number?, damage: { number }?): number
	--- The whole surface first, or the previous frame shows through wherever this
	--- one does not cover.
	--- DESELECT BEFORE DELETING. GDI refuses to delete an object that is still
	--- selected into a DC, and the refusal is silent: the call returns 0, the
	--- brush leaks, and the DC keeps drawing with a handle the painter believes
	--- it has freed. It cost the first parity run 6 of 14 nodes, which read as
	--- unpainted WHITE -- the bitmap's initial colour, showing through because
	--- even the background fill had failed.
	--- THE DAMAGE RECT MUST CLIP THE WHOLE PASS, not merely select which nodes
	--- run. Skipping a node that does not touch the rect is only sound if the
	--- nodes that DO touch it cannot paint outside it -- and they can: `Window`
	--- spans the screen, so it intersects any damage rect and, unclipped,
	--- repainted the entire surface. Everything above it that had been skipped
	--- was then simply gone. It showed up as the topbar losing its colour to the
	--- window beneath it, 10% of sampled pixels wrong, every one of them OUTSIDE
	--- the damage rect -- which is what pointed here rather than at the delta.
	--- `staledamage` drops the clip that makes skipping nodes sound, which is
	--- exactly the defect `--damage-check` was written to catch: 22488 of 222768
	--- pixels wrong, every one of them OUTSIDE the damage rect.
	local outerSave = 0
	if damage and poison ~= "staledamage" then
		outerSave = gdi.SaveDC(hdc)
		gdi.IntersectClipRect(hdc,
			math.floor(damage[1]) - PAD, math.floor(damage[2]) - PAD,
			math.ceil(damage[1] + damage[3]) + PAD, math.ceil(damage[2] + damage[4]) + PAD)
	end

	local bg = brushFor(background or Win32.colorref(11, 13, 18))
	local nullPen = gdi.GetStockObject(Win32.NULL_PEN)
	gdi.SelectObject(hdc, bg)
	gdi.SelectObject(hdc, nullPen)
	--- Only the damaged region is recleared; everything outside it still holds
	--- the previous frame, which is the whole point of being given a damage rect.
	if damage then
		gdi.Rectangle(hdc, math.floor(damage[1]) - PAD, math.floor(damage[2]) - PAD,
			math.ceil(damage[1] + damage[3]) + PAD, math.ceil(damage[2] + damage[4]) + PAD)
	else
		gdi.Rectangle(hdc, -1, -1, frame.Width + 2, frame.Height + 2)
	end
	gdi.SelectObject(hdc, gdi.GetStockObject(NULL_BRUSH))

	local drawn = 0
	local st: TextState = { colour = nil, size = nil, bk = false }
	for _, n in ipairs(frame.Nodes) do
		local alpha = n.alpha or 1
		local fill = colorOf(n.fill)
		local hasText = type(n.text) == "string" and n.text ~= ""
		local stroke = n.stroke

		if (fill == nil or alpha < ALPHA_FLOOR) and not hasText and stroke == nil then
			continue
		end
		--- Skipped ENTIRELY rather than left to the clip: the clip discards the
		--- pixels but still pays the GDI calls per node.
		if not touches(n, damage) then
			continue
		end

		--- SaveDC/RestoreDC scopes the clip. Without it a clipped node clips
		--- everything drawn after it, which looks like the rest of the screen
		--- vanishing rather than like a clipping bug.
		--- ONLY WHEN THERE IS A CLIP TO SCOPE. SaveDC/RestoreDC ran on every node
		--- and exists solely to unwind IntersectClipRect, so an unclipped node
		--- paid the pair for nothing -- and RestoreDC resets the whole DC, which
		--- is what forced the background mode and text colour to be re-set on
		--- every single node.
		local saved = 0
		if n.clip then
			saved = gdi.SaveDC(hdc)
			gdi.IntersectClipRect(hdc, math.floor(n.clip[1]), math.floor(n.clip[2]),
				math.ceil(n.clip[1] + n.clip[3]), math.ceil(n.clip[2] + n.clip[4]))
			st.bk = false
			st.colour = nil
			st.size = nil
		end

		local left, top = math.floor(n.x), math.floor(n.y)
		local right, bottom = math.ceil(n.x + n.w), math.ceil(n.y + n.h)

		if fill and alpha >= ALPHA_FLOOR then
			local brush = brushFor(fill)
			gdi.SelectObject(hdc, brush)

			--- The stroke is drawn by the same call as the fill: GDI outlines a
			--- Rectangle with the current PEN. A separate pass would double-draw
			--- the edge and thicken every border by a pixel.
			local pen
			if stroke and stroke.colour then
				pen = penFor(Win32.colorref(stroke.colour[1], stroke.colour[2], stroke.colour[3]),
					math.max(1, math.floor(stroke.thickness or 1)))
			else
				pen = gdi.GetStockObject(Win32.NULL_PEN)
			end
			gdi.SelectObject(hdc, pen)

			local radius = math.floor(n.radius or 0)
			if radius > 0 then
				gdi.RoundRect(hdc, left, top, right, bottom, radius * 2, radius * 2)
			else
				gdi.Rectangle(hdc, left, top, right, bottom)
			end

			--- SELECT A STOCK OBJECT, never the previous handle.
			---
			--- Restoring `keptBrush` looks like the textbook idiom and is wrong
			--- here: after the first node, the "previous" brush is the background
			--- brush this function already DELETED. Selecting a dangling handle
			--- makes GDI silently fall back to WHITE_BRUSH, and every node after
			--- that point paints white -- which is exactly what the parity check
			--- read, and why it looked like the framework had stopped producing
			--- colours.
			---
			--- Stock objects cannot be deleted and are always valid, so parking on
			--- one between nodes has no such failure mode.
			gdi.SelectObject(hdc, gdi.GetStockObject(NULL_BRUSH))
			gdi.SelectObject(hdc, gdi.GetStockObject(Win32.NULL_PEN))
			drawn += 1
		elseif stroke and stroke.colour then
			--- An outline with no fill of its own.
			local pen = gdi.CreatePen(0, math.max(1, math.floor(stroke.thickness or 1)),
				Win32.colorref(stroke.colour[1], stroke.colour[2], stroke.colour[3]))
			gdi.SelectObject(hdc, pen)
			gdi.SelectObject(hdc, gdi.GetStockObject(NULL_BRUSH))
			gdi.Rectangle(hdc, left, top, right, bottom)
			gdi.SelectObject(hdc, gdi.GetStockObject(Win32.NULL_PEN))
			gdi.DeleteObject(pen)
			drawn += 1
		end

		if hasText then
			--- The DC state notes that used to live here moved into
			--- `drawTextNode`, which both passes now share. The hard-won one is
			--- still true and still load-bearing: RestoreDC resets the background
			--- mode, so a single SetBkMode before the loop survives exactly one
			--- clipped node, after which every TextOutW draws on an OPAQUE white
			--- box and erases what is beneath it. That is why `st` is invalidated
			--- wherever RestoreDC is called.
			drawTextNode(hdc, n, st)
			drawn += 1
		end

		--- `-1`, NOT the handle SaveDC returned. `RestoreDC(hdc, -1)` pops the most
		--- recent saved state, which is what this loop actually wants and which
		--- still works when SaveDC failed and returned 0 -- `RestoreDC(hdc, 0)` is
		--- invalid and leaves the clip region SET.
		---
		--- That is not hypothetical: a persisting clip made every node after the
		--- first clipped one draw nowhere, and `GetPixel` then returned CLR_INVALID
		--- (0xFFFFFFFF) for those points. Printed with %06X it truncates to
		--- 0xFFFFFF and reads as "painted white", which sent the first diagnosis
		--- after a brush-deletion bug that was not there.
		if saved ~= 0 then
			gdi.RestoreDC(hdc, -1)
			--- The DC is now back to whatever it was BEFORE this node, so nothing
			--- tracked in `st` can be trusted.
			st.bk = false
			st.colour = nil
			st.size = nil
		end
	end

	if outerSave ~= 0 then
		gdi.RestoreDC(hdc, -1)
	end
	return drawn
end

--- TEXT ONLY, for the raster backend to draw over its blit.
---
--- The Rust rasterizer deliberately does not do text -- 96 of 237 nodes are text
--- runs, and glyph rasterisation and shaping are the part that would consume the
--- project. This is the same text pass `Paint` performs, extracted so the two
--- painters share one implementation and cannot drift in font, size or baseline.
--- The raster backend's text pass: the same drawing, over its blit.
local function textPass(hdc: any, frame: any, damage: { number }?): number
	local drawn = 0
	local st: TextState = { colour = nil, size = nil, bk = false }
	--- Clipped for the same reason `Paint` is: a glyph run can extend past its
	--- node's box, so selecting nodes by intersection is not on its own enough.
	local outerSave = 0
	if damage then
		outerSave = gdi.SaveDC(hdc)
		gdi.IntersectClipRect(hdc,
			math.floor(damage[1]) - PAD, math.floor(damage[2]) - PAD,
			math.ceil(damage[1] + damage[3]) + PAD, math.ceil(damage[2] + damage[4]) + PAD)
	end
	for _, n in ipairs(frame.Nodes) do
		if type(n.text) ~= "string" or n.text == "" or not touches(n, damage) then
			continue
		end
		local saved = 0
		if n.clip then
			saved = gdi.SaveDC(hdc)
			gdi.IntersectClipRect(hdc, math.floor(n.clip[1]), math.floor(n.clip[2]),
				math.ceil(n.clip[1] + n.clip[3]), math.ceil(n.clip[2] + n.clip[4]))
			st.bk = false
			st.colour = nil
			st.size = nil
		end
		drawTextNode(hdc, n, st)
		drawn += 1
		if saved ~= 0 then
			gdi.RestoreDC(hdc, -1)
			st.bk = false
			st.colour = nil
			st.size = nil
		end
	end
	if outerSave ~= 0 then
		gdi.RestoreDC(hdc, -1)
	end
	return drawn
end

function NativePainter.PaintTextOnly(hdc: any, frame: any, damage: { number }?): number
	return textPass(hdc, frame, damage)
end

return NativePainter
