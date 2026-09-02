# Aether Graduation — Open Follow-ups

State at the end of the extraction. Everything here is known and deliberate; none
of it is a surprise waiting to be found.

---

## 1. The remote — RESOLVED for Aether, still open for the monorepo

Aether lives at **github.com/project-aether-ui/aether**, in its own organisation
rather than under `SpektrLabs`. That org is Roblox-focused, and this framework's
whole claim is that it is not.

Dew pins it by commit and builds. Both halves come from the one revision: the
Rust crates through Cargo, and the Luau source through
`aether_runtime::luau_source_root()`, which reports the checkout Cargo already
made — so there is no second, unpinned dependency on the same thing.

TWO THINGS THAT HAD TO BE TRUE FIRST, and both are worth remembering:

  * **Commits carried a private email.** GitHub refused the push outright. The
    history was rewritten onto the noreply address — which had to happen BEFORE
    anything pinned a revision, because it changed every SHA.
  * **A pinned checkout has the framework and none of its dependencies.**
    `roblox_packages/` is generated, so vide is not in the repository. VideCore
    now takes `@vide` as its first candidate and a host supplies it; see
    `Capabilities.aliases` for why a `.luaurc` cannot.

STILL OPEN: `SpektrLabs/rbx-essentials` is private AND far ahead of its own
origin/main, so testkit still cannot be reached by commit — see §2.

**Verified working**, and worth not re-deriving:

- `{ repo = "owner/name", rev = "..." }` resolves and records the concrete
  `tree_id` in `pesde.lock`.
- `{ repo, rev, path = "sub/dir" }` resolves a subdirectory manifest.
- A `luau`-target consumer CAN depend on a `roblox`-target git package.

**Verified NOT working**, so do not plan around it:

- A subdirectory manifest whose `lib` reaches upward (`../../src`) — pesde copies
  only that subdirectory. **Two targets from one source tree is not
  expressible.** One manifest, one target.
- A `file://` pin. It looks like pinning and is not: the revision exists on one
  machine, so a lockfile built from it is unusable to anyone else.

## 2. testkit is wired by `.luaurc` alias, not by manifest — RESOLVED

Resolved by not depending on testkit at all.

`.luaurc` aliased `@testkit` and `@testkit_env` into `./.testkit/...`, which
nothing populated. All thirty-three suites were therefore unrunnable from the day
Aether graduated, and nothing said so: a suite that cannot load produces no
failures, so their silence read as success for months.

Measured before replacing it, the entire surface those suites use is four
functions — `test` 171 times, `run` 33, `it` 11, `describe` 6 — with 815 plain
`assert()` calls doing the checking. That is a registry, not a framework, and
pinning a cross-repository dependency on a private monorepo to obtain it costs
more than the eighty lines in `tests/testkit.luau`. The call shapes are kept
exactly, so no suite changed to accommodate it.

`tests/run.luau` went the same way: 587 monorepo lines orchestrating tiers and
naming suites that do not exist here, replaced by a discoverer that runs one
process per `*.test.luau`.

What the silence had been hiding, once they ran:

- Nine suites required `"../../src"`, a DIRECTORY — which resolves `init.luau`
  but keeps the directory as the module's identity, so `init`'s own `"./api"`
  resolved one level too high. The same identity trap that made Aether's root
  unreachable from Dew.
- Two still pointed at `../../../framework/Aether/src`, and one at
  `../../../../motion/Flux/src/flux`. Flux did not graduate; that test now
  installs `host.spring` — vide's real spring, already driven by the simulated
  clock — through the `Motion` seam, which is what the seam is for.
- Three `LayoutAutomaticSize` cases asserted that measurement passes THROUGH a
  scale-sized child. Two Studio-verified conformance cases say it is measured
  against the space available to its parent. The suite had been asserting a third
  behaviour, matching neither the engine nor the implementation it was written
  against, for as long as it could not run. See §7.

`lune run tests/run.luau` is back in CI.

---

## 6. verify_test_inventory is blocked on LAYOUT, not testkit — OPEN

The blocker was recorded as "testkit is not reachable by commit". That is
resolved and was never the whole story. The gate requires testkit's `Discover`
from `pkgs/testkit/core/src`, and its first assertion is that
`tests/engine/prism` still scans for `.spec.luau` files. Neither the directory
nor the file convention exists in this repository.

What a test inventory should assert HERE is a different question with a different
answer: 33 `*.test.luau` suites discovered by `tests/run.luau`, no specs, no
engine mount. Left blocked with an accurate reason rather than rewritten to
assert something else while keeping the old name.

---

## 7. What decides whether a scale-sized child is measured? — ANSWERED

It does not, and the way this was gotten wrong is the part worth keeping.

The rule that a scale-sized child resolves against the space available to its
parent is verified twice, both times with a scale of 0.5. `LayoutAutomaticSize`
asserted something else for a full-scale child — that measurement passes THROUGH
it — and when the suite became runnable again those three assertions failed. They
were rewritten to match the implementation, on the reasoning that a suite which
had been inert for months could not outrank two Studio-verified cases.

Studio then answered the full-scale case: **90**. Pass-through. The suite had been
right the whole time, and the generalisation from 0.5 to 1 was the error.

`grow()` now takes the pass-through branch for a child whose scale on the
measured axis is `>= 1`, and the assertions are restored.

The lesson is not "trust the old tests". It is that a rule fitted to two points
does not extend to a third by argument, and that "the tests must be stale" is the
most comfortable available explanation for a failure — so it is the one that most
needs evidence behind it. The conformance case cost a few minutes and caught it.

### ANSWERED, and the discriminator was wrong

Both queued cases came back against the prediction, which is the outcome the
previous note called "green by luck". They were right to be queued.

| case | predicted | engine |
|---|---|---|
| `automatic_size_half_scale_child_with_content` | 120 | **80** |
| `automatic_size_scale_child_without_a_layout` | 120 | **30** |

The first is decisive: a HALF-scale child with content behind it is passed through
exactly as the full-scale one was. Scale magnitude was never the rule. It fitted
three cases because the only full-scale case was also the only one with content.

**The rule is a conjunction, and each half alone is demonstrably wrong.** A
scale-sized child is measured only if it has no content AND asks for less than the
whole axis:

- content behind it wins whenever there is any (90, and 80)
- no content, partial scale resolves against the offered space (120, and 60)
- no content, full scale resolves to nothing: `H = 1 x H + 0` holds for every `H`,
  so the element keeps its authored size and `Warnings()` reports the axis

Replacing `xs < 1` with the content test alone passed all of conformance and
immediately broke `testUnmeasurableAxisIsReported` in the suite — the third
configuration, which no conformance case covers. That test is the only reason the
over-correction was caught, which is a point in favour of keeping unit assertions
that conformance does not duplicate.

### The rule, as it now stands on eight readings

**With a UIListLayout**, a scale-sized child resolves against the space OFFERED to
the parent, and content behind it is ignored. Verified at three scales, which is
what makes it a rule rather than arithmetic that fits one number:

| | resolved | engine |
|---|---|---|
| `0.25` scale | `0.25 x 200 + 20` | 70 |
| `0.5` scale | `0.5 x 200 + 20` | 120 |
| `0.5` under an 80-tall grandparent | `0.5 x 80 + 20` | 60 |
| `0.5` **with 80 of content behind it** | `0.5 x 200 + 20` | **120** |

That last one answered against the prediction. `grow()` passed a child with content
through without consulting the layout at all, so the precedence was backwards. A
layout stacks the direct children and computes the content size itself, so a
descendant behind one of them never reaches the measurement -- "the layout wins"
and "content is ignored" are one statement, not two.

**Without a layout**, the child resolves against the content size counting OFFSETS
ONLY, then the parent takes the larger of the two:

| | C | `s x C + o` | max | engine |
|---|---|---|---|---|
| childless | 20 | 30 | **30** | 30 |
| 80 of content | 80 | 60 | **80** | 80 |
| full scale, 90 of content | 90 | 90 | **90** | 90 |
| full scale, childless | 0 | 0 | **0** | unmeasurable, warns |

### What is still open

One gap remains, and it is the childless no-layout row above. `grow()` resolves
against the offered space whenever there is no content, giving 120 where the engine
gives 30. Every case WITH content hides it, because the content dominates the max
and passing through reaches the same number by another route -- only the childless
case separates them.

Closing it means computing the offsets-only content size first, which is a second
pass over the subtree rather than another condition on the existing line. That is
the one piece of this still worth calling a rework; everything else turned out to
be precedence.

---

## 3. The zune host is gone — RESOLVED

Scrapped rather than repaired. It put Luau in charge of the process and reached
native code through `zune.ffi`, which is unsandboxable by construction: a runtime
that hands a guest `dlopen` has no security boundary. Both production hosts —
the `aether` CLI and Dew — invert it, with Rust owning the process and Luau
embedded as a guest.

That also dissolved the dangling `hosts/web/src/App` requires, which were the
symptom: `App.luau` is a demo scene pulling in kits and Flux, and it stays in the
monorepo along with the web host.

`verify_frame_checks` and `verify_headless_is_portable` drove the zune CLI and are
deleted with it. Both are worth having and both come back, repointed at `aether`
once that CLI exists. See `docs/hosting_architecture.md`.

## 4. `verify_test_inventory` still checks for an engine host

It asserts that `tests/engine/prism/init.luau` scans for `.spec.luau` files. There
is no engine tier in this repo. The engine-discovery branch needs removing or the
gate needs a "no engine tier" mode.

---

## Gate status at extraction

```
PASS  verify_cycles, verify_property_names, verify_use_before_declaration,
      verify_reactive_scopes, verify_autosize_cycles, verify_tests_not_shipped,
      verify_no_versioned_vendor_paths, verify_require_paths
FAIL  verify_test_inventory           (§2, §4)

(verify_frame_checks and verify_headless_is_portable were deleted with the zune
host -- see §3, and all_gates.luau for the terms of their return.)
```
