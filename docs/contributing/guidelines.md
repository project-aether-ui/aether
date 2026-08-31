# Guidelines

How work is organised, written and landed here. Four documents, each answering a
different question.

## The guides

| | Answers |
| :--- | :--- |
| [branching.md](guides/branching.md) | Where does this work go, and how big should it be? |
| [writing.md](guides/writing.md) | How do I write the commit, the pull request, the release note, the README? |
| [merging.md](guides/merging.md) | How does this land on `main`? |

Read in that order the first time. After that they are reference.

## The short version

**One observable goal per branch**, and the prefix says which kind of work it is.
`bootstrap/` is the exception, being a milestone rather than a goal.

**The branch prefix decides how it merges.**
`bootstrap/` gets a merge commit; `feat/` and `fix/` are squashed. One line on
`main` per unit of work, so `git log --first-parent` reads as a list of what
landed.

**Write for the reader you actually have.**
A commit is read by someone running `git blame` in two years; a pull request by a
reviewer now; a release note by someone upgrading; a README by someone deciding
whether to stay. Most bad writing in all four is aimed at the wrong one.

**Plain ASCII everywhere.**
No em dashes, curly quotes, arrows or emoji, in commits, pull requests, releases
or documentation. A character you cannot type is one that gets pasted
inconsistently.

**`main` is always green.**
Every commit on it compiles, passes its checks, and runs.

## Conventions that live elsewhere

- The structural gates in [`tests/gates`](../../tests/gates) enforce invariants
  no review reliably catches. `all_gates.luau` says which and why.
- [`conformance/`](../../conformance) is where a change to layout is proven
  against Roblox rather than argued about.
