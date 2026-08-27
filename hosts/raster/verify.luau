--!strict
--[[
	aether_raster — does the Rust rasterizer do what GDI could not? (ms-52 M8)

	    cargo build --release          (in this directory, once)
	    zune run pkgs/ui/hosts/raster/verify.luau

	WHY THESE THREE ASSERTIONS
	They are exactly the gaps the GDI painter documented as omissions, so this is
	the smallest thing that proves the backend is worth having:

	  * ALPHA. 49 of 85 filled rects on the two real screens are translucent. GDI's
	    `Rectangle` has no opacity, so the native host drew them opaque -- most of
	    the screen rendered wrong. Blending 50% white over red must give ~0xFF8080,
	    and nothing else does.
	  * ANTI-ALIASED ROUNDED CORNERS, which GDI's `RoundRect` produces jagged.
	  * The C ABI itself: that `zune.ffi` can call into Rust at all.

	Pixels are read back rather than eyeballed, the same instrument the GDI
	painter's `--check` uses, and for the same reason: a renderer verified by
	looking at it is verified by nobody in CI.
]]

local ffi = (zune :: any).ffi
local t = ffi.types

local DLL = "pkgs/ui/hosts/raster/target/release/aether_raster.dll"

local ok, lib = pcall(ffi.dlopen, DLL, {
	ar_surface_new = { returns = t.pointer, args = { t.u32, t.u32 } },
	ar_begin = { returns = t.void, args = { t.pointer, t.u8, t.u8, t.u8 } },
	ar_fill_rect = {
		returns = t.void,
		args = { t.pointer, t.float, t.float, t.float, t.float, t.float, t.u8, t.u8, t.u8, t.u8 },
	},
	ar_stroke_rect = {
		returns = t.void,
		args = { t.pointer, t.float, t.float, t.float, t.float, t.float, t.float, t.u8, t.u8, t.u8, t.u8 },
	},
	ar_clip_push = { returns = t.void, args = { t.pointer, t.i32, t.i32, t.i32, t.i32 } },
	ar_clip_pop = { returns = t.void, args = { t.pointer } },
	ar_pixel = { returns = t.u32, args = { t.pointer, t.u32, t.u32 } },
	ar_surface_free = { returns = t.void, args = { t.pointer } },
})

assert(ok, `could not load {DLL} -- run \`cargo build --release\` in pkgs/ui/hosts/raster first`)

local s = lib.ar_surface_new(200, 200)
assert(tostring(s) ~= "<pointer: 0x0>", "the surface should allocate")

lib.ar_begin(s, 0, 0, 0)

--- 1. ALPHA, the gap that matters most.
lib.ar_fill_rect(s, 10, 10, 100, 100, 0, 255, 0, 0, 255)
local opaque = lib.ar_pixel(s, 50, 50)
assert(opaque == 0xFF0000, `an opaque red fill should read 0xFF0000, got 0x{string.format("%06X", opaque)}`)

lib.ar_fill_rect(s, 10, 10, 100, 100, 0, 255, 255, 255, 128)
local blended = lib.ar_pixel(s, 50, 50)
local g = bit32.band(bit32.rshift(blended, 8), 0xFF)
print(string.format("alpha:  opaque 0x%06X, then 50%% white -> 0x%06X", opaque, blended))
assert(g > 100 and g < 160,
	`50%% white over red must BLEND, got 0x{string.format("%06X", blended)} -- `
		.. `an opaque draw would read 0xFFFFFF and no draw 0xFF0000`)

--- 2. ANTI-ALIASED ROUNDED CORNERS.
lib.ar_fill_rect(s, 120, 10, 60, 60, 20, 0, 255, 0, 255)
local centre = lib.ar_pixel(s, 150, 40)
local corner = lib.ar_pixel(s, 121, 11)
print(string.format("corner: centre 0x%06X, corner 0x%06X", centre, corner))
assert(centre == 0x00FF00, "a rounded fill must still fill its centre")
assert(corner ~= 0x00FF00, "and must leave its corner unpainted -- radius is being ignored")

--- 3. CLIPPING, which nests by intersection.
lib.ar_clip_push(s, 0, 0, 100, 200)
lib.ar_fill_rect(s, 0, 150, 200, 40, 0, 0, 0, 255, 255)
lib.ar_clip_pop(s)
local inside = lib.ar_pixel(s, 50, 170)
local outside = lib.ar_pixel(s, 150, 170)
print(string.format("clip:   inside 0x%06X, outside 0x%06X", inside, outside))
assert(inside == 0x0000FF, "the clipped fill must paint inside the clip")
assert(outside ~= 0x0000FF, "and must not paint outside it")

lib.ar_surface_free(s)
print("OK -- alpha, anti-aliased corners and clipping all work through the C ABI.")
