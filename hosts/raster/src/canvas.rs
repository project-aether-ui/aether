//! A safe Rust surface over the C ABI.
//!
//! WHY THIS IS A WRAPPER AND NOT A REWRITE. The rasteriser's public interface is
//! a C ABI because its first consumer reached it through `zune.ffi`. That
//! consumer is gone and every consumer now is Rust, so the natural move looks
//! like promoting the internals to a safe API and demoting the C functions to
//! wrappers.
//!
//! It is not the move, yet. Those functions carry the poison hooks the gates fire
//! through (`ar_poison`, `scripts/poison_matrix.luau`), the damage-rect
//! bookkeeping and the vello/tiny-skia backend switch. Re-homing all of that to
//! get a nicer signature would mean rewriting the one path that is currently
//! proven, in the same change that adds the first Rust caller — and if the result
//! misbehaved there would be two suspects instead of one.
//!
//! So this owns the pointer and calls the same entry points everyone else does.
//! ONE implementation, no second path to drift, and the unsafe is confined to
//! this file where each block is one deref of a pointer we allocated ourselves
//! and never hand out.

use crate::{Surface, ar_begin, ar_clip_pop, ar_clip_push, ar_fill_gradient, ar_fill_rect,
            ar_bgra, ar_fill_text, ar_font_load, ar_png, ar_stroke_rect,
            ar_surface_new_backend, ar_surface_free, ar_text_ascent, ar_text_width};

/// Which rasteriser paints.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Backend {
    #[default]
    TinySkia,
    VelloCpu,
}

impl Backend {
    fn code(self) -> u32 {
        match self {
            Backend::TinySkia => 0,
            Backend::VelloCpu => 1,
        }
    }
}

/// A font, by the id the store handed back.
///
/// NOT A ZERO DEFAULT. `ar_font_load` returns 0 for a font it could not read, and
/// the metrics calls answer a NEGATIVE width for an unknown id — which the ABI's
/// own comment warns must not be treated as zero, because a zero width collapses
/// the element rather than merely mismeasuring it. Wrapping the id in a type that
/// can only be built from a successful load keeps that mistake unavailable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Font(u32);

impl Font {
    /// Load a font file. `index` selects a face within a collection.
    pub fn load(path: &str, index: u32) -> Option<Font> {
        let id = ar_font_load(path.as_ptr(), path.len() as u32, index);
        (id != 0).then_some(Font(id))
    }

    /// Width of one run, in pixels. `None` when the font is unknown.
    pub fn width(self, size: f32, text: &str) -> Option<f32> {
        let w = ar_text_width(self.0, size, text.as_ptr(), text.len() as u32);
        (w >= 0.0).then_some(w)
    }

    /// Distance from the top of the line box to the baseline.
    pub fn ascent(self, size: f32) -> f32 {
        ar_text_ascent(self.0, size)
    }
}

/// An owned drawing surface.
pub struct Canvas {
    ptr: *mut Surface,
    width: u32,
    height: u32,
}

impl Canvas {
    pub fn new(width: u32, height: u32, backend: Backend) -> Option<Canvas> {
        let ptr = ar_surface_new_backend(width, height, backend.code());
        (!ptr.is_null()).then_some(Canvas { ptr, width, height })
    }

    pub fn width(&self) -> u32 {
        self.width
    }

    pub fn height(&self) -> u32 {
        self.height
    }

    /// Start a frame, clearing to a background colour.
    pub fn begin(&mut self, r: u8, g: u8, b: u8) {
        ar_begin(self.ptr, r, g, b);
    }

    pub fn fill_rect(&mut self, x: f32, y: f32, w: f32, h: f32, radius: f32, rgba: (u8, u8, u8, u8)) {
        ar_fill_rect(self.ptr, x, y, w, h, radius, rgba.0, rgba.1, rgba.2, rgba.3);
    }

    pub fn stroke_rect(
        &mut self,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        radius: f32,
        thickness: f32,
        rgba: (u8, u8, u8, u8),
    ) {
        ar_stroke_rect(self.ptr, x, y, w, h, radius, thickness, rgba.0, rgba.1, rgba.2, rgba.3);
    }

    /// Fill with a gradient. Each stop is `(at, r, g, b, a)`, flattened, which is
    /// the layout the ABI reads five floats at a time.
    pub fn fill_gradient(
        &mut self,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        radius: f32,
        rotation: f32,
        stops: &[[f32; 5]],
    ) {
        if stops.is_empty() {
            return;
        }
        let flat: Vec<f32> = stops.iter().flatten().copied().collect();
        ar_fill_gradient(self.ptr, x, y, w, h, radius, rotation, flat.as_ptr(), stops.len() as u32);
    }

    /// Draw a run. `x`/`y` are the TOP-LEFT of the text box, matching every other
    /// coordinate in this ABI and in `Live.Frame`.
    ///
    /// DO NOT ADD AN ASCENT. The baseline conversion happens inside, precisely so
    /// no caller has to query one separately — which is how two hosts drift into
    /// disagreeing vertically. A caller that adds it anyway pushes every run down
    /// by roughly a line.
    ///
    /// Returns false when nothing was drawn. The most likely reason is the
    /// BACKEND: tiny-skia is a shape backend and has no text at all, so a run on
    /// one is silently dropped. Use [`Backend::VelloCpu`] for anything with text.
    pub fn fill_text(&mut self, font: Font, size: f32, x: f32, y: f32, rgba: (u8, u8, u8, u8), text: &str) -> bool {
        ar_fill_text(
            self.ptr,
            font.0,
            size,
            x,
            y,
            rgba.0,
            rgba.1,
            rgba.2,
            rgba.3,
            text.as_ptr(),
            text.len() as u32,
        ) != 0
    }

    pub fn clip_push(&mut self, x: i32, y: i32, w: i32, h: i32) {
        ar_clip_push(self.ptr, x, y, w, h);
    }

    pub fn clip_pop(&mut self) {
        ar_clip_pop(self.ptr);
    }

    /// The finished frame as BGRA, ready for a Windows DIB.
    ///
    /// THE WHOLE BUFFER IS ALWAYS VALID, even though only the damaged rows are
    /// re-swizzled per frame: the rows outside the damage rect still hold the
    /// bytes from the frame that last painted them. So a caller blits the entire
    /// slice and is correct; it does not have to track damage to stay right, only
    /// to go faster.
    ///
    /// Borrows `&mut self` because it rasterises on demand — a vello frame that
    /// was recorded but never read has produced no pixels yet.
    pub fn bgra(&mut self) -> Option<&[u8]> {
        let ptr = ar_bgra(self.ptr);
        if ptr.is_null() {
            return None;
        }
        let len = self.width as usize * self.height as usize * 4;
        // SAFETY: `ar_bgra` returns the surface's own scratch buffer, sized
        // width*height*4 and valid until the next call on this surface. `&mut
        // self` is what makes "until the next call" enforceable.
        Some(unsafe { std::slice::from_raw_parts(ptr, len) })
    }

    /// Write the surface out as a PNG. `Ok(())` or the ABI's status code.
    pub fn write_png(&mut self, path: &str) -> Result<(), u32> {
        match ar_png(self.ptr, path.as_ptr(), path.len() as u32) {
            0 => Ok(()),
            code => Err(code),
        }
    }
}

impl Drop for Canvas {
    fn drop(&mut self) {
        ar_surface_free(self.ptr);
    }
}

// SAFETY: a Canvas owns its Surface exclusively — the pointer is allocated in
// `new`, never copied out, and freed in `drop`. There is no interior sharing, so
// moving one between threads moves the whole thing. It is deliberately NOT `Sync`:
// every method takes `&mut self` because the underlying surface mutates, and the
// font store the text calls reach is process-global.
unsafe impl Send for Canvas {}
