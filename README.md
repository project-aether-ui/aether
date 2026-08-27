# Aether

A headless UI framework for Luau. Layout, hit testing, pointer arbitration, focus
and text editing are resolved in Luau; a **host** binds that abstract geometry to a
concrete target and paints it.

```
Layer 2     Aether.Core        abstract behaviour, no Instance anywhere
Layer 2.5   Aether.Host.*      binds abstract geometry to a target
```

`Host.detect()` selects by ENVIRONMENT, never by configuration — the Roblox host
when `game` is an Instance, the headless host otherwise. There is no flag to force
the wrong one, because every bug in this area has been a path that silently took
the wrong branch.

## Targets

| Host | What stands in for the engine |
| :--- | :--- |
| Roblox | the engine itself |
| Headless | mock instances over vide's own reactive core |
| `hosts/raster` | `vello_hybrid` / `wgpu` presenting to a window, via a C ABI |

## Status

**0.0.1 — pre-alpha.** The API is not stable and nothing is published to a
registry. Consumers depend on this repository by git commit:

```toml
[dependencies]
Aether = { repo = "<owner>/aether", rev = "<full-sha>" }
```

pesde synthesises `0.0.0-<sha>` for a git source, so the commit is the identity and
the version above is a statement about maturity rather than a resolution key. A
`luau`- or `lune`-target consumer can depend on this `roblox`-target package: the
whole source tree is copied and the generated redirect is an ordinary Luau file, it
simply lands in `roblox_packages/` rather than `luau_packages/`.

## Layout

```
src/            the framework; src/Icon is a workspace member
packages/       workspace members that are not the framework (virtual)
hosts/          off-engine hosts — raster (Rust), zune (Luau)
tests/          suites, and the structural gates under tests/gates
stories/        visual cases
```

## Running things

```sh
pesde install
lune run tests/run.luau                      # suites
lune run tests/gates/all_gates.luau --run    # structural gates
```

## History

Aether was developed inside the `spektr/essentials` monorepo as
`pkgs/ui/framework/Aether` and graduated to its own repository once it had
consumers that did not belong there. See `docs/graduation_followups.md` for
what the split left unfinished.

## License

[MIT](LICENSE)
