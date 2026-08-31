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
| **[unverified]** | Believed, and neither observed nor tested. Treat as a question. |
| **[verified-relationally]** | A case proves a ratio, a minimum or an integer multiple rather than a value, because the value is a property of the host. |

Cases were last run against Roblox **0.736.0.7361346**, and each records the
build that verified it. The property surface is generated from a reflection
database currently at **0.728**, so the standard's two halves are measured
against different builds. Neither is wrong; the skew is worth knowing before
someone reconciles two numbers that were never taken at the same time.

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

Order is `LayoutOrder`, then declaration order. The cursor advances by what each
child actually resolved to, so a stack of differently-sized rows lays out
correctly.

**[reference]** `SortOrder`, `HorizontalAlignment` and `VerticalAlignment` are
not implemented. They are in the backlog, not excluded.

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

Front-to-back order is `ZIndex`, then depth, then declaration order.

**[reference]** No case covers it. A case asserting order rather than geometry
would need the runner to compare sequences, which it does not yet do.

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

**[asserted]** `TextScaled chooses the text size from the box` -- the same string
in boxes of 1x and 2x height renders at 1x and 2x. An implementation ignoring
`TextScaled` honours `TextSize` in both and reports 1.0.

**Aether implements none of this.** `TextScaled` appears in one comment and is
read by nothing, so the case is gated behind `requires`.

**[unverified]** What happens when `TextScaled` and `AutomaticSize` are both set
on the same axis. Each wants the other to decide, which is the same shape as the
scale-under-AutomaticSize cycle in section 3 -- and that one turned out to have a
specific answer nobody guessed, so this one probably does too.

### What is still unspecified
- **Line height.** The headless provider uses `1.2 x TextSize`. Whether Roblox
  agrees is unverified, and it is exactly the kind of constant that is wrong by a
  few percent everywhere without anyone noticing.

## 8. What reaches the display list

An element solved to zero width or height produces nothing to paint and is
**absent** from the display list, rather than present with an empty rectangle.

**[verified]** `a node with zero area is absent from the display list`.

This is a rule of the display list rather than of layout: the node exists, was
measured, and has a place in the tree. Any implementation must drop it at the
same point, or a consumer diffing two frames sees nodes appear and disappear for
reasons the tree does not explain.

## What this document does not yet cover

Each of these is a section someone will have to write, and none can be written
honestly without opening Studio first.

- `UIGridLayout`, `UIPageLayout`, `UITableLayout`.
- The flex properties: `FlexMode`, `GrowRatio`, `ShrinkRatio`, `HorizontalFlex`,
  `VerticalFlex`, `ItemLineAlignment`.
- `UIAspectRatioConstraint`, `UISizeConstraint`, `UITextSizeConstraint`.
- Text wrapping and `TextScaled`; see section 7 for what is now covered and what
  is not.
- `ScrollingFrame` canvas resolution and `AutomaticCanvasSize`.
- `SizeConstraint`, which changes which parent axis a scale resolves against.

The property-level view of the same gap is generated into Dew's
`docs/datamodel_scope.md`, which counts 105 in-scope properties still to
implement.
