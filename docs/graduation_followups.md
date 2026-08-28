# Aether Graduation — Open Follow-ups

State at the end of the extraction. Everything here is known and deliberate; none
of it is a surprise waiting to be found.

---

## 1. The monorepo cannot be reached by git dependency yet — BLOCKING

The whole cross-repo plan rests on `{ repo, rev, path }` git dependencies. The
mechanism is verified working. The monorepo is not reachable through it:

1. **`SpektrLabs/rbx-essentials` is private.** An unauthenticated fetch returns
   404, and pesde reports that as `no entry found at path pkgs/testkit/core` —
   which reads like a missing directory and is not one.
2. **It is 254 commits ahead of its own `origin/main`.** Even with auth,
   `rev = "main"` resolves to a tree where this framework is still called CoreUI:
   `pkgs/ui/framework/Aether` does not exist on the remote at all.

Until the monorepo is pushed, no consumer — this repo, Dew, or the monorepo
itself — can pin anything by commit.

**Verified working**, so the plan is sound once the above is fixed:

- `{ repo = "owner/name", rev = "main" }` resolves and records the concrete
  `tree_id` in `pesde.lock`.
- `{ repo, rev, path = "sub/dir" }` resolves a subdirectory manifest.
- A `luau`-target consumer CAN depend on a `roblox`-target git package; the
  redirect lands in `roblox_packages/` and is an ordinary Luau file.

**Verified NOT working**, so do not plan around it:

- A subdirectory manifest whose `lib` reaches upward (`../../src`) — pesde copies
  only that subdirectory, so the path is not there. **Two targets from one source
  tree is not expressible.** One manifest, one target.

---

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
