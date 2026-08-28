//! Require resolution for the guest.
//!
//! Aether's own source uses relative string requires — `require("./Roblox")`,
//! `require("../TextInputManager")` — and resolves its packages through pesde's
//! generated redirect trees. Both are the Luau require-by-string RFC, which mlua
//! implements as [`FsRequirer`], including `.luaurc` alias tables. So the
//! framework loads here UNMODIFIED, which is the property that makes "the same
//! application on both hosts" mean anything at all.
//!
//! THE BASE VM HAS NO `require`. `Vm::new` removes it, and this module installs
//! one bounded to the granted roots. A guest that was never granted a root cannot
//! reach the filesystem through require at all, rather than reaching it through a
//! resolver that merely declines to help.

use crate::vm::{Capabilities, Vm};
use mlua::prelude::*;
use mlua::luau::FsRequirer;
use std::path::{Path, PathBuf};

/// Install `require` into the guest.
///
/// Returns `Ok(false)` when no roots were granted — not an error, because a guest
/// with no roots is a legitimate configuration (a mod supplied as a single
/// pre-loaded chunk, for instance) rather than a misconfiguration to shout about.
pub fn install(vm: &Vm, caps: &Capabilities) -> LuaResult<bool> {
    if caps.require_roots.is_empty() {
        return Ok(false);
    }
    let require = vm.lua().create_require_function(FsRequirer::default())?;
    vm.lua().globals().set("require", require)?;
    Ok(true)
}

/// Load a module as the guest's entry point.
///
/// THE `@` PREFIX IS NOT COSMETIC. `FsRequirer` only permits requires from chunks
/// whose name starts with `@`, because that is how it tells a chunk that has a
/// location on disk from one that was handed over as a string and therefore has
/// nothing to resolve relative paths against. A chunk named without it loads fine
/// and then fails on its first `require` with a message about the chunk name,
/// which reads like a bug in the module rather than in how it was loaded.
pub fn load_entry<'a>(vm: &'a Vm, path: &Path) -> LuaResult<LuaFunction> {
    let source = std::fs::read_to_string(path).map_err(|e| {
        LuaError::RuntimeError(format!("could not read entry module {}: {e}", path.display()))
    })?;

    // A BOM is not whitespace to the Luau lexer; it is an unexpected symbol on
    // line 1. Windows editors write one, and the resulting parse error points at
    // a character that is invisible in every editor that could show it.
    let source = source.strip_prefix('\u{feff}').unwrap_or(&source);

    // WITHOUT THE EXTENSION. `FsRequirer::resolve_module` appends `.luau` to
    // whatever it is given, so a chunk named `.../app.luau` sends it looking for
    // `.../app.luau.luau`, finds nothing, and reports `NavigateError::NotFound`.
    // That surfaces as "could not reset to requiring context" naming the module
    // the guest asked for — so the error points at a module that is present and
    // fine, while the path that is wrong belongs to the chunk asking for it.
    let mut stem = absolute(path);
    stem.set_extension("");

    let name = format!("@{}", stem.display());
    vm.lua().load(source).set_name(name).into_function()
}

/// An absolute path the requirer can navigate from.
///
/// An absolute path the requirer can navigate from.
///
/// `canonicalize` on Windows returns an EXTENDED-LENGTH path (the `\\?\C:\...`
/// form), and `FsRequirer` cannot reset its context to one: the guest's very
/// first require fails with "could not reset to requiring context". The message
/// names the module being required rather than the chunk doing the requiring, so
/// it reads as a missing module when what is wrong is the caller's own path.
fn absolute(path: &Path) -> PathBuf {
    const EXTENDED_LENGTH_PREFIX: &str = r"\\?\";
    let resolved = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    match resolved.to_string_lossy().strip_prefix(EXTENDED_LENGTH_PREFIX) {
        Some(stripped) => PathBuf::from(stripped),
        None => resolved,
    }
}
