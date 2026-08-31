# Aether

A headless UI framework for Luau. One component runs inside Roblox, on the
desktop, and in CI, because layout, hit testing, pointer arbitration, focus and
text editing are all resolved in Luau rather than by an engine.

A host binds that abstract geometry to something concrete and paints it.
`Host.detect()` picks one by environment and never by configuration: the Roblox
host when `game` is an Instance, the headless host otherwise.

## Running it

```sh
pesde install

lune run tests/run.luau                      # the suites
lune run tests/gates/all_gates.luau --run    # the structural gates
lune run conformance/run.luau                # against Roblox's own behaviour
```

[aether-cli](https://github.com/project-aether-ui/aether-cli) renders a component
with no engine underneath it, from its own repository:

```sh
aether snapshot examples/counter/entry/desktop.luau -o counter.png
aether preview  examples/counter/entry/desktop.luau
```

`snapshot` needs no display, so it runs in CI. `preview` opens a window.

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
| `hosts/raster` | `vello_hybrid` or `vello_cpu`, presenting to a window |

The off-engine hosts are Rust-owned: Rust holds the process and embeds Luau as a
guest. [docs/hosting_architecture.md](docs/hosting_architecture.md) has why, and
how the CLI and Dew share one pipeline.

## Conformance

[`conformance/`](conformance) runs the same cases against this implementation and
against Roblox itself, so "matches the engine" is a measurement rather than a
claim. Each case records which of the two verified it, and the suite reports
being behind Roblox separately from being wrong.

## Layout

```
src/            the framework; src/Icon is a workspace member
packages/       workspace members that are not the framework
hosts/          raster, runtime and window; the CLI is its own repository
conformance/    cases, and a runner for each implementation
tests/          suites, and the structural gates under tests/gates
```

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
