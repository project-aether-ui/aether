//! The guest VM, and what it is allowed to touch.
//!
//! DENY BY DEFAULT, FOR EVERY SHELL INCLUDING THE TRUSTED ONE.
//!
//! It is tempting to give the CLI an unrestricted VM — it runs the author's own
//! code, the way `cargo run` does — and to switch on the sandbox only for Dew,
//! which runs code fetched from strangers. That would leave the boundary Dew's
//! security depends on as a path only Dew ever takes, and therefore the one path
//! that is never exercised while anyone is watching. So both shells take the same
//! path and differ only in what they hand [`Vm::grant`].

use mlua::prelude::*;
use std::path::PathBuf;

/// What the guest may reach, beyond pure Luau.
///
/// Every field defaults to the closed position. A shell opens what it needs by
/// name, so the set of things a guest can do is a value that can be printed,
/// diffed against a manifest, and asserted on in a test — rather than a property
/// of whichever globals happened to survive setup.
#[derive(Debug, Clone, Default)]
pub struct Capabilities {
    /// Roots the require resolver may descend into. Empty means the guest cannot
    /// require anything outside what is already loaded.
    pub require_roots: Vec<PathBuf>,
    /// Let the guest print. Harmless in a CLI, noise in a desktop host, and worth
    /// naming rather than assuming either way.
    pub print: bool,

    /// Aliases the HOST supplies, by name without the `@`.
    ///
    /// For dependencies that Aether declares and a host installs — `vide` above
    /// all. A `.luaurc` cannot serve these: aliases resolve by walking up from
    /// the requiring FILE, and when Aether is a pinned dependency its source is
    /// in a package cache no file of the host's is anywhere near.
    pub aliases: std::collections::HashMap<String, PathBuf>,
}

impl Capabilities {
    /// The set the `aether` CLI grants itself: the author's own project, and
    /// stdout. Written down as a named constructor rather than assembled inline
    /// at the call site, so "what the CLI allows" is one greppable answer.
    pub fn cli(project_root: impl Into<PathBuf>) -> Self {
        Capabilities {
            require_roots: vec![project_root.into()],
            print: true,
            ..Default::default()
        }
    }
}

pub struct Vm {
    lua: Lua,
}

impl Vm {
    /// A guest with nothing granted.
    ///
    /// `Lua::new()` opens the standard libraries, so the closing is done here and
    /// EXPLICITLY, by name. A shorter route would be to build from an empty state
    /// and add back what is wanted, and it is rejected on purpose: the list below
    /// is auditable, and a reviewer can check it against what Luau actually ships.
    /// A missing entry is then a visible omission rather than an invisible one.
    pub fn new(caps: Capabilities) -> LuaResult<Self> {
        let lua = Lua::new();

        {
            let globals = lua.globals();

            // THE ESCAPE HATCHES. Each of these hands the guest the host process:
            // `os.execute` and `io.open` directly, `package` through `loadlib` and
            // the C path, and `dofile`/`loadfile`/`loadstring` through arbitrary
            // chunks that our own require never resolved and no root ever bounded.
            //
            // `require` goes too, and comes back from `modules::install` bound to
            // the granted roots. A guest with no roots therefore has no require at
            // all, rather than one that merely declines.
            //
            // Removing a name that Luau does not ship is a no-op, and listing it
            // anyway is deliberate: this reads as the full inventory rather than
            // as the subset that happened to need removing on the day it was
            // written.
            for name in ["io", "os", "package", "dofile", "loadfile", "load", "loadstring", "require"]
            {
                globals.set(name, LuaValue::Nil)?;
            }

            // WHAT IS DELIBERATELY LEFT, AND WHY IT IS NOT AN OVERSIGHT.
            //
            // `debug` STAYS. Luau's is not Lua 5.1's, and the difference is the
            // whole argument: measured against this build it carries exactly
            // `info` and `traceback` — no `getupvalue`, no `setupvalue`, no
            // `sethook`, so none of the reaching-into-a-host-closure that makes
            // the name notorious. Removing it on reputation broke vide, whose
            // `flags.luau` calls `debug.info` on its first line to detect whether
            // it was compiled with optimisations. That failure surfaced eight
            // frames deep as "attempt to index nil with 'info'".
            //
            // `collectgarbage` and `getfenv`/`setfenv` stay for parity: Roblox
            // exposes all three, and a guest that behaves differently here is a
            // guest whose application no longer runs identically on both hosts.
            // `getfenv(0)` is also how the framework installs its value
            // vocabulary when there is no engine to supply `UDim2` and `Color3`.
            //
            // NONE OF THIS IS PER-MOD ISOLATION. This closes the hatches that
            // reach the process. Running several mutually untrusting mods means
            // one VM each, plus a policy for `getfenv` across them, and that is
            // Dew's to settle rather than something this crate can decide for it.

            if !caps.print {
                globals.set("print", LuaValue::Nil)?;
            }
        }

        Ok(Vm { lua })
    }

    pub fn lua(&self) -> &Lua {
        &self.lua
    }

    /// Install a capability table under a global name.
    ///
    /// This is the ONLY way anything reaches the guest from outside. There is no
    /// ambient alternative, which is what makes the grant list exhaustive by
    /// construction rather than by discipline.
    pub fn grant(&self, name: &str, table: LuaTable) -> LuaResult<()> {
        self.lua.globals().set(name, table)
    }
}
