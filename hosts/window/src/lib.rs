//! A native window, a message pump, and a blit.
//!
//! What a shell needs from a platform and nothing more. It reports input as
//! plain values and takes pixels as a byte slice, so it knows nothing about
//! Aether, Luau, or which rasteriser drew the frame.
//!
//! ## Events, not callbacks
//!
//! [`Window::poll`] drains the queue into a `Vec<Event>` rather than dispatching
//! through a closure. A Win32 window procedure runs on the OS's stack, inside
//! `DispatchMessage`, and calling into a Luau VM from there means the guest can
//! re-enter the pump — which is how a nested modal loop ends up stepping the
//! clock twice for one frame. Draining first keeps the guest on our stack, where
//! the shell decides when it runs.

#![cfg(windows)]

mod win32;

pub use win32::Window;

/// What kind of surface a window is.
///
/// NOT A FLAG ON ONE STRUCT, because the two differ in what they can be asked.
/// A widget has an anchor and no title; a window has a title and no anchor, and
/// letting either set the other's fields means a setting that is silently
/// ignored — which is how a manifest becomes decoration.
#[derive(Debug, Clone, PartialEq)]
pub enum Surface {
    /// An ordinary window: caption, border, resizable, in the taskbar.
    ///
    /// What a developer previewing a component wants, and what a settings panel
    /// or a log viewer should be.
    Window { title: String },

    /// A floating widget: no chrome, always on top, out of the taskbar, and
    /// PER-PIXEL TRANSPARENT.
    ///
    /// The Rainmeter shape. The window's visible silhouette is whatever the tree
    /// painted — rounded corners and soft edges included — because the surface is
    /// composited from a premultiplied buffer rather than blitted into a
    /// rectangle. `WS_EX_LAYERED` with `UpdateLayeredWindow` does this on an
    /// ordinary DIB, so it needs no swapchain and no DirectComposition.
    Widget {
        /// Screen position of the top-left corner.
        x: i32,
        y: i32,
        /// Let clicks fall through to whatever is behind. A monitor that only
        /// displays wants this; anything with a control does not.
        click_through: bool,
    },
}

/// Which mouse button, spelled the way a shell wants to match on it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Button {
    Left,
    Right,
    Middle,
}

/// Something the window saw.
///
/// Coordinates are CLIENT-RELATIVE and in physical pixels — the same space the
/// display list uses, so a shell forwards them without converting. The one place
/// that is not free is the wheel, which Win32 reports in screen coordinates; that
/// conversion happens inside rather than being left as a trap for each caller.
#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    PointerMove { x: f32, y: f32 },
    PointerDown { x: f32, y: f32, button: Button },
    PointerUp { x: f32, y: f32, button: Button },
    /// Positive scrolls the content up, matching `Live.Session`'s own sign.
    Wheel { x: f32, y: f32, delta: f32 },
    /// A typed character, already decoded from the platform's encoding.
    Char(char),
    /// A named key that produces no character — "Backspace", "Left", "Return".
    Key { name: String, shift: bool, ctrl: bool },
    Resized { width: u32, height: u32 },
    /// The surface must be fully repainted; nothing can be patched.
    Exposed,
    CloseRequested,
}
