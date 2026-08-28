//! What a display must be able to do, and nothing about how.
//!
//! DELIBERATELY NOT COUPLED TO `aether_raster`. The display list has now survived
//! four rasterisers without the framework changing a line, and that property is
//! worth preserving one level up too: a snapshot painter writing a PNG, a GPU
//! painter owning a swapchain, and a test painter recording calls are all the
//! same shape, and none of them should require the others to be compiled.
//!
//! It is also what lets this crate be finished before the surface question is.
//! Whether the desktop shell ends up on a plain `wgpu` swapchain or on
//! DirectComposition for per-pixel window transparency changes how a painter is
//! CONSTRUCTED and nothing about this trait.

use crate::frame::{Delta, Frame, Gradient, Node, Rect, Rgb};

/// A display that paints frames.
///
/// Implementors get `paint_frame` for free and should override `paint_delta` only
/// when they can genuinely repaint a region — a retained display can, an
/// immediate-mode one over a rotating swapchain cannot, because "the surface still
/// holds the previous frame" is false there and the dirty rect has nothing to
/// repair.
pub trait Painter {
    /// Begin a frame, clearing to the given background.
    fn begin(&mut self, width: f32, height: f32, background: Option<Rgb>);

    fn fill_rounded_rect(&mut self, rect: Rect, radius: f32, colour: Rgb, alpha: f32);

    fn stroke_rounded_rect(
        &mut self,
        rect: Rect,
        radius: f32,
        thickness: f32,
        colour: Rgb,
        alpha: f32,
    );

    /// Draw text. `align_x`/`align_y` are already resolved against Roblox's own
    /// defaults by the time they arrive — a painter that re-decides alignment is
    /// the bug this signature exists to prevent.
    fn draw_text(&mut self, node: &Node);

    /// Fill with a gradient.
    ///
    /// The default FALLS BACK TO THE FLAT FILL rather than drawing nothing: a
    /// backend that cannot ramp should render the node's own colour, which is
    /// what it looked like before gradients existed. Drawing nothing would make
    /// a gradient node disappear, which is worse than an unramped one and much
    /// harder to spot.
    fn fill_gradient(&mut self, rect: Rect, radius: f32, gradient: &Gradient, fallback: Option<Rgb>, alpha: f32) {
        let _ = gradient;
        if let Some(colour) = fallback {
            self.fill_rounded_rect(rect, radius, colour, alpha);
        }
    }

    fn clip_push(&mut self, rect: Rect);
    fn clip_pop(&mut self);

    /// Present. Returns whether the surface accepted it.
    fn end(&mut self) -> bool;

    /// Paint a whole frame in paint order.
    ///
    /// The traversal lives here rather than in each painter because it encodes
    /// the ORDER things happen in — clip, fill, gradient, stroke, text — and three
    /// painters independently discovering that order is three chances to get it
    /// wrong in a way that only shows up on one backend.
    fn paint_frame(&mut self, frame: &Frame, background: Option<Rgb>) -> bool {
        self.begin(frame.width, frame.height, background);
        for node in &frame.nodes {
            paint_node(self, node);
        }
        self.end()
    }

    /// Paint only what changed. The default repaints everything, which is always
    /// correct and never wrong — just wasteful. Override it when the surface can
    /// actually hold a previous frame.
    fn paint_delta(&mut self, delta: &Delta, background: Option<Rgb>) -> bool {
        self.paint_frame(&delta.frame, background)
    }
}

fn paint_node<P: Painter + ?Sized>(painter: &mut P, node: &Node) {
    let clipped = node.clip.is_some();
    if let Some(clip) = node.clip {
        painter.clip_push(clip);
    }

    // A NODE WITH NO FILL IS NOT A BLACK NODE. Live.luau emits nil when nothing
    // set a colour, and the engine draws nothing for it; inventing a default here
    // would paint rectangles Roblox leaves empty.
    //
    // A GRADIENT REPLACES THE FLAT FILL, and is checked first for that reason. It
    // can also be an ALPHA ramp over the node's own colour with no colour ramp of
    // its own, which is why the fill travels with it rather than being skipped.
    if node.alpha > 0.0 {
        match &node.gradient {
            Some(gradient) => {
                painter.fill_gradient(node.rect, node.radius, gradient, node.fill, node.alpha)
            }
            None => {
                if let Some(fill) = node.fill {
                    painter.fill_rounded_rect(node.rect, node.radius, fill, node.alpha);
                }
            }
        }
    }

    if let Some(stroke) = &node.stroke {
        if let Some(colour) = stroke.colour {
            painter.stroke_rounded_rect(
                node.rect,
                node.radius,
                stroke.thickness,
                colour,
                stroke.alpha,
            );
        }
    }

    if node.text.is_some() {
        painter.draw_text(node);
    }

    if clipped {
        painter.clip_pop();
    }
}
