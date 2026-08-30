//! Driving a real press through a real session.
//!
//! The router's own suites call `PointerRouter.Input` against hand-registered
//! records, which is a genuine unit test of arbitration and skips everything
//! between a TREE and a hit: mounting, layout, bounds being written back, and
//! the router finding a pressable it was never told about directly.
//!
//! A pressable that renders and does not respond passes every one of those
//! suites, which is how this went unnoticed.

use aether_runtime::{Application, Capabilities, Pointer};
use mlua::Function;
use std::path::PathBuf;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .expect("repo root")
        .to_path_buf()
}

fn app() -> Application {
    let entry = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/pressable.luau");
    Application::load(Capabilities::cli(repo_root()), &entry).expect("fixture loads")
}

/// The button occupies (20,20)-(120,60); this is its middle.
const INSIDE: (f32, f32) = (70.0, 40.0);

#[test]
fn a_press_inside_a_pressable_fires_it() {
    let app = app();
    let session = app.session().unwrap();
    let presses: Function = app.get("Presses").unwrap();

    // Step first: layout has to have run and written bounds back, or the router
    // resolves against a tree whose rectangles are all zero.
    session.step(1.0 / 60.0).unwrap();

    session.pointer(Pointer::Down, INSIDE.0, INSIDE.1).unwrap();
    session.pointer(Pointer::Up, INSIDE.0, INSIDE.1).unwrap();

    let count: i32 = presses.call(()).unwrap();
    assert_eq!(count, 1, "the press never reached the pressable");
}

#[test]
fn a_press_outside_it_does_not() {
    let app = app();
    let session = app.session().unwrap();
    let presses: Function = app.get("Presses").unwrap();

    session.step(1.0 / 60.0).unwrap();
    session.pointer(Pointer::Down, 180.0, 90.0).unwrap();
    session.pointer(Pointer::Up, 180.0, 90.0).unwrap();

    let count: i32 = presses.call(()).unwrap();
    assert_eq!(count, 0, "a press outside the pressable fired it anyway");
}

#[test]
fn moving_over_it_reports_hover() {
    let app = app();
    let session = app.session().unwrap();
    let hovers: Function = app.get("Hovers").unwrap();

    session.step(1.0 / 60.0).unwrap();
    session.pointer(Pointer::Move, INSIDE.0, INSIDE.1).unwrap();
    session.step(1.0 / 60.0).unwrap();

    let count: i32 = hovers.call(()).unwrap();
    assert!(count >= 1, "hover never reached the pressable");
}


/// `OnActivated` is what a button should use, and it is not `OnPressed`.
///
/// A press followed by a release INSIDE the element activates it; a press that
/// wanders off and releases elsewhere must not. Worth pinning separately because
/// a widget wired to `OnPressed` fires on mouse-down and cannot be cancelled,
/// which is a subtly wrong button rather than a broken one.
#[test]
fn activation_needs_a_press_and_a_release_inside() {
    let app = app();
    let session = app.session().unwrap();
    let activations: Function = app.get("Activations").unwrap();

    session.step(1.0 / 60.0).unwrap();

    session.pointer(Pointer::Down, INSIDE.0, INSIDE.1).unwrap();
    session.pointer(Pointer::Up, INSIDE.0, INSIDE.1).unwrap();
    assert_eq!(
        activations.call::<i32>(()).unwrap(),
        1,
        "press and release inside should activate"
    );

    // Press inside, release outside: not an activation.
    session.pointer(Pointer::Down, INSIDE.0, INSIDE.1).unwrap();
    session.pointer(Pointer::Up, 180.0, 90.0).unwrap();
    assert_eq!(
        activations.call::<i32>(()).unwrap(),
        1,
        "releasing outside the element should not activate it"
    );
}
