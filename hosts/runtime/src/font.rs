//! Finding a face to draw with.
//!
//! NO DEPENDENCY ON A RASTERISER. This answers with a PATH, and whoever owns a
//! font store turns that into a loaded face. Both native shells need the same
//! answer and neither should have to carry the other's backend to get it.
//!
//! IT IS A FALLBACK, NOT A FONT SYSTEM. The display list carries no font name
//! yet — `Live.Frame` has `textSize` and alignment and nothing that selects a
//! family — so there is exactly one face in play and pretending otherwise would
//! create a second place for text to diverge between hosts. When the frame grows
//! a font name this becomes the default arm of a real lookup.

use std::path::{Path, PathBuf};

/// Candidates in preference order, per platform.
///
/// Deliberately a short list of faces that ship with the OS rather than a full
/// fontconfig walk: this needs to answer on a bare CI container as reliably as on
/// a desktop, and a wrong-but-present face is a better failure than none.
const CANDIDATES: &[&str] = &[
    // Windows
    "C:/Windows/Fonts/segoeui.ttf",
    "C:/Windows/Fonts/arial.ttf",
    "C:/Windows/Fonts/tahoma.ttf",
    // Linux
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    // macOS
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
];

/// The first system face that exists, or `None`.
///
/// `None` is a legitimate answer and callers must handle it rather than
/// unwrapping: a shell that panics here has turned "this container has no fonts"
/// into "the renderer is broken", which sends the next person looking in the
/// wrong place entirely.
pub fn system_font() -> Option<PathBuf> {
    CANDIDATES
        .iter()
        .map(Path::new)
        .find(|p| p.is_file())
        .map(Path::to_path_buf)
}

/// A monospace face, for anything that must align in columns.
pub fn system_mono() -> Option<PathBuf> {
    const MONO: &[&str] = &[
        "C:/Windows/Fonts/consola.ttf",
        "C:/Windows/Fonts/CascadiaCode.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/System/Library/Fonts/Menlo.ttc",
    ];
    MONO.iter()
        .map(Path::new)
        .find(|p| p.is_file())
        .map(Path::to_path_buf)
        .or_else(system_font)
}
