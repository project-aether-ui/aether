//! One frame, end to end — the loop both native shells run.
//!
//! `aether preview` and Dew differ in what surrounds this: one opens a window for
//! a developer's own project, the other manages many windows, hotkeys and a mod
//! sandbox. Neither differs in what a FRAME is, and writing that out twice is how
//! the two would slowly start disagreeing about when to step the clock or when a
//! full repaint is required.
//!
//! Generic over the painter on purpose: the same driver runs a CPU surface
//! writing PNGs and a swapchain presenting to a window.

use crate::frame::Rgb;
use crate::painter::Painter;
use crate::session::{Modifiers, Pointer, Session};
use mlua::prelude::*;

pub struct Driver<P: Painter> {
    session: Session,
    painter: P,
    background: Option<Rgb>,
    /// Whether the next paint must be a FULL one.
    ///
    /// Set at construction and after a resize, because in both cases the surface
    /// holds nothing a delta could patch. Tracking it here rather than asking the
    /// caller to remember means a shell cannot forget it and get a window that
    /// paints only the parts that happened to change first.
    needs_full: bool,
}

impl<P: Painter> Driver<P> {
    pub fn new(session: Session, painter: P, background: Option<Rgb>) -> Self {
        Driver {
            session,
            painter,
            background,
            needs_full: true,
        }
    }

    pub fn painter_mut(&mut self) -> &mut P {
        &mut self.painter
    }

    pub fn session(&self) -> &Session {
        &self.session
    }

    /// The surface can no longer be patched — repaint everything next frame.
    pub fn invalidate(&mut self) {
        self.needs_full = true;
    }

    /// Advance and paint one frame. Returns whether anything was drawn.
    ///
    /// `false` means the frame was IDLE, not that it failed — nothing changed, so
    /// nothing was painted. A shell can use that to skip a present and let the
    /// machine idle, which is the entire point of the delta carrying an empty
    /// change set.
    pub fn frame(&mut self, dt: f32) -> LuaResult<bool> {
        self.session.step(dt)?;

        let full = std::mem::replace(&mut self.needs_full, false);
        let delta = self.session.delta(full)?;

        // AN IDLE FRAME IS STILL A FRAME THAT STEPPED. The clock moved and the
        // router settled above; only the PAINT is skipped. Returning early before
        // the step would freeze animation the moment a screen went quiet.
        if !full && delta.changed.is_empty() && delta.removed.is_empty() {
            return Ok(false);
        }

        self.painter.paint_delta(&delta, self.background);
        Ok(true)
    }

    pub fn pointer(&self, kind: Pointer, x: f32, y: f32) -> LuaResult<()> {
        self.session.pointer(kind, x, y)
    }

    pub fn wheel(&self, x: f32, y: f32, delta: f32) -> LuaResult<()> {
        self.session.wheel(x, y, delta)
    }

    /// Feed a key. Returns whether the guest consumed it.
    ///
    /// ACT ON THE ANSWER before running a shell accelerator, or typing into a
    /// focused field triggers the shell's own shortcuts.
    pub fn key(&self, key: &str, modifiers: Modifiers) -> LuaResult<bool> {
        self.session.key(key, modifiers)
    }
}
