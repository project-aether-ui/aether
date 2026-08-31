# Merging

One line on `main` per unit of work. Every rule here follows from that.

`git log --first-parent main` should read as a list of what landed, at the
granularity someone would actually want. That view is the source for release
notes, and it only stays useful if each merge contributes one entry.

## The branch prefix picks the strategy

| Prefix | Defined as | Merge as |
| :--- | :--- | :--- |
| `bootstrap/` | greenfield architectural scaffolding | merge commit |
| `feat/` | one observable goal, 48h and 400 lines | squash |
| `fix/` | defect repair | squash |
| `spike/` | R&D experiment | usually not merged at all |

The taxonomy in [branching.md](branching.md) already encodes the decision,
because it already declares how many goals a branch contains.

**A `feat/` or `fix/` branch has one observable goal.**
One goal collapses to one commit without losing anything. Its internal history is
"implement, rename, fix, add test", which is transient by construction: no commit
in the middle was a state anyone would want to return to.

**A `bootstrap/` branch is a milestone.**
Several goals, several commits worth keeping, and a boundary worth being able to
revert as a unit. `git revert -m 1 <merge>` undoes the whole thing in one step,
which is only possible if the merge commit exists.

## What squashing costs

Squash-merge keeps one commit message and discards the rest, including every
`Co-Authored-By` trailer on the commits it absorbs.

In this repository the commit body is where the reasoning lives, so the check
before squashing is not the line count. It is: **do these bodies say anything
worth finding in two years?** If three of five commits explain a real finding,
that branch wants a merge commit whatever its prefix says.

## Version is a proxy, not a rule

"Merge commits before 0.1.0, squash after" gives the right answer nearly always,
because the mix of branches changes: bootstrap work dominates before a release
and feature work after it.

It breaks in the two cases that matter:

- A `bootstrap/` branch after 1.0, meaning a second architectural pivot, still
  wants a merge commit.
- A single-commit `fix/` before 0.1.0 does not need one.

Judge the branch, not the version.

## On GitHub

| Button | Use for |
| :--- | :--- |
| Create a merge commit | `bootstrap/`, and any branch whose bodies are worth keeping |
| Squash and merge | `feat/`, `fix/` |
| Rebase and merge | a branch whose commits are each independent and each worth keeping separately, with no grouping worth recording |

GitHub offers no fast-forward. That is fine: a fast-forward records nothing about
where the branch began or ended, which is the one thing this document is trying
to preserve.

## Before the merge button

Collapse the transient commits first, on the branch, while it is still yours.

A commit is transient when a later commit on the same branch fixed, replaced or
undid it, such that the tree in between was never a state anyone would want. Fold
those into the commit they correct. Keep the rest, including anything that
documents a pivot, a dead end that taught something, or a decision that was
reversed for a reason.

The result should be that every commit reaching `main` was, at the moment it was
written, true.
