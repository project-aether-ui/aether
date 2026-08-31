# Branching

`main` is always green. Every commit on it compiles, passes its checks, and
produces a running program. Broken experiments and half-written APIs live on a
branch until they are neither.

## The prefix declares the intent

| Prefix | Format | For |
| :--- | :--- | :--- |
| `bootstrap/` | `bootstrap/<milestone>` | greenfield architectural scaffolding |
| `feat/` | `feat/<scope>-<description>` | one new capability |
| `fix/` | `fix/<scope>-<description>` | one defect |
| `refactor/` | `refactor/<scope>-<description>` | restructuring with no behaviour change |
| `spike/` | `spike/<topic>` | an experiment, usually never merged |

The prefix is not decoration. It says how many goals the branch contains, which
is what decides how it merges: see [merging.md](merging.md).

## Scope

**One observable goal per branch**, for everything except `bootstrap/`.

"Observable" means someone could describe what changed without reading the diff.
A branch that needs "and" to describe it is two branches.

**Aim for under three days and under 400 lines.**
Not a rule, a smell. A branch that outgrows both has usually absorbed work that
was not its goal, and the review it eventually gets will be worse for it.

`bootstrap/` is exempt because a milestone is several goals by definition. It
pays for that exemption by being rare.

## Carving finished work out of a long branch

Work often becomes ready before the branch it lives on does. Pull the finished
directory onto a fresh branch rather than waiting:

```sh
git checkout main
git checkout -b feat/luau-memory-limit
git checkout dev/workspace -- host/src/luau/
git commit -m "feat(luau): implement safe VM memory limits"
```

Then carry on where you were, and rebase once it lands. This is preferable to
cherry-picking when the work is a whole directory, and to waiting when it is
finished.

## Before opening a pull request

Collapse the transient commits, on the branch, while it is still yours. A commit
is transient when a later commit on the same branch fixed or replaced it, such
that the tree in between was never a state anyone would want.

[merging.md](merging.md) has the rest, including what to keep: a pivot, a dead
end that taught something, and a decision that was reversed for a reason are all
worth their place in history.

## What does not happen

**No direct pushes to `main`.**
Work reaches it through a pull request, so there is a place for the change to be
described and a boundary that can be reverted.

**No merge of a branch whose checks are red**, including a branch that is red for
a reason outside itself. Fix or document the reason first, because a
known-failing check trains everyone to ignore the check.
