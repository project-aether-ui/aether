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

pub mod driver;
pub mod font;
pub mod frame;
pub mod modules;
pub mod painter;

#[cfg(feature = "raster")]
pub mod raster;
pub mod session;
pub mod vm;

pub use driver::Driver;
pub use frame::{Delta, Frame, Node, Rect, Rgb};
pub use painter::Painter;
#[cfg(feature = "raster")]
pub use raster::RasterPainter;
pub use session::{Modifiers, Pointer, Session, Stats};
pub use vm::{Capabilities, Vm};

use mlua::prelude::*;
use std::path::{Path, PathBuf};

/// Drop Windows' extended-length path prefix.
///
/// `canonicalize` returns the extended-length form (backslash, backslash,
/// question mark, backslash, then the drive), and almost nothing downstream
/// accepts it: `FsRequirer` cannot reset its context to one, and it survives into
/// a `.luaurc` as `//?/C:/...`, where it reads as a UNC host rather than a drive.
/// Both failures point somewhere other than the path.
///
/// The prefix is spelled out in prose above because it is four characters of
/// pure backslash-escaping, and a draft of this function shipped with one too
/// few — matching nothing, stripping nothing, and leaving every symptom intact.
pub fn strip_extended_prefix(path: PathBuf) -> PathBuf {
    const PREFIX: &str = r"\\?\";
    match path.to_string_lossy().strip_prefix(PREFIX) {
        Some(stripped) => PathBuf::from(stripped),
        None => path,
    }
}

/// Where Aether's own Luau source sits, relative to this crate.
///
/// THE POINT IS THAT A HOST NEEDS NO PATH OF ITS OWN. A consumer pins this crate
/// by commit; the framework's Luau lives in the same repository, so the checkout
/// Cargo already made IS the matching source — same revision, by construction,
/// with nothing to keep in step by hand.
///
/// A host that instead configured "../aether/src" would be carrying a second,
/// unpinned dependency on the same thing: correct only while two checkouts
/// happen to agree, and silently wrong the moment they do not.
///
/// `CARGO_MANIFEST_DIR` is baked at compile time — for a git dependency that is
/// the vendored checkout under `~/.cargo/git`, and in this workspace it is the
/// crate directory. Returns `None` if the layout is not there, which is a real
/// possibility for a vendoring scheme that flattens crates.
pub fn luau_source_root() -> Option<PathBuf> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("..");
    let src = root.join("src");
    src.is_dir()
        .then(|| strip_extended_prefix(root.canonicalize().unwrap_or_else(|_| root.clone()))) 
}

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

    /// Read any other field the entry module returned.
    ///
    /// Entry points expose more than a `Session` — a size to open a window at, a
    /// transition a shell can drive, a title. Rather than growing a struct field
    /// per convention, a shell asks for what it knows it needs and handles the
    /// absence: an entry written for the CLI should not fail to load under Dew
    /// merely because it omitted something Dew never reads.
    pub fn get<T: FromLua>(&self, field: &str) -> LuaResult<T> {
        self.entry.get(field)
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
