--!strict
--[[
	The windowed GPU painter: vello_hybrid presenting straight to the window
	(ms-52 M13).

	WHY THIS IS A SEPARATE PAINTER rather than a third backend inside
	`RasterPainter`. Every other painter in this host produces PIXELS that
	something else then puts on screen -- GDI into a memory DC, the Rust
	rasterisers into a buffer the host blits. This one owns the swapchain and
	presents itself, so it has no `Present(dc)` and no `Pixel(x, y)`, and folding
	it into a painter whose whole interface is "give me your pixels" would mean
	answering those calls with lies.

	It consumes the SAME `Live.Frame` as all of them, which is the property that
	has now survived four rasterisers without the framework changing a line.

	WHAT IS UNAVAILABLE HERE, and both are consequences of the same fact:
	  * GDI CANNOT DRAW ON THIS WINDOW. A wgpu surface and GDI do not compose, so
	    there is no text-over-the-blit fallback -- vello's own glyph rendering is
	    the only text. That is why text moved into the renderer first.
	  * NO DAMAGE-CLIPPED REPAINT. Swapchain buffers rotate, so "the surface still
	    holds the previous frame" is false and the damage rect has nothing to
	    repair. Every frame draws whole, which is affordable because the GPU is
	    drawing it.
	  * NO PIXEL READBACK, deliberately. `hybrid_probe` measured that bringing the
	    pixels home costs more than the GPU saves; a `Pixel()` here would be the
	    same mistake wearing an instrument's clothes.
]]

local Win32 = require("./Win32")
local RasterPainter = require("./RasterPainter")
--- For `TextOrigin` only: the alignment rule is shared, never duplicated.
local NativePainter = require("./NativePainter")

local ffi = (zune :: any).ffi
local t = ffi.types

local WindowedPainter = {}

local lib: any = nil
local loadError: string? = nil

--- The library path candidates, matching RasterPainter's. `dlopen` resolves a
--- relative path against the CWD rather than against this script, so a single
--- hardcoded path only works when launched from one directory.
local DLL_CANDIDATES = {
	"pkgs/ui/hosts/raster/target/release/aether_raster.dll",
	"../../raster/target/release/aether_raster.dll",
	"../raster/target/release/aether_raster.dll",
	"./raster/target/release/aether_raster.dll",
}

--- Loaded lazily and the failure REPORTED, because the most likely cause is a
--- library built without the `gpu` feature -- which is the DEFAULT. That is a
--- specific, fixable condition and deserves a specific message rather than a nil.
function WindowedPainter.Available(): (boolean, string?)
	if lib then
		return true, nil
	end
	if loadError then
		return false, loadError
	end
	local signature = {
		ar_win_attach = { returns = t.pointer, args = { t.pointer, t.pointer, t.u32, t.u32 } },
		ar_win_free = { returns = t.void, args = { t.pointer } },
		ar_win_alive = { returns = t.u32, args = { t.pointer } },
		ar_win_attach_error = { returns = t.u32, args = {} },

		ar_win_begin = { returns = t.void, args = { t.pointer, t.u8, t.u8, t.u8 } },
		ar_win_fill_rect = {
			returns = t.void,
			args = { t.pointer, t.float, t.float, t.float, t.float, t.float,
				t.u8, t.u8, t.u8, t.u8 },
		},
		ar_win_stroke_rect = {
			returns = t.void,
			args = { t.pointer, t.float, t.float, t.float, t.float, t.float, t.float,
				t.u8, t.u8, t.u8, t.u8 },
		},
		ar_win_fill_gradient = {
			returns = t.void,
			args = { t.pointer, t.float, t.float, t.float, t.float, t.float, t.float,
				t.pointer, t.u32 },
		},
		ar_win_clip_push = { returns = t.void, args = { t.pointer, t.i32, t.i32, t.i32, t.i32 } },
		ar_win_clip_pop = { returns = t.void, args = { t.pointer } },
		ar_win_fill_text = {
			returns = t.u32,
			args = { t.pointer, t.u32, t.float, t.float, t.float,
				t.u8, t.u8, t.u8, t.u8, t.pointer, t.u32 },
		},
		ar_win_resize = { returns = t.void, args = { t.pointer, t.u32, t.u32 } },
		ar_win_present = { returns = t.u32, args = { t.pointer } },
		ar_win_verify_capture = { returns = t.u32, args = { t.pointer } },
		ar_win_verify_pixel = { returns = t.u32, args = { t.pointer, t.u32, t.u32 } },
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
	loadError = `the GPU entry points are not in aether_raster.dll. They are behind an`
		.. ` OPT-IN feature, so the usual cause is a default build --`
		.. ` run: cargo build --release --features gpu (in pkgs/ui/hosts/raster).`
		.. ` Tried: {table.concat(tried, ", ")}`
	return false, loadError
end

export type Target = {
	Ptr: any,
	Width: number,
	Height: number,
}

--- Attach to a live window. Returns nil and a reason on any failure -- no GPU, no
--- compatible adapter, a library without the feature -- so the host can fall back
--- to a CPU backend rather than exit.
--- `hinstance` is passed as well as the window.
---
--- Vulkan's `VkWin32SurfaceCreateInfoKHR` requires the module instance, and
--- leaving `raw_window_handle`'s `hinstance` as None made surface creation fail
--- outright -- reported as "wgpu could not create a surface from this window
--- handle", which was accurate and gave no hint that a second handle was
--- missing. The window is created with a NULL hInstance but still HAS one; the
--- system fills it in, and `GWLP_HINSTANCE` reads it back.
function WindowedPainter.Attach(hwnd: any, width: number, height: number): (Target?, string?)
	local ok, why = WindowedPainter.Available()
	if not ok then
		return nil, why
	end
	local hinstance = Win32.user32.GetWindowLongPtrA(hwnd, Win32.GWLP_HINSTANCE)
	local ptr = lib.ar_win_attach(hwnd, hinstance, width, height)

	--- VALIDATED BY ASKING THE LIBRARY, not by comparing to nil.
	---
	--- `zune.ffi` wraps a returned NULL in pointer userdata, so `ptr == nil` is
	--- FALSE for a failed attach. The host therefore announced "painter: GPU",
	--- drew a whole frame into a null pointer, and reported 152 fps -- every
	--- draw call silently discarded, because they all return void. The counter
	--- was counting calls it had issued, not work anything had done.
	if ptr == nil or lib.ar_win_alive(ptr) ~= 1 then
		local REASONS = {
			[1] = "the window handle was NULL",
			[2] = "wgpu could not create a surface from this window handle",
			[3] = "no GPU adapter can present to this window",
			[4] = "the adapter refused to create a device",
			[5] = "the surface offers no texture format",
		}
		local code = lib.ar_win_attach_error()
		return nil, REASONS[code] or `attach failed with code {code}`
	end
	return { Ptr = ptr, Width = width, Height = height }, nil
end

function WindowedPainter.Free(target: Target)
	if lib and target.Ptr then
		lib.ar_win_free(target.Ptr)
	end
end

function WindowedPainter.Resize(target: Target, width: number, height: number)
	if lib and target.Ptr then
		lib.ar_win_resize(target.Ptr, width, height)
		target.Width = width
		target.Height = height
	end
end

local function cstrBuf(text: string): (any, number)
	return ffi.dupe(buffer.fromstring(text)), #text
end

--- Record one frame and present it.
---
--- The node loop is the SAME SHAPE as `RasterPainter.Paint`, and deliberately so:
--- the two consume identical frames, so any divergence between what this shows
--- and what the CPU backend shows is a painter bug by construction. The gradient
--- semantics in particular are the hard-won ones -- an alpha ramp MODULATES the
--- element's own opacity and a colour ramp MULTIPLIES its colour; neither is a
--- layer over the fill, which is why a gradient replaces the flat fill rather
--- than sitting on top of it.
function WindowedPainter.Paint(target: Target, frame: any): number
	lib.ar_win_begin(target.Ptr, 11, 13, 18)

	local fontId = RasterPainter.LoadFont()
	local drawn = 0
	for _, n in ipairs(frame.Nodes) do
		local hasStroke = n.stroke ~= nil and n.stroke.colour ~= nil
		local hasGradient = n.gradient ~= nil
		local hasFill = n.fill ~= nil and (n.alpha or 1) > 0.004 and n.gradient == nil
		local hasText = fontId ~= nil and type(n.text) == "string" and n.text ~= ""
		if not hasFill and not hasStroke and not hasGradient and not hasText then
			continue
		end

		local clipped = n.clip ~= nil
		if clipped then
			lib.ar_win_clip_push(
				target.Ptr,
				math.floor(n.clip[1]), math.floor(n.clip[2]),
				math.ceil(n.clip[3]), math.ceil(n.clip[4])
			)
		end

		local radius = n.radius or 0

		if hasFill then
			lib.ar_win_fill_rect(
				target.Ptr, n.x, n.y, n.w, n.h, radius,
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
				local flat = buffer.create(#list * 5 * 4)
				for i, st in ipairs(list) do
					local base = (i - 1) * 5 * 4
					buffer.writef32(flat, base, st.t or 0)
					local c = n.fill or { 255, 255, 255 }
					if stops then
						--- A COLOUR GRADIENT MULTIPLIES the element's own colour.
						--- White leaves it untouched; grey darkens it. Painting the
						--- stop colour directly renders a slate card as an opaque
						--- white block.
						buffer.writef32(flat, base + 4, st.c[1] * c[1] / 255)
						buffer.writef32(flat, base + 8, st.c[2] * c[2] / 255)
						buffer.writef32(flat, base + 12, st.c[3] * c[3] / 255)
						buffer.writef32(flat, base + 16, math.floor((n.alpha or 1) * 255 + 0.5))
					else
						--- An ALPHA RAMP varies the element's OWN opacity, multiplied
						--- by its base transparency: a 50%-opaque element with a ramp
						--- from 0.9 to 0.7 is 45% to 35%, not 90% to 70%.
						buffer.writef32(flat, base + 4, c[1])
						buffer.writef32(flat, base + 8, c[2])
						buffer.writef32(flat, base + 12, c[3])
						buffer.writef32(flat, base + 16,
							math.floor((st.a or 1) * (n.alpha or 1) * 255 + 0.5))
					end
				end
				lib.ar_win_fill_gradient(
					target.Ptr, n.x, n.y, n.w, n.h, radius,
					n.gradient.rotation or 0, ffi.dupe(flat), #list
				)
				drawn += 1
			end
		end

		if hasText then
			local tc = n.textColour or { 230, 232, 238 }
			local size = n.textSize or 14
			local mw, mh = RasterPainter.Metrics(n.text, size, nil)
			local tx, ty = NativePainter.TextOrigin(n, mw, mh)
			local ptr, len = cstrBuf(n.text)
			local got = lib.ar_win_fill_text(
				target.Ptr, fontId :: number, size, tx, ty,
				tc[1], tc[2], tc[3],
				math.floor((n.textAlpha or 1) * 255 + 0.5),
				ptr, len)
			if got > 0 then
				drawn += 1
			end
		end

		if hasStroke then
			lib.ar_win_stroke_rect(
				target.Ptr, n.x, n.y, n.w, n.h, radius,
				n.stroke.thickness or 1,
				n.stroke.colour[1], n.stroke.colour[2], n.stroke.colour[3],
				math.floor((n.stroke.alpha or 1) * 255 + 0.5)
			)
			drawn += 1
		end

		if clipped then
			lib.ar_win_clip_pop(target.Ptr)
		end
	end

	return drawn
end

--- CAPTURE THE CURRENT SCENE OFF-SCREEN, for verification only.
---
--- The frame loop presents and never reads back -- that is the entire reason this
--- painter exists, and `hybrid_probe` measured the readback costing more than the
--- GPU saves. But a renderer with no way to inspect its output has no automated
--- gate at all, and can draw garbage until a human notices.
---
--- So this is the check's door and not the loop's: it re-renders to its own
--- texture and is deliberately slow, which makes it useless as a shortcut.
function WindowedPainter.Capture(target: Target): boolean
	return lib.ar_win_verify_capture(target.Ptr) == 1
end

--- One pixel of the last capture, as 0x00RRGGBB.
function WindowedPainter.Pixel(target: Target, x: number, y: number): number
	return lib.ar_win_verify_pixel(target.Ptr, x, y)
end

--- Present the recorded frame. Returns false when the frame was dropped, which is
--- ordinary -- an occluded or resizing window -- and not an error.
function WindowedPainter.Present(target: Target): boolean
	return lib.ar_win_present(target.Ptr) == 1
end

return WindowedPainter
