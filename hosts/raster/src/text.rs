//! Text, moved out of the platform and into the renderer (ms-52 M11).
//!
//! WHY THIS EXISTS AT ALL, given two decisions said not to write it.
//! `D-owning_the_rasterizer.md` and `D-fonts_across_hosts.md` both argued for
//! delegating text to the platform, and that was right while the platform could
//! still reach the surface. A wgpu swapchain ends that: GDI cannot draw onto a
//! surface wgpu owns, so a windowed GPU host must rasterise its own glyphs. es9
//! chose the windowed GPU path knowing that, so text comes here.
//!
//! MEASUREMENT AND PAINTING MUST STAY TOGETHER. This is the one rule the earlier
//! work established with a real failure behind it: ms-52 M7 shipped a host that
//! painted with Segoe UI Symbol while layout measured with a bundled advance
//! table -- 5% out on ordinary labels, 21% on a narrow-glyph run, and anything
//! using `AutomaticSize` sized to a width nothing would draw. So the SAME function
//! that positions glyphs for painting also answers the width query, and there is
//! no second implementation that could drift from it.
//!
//! WHAT THIS IS NOT: shaping. Mapping characters to glyphs through the font's
//! cmap and advancing by each glyph's own width is correct for the Latin and
//! symbol runs these screens use, and is wrong for Arabic, Devanagari, emoji
//! sequences and anything needing ligatures or kerning. That is `parley`'s job and
//! it is a later step; pretending otherwise here would hide the gap.

use skrifa::instance::{LocationRef, Size};
use skrifa::metrics::GlyphMetrics;
use skrifa::{FontRef, MetadataProvider};
use std::collections::HashMap;
use std::sync::Arc;
use vello_cpu::peniko::{Blob, FontData};

pub struct Font {
    pub data: FontData,
    bytes: Arc<Vec<u8>>,
}

impl Font {
    fn font_ref(&self) -> Option<FontRef<'_>> {
        FontRef::new(self.bytes.as_slice()).ok()
    }
}

#[derive(Default)]
pub struct FontStore {
    fonts: HashMap<u32, Font>,
    next: u32,
}

/// One positioned glyph, in the coordinate space `glyph_run` expects: x advances
/// along the run and y sits on the BASELINE.
#[derive(Clone, Copy)]
pub struct Positioned {
    pub id: u32,
    pub x: f32,
    pub y: f32,
}

pub struct Run {
    pub glyphs: Vec<Positioned>,
    pub width: f32,
    pub ascent: f32,
    pub descent: f32,
    pub line_height: f32,
}

/// Characters that are NEVER drawn, however the font answers.
///
/// There are two reasons a character can fail to map to a glyph and they need
/// opposite treatment:
///
///   * The font LACKS it. Drawing `.notdef` -- a box -- is right: it makes a
///     missing face look missing, and this host has already spent a session on
///     "the icons are not showing" for exactly that reason.
///   * The character DOES NOT DRAW AT ALL. Format and zero-width characters are
///     instructions to the shaper, not marks. A font has no glyph for them
///     because it should not, so `.notdef` is a wrong answer to the wrong
///     question.
///
/// es9 found the second case as "emojis like the car in the shop menu have a box
/// shaped glyph character trailing them". That box is U+FE0F, VARIATION
/// SELECTOR-16, which asks for emoji presentation and occupies no width. The
/// emoji itself mapped perfectly (U+1F697 to glyph 3802); the selector after it
/// became a box.
///
/// This also corrects MEASUREMENT: the selector was contributing `.notdef`'s
/// advance, so every emoji-bearing string measured wider than it draws.
fn is_non_printing(ch: char) -> bool {
    matches!(ch as u32,
        // Variation selectors 1-16, and the supplement.
        0xFE00..=0xFE0F | 0xE0100..=0xE01EF
        // Zero-width space, ZWNJ, ZWJ, and the bidi marks.
        | 0x200B..=0x200F
        // Word joiner and the invisible math operators.
        | 0x2060..=0x2064
        // Bidi embedding/override controls, and the isolates.
        | 0x202A..=0x202E | 0x2066..=0x2069
        // Zero-width no-break space, better known as a stray BOM.
        | 0xFEFF
        // Soft hyphen: a line-break opportunity, not a mark.
        | 0x00AD
        // Tag characters, used in emoji flag sequences.
        | 0xE0020..=0xE007F)
}

impl FontStore {
    pub fn load(&mut self, bytes: Vec<u8>, index: u32) -> u32 {
        let bytes = Arc::new(bytes);
        // The blob and skrifa share ONE allocation rather than two copies: a font
        // file is megabytes, and holding it twice for the same glyphs would be
        // the sort of quiet cost this milestone is trying to remove.
        let blob = Blob::new(bytes.clone() as Arc<dyn AsRef<[u8]> + Send + Sync>);
        self.next += 1;
        let id = self.next;
        self.fonts.insert(id, Font { data: FontData::new(blob, index), bytes });
        id
    }

    pub fn get(&self, id: u32) -> Option<&Font> {
        self.fonts.get(&id)
    }

    /// Lay one run out. THE SINGLE SOURCE for both painting and measurement.
    ///
    /// Returns `None` only when the font id is unknown or the file did not parse,
    /// which callers must treat as a failure rather than as an empty string --
    /// a zero width collapses the element, which is far more destructive than an
    /// approximate one.
    pub fn layout(&self, id: u32, size: f32, text: &str) -> Option<Run> {
        let font = self.get(id)?;
        let fr = font.font_ref()?;
        let px = Size::new(size);
        let coords = LocationRef::default();
        let metrics = fr.metrics(px, coords);
        let gm: GlyphMetrics = fr.glyph_metrics(px, coords);
        let charmap = fr.charmap();

        let mut glyphs = Vec::with_capacity(text.len());
        let mut x = 0.0_f32;
        for ch in text.chars() {
            // Formatting characters carry no mark and no width. See
            // `is_non_printing`: this is the ONE case where a missing glyph must
            // not become a box.
            if is_non_printing(ch) {
                continue;
            }
            // A character the font has no glyph for maps to .notdef (0), which
            // DRAWS -- usually as a box. That is deliberate: silently skipping it
            // would make a missing font look like a missing string, and this host
            // has already spent a session on "the icons are not showing".
            let gid = charmap.map(ch).unwrap_or_default();
            let advance = gm.advance_width(gid).unwrap_or(0.0);
            glyphs.push(Positioned { id: gid.to_u32(), x, y: 0.0 });
            x += advance;
        }

        let ascent = metrics.ascent;
        let descent = metrics.descent.abs();
        Some(Run {
            glyphs,
            width: x,
            ascent,
            descent,
            line_height: ascent + descent + metrics.leading,
        })
    }
}
