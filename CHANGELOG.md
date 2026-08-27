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
