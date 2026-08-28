//! `aether_runtime` — the Rust-owned host runtime for Aether.
//!
//! ## What this is for
//!
//! An Aether application is a Luau module. On Roblox, the engine hosts it: it
//! lays out, it paints, and `UserInputService` reports input. Off Roblox, THIS
//! crate is the engine — it owns the process, embeds Luau as a guest, drives
//! frames, and hands a display list to a painter.
//!
//! The same application source runs on both. That is the point, and it is
//! structural rather than aspirational: `Host.detect()` in the framework picks
//! its host by environment, and everything that decides anything about a UI
//! stays in Luau on both sides. Rust never decides where a thing goes or what a
//! click means.
//!
//! ```text
//!   Aether (Luau)  ──Live.Frame──>  aether_runtime  ──>  impl Painter
//!        ^                                │
//!        └────── Pointer / Key / Step ────┘
//! ```
//!
//! ## Two shells, one runtime
//!
//! The `aether` CLI and the Dew desktop platform both build on this crate and
//! differ ONLY in which capabilities they grant. The CLI runs the author's own
//! code, the way `cargo run` does; Dew runs code fetched from strangers. Neither
//! gets a different pipeline, and neither gets a VM that skips the sandbox — see
//! [`vm`] for why the trusted shell takes the guarded path too.
//!
//! ## What this crate deliberately does not contain
//!
//! No window, no swapchain, no `ffi`, and no `libloading`. Windows and surfaces
//! belong to a shell; native code belongs to a painter behind [`painter::Painter`].
//! The guest reaches the outside world only through capability tables the host
//! installs by name, which is the property that makes a permission model possible
//! at all.

pub mod frame;
pub mod modules;
pub mod painter;

#[cfg(feature = "raster")]
pub mod raster;
pub mod session;
pub mod vm;

pub use frame::{Delta, Frame, Node, Rect, Rgb};
pub use painter::Painter;
#[cfg(feature = "raster")]
pub use raster::RasterPainter;
pub use session::{Modifiers, Pointer, Session, Stats};
pub use vm::{Capabilities, Vm};

use mlua::prelude::*;
use std::path::Path;

/// A loaded application, before it is driven.
pub struct Application {
    vm: Vm,
    /// The value the entry module returned. Held as a registry-independent handle
    /// so the shell can hand it back to the framework when it opens a session.
    entry: LuaTable,
}

impl Application {
    /// Load an application's entry module under a fresh guest VM.
    ///
    /// The entry module must return a table carrying a `Session` field — the
    /// result of `Live.Session(host, root, router, w, h)`. That indirection is
    /// deliberate: it keeps the decision of HOW to mount (which root, which
    /// router, which dimensions) in Luau, where the Roblox entry point makes the
    /// same decision with the same code.
    pub fn load(caps: Capabilities, entry: &Path) -> LuaResult<Self> {
        let vm = Vm::new(caps.clone())?;
        modules::install(&vm, &caps)?;
        let chunk = modules::load_entry(&vm, entry)?;
        let entry: LuaTable = chunk.call(())?;
        Ok(Application { vm, entry })
    }

    pub fn vm(&self) -> &Vm {
        &self.vm
    }

    /// Bind to the application's `Live.Session`.
    pub fn session(&self) -> LuaResult<Session> {
        let t: LuaTable = self.entry.get("Session").map_err(|_| {
            LuaError::RuntimeError(
                "the entry module returned no `Session` field — an Aether application's \
                 entry point returns { Session = Live.Session(...) }"
                    .into(),
            )
        })?;
        Session::from_lua(self.vm.lua(), &t)
    }
}
