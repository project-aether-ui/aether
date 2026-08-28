//! The Win32 implementation.

use crate::{Button, Event};
use std::cell::RefCell;
use windows::core::PCWSTR;
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, EndPaint, GetDC, ReleaseDC, StretchDIBits, BITMAPINFO, BITMAPINFOHEADER, BI_RGB,
    DIB_RGB_COLORS, HDC, PAINTSTRUCT, SRCCOPY, ScreenToClient,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetKeyState, ReleaseCapture, SetCapture, VIRTUAL_KEY, VK_BACK, VK_CONTROL, VK_DELETE, VK_DOWN,
    VK_END, VK_ESCAPE, VK_HOME, VK_LEFT, VK_RETURN, VK_RIGHT, VK_SHIFT, VK_TAB, VK_UP,
};
use windows::Win32::UI::WindowsAndMessaging::*;

thread_local! {
    /// Events collected by the window procedure, drained by `poll`.
    ///
    /// THREAD-LOCAL RATHER THAN A POINTER IN `GWLP_USERDATA`, because a Win32
    /// window is owned by the thread that created it and its procedure only ever
    /// runs there. A queue per thread is therefore exactly a queue per window
    /// set, with no lifetime to get wrong and no cast from an integer back to a
    /// reference that would be unsound if a message arrived after a drop.
    static EVENTS: RefCell<Vec<Event>> = const { RefCell::new(Vec::new()) };
}

fn push(event: Event) {
    EVENTS.with(|e| e.borrow_mut().push(event));
}

fn xy(lparam: LPARAM) -> (f32, f32) {
    // The coordinates are SIGNED 16-bit halves. Reading them as unsigned puts the
    // pointer at ~65000 the moment it leaves the window's left or top edge while
    // a button is held, which is exactly when a drag wants to keep tracking.
    let raw = lparam.0 as u32;
    let x = (raw & 0xFFFF) as i16;
    let y = ((raw >> 16) & 0xFFFF) as i16;
    (x as f32, y as f32)
}

/// A named key for the ones that produce no character.
///
/// Only the keys a text field acts on. Anything else is left to `WM_CHAR`, which
/// already handles layout, dead keys and modifiers correctly — re-deriving a
/// character from a virtual-key code is how a host ends up typing the wrong thing
/// on a non-US keyboard.
fn key_name(vk: u32) -> Option<&'static str> {
    Some(match VIRTUAL_KEY(vk as u16) {
        VK_BACK => "Backspace",
        VK_DELETE => "Delete",
        VK_LEFT => "Left",
        VK_RIGHT => "Right",
        VK_UP => "Up",
        VK_DOWN => "Down",
        VK_HOME => "Home",
        VK_END => "End",
        VK_RETURN => "Return",
        VK_TAB => "Tab",
        VK_ESCAPE => "Escape",
        _ => return None,
    })
}

fn modifier(vk: VIRTUAL_KEY) -> bool {
    // The high bit means "down now"; the low bit is the toggle state and is why
    // testing the whole value treats a released Caps Lock as a held key.
    unsafe { (GetKeyState(vk.0 as i32) as u16 & 0x8000) != 0 }
}

unsafe extern "system" fn wndproc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    match msg {
        WM_MOUSEMOVE => {
            let (x, y) = xy(lp);
            push(Event::PointerMove { x, y });
            LRESULT(0)
        }
        WM_LBUTTONDOWN | WM_RBUTTONDOWN | WM_MBUTTONDOWN => {
            let (x, y) = xy(lp);
            let button = match msg {
                WM_RBUTTONDOWN => Button::Right,
                WM_MBUTTONDOWN => Button::Middle,
                _ => Button::Left,
            };
            // CAPTURE, so a drag that leaves the window still reports its release.
            // Without it a press-drag-out-release leaves the UI stuck held down.
            let _ = SetCapture(hwnd);
            push(Event::PointerDown { x, y, button });
            LRESULT(0)
        }
        WM_LBUTTONUP | WM_RBUTTONUP | WM_MBUTTONUP => {
            let (x, y) = xy(lp);
            let button = match msg {
                WM_RBUTTONUP => Button::Right,
                WM_MBUTTONUP => Button::Middle,
                _ => Button::Left,
            };
            let _ = ReleaseCapture();
            push(Event::PointerUp { x, y, button });
            LRESULT(0)
        }
        WM_MOUSEWHEEL => {
            // WM_MOUSEWHEEL CARRIES SCREEN COORDINATES, unlike every other mouse
            // message. Forwarding them unconverted scrolls whatever happens to be
            // under that point in the wrong space — and on a window near the
            // bottom-right of a large display, that is nothing at all.
            let (sx, sy) = xy(lp);
            let mut point = windows::Win32::Foundation::POINT {
                x: sx as i32,
                y: sy as i32,
            };
            let _ = ScreenToClient(hwnd, &mut point);
            let delta = ((wp.0 >> 16) as i16) as f32 / 120.0;
            push(Event::Wheel {
                x: point.x as f32,
                y: point.y as f32,
                delta,
            });
            LRESULT(0)
        }
        WM_CHAR => {
            if let Some(c) = char::from_u32(wp.0 as u32) {
                // Control codes arrive here too; Backspace and Return are already
                // reported as named keys by WM_KEYDOWN, and passing them again as
                // characters would apply each twice.
                if !c.is_control() {
                    push(Event::Char(c));
                }
            }
            LRESULT(0)
        }
        WM_KEYDOWN => {
            if let Some(name) = key_name(wp.0 as u32) {
                push(Event::Key {
                    name: name.to_string(),
                    shift: modifier(VK_SHIFT),
                    ctrl: modifier(VK_CONTROL),
                });
            }
            LRESULT(0)
        }
        WM_SIZE => {
            let raw = lp.0 as u32;
            let width = (raw & 0xFFFF) as u32;
            let height = ((raw >> 16) & 0xFFFF) as u32;
            if width > 0 && height > 0 {
                push(Event::Resized { width, height });
            }
            LRESULT(0)
        }
        WM_PAINT => {
            // VALIDATE THE REGION, or Windows re-posts WM_PAINT forever and the
            // pump spins at 100% doing nothing. The frame loop repaints anyway;
            // this only records that the surface can no longer be patched.
            let mut ps = PAINTSTRUCT::default();
            let _ = BeginPaint(hwnd, &mut ps);
            let _ = EndPaint(hwnd, &ps);
            push(Event::Exposed);
            LRESULT(0)
        }
        WM_ERASEBKGND => {
            // CLAIM IT, so Windows does not clear to the class brush before every
            // paint. Left to the default, the window flashes its background
            // between frames.
            LRESULT(1)
        }
        WM_CLOSE => {
            push(Event::CloseRequested);
            LRESULT(0)
        }
        WM_DESTROY => {
            PostQuitMessage(0);
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, wp, lp),
    }
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

pub struct Window {
    hwnd: HWND,
    width: u32,
    height: u32,
}

impl Window {
    pub fn new(title: &str, width: u32, height: u32) -> Result<Window, String> {
        unsafe {
            let instance = GetModuleHandleW(None).map_err(|e| e.to_string())?;
            let class = wide("AetherWindow");

            // Registering twice returns an error that is not one — a second window
            // of the same class is fine and the class is already there. The
            // result is deliberately discarded rather than checked.
            let wc = WNDCLASSW {
                lpfnWndProc: Some(wndproc),
                hInstance: instance.into(),
                lpszClassName: PCWSTR(class.as_ptr()),
                hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
                ..Default::default()
            };
            let _ = RegisterClassW(&wc);

            // SIZE THE CLIENT AREA, not the window. `CreateWindowEx` takes the
            // outer rectangle, so passing the wanted size directly yields a client
            // area smaller by the border and caption — and every frame then
            // renders into a surface that does not match the window.
            let mut rect = RECT {
                left: 0,
                top: 0,
                right: width as i32,
                bottom: height as i32,
            };
            let _ = AdjustWindowRect(&mut rect, WS_OVERLAPPEDWINDOW, false);

            // BOUND TO A LOCAL, not written inline. `PCWSTR(wide(title).as_ptr())`
            // drops the Vec at the end of the enclosing expression, so the window
            // is created from a pointer into freed memory — which usually
            // "works", occasionally shows a garbage title, and is undefined
            // behaviour every time.
            let title_w = wide(title);

            let hwnd = CreateWindowExW(
                WINDOW_EX_STYLE::default(),
                PCWSTR(class.as_ptr()),
                PCWSTR(title_w.as_ptr()),
                WS_OVERLAPPEDWINDOW,
                CW_USEDEFAULT,
                CW_USEDEFAULT,
                rect.right - rect.left,
                rect.bottom - rect.top,
                None,
                None,
                Some(instance.into()),
                None,
            )
            .map_err(|e| e.to_string())?;

            let _ = ShowWindow(hwnd, SW_SHOW);

            Ok(Window {
                hwnd,
                width,
                height,
            })
        }
    }

    pub fn size(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    /// Drain everything the window has seen since the last call.
    ///
    /// Returns `None` when the window has quit and the shell should stop.
    pub fn poll(&mut self) -> Option<Vec<Event>> {
        unsafe {
            let mut msg = MSG::default();
            while PeekMessageW(&mut msg, None, 0, 0, PM_REMOVE).as_bool() {
                if msg.message == WM_QUIT {
                    return None;
                }
                let _ = TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        }

        let events = EVENTS.with(|e| std::mem::take(&mut *e.borrow_mut()));
        for event in &events {
            if let Event::Resized { width, height } = event {
                self.width = *width;
                self.height = *height;
            }
        }
        Some(events)
    }

    /// Put a BGRA buffer on screen. `bgra` must be `width * height * 4` bytes.
    pub fn blit(&self, bgra: &[u8], width: u32, height: u32) {
        if bgra.len() < (width * height * 4) as usize {
            return;
        }
        unsafe {
            let hdc: HDC = GetDC(Some(self.hwnd));
            if hdc.is_invalid() {
                return;
            }

            let info = BITMAPINFO {
                bmiHeader: BITMAPINFOHEADER {
                    biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                    biWidth: width as i32,
                    // NEGATIVE, for a TOP-DOWN bitmap. A DIB is bottom-up by
                    // default, so a positive height presents every frame flipped
                    // vertically — which reads as a renderer bug and is a header
                    // field.
                    biHeight: -(height as i32),
                    biPlanes: 1,
                    biBitCount: 32,
                    biCompression: BI_RGB.0,
                    ..Default::default()
                },
                ..Default::default()
            };

            StretchDIBits(
                hdc,
                0,
                0,
                self.width as i32,
                self.height as i32,
                0,
                0,
                width as i32,
                height as i32,
                Some(bgra.as_ptr() as *const _),
                &info,
                DIB_RGB_COLORS,
                SRCCOPY,
            );

            ReleaseDC(Some(self.hwnd), hdc);
        }
    }
}

impl Drop for Window {
    fn drop(&mut self) {
        unsafe {
            let _ = DestroyWindow(self.hwnd);
        }
    }
}
