# Changelog

## 0.0.1 — unreleased

The first version of Aether as a standalone repository.

### Graduated from `spektr/essentials`

- Extracted `pkgs/ui/framework/Aether` to the repository root, with `src/Icon`,
  `pkgs/core/virtual` (as `packages/virtual`) and the off-engine hosts.
- **Version reset to `0.0.1`.** Aether left the monorepo at `0.1.0-alpha.5`, a
  number inherited from a workspace-wide lockstep bump rather than earned. `0.1.0`
  means "walking skeleton" in this project's own tier table and the framework has
  not shipped that.
- **Versioning is now independent.** The monorepo's lockstep policy justified
  itself on the premise that "there are no external consumers to break". That
  premise expired. Consumers pin by commit.
- Carried 11 of the monorepo's structural gates; left behind `verify_package_tiers`,
  `verify_lockstep`, `verify_package_resolution`, `verify_53d8` and `verify_43`,
  each of which asserts something about the monorepo's shape. Reasons are recorded
  in `tests/gates/all_gates.luau`.

### Fixed

- `verify_require_paths` counted one `.Parent` hop too many for any module directly
  under a root-level `src/`. Its strip pattern required a separator before `src`,
  which no longer holds now that the framework's source is `src/` at the repository
  root. It reported two source defects and was one wrong pattern.

### Removed

- **The Rust workspace — `hosts/raster`, `hosts/runtime`, `hosts/window`,
  `Cargo.toml` and `Cargo.lock` — moved to Dew** (`Dew/crates/`), per ADR-004.
  Measured before it moved: `pesde.toml` ships `src/**`, so no Rust here ever
  reached a Luau consumer, and the three crates had exactly two dependents — Dew
  and aether-cli, both hosts, one of them retiring. They were Dew's rendering
  stack living in the framework's repository, left from when the zune experiment
  and the CLI needed them, and the layout was being read as the decision: adding
  an image node to the display list looked like changing a public framework
  contract when it is a host editing its own renderer.

  **Nothing a consumer installs changes.** `includes` was already `src/**`.
  aether-cli keeps its pin at `a01a034` and is untouched; it is frozen by ADR-002
  until it is archived.

  The `rust` and `fmt` CI jobs went with them, and
  `tests/gates/verify_framework_boundaries.luau` now allows no Rust at all: a
  stray `.rs` or a new `Cargo.toml` anywhere in this tree fails the gate on the
  commit that adds it. Its allowlist is down from 4 entries to 1 —
  `src/host/Headless.luau`, which archives to `OSS/luau-datamodel/` under ADR-002.
- **The zune host.** It put Luau in charge of the process and reached native code
  through `zune.ffi`, which cannot be sandboxed: a runtime that hands a guest
  `dlopen` has no security boundary, and nothing above it can create one. Both
  production hosts invert it — Rust owns the process and embeds Luau as a guest.
  What the experiment established is recorded in `docs/hosting_architecture.md`;
  the monorepo copy remains as the reference for the port.
- `verify_frame_checks` and `verify_headless_is_portable`, which drove the zune
  CLI. Both return, repointed at the `aether` CLI, once it exists. Deleted rather
  than left red, because a permanently failing gate teaches everyone to ignore the
  gate report.

### Added

- `docs/hosting_architecture.md` — the shared-pipeline decision: one Rust core
  (`hosts/runtime` + `hosts/raster`) under both the `aether` CLI and Dew, split at
  trust rather than at features, with a Roblox author depending on neither.

### Added (painting)

- `aether_raster::Canvas` — a safe Rust surface over the C ABI, wrapping it
  rather than replacing it while the poison gates still fire through those
  functions.
- `aether_runtime::RasterPainter`, behind the `raster` feature — a CPU painter
  over `Canvas`, and the first implementation of `Painter`.
- `Painter::fill_gradient`. The trait had none, so every gradient in a frame was
  dropped on the way to the surface. The default falls back to the flat fill.
- `tests/render.rs` — pixel assertions, plus a PNG written to
  `hosts/runtime/target/aether_frame.png` to look at.

### Fixed (painting)

- The painter added a font ascent on top of `ar_fill_text`, which already
  converts a top-left to a baseline internally. Every run landed about a line
  low. The ABI's own comment warns against exactly this.

### Added (the shared example)

- `examples/counter/` — one component, two entry points, and a Rojo project.
  `src/Counter.luau` is host-agnostic; `entry/roblox.client.luau` and
  `entry/desktop.luau` are the only files that differ.
- `aether_runtime::Driver` — the frame loop both native shells run.
- `aether_runtime::font` — system face resolution, with no rasteriser dependency.
- `Application::get`, so an entry can expose a size or a transition alongside its
  `Session`.

### Learned (written into the example)

- A shared component may NAME the value vocabulary but must not EVALUATE it at
  module scope: a module body runs at require time, and off-engine the host
  installs `UDim2`/`Color3` during startup. This works on Roblox and fails
  everywhere else, which is the worst way for it to fail.

### Added (the shells)

- `aether_window` — a Win32 window, message pump and BGRA blit, knowing nothing
  about Aether or Luau. Shared by the CLI's preview and, later, by Dew.
  Deliberately opaque: transparency needs DirectComposition and becomes another
  surface beside this one, not a rewrite of it.
- `aether-cli`, binary `aether` — `snapshot` renders a component to a PNG with no
  display; `preview` opens a window and runs the same `Driver` loop Dew will.
- A Cargo workspace. Four independent `target/` directories were compiling the
  same dependency trees separately and filled the disk.

### Fixed

- The window title was built from a `Vec` dropped before `CreateWindowExW` read
  it — a window created from freed memory.
- `aether --help` was parsed as a command needing an entry module, so it reported
  an error the user had not made before printing the usage.

### Changed (require by string)

- Every require in the package is a string path. Removed `script.Parent` and
  Instance walks entirely, along with `loadSubmodule`, `loadSibling`, and the
  pcall cascades that guessed at two to four candidate paths — several of which
  pointed into the monorepo layout this package has left.
- `Deps` keeps ONE environment branch, and it is about the artefact rather than
  the path: `roblox_packages/vide` is a redirect pesde generates that reaches its
  target through the Instance tree, so it resolves in the engine and nowhere
  else. It now tests `typeof(game)` — the actual question — rather than
  `typeof(script)`.
- `Text.luau` takes `create` from `Deps` instead of searching for vide itself.

### Added

- The reactive surface — `create`, `source`, `derive`, `effect`, `cleanup` — and
  `Vocabulary` are exported from the root. They lived only in `Deps`, so an
  author reached for the two things they build with through a module whose name
  says "internal dependency resolution".

### Changed

- The public table moved to `src/api.luau`; `init.luau` forwards to it. The root
  was unreachable by a string alias: pointing one at `src` loads `init.luau` but
  keeps `src` as its identity, so every `./x` inside resolved one level too high,
  and `@aether/init` never resolves because a require ending in `init` skips the
  extension search that would find it. `@aether/api` has neither problem, and
  Roblox's folder require still lands on `init`.
