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

## 7. What reaches the display list

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
- Text measurement, which decides `AutomaticSize` on a `TextLabel` and is the
  largest single omission here.
- `ScrollingFrame` canvas resolution and `AutomaticCanvasSize`.
- `SizeConstraint`, which changes which parent axis a scale resolves against.

The property-level view of the same gap is generated into Dew's
`docs/datamodel_scope.md`, which counts 105 in-scope properties still to
implement.
