# Aether Graduation — Open Follow-ups

State at the end of the extraction. Everything here is known and deliberate; none
of it is a surprise waiting to be found.

---

## 1. The remote — RESOLVED for Aether, still open for the monorepo

Aether lives at **github.com/project-aether-ui/aether**, in its own organisation
rather than under `SpektrLabs`. That org is Roblox-focused, and this framework's
whole claim is that it is not.

Dew pins it by commit and builds. That pin used to be a CARGO pin, and both
halves came from the one revision: the Rust crates through Cargo, and the Luau
source through `aether_runtime::luau_source_root()`, which reported the checkout
Cargo had already made.

**There are no longer two halves.** ADR-004 moved the three crates into Dew, so
the only thing Dew takes from here is Luau — and it takes it the way it takes
vide, as a pesde git dependency pinned by commit in `Dew/pesde.toml`. Same
property, one dependency instead of two: `installed_package("aether")` reports
the checkout pesde made. What the note below says about a pinned checkout
carrying the framework and none of its dependencies is unchanged and still the
reason `Capabilities.aliases` exists.

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

## 6. verify_test_inventory -- ANSWERED, and the answer was not the obvious one

The blocker was recorded as "testkit is not reachable by commit". That was
resolved and was never the whole story: the gate required testkit's `Discover`
from `pkgs/testkit/core/src`, and its first assertion was that
`tests/engine/prism` still scanned for `.spec.luau` files. Neither the directory
nor the file convention came across at graduation.

**The obvious rewrite is worthless, and that is the finding.** "Every
`*.test.luau` is found by the runner" cannot fail. `tests/run.luau` walks the
whole repository for exactly the patterns in `tests/suites.luau`, so every suite
outside `excluded` is discovered BY CONSTRUCTION. A gate asserting it would print
a green number identical to the one it prints with the runner switched off.
Reachability for that filename shape is closed by the runner, and a gate is the
wrong instrument for a closed question.

What is still open is narrower, and the gate now asks only that:

  1. **Naming drift.** `Foo.spec.luau`, `foo_test.luau`, `Foo.test.lua`. The
     engine tier's `.spec.luau` convention is gone; the muscle memory is not.
     Such a file matches no runner pattern and sits in the tree looking exactly
     like coverage. `tests/suites.luau` lists these shapes as `alsoTestShaped`.
  2. **A suite silenced by configuration.** `excluded` decides what the runner
     skips, so the census walks PAST it and reports anything of ours it hid.
     Silencing a suite is a decision and does not get to be a quiet one.
  3. **A suite that never reports.** A file the runner executes that never calls
     `T.run` exits 0 having asserted nothing, which is the ms-43 M30 failure
     exactly.

**Two things were found while writing it, both of the milestone's own class.**

`tests/suites.luau` claimed in its header to be the one home read by the runner
and the gate. The runner had stopped reading it and was scanning `.` directly, so
the claim had been false for as long as that was true -- the failure the file
exists to prevent, committed by the file that prevents it. The runner reads it
again, and the gate now CHECKS that it does, so the claim is enforced instead of
asserted in prose.

The old gate's own comment said non-vacuity was "enforced AT RUNTIME, by the
thing that runs the tests". That was true of the testkit it was inherited from
and not of `tests/testkit.luau`, where `run` on an empty registry printed
`0 passed` and returned 0 -- the same shape a green suite prints. `Testkit.run`
now exits non-zero when nothing registered.

**Each of the four checks was made to fail on purpose before the gate came out of
`BLOCKED`.** A gate that has never been seen to fail is not known to work, which
is the whole complaint against the one it replaces.

`M.BLOCKED` is now empty.

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

### CLOSED

`grow()` now sweeps twice when there is no layout: once counting offsets only to
find the content size, once resolving the scale children against it. Under a layout
the base is the offered box and a single sweep still answers it.

All twenty conformance cases are verified against the engine. The AutomaticSize
scale question that ran through this milestone is finished.

**What made it hard is worth keeping.** Four rules fitted the evidence in turn --
"skip scale children", "scale magnitude decides", "content decides", "content and
scale together" -- and each one fitted every case that existed when it was written.
The cases that ended it were not the ones confirming a rule but the ones built so a
wrong rule could not survive them: a childless scale child, a half-scale child with
content, a quarter scale under a layout. Each was written to split two readings that
agreed everywhere else, and each one moved the answer.

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

## 4. `verify_test_inventory` still checks for an engine host -- RESOLVED

Folded into §6. The engine-discovery branch is gone rather than given a "no
engine tier" mode: there is no engine tier to have a mode about, and a branch
kept for a host that does not exist is a branch nobody can test.

---

## Gate status

```
PASS  verify_cycles, verify_require_paths, verify_property_names,
      verify_use_before_declaration, verify_reactive_scopes,
      verify_autosize_cycles, verify_test_inventory, verify_tests_not_shipped,
      verify_no_versioned_vendor_paths

      9 of 9. M.BLOCKED is empty -- see §6 for what the last entry became.

(verify_frame_checks and verify_headless_is_portable were deleted with the zune
host -- see §3, and all_gates.luau for the terms of their return.)
```
