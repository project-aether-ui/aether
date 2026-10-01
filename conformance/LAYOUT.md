# DataModel Standard: layout

What an implementation must compute, given a tree, to produce the same rectangles
Roblox produces.

This is the half of the standard with no machine-readable source. The class and
property surface is generated from Roblox's own reflection database; layout
behaviour is documented only by observation, and every claim below is either
verified against the engine or marked as not.

| Marker | Means |
| :--- | :--- |
| **[verified]** | A conformance case observed this in Studio. The case name is given. |
| **[reference]** | Recorded from the Luau implementation. It is what we do, not necessarily what Roblox does. |
| **[asserted]** | A case states it from Roblox's documentation and nobody has run it in Studio yet. |
| **[unverified]** | Believed, and neither observed nor tested. Treat as a question. |
| **[verified-relationally]** | A case proves a ratio, a minimum or an integer multiple rather than a value, because the value is a property of the host. |

Each case records the build that verified it. Every verified case cites Roblox
**0.741.19.7411056**, the same build the class and property surface is pinned
to. Property defaults still come from a reflection database at **0.728**, so
the standard's two halves are measured against different builds. Neither is
wrong; the skew is worth knowing before someone reconciles two numbers that
were never taken at the same time.

Nothing here is normative because it is written down. It is normative because a
case in `cases/` proves it, and the ones that carry no case are the ones to be
suspicious of.

## 1. Coordinate model

A `UDim2` is `{scale, offset}` per axis, and the two **add**. Scale resolves
against the parent's resolved size on that axis; offset is a count of pixels.

    width  = parent.width  * size.X.Scale + size.X.Offset
    height = parent.height * size.Y.Scale + size.Y.Offset

Position resolves the same way, against the parent's origin:

    x = parent.x + parent.width  * position.X.Scale + position.X.Offset
    y = parent.y + parent.height * position.Y.Scale + position.Y.Offset

**[verified]** `scale resolves against the parent, not the surface` -- nesting two
half-scale frames gives a quarter, not a half.
**[verified]** `scale and offset combine additively` -- a negative offset insets a
full-width child, which is the idiom every padded container uses.

The root element resolves against the surface, whose origin is `(0, 0)`.

## 2. Resolution order

For one element, in this order:

1. **Size**, from the parent's resolved size.
2. **Position**, from the parent's resolved origin and size.
3. **AnchorPoint**, subtracted from the position as a fraction of the element's
   own size.

Anchor comes last because it depends on the size computed in step 1. An
implementation that applies it earlier has nothing to multiply.

    x -= width  * anchorPoint.X
    y -= height * anchorPoint.Y

**[verified]** `anchor point shifts an element by a fraction of its own size` --
`(0.5, 0.5)` at position `(0.5, 0.5)` centres the element on the parent's centre.

**[asserted]** `AnchorPoint offsets by the size AutomaticSize produced` -- and
"its own size" means the size after `AutomaticSize` has decided it, not the
authored one. The ordering matters only when an element is both anchored and
auto-sized, which is why Aether got it wrong for the life of the file: the anchor
was applied while resolving the element, against an authored height that is
usually zero, so the offset was zero and the element sat as though anchored at
the top-left.

Children are then resolved against the **content box**: the element's own
rectangle, inset by any `UIPadding` child. A container's own rectangle is never
inset by its padding; only what it offers its children is.

## 3. AutomaticSize

The parent measures its children instead of being told its size. The authored
size is a **floor**, not the answer: an element never shrinks below what it was
written as.

    resolved = max(authored, measuredExtent + padding)

Measurement happens **after** children are placed, because it depends on where
they landed.

### The cycle, and the rule that breaks it

A parent measuring an axis depends on its children; a child sized in Scale on
that axis depends on its parent. Roblox breaks the loop by resolving the child's
scale against **the space the parent was offered** -- the box its own parent gave
it -- rather than against the parent's final measured size. The parent then fits
the result.

**[verified]** `AutomaticSize resolves a Scale-sized child against the available
space` -- a `{1,0, 0.5,20}` child of an auto-sizing frame, on a 200-tall surface,
makes the frame 120 tall. That is `0.5 * 200 + 20`.

Neither of the two obvious guesses is right. Treating the scale as zero and
measuring only the offset gives 20; excluding the child from the measurement
gives 0. The engine gives 120.

**[verified]** `AutomaticSize with a Scale child under a smaller grandparent` --
the same child under an 80-tall grandparent makes the frame 60 tall, which is
`0.5 * 80 + 20`. It is the space the parent was **offered**, not the surface. The
first verified case could not distinguish the two, because there they were the
same 200; this one separates them.

**[reference]** The rule is applied to immediate children only. Deeper
descendants sized in Scale on the measured axis contribute nothing. No case
covers nesting.

`UIPadding` is included in the measured size: the parent grows to fit its
children **plus** its own padding, rather than the children being inset into a
size already decided.

**[verified]** `AutomaticSize includes UIPadding in the measured size`.

## 4. UIListLayout

A container carrying one assigns its children positions in sequence along
`FillDirection`, separated by `Padding`.

**A child under a list cannot position itself.** Its own `Position` is ignored,
not added to the slot.

**[verified]** `UIListLayout stacks children and ignores their Position` -- a
first child with `Position.Y = 50` lands at `y = 0`.

Under `SortOrder = LayoutOrder`, order is `LayoutOrder`, then declaration order.
The cursor advances by what each child actually resolved to, so a stack of
differently-sized rows lays out correctly.

**What the standard says is separate from who implements it.** `SortOrder`,
`HorizontalAlignment` and `VerticalAlignment` are part of the standard, and the
cases below state what they do. **[reference]** The Luau implementation reads
none of the three. Dew reads the two alignments on the cross axis only, and sorts
by `LayoutOrder` whatever `SortOrder` says. Neither sentence is a claim about the
engine.

Every claim below is **[verified]** against Roblox **0.741.19.7411056** by the
case named. A case whose behaviour Dew does not implement yet carries `requires`,
and reports unsupported there rather than failing. Some case names state the
guess they were written to test; where a name and its expectation disagree, the
expectation is the engine's.

**Ordering.** `SortOrder` defaults to `Name` on `UIListLayout`, `UIGridLayout`,
`UITableLayout` and `UIPageLayout`, read from fresh instances in the command bar.
Ties fall back to declaration order.
**[verified]** `UIListLayout with SortOrder unset orders children by Name`,
`UIListLayout with SortOrder Name ignores LayoutOrder`, `UIListLayout breaks an
equal LayoutOrder by declaration order`, `UIListLayout with SortOrder unset and
identical names keeps declaration order`.

**[verified]** `UIListLayout gives an invisible child no slot and no Padding`.
**[verified]** `UIListLayout places a child with AnchorPoint as though it had
none`, on both axes.

**Alignment.** Alignment applies on the main axis too, and a run longer than the
panel is centred past its edge rather than clamped to it.
**[verified]** `UIListLayout VerticalAlignment Center centres a vertical run`,
`... Bottom pushes a vertical run down`, `UIListLayout HorizontalAlignment Center
centres a horizontal run`, `UIListLayout centres an overflowing run past the top
edge`.

**Padding.** The scale in `Padding` resolves against the content box inside any
`UIPadding`, not the parent's full size: `UDim(0.1, 4)` in a 120 panel padded 10
on each side gives a gap of 14.
**[verified]** `UIListLayout Padding scale resolves against the parent's width`
and `... height`.

**Wraps.** A child that does not fit starts a new line, lines are separated by
`Padding`, and a child wider than the panel takes a line of its own, unshrunk.
Main axis alignment centres each line on its own width; cross axis alignment
moves the block of lines, first line on top.
**[verified]** `UIListLayout Wraps moves an overflowing child to a new row`,
`... to a new column`, `... gives a child wider than the panel its own row`,
`... with HorizontalAlignment Center centres each row on its own width`, `...
with VerticalAlignment Bottom aligns the block of rows`.
**[verified]** `AbsoluteContentSize` is the extent of the lines, `Padding`
included: 145 by 55 for `UIListLayout Wraps moves an overflowing child to a new
row`, read in the command bar.

**HorizontalFlex.** `None` packs at the start. `Fill` grows every child by an
equal share of the free space left after `Padding`, and on a vertical list makes
every child the panel's width. `SpaceBetween`, `SpaceAround` and `SpaceEvenly`
take their CSS meanings; a lone child sits at the start under `SpaceBetween` and
in the centre under the other two.
**[verified]** `UIListLayout HorizontalFlex None does not distribute`, `... Fill
grows every child by an equal share`, `... Fill keeps Padding as a fixed gap`,
`... Fill stretches a vertical list's children across`, `... SpaceBetween puts
the free space between children`, `... SpaceAround puts equal space around each
child`, `... SpaceEvenly makes every gap equal, edges included`, `... SpaceBetween
on a vertical list moves nothing`, and the four `... with a single child`.

`SpaceAround` and `SpaceEvenly` ignore `Padding`: with `Padding` 6, widths 20, 40
and 60 in 240 land exactly where they land without it.
**[verified]** `UIListLayout HorizontalFlex SpaceAround keeps Padding as a fixed
gap`, `... SpaceEvenly keeps Padding as a fixed gap`. `... SpaceBetween keeps
Padding as a fixed gap` also matches the positions without `Padding`, which
cannot tell ignoring it from treating it as a minimum gap.

When the children overflow, `Fill` shrinks each in proportion to its width, not
by an equal share: 60, 90 and 150 in 240 become 48, 72 and 120.
**[verified]** `UIListLayout HorizontalFlex Fill shrinks overflowing children by
an equal share`.

**[verified]** `AbsoluteContentSize` counts the children, not the distributed
space: for widths 20, 40 and 60 it reads 120 by 20 under `None`, `SpaceAround`,
`SpaceBetween` and `SpaceEvenly`, and 240 by 20 under `Fill`, where the children
themselves grew. Read in the command bar from `UIListLayout HorizontalFlex None
does not distribute` and the four plain `Fill`, `SpaceAround`, `SpaceBetween` and
`SpaceEvenly` cases.

**ItemLineAlignment.** Aligns each child within its line, and a line without
`Wraps` is as tall as its tallest child, not the panel. Heights 20, 30 and 40 in
a 60 tall panel: `Start` puts all three at y 0, `Center` at 10, 5 and 0, `End` at
20, 10 and 0, and `Stretch` makes all three 40 tall.
**[verified]** `UIListLayout ItemLineAlignment Start on a single line`, `...
Center ...`, `... End ...`, `... Stretch ...`.
`Automatic` defers to `VerticalAlignment`, which aligns against the panel: under
`Bottom` the same children sit on the panel's bottom edge, at 40, 30 and 20.
**[verified]** `UIListLayout ItemLineAlignment Automatic defers to
VerticalAlignment`.

**UIFlexItem.** Defaults, from the command bar: `FlexMode` `None`, `GrowRatio` 0,
`ShrinkRatio` 0, `ItemLineAlignment` `Automatic`.

`Grow` children split the free space equally whatever their widths: 40 and 120
in 200 become 60 and 140. `Custom` splits it by `GrowRatio`, and a ratio of 0
takes nothing. `GrowRatio` is ignored unless `FlexMode` is `Custom`. `Fill` grows
into free space. The basis is a child's resolved size, scale included. Growth is
per wrapped line, comes before the list's `SpaceBetween` and leaves it nothing,
and under the list's `Fill` adds to every child's share rather than replacing it.
**[verified]** `UIFlexItem Grow takes the free space beside a child with no
flex`, `UIFlexItem two Grow children split the free space equally`, `UIFlexItem
Custom GrowRatio 1 and 2 splits free space one to two`, `... 0 and 1 gives all
free space to the second`, `... 0 and 0 grows nothing`, `UIFlexItem GrowRatio is
ignored when FlexMode is None`, `UIFlexItem Fill grows into free space`,
`UIFlexItem Grow uses a scale-sized child's resolved size as its basis`,
`UIFlexItem Grow with Wraps grows within its own line`, `UIFlexItem Grow
consumes the free space before HorizontalFlex SpaceBetween`, `UIFlexItem Grow
under HorizontalFlex Fill grows alongside its siblings`.

Shrinking is not an equal share. In the two cases with more than one shrinking
child, each child's loss is proportional to its width times its shrink ratio
(1 for `Shrink`). Two cases do not establish that rule beyond them.
**[verified]** `UIFlexItem two Shrink children share an overflow equally`: 100
and 200 in 150 become 50 and 100.
**[verified]** `UIFlexItem Custom ShrinkRatio 1 and 3 shares an overflow one to
three`: 100 and 140 in 200 become 92.31 and 107.69, the 40 overflow split 100 to
420. The exact values are 1200/13 and 1400/13; the engine runner rounds to two
places.
**[verified]** `UIFlexItem Fill shrinks out of an overflow`: a lone `Fill` child
absorbs the whole overflow.

**[verified]** `UIFlexItem under a parent with no UIListLayout has no effect`,
`UIFlexItem under a UIGridLayout has no effect on the cell`.
**[verified]** `UIFlexItem ItemLineAlignment Stretch overrides the list's
Center`, but every child in it is 20 tall, so the line is 20 tall and neither
value moves anything. The per item override is still unobserved.
**[asserted]** `UIFlexItem ItemLineAlignment Stretch stretches one child in a
centred line` gives the line children 20, 40 and 30 tall so the override can
move the stretched one; it awaits a Studio pass.

## 5. Clipping

`ClipsDescendants` intersects a child's visible rectangle with its ancestor's.
The intersection is carried on the display list as a **rectangle**.

**[divergent]** Roblox clips to the parent's rounded shape when a `UICorner` is
present; this implementation does not, because the display list's clip has no
radius. A child of a rounded clipping parent keeps square corners.

**[verified]** `a clipped child keeps its rectangle (the radius gap is
invisible here)` -- and the engine agrees,
which is the point: **the divergence is invisible to a geometric assertion.**
Clipping to a rounded parent does not move a child, it changes which of its
pixels survive. Catching it needs a clip radius in the display list and a
pixel-level runner.

## 6. Paint order

Back-to-front order is `ZIndex`, then depth, then declaration order. The solve
returns a flat list in the order a renderer should walk it.

**[reference]** `ZIndex orders the paint, then depth, then declaration` -- three
siblings declared in one order and ZIndexed into another come back in ZIndex
order. It is the only case in the suite that asserts a **sequence**, because
paint order is a property of the list rather than of any node in it.

**It cannot be verified against the engine, and will stay `reference` until
something can.** Roblox exposes no display list and no painted sequence: two
overlapping frames look different and report identical geometry. The engine
runner reports this case as *unobservable* rather than agreeing with it, which is
the same discipline as refusing to agree with a case that asserts nothing.

### Three gaps, one missing instrument

| Gap | Why a geometric runner cannot see it |
| :--- | :--- |
| Paint order | overlapping elements report the same rectangles either way |
| Clip radius | rounding a clip changes which pixels survive, not where the child is |
| Gradient kind | a gradient moves nothing |

All three need the same thing: a runner that compares **rendered pixels** rather
than rectangles. That is one instrument closing three holes, and it is the
largest single upgrade available to this suite.

## 7. Text measurement

**Text measurement is a host service, not a layout rule.** Layout asks how wide a
string is and uses the answer; it does not decide what the answer is.

That is not an implementation detail to be tidied away later. There are four
providers and they give four answers:

| Host | Provider |
| :--- | :--- |
| Roblox | the engine's own text bounds, exact |
| Aether headless | a per-glyph advance table for a nominal humanist sans |
| Web | the browser, through a cache it fills asynchronously |
| Dew and the CLI | real font metrics, through skrifa |

So **no case may assert that a string is 71.4 pixels wide.** That is true of one
provider. A standard that fixed the number would be describing a font rather than
describing layout, and would make every implementation with a different face
non-conformant for being correct.

### What is specifiable

The relationships, which every correct provider agrees on.

**[verified-relationally]** `text measurement is linear in TextSize` -- doubling
the size doubles the measured width and the line height, because an advance is a
fraction of the em square and the em square is the size.

Measured on the engine: height exactly **2.0000**, width **1.9896**. Linearity is
something an implementation may rely on; exactness is not, and the missing
percent is glyph advances rounding differently at 14 and at 28.

**[verified-relationally]** `text measurement is per glyph, not per character` --
`WWWW` and `llll` are the same length and nowhere near the same width. This rules
out `#text * factor`, which reports a plausible width for every string while
being wrong about all of them, and which passes any test that only checks a width
is non-zero.

**The spread between providers is measured, and it is large.** For those two
strings the engine reports **4.4286** and Aether's off-engine table **3.39**.
Both conform. Any implementation measuring per character reports exactly 1.0, and
that is the only thing the case forbids.

So this one asserts a **minimum** rather than a value. A tolerance fitted around
either observed number would make the case assert a font instead of asserting the
rule, and would fail the other host for being right. Ratios and minimums are the
mechanism the suite offers for anything an implementation cannot be held to
exactly; text is the first thing to need them.

### Line height

**[verified]** `one line of text is a fixed multiple of TextSize` -- a
single-line auto-sized label resolves to exactly **1.5 x TextSize**. Measured
against a `Frame` of fixed height rather than against another text element, since
a ratio between two labels cancels the line height out.

Aether used **1.2** and had done since the file was written, under a comment
asserting that "Roblox's own text bounds report the same shape". Nobody had
checked. Every auto-sized `TextLabel` off-engine was twenty percent short --
small enough to read as a font difference, large enough to misplace everything
below it in a list.

**[unverified]** Whether 1.5 is purely line height or includes something the
engine adds. What is established is the resolved height, which is what layout
needs.

**The 1.5 belongs to the face.** That case uses the default face, LegacyArial.
A command-bar probe read one line as 1.5 x TextSize in LegacyArial and 1.0 x in
Source Sans Pro and Builder Sans, at 14, 20 and 32.

**[asserted]** `one line of LegacyArial is one and a half TextSize tall`,
`one line of Source Sans Pro is one TextSize tall` and
`one line of Builder Sans is one TextSize tall`, each against a ruler at three
sizes.

### Font face

**[asserted]** `LegacyArial is Arimo at one and a half times the size`. The
LegacyArial family file names Arimo's own files; what makes it Legacy is a
scale of 1.5 on both axes. That scale is where the 1.5 line height comes from.

**[asserted]** `the font face sets the width of a string` and
`Builder Sans sets its own width`. The same string at the same size measures
differently in each face. Asserted as ratios between faces, never as widths,
for the reasons in the next section.

Builder Sans has cases of its own, gated on `FontFace.BuilderSans`, because
its licence does not allow redistribution. An implementation can honour every
open face and still have no Builder Sans to draw.

These cases set the family through the legacy `Font` enum (`Legacy`, `Arimo`,
`SourceSans`, `BuilderSans`), which the engine resolves to the matching
`FontFace`. The value encoding has no `Font` datatype yet.

### Measured width is not reproducible to the last percent

The same case, on the same build and the same machine, reported a width ratio of
**1.9896** on one run and **2.0244** on the next. The height ratio was exactly
**2.0000** both times.

**The Studio viewport was resized between those two runs, and a third run
returned exactly 1.9896.** So the measurement is deterministic for a given
display configuration and moves with the configuration -- it is not drift, and it
is not a font arriving late.

That is consistent with the split: line height is computed from `TextSize`
arithmetically and is stable, while width comes from glyph advances that are
rasterised and rounded, so a change in display scale moves it.

**[unverified]** Whether the sensitivity is to viewport size, device pixel ratio,
or GUI scale specifically. Three runs identify *that* the configuration matters,
not *which part of it*.

What follows: **a measured text width is reproducible for a given display and
not across displays**, so the standard cannot fix one and a case must not assert
one. That is the second independent reason for the rule, after the four
providers, and this one applies even within a single provider on a single
machine.

### The contract layout depends on

**Measurement must be synchronous.** `Layout.Solve` runs inside a frame and
returns; it cannot await. A provider that must round-trip to answer cannot answer
during the solve that needs it, which is why the web host answers from a cache
and converges after the first frame that draws a given string rather than
blocking on the browser.

An implementation whose measurement is asynchronous has to make the same choice:
answer approximately now, or do not answer at all. It may not make layout wait.

### Wrapping

`TextWrapped` breaks a string that does not fit the element's width;
`AutomaticSize.Y` then grows the element to hold the resulting lines. With
`TextWrapped` off the string overflows instead, and the element stays one line
tall however long the text is.

**Aether implements none of this.** `TextWrapped` is read by nothing, so both
cases below are gated behind `requires` and report as unsupported rather than
failing. They can still be verified against the engine, which is the point of the
gate: a case may know the right answer before anything implements it.

**[asserted]** `TextWrapped grows the height past one line` -- a string several
times its element's width occupies at least two lines. Asserted as a **minimum**,
because where the breaks fall is provider-specific and the line count follows
from it. An implementation ignoring `TextWrapped` reports exactly 1.0.

**[asserted]** `TextWrapped off keeps a long string on one line` -- the negative
half, and the one that catches an implementation growing height for the wrong
reason. Without it, something that measured height from the unwrapped width would
pass the case above.

**Break positions are deliberately not specified.** They are where two providers
diverge most: the same string, the same width and the same nominal font can break
differently on different rasterisers. A standard fixing them would be describing
one text shaper.

### TextScaled

`TextScaled` inverts the relationship. Everywhere else the box is measured from
the text; here the text is chosen to fit the box, and `TextSize` stops being the
answer.

**It is hard to observe, and that is the interesting part.** The element's size
is whatever the tree set, so no geometric field reports what changed. What
changed is the size the text is RENDERED at, which Roblox exposes as `TextBounds`
and the display list carries as `textSize`.

Those are proportional rather than equal -- one is a font size, the other that
size times a line height -- so the suite reads them through a derived
`textHeight` field and **only ratios over it are meaningful**. An absolute
assertion on `textHeight` would be comparing a font size against a block height.

**[verified-relationally]** `TextScaled chooses the text size from the box` -- the
same string in boxes of 1x and 2x height renders at 1x and 2x. An implementation
ignoring `TextScaled` honours `TextSize` in both and reports 1.0.

The engine returned exactly **2.0000**. Slack had been allowed for a fit that
might round to a whole font size; it did not, so **the scaling is proportional
rather than snapped**, and the case's tolerance is now tight enough to catch a
clamped fit rather than loose enough to admit one.

**Aether implements none of this.** `TextScaled` appears in one comment and is
read by nothing, so the case is gated behind `requires`.

**[unverified]** What happens when `TextScaled` and `AutomaticSize` are both set
on the same axis. Each wants the other to decide, which is the same shape as the
scale-under-AutomaticSize cycle in section 3 -- and that one turned out to have a
specific answer nobody guessed, so this one probably does too.

### Padding, RichText and LineHeight

**[asserted]** `UIPadding adds to an auto-sized label's text extent`. A label
grows to hold its text plus its own padding, so the padding insets the text
instead of eating into it. The height is checked against a ruler; the width
only as a minimum, since the width of the text belongs to the face.

**[asserted]** `RichText measures the content, not the markup`. With RichText
on, the tags are not measured. With it off, they are measured as text.

**[asserted]** `LineHeight spaces lines and leaves one line alone`. One line is
the same height at LineHeight 2 as at 1. Three lines grow by at least half;
whether every line doubles or only the gaps after the first is not settled.

### What is drawn, as against what is laid out

An auto-sized label never truncates or drops a line, so neither shows in its
size. These claims are read from the text itself: `textBoundsX` and
`textBoundsY` (the engine's `TextBounds`), `textFits` and `contentText`. Lines
are counted as a ratio to a one-line label, and widths only against the
label's own box or another label, so no pixel value is asserted.

**[asserted]** `a wrapped label drops the lines that do not fit`. A wrapped
label of fixed height draws only the lines that fit whole. The rest are not
drawn at all, `TextBounds` counts only the lines drawn, and `TextFits` is
false. Auto-sized to the same width, every line is drawn.

**[asserted]** `LineHeight 2 leaves one wrapped line where two fitted`.
LineHeight changes how many lines fit, and the same rule then drops the rest.

**[asserted]** `TextTruncate shortens the bounds and keeps the content`. The
drawn prefix and ellipsis fit inside the box and `TextBounds` measures them;
`TextFits` is false; `ContentText` is the whole string.

**[asserted]** `ContentText strips RichText markup`. With RichText on, the
markup is removed; with it off, the string is kept as written.

### What is still unspecified

## 8. What reaches the display list

An element solved to zero width or height produces nothing to paint and is
**absent** from the display list, rather than present with an empty rectangle.

**[verified]** `a node with zero area is absent from the display list`.

This is a rule of the display list rather than of layout: the node exists, was
measured, and has a place in the tree. Any implementation must drop it at the
same point, or a consumer diffing two frames sees nodes appear and disappear for
reasons the tree does not explain.

## 9. Content and image resolution

What a host must accept versus what it may gate.

- **A conformant host MUST accept `rbxassetid://`** as a well-formed `Content`
  URI. Both `Content.fromUri("rbxassetid://<id>")` and the legacy string form
  `Image = "rbxassetid://<id>"` must assign without error.
- **Resolution is host-defined.** How a host turns that URI into pixels is not
  dictated by the standard: Roblox resolves it natively through its own client
  content pipeline, while off-engine hosts may resolve by fetch-and-cache, map
  to a local asset store, or decline resolution.
- **A host MAY require a permission or grant** before resolving a remote
  scheme. Network access to third-party endpoints is a capability, and gating
  it behind an explicit mod grant does not violate conformance.
- **A host MAY accept additional schemes.** Local schemes (such as `mod://` for
  assets co-located with an application) and platform-specific registries (such
  as `dewassetid://` or generic URLs) may be provided.
- **An unresolvable `Content` is a rendering outcome, not a property error.**
  When an asset URI cannot be resolved -- whether because the scheme is
  unsupported, a network grant was withheld, the host is offline, or the file
  is missing -- the property assignment succeeds, the property retains its
  assigned value upon readback, and the host indicates why nothing was drawn
  (reporting the reason and drawing an unresolvable or missing indicator).

The last rule preserves application portability: a Roblox application moved to
an off-engine host where a remote asset grant is withheld remains a correct
application missing an image, rather than a broken application that fails at
runtime.

## 10. UIGridLayout

Children take fixed cells in order, filling along `FillDirection` and starting at
`StartCorner`. Every claim below is **[verified]** against Roblox
**0.741.19.7411056**.

Defaults, read from a fresh instance in the command bar: `CellSize`
`{0, 100}, {0, 100}`, `CellPadding` `{0, 5}, {0, 5}`, `FillDirection`
`Horizontal` (the list's is `Vertical`), `FillDirectionMaxCells` 0, `StartCorner`
`TopLeft`, `SortOrder` `Name`.
**[verified]** `UIGridLayout defaults to 100 pixel cells, 5 pixel padding,
filling across`, which reads back `AbsoluteCellSize` 100 by 100,
`AbsoluteCellCount` 2 by 2 and `AbsoluteContentSize` 205 by 205.
**[verified]** `UIGridLayout with SortOrder unset orders cells by Name`.
**[verified]** `UIGridLayout FillDirection Vertical fills down before across`.
**[verified]** `UIGridLayout FillDirectionMaxCells caps a row before the width
does`, which reads back `AbsoluteCellSize` 50 by 50, `AbsoluteCellCount` 2 by 3
and `AbsoluteContentSize` 105 by 160.

Scale in `CellSize` and in `CellPadding` both resolve against the content box
inside any `UIPadding`: a 0.1 `CellPadding` in a 200 content box is a gap of 20.
**[verified]** `UIGridLayout CellSize scale resolves against the padded content
box`, `UIGridLayout CellPadding scale resolves against the parent's size`.

Alignment moves the grid as one block, not each row.
**[verified]** `UIGridLayout alignment moves the grid as a block, not each row`.

`StartCorner` is a corner of that block, not of the panel. Three 100 cells in a
220 panel aligned `Left` and `Top` fill a 205 by 205 block at the top left:
`TopRight` puts A at (105, 0) and B at (0, 0), `BottomLeft` puts A at (0, 105)
and C at (0, 0), and `BottomRight` puts A at (105, 105), B at (0, 105) and C at
(105, 0).
**[verified]** `UIGridLayout StartCorner TopLeft`, `... TopRight`, `...
BottomLeft`, `... BottomRight`.

A child that a `UISizeConstraint` or `UIAspectRatioConstraint` makes smaller than
its cell is centred in the cell, and the next cell does not move: `MaxSize` 60 by
60 in a 100 cell sits at (20, 20), and an aspect ratio of 2 gives 100 by 50 at
y 25.
**[verified]** `UIGridLayout lets a UISizeConstraint shrink a child within its
cell`, `UIGridLayout lets a UIAspectRatioConstraint reshape a child within its
cell`.

## 11. UISizeConstraint

`MinSize` and `MaxSize` clamp the size a child would otherwise take, including a
size a layout or a flex item assigns. Defaults, from the command bar: `MinSize`
0, 0 and `MaxSize` inf, inf. Every claim below is **[verified]** against Roblox
**0.741.19.7411056**.

Without a layout, a bound resizes the child at its own `Position`.
**[verified]** `UISizeConstraint MinSize grows a child past its Size`,
`UISizeConstraint MaxSize shrinks a child below its Size`.

A clamped list child advances the list by its clamped size.
**[verified]** `UISizeConstraint clamps a list child and the list advances by the
clamped size`.

Under flex, a child stops at its bound. A flexing sibling takes up what it left;
a sibling with no flex does not, so the space stays empty or the overflow stays.
**[verified]** `UISizeConstraint MaxSize on a Grow child hands the rest to its
Grow sibling` (A stops at 60, B grows to 140), `UISizeConstraint MinSize on a
Shrink child hands the rest to its Shrink sibling` (A held at 140, B shrinks to
60), `UIFlexItem Grow stops at a UISizeConstraint MaxSize`, `UIFlexItem Shrink
stops at a UISizeConstraint MinSize`.

## What this document does not yet cover

Each of these is a section someone will have to write, and none can be written
honestly without opening Studio first.

- `UIPageLayout`, `UITableLayout`.
- Sections 4, 10 and 11 beyond what their cases state. `VerticalFlex` has no
  case of its own; it is assumed to mirror `HorizontalFlex`.
- `UIAspectRatioConstraint` outside a grid. The `uiaspectratioconstraint_*` cases
  assert `AspectType`, `DominantAxis` and `AnchorPoint` behaviour, each with sizes
  that tell the candidate rules apart, and await a Studio pass.
- `UITextSizeConstraint`.
- Text wrapping and `TextScaled`; see section 7 for what is now covered and what
  is not.
- `ScrollingFrame` canvas resolution and `AutomaticCanvasSize`.
- `SizeConstraint`, which changes which parent axis a scale resolves against.

The property-level view of the same gap is generated into Dew's
`docs/datamodel_scope.md`, which tracks the in-scope properties still to
implement.
