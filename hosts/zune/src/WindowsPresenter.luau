--!strict
--[[
	spektr/zune_host · WindowsPresenter — the surface onto a Windows DC (ms-53 P2).

	SPLIT OUT SO THE RASTERISER IS PLATFORM-NEUTRAL.

	`RasterPainter` did everything -- create a surface, paint, measure text, read
	pixels back -- and required `Win32` for ONE thing: two `SetDIBitsToDevice`
	calls and the BITMAPINFO they need. That single require made the whole
	rasteriser Windows-only, and it is what stood between this repo and rendering
	inside a Linux container.

	Nothing else moved. The Rust crate beneath has no platform `cfg` outside
	optional features, and `vello_cpu` and `tiny-skia` are pure Rust. So this is a
	factoring, not a port -- and `verify_headless_is_portable` fails if anything on
	the headless path ever requires this file again.
]]

local Win32 = require("./Win32")

local gdi = Win32.gdi32
local ffi = (zune :: any).ffi

local WindowsPresenter = {}

--- A top-down 32bpp BITMAPINFO.
---
--- Negative height is what makes it top-down, which matches the rasteriser's row
--- order; a positive height would present every frame upside down.
local function bitmapInfo(width: number, height: number): any
	local b = buffer.create(40)
	buffer.writeu32(b, 0, 40)
	buffer.writei32(b, 4, width)
	buffer.writei32(b, 8, -height)
	buffer.writeu16(b, 12, 1)
	buffer.writeu16(b, 14, 32)
	buffer.writeu32(b, 16, 0)
	return ffi.dupe(b)
end

--- Set by a caller that wants Present broken into its two halves.
---
--- `ar_bgra` rasterises if needed and then SWIZZLES the surface into BGRA for
--- GDI -- a byte shuffle over every damaged row -- and `SetDIBitsToDevice`
--- uploads it. Two costs with two different fixes, which the loop's accounting
--- cannot tell apart from outside. Nil unless `--account` is on.
WindowsPresenter.Account = nil :: { swizzle: number, upload: number }?

function WindowsPresenter.Present(RasterPainter: any, s: any, hdc: any, damage: { number }?)
	if s.Info == nil then
		s.Info = bitmapInfo(s.Width, s.Height)
	end
	local acct = WindowsPresenter.Account
	local t0 = if acct then os.clock() else 0
	local bits = RasterPainter.Bits(s)
	if acct then
		local t1 = os.clock()
		acct.swizzle += t1 - t0
		--- Reassigned rather than added at the end of each branch: this has three
		--- exits and the upload happens on two of them.
		acct.upload -= t1
	end

	if damage then
		local y0 = math.max(0, math.floor(damage[2]) - 2)
		local y1 = math.min(s.Height, math.ceil(damage[2] + damage[4]) + 2)
		local rows = y1 - y0
		if rows <= 0 then
			if acct then acct.upload += os.clock() end
			return
		end
		--- `uStartScan`/`cScanLines` are counted from the TOP for a top-down DIB,
		--- which is why `y0` can be used directly here.
		gdi.SetDIBitsToDevice(hdc, 0, y0, s.Width, rows, 0, 0, y0, rows, bits, s.Info, 0)
		if acct then acct.upload += os.clock() end
		return
	end
	gdi.SetDIBitsToDevice(hdc, 0, 0, s.Width, s.Height, 0, 0, 0, s.Height, bits, s.Info, 0)
	if acct then acct.upload += os.clock() end
end

return WindowsPresenter
