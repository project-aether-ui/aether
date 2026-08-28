//! Driving a running application, frame by frame.
//!
//! This is a thin binding over `Live.Session` in `src/host/Live.luau`, and thin
//! is the whole design. Every decision an application makes — layout, hover
//! arbitration, focus, motion, what a click means — stays in Luau, exactly as it
//! does when Roblox is the host. Rust supplies frames, pointer positions and
//! keystrokes, and paints rectangles it did not choose.
//!
//! WHY THAT SPLIT AND NOT A MORE CONVENIENT ONE. Roblox divides a UI into an
//! engine that renders and reports, and an application that decides. If any of
//! the deciding leaked into Rust here, the desktop host would diverge from the
//! Roblox host the moment either changed — and it would diverge quietly, because
//! nothing type-checks "these two hosts agree". Keeping Rust ignorant is what
//! makes identical behaviour structural rather than aspirational.

use crate::frame::{Delta, Frame};
use mlua::prelude::*;

/// A pointer event kind, spelled as `Live.Session` expects it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pointer {
    Move,
    Down,
    Up,
}

impl Pointer {
    fn as_str(self) -> &'static str {
        match self {
            Pointer::Move => "move",
            Pointer::Down => "down",
            Pointer::Up => "up",
        }
    }
}

/// Modifier state accompanying a key.
#[derive(Debug, Clone, Copy, Default)]
pub struct Modifiers {
    pub shift: bool,
    pub ctrl: bool,
}

impl Modifiers {
    fn is_empty(self) -> bool {
        !self.shift && !self.ctrl
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub struct Stats {
    pub frames: u64,
    pub events: u64,
    pub sent: u64,
    pub skipped: u64,
}

/// A mounted application being driven by this process.
pub struct Session {
    /// Held so modifier tables are built in the state the session belongs to.
    /// `Lua` is a handle rather than the interpreter, so this is a refcount bump.
    lua: Lua,
    step: LuaFunction,
    pointer: LuaFunction,
    wheel: LuaFunction,
    key: LuaFunction,
    snapshot: LuaFunction,
    snapshot_delta: LuaFunction,
    stats: LuaFunction,
}

impl Session {
    /// Bind to a `Live.Session` table returned by the guest.
    pub fn from_lua(lua: &Lua, t: &LuaTable) -> LuaResult<Self> {
        Ok(Session {
            lua: lua.clone(),
            step: t.get("Step")?,
            pointer: t.get("Pointer")?,
            wheel: t.get("Wheel")?,
            key: t.get("Key")?,
            snapshot: t.get("Snapshot")?,
            snapshot_delta: t.get("SnapshotDelta")?,
            stats: t.get("Stats")?,
        })
    }

    /// Advance one frame.
    ///
    /// THE ORDER INSIDE IS NOT OURS TO CHOOSE and is worth knowing anyway: the
    /// clock moves first because motion changes geometry, then the router settles
    /// because an element that moved under a stationary pointer has changed what
    /// is hovered. Roblox never reports that second case — it is why the router
    /// polls at all — so a host that drives its own frames must pump it, or hover
    /// goes stale the moment anything animates.
    pub fn step(&self, dt: f32) -> LuaResult<()> {
        self.step.call(dt)
    }

    pub fn pointer(&self, kind: Pointer, x: f32, y: f32) -> LuaResult<()> {
        self.pointer.call((kind.as_str(), x, y))
    }

    /// Wheel input in scroll steps; positive scrolls the content up.
    pub fn wheel(&self, x: f32, y: f32, delta: f32) -> LuaResult<()> {
        self.wheel.call((x, y, delta))
    }

    /// Feed a key to whatever field is focused. Returns whether it was consumed.
    ///
    /// ACT ON THE ANSWER. A key the guest consumed must not also reach the shell's
    /// own accelerators, or typing "q" into a focused text field quits the
    /// application. `Frame::focused` exists for the cases where the shell has to
    /// decide before asking.
    pub fn key(&self, key: &str, modifiers: Modifiers) -> LuaResult<bool> {
        if modifiers.is_empty() {
            // nil rather than an empty table: Live.Session's signature makes the
            // argument optional, and the two spellings should not diverge.
            return self.key.call((key, LuaValue::Nil));
        }
        let mods = self.lua.create_table()?;
        mods.set("Shift", modifiers.shift)?;
        mods.set("Ctrl", modifiers.ctrl)?;
        self.key.call((key, mods))
    }

    pub fn snapshot(&self) -> LuaResult<Frame> {
        let t: LuaTable = self.snapshot.call(())?;
        Frame::from_lua(&t)
    }

    /// What changed since the last call. Pass `true` for a full delta — every
    /// node and the paint order, as though the display had never been sent
    /// anything, which is what a resized or newly attached surface needs.
    pub fn delta(&self, full: bool) -> LuaResult<Delta> {
        let t: LuaTable = self.snapshot_delta.call(full)?;
        Delta::from_lua(&t)
    }

    pub fn stats(&self) -> LuaResult<Stats> {
        let t: LuaTable = self.stats.call(())?;
        Ok(Stats {
            frames: t.get("Frames").unwrap_or(0),
            events: t.get("Events").unwrap_or(0),
            sent: t.get("Sent").unwrap_or(0),
            skipped: t.get("Skipped").unwrap_or(0),
        })
    }
}
