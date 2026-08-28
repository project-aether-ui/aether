# aether_runtime

The Rust-owned host runtime for Aether. Rust holds the process; Luau is a guest
inside it.

```
Aether (Luau)  --Live.Frame-->  aether_runtime  -->  impl Painter
     ^                                 |
     +------- Pointer / Key / Step ----+
```

Both off-engine shells build on this crate and differ only in which capabilities
they grant: the `aether` CLI runs the author's own code, Dew runs code fetched
from strangers. Neither gets a different pipeline, and neither gets a VM that
skips the sandbox.

There is no window, no swapchain, no `ffi` and no `libloading` here. Surfaces
belong to a shell; native drawing belongs behind `painter::Painter`. That is what
lets this crate be finished before the surface question is.

See [`docs/hosting_architecture.md`](../../docs/hosting_architecture.md).

## Tests

`tests/parity.rs` is the load-bearing one. It loads a real Aether application into
an embedded guest, drives a frame, and decodes the display list in Rust — with the
framework's source required unmodified, exactly as Roblox requires it. If it
passes, "the same application runs on both hosts" is a property of the build.

```sh
cargo test
```
