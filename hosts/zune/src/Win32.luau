--!strict
--[[
	Win32, bound from Luau (ms-52 M7).

	WHY THERE IS NO STRUCT MARSHALLING HERE
	The risk I flagged for this milestone was `WNDCLASSEXA`, `MSG`, `PAINTSTRUCT`
	and `RECT` — layout and padding done by hand, where a wrong offset crashes
	rather than errors. Almost all of it turned out to be avoidable, and the
	avoidance is the interesting part:

	  * NO `RegisterClassExA`. The window is created with the built-in `STATIC`
	    class and then SUBCLASSED — `SetWindowLongPtrA(hwnd, GWLP_WNDPROC, proc)`
	    installs our own procedure. A whole struct disappears.
	  * NO `RECT`. `Rectangle`, `RoundRect` and `IntersectClipRect` all take four
	    integers directly. `FillRect` is the one that wants a RECT, so it is not
	    used.
	  * NO `PAINTSTRUCT`. `GetDC`/`ReleaseDC` paint on demand; `WM_PAINT` is
	    answered by validating the region rather than by BeginPaint/EndPaint.
	  * `MSG` survives as an OPAQUE BUFFER. The loop only passes the pointer back
	    to `TranslateMessage` and `DispatchMessageA` — it never reads a field, so
	    the layout never has to be known.

	What is left needs no layout knowledge at all, which is why this file is
	bindings and constants and nothing else.

	COORDINATES ARE PACKED IN lParam for mouse messages — x in the low word, y in
	the high word, both CLIENT-relative. That is also how the OS avoids a POINT
	struct, and it is why this host does not need `GetCursorPos`/`ScreenToClient`.
]]

local ffi = (zune :: any).ffi
local t = ffi.types

local Win32 = {}

Win32.user32 = ffi.dlopen("user32.dll", {
	CreateWindowExA = {
		returns = t.pointer,
		args = { t.u32, t.pointer, t.pointer, t.u32, t.i32, t.i32, t.i32, t.i32, t.pointer, t.pointer, t.pointer, t.pointer },
	},
	DestroyWindow = { returns = t.i32, args = { t.pointer } },
	ShowWindow = { returns = t.i32, args = { t.pointer, t.i32 } },
	UpdateWindow = { returns = t.i32, args = { t.pointer } },
	IsWindow = { returns = t.i32, args = { t.pointer } },
	SetWindowLongPtrA = { returns = t.i64, args = { t.pointer, t.i32, t.pointer } },
	--- Returns a POINTER, not an i64.
	---
	--- 64-bit values cross `zune.ffi` as 8-byte BUFFERS rather than numbers -- the
	--- same trap that made `WM_MOUSEMOVE` coordinates arrive as buffers and
	--- needed `low32`. Declaring this `i64` meant the HINSTANCE arrived as a
	--- buffer, was passed on as one, and reached Rust as garbage. A handle is an
	--- opaque token that only has to survive a round trip, so keeping it a pointer
	--- means it is never converted at all.
	GetWindowLongPtrA = { returns = t.pointer, args = { t.pointer, t.i32 } },
	DefWindowProcA = { returns = t.i64, args = { t.pointer, t.u32, t.u64, t.i64 } },
	PeekMessageA = { returns = t.i32, args = { t.pointer, t.pointer, t.u32, t.u32, t.u32 } },
	TranslateMessage = { returns = t.i32, args = { t.pointer } },
	DispatchMessageA = { returns = t.i64, args = { t.pointer } },
	PostMessageA = { returns = t.i32, args = { t.pointer, t.u32, t.u64, t.i64 } },
	GetDC = { returns = t.pointer, args = { t.pointer } },
	ReleaseDC = { returns = t.i32, args = { t.pointer, t.pointer } },
	ValidateRect = { returns = t.i32, args = { t.pointer, t.pointer } },
	GetSystemMetrics = { returns = t.i32, args = { t.i32 } },
	SetWindowTextA = { returns = t.i32, args = { t.pointer, t.pointer } },
	--- Text width WITHOUT an out-param: this returns a DWORD with the width in
	--- the low word, so it needs no SIZE struct. `GetTextExtentPoint32W` wants
	--- one, and a plain Luau buffer does not cross as a writable pointer.
	---
	--- It lives in USER32, not gdi32, which is easy to assume wrong -- every other
	--- text call here is a GDI one.
	GetTabbedTextExtentW = { returns = t.u32, args = { t.pointer, t.pointer, t.i32, t.i32, t.pointer } },
})

--- The multimedia timer, for one function.
---
--- Windows' default scheduler granularity is ~15.6ms, so `task.wait(1/60)` --
--- 16.67ms -- actually sleeps ~31ms and the loop runs at 32fps. `timeBeginPeriod(1)`
--- asks for 1ms granularity, which is the standard fix and the only way a Win32
--- program paces above ~64fps at all.
Win32.winmm = ffi.dlopen("winmm.dll", {
	timeBeginPeriod = { returns = t.u32, args = { t.u32 } },
	timeEndPeriod = { returns = t.u32, args = { t.u32 } },
})

Win32.gdi32 = ffi.dlopen("gdi32.dll", {
	CreateSolidBrush = { returns = t.pointer, args = { t.u32 } },
	CreatePen = { returns = t.pointer, args = { t.i32, t.i32, t.u32 } },
	GetStockObject = { returns = t.pointer, args = { t.i32 } },
	SelectObject = { returns = t.pointer, args = { t.pointer, t.pointer } },
	DeleteObject = { returns = t.i32, args = { t.pointer } },
	Rectangle = { returns = t.i32, args = { t.pointer, t.i32, t.i32, t.i32, t.i32 } },
	RoundRect = { returns = t.i32, args = { t.pointer, t.i32, t.i32, t.i32, t.i32, t.i32, t.i32 } },
	GetPixel = { returns = t.u32, args = { t.pointer, t.i32, t.i32 } },
	SetBkMode = { returns = t.i32, args = { t.pointer, t.i32 } },
	SetTextColor = { returns = t.u32, args = { t.pointer, t.u32 } },
	TextOutA = { returns = t.i32, args = { t.pointer, t.i32, t.i32, t.pointer, t.i32 } },
	--- The WIDE variant. Icons in this repo are Unicode glyphs -- the arrows, the
	--- tick, the star -- and TextOutA reads their UTF-8 bytes as ANSI codepage,
	--- which draws nothing recognisable. See Win32.wstr.
	TextOutW = { returns = t.i32, args = { t.pointer, t.i32, t.i32, t.pointer, t.i32 } },
	GetTextExtentPoint32A = { returns = t.i32, args = { t.pointer, t.pointer, t.i32, t.pointer } },
	--- The wide variant, for the same reason TextOutW is used. The out-param is a
	--- SIZE struct: two i32, which a plain buffer can carry without ffi.struct.
	GetTextExtentPoint32W = { returns = t.i32, args = { t.pointer, t.pointer, t.i32, t.pointer } },
	SaveDC = { returns = t.i32, args = { t.pointer } },
	RestoreDC = { returns = t.i32, args = { t.pointer, t.i32 } },
	IntersectClipRect = { returns = t.i32, args = { t.pointer, t.i32, t.i32, t.i32, t.i32 } },
	CreateCompatibleDC = { returns = t.pointer, args = { t.pointer } },
	CreateCompatibleBitmap = { returns = t.pointer, args = { t.pointer, t.i32, t.i32 } },
	BitBlt = { returns = t.i32, args = { t.pointer, t.i32, t.i32, t.i32, t.i32, t.pointer, t.i32, t.i32, t.u32 } },
	--- Blit a raw pixel buffer into a DC. This is how the Rust rasterizer's output
	--- reaches the window: it hands back BGRA, which is exactly what a 32bpp
	--- BI_RGB DIB wants, so nothing is converted on the Luau side.
	SetDIBitsToDevice = {
		returns = t.i32,
		args = { t.pointer, t.i32, t.i32, t.u32, t.u32, t.i32, t.i32, t.u32, t.u32, t.pointer, t.pointer, t.u32 },
	},
	CreateFontA = {
		returns = t.pointer,
		args = { t.i32, t.i32, t.i32, t.i32, t.i32, t.u32, t.u32, t.u32, t.u32, t.u32, t.u32, t.u32, t.u32, t.pointer },
	},
})

--- A NUL-terminated C string. `ffi.dupe` copies the buffer into memory the
--- library can read; a Luau string cannot be handed over directly.
function Win32.cstr(s: string): any
	local b = buffer.create(#s + 1)
	buffer.writestring(b, 0, s)
	return ffi.dupe(b)
end

--- A UTF-16LE string, plus its length in WCHARs.
---
--- WHY THIS EXISTS (ms-52 M7)
--- The icons in ShopUI and SettingsUI are not images -- they are TEXT: `◀`, `▶`,
--- `⭐`, `✓`, `✕`. `TextOutA` takes ANSI bytes, so a UTF-8 glyph arrives as two
--- or three meaningless codepage characters and draws as nothing recognisable.
--- That is why the icons appeared missing while every other label was fine.
---
--- Converted here rather than through `MultiByteToWideChar`, because Luau already
--- knows how to walk UTF-8 and the conversion is short. Astral codepoints (most
--- emoji above U+FFFF) become surrogate PAIRS; getting that wrong would drop
--- exactly the characters most likely to be used as an icon.
function Win32.wstr(s: string): (any, number)
	local units: { number } = {}
	for _, code in utf8.codes(s) do
		if code < 0x10000 then
			table.insert(units, code)
		else
			local v = code - 0x10000
			table.insert(units, 0xD800 + bit32.rshift(v, 10))
			table.insert(units, 0xDC00 + bit32.band(v, 0x3FF))
		end
	end
	local b = buffer.create((#units + 1) * 2)
	for i, unit in ipairs(units) do
		buffer.writeu16(b, (i - 1) * 2, unit)
	end
	buffer.writeu16(b, #units * 2, 0)
	return (zune :: any).ffi.dupe(b), #units
end

--- COLORREF is 0x00BBGGRR — blue in the HIGH byte, which is the reverse of every
--- other colour API in this repo. Getting it backwards yields a picture that is
--- plausibly wrong rather than obviously wrong, so it lives in one function.
function Win32.colorref(r: number, g: number, b: number): number
	return r + g * 256 + b * 65536
end

Win32.null = ffi.null
Win32.alloc = ffi.alloc
Win32.closure = ffi.closure

--- Constants, named rather than inlined.
Win32.WS_OVERLAPPEDWINDOW = 0x00CF0000
Win32.WS_VISIBLE = 0x10000000
Win32.SW_SHOW = 5
Win32.GWLP_WNDPROC = -4
--- The module instance that owns a window. Vulkan's Win32 surface wants it, and
--- a window created with a NULL hInstance still HAS one -- the system fills it in.
Win32.GWLP_HINSTANCE = -6
Win32.TRANSPARENT = 1
Win32.NULL_PEN = 8
Win32.SRCCOPY = 0x00CC0020

Win32.WM_DESTROY = 0x0002
Win32.WM_CLOSE = 0x0010
Win32.WM_PAINT = 0x000F
Win32.WM_MOUSEMOVE = 0x0200
Win32.WM_LBUTTONDOWN = 0x0201
Win32.WM_LBUTTONUP = 0x0202
Win32.WM_MOUSEWHEEL = 0x020A
Win32.WM_CHAR = 0x0102
Win32.WM_KEYDOWN = 0x0100

--- SIXTY-FOUR-BIT ARGUMENTS ARRIVE AS BUFFERS, NOT NUMBERS.
---
--- A `u64`/`i64` parameter reaches an `ffi.closure` as an 8-byte buffer, because
--- a Luau number cannot carry the full range. 32-bit parameters arrive as plain
--- numbers, so `msg` looked fine and `wParam`/`lParam` did not — and the mismatch
--- only appears when a REAL message arrives.
---
--- That is exactly what shipped: `--frames 90` ran the loop happily because no
--- mouse moved over the window during it, and the first real WM_MOUSEMOVE
--- panicked with "invalid argument #1 to 'band' (number expected, got buffer)".
--- A bounded run proved the loop turns, not that input works.
---
--- Only the low 32 bits carry the payload for these messages, so `readu32` at
--- offset 0 is the whole decode.
local function low32(v: any): number
	if type(v) == "buffer" then
		return buffer.readu32(v, 0)
	end
	return v
end

Win32.low32 = low32

--- Mouse coordinates arrive packed in lParam, client-relative. The high word is
--- signed: a pointer dragged above or left of the client area reports a negative
--- coordinate, and reading it unsigned puts it at 65000-odd instead — which
--- looks like the pointer teleporting rather than like a sign error.
function Win32.unpackXY(lp: any): (number, number)
	local packed = low32(lp)
	local x = bit32.band(packed, 0xFFFF)
	local y = bit32.band(bit32.rshift(packed, 16), 0xFFFF)
	if x >= 0x8000 then
		x -= 0x10000
	end
	if y >= 0x8000 then
		y -= 0x10000
	end
	return x, y
end

--- The wheel delta is the SIGNED high word of wParam, in multiples of 120.
function Win32.wheelDelta(wp: any): number
	local d = bit32.band(bit32.rshift(low32(wp), 16), 0xFFFF)
	if d >= 0x8000 then
		d -= 0x10000
	end
	return d / 120
end

return Win32
