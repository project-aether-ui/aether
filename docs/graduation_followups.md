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

## 2. testkit is wired by `.luaurc` alias, not by manifest

`.luaurc` aliases `@testkit` and `@testkit_env` to `./.testkit/...`, which nothing
populates yet. `verify_test_inventory` still requires testkit by the monorepo's
old relative path and fails.

This mirrors how the monorepo does it — its root declares no testkit workspace
member either, which is why declaring testkit as a pesde path dependency fails
with `workspace package spektr/testkit_core luau not found in package`.

Resolve with §1: pin both by git, then point the aliases at the installed tree.

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
