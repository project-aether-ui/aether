//! Aether's rasterizer: a C ABI over tiny-skia, consumed by `zune.ffi`.
//!
//! WHY THIS EXISTS
//! The native host paints with GDI, which cannot do two things the browser host
//! does: ALPHA BLENDING and GRADIENTS. On the two real screens 49 of 85 filled
//! rects are translucent, so that is not a polish gap — it is most of the screen
//! rendered wrong, and it is what stops the native host being a product rather
//! than an instrument.
//!
//! WHY tiny-skia RATHER THAN SKIA
//! Skia's public API is C++, and `zune.ffi` speaks the C ABI, so Skia needs a
//! C++ shim and its build. tiny-skia is Skia's CPU raster pipeline ported to pure
//! Rust — no C++, no system dependencies, and it covers precisely the primitives
//! this display list uses. Measured across both real screens, that list is five
//! things: filled rects (85, of which 81 rounded and 49 translucent), rect clips
//! (233), text (96), strokes (23) and linear gradients (5).
//!
//! WHAT THIS DELIBERATELY DOES NOT DO: text. 96 of 237 nodes are text runs, and
//! glyph rasterization, hinting, shaping and fallback are where a hand-rolled
//! renderer dies. The host draws shapes here and text with the platform, which
//! keeps the hard half delegated while the easy half gets alpha and gradients.
//!
//! TWO BACKENDS BEHIND ONE ABI (ms-52 M10). `vello_cpu` joins tiny-skia, chosen
//! per surface at construction. They are kept SIDE BY SIDE rather than swapped
//! for the same reason the GDI and Rust painters are: fed byte-identical frames,
//! a disagreement between two rasterisers is a backend bug by construction, and
//! that is the only cheap way to tell one from a framework bug. `--compare`
//! already does this for GDI vs Rust; it now does it for Rust vs Rust.
//!
//! THE ABI IS DELIBERATELY FLAT. No structs cross the boundary — only integers,
//! floats and pointers to flat arrays. Struct marshalling through an FFI is where
//! a wrong offset becomes a crash rather than an error, and the native host has
//! already avoided it once on the Win32 side.

#[cfg(feature = "gpu")]
pub mod hybrid_probe;
#[cfg(feature = "gpu")]
pub mod windowed;
pub mod text;

use std::collections::HashMap;
use tiny_skia::{
    FillRule, GradientStop, LinearGradient, Mask, Paint, PathBuilder, Pixmap, Point, Rect, Stroke,
    Transform,
};
use vello_cpu::color::{AlphaColor, DynamicColor, Srgb};
use vello_cpu::kurbo::{BezPath, Point as VPoint, Rect as VRect, RoundedRect, Shape,
    Stroke as VStroke};
use vello_cpu::peniko::{ColorStop, Gradient as VGradient};
use text::FontStore;
use vello_cpu::{CompositeMode, Pixmap as VPixmap, RasterizerSettings, RenderContext, RenderMode,
    Resources};

/// The loaded fonts, shared by every surface.
///
/// Process-wide rather than per-surface on purpose: a font file is megabytes, the
/// two surfaces a comparison run creates want the same faces, and a font's
/// identity has nothing to do with which rasteriser draws it.
static FONTS: std::sync::Mutex<Option<FontStore>> = std::sync::Mutex::new(None);

fn with_fonts<R>(f: impl FnOnce(&mut FontStore) -> R) -> R {
    let mut guard = FONTS.lock().expect("font store poisoned");
    f(guard.get_or_insert_with(FontStore::default))
}

/// Load a font file. Returns an id, or 0 on failure.
///
/// Zero rather than a panic: a missing font is a deployment problem the host can
/// report and fall back from, not a reason to take the process down.
#[no_mangle]
pub extern "C" fn ar_font_load(path: *const u8, len: u32, index: u32) -> u32 {
    if path.is_null() {
        return 0;
    }
    let bytes = unsafe { std::slice::from_raw_parts(path, len as usize) };
    let path = match std::str::from_utf8(bytes) {
        Ok(p) => p,
        Err(_) => return 0,
    };
    match std::fs::read(path) {
        Ok(data) => with_fonts(|f| f.load(data, index)),
        Err(_) => 0,
    }
}

/// Width of one run, in pixels. Negative means the font id was unknown -- which
/// the caller must NOT treat as zero: a zero width collapses the element.
#[no_mangle]
pub extern "C" fn ar_text_width(font: u32, size: f32, text: *const u8, len: u32) -> f32 {
    let s = match utf8(text, len) {
        Some(s) => s,
        None => return -1.0,
    };
    with_fonts(|f| match f.layout(font, size, s) {
        Some(run) => run.width,
        None => -1.0,
    })
}

/// Line height for a size, in pixels. Negative when the font id is unknown.
///
/// Two scalar getters rather than one out-pointer: `zune.ffi` would have to
/// allocate a buffer, hand over a COPY of it, and read the copy back, and every
/// step of that is a place to be subtly wrong about which memory is which. A
/// float return has no such surface.
#[no_mangle]
pub extern "C" fn ar_text_line_height(font: u32, size: f32) -> f32 {
    with_fonts(|f| match f.layout(font, size, "") {
        Some(run) => run.line_height,
        None => -1.0,
    })
}

/// Ascent for a size, in pixels. Negative when the font id is unknown.
#[no_mangle]
pub extern "C" fn ar_text_ascent(font: u32, size: f32) -> f32 {
    with_fonts(|f| match f.layout(font, size, "") {
        Some(run) => run.ascent,
        None => -1.0,
    })
}

fn utf8<'a>(ptr: *const u8, len: u32) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    std::str::from_utf8(unsafe { std::slice::from_raw_parts(ptr, len as usize) }).ok()
}

/// Draw a run. `x`/`y` are the TOP-LEFT of the text box, matching every other
/// coordinate in this ABI and in `Live.Frame`.
///
/// The baseline conversion happens HERE rather than in the host: `glyph_run`
/// positions glyphs on the baseline, and asking each host to add an ascent it
/// would have to query separately is how the two drift apart.
#[no_mangle]
pub extern "C" fn ar_fill_text(
    ptr: *mut Surface,
    font: u32,
    size: f32,
    x: f32,
    y: f32,
    r: u8,
    g: u8,
    b: u8,
    alpha: u8,
    text: *const u8,
    len: u32,
) -> u32 {
    let s = match unsafe { ptr.as_mut() } {
        Some(s) => s,
        None => return 0,
    };
    let string = match utf8(text, len) {
        Some(s) => s,
        None => return 0,
    };
    if string.is_empty() || poisoned("blank") || poisoned("blackout") {
        return 0;
    }
    // tiny-skia has no text and never will here; it stays a SHAPE backend, and
    // the host keeps drawing its text with GDI when that backend is selected.
    if s.which != Which::VelloCpu {
        return 0;
    }
    let laid = match with_fonts(|f| {
        f.layout(font, size, string).map(|run| {
            let data = f.get(font).map(|ft| ft.data.clone());
            (run.glyphs, run.ascent, data)
        })
    }) {
        Some(v) => v,
        None => return 0,
    };
    let (glyphs, ascent, data) = laid;
    let data = match data {
        Some(d) => d,
        None => return 0,
    };
    let v = match s.vello.as_mut() {
        Some(v) => v,
        None => return 0,
    };
    // The run is laid out from ZERO; the node's left edge is added here. Dropping
    // it drew every label in the screen's top-left corner on top of each other.
    let baseline = y + ascent;
    let count = glyphs.len() as u32;
    v.ctx.set_paint(AlphaColor::<Srgb>::from_rgba8(r, g, b, alpha));
    v.ctx
        .glyph_run(&mut v.resources, &data)
        .font_size(size)
        .hint(true)
        // THE GLYPH ATLAS, and vello marks it "highly experimental and not
        // recommended for external use". Enabled anyway, on evidence rather than
        // hope: text is the largest single item in the frame -- 82 runs at 23.5 us
        // -- and caching rasterised glyphs takes it to 15.7 us, 1.93 ms to 1.29 ms.
        //
        // The risk is bounded by gates that already exist and would catch a wrong
        // picture: the glyph-ink and centring checks in `--raster --check` compare
        // painted pixels against the frame, and the poison matrix proves those
        // checks can still fail. If a vello release breaks this, they go red.
        //
        // Turn it off here if that happens; nothing else depends on it.
        .atlas_cache(true)
        .fill_glyphs(glyphs.into_iter().map(|p| vello_cpu::Glyph {
            id: p.id,
            x: x + p.x,
            y: baseline + p.y,
        }));
    count
}


// ---------------------------------------------------------------------------
// Poison: deliberate sabotage, for proving the gates can fail (ms-52 M15.1b).
//
// A gate whose assertions are all NEGATIVE -- "the pixel is not the node's
// colour, not the background" -- is satisfied by a backend that draws NOTHING.
// That is not hypothetical: the vello_cpu port rendered black over the whole
// screen and `--raster --check` reported 100% pixel parity and OK.
//
// It was fixed by adding a positive assertion, but only because the bug happened
// to be hit. These entry points let a harness ASK each gate to prove it can
// still fail, instead of trusting that it can.
//
// Every poison replays a defect that really occurred in this milestone.
// ---------------------------------------------------------------------------

#[cfg(feature = "poison")]
static POISON: std::sync::Mutex<Option<String>> = std::sync::Mutex::new(None);

#[cfg(feature = "poison")]
fn poisoned(name: &str) -> bool {
    match POISON.lock() {
        Ok(g) => g.as_deref() == Some(name),
        Err(_) => false,
    }
}

/// Not compiled unless the feature is on, so the check costs nothing -- and more
/// importantly cannot be reached -- in a normal build.
#[cfg(not(feature = "poison"))]
#[inline(always)]
fn poisoned(_name: &str) -> bool {
    false
}

/// Arm a poison by name, or disarm with an empty string. Returns 1 when the
/// library was built with the feature, 0 otherwise -- which is how the harness
/// tells "the gate did not notice" from "the sabotage never happened".
#[cfg(feature = "poison")]
#[no_mangle]
pub extern "C" fn ar_poison(name: *const u8, len: u32) -> u32 {
    let value = match utf8(name, len) {
        Some(s) if !s.is_empty() => Some(s.to_string()),
        _ => None,
    };
    if let Ok(mut g) = POISON.lock() {
        *g = value;
    }
    1
}

/// Which rasteriser a surface uses. Selected per surface at construction so both
/// can exist in one process and paint the same frame.
#[derive(Clone, Copy, PartialEq)]
pub enum Which {
    TinySkia,
    VelloCpu,
}

/// The vello side of a surface.
///
/// vello RECORDS a scene and rasterises it once, unlike tiny-skia which draws
/// immediately. So the draw calls accumulate here and `render` happens lazily at
/// the first read of the pixels -- which is why `rendered` exists rather than the
/// backend simply painting as it goes.
struct VelloState {
    ctx: RenderContext,
    pixmap: VPixmap,
    resources: Resources,
    rendered: bool,
    /// How many clip paths are currently pushed, so they can be unwound before
    /// rendering. An unbalanced clip stack is a panic in vello rather than a
    /// wrong picture.
    depth: usize,
}

pub struct Surface {
    which: Which,
    vello: Option<VelloState>,
    width: u32,
    height: u32,
    pixmap: Pixmap,
    /// Clip rectangles, innermost last. Masks are CACHED by rectangle: a screen
    /// applies 233 clips but only a handful of distinct ones, and building a
    /// full-size mask per node would cost more than the drawing.
    clips: Vec<(i32, i32, i32, i32)>,
    masks: HashMap<(i32, i32, i32, i32), Mask>,
    /// The DAMAGE rect for this frame: nothing outside it is repainted, and the
    /// surface keeps last frame's pixels there. `None` means the whole surface.
    damage: Option<(i32, i32, i32, i32)>,
    /// BGRA scratch for the blit. Windows DIBs are BGRA; tiny-skia is RGBA. Kept
    /// here so the caller gets a stable pointer and we do not allocate per frame.
    bgra: Vec<u8>,
}

fn rounded_path(x: f32, y: f32, w: f32, h: f32, r: f32) -> Option<tiny_skia::Path> {
    if w <= 0.0 || h <= 0.0 {
        return None;
    }
    let r = r.min(w / 2.0).min(h / 2.0).max(0.0);
    let mut pb = PathBuilder::new();
    if r <= 0.0 {
        pb.push_rect(Rect::from_xywh(x, y, w, h)?);
    } else {
        // A circular corner as two cubics is within a pixel of a true arc at UI
        // radii, and avoids pulling in an arc builder.
        let k = r * 0.5522847;
        pb.move_to(x + r, y);
        pb.line_to(x + w - r, y);
        pb.cubic_to(x + w - r + k, y, x + w, y + r - k, x + w, y + r);
        pb.line_to(x + w, y + h - r);
        pb.cubic_to(x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h);
        pb.line_to(x + r, y + h);
        pb.cubic_to(x + r - k, y + h, x, y + h - r + k, x, y + h - r);
        pb.line_to(x, y + r);
        pb.cubic_to(x, y + r - k, x + r - k, y, x + r, y);
        pb.close();
    }
    pb.finish()
}

impl Surface {
    /// Ensure the innermost clip's mask EXISTS, without handing out a borrow.
    ///
    /// This used to return `Option<&Mask>`, and every caller then had to write
    /// `.cloned()` to satisfy the borrow checker — because a `&Mask` borrowed
    /// from `self` cannot be held across `self.pixmap.fill_path(&mut self…)`.
    ///
    /// THAT CLONE WAS COPYING A FULL-SURFACE MASK PER DRAW CALL. At 1280x720
    /// that is 900 KB memcpy'd for every filled rect, stroke and gradient — ~60 MB
    /// per frame across shop's 67 shape nodes, to apply a clip that was already
    /// cached. It was most of the 9.8 ms this backend spent painting, and it read
    /// as "CPU rasterization is just expensive" rather than as a defect.
    ///
    /// Returning nothing lets the caller take the two borrows SEPARATELY —
    /// `self.masks` immutably and `self.pixmap` mutably — which Rust permits for
    /// disjoint fields and which needs no copy at all.
    /// Does the innermost clip actually CUT this shape?
    ///
    /// A clip that fully contains the shape's bounding box changes no pixel, but
    /// passing the mask anyway forces tiny-skia down its masked blend path for
    /// every span. Most nodes sit well inside their clip — a row inside a
    /// scrolling list is only clipped for the few frames it straddles the edge —
    /// so this elides the mask for the common case and keeps it for the case that
    /// needs it.
    ///
    /// Conservative on purpose: it returns true whenever the containment is not
    /// certain, so an error here costs speed and never correctness.
    fn clip_cuts(&self, x: f32, y: f32, w: f32, h: f32, pad: f32) -> bool {
        match self.clips.last() {
            None => false,
            Some(&(cx, cy, cw, ch)) => {
                !(x - pad >= cx as f32
                    && y - pad >= cy as f32
                    && x + w + pad <= (cx + cw) as f32
                    && y + h + pad <= (cy + ch) as f32)
            }
        }
    }

    /// The rounded-rect path vello draws. kurbo builds it exactly rather than
    /// with the four-cubic approximation the tiny-skia path uses, so a corner may
    /// differ by a fraction of a pixel between backends -- which is expected, and
    /// is why the cross-backend comparison allows a tolerance rather than
    /// demanding equality.
    fn vello_path(x: f32, y: f32, w: f32, h: f32, r: f32) -> Option<BezPath> {
        if w <= 0.0 || h <= 0.0 {
            return None;
        }
        let (x0, y0) = (x as f64, y as f64);
        let (x1, y1) = ((x + w) as f64, (y + h) as f64);
        let r = (r.min(w / 2.0).min(h / 2.0).max(0.0)) as f64;
        if r <= 0.0 {
            Some(VRect::new(x0, y0, x1, y1).to_path(0.1))
        } else {
            Some(RoundedRect::new(x0, y0, x1, y1, r).to_path(0.1))
        }
    }

    fn ensure_mask(&mut self) {
        let key = match self.clips.last() {
            Some(k) => *k,
            None => return,
        };
        let (w, h) = (self.pixmap.width(), self.pixmap.height());
        self.masks.entry(key).or_insert_with(|| {
            let mut mask = Mask::new(w, h).expect("mask allocation");
            if let Some(rect) =
                Rect::from_xywh(key.0 as f32, key.1 as f32, key.2 as f32, key.3 as f32)
            {
                if let Some(path) = PathBuilder::from_rect(rect).transform(Transform::identity()) {
                    mask.fill_path(&path, FillRule::Winding, true, Transform::identity());
                }
            }
            mask
        });
    }
}

#[no_mangle]
pub extern "C" fn ar_surface_new(width: u32, height: u32) -> *mut Surface {
    ar_surface_new_backend(width, height, 0)
}

/// `backend`: 0 = tiny-skia, 1 = vello_cpu.
///
/// An unknown value falls back to tiny-skia rather than returning null: the
/// caller's alternative is no display at all, and the flag comes from a command
/// line.
#[no_mangle]
pub extern "C" fn ar_surface_new_backend(width: u32, height: u32, backend: u32) -> *mut Surface {
    // The tiny-skia pixmap is allocated either way. It is the parity instrument's
    // scratch and it costs one buffer; the alternative is an Option that every
    // read has to unwrap.
    let pixmap = match Pixmap::new(width, height) {
        Some(p) => p,
        None => return std::ptr::null_mut(),
    };
    let which = if backend == 1 { Which::VelloCpu } else { Which::TinySkia };
    // vello sizes in u16, so a window wider than 65535 is not representable. It
    // is reported as a failure rather than silently truncated.
    if which == Which::VelloCpu && (width > u16::MAX as u32 || height > u16::MAX as u32) {
        return std::ptr::null_mut();
    }
    let vello = if which == Which::VelloCpu {
        Some(VelloState {
            ctx: RenderContext::new(width as u16, height as u16),
            pixmap: VPixmap::new(width as u16, height as u16),
            resources: Resources::new(),
            rendered: false,
            depth: 0,
        })
    } else {
        None
    };
    Box::into_raw(Box::new(Surface {
        which,
        vello,
        width,
        height,
        pixmap,
        clips: Vec::new(),
        masks: HashMap::new(),
        damage: None,
        bgra: vec![0u8; (width as usize) * (height as usize) * 4],
    }))
}

/// Which backend a surface is using, so a caller can report it rather than
/// assume it -- a `--vello` flag that silently fell back to tiny-skia would make
/// every measurement below it a lie.
#[no_mangle]
pub extern "C" fn ar_backend(ptr: *const Surface) -> u32 {
    match unsafe { ptr.as_ref() } {
        Some(s) => match s.which {
            Which::TinySkia => 0,
            Which::VelloCpu => 1,
        },
        None => 0,
    }
}

#[no_mangle]
pub extern "C" fn ar_surface_free(ptr: *mut Surface) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)) };
    }
}

/// Start a frame: clear to an opaque colour and drop any clip left behind.
#[no_mangle]
pub extern "C" fn ar_begin(ptr: *mut Surface, r: u8, g: u8, b: u8) {
    let s = match unsafe { ptr.as_mut() } {
        Some(s) => s,
        None => return,
    };
    flush_pending(s);
    s.clips.clear();
    s.damage = None;
    // `blackout` is the EXACT state the vello_cpu port shipped in: nothing drawn
    // AND no background clear, so every pixel reads transparent black -- which is
    // neither the node's colour nor the background, and therefore satisfies every
    // negative assertion a gate might make. `blank` alone does not reproduce it,
    // because a cleared surface still equals the background and gets caught by a
    // different assertion.
    if poisoned("blackout") {
        return;
    }
    if s.which == Which::VelloCpu {
        vello_begin(s, r, g, b, None);
        return;
    }
    s.pixmap.fill(tiny_skia::Color::from_rgba8(r, g, b, 255));
}

/// Start a vello frame: unwind any clips left from last time, reset the recorded
/// scene, and lay down the background.
///
/// `reset` rather than a fresh context: the context owns sizeable scratch and
/// rebuilding it every frame would allocate on the frame thread.
fn vello_begin(s: &mut Surface, r: u8, g: u8, b: u8, damage: Option<(i32, i32, i32, i32)>) {
    let (w, h) = (s.width, s.height);
    let v = match s.vello.as_mut() {
        Some(v) => v,
        None => return,
    };
    while v.depth > 0 {
        v.ctx.pop_clip_path();
        v.depth -= 1;
    }
    v.ctx.reset();
    v.rendered = false;
    v.ctx.set_paint(AlphaColor::<Srgb>::from_rgba8(r, g, b, 255));
    match damage {
        Some((dx, dy, dw, dh)) => {
            // The damage rect is pushed as the base clip so nothing can paint
            // outside it, then filled -- the same two jobs the tiny-skia path
            // does with its clip stack and a Source-mode rect.
            let rect = VRect::new(dx as f64, dy as f64, (dx + dw) as f64, (dy + dh) as f64);
            v.ctx.push_clip_path(&rect.to_path(0.1));
            v.depth += 1;
            v.ctx.fill_rect(&rect);
        }
        None => {
            v.ctx.fill_rect(&VRect::new(0.0, 0.0, w as f64, h as f64));
        }
    }
}

/// Start a frame that only repaints ONE RECTANGLE.
///
/// THE POINT IS FILL RATE, which is what actually costs here. These screens
/// stack large translucent panels, so a frame blends far more pixels than it has
/// nodes — a full-window rounded rect is ~920k pixels of alpha blending on a CPU,
/// and several of them overlap. Clipping the paint to the region that actually
/// changed shrinks every one of those fills at once, which no amount of
/// per-node caching can do.
///
/// The surface KEEPS last frame's pixels outside the damage rect, so the caller
/// must present only the damaged region too — presenting the whole surface would
/// be correct but would give back the cost this saves.
#[no_mangle]
pub extern "C" fn ar_begin_rect(
    ptr: *mut Surface,
    r: u8,
    g: u8,
    b: u8,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
) {
    let s = match unsafe { ptr.as_mut() } {
        Some(s) => s,
        None => return,
    };
    flush_pending(s);
    s.clips.clear();
    let (pw, ph) = (s.pixmap.width() as i32, s.pixmap.height() as i32);
    let l = x.max(0);
    let t = y.max(0);
    let rr = (x + w).min(pw);
    let bb = (y + h).min(ph);
    if rr <= l || bb <= t {
        // Nothing to do, but the damage must still be recorded as empty so the
        // node loop skips everything rather than painting unclipped.
        s.damage = Some((l, t, 0, 0));
        s.clips.push((l, t, 0, 0));
        return;
    }
    let rect = (l, t, rr - l, bb - t);
    s.damage = Some(rect);
    if s.which == Which::VelloCpu {
        s.clips.push(rect);
        vello_begin(s, r, g, b, Some(rect));
        return;
    }
    // The damage rect is the BASE CLIP, so every nested clip intersects with it
    // and no draw can escape the region — the same mechanism the display list
    // already uses, rather than a second one to keep in sync.
    s.clips.push(rect);
    if let Some(re) = Rect::from_xywh(l as f32, t as f32, (rr - l) as f32, (bb - t) as f32) {
        let mut paint = Paint::default();
        paint.set_color_rgba8(r, g, b, 255);
        paint.anti_alias = false;
        paint.blend_mode = tiny_skia::BlendMode::Source;
        s.pixmap
            .fill_rect(re, &paint, Transform::identity(), None);
    }
}

/// The damage rect, so the caller can present exactly what was repainted.
/// Writes 4 ints and returns 1, or returns 0 when the whole surface is valid.
#[no_mangle]
pub extern "C" fn ar_damage(ptr: *const Surface, out: *mut i32) -> u32 {
    let s = match unsafe { ptr.as_ref() } {
        Some(s) => s,
        None => return 0,
    };
    match s.damage {
        None => 0,
        Some((x, y, w, h)) => {
            if out.is_null() {
                return 0;
            }
            unsafe {
                *out = x;
                *out.add(1) = y;
                *out.add(2) = w;
                *out.add(3) = h;
            }
            1
        }
    }
}

/// A filled, optionally rounded, optionally translucent rectangle.
///
/// `alpha` is 0..255 and is the thing GDI could not do at all.
#[no_mangle]
pub extern "C" fn ar_fill_rect(
    ptr: *mut Surface,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    radius: f32,
    r: u8,
    g: u8,
    b: u8,
    alpha: u8,
) {
    let s = match unsafe { ptr.as_mut() } {
        Some(s) => s,
        None => return,
    };
    // `blank` replays the vello_cpu port drawing nothing while `--raster --check`
    // scored 100% pixel parity. A gate that cannot fail here is a gate a blank
    // backend passes.
    if poisoned("blank") || poisoned("blackout") {
        return;
    }
    // `opaque` replays what GDI does -- a translucent node painted at full
    // opacity. The blend assertion exists to catch exactly this.
    let alpha = if poisoned("opaque") { 255 } else { alpha };
    if s.which == Which::VelloCpu {
        if let Some(path) = Surface::vello_path(x, y, w, h, radius) {
            if let Some(v) = s.vello.as_mut() {
                v.ctx.set_paint(AlphaColor::<Srgb>::from_rgba8(r, g, b, alpha));
                v.ctx.fill_path(&path);
            }
        }
        return;
    }

    let mut paint = Paint::default();
    paint.set_color_rgba8(r, g, b, alpha);
    paint.anti_alias = true;

    let cuts = s.clip_cuts(x, y, w, h, 0.0);
    if cuts {
        s.ensure_mask();
    }

    // A SQUARE RECT IS NOT A PATH. `fill_rect` takes tiny-skia's rectangle
    // blitter directly; routing it through `fill_path` builds a path, runs the
    // scanline rasterizer and anti-aliases four edges that are exactly on pixel
    // boundaries. Only rounded corners need the path.
    if radius <= 0.0 {
        if let Some(rect) = Rect::from_xywh(x, y, w, h) {
            let Surface { pixmap, masks, clips, .. } = s;
            let mask = if cuts { clips.last().and_then(|k| masks.get(k)) } else { None };
            pixmap.fill_rect(rect, &paint, Transform::identity(), mask);
        }
        return;
    }

    let path = match rounded_path(x, y, w, h, radius) {
        Some(p) => p,
        None => return,
    };
    let Surface { pixmap, masks, clips, .. } = s;
    let mask = if cuts { clips.last().and_then(|k| masks.get(k)) } else { None };
    pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), mask);
}

/// An outline. Drawn as a separate pass from the fill, unlike the GDI painter
/// where the pen and brush ride the same call.
#[no_mangle]
pub extern "C" fn ar_stroke_rect(
    ptr: *mut Surface,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    radius: f32,
    thickness: f32,
    r: u8,
    g: u8,
    b: u8,
    alpha: u8,
) {
    let s = match unsafe { ptr.as_mut() } {
        Some(s) => s,
        None => return,
    };
    if poisoned("blank") || poisoned("blackout") {
        return;
    }
    if s.which == Which::VelloCpu {
        if let Some(path) = Surface::vello_path(x, y, w, h, radius) {
            if let Some(v) = s.vello.as_mut() {
                v.ctx.set_paint(AlphaColor::<Srgb>::from_rgba8(r, g, b, alpha));
                v.ctx.set_stroke(VStroke::new(thickness.max(0.1) as f64));
                v.ctx.stroke_path(&path);
            }
        }
        return;
    }

    let path = match rounded_path(x, y, w, h, radius) {
        Some(p) => p,
        None => return,
    };
    let mut paint = Paint::default();
    paint.set_color_rgba8(r, g, b, alpha);
    paint.anti_alias = true;
    let mut stroke = Stroke::default();
    stroke.width = thickness.max(0.1);
    // Padded by the stroke width: an outline straddles its node's edge, so a clip
    // that merely touches the bounds still cuts the stroke.
    let cuts = s.clip_cuts(x, y, w, h, stroke.width);
    if cuts {
        s.ensure_mask();
    }
    let Surface { pixmap, masks, clips, .. } = s;
    let mask = if cuts { clips.last().and_then(|k| masks.get(k)) } else { None };
    pixmap.stroke_path(&path, &paint, &stroke, Transform::identity(), mask);
}

/// A linear gradient fill.
///
/// `stops` is a FLAT array of `[t, r, g, b, a]` per stop, t in 0..1 and channels
/// in 0..255, so nothing structured crosses the ABI. `rotation` is degrees
/// clockwise from left-to-right, matching Roblox's UIGradient and the browser
/// painter.
#[no_mangle]
pub extern "C" fn ar_fill_gradient(
    ptr: *mut Surface,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    radius: f32,
    rotation: f32,
    stops: *const f32,
    stop_count: u32,
) {
    let s = match unsafe { ptr.as_mut() } {
        Some(s) => s,
        None => return,
    };
    if stops.is_null() || stop_count == 0 || poisoned("blank") || poisoned("blackout") {
        return;
    }
    let raw = unsafe { std::slice::from_raw_parts(stops, (stop_count as usize) * 5) };
    let mut parsed: Vec<GradientStop> = Vec::with_capacity(stop_count as usize);
    for i in 0..stop_count as usize {
        let t = raw[i * 5].clamp(0.0, 1.0);
        let c = tiny_skia::Color::from_rgba8(
            raw[i * 5 + 1] as u8,
            raw[i * 5 + 2] as u8,
            raw[i * 5 + 3] as u8,
            raw[i * 5 + 4] as u8,
        );
        parsed.push(GradientStop::new(t, c));
    }
    if parsed.len() < 2 {
        // A single stop is a flat fill, and tiny-skia requires two. The colour is
        // re-read from the raw array rather than from the stop, which exposes no
        // accessor.
        let c = tiny_skia::Color::from_rgba8(raw[1] as u8, raw[2] as u8, raw[3] as u8, raw[4] as u8);
        parsed.push(GradientStop::new(1.0, c));
    }

    let rad = rotation.to_radians();
    let (cx, cy) = (x + w / 2.0, y + h / 2.0);
    let half = (rad.cos().abs() * w / 2.0) + (rad.sin().abs() * h / 2.0);
    let (sx, sy) = (cx - rad.cos() * half, cy - rad.sin() * half);
    let (ex, ey) = (cx + rad.cos() * half, cy + rad.sin() * half);

    if s.which == Which::VelloCpu {
        let stops: Vec<ColorStop> = (0..stop_count as usize)
            .map(|i| ColorStop {
                offset: raw[i * 5].clamp(0.0, 1.0),
                color: DynamicColor::from_alpha_color(AlphaColor::<Srgb>::from_rgba8(
                    raw[i * 5 + 1] as u8,
                    raw[i * 5 + 2] as u8,
                    raw[i * 5 + 3] as u8,
                    raw[i * 5 + 4] as u8,
                )),
            })
            .collect();
        // Two stops minimum, for the same reason tiny-skia needs them: a single
        // stop is a flat fill and neither renderer accepts a one-stop ramp.
        let stops = if stops.len() < 2 {
            let mut v = stops.clone();
            if let Some(first) = stops.first() {
                v.push(ColorStop { offset: 1.0, color: first.color });
            }
            v
        } else {
            stops
        };
        if stops.len() < 2 {
            return;
        }
        let grad = VGradient::new_linear(
            VPoint::new(sx as f64, sy as f64),
            VPoint::new(ex as f64, ey as f64),
        )
        .with_stops(stops.as_slice());
        if let Some(path) = Surface::vello_path(x, y, w, h, radius) {
            if let Some(v) = s.vello.as_mut() {
                v.ctx.set_paint(grad);
                v.ctx.fill_path(&path);
                // Back to a solid paint, or the next fill silently inherits the
                // gradient -- the recorded-scene equivalent of GDI's "selected
                // object survives the call" trap.
                v.ctx.set_paint(AlphaColor::<Srgb>::from_rgba8(0, 0, 0, 255));
            }
        }
        return;
    }

    let start = Point::from_xy(sx, sy);
    let end = Point::from_xy(ex, ey);

    let shader = match LinearGradient::new(
        start,
        end,
        parsed,
        tiny_skia::SpreadMode::Pad,
        Transform::identity(),
    ) {
        Some(sh) => sh,
        None => return,
    };
    let path = match rounded_path(x, y, w, h, radius) {
        Some(p) => p,
        None => return,
    };
    let mut paint = Paint::default();
    paint.shader = shader;
    paint.anti_alias = true;
    let cuts = s.clip_cuts(x, y, w, h, 0.0);
    if cuts {
        s.ensure_mask();
    }
    let Surface { pixmap, masks, clips, .. } = s;
    let mask = if cuts { clips.last().and_then(|k| masks.get(k)) } else { None };
    pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), mask);
}

/// Push a clip rectangle. Nested clips INTERSECT, which is what a display list's
/// nested `ClipsDescendants` means.
#[no_mangle]
pub extern "C" fn ar_clip_push(ptr: *mut Surface, x: i32, y: i32, w: i32, h: i32) {
    let s = match unsafe { ptr.as_mut() } {
        Some(s) => s,
        None => return,
    };
    // `noclip` replays the damage-clipping defect: skipping nodes outside the
    // rect is only sound if the ones inside it cannot paint outside, and without
    // the clip `Window` repainted the whole surface over everything skipped.
    if poisoned("noclip") {
        return;
    }
    let next = match s.clips.last() {
        Some(&(px, py, pw, ph)) => {
            let l = x.max(px);
            let t = y.max(py);
            let r = (x + w).min(px + pw);
            let b = (y + h).min(py + ph);
            (l, t, (r - l).max(0), (b - t).max(0))
        }
        None => (x, y, w.max(0), h.max(0)),
    };
    s.clips.push(next);
    if s.which == Which::VelloCpu {
        // The INTERSECTED rect, matching what the tiny-skia mask would be. vello
        // would intersect a raw rect with its parent anyway, so this only makes
        // the two backends provably identical in what they clip to.
        let rect = VRect::new(
            next.0 as f64, next.1 as f64,
            (next.0 + next.2) as f64, (next.1 + next.3) as f64);
        if let Some(v) = s.vello.as_mut() {
            v.ctx.push_clip_path(&rect.to_path(0.1));
            v.depth += 1;
        }
    }
}

#[no_mangle]
pub extern "C" fn ar_clip_pop(ptr: *mut Surface) {
    if let Some(s) = unsafe { ptr.as_mut() } {
        s.clips.pop();
        if s.which == Which::VelloCpu {
            if let Some(v) = s.vello.as_mut() {
                if v.depth > 0 {
                    v.ctx.pop_clip_path();
                    v.depth -= 1;
                }
            }
        }
    }
}

/// Rasterise a recorded-but-unrendered scene before it is thrown away.
///
/// THE PIXMAP IS THE ACCUMULATOR ACROSS FRAMES, which is what makes damaged
/// repainting possible at all: a clipped frame composites over the pixels the
/// previous frame left. vello RECORDS rather than draws, so a frame that was
/// painted but never read had produced no pixels at all -- and the next
/// `ctx.reset()` discarded it silently.
///
/// The whole previous frame then did not exist, and a damaged repaint composited
/// over a blank pixmap: `--damage-check` reported 93795 of 94245 pixels wrong,
/// all of them transparent black. The GDI painter has no equivalent failure
/// because it draws immediately, which is exactly why this needed its own gate.
fn flush_pending(s: &mut Surface) {
    if s.which == Which::VelloCpu {
        vello_render(s);
    }
}

/// Rasterise the recorded vello scene, once per frame.
///
/// vello records draw calls and rasterises on demand, so this must run before
/// any read of the pixels -- and exactly once, or a frame is rasterised twice and
/// the cost is double with no visible difference to say so.
fn vello_render(s: &mut Surface) {
    if s.which != Which::VelloCpu {
        return;
    }
    let damaged = s.damage.is_some();
    let v = match s.vello.as_mut() {
        Some(v) => v,
        None => return,
    };
    if v.rendered {
        return;
    }
    // Clips must be balanced before rendering; an outstanding one panics.
    while v.depth > 0 {
        v.ctx.pop_clip_path();
        v.depth -= 1;
    }
    v.ctx.flush();
    // COMPOSITE MODE FOLLOWS THE DAMAGE RECT, and getting this wrong erases the
    // screen. `Replace` -- the default -- CLEARS THE WHOLE PIXMAP before drawing,
    // which is right for a full frame and catastrophic for a clipped one: every
    // pixel the damage rect does not cover would go transparent, and those are
    // exactly the pixels a damaged repaint is trusting to still be there.
    //
    // `SrcOver` leaves them. Inside the rect the background fill is opaque, so it
    // overwrites regardless, and the result is identical to a full repaint --
    // which is what `--damage-check` asserts rather than assumes.
    let composite = if damaged { CompositeMode::SrcOver } else { CompositeMode::Replace };
    // OptimizeSpeed selects the u8 pipeline, which is what the crate recommends
    // for application rendering; OptimizeQuality is for snapshot tests.
    v.ctx.render_with(
        &mut v.pixmap,
        &mut v.resources,
        RasterizerSettings {
            render_mode: RenderMode::OptimizeSpeed,
            composite_mode: composite,
            ..Default::default()
        },
    );
    v.rendered = true;
}

/// The finished frame as BGRA, which is what a Windows DIB wants. Returns a
/// pointer valid until the next call.
#[no_mangle]
pub extern "C" fn ar_bgra(ptr: *mut Surface) -> *const u8 {
    let s = match unsafe { ptr.as_mut() } {
        Some(s) => s,
        None => return std::ptr::null(),
    };
    vello_render(s);
    // ONLY THE DAMAGED ROWS. The swizzle touches every byte it covers, so on a
    // 1280x720 window a full frame is ~3.7 MB of work whether or not anything
    // moved — which made it the second-largest cost once the paint was clipped.
    // The rows outside the damage rect still hold the correct bytes from the
    // frame that last painted them.
    let (row0, row1) = match s.damage {
        Some((_, y, _, h)) => (y.max(0) as usize, ((y + h) as usize).min(s.height as usize)),
        None => (0, s.height as usize),
    };
    // DESTRUCTURED so the destination and the source are disjoint borrows. The
    // previous version indexed `s.bgra[i]` and `src[i]` inside the loop because
    // it could not hold both at once, and that is what made this expensive: four
    // bounds-checked byte reads and four bounds-checked byte writes per pixel,
    // in a shape LLVM will not vectorise. Measured at 0.894 ms of an 8.4 ms
    // shop frame — 11% — against 0.082 ms for the upload it feeds.
    let Surface { which, vello, pixmap, bgra, width, .. } = s;
    // Both backends hand back premultiplied RGBA; the surface is cleared opaque
    // so alpha is 255 everywhere and no un-premultiply is needed.
    let src: &[u8] = if *which == Which::VelloCpu {
        match vello.as_ref() {
            Some(v) => v.pixmap.data_as_u8_slice(),
            None => return std::ptr::null(),
        }
    } else {
        pixmap.data()
    };
    let stride = *width as usize * 4;
    let (from, to) = (row0 * stride, row1 * stride);
    if to <= src.len() && to <= bgra.len() {
        // `chunks_exact` on both sides: the compiler knows each step has exactly
        // four bytes on each side, drops every bounds check, and vectorises the
        // shuffle. Same bytes out as the index loop, by construction.
        // `channels` replays the defect this loop is one edit away from at all
        // times: red and blue transposed. Nothing that reads `ar_pixel` can see
        // it -- every assertion in `--raster --check` was on that side of the
        // swizzle until the presented-pixel check was added -- so this proves
        // that check is the one holding the line.
        let swap = poisoned("channels");
        for (d, p) in bgra[from..to]
            .chunks_exact_mut(4)
            .zip(src[from..to].chunks_exact(4))
        {
            d[0] = if swap { p[0] } else { p[2] };
            d[1] = p[1];
            d[2] = if swap { p[2] } else { p[0] };
            d[3] = 255;
        }
    }
    s.bgra.as_ptr()
}

/// Write the finished frame to a PNG.
///
/// THE POINT IS THAT THIS PATH TOUCHES NO WINDOW. `ar_bgra` exists to feed a
/// Windows DIB and is the only reason the CPU backends ever needed a platform;
/// this is the same pixels going to a file instead, so a container with no
/// display can produce exactly what the window would have shown.
///
/// RGBA, not the BGRA scratch: `image` wants the rasteriser's own byte order, so
/// this skips the swizzle entirely rather than undoing it.
///
/// Returns 0 on success, or a non-zero code. NOT a bool: "could not open the
/// file" and "the surface was never rendered" are different failures and a caller
/// in CI needs to tell them apart from an exit code.
#[no_mangle]
pub extern "C" fn ar_png(ptr: *mut Surface, path: *const u8, len: u32) -> u32 {
    let s = match unsafe { ptr.as_mut() } {
        Some(s) => s,
        None => return 1,
    };
    let path = match utf8(path, len) {
        Some(p) if !p.is_empty() => p.to_string(),
        _ => return 2,
    };
    // vello records and rasterises on demand, so a frame that was painted but
    // never read has produced no pixels at all -- the same trap that made a
    // damaged repaint composite over a blank pixmap in M10.
    vello_render(s);
    let (w, h) = (s.width, s.height);
    let src: &[u8] = if s.which == Which::VelloCpu {
        match s.vello.as_ref() {
            Some(v) => v.pixmap.data_as_u8_slice(),
            None => return 3,
        }
    } else {
        s.pixmap.data()
    };
    let buf = match image::RgbaImage::from_raw(w, h, src.to_vec()) {
        Some(b) => b,
        None => return 4,
    };
    match buf.save(&path) {
        Ok(()) => 0,
        Err(_) => 5,
    }
}

/// Read one pixel back, as 0x00RRGGBB. The parity instrument: it lets a test
/// assert what was actually rasterised without a window or a screenshot.
#[no_mangle]
pub extern "C" fn ar_pixel(ptr: *mut Surface, x: u32, y: u32) -> u32 {
    let s = match unsafe { ptr.as_mut() } {
        Some(s) => s,
        None => return 0,
    };
    // READING A PIXEL IS READING THE FRAME, and vello has not necessarily drawn
    // it yet -- it records a scene and rasterises on demand. Without this the
    // parity instrument read an untouched pixmap and reported black for every
    // point, while the host's own check passed anyway: it asserts a blended pixel
    // matches NEITHER the node's colour nor the one beneath it, and transparent
    // black satisfies that vacuously. A backend drawing nothing scored 100%.
    vello_render(s);
    if x >= s.width || y >= s.height {
        return 0xFFFF_FFFF;
    }
    let i = ((y * s.width + x) * 4) as usize;
    let d: &[u8] = match s.which {
        Which::VelloCpu => match s.vello.as_ref() {
            Some(v) => v.pixmap.data_as_u8_slice(),
            None => return 0xFFFF_FFFF,
        },
        Which::TinySkia => s.pixmap.data(),
    };
    ((d[i] as u32) << 16) | ((d[i + 1] as u32) << 8) | (d[i + 2] as u32)
}

// ---------------------------------------------------------------------------
// The windowed GPU surface (ms-52 M13).
//
// A SEPARATE HANDLE from `Surface`, not a third `Which` variant. The two are not
// the same kind of object: a `Surface` owns pixels a caller can read back, and
// this owns a swapchain it can only PRESENT. Folding them together would put an
// `ar_bgra` on something that has no pixels to give, and every reader of that
// enum would have to know which variant answers which call.
// ---------------------------------------------------------------------------

#[cfg(feature = "gpu")]
mod gpu_abi {
    use super::*;
    use crate::windowed::Windowed;

    /// The last verification capture. A static rather than a field on `Windowed`
    /// so the frame-loop struct carries no pixel buffer at all -- the moment it
    /// does, someone will read from it in the loop and undo the reason this
    /// renderer exists.
    static VERIFY: std::sync::Mutex<Option<Vec<u32>>> = std::sync::Mutex::new(None);

    /// Why the last attach failed. Reported through a separate call rather than
    /// squeezed into the return, because the return is a pointer and every
    /// sentinel value it could carry is also a plausible address.
    static ATTACH_ERROR: std::sync::Mutex<Option<u32>> = std::sync::Mutex::new(None);
    use vello_cpu::peniko::{ColorStop, Gradient as VGradient};

    /// Attach a GPU surface to a live Win32 window. Null on failure -- no GPU, no
    /// compatible adapter, a bad handle -- and the host must fall back rather
    /// than treat it as fatal.
    /// The HWND arrives as a POINTER, not an integer.
    ///
    /// `zune.ffi` hands back window handles as opaque pointer userdata, and
    /// declaring this `i64` made the call fail with "invalid argument type (got
    /// userdata)" rather than converting. Taking `*mut c_void` and casting is
    /// exact on both 32- and 64-bit, and avoids asking the Luau side to
    /// reinterpret a handle it should only ever pass along.
    #[no_mangle]
    pub extern "C" fn ar_win_attach(
        hwnd: *mut std::ffi::c_void,
        hinstance: *mut std::ffi::c_void,
        width: u32,
        height: u32,
    ) -> *mut Windowed {
        if width == 0 || height == 0 || width > u16::MAX as u32 || height > u16::MAX as u32 {
            return std::ptr::null_mut();
        }
        match Windowed::attach_reporting(hwnd as isize, hinstance as isize, width as u16, height as u16) {
            Ok(w) => Box::into_raw(Box::new(w)),
            Err(why) => {
                *ATTACH_ERROR.lock().expect("attach error poisoned") = Some(why);
                std::ptr::null_mut()
            }
        }
    }

    /// Why the last `ar_win_attach` failed. 0 means it has not.
    #[no_mangle]
    pub extern "C" fn ar_win_attach_error() -> u32 {
        ATTACH_ERROR.lock().expect("attach error poisoned").unwrap_or(0)
    }

    /// Is this a live target? 1 if the pointer resolves, 0 if null.
    ///
    /// Exists because every other entry point here returns void, so a null
    /// pointer produced SILENCE rather than an error -- the host counted draw
    /// calls it had issued while the library ignored every one of them.
    #[no_mangle]
    pub extern "C" fn ar_win_alive(ptr: *const Windowed) -> u32 {
        u32::from(unsafe { ptr.as_ref() }.is_some())
    }

    #[no_mangle]
    pub extern "C" fn ar_win_free(ptr: *mut Windowed) {
        if !ptr.is_null() {
            unsafe { drop(Box::from_raw(ptr)) };
        }
    }

    #[no_mangle]
    pub extern "C" fn ar_win_begin(ptr: *mut Windowed, r: u8, g: u8, b: u8) {
        if let Some(w) = unsafe { ptr.as_mut() } {
            w.begin(r, g, b);
        }
    }

    #[no_mangle]
    pub extern "C" fn ar_win_fill_rect(
        ptr: *mut Windowed, x: f32, y: f32, w: f32, h: f32, radius: f32,
        r: u8, g: u8, b: u8, alpha: u8,
    ) {
        let win = match unsafe { ptr.as_mut() } { Some(v) => v, None => return };
        if let Some(path) = Windowed::path(x, y, w, h, radius) {
            win.fill(&path, r, g, b, alpha);
        }
    }

    #[no_mangle]
    pub extern "C" fn ar_win_stroke_rect(
        ptr: *mut Windowed, x: f32, y: f32, w: f32, h: f32, radius: f32, thickness: f32,
        r: u8, g: u8, b: u8, alpha: u8,
    ) {
        let win = match unsafe { ptr.as_mut() } { Some(v) => v, None => return };
        if let Some(path) = Windowed::path(x, y, w, h, radius) {
            win.stroke(&path, thickness, r, g, b, alpha);
        }
    }

    /// Same flat `[t, r, g, b, a]` stop array as `ar_fill_gradient`. Nothing
    /// structured crosses the ABI, here or anywhere else in this library.
    #[no_mangle]
    pub extern "C" fn ar_win_fill_gradient(
        ptr: *mut Windowed, x: f32, y: f32, w: f32, h: f32, radius: f32, rotation: f32,
        stops: *const f32, stop_count: u32,
    ) {
        let win = match unsafe { ptr.as_mut() } { Some(v) => v, None => return };
        if stops.is_null() || stop_count == 0 {
            return;
        }
        let raw = unsafe { std::slice::from_raw_parts(stops, (stop_count as usize) * 5) };
        let mut parsed: Vec<ColorStop> = (0..stop_count as usize)
            .map(|i| ColorStop {
                offset: raw[i * 5].clamp(0.0, 1.0),
                color: DynamicColor::from_alpha_color(AlphaColor::<Srgb>::from_rgba8(
                    raw[i * 5 + 1] as u8, raw[i * 5 + 2] as u8,
                    raw[i * 5 + 3] as u8, raw[i * 5 + 4] as u8,
                )),
            })
            .collect();
        // A single stop is a flat fill and no gradient implementation accepts a
        // one-stop ramp -- the same rule the CPU backends follow.
        if parsed.len() == 1 {
            let c = parsed[0].color;
            parsed.push(ColorStop { offset: 1.0, color: c });
        }
        if parsed.len() < 2 {
            return;
        }
        let rad = rotation.to_radians();
        let (cx, cy) = (x + w / 2.0, y + h / 2.0);
        let half = (rad.cos().abs() * w / 2.0) + (rad.sin().abs() * h / 2.0);
        let grad = VGradient::new_linear(
            vello_cpu::kurbo::Point::new((cx - rad.cos() * half) as f64, (cy - rad.sin() * half) as f64),
            vello_cpu::kurbo::Point::new((cx + rad.cos() * half) as f64, (cy + rad.sin() * half) as f64),
        )
        .with_stops(parsed.as_slice());
        if let Some(path) = Windowed::path(x, y, w, h, radius) {
            win.gradient(&path, grad);
        }
    }

    #[no_mangle]
    pub extern "C" fn ar_win_clip_push(ptr: *mut Windowed, x: i32, y: i32, w: i32, h: i32) {
        if let Some(win) = unsafe { ptr.as_mut() } {
            win.clip_push(x, y, w, h);
        }
    }

    #[no_mangle]
    pub extern "C" fn ar_win_clip_pop(ptr: *mut Windowed) {
        if let Some(win) = unsafe { ptr.as_mut() } {
            win.clip_pop();
        }
    }

    /// Draw a run. `x`/`y` are the TOP-LEFT of the text box, exactly as in
    /// `ar_fill_text`, and the baseline conversion happens here for the same
    /// reason: asking each host to add an ascent it queried separately is how the
    /// two drift apart.
    #[no_mangle]
    pub extern "C" fn ar_win_fill_text(
        ptr: *mut Windowed, font: u32, size: f32, x: f32, y: f32,
        r: u8, g: u8, b: u8, alpha: u8, text: *const u8, len: u32,
    ) -> u32 {
        let win = match unsafe { ptr.as_mut() } { Some(v) => v, None => return 0 };
        let string = match utf8(text, len) { Some(s) => s, None => return 0 };
        if string.is_empty() {
            return 0;
        }
        let laid = with_fonts(|f| {
            f.layout(font, size, string)
                .map(|run| (run.glyphs, run.ascent, f.get(font).map(|ft| ft.data.clone())))
        });
        let (glyphs, ascent, data) = match laid { Some(v) => v, None => return 0 };
        let data = match data { Some(d) => d, None => return 0 };
        let baseline = y + ascent;
        let count = glyphs.len() as u32;
        // Collected because `fill_glyphs` wants a Clone iterator and a `map` over
        // a moved Vec is not one twice over.
        let positioned: Vec<vello_cpu::Glyph> = glyphs
            .into_iter()
            .map(|p| vello_cpu::Glyph { id: p.id, x: x + p.x, y: baseline + p.y })
            .collect();
        win.glyphs(&data, size, (r, g, b, alpha), positioned.into_iter());
        count
    }

    #[no_mangle]
    pub extern "C" fn ar_win_resize(ptr: *mut Windowed, width: u32, height: u32) {
        if width > u16::MAX as u32 || height > u16::MAX as u32 {
            return;
        }
        if let Some(win) = unsafe { ptr.as_mut() } {
            win.resize(width as u16, height as u16);
        }
    }

    /// Rasterise the current scene off-screen and cache the pixels so they can be
    /// read one at a time. FOR VERIFICATION ONLY -- see `Windowed::read_back`.
    /// Returns 1 on success.
    ///
    /// Cached rather than answering per pixel, because a per-pixel readback would
    /// re-render the whole scene for every sample and a grid check takes tens of
    /// thousands of them.
    #[no_mangle]
    pub extern "C" fn ar_win_verify_capture(ptr: *mut Windowed) -> u32 {
        let win = match unsafe { ptr.as_mut() } { Some(v) => v, None => return 0 };
        match win.read_back() {
            Some(pixels) => {
                *VERIFY.lock().expect("verify buffer poisoned") = Some(pixels);
                1
            }
            None => 0,
        }
    }

    /// One pixel of the last capture, as `0x00RRGGBB`. `0xFFFFFFFF` when out of
    /// range or when nothing has been captured.
    #[no_mangle]
    pub extern "C" fn ar_win_verify_pixel(ptr: *const Windowed, x: u32, y: u32) -> u32 {
        let win = match unsafe { ptr.as_ref() } { Some(v) => v, None => return 0xFFFF_FFFF };
        if x >= win.width as u32 || y >= win.height as u32 {
            return 0xFFFF_FFFF;
        }
        let guard = VERIFY.lock().expect("verify buffer poisoned");
        match guard.as_ref() {
            Some(px) => {
                let i = (y as usize) * (win.width as usize) + x as usize;
                px.get(i).copied().unwrap_or(0xFFFF_FFFF)
            }
            None => 0xFFFF_FFFF,
        }
    }

    /// Render and present. 1 on success, 0 when the frame was dropped -- which is
    /// ordinary (occluded, resizing) and not an error.
    #[no_mangle]
    pub extern "C" fn ar_win_present(ptr: *mut Windowed) -> u32 {
        match unsafe { ptr.as_mut() } {
            Some(win) => u32::from(win.present()),
            None => 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// vello's OWN documented example, verbatim in shape, to separate "vello is
    /// misused here" from "vello does not work in this build".
    #[test]
    fn vello_doc_example_works() {
        let mut ctx = RenderContext::new(10, 5);
        let mut resources = Resources::new();
        ctx.set_paint(AlphaColor::<Srgb>::from_rgba8(255, 0, 255, 255));
        ctx.fill_rect(&VRect::new(3.0, 1.0, 7.0, 4.0));
        let mut target = VPixmap::new(10, 5);
        ctx.flush();
        ctx.render(&mut target, &mut resources);
        let d = target.data_as_u8_slice();
        let i = (2 * 10 + 4) * 4;
        assert_eq!(
            (d[i], d[i + 1], d[i + 2], d[i + 3]),
            (255, 0, 255, 255),
            "plain vello did not paint its own example"
        );
    }

    /// Does a CLIPPED, SrcOver render leave the pixels outside the clip alone?
    ///
    /// The whole damage optimisation rests on this. `--damage-check` says vello
    /// blanks everything outside the rect; this asks vello directly, with no
    /// wrapper in between, so the answer cannot be blamed on the wrapper.
    #[test]
    fn vello_srcover_preserves_outside_the_clip() {
        let mut ctx = RenderContext::new(32, 32);
        let mut resources = Resources::new();
        let mut target = VPixmap::new(32, 32);

        // Frame one: fill everything red, Replace.
        ctx.set_paint(AlphaColor::<Srgb>::from_rgba8(255, 0, 0, 255));
        ctx.fill_rect(&VRect::new(0.0, 0.0, 32.0, 32.0));
        ctx.flush();
        ctx.render_with(&mut target, &mut resources, RasterizerSettings {
            render_mode: RenderMode::OptimizeSpeed,
            composite_mode: CompositeMode::Replace,
            ..Default::default()
        });
        let d = target.data_as_u8_slice();
        let far = (28 * 32 + 28) * 4;
        assert_eq!((d[far], d[far + 1], d[far + 2]), (255, 0, 0), "setup failed");

        // Frame two: repaint only an 8x8 corner, SrcOver.
        ctx.reset();
        let clip = VRect::new(0.0, 0.0, 8.0, 8.0);
        ctx.push_clip_path(&clip.to_path(0.1));
        ctx.set_paint(AlphaColor::<Srgb>::from_rgba8(0, 0, 255, 255));
        ctx.fill_rect(&clip);
        ctx.pop_clip_path();
        ctx.flush();
        ctx.render_with(&mut target, &mut resources, RasterizerSettings {
            render_mode: RenderMode::OptimizeSpeed,
            composite_mode: CompositeMode::SrcOver,
            ..Default::default()
        });

        let d = target.data_as_u8_slice();
        let near = (4 * 32 + 4) * 4;
        assert_eq!(
            (d[near], d[near + 1], d[near + 2]),
            (0, 0, 255),
            "inside the clip should be repainted"
        );
        assert_eq!(
            (d[far], d[far + 1], d[far + 2]),
            (255, 0, 0),
            "OUTSIDE the clip should still be the previous frame"
        );
    }

    /// IS THE GPU WORTH IT WHEN THE PIXELS HAVE TO COME BACK?
    ///
    /// vello_cpu rasterises shop's frame in 1.70 ms. A headless vello_hybrid slots
    /// behind the same ABI with no architecture change, but pays a GPU→CPU
    /// readback -- 3.7 MB and a full pipeline sync per frame at 1280x720.
    ///
    /// Reported rather than asserted: this is a measurement that decides a design,
    /// not a property to hold. Run with --nocapture.
    #[cfg(feature = "gpu")]
    #[test]
    fn hybrid_headless_cost() {
        const W: u16 = 1280;
        const H: u16 = 720;
        let mut gpu = match hybrid_probe::Gpu::new(W, H) {
            Some(g) => g,
            None => {
                println!("NO GPU ADAPTER -- vello_hybrid is unavailable on this machine");
                return;
            }
        };
        let scene = hybrid_probe::shoplike_scene(W, H, 67);
        let mut out = Vec::new();

        // Warm up: the first frame compiles pipelines and allocates.
        let (r0, b0) = gpu.render_and_read(&scene, &mut out);
        println!("first frame (cold): render {r0:.3} ms, readback {b0:.3} ms");

        let n = 30;
        let (mut render, mut readback) = (0.0, 0.0);
        for _ in 0..n {
            let (r, b) = gpu.render_and_read(&scene, &mut out);
            render += r;
            readback += b;
        }
        let (render, readback) = (render / n as f64, readback / n as f64);
        println!("steady state over {n} frames, 67 rounded translucent panels, {W}x{H}:");
        println!("  submit + render   {render:.3} ms");
        println!("  readback          {readback:.3} ms");
        println!("  TOTAL             {:.3} ms", render + readback);
        // THE SAME GEOMETRY through vello_cpu, so this is one comparison rather
        // than two measurements of different things.
        let cpu = hybrid_probe::shoplike_cpu_ms(W, H, 67, 30);
        println!("  vello_cpu, IDENTICAL scene: {cpu:.3} ms");
        println!("  -> GPU raster alone is {:.1}x the CPU; with readback it is {:.2}x",
            cpu / render, cpu / (render + readback));
        assert_eq!(out.len(), usize::from(W) * usize::from(H) * 4, "readback size");
    }

    /// A real system font, so these tests exercise the same file the host will.
    fn segoe() -> Option<u32> {
        // THE SAME CANDIDATES, IN THE SAME ORDER, as RasterPainter.FONT_CANDIDATES.
        // They diverged once and it cost a diagnosis: the test loaded Segoe UI
        // while the host loads Segoe UI SYMBOL, so a symbol lookup that works in
        // the host reported .notdef here and looked like a charmap bug.
        for path in [
            "C:/Windows/Fonts/seguisym.ttf",
            "C:/Windows/Fonts/segoeui.ttf",
            "C:/Windows/Fonts/arial.ttf",
        ] {
            let bytes = path.as_bytes();
            let id = ar_font_load(bytes.as_ptr(), bytes.len() as u32, 0);
            if id != 0 {
                return Some(id);
            }
        }
        None
    }

    /// TEXT MUST MEASURE PER GLYPH, not by a uniform factor.
    ///
    /// This is the assertion that caught the bundled advance table in M7: ten
    /// narrow glyphs and ten wide ones are the SAME LENGTH, so any per-character
    /// approximation returns the same width for both and reports itself working.
    /// Real metrics cannot.
    #[test]
    fn text_measures_per_glyph() {
        let Some(font) = segoe() else {
            println!("no system font available; skipping");
            return;
        };
        let narrow = "iiiiiiiiii";
        let wide = "WWWWWWWWWW";
        let n = ar_text_width(font, 14.0, narrow.as_ptr(), narrow.len() as u32);
        let w = ar_text_width(font, 14.0, wide.as_ptr(), wide.len() as u32);
        println!("10 narrow {n:.1}px, 10 wide {w:.1}px");
        assert!(n > 0.0 && w > 0.0, "both runs must have a width");
        assert!(w > n * 2.0, "per-glyph metrics: 10 narrow {n}, 10 wide {w}");

        // And it must scale with size, or `textSize` is being ignored -- the exact
        // symptom of GDI's stock font before M7 selected one.
        let big = ar_text_width(font, 28.0, wide.as_ptr(), wide.len() as u32);
        assert!(big > w * 1.8, "width must scale with size: 14px {w}, 28px {big}");

        // An unknown font must REPORT failure, not answer zero. A zero width
        // collapses the element, which is worse than an approximate one.
        assert!(ar_text_width(9999, 14.0, wide.as_ptr(), wide.len() as u32) < 0.0,
            "an unknown font must not answer a width");
    }

    /// PAINTING AND MEASURING MUST AGREE, which is the rule M7 broke by measuring
    /// with one font and drawing with another.
    ///
    /// Asserted through the pixels rather than by comparing the measurement to
    /// itself: draw a run, then find the rightmost column carrying ink, and
    /// require it to land inside the width that was reported. A painter that
    /// ignored the metrics would overrun or fall short.
    #[test]
    fn painted_ink_fits_the_measured_width() {
        let Some(font) = segoe() else {
            println!("no system font available; skipping");
            return;
        };
        let text = "Handgloves";
        let size = 32.0_f32;
        let width = ar_text_width(font, size, text.as_ptr(), text.len() as u32);
        assert!(width > 0.0);

        let s = ar_surface_new_backend(512, 128, 1);
        ar_begin(s, 0, 0, 0);
        let drawn = ar_fill_text(s, font, size, 20.0, 20.0, 255, 255, 255, 255,
            text.as_ptr(), text.len() as u32);
        assert_eq!(drawn as usize, text.chars().count(), "one glyph per character");

        let mut rightmost = 0;
        let mut inked = 0;
        for py in 0..128u32 {
            for px in 0..512u32 {
                if ar_pixel(s, px, py) != 0 {
                    inked += 1;
                    if px > rightmost {
                        rightmost = px;
                    }
                }
            }
        }
        ar_surface_free(s);
        println!("measured {width:.1}px, ink ends at x={rightmost} (started at 20), {inked} lit pixels");
        assert!(inked > 200, "the run must actually paint; only {inked} pixels were lit");
        // Ink must not exceed the advertised width, and must fill most of it --
        // a run that measured far wider than it draws is the AutomaticSize bug.
        assert!((rightmost as f32) <= 20.0 + width + 2.0,
            "ink ran past the measured width: ends {rightmost}, measured {width}");
        assert!((rightmost as f32) > 20.0 + width * 0.75,
            "ink fell far short of the measured width: ends {rightmost}, measured {width}");
    }

    /// A VARIATION SELECTOR MUST NOT DRAW A BOX.
    ///
    /// es9: "emojis like the car in the shop menu have a box shaped glyph
    /// character trailing them". The emoji mapped fine -- U+1F697 to glyph 3802 --
    /// and U+FE0F after it fell through to `.notdef`, which this renderer draws
    /// on purpose so a missing font looks missing. A formatting character is the
    /// one case where that rule is wrong.
    #[test]
    fn variation_selectors_do_not_draw() {
        let Some(font) = segoe() else { return };

        let bare = "\u{1F697}";
        let with_vs = "\u{1F697}\u{FE0F}";

        let ids = |t: &str| -> Vec<u32> {
            with_fonts(|f| {
                f.layout(font, 32.0, t)
                    .map(|r| r.glyphs.iter().map(|g| g.id).collect())
                    .unwrap_or_default()
            })
        };

        let a = ids(bare);
        let b = ids(with_vs);
        // The emoji itself must resolve, or this test is asserting about a font
        // that cannot draw the character at all and proves nothing.
        assert_eq!(a.len(), 1, "the emoji should be one glyph");
        assert_ne!(a[0], 0, "the emoji must map to a real glyph, not .notdef");
        assert_eq!(b, a, "a variation selector must add no glyph, got {b:?} vs {a:?}");
        assert!(!b.contains(&0), "no .notdef may be drawn for a formatting character");

        // ZWJ, the bidi marks and a stray BOM are the same class of character.
        for t in ["a\u{200D}b", "a\u{200E}b", "a\u{FEFF}b", "a\u{00AD}b"] {
            let g = ids(t);
            assert_eq!(g.len(), 2, "{t:?} should draw two glyphs, got {}", g.len());
            assert!(!g.contains(&0), "{t:?} drew a .notdef");
        }

        // AND MEASUREMENT FOLLOWS. The selector was contributing .notdef's
        // advance, so every emoji-bearing string measured wider than it draws --
        // which is the AutomaticSize failure mode, not merely a cosmetic one.
        let wb = ar_text_width(font, 32.0, bare.as_ptr(), bare.len() as u32);
        let wv = ar_text_width(font, 32.0, with_vs.as_ptr(), with_vs.len() as u32);
        assert!(wb > 0.0);
        assert_eq!(wb, wv, "a variation selector must add no width: {wb} vs {wv}");

        // A character the font genuinely LACKS must still draw .notdef. Without
        // this the fix above could have been "skip anything that does not map",
        // which would make a missing font invisible instead of obvious.
        let missing = "\u{10FFFD}";
        let g = ids(missing);
        assert_eq!(g, vec![0],
            "an unmapped PRINTING character must still draw .notdef, got {g:?}");
    }

    /// The smallest possible question: does a surface of each backend, asked for
    /// one opaque rectangle, actually contain that colour afterwards?
    ///
    /// Written because the vello backend rendered BLACK through the FFI while the
    /// host's own check reported OK -- that check asserts a blended pixel matches
    /// neither the node's colour nor the one beneath it, and transparent black
    /// satisfies that vacuously. A backend that draws nothing passes it.
    #[test]
    fn each_backend_paints_a_rect() {
        for backend in [0u32, 1u32] {
            let s = ar_surface_new_backend(64, 64, backend);
            assert!(!s.is_null(), "backend {backend} did not allocate");
            ar_begin(s, 11, 13, 18);
            ar_fill_rect(s, 8.0, 8.0, 40.0, 40.0, 0.0, 200, 100, 50, 255);
            let inside = ar_pixel(s, 24, 24);
            let outside = ar_pixel(s, 2, 2);
            ar_surface_free(s);
            assert_eq!(
                inside, 0x00C8_6432,
                "backend {backend}: the filled rect should be (200,100,50), got {inside:#08x}"
            );
            assert_eq!(
                outside, 0x000B_0D12,
                "backend {backend}: the background should be (11,13,18), got {outside:#08x}"
            );
        }
    }
}
