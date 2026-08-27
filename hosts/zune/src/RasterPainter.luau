--!strict
--[[
	The native painter, backed by the Rust rasterizer (ms-52 M8).

	    cargo build --release            (once, in pkgs/ui/hosts/raster)
	    zune run pkgs/ui/hosts/zune/src/Native.luau --raster --screen shop

	WHY THIS EXISTS ALONGSIDE NativePainter
	GDI cannot blend. 49 of 85 filled rects on the two real screens are
	translucent, so the GDI painter drew most of the screen opaque -- correct
	geometry, wrong picture. It also has no gradients, and its rounded corners are
	not anti-aliased.

	This consumes the SAME `Live.Frame` and produces the same geometry with those
	three fixed. Both painters stay: they are fed byte-identical frames, so a
	disagreement between them is a painter bug by construction, and that is the
	only cheap way to tell a painter bug from a framework bug.

	THE DIVISION OF LABOUR IS DELIBERATE. Shapes are rasterised in Rust; TEXT is
	drawn by GDI on top. 96 of 237 nodes are text runs, and glyph rasterisation,
	shaping and fallback are the part that would consume the project. The platform
	already does it well.
]]

--- For `TextOrigin` only: the alignment rule is shared, not duplicated.
--- The SHARED alignment rule, not the GDI painter. Requiring 
--- for it dragged  in and kept this file Windows-only (ms-53 P2).
local TextOrigin = require("./TextOrigin")

local z = (zune :: any)
local ffi = z.ffi
local t = ffi.types

local RasterPainter = {}

--- THE LIBRARY PATH MUST NOT DEPEND ON THE WORKING DIRECTORY.
---
--- `dlopen` resolves a relative path against the CWD, not against this script, so
--- a single hardcoded path only worked when the host was launched from the repo
--- root. Run it from `pkgs/ui/hosts/zune/src` -- which is the obvious place to
--- run it from -- and the library silently was not found.
---
--- Candidates rather than one guess, ordered from the repo root outwards, so both
--- spellings work and neither is privileged.
--- THE LIBRARY NAME IS PLATFORM-SHAPED, and hardcoding `.dll` was the second
--- thing keeping this file on Windows (ms-53 P2). The crate itself has no
--- platform `cfg` outside optional features and builds clean on Linux x86_64;
--- only the FILENAME differs.
local LIB_FILE = if z.process.os == "windows"
	then "aether_raster.dll"
	elseif z.process.os == "macos" then "libaether_raster.dylib"
	else "libaether_raster.so"

local DLL_CANDIDATES = {
	`pkgs/ui/hosts/raster/target/release/{LIB_FILE}`,
	`../../raster/target/release/{LIB_FILE}`,
	`../raster/target/release/{LIB_FILE}`,
	`./raster/target/release/{LIB_FILE}`,
}

local lib: any = nil
local loadError: string? = nil

--- Loaded lazily, and the failure REPORTED rather than swallowed: the library is
--- a build artifact, so "did you run cargo build" is a question someone will ask,
--- and a nil is the least useful possible answer to it.
function RasterPainter.Available(): (boolean, string?)
	if lib then
		return true, nil
	end
	if loadError then
		return false, loadError
	end
	local signature = {
		ar_surface_new = { returns = t.pointer, args = { t.u32, t.u32 } },
		ar_surface_new_backend = { returns = t.pointer, args = { t.u32, t.u32, t.u32 } },
		ar_backend = { returns = t.u32, args = { t.pointer } },
		ar_surface_free = { returns = t.void, args = { t.pointer } },
		ar_begin = { returns = t.void, args = { t.pointer, t.u8, t.u8, t.u8 } },
		ar_begin_rect = {
			returns = t.void,
			args = { t.pointer, t.u8, t.u8, t.u8, t.i32, t.i32, t.i32, t.i32 },
		},
		ar_fill_rect = {
			returns = t.void,
			args = { t.pointer, t.float, t.float, t.float, t.float, t.float, t.u8, t.u8, t.u8, t.u8 },
		},
		ar_stroke_rect = {
			returns = t.void,
			args = { t.pointer, t.float, t.float, t.float, t.float, t.float, t.float, t.u8, t.u8, t.u8, t.u8 },
		},
		ar_fill_gradient = {
			returns = t.void,
			args = { t.pointer, t.float, t.float, t.float, t.float, t.float, t.float, t.pointer, t.u32 },
		},
		ar_clip_push = { returns = t.void, args = { t.pointer, t.i32, t.i32, t.i32, t.i32 } },
		ar_clip_pop = { returns = t.void, args = { t.pointer } },
		ar_bgra = { returns = t.pointer, args = { t.pointer } },
		ar_png = { returns = t.u32, args = { t.pointer, t.pointer, t.u32 } },
		ar_font_load = { returns = t.u32, args = { t.pointer, t.u32, t.u32 } },
		ar_text_width = { returns = t.float, args = { t.u32, t.float, t.pointer, t.u32 } },
		ar_text_line_height = { returns = t.float, args = { t.u32, t.float } },
		ar_text_ascent = { returns = t.float, args = { t.u32, t.float } },
		ar_fill_text = {
			returns = t.u32,
			args = { t.pointer, t.u32, t.float, t.float, t.float,
				t.u8, t.u8, t.u8, t.u8, t.pointer, t.u32 },
		},
		ar_pixel = { returns = t.u32, args = { t.pointer, t.u32, t.u32 } },
	}
	local tried = {}
	for _, candidate in ipairs(DLL_CANDIDATES) do
		local ok, result = pcall(ffi.dlopen, candidate, signature)
		if ok then
			lib = result
			return true, nil
		end
		table.insert(tried, candidate)
	end
	loadError = `{LIB_FILE} not found. Tried: {table.concat(tried, ", ")}`
		.. ` -- run "cargo build --release" in pkgs/ui/hosts/raster`
	return false, loadError
end

export type Surface = {
	Ptr: any,
	Width: number,
	Height: number,
	--- Built lazily by `WindowsPresenter`, which is the only thing that needs a
	--- BITMAPINFO. nil everywhere else, including every headless run.
	Info: any?,
	--- Which rasteriser actually backs this surface. Read back from the library
	--- rather than remembered from the request: a `--vello` flag that silently
	--- fell back to tiny-skia would make every measurement taken under it a lie.
	Backend: string,
}

--- TEXT, WHEN THE RENDERER OWNS IT (ms-52 M11).
---
--- Two decisions argued for delegating text to the platform, and that held while
--- the platform could still reach the surface. A wgpu swapchain ends that -- GDI
--- cannot draw onto a surface wgpu owns -- so the windowed GPU path es9 chose
--- requires the renderer to rasterise its own glyphs. This is that half, landed
--- first and on the CPU backend, so it can be verified by every existing gate
--- before the presentation architecture changes underneath it.
---
--- tiny-skia is unaffected and still has GDI draw its text.
local fontId: number? = nil
--- ORDERED BY PLATFORM, and the Windows list stays first on Windows for a
--- reason worth keeping: Segoe UI SYMBOL carries the arrows, ticks and geometric
--- shapes this repo uses as icons, and a UI face without the symbol block draws
--- them as boxes -- which is what "the arrows show as vertical lines" was.
---
--- THE LINUX LIST IS NOT AN EQUIVALENT. DejaVu and Liberation have a symbol
--- block but not Segoe's, so a snapshot rendered on Linux will not be pixel-equal
--- to one rendered here. That is a REAL constraint on the CI product, not a
--- detail: a baseline must be produced on the same platform it is compared
--- against, exactly as ms-52 found for backends. Recorded here because this list
--- is where someone will look when the diffs come back full of text.
local FONT_CANDIDATES = if z.process.os == "windows"
	then {
		"C:/Windows/Fonts/seguisym.ttf",
		"C:/Windows/Fonts/segoeui.ttf",
		"C:/Windows/Fonts/arial.ttf",
	}
	elseif z.process.os == "macos" then {
		"/System/Library/Fonts/SFNS.ttf",
		"/System/Library/Fonts/Supplemental/Arial.ttf",
		"/Library/Fonts/Arial.ttf",
	}
	else {
		"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
		"/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
		"/usr/share/fonts/TTF/DejaVuSans.ttf",
		"/usr/share/fonts/dejavu/DejaVuSans.ttf",
	}

local function cstrBuf(text: string): (any, number)
	local b = buffer.fromstring(text)
	return ffi.dupe(b), #text
end

--- Load the text face. Returns nil and a reason rather than raising: a missing
--- font is a deployment problem the host should report and fall back from.
function RasterPainter.LoadFont(): (number?, string?)
	if fontId then
		return fontId, nil
	end
	local ok = RasterPainter.Available()
	if not ok then
		return nil, "the rasteriser is unavailable"
	end
	local tried = {}
	for _, path in ipairs(FONT_CANDIDATES) do
		local ptr, len = cstrBuf(path)
		local id = lib.ar_font_load(ptr, len, 0)
		if id ~= 0 then
			fontId = id
			return id, nil
		end
		table.insert(tried, path)
	end
	return nil, `no usable font. Tried: {table.concat(tried, ", ")}`
end

--- Measure a run with the font that will PAINT it.
---
--- Shares the loaded face with `PaintText` deliberately. ms-52 M7 shipped a host
--- that measured with one font and painted with another -- 5% out on ordinary
--- labels, 21% on a narrow-glyph run, and `AutomaticSize` sizing to a width
--- nothing would draw. The two must not be able to drift, so there is one path.
function RasterPainter.Metrics(text: string, size: number, _font: string?): (number, number)
	local id = RasterPainter.LoadFont()
	if id == nil then
		return #text * size * 0.55, size * 1.2
	end
	local lh = lib.ar_text_line_height(id, size)
	--- The font's own line height, not a factor of the size. `size * 1.2` is the
	--- approximation this milestone exists to remove, kept only for the case
	--- where the font could not answer.
	local height = if lh > 0 then lh else size * 1.2
	if text == "" then
		return 0, height
	end
	local ptr, len = cstrBuf(text)
	local w = lib.ar_text_width(id, size, ptr, len)
	if w < 0 then
		--- REPORTED, not silently zeroed. A zero width collapses the element.
		return #text * size * 0.55, height
	end
	return w, height
end

--- ARM A DELIBERATE DEFECT, for proving a gate can still fail.
---
--- Loaded SEPARATELY from the main signature table, and pcall'd, because
--- `ar_poison` only exists when the library was built `--features poison`. Adding
--- it to the main table would make every normal run fail to `dlopen`.
---
--- Returns false when the symbol is absent, which is how the harness tells "the
--- gate did not notice the sabotage" from "the sabotage never happened" -- two
--- outcomes that look identical from the outside and mean opposite things.
local poisonLib: any = nil
local poisonChecked = false

function RasterPainter.SetPoison(name: string?): boolean
	if not poisonChecked then
		poisonChecked = true
		if RasterPainter.Available() then
			for _, candidate in ipairs(DLL_CANDIDATES) do
				local ok, result = pcall(ffi.dlopen, candidate, {
					ar_poison = { returns = t.u32, args = { t.pointer, t.u32 } },
				})
				if ok then
					poisonLib = result
					break
				end
			end
		end
	end
	if not poisonLib then
		return false
	end
	local text = name or ""
	local ptr, len = cstrBuf(text)
	return poisonLib.ar_poison(ptr, len) == 1
end

--- The backends, by their ABI number.
RasterPainter.TINY_SKIA = 0
RasterPainter.VELLO_CPU = 1

--- A BITMAPINFOHEADER, written as a flat buffer.
function RasterPainter.NewSurface(width: number, height: number, backend: number?): Surface?
	local ok = RasterPainter.Available()
	if not ok then
		return nil
	end
	local want = backend or RasterPainter.TINY_SKIA
	local ptr = lib.ar_surface_new_backend(width, height, want)
	if ptr == nil then
		return nil
	end
	local got = lib.ar_backend(ptr)
	return {
		Ptr = ptr,
		Width = width,
		Height = height,
		Backend = if got == RasterPainter.VELLO_CPU then "vello_cpu" else "tiny-skia",
	}
end

function RasterPainter.FreeSurface(s: Surface)
	if lib and s.Ptr then
		lib.ar_surface_free(s.Ptr)
	end
end

--- Rasterise one frame's SHAPES. Text is not drawn here; see the note at the top.
---
--- Returns how many draw calls were issued, so a caller can assert the painter
--- did something rather than trusting that it did.
--- A LOUD BACKDROP -- and a correction about what it can and cannot show.
---
--- Added on the theory that a translucent menu over stripes would make blending
--- obvious. It does not, and cannot: `Window` is alpha 1.00 on BOTH real screens.
--- The outermost panel is opaque by the application's own design, so nothing
--- behind it will ever show through, and es9 correctly reported "the menu is not
--- translucent at all" while looking at exactly that.
---
--- What IS translucent sits INSIDE the window -- 40 of shop's filled nodes are
--- between 0.5 and 0.99 -- and blends against the window, not against this. So
--- the backdrop shows only in the margin around the window, which is honest but
--- proves nothing about alpha.
---
--- Kept because it is genuinely useful for judging the window's own edges,
--- corner radii and shadow against something other than a flat ground. It is NOT
--- a translucency demo; `--compare` is.
function RasterPainter.PaintBackdrop(s: Surface)
	local bars = {
		{ 224, 64, 96 },
		{ 248, 176, 48 },
		{ 64, 200, 160 },
		{ 96, 128, 248 },
	}
	local w = math.ceil(s.Width / #bars)
	for i, c in ipairs(bars) do
		lib.ar_fill_rect(s.Ptr, (i - 1) * w, 0, w, s.Height, 0, c[1], c[2], c[3], 255)
	end
end

--- Does this node's box touch the damaged region?
---
--- Nodes are skipped ENTIRELY when they do not, rather than relying on the clip
--- to discard their pixels: the clip saves the blend but still pays path
--- construction and the FFI call per node.
---
--- Padded by two pixels because a stroke straddles its node's edge and an
--- anti-aliased corner writes a fraction of a pixel outside the exact rectangle.
--- Getting this too tight leaves a hairline of the previous frame behind, which
--- is the classic damage-tracking artefact and reads as a rendering bug.
local function touches(n: any, d: { number }?): boolean
	if d == nil then
		return true
	end
	return not (n.x + n.w < d[1] - 2 or n.x > d[1] + d[3] + 2
		or n.y + n.h < d[2] - 2 or n.y > d[2] + d[4] + 2)
end

--- `damage` repaints only that rectangle and leaves the rest of the surface
--- holding the previous frame. The caller MUST then present only that rectangle.
--- Does this surface draw its own text?
---
--- Only the vello backend can. tiny-skia is a SHAPE backend by design -- glyph
--- rasterisation is not something it does -- so when it is selected the host
--- keeps drawing text with GDI over the blit, exactly as before.
--- Text can be suppressed, for ONE caller: the cross-backend comparison.
---
--- tiny-skia is a shape backend and always will be, so comparing it against a
--- vello surface that also draws glyphs measures the presence of text rather than
--- any disagreement about rasterisation -- 83 draw calls against 165, and every
--- text pixel counted as a divergence. Suppressing text makes the two comparable
--- on the thing they both do.
---
--- Deliberately NOT a per-surface option: it exists to make one instrument
--- honest, and a per-surface flag would invite using it to paper over a real
--- difference somewhere else.
local textEnabled = true

function RasterPainter.SetTextEnabled(on: boolean)
	textEnabled = on
end

function RasterPainter.OwnsText(s: Surface): boolean
	return textEnabled and s.Backend == "vello_cpu" and RasterPainter.LoadFont() ~= nil
end

function RasterPainter.Paint(s: Surface, frame: any, backdrop: boolean?, damage: { number }?): number
	local ownsText = RasterPainter.OwnsText(s)
	if damage then
		lib.ar_begin_rect(s.Ptr, 11, 13, 18,
			math.floor(damage[1]), math.floor(damage[2]),
			math.ceil(damage[3]), math.ceil(damage[4]))
	else
		lib.ar_begin(s.Ptr, 11, 13, 18)
	end
	if backdrop then
		RasterPainter.PaintBackdrop(s)
	end

	local drawn = 0
	for _, n in ipairs(frame.Nodes) do
		if not touches(n, damage) then
			continue
		end
		local hasStroke = n.stroke ~= nil and n.stroke.colour ~= nil
		local hasGradient = n.gradient ~= nil

		--- AN ALPHA RAMP MODULATES THE FILL, IT DOES NOT SIT ON TOP OF IT.
		---
		--- A UIGradient carrying only `Transparency` describes how the element's
		--- OWN opacity varies across itself -- Roblox draws the element once, with
		--- a per-pixel alpha. Painting a flat opaque fill and then compositing the
		--- ramp over it in the same colour yields... an opaque element, which is
		--- exactly why `MenuWindow`'s window looked solid while its gradient ramped
		--- 0.1 to 0.3 in the data.
		---
		--- es9 asked to "make the outermost background translucent with a
		--- UIGradient". It already was; this painter was flattening it.
		--- A GRADIENT IS THE ELEMENT'S PAINT, not a layer over it. Roblox draws the
		--- element ONCE, with the gradient applied to its own colour and alpha, so
		--- the flat fill is skipped whenever a gradient is present -- of either
		--- kind.
		local hasFill = n.fill ~= nil and (n.alpha or 1) > 0.004 and n.gradient == nil
		--- A TEXT-ONLY node has no fill, no stroke and no gradient, and this
		--- early-out used to drop it -- harmlessly, while GDI drew the text in a
		--- separate pass, and catastrophically now that this loop owns it.
		local hasOwnText = ownsText and type(n.text) == "string" and n.text ~= ""
		if not hasFill and not hasStroke and not hasGradient and not hasOwnText then
			continue
		end

		--- Pushed and popped PER NODE rather than tracked as an ancestor stack,
		--- because `Live.Frame` hands every node its fully resolved clip, already
		--- intersected. One push and one pop is therefore exact.
		local clipped = n.clip ~= nil
		if clipped then
			lib.ar_clip_push(
				s.Ptr,
				math.floor(n.clip[1]),
				math.floor(n.clip[2]),
				math.ceil(n.clip[3]),
				math.ceil(n.clip[4])
			)
		end

		local radius = n.radius or 0

		if hasFill then
			--- ALPHA, which is the entire point. GDI drew this opaque.
			lib.ar_fill_rect(
				s.Ptr, n.x, n.y, n.w, n.h, radius,
				n.fill[1], n.fill[2], n.fill[3],
				math.floor((n.alpha or 1) * 255 + 0.5)
			)
			drawn += 1
		end

		if hasGradient then
			local stops = n.gradient.stops
			local alphaStops = n.gradient.alphaStops
			local list = stops or alphaStops
			if list and #list > 0 then
				--- Flat `[t, r, g, b, a]` per stop: nothing structured crosses the
				--- ABI. A colour ramp carries its own colours; an ALPHA ramp varies
				--- the node's OWN fill, exactly as the canvas painter does.
				local flat = buffer.create(#list * 5 * 4)
				for i, st in ipairs(list) do
					local base = (i - 1) * 5 * 4
					buffer.writef32(flat, base, st.t or 0)
					if stops then
						--- A COLOUR GRADIENT MULTIPLIES the element's own colour --
						--- it is a shading modifier, not a replacement. White leaves
						--- the colour untouched; grey darkens it.
						---
						--- Painting the stop colour DIRECTLY is what made
						--- `HeroBannerFrame` -- slate, with a white-to-grey ramp --
						--- render as an opaque white block sitting on top of the
						--- menu. es9 spotted it as "still seems to sit atop an
						--- opaque mostly white background".
						local c = n.fill or { 255, 255, 255 }
						buffer.writef32(flat, base + 4, st.c[1] * c[1] / 255)
						buffer.writef32(flat, base + 8, st.c[2] * c[2] / 255)
						buffer.writef32(flat, base + 12, st.c[3] * c[3] / 255)
						--- And at the ELEMENT's alpha. Forcing 255 made every
						--- gradient opaque regardless of what the element declared.
						buffer.writef32(flat, base + 16, math.floor((n.alpha or 1) * 255 + 0.5))
					else
						--- The node's own colour at the ramp's alpha, multiplied by
						--- the node's base transparency: a 50%-opaque element with a
						--- ramp from 0.9 to 0.7 is 45% to 35%, not 90% to 70%.
						local c = n.fill or { 255, 255, 255 }
						buffer.writef32(flat, base + 4, c[1])
						buffer.writef32(flat, base + 8, c[2])
						buffer.writef32(flat, base + 12, c[3])
						buffer.writef32(flat, base + 16,
							math.floor((st.a or 1) * (n.alpha or 1) * 255 + 0.5))
					end
				end
				lib.ar_fill_gradient(
					s.Ptr, n.x, n.y, n.w, n.h, radius,
					n.gradient.rotation or 0, ffi.dupe(flat), #list
				)
				drawn += 1
			end
		end

		--- TEXT IN PAINT ORDER, which GDI could not do here.
		---
		--- The GDI arrangement draws every shape, blits, then draws every text run
		--- on top -- because the blit would erase anything drawn before it. That is
		--- wrong whenever a later node should cover an earlier label, and it was
		--- accepted only because the alternative was not available.
		---
		--- vello records a scene, so a text run can sit at its true position in
		--- paint order and be occluded exactly as the display list says.
		if ownsText and type(n.text) == "string" and n.text ~= "" then
			local tc = n.textColour or { 230, 232, 238 }
			local size = n.textSize or 14
			local ptr, len = cstrBuf(n.text)
			--- ONE positioning rule, shared with the GDI painter, so the displays
			--- can disagree about glyph SHAPES and never about position. Measured
			--- with vello's own font, which is what draws here.
			local mw, mh = RasterPainter.Metrics(n.text, size, nil)
			local tx, ty = TextOrigin.Resolve(n, mw, mh)
			local drew = lib.ar_fill_text(
				s.Ptr, fontId :: number, size,
				tx, ty,
				tc[1], tc[2], tc[3],
				math.floor((n.textAlpha or 1) * 255 + 0.5),
				ptr, len)
			if drew > 0 then
				drawn += 1
			end
		end

		if hasStroke then
			lib.ar_stroke_rect(
				s.Ptr, n.x, n.y, n.w, n.h, radius,
				n.stroke.thickness or 1,
				n.stroke.colour[1], n.stroke.colour[2], n.stroke.colour[3],
				math.floor((n.stroke.alpha or 1) * 255 + 0.5)
			)
			drawn += 1
		end

		if clipped then
			lib.ar_clip_pop(s.Ptr)
		end
	end

	return drawn
end

--- Copy the rasterised surface into a device context.
---
--- Text is drawn AFTER this by the caller, not before: the blit covers the whole
--- surface and would erase anything already there.
--- Copy the rasterised surface into a device context.
---
--- With a damage rect, only the affected BAND OF SCANLINES is copied. Rows, not
--- an arbitrary rectangle: `SetDIBitsToDevice` addresses the source by scanline
--- range, and a full-width band needs no arithmetic on the row stride -- which is
--- where a top-down DIB (negative biHeight) most easily goes subtly wrong.
--- Trading a little extra width for that is worth it; the height is where the
--- saving is anyway.
--- PRESENT LIVES IN `WindowsPresenter.luau` NOW (ms-53 P2).
---
--- It was the ONLY thing in this file that touched Win32 -- two
--- `SetDIBitsToDevice` calls and the BITMAPINFO they need -- and it kept the
--- whole rasteriser Windows-only for no reason that survives inspection.
--- Everything else here (surface creation, painting, text, pixel readback, PNG)
--- is platform-neutral, and the Rust crate beneath it has no platform `cfg` at
--- all outside optional features.
---
--- That single require is what stood between this repo and rendering in a Linux
--- container, which is what `aether-cli` needs. Moving it out is a factoring,
--- not a port.

--- Write the surface to a PNG. No window, no DC, no platform.
---
--- Returns nil on success or an error string. The Rust side answers a code
--- rather than a bool because "could not open the file" and "the surface was
--- never rendered" are different failures and a CI caller has to tell them
--- apart.
local PNG_ERRORS: { [number]: string } = {
	[1] = "the surface handle was null",
	[2] = "the path was empty or not valid UTF-8",
	[3] = "the vello surface had no pixmap",
	[4] = "the pixel buffer did not match the surface size",
	[5] = "the file could not be written",
}

--- The BGRA bytes for a Windows DIB. Platform-neutral itself -- it is a pointer
--- to a buffer -- and used only by `WindowsPresenter`.
function RasterPainter.Bits(s: Surface): any
	return lib.ar_bgra(s.Ptr)
end

function RasterPainter.WritePNG(s: Surface, path: string): string?
	local buf, len = cstrBuf(path)
	local code = lib.ar_png(s.Ptr, buf, len)
	if code == 0 then
		return nil
	end
	return PNG_ERRORS[code] or `unknown error {code}`
end

--- One pixel of the RASTERISED surface, as 0x00RRGGBB. The parity instrument,
--- and the reason this backend could be verified before it was ever displayed.
function RasterPainter.Pixel(s: Surface, x: number, y: number): number
	return lib.ar_pixel(s.Ptr, x, y)
end

return RasterPainter
