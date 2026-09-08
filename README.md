# Aether

A headless UI framework for Luau. One component runs inside Roblox, on the
desktop, and in CI, because layout, hit testing, pointer arbitration, focus and
text editing are all resolved in Luau rather than by an engine.

A host binds that abstract geometry to something concrete and paints it.
`Host.detect()` selects by capability and never by configuration: the DataModel
host when the environment supplies a DataModel this framework can drive, and the
Luau test double otherwise.

## Running it

```sh
pesde install

lune run tests/run.luau                      # the suites
lune run tests/gates/all_gates.luau --run    # the structural gates
lune run conformance/run.luau                # against Roblox's own behaviour
```

Rendering off-engine needs a host that owns the process and embeds Luau as a
guest. That host is not in this repository (ADR-004) and is not published yet,
so the desktop path is not something a reader can run from here today;
`examples/counter/entry/desktop.luau` is the entry point such a host mounts.

## One component, three hosts

[`examples/counter`](examples/counter) is the whole claim in one directory:

```
src/Counter.luau            host-agnostic; asks Deps for create and source
entry/roblox.client.luau    mounts into a ScreenGui, the engine drives
entry/desktop.luau          installs the vocabulary, opens a Live.Session
```

Both entry points are under twenty lines. That ratio is the point.

| Host | What stands in for the engine |
| :--- | :--- |
| Roblox | the engine itself |
| Headless | mock instances over vide's own reactive core |
| Dew | `vello_cpu` or `vello_hybrid`, presenting to a window |

The off-engine hosts are Rust-owned: Rust holds the process and embeds Luau as a
guest. That Rust is THEIRS, not this repository's -- the rasteriser, the runtime
and the window layer live in Dew (ADR-004), and this package ships `src/**` and
nothing else. [docs/hosting_architecture.md](docs/hosting_architecture.md) has
why, and what an off-engine host is required to supply.

## Conformance

[`conformance/`](conformance) runs the same cases against this implementation and
against Roblox itself, so "matches the engine" is a measurement rather than a
claim. Each case records which of the two verified it, and the suite reports
being behind Roblox separately from being wrong.

## Layout

```
src/            the framework; src/Icon is a workspace member
packages/       workspace members that are not the framework
conformance/    cases, and a runner for each implementation
tests/          suites, and the structural gates under tests/gates
```

**No Rust.** `hosts/` held a three-crate Cargo workspace -- raster, runtime and
window -- until ADR-004 measured what it was: Dew's rendering stack, in the
framework's repository, reaching no Luau consumer. It lives in Dew now, and
`tests/gates/verify_framework_boundaries.luau` fails on the commit that brings
any of it back.

## Status

**0.0.1, pre-alpha.** The API is not stable and nothing is published to a
registry. Consumers depend on this repository by commit:

```toml
[dependencies]
Aether = { repo = "project-aether-ui/aether", rev = "<full-sha>" }
```

pesde synthesises `0.0.0-<sha>` for a git source, so the commit is the identity
and the version above is a statement about maturity rather than a resolution key.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md), and
[docs/contributing/guidelines.md](docs/contributing/guidelines.md) for how work
is branched, written and landed.

## License

[MIT](LICENSE)
