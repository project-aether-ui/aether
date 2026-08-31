# DataModel Standard — conformance suite

A tree goes in. A display list comes out. Any implementation can be run against
it.

This exists because there are going to be at least three implementations of the
same standard — Roblox's native one, Dew's native one, and the Luau one — and the
only thing that keeps three implementations honest is a shared suite. Six
hand-rolled vide shims in this project's history drifted to three fidelity levels
because there was no such thing.

## A case is data, not code

```luau
return {
    name = "scale resolves against the parent's size",
    provenance = "reference",
    surface = { width = 200, height = 100 },
    tree = {
        class = "Frame",
        name = "Root",
        props = { Size = { "UDim2", 1, 0, 1, 0 } },
        children = { … },
    },
    expect = {
        { name = "Root", x = 0, y = 0, w = 200, h = 100 },
    },
}
```

Data rather than a builder function, so a runner in **any** language can consume
it. The Luau runner is here; a Rust one will read the same cases.

## Provenance is the most important field

| Value | Means | Worth |
| :--- | :--- | :--- |
| `roblox` | Observed in Studio and recorded | **Conformance.** This is what the standard says. |
| `asserted` | Believed to be Roblox's behaviour, not yet verified | **An open question.** Failing one is a question, not a failure. |
| `reference` | Recorded from the Luau implementation | **Regression only.** Says we have not changed, not that we are right. |
| `divergent` | Known to differ from Roblox, recorded anyway | A documented gap, with `note` explaining it |

`asserted` is the one that earns its place. A case can be written from knowledge
of Roblox before anyone has opened Studio, and when the implementation disagrees
the honest state is *neither* "the suite is failing" *nor* "the implementation is
fine" — it is an open question with a name. Counting those as failures leaves the
suite permanently red, which teaches everyone to stop reading it. Verify one and
it becomes `roblox`; from then on, failing is failing.

A suite that blurs these lies about what it proves. Most cases start as
`reference` — that is honest and still useful, because it pins behaviour while
the implementations multiply. Promoting one to `roblox` requires opening Studio,
and every promotion makes the standard more real.

**Never edit a `roblox` expectation to make an implementation pass.** That is the
one rule. If an implementation disagrees with a verified case, the implementation
is wrong, or the case needs re-verifying in Studio — not adjusting.

## Running

```sh
lune run conformance/run.luau            # every case
lune run conformance/run.luau layout     # cases whose name matches
```

Exit code is non-zero on any failure, so it can gate a commit.
