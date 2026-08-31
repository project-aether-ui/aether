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

## 7. Does the scale rule generalise to scale 1? — OPEN

`automatic_size_full_scale_child` is `asserted`, not verified.

The rule that a scale-sized child resolves against the space available to its
parent is verified twice, but both cases use a PARTIAL scale (`0.5`). Applied to
`fromScale(1, 1)` it means an AutomaticSize.X frame whose only child is a full
scale face measures to the whole space on offer — so Aether's `Button` fills its
container rather than hugging its label, on Roblox as much as anywhere.

An engine could reasonably treat "all of this axis" as the degenerate case of the
cycle rather than a partial constraint on it, and answer 90. The implementation
follows the verified rule because that is the conservative choice, and the case
exists so a Studio pass settles it rather than a user noticing that every
automatically sized button is full width.

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
