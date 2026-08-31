# Contributing

Start with [docs/contributing/guidelines.md](docs/contributing/guidelines.md).
It is the index, and it carries the short version of everything below it.

Three things worth knowing before the first pull request:

- **One observable goal per branch**, and the prefix says which kind of work it
  is. A branch that needs "and" to describe it is two branches.
- **`main` is always green.** Every commit on it compiles, passes its checks, and
  runs.
- **Plain ASCII**, in commits, pull requests and documentation alike.

A change to layout is proven in [`conformance/`](conformance) rather than argued
about. A case verified against Roblox is the standard; one recorded from this
implementation is a regression test, and the suite keeps them apart.
