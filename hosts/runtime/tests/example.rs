//! The shared example, driven and drawn.
//!
//! `examples/counter/src/Counter.luau` is loaded here through its DESKTOP entry
//! point. The same component file is mounted by `entry/roblox.client.luau` inside
//! a place. Nothing in the component differs between the two, and this suite is
//! what keeps that true — if the shared file grows a dependency on either host,
//! it stops loading here.
//!
//! It also exercises `Driver`, which is the loop both native shells run, rather
//! than calling `Session` directly the way `parity.rs` does. Two things are
//! therefore under test at once, deliberately: the example, and the code path a
//! real shell will take to run it.

#![cfg(feature = "raster")]

use aether_raster::{Backend, Font};
use aether_runtime::{Application, Capabilities, Driver, Rgb};
use mlua::Function;
use std::path::PathBuf;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .expect("repo root")
        .to_path_buf()
}

fn entry() -> PathBuf {
    repo_root().join("examples/counter/entry/desktop.luau")
}

fn app() -> Application {
    Application::load(Capabilities::cli(repo_root()), &entry())
        .expect("the shared example should load through its desktop entry")
}

fn driver() -> Driver<aether_runtime::RasterPainter> {
    let app = app();
    let session = app.session().expect("session");

    let mut painter =
        aether_runtime::RasterPainter::new(240, 96, Backend::VelloCpu).expect("surface");
    if let Some(path) = aether_runtime::font::system_font() {
        if let Some(font) = Font::load(&path.to_string_lossy(), 0) {
            painter = painter.with_font(font);
        }
    }

    // The application is kept alive by the Driver holding its Session, which
    // holds the Lua handles. Leaking it here is deliberate and local to the test:
    // dropping the Application would drop the VM out from under the session.
    std::mem::forget(app);

    Driver::new(session, painter, Some(Rgb(0, 0, 0)))
}

#[test]
fn the_shared_component_loads_off_engine() {
    let _ = driver();
}

/// The first frame must be FULL — the surface holds nothing a delta could patch.
#[test]
fn the_first_frame_paints_everything() {
    let mut driver = driver();
    let painted = driver.frame(1.0 / 120.0).expect("frame");
    assert!(
        painted,
        "the first frame must paint; there is nothing to patch"
    );
}

/// And the second must not, because nothing moved.
///
/// This is the property that lets a desktop host idle instead of burning a core
/// repainting an unchanged screen, and it is the reason `Driver::frame` answers
/// with a bool rather than nothing.
#[test]
fn an_unchanged_second_frame_paints_nothing() {
    let mut driver = driver();
    driver.frame(1.0 / 120.0).expect("first");
    let painted = driver.frame(1.0 / 120.0).expect("second");
    assert!(
        !painted,
        "nothing changed, so nothing should have been painted"
    );
}

/// Writes the example out so it can be compared against the same component
/// running in Studio.
#[test]
fn writes_the_example_png() {
    let mut driver = driver();
    driver.frame(1.0 / 120.0).expect("frame");

    let out = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/counter.png");
    if let Some(parent) = out.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let path = out.to_string_lossy().to_string();
    driver.painter_mut().write_png(&path).expect("png");

    let size = std::fs::metadata(&path).expect("exists").len();
    assert!(size > 0);
    println!("wrote {path} ({size} bytes)");
}

/// THE REACTIVE GRAPH DRIVES THE DISPLAY LIST, off-engine, with no engine to
/// write properties back.
///
/// The component gives `Text` a FUNCTION of a `source`. On Roblox vide reacts by
/// assigning the property and the engine repaints. Here nothing assigns anything
/// — the same graph simply produces a different `Live.Frame` on the next solve.
/// A static tree would pass every other test in this file and fail this one, so
/// this is the assertion that the two hosts share behaviour rather than merely
/// sharing a file.
#[test]
fn incrementing_changes_what_is_rendered() {
    let app = app();
    let session = app.session().expect("session");
    let increment: Function = app.get("Increment").expect("the entry exposes Increment");

    session.step(1.0 / 120.0).expect("step");
    let before = session.snapshot().expect("snapshot");
    // BY CONTENT, not by position. The first text node is the title; picking
    // `nodes[0]` would assert against "aether counter" and pass or fail for
    // reasons unrelated to the counter.
    let text_before = before
        .nodes
        .iter()
        .filter_map(|n| n.text.clone())
        .find(|t| t.contains("count:"))
        .expect("the value label should carry the count");
    assert!(
        text_before.contains("count: 0"),
        "expected the initial count, got {text_before:?}"
    );

    increment.call::<()>(()).expect("increment");
    session.step(1.0 / 120.0).expect("step");

    let after = session.snapshot().expect("snapshot");
    let texts: Vec<String> = after.nodes.iter().filter_map(|n| n.text.clone()).collect();
    assert!(
        texts.iter().any(|t| t.contains("count: 1")),
        "the reactive update never reached the display list; texts were {texts:?}"
    );
}

/// A small change must produce a small dirty rectangle, and a cheaper paint.
///
/// This is the property the damage-clipped repaint rests on. Without it
/// `paint_delta` clips to a rectangle covering everything and saves nothing,
/// which would look exactly like working code on a small surface and cost 30ms a
/// frame on a desktop-sized one.
#[test]
fn a_small_change_dirties_a_small_rectangle() {
    let app = app();
    let session = app.session().expect("session");
    let increment: mlua::Function = app.get("Increment").expect("Increment");

    session.step(1.0 / 60.0).unwrap();
    let full = session.delta(true).expect("full delta");
    let (fw, fh) = (full.frame.width, full.frame.height);

    // A forced full delta covers the surface, which is what makes it full.
    let covers_all = full.dirty.map(|d| d.w >= fw && d.h >= fh).unwrap_or(true);
    assert!(covers_all, "a forced full delta should dirty everything");

    increment.call::<()>(()).expect("increment");
    session.step(1.0 / 60.0).unwrap();

    let delta = session.delta(false).expect("delta");
    let dirty = delta
        .dirty
        .expect("changing the count should dirty something");

    let changed_area = dirty.w * dirty.h;
    let whole = fw * fh;
    assert!(
        changed_area < whole / 2.0,
        "one label changed but the dirty rect covers {:.0}% of the frame \
         ({}x{} of {fw}x{fh}) — the damage-clipped repaint saves nothing",
        100.0 * changed_area / whole,
        dirty.w,
        dirty.h
    );

    println!(
        "dirty {:.0}x{:.0} of {fw:.0}x{fh:.0} — {:.1}% of the surface",
        dirty.w,
        dirty.h,
        100.0 * changed_area / whole
    );
}
