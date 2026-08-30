//! A [`Painter`] over `aether_raster`.
//!
//! FEATURE-GATED, so the trait stays free of it. `painter.rs` deliberately knows
//! no backend — a snapshot painter writing a PNG, a GPU painter owning a
//! swapchain and a test painter recording calls are the same shape, and none
//! should force the others to compile. This module is the first real
//! implementation, not the only allowed one.
//!
//! It paints to a CPU surface. That is the half of the problem that does NOT
//! depend on the unresolved surface question: no window, no wgpu, no
//! DirectComposition, and therefore nothing here changes whichever way that goes.
//! A windowed painter reuses the same node traversal from `painter.rs` and swaps
//! only how the canvas is obtained and presented.

use crate::frame::{Align, Delta, Gradient, Node, Rect, Rgb};
use crate::painter::Painter;
use aether_raster::{Backend, Canvas, Font};

pub struct RasterPainter {
    canvas: Canvas,
    /// The face used for every run. One font for now, deliberately: the display
    /// list carries no font name yet, so pretending to select one would be a
    /// second place for text to diverge between hosts.
    font: Option<Font>,
}

impl RasterPainter {
    pub fn new(width: u32, height: u32, backend: Backend) -> Option<Self> {
        Some(RasterPainter {
            canvas: Canvas::new(width, height, backend)?,
            font: None,
        })
    }

    /// Use this font for text.
    ///
    /// TEXT ALSO NEEDS THE RIGHT BACKEND. tiny-skia is a shape backend with no
    /// text at all, so a run on one is dropped however good the font is; pair a
    /// font with [`Backend::VelloCpu`].
    ///
    /// Without a font, text nodes are SKIPPED rather than drawn in a substitute face — a missing glyph run is visible in a snapshot,
    /// whereas a silently substituted font looks like a rendering bug in Aether.
    pub fn with_font(mut self, font: Font) -> Self {
        self.font = Some(font);
        self
    }

    pub fn canvas_mut(&mut self) -> &mut Canvas {
        &mut self.canvas
    }

    pub fn write_png(&mut self, path: &str) -> Result<(), u32> {
        self.canvas.write_png(path)
    }
}

/// The alpha ramp sampled at a colour stop's position, so the two ramps of one
/// gradient combine instead of one overwriting the other. Linear between the
/// bracketing stops, which is what both Roblox and the ABI do.
fn alpha_at(stops: &[crate::frame::AlphaStop], at: f32) -> Option<f32> {
    if stops.is_empty() {
        return None;
    }
    let first = stops.first()?;
    if at <= first.at {
        return Some(first.alpha);
    }
    let last = stops.last()?;
    if at >= last.at {
        return Some(last.alpha);
    }
    for pair in stops.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        if at >= a.at && at <= b.at {
            let span = b.at - a.at;
            if span <= 0.0 {
                return Some(b.alpha);
            }
            let t = (at - a.at) / span;
            return Some(a.alpha + (b.alpha - a.alpha) * t);
        }
    }
    Some(last.alpha)
}

fn rgba(c: Rgb, alpha: f32) -> (u8, u8, u8, u8) {
    (c.0, c.1, c.2, (alpha.clamp(0.0, 1.0) * 255.0).round() as u8)
}

impl Painter for RasterPainter {
    fn begin(&mut self, _width: f32, _height: f32, background: Option<Rgb>) {
        // `None` MEANS TRANSPARENT, not black.
        //
        // It read as "no colour given, use a default" and cleared to opaque
        // black, which on a layered window is a black rectangle rather than a
        // shaped widget — the alpha channel said 255 everywhere and the rounded
        // corners the tree drew had nothing to cut out of.
        //
        // The distinction is the whole reason the parameter is an Option: a
        // surface either HAS a background or is composited from what was painted
        // on it, and those are different frames, not a colour and its default.
        match background {
            Some(bg) => self.canvas.begin(bg.0, bg.1, bg.2),
            None => self.canvas.begin_alpha(0, 0, 0, 0),
        }
    }

    fn fill_rounded_rect(&mut self, rect: Rect, radius: f32, colour: Rgb, alpha: f32) {
        self.canvas
            .fill_rect(rect.x, rect.y, rect.w, rect.h, radius, rgba(colour, alpha));
    }

    fn stroke_rounded_rect(
        &mut self,
        rect: Rect,
        radius: f32,
        thickness: f32,
        colour: Rgb,
        alpha: f32,
    ) {
        self.canvas.stroke_rect(
            rect.x,
            rect.y,
            rect.w,
            rect.h,
            radius,
            thickness,
            rgba(colour, alpha),
        );
    }

    fn draw_text(&mut self, node: &Node) {
        let (Some(font), Some(text)) = (self.font, node.text.as_deref()) else {
            return;
        };
        if text.is_empty() {
            return;
        }

        let colour = node.text_colour.unwrap_or(Rgb(255, 255, 255));
        let size = node.text_size;

        // ALIGNMENT IS APPLIED HERE AND NOWHERE ELSE. The display list carries
        // the resolved alignment — including Roblox's centre default for an unset
        // one — so this positions the run and never re-decides what it should be.
        let width = font.width(size, text).unwrap_or(0.0);
        let x = match node.text_align_x.unwrap_or(Align::Center) {
            Align::Start => node.rect.x,
            Align::Center => node.rect.x + (node.rect.w - width) / 2.0,
            Align::End => node.rect.x + node.rect.w - width,
        };

        // `fill_text` takes the TOP-LEFT and converts to a baseline itself. An
        // earlier draft here added `font.ascent(size)` on top of that, which the
        // ABI's own comment warns against by name — every run landed about a line
        // too low. The rule lives in one place; this supplies a box, not a
        // baseline.
        let y = match node.text_align_y.unwrap_or(Align::Center) {
            Align::Start => node.rect.y,
            Align::Center => node.rect.y + (node.rect.h - size) / 2.0,
            Align::End => node.rect.y + node.rect.h - size,
        };

        self.canvas
            .fill_text(font, size, x, y, rgba(colour, 1.0), text);
    }

    /// Both ramps, resolved into the flat `(at, r, g, b, a)` stops the ABI reads.
    ///
    /// AN ALPHA-ONLY GRADIENT IS STILL A GRADIENT. It carries no colour to
    /// interpolate — the thing varying is the node's OWN fill at changing alpha —
    /// and treating that as "no gradient" is what once left a window body reading
    /// flat. So the colour comes from the ramp when there is one and from the
    /// node's fill when there is not.
    fn fill_gradient(
        &mut self,
        rect: Rect,
        radius: f32,
        gradient: &Gradient,
        fallback: Option<Rgb>,
        alpha: f32,
    ) {
        let base = fallback.unwrap_or(Rgb(255, 255, 255));

        let stops: Vec<[f32; 5]> = if !gradient.stops.is_empty() {
            gradient
                .stops
                .iter()
                .map(|s| {
                    let a = alpha_at(&gradient.alpha_stops, s.at).unwrap_or(1.0) * alpha;
                    [s.at, s.colour.0 as f32, s.colour.1 as f32, s.colour.2 as f32, a * 255.0]
                })
                .collect()
        } else {
            gradient
                .alpha_stops
                .iter()
                .map(|s| {
                    [s.at, base.0 as f32, base.1 as f32, base.2 as f32, s.alpha * alpha * 255.0]
                })
                .collect()
        };

        if stops.is_empty() {
            if let Some(colour) = fallback {
                self.fill_rounded_rect(rect, radius, colour, alpha);
            }
            return;
        }

        self.canvas.fill_gradient(
            rect.x,
            rect.y,
            rect.w,
            rect.h,
            radius,
            gradient.rotation,
            &stops,
        );
    }

    fn clip_push(&mut self, rect: Rect) {
        self.canvas.clip_push(
            rect.x as i32,
            rect.y as i32,
            rect.w as i32,
            rect.h as i32,
        );
    }

    fn clip_pop(&mut self) {
        self.canvas.clip_pop();
    }

    /// Repaint ONLY the rectangle that changed.
    ///
    /// The default throws the delta away and repaints the surface, which is
    /// always correct and, on a desktop-sized overlay, wildly wasteful: a frame
    /// where one window moved cost the same as one where the whole screen did —
    /// 30ms to touch 3.7M pixels for a surface that was 3.2% painted.
    ///
    /// Three pieces already existed and none of them were connected. `Live.Frame`
    /// computes the dirty rectangle, `begin_rect` clips the frame to it and
    /// leaves the rest of the surface holding last frame's pixels, and `bgra()`
    /// swizzles only the damaged rows. This is the line that joins them.
    ///
    /// EVERY NODE IS STILL WALKED, deliberately. Filtering the display list to
    /// nodes that intersect the damage would be a second, weaker implementation
    /// of the clip the rasteriser already applies — and it is not where the time
    /// went: walking 3 windows' worth of nodes was 1.6ms against 30ms of
    /// rasterising. The cost is per-PIXEL, so clipping pixels is the fix.
    fn paint_delta(&mut self, delta: &Delta, background: Option<Rgb>) -> bool {
        let Some(dirty) = delta.dirty else {
            // No dirty rectangle means the frame did not say what moved — a full
            // repaint is the only answer that is certainly right.
            return self.paint_frame(&delta.frame, background);
        };

        // A rectangle covering the whole surface is a full repaint written
        // expensively; skip the clip machinery and take the simple path.
        if dirty.x <= 0.0
            && dirty.y <= 0.0
            && dirty.w >= delta.frame.width
            && dirty.h >= delta.frame.height
        {
            return self.paint_frame(&delta.frame, background);
        }

        // OUTWARD TO WHOLE PIXELS. A rectangle rounded inward leaves a
        // half-covered pixel of the previous frame at every edge, which reads as
        // a faint outline trailing whatever moved.
        let (x, y) = (dirty.x.floor() as i32, dirty.y.floor() as i32);
        let w = (dirty.x + dirty.w).ceil() as i32 - x;
        let h = (dirty.y + dirty.h).ceil() as i32 - y;

        let clear = match background {
            Some(bg) => (bg.0, bg.1, bg.2, 255),
            None => (0, 0, 0, 0),
        };
        self.canvas.begin_rect(clear, x, y, w, h);

        for node in &delta.frame.nodes {
            crate::painter::paint_node(self, node);
        }
        self.end()
    }

    fn end(&mut self) -> bool {
        // A CPU surface holds its pixels; presenting is the caller's business
        // (write a PNG, blit to a DC). Nothing to do, and nothing to pretend.
        true
    }
}
