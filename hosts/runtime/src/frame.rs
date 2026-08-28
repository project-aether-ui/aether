//! The display list, decoded.
//!
//! These structs mirror `src/host/Live.luau`'s `buildNode` field for field. That
//! file is the authority; this one follows it. When a field is added there it is
//! added here, and `Frame::CONTRACT_FIELDS` below is what keeps the two in step
//! rather than memory.
//!
//! `Option` IS LOAD-BEARING AND NOT A CONVENIENCE. Live.luau emits nil rather
//! than a default for `fill`, `stroke`, `gradient` and `text`, with the reason
//! stated there: "nothing set a colour" is a finding, and a default would erase
//! it. Decoding a missing fill as opaque black would invent geometry the Roblox
//! host does not draw — which is exactly the class of divergence this crate
//! exists to prevent.

use mlua::prelude::*;

/// 0-255 per channel, as Live.luau's `rgb()` emits them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rgb(pub u8, pub u8, pub u8);

impl Rgb {
    fn from_table(t: Option<LuaTable>) -> Option<Self> {
        let t = t?;
        Some(Rgb(t.get(1).ok()?, t.get(2).ok()?, t.get(3).ok()?))
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

#[derive(Debug, Clone)]
pub struct Stroke {
    pub colour: Option<Rgb>,
    pub thickness: f32,
    /// Already inverted from Roblox `Transparency` by Live.luau: 1 is opaque.
    pub alpha: f32,
}

/// A colour ramp stop.
#[derive(Debug, Clone, Copy)]
pub struct Stop {
    pub at: f32,
    pub colour: Rgb,
}

/// An alpha ramp stop.
#[derive(Debug, Clone, Copy)]
pub struct AlphaStop {
    pub at: f32,
    pub alpha: f32,
}

/// A UIGradient.
///
/// `stops` is a COLOUR ramp and `alpha_stops` an ALPHA ramp, and a gradient may
/// carry either or both. Live.luau records what happens when only the first is
/// honoured: one of ShopUI's two gradients went unexpressed and a window body
/// read flat, because its gradient is a `Transparency` NumberSequence with no
/// colour to interpolate. A painter that handles only `stops` reproduces that
/// bug, so both are decoded here whether or not a painter uses them yet.
#[derive(Debug, Clone, Default)]
pub struct Gradient {
    pub stops: Vec<Stop>,
    pub alpha_stops: Vec<AlphaStop>,
    pub rotation: f32,
}

/// Text alignment on one axis.
///
/// THE DEFAULT IS THE HALF THAT MATTERS. An unset `TextXAlignment` is CENTRE in
/// Roblox, not left. Live.luau supplies that default once, at the source, because
/// three separate painters had each invented their own left inset and every icon
/// in the shop kit sat in the wrong place. Nothing downstream re-decides it, and
/// nothing here should either.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Align {
    Start,
    Center,
    End,
}

impl Align {
    fn parse(s: Option<String>) -> Option<Self> {
        Some(match s?.as_str() {
            "left" | "top" | "start" => Align::Start,
            "right" | "bottom" | "end" => Align::End,
            _ => Align::Center,
        })
    }
}

/// One node of the display list, in paint order.
#[derive(Debug, Clone)]
pub struct Node {
    /// Stable across frames, so a display can patch one node rather than rebuild
    /// the screen. This is what makes [`Delta`] worth having.
    pub id: u64,
    pub name: String,
    pub rect: Rect,
    pub fill: Option<Rgb>,
    pub alpha: f32,
    pub radius: f32,
    pub clip: Option<Rect>,
    pub stroke: Option<Stroke>,
    pub gradient: Option<Gradient>,
    pub text: Option<String>,
    pub text_size: f32,
    pub text_align_x: Option<Align>,
    pub text_align_y: Option<Align>,
    pub text_colour: Option<Rgb>,
}

#[derive(Debug, Clone)]
pub struct Frame {
    pub width: f32,
    pub height: f32,
    pub nodes: Vec<Node>,
    /// Whether a text field holds focus. A display needs this to decide whether
    /// to swallow a keystroke's own default; it cannot wait to be told whether
    /// the guest consumed the key, because that answer is a round trip away and
    /// by then the surface has already acted on it.
    pub focused: bool,
}

impl Frame {
    /// Every key `buildNode` emits.
    ///
    /// Not decoration: `tests/frame_contract.rs` asserts a real snapshot carries
    /// exactly these, so a field added in Live.luau and forgotten here fails a
    /// test instead of being silently dropped on the way to the painter. The
    /// alternative is the failure mode this whole module is written against —
    /// a display that quietly paints less than the engine does.
    pub const CONTRACT_FIELDS: &'static [&'static str] = &[
        "id",
        "name",
        "x",
        "y",
        "w",
        "h",
        "fill",
        "alpha",
        "radius",
        "clip",
        "stroke",
        "gradient",
        "text",
        "textSize",
        "textAlignX",
        "textAlignY",
        "textColour",
    ];
}

/// What changed since the last delta.
///
/// `order` and `dirty` are absent when nothing moved, which is the property the
/// type exists for: an idle screen produces no traffic.
#[derive(Debug, Clone)]
pub struct Delta {
    pub width: f32,
    pub height: f32,
    pub focused: bool,
    pub changed: Vec<Node>,
    pub removed: Vec<u64>,
    pub order: Option<Vec<u64>>,
    pub dirty: Option<Rect>,
    /// The frame this delta was computed from, handed back because computing the
    /// delta already built it. Asking for both separately walks every node twice.
    pub frame: Frame,
}

fn rect_from_array(t: Option<LuaTable>) -> Option<Rect> {
    let t = t?;
    Some(Rect {
        x: t.get(1).ok()?,
        y: t.get(2).ok()?,
        w: t.get(3).ok()?,
        h: t.get(4).ok()?,
    })
}

fn stops_from(t: Option<LuaTable>) -> Vec<Stop> {
    let Some(t) = t else {
        return Vec::new();
    };
    t.sequence_values::<LuaTable>()
        .flatten()
        .filter_map(|s| {
            Some(Stop {
                at: s.get("at").or_else(|_| s.get(1)).ok()?,
                colour: Rgb::from_table(s.get("colour").or_else(|_| s.get(2)).ok())?,
            })
        })
        .collect()
}

fn alpha_stops_from(t: Option<LuaTable>) -> Vec<AlphaStop> {
    let Some(t) = t else {
        return Vec::new();
    };
    t.sequence_values::<LuaTable>()
        .flatten()
        .filter_map(|s| {
            Some(AlphaStop {
                at: s.get("at").or_else(|_| s.get(1)).ok()?,
                alpha: s.get("alpha").or_else(|_| s.get(2)).ok()?,
            })
        })
        .collect()
}

impl Node {
    pub fn from_lua(t: &LuaTable) -> LuaResult<Self> {
        let stroke = t.get::<Option<LuaTable>>("stroke")?.map(|s| Stroke {
            colour: Rgb::from_table(s.get("colour").ok()),
            thickness: s.get("thickness").unwrap_or(1.0),
            alpha: s.get("alpha").unwrap_or(1.0),
        });

        let gradient = t.get::<Option<LuaTable>>("gradient")?.map(|g| Gradient {
            stops: stops_from(g.get("stops").ok()),
            alpha_stops: alpha_stops_from(g.get("alphaStops").ok()),
            rotation: g.get("rotation").unwrap_or(0.0),
        });

        Ok(Node {
            id: t.get("id")?,
            name: t.get::<Option<String>>("name")?.unwrap_or_default(),
            rect: Rect {
                x: t.get("x")?,
                y: t.get("y")?,
                w: t.get("w")?,
                h: t.get("h")?,
            },
            fill: Rgb::from_table(t.get("fill")?),
            alpha: t.get::<Option<f32>>("alpha")?.unwrap_or(1.0),
            radius: t.get::<Option<f32>>("radius")?.unwrap_or(0.0),
            clip: rect_from_array(t.get("clip")?),
            stroke,
            gradient,
            text: t.get("text")?,
            text_size: t.get::<Option<f32>>("textSize")?.unwrap_or(14.0),
            text_align_x: Align::parse(t.get("textAlignX")?),
            text_align_y: Align::parse(t.get("textAlignY")?),
            text_colour: Rgb::from_table(t.get("textColour")?),
        })
    }
}

impl Frame {
    pub fn from_lua(t: &LuaTable) -> LuaResult<Self> {
        let nodes_tbl: LuaTable = t.get("Nodes")?;
        let mut nodes = Vec::with_capacity(nodes_tbl.raw_len());
        for n in nodes_tbl.sequence_values::<LuaTable>() {
            nodes.push(Node::from_lua(&n?)?);
        }
        Ok(Frame {
            width: t.get("Width")?,
            height: t.get("Height")?,
            nodes,
            focused: t.get::<Option<bool>>("Focused")?.unwrap_or(false),
        })
    }
}

impl Delta {
    pub fn from_lua(t: &LuaTable) -> LuaResult<Self> {
        let changed_tbl: LuaTable = t.get("Changed")?;
        let mut changed = Vec::with_capacity(changed_tbl.raw_len());
        for n in changed_tbl.sequence_values::<LuaTable>() {
            changed.push(Node::from_lua(&n?)?);
        }

        let removed = t
            .get::<LuaTable>("Removed")?
            .sequence_values::<u64>()
            .flatten()
            .collect();

        let order = t
            .get::<Option<LuaTable>>("Order")?
            .map(|o| o.sequence_values::<u64>().flatten().collect());

        Ok(Delta {
            width: t.get("Width")?,
            height: t.get("Height")?,
            focused: t.get::<Option<bool>>("Focused")?.unwrap_or(false),
            changed,
            removed,
            order,
            dirty: rect_from_array(t.get("Dirty")?),
            frame: Frame::from_lua(&t.get::<LuaTable>("Frame")?)?,
        })
    }
}
