//! The claim this crate exists to support, as a test.
//!
//! An Aether application is loaded into an embedded Luau guest, driven for a
//! frame, and its display list decoded in Rust — with the framework's own source
//! required unmodified, exactly as Roblox requires it. If this passes, "the same
//! application runs on both hosts" is a property of the build rather than an
//! intention.

use aether_runtime::{Application, Capabilities};
use std::path::PathBuf;

fn repo_root() -> PathBuf {
    // hosts/runtime -> hosts -> repo root
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(|p| p.parent())
        .expect("repo root")
        .to_path_buf()
}

fn fixture() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/app.luau")
}

fn load() -> Application {
    Application::load(Capabilities::cli(repo_root()), &fixture())
        .expect("the fixture application should load")
}

#[test]
fn an_application_loads_and_opens_a_session() {
    let app = load();
    app.session().expect("entry module should expose a Session");
}

#[test]
fn a_frame_carries_the_tree_the_application_declared() {
    let app = load();
    let session = app.session().unwrap();

    session.step(1.0 / 120.0).expect("step");
    let frame = session.snapshot().expect("snapshot");

    assert_eq!(frame.width, 200.0);
    assert_eq!(frame.height, 80.0);

    // The root and its label. Nodes with zero area are dropped by Live.luau, so
    // an empty list here means layout did not run rather than that the tree was
    // empty — which is the failure this asserts against.
    assert!(
        frame.nodes.len() >= 2,
        "expected the root and its label, got {} node(s)",
        frame.nodes.len()
    );

    let label = frame
        .nodes
        .iter()
        .find(|n| n.text.as_deref() == Some("aether"))
        .expect("the TextLabel should reach the display list with its text");

    assert_eq!(label.rect.w, 120.0);
    assert_eq!(label.rect.h, 24.0);
    assert_eq!(label.text_size, 16.0);
}

/// THE DEFAULT IS THE HALF THAT MATTERS. An unset `TextXAlignment` is CENTRE in
/// Roblox, and three painters once each invented a left inset instead. This
/// pins the default at the seam so a painter never has to decide it again.
#[test]
fn unset_text_alignment_decodes_as_centre() {
    use aether_runtime::frame::Align;

    let app = load();
    let session = app.session().unwrap();
    session.step(1.0 / 120.0).unwrap();
    let frame = session.snapshot().unwrap();

    let label = frame
        .nodes
        .iter()
        .find(|n| n.text.is_some())
        .expect("a text node");

    assert_eq!(label.text_align_x, Some(Align::Center));
    assert_eq!(label.text_align_y, Some(Align::Center));
}

/// An idle screen must produce no traffic. This is the property `Delta` exists
/// for, and the one a naive host loses by calling `snapshot()` every frame.
#[test]
fn an_idle_frame_reports_nothing_changed() {
    let app = load();
    let session = app.session().unwrap();

    session.step(1.0 / 120.0).unwrap();
    let first = session.delta(true).expect("first delta");
    assert!(
        !first.changed.is_empty(),
        "a forced full delta should carry every node"
    );

    session.step(1.0 / 120.0).unwrap();
    let second = session.delta(false).expect("second delta");
    assert!(
        second.changed.is_empty(),
        "nothing moved, so nothing should have been sent; got {} node(s)",
        second.changed.len()
    );
}

/// The guest must not be able to reach the host process. These are the names
/// that hand it one, and the sandbox is only meaningful if their absence is
/// checked rather than assumed.
#[test]
fn the_guest_has_no_escape_hatches() {
    let app = load();
    let lua = app.vm().lua();

    for name in ["io", "os", "package", "loadstring", "dofile", "loadfile"] {
        let value: mlua::Value = lua.globals().get(name).unwrap();
        assert!(
            value.is_nil(),
            "`{name}` is reachable from the guest — the sandbox is not closed"
        );
    }

    // AND THE OTHER DIRECTION, which is the half that actually bit. `debug` must
    // SURVIVE: Luau's carries only `info` and `traceback`, and vide calls
    // `debug.info` on the first line it executes. Asserting its presence keeps a
    // future tightening of the list above from silently breaking the framework.
    let debug: mlua::Table = lua.globals().get("debug").expect("Luau's debug must survive");
    assert!(debug.contains_key("info").unwrap());
}


/// The prefix strip is four characters of backslash-escaping and a draft shipped
/// with one too few — matching nothing and stripping nothing. Asserted rather
/// than eyeballed, because that is exactly the kind of literal a reader's eye
/// slides over.
#[test]
fn the_extended_length_prefix_is_stripped() {
    use aether_runtime::strip_extended_prefix;
    use std::path::PathBuf;

    // BUILT FROM CHARACTERS, not written as a literal. The prefix is four
    // characters of pure backslash and every tool between a keyboard and this
    // file has an opinion about them — the first draft of this test lost one in
    // transit and then failed against a library that was correct, which is the
    // most expensive way for a test to be wrong.
    let prefix: String = ['\\', '\\', '?', '\\'].iter().collect();
    let tail = r"C:\Users\someone\aether\src";

    assert_eq!(
        strip_extended_prefix(PathBuf::from(format!("{prefix}{tail}"))),
        PathBuf::from(tail)
    );

    // An ordinary path is returned untouched.
    let plain = PathBuf::from(r"C:\Users\someone\aether\src");
    assert_eq!(strip_extended_prefix(plain.clone()), plain);
}
