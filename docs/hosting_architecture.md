# Hosting Architecture — one pipeline, two shells

## The inversion

The zune host put **Luau in charge of the process** and had it reach into native
code through `zune.ffi`. That was the right shape for an experiment — it needed no
Rust build step and it answered the only question that mattered at the time, which
was whether layout, arbitration, motion and text editing genuinely ran off-engine.
They do.

It is the wrong shape for anything that runs someone else's code. `zune.ffi` has
`dlopen`; a runtime that hands a guest `dlopen` has no security boundary, and no
amount of care above it creates one. **A capability model cannot be enforced from
inside the runtime it is meant to constrain.**

So both production hosts invert it:

```
EXPERIMENT (scrapped)          PRODUCTION
─────────────────────          ──────────────────────────
Luau owns the process          Rust owns the process
  └── FFI ──> native             └── embeds Luau (mlua)
                                       ^ guest, no FFI, no io, no os
```

The guest gets nothing by default. Every capability is a function the host
injects, which means the set of things a guest can do is a list in Rust that can
be read, tested, and differ per guest.

## Three consumers, one core

Aether itself does not know what is hosting it. `Host.detect()` picks by
environment, and the display list it emits — `Live.Frame` — has survived four
rasterisers without the framework changing a line. That is the seam everything
else hangs off.

```
                       ┌─────────────────────────┐
                       │   Aether (Luau, this    │
                       │   repo) — layout, hit    │
                       │   test, pointer, focus   │
                       └───────────┬──────────────┘
                                   │ Live.Frame
              ┌────────────────────┼────────────────────┐
              │                    │                    │
        ┌─────▼──────┐      ┌──────▼───────┐     ┌──────▼───────┐
        │  ROBLOX    │      │  aether CLI  │     │     DEW      │
        │            │      │              │     │              │
        │ the engine │      │ dev tool for │     │ desktop      │
        │ IS the host│      │ any Aether   │     │ applet       │
        │ no Rust at │      │ author       │     │ platform     │
        │ all        │      │              │     │              │
        └────────────┘      └──────┬───────┘     └──────┬───────┘
                                   │                    │
                                   └────────┬───────────┘
                                            │
                                  ┌─────────▼──────────┐
                                  │  SHARED RUST CORE  │
                                  │  Dew/crates/runtime│
                                  │  Dew/crates/raster │
                                  └────────────────────┘
```

**THE SHARED RUST CORE IS NOT IN THIS REPOSITORY, and this document described it
as if it were until ADR-004 said otherwise.** `hosts/raster`, `hosts/runtime` and
`hosts/window` lived here because the zune experiment and the CLI needed them,
and the layout was then read as the decision: adding an image node to the display
list looked like changing a public framework contract when it is a host editing
its own renderer. They are Dew's, they live in `Dew/crates/`, and everything
below about what the core does and how the two shells differ is unchanged by
where it sits.

A Roblox author downloads none of this. They depend on the Luau package and the
engine is their host — which is the whole point of `Host.detect()` and the reason
the Roblox branch must never learn about desktop concerns.

## What is shared, and what is not

The pipeline is shared. The shell is not.

| | the shared core | `aether` CLI | Dew |
| :-- | :-- | :-- | :-- |
| Luau VM + require resolution | ✅ | | |
| Mount Aether, solve, emit `Live.Frame` | ✅ | | |
| `Live.Frame` → `aether_raster` draw calls | ✅ | | |
| Window surface, input → `PointerRouter` | ✅ | | |
| Clock driving springs | ✅ | | |
| Capability injection *mechanism* | ✅ | | |
| Which capabilities are granted | | permissive | per-mod manifest |
| Headless snapshot / visual diff | | ✅ | |
| Story discovery, hot reload | | ✅ | |
| Multi-window, tray, global hotkeys | | | ✅ |
| Mod loader, per-mod VM isolation | | | ✅ |
| Sandbox enforcement | | | ✅ |

The split is drawn at **trust**, not at features. The CLI runs the author's own
code, the way `cargo run` does; Dew runs code fetched from strangers. That
difference is the only thing the shell decides, and it decides it by choosing
which capabilities to inject — not by using a different pipeline.

### The rule that keeps this honest

The shared core is **deny-by-default**, including for the CLI. The CLI grants
itself a permissive set explicitly rather than inheriting an unrestricted VM.
One code path, exercised by both, so the boundary Dew depends on is not a path
only Dew ever takes.

## Cost, and why the CLI stays small

`aether_raster` already gates `vello_hybrid`/`wgpu` behind an off-by-default `gpu`
feature, with the measurement recorded in its manifest. That structure is what
lets one crate serve both:

- **`aether snapshot` / CI** — `vello_cpu`, no GPU driver, no wgpu in the build.
- **`aether preview` / Dew** — `gpu`, swapchain to a real window.

A Roblox author running visual diffs in CI never compiles wgpu.

## What the zune host taught, and what was kept

Deleted from this repository — the monorepo copy remains as the record. What it
established survives as follows:

- **The `Live.Frame` contract holds off-engine.** Four painters consumed it
  unchanged. This is the reason the diagram above has one seam and not three.
- **Require semantics differ per runtime.** `Headless.luau` and `PureVocabulary.luau`
  carry comments naming what broke under zune versus lune. Those comments stay;
  they are why the headless host is portable rather than accidentally lune-shaped.
- **The Win32 message → `PointerRouter` mapping** (`WM_MOUSEMOVE`/`LBUTTON*`/
  `MOUSEWHEEL`/`CHAR`/`KEYDOWN`) is a solved problem to port, not to rediscover.
- **Text baseline and alignment** (`TextOrigin`) is one rule shared by every
  painter. It must not be duplicated per backend a second time.
- **`WindowedPainter` has no `Present(dc)` and no `Pixel()`** because a swapchain
  owns its own presentation. The Rust painter inherits that shape.
- **Two gates go dormant.** `verify_frame_checks` and `verify_headless_is_portable`
  drove the zune CLI. They return, repointed at `aether`, once that CLI exists —
  see `tests/gates/all_gates.luau`.
