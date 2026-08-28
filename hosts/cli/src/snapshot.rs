//! `aether snapshot` — one frame to a PNG.
//!
//! NEEDS NO DISPLAY, which is the property worth protecting. It is what a CI job
//! runs to diff a component's appearance across a change, and what a Roblox
//! author uses to see their UI without opening Studio. Both of those happen on
//! machines with no window server, so nothing here may reach for one.

use crate::Args;
use aether_raster::{Backend, Font};
use aether_runtime::{Application, Capabilities, Driver, RasterPainter, Rgb};

/// The size an entry point asks for, or a default.
///
/// An entry MAY expose `Width`/`Height`; nothing requires it, because an entry
/// written before those existed should still render rather than fail on a field
/// it never heard of.
pub fn size_of(app: &Application, override_size: Option<(u32, u32)>) -> (u32, u32) {
    if let Some(size) = override_size {
        return size;
    }
    let width: u32 = app.get("Width").unwrap_or(0);
    let height: u32 = app.get("Height").unwrap_or(0);
    if width > 0 && height > 0 {
        (width, height)
    } else {
        (480, 270)
    }
}

/// Build a painter with a system face attached where there is one.
///
/// VELLO, NOT TINY-SKIA. tiny-skia is a shape backend with no text at all, so a
/// component's labels would silently vanish from the output — a snapshot that
/// looks like a layout bug and is a backend choice.
pub fn painter(width: u32, height: u32) -> Result<RasterPainter, String> {
    let mut painter = RasterPainter::new(width, height, Backend::VelloCpu)
        .ok_or("could not create a drawing surface")?;

    match aether_runtime::font::system_font() {
        Some(path) => match Font::load(&path.to_string_lossy(), 0) {
            Some(font) => painter = painter.with_font(font),
            // Named rather than silent: text will be missing from the output and
            // the reason should not have to be guessed at from the picture.
            None => eprintln!("aether: found {} but could not load it; text will be missing", path.display()),
        },
        None => eprintln!("aether: no system font found; text will be missing"),
    }

    Ok(painter)
}

pub fn run(args: &Args) -> Result<(), String> {
    let root = args
        .entry
        .parent()
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_default());

    let app = Application::load(Capabilities::cli(root), &args.entry)
        .map_err(|e| format!("could not load {}: {e}", args.entry.display()))?;

    let (width, height) = size_of(&app, args.size);
    let session = app.session().map_err(|e| e.to_string())?;
    let mut driver = Driver::new(session, painter(width, height)?, Some(Rgb(0, 0, 0)));

    // STEP BEFORE DRAWING, at least once. A spring has not moved on frame zero
    // and a component that positions itself in an effect has not run one, so a
    // snapshot taken without stepping shows a layout nobody will ever see.
    for _ in 0..args.frames.max(1) {
        driver
            .frame(1.0 / 60.0)
            .map_err(|e| format!("while rendering: {e}"))?;
    }

    let out = args.out.to_string_lossy().to_string();
    driver
        .painter_mut()
        .write_png(&out)
        .map_err(|code| format!("could not write {out}: rasteriser status {code}"))?;

    println!("wrote {out} ({width}x{height})");
    Ok(())
}
