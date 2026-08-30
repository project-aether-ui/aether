//! A requirer that lets the HOST supply aliases.
//!
//! WHY A `.luaurc` IS NOT ENOUGH. Aliases are resolved by walking up from the
//! REQUIRING FILE, so a config file only reaches modules underneath it. When
//! Aether is a dependency its source lives in someone's package cache — under
//! `~/.cargo/git/checkouts/…` for a commit pin — and no file a host can write in
//! its own repository is on that path. Dew hit this exactly: it wrote a
//! `.luaurc` naming `vide`, and `VideCore` never saw it, because `VideCore` is
//! in the checkout and the config was three directories and one package cache
//! away.
//!
//! Writing into the cache is not the answer either — it is shared, it is
//! regenerated, and it is not ours.
//!
//! `to_alias_fallback` is the seam Luau's own require system provides for this:
//! a last chance to resolve an alias after every config file has failed. So a
//! host registers what it supplies, in code, and it applies wherever the
//! requiring module happens to live.

use mlua::luau::{FsRequirer, NavigateError, Require};
use mlua::prelude::*;
use std::collections::HashMap;
use std::path::PathBuf;

pub struct HostRequirer {
    inner: FsRequirer,
    /// Alias name (without `@`) to the directory it stands for.
    aliases: HashMap<String, PathBuf>,
}

impl HostRequirer {
    pub fn new(aliases: HashMap<String, PathBuf>) -> Self {
        HostRequirer {
            inner: FsRequirer::default(),
            aliases,
        }
    }
}

impl Require for HostRequirer {
    fn is_require_allowed(&self, chunk_name: &str) -> bool {
        self.inner.is_require_allowed(chunk_name)
    }

    fn reset(&mut self, chunk_name: &str) -> Result<(), NavigateError> {
        self.inner.reset(chunk_name)
    }

    fn jump_to_alias(&mut self, path: &str) -> Result<(), NavigateError> {
        self.inner.jump_to_alias(path)
    }

    /// AFTER the config files, not before.
    ///
    /// Deliberately `to_alias_fallback` rather than `to_alias_override`: a
    /// package that ships its own `.luaurc` should keep winning for its own
    /// aliases, and the host fills the gaps. An override would let a host
    /// silently redirect a dependency's internal requires, which is a much
    /// larger power than "supply what I was asked for".
    fn to_alias_fallback(&mut self, alias: &str) -> Result<(), NavigateError> {
        match self.aliases.get(alias) {
            Some(path) => self.inner.jump_to_alias(&path.to_string_lossy()),
            None => Err(NavigateError::NotFound),
        }
    }

    fn to_parent(&mut self) -> Result<(), NavigateError> {
        self.inner.to_parent()
    }

    fn to_child(&mut self, name: &str) -> Result<(), NavigateError> {
        self.inner.to_child(name)
    }

    fn has_module(&self) -> bool {
        self.inner.has_module()
    }

    fn cache_key(&self) -> String {
        self.inner.cache_key()
    }

    fn has_config(&self) -> bool {
        self.inner.has_config()
    }

    fn config(&self) -> std::io::Result<Vec<u8>> {
        self.inner.config()
    }

    fn loader(&self, lua: &Lua) -> LuaResult<LuaFunction> {
        self.inner.loader(lua)
    }
}
