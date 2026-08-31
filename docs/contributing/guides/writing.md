# Writing commits, pull requests and releases

Three kinds of writing, three different readers. Almost every mistake in all
three comes from writing for the wrong one.

| | Reader | Asking |
| :--- | :--- | :--- |
| **Commit** | someone running `git blame` in two years | *why is this line like this?* |
| **Pull request** | a reviewer, now | *what am I looking at, and where should I look?* |
| **Release note** | someone upgrading | *what will I notice, and what must I do?* |
| **README** | someone who just arrived | *what is this, and is it for me?* |

A commit that reads like a release note is too vague to be useful in a blame. A
release note that reads like a commit is unreadable to anyone who does not know
the codebase.

## Plain ASCII

No em dashes, no curly quotes, no arrows, no ellipsis characters, no emoji. Use
a hyphen, a colon, or a new sentence.

The reason is not purity. It is that both a person typing into a terminal and an
agent generating text should be able to produce the house style without thinking
about it, and a character you cannot type is a character that gets pasted
inconsistently. Diagrams use `| - + < > v ^` for the same reason.

Emoji in a running program's output is fine. It is product, not prose.

---

## Commits

```
<type>(<scope>): <subject>

<what was wrong, or what was wanted>

<why this approach, and what it costs>
```

Type and scope follow the conventional-commit scopes, mapped to directories in
this repository. The subject is imperative and lowercase: "fix the layer
root", not "fixed" or "Fixes".

**The body's job is the WHY.**
The diff already says what changed and nobody needs it restated. What the diff
cannot say is what was wrong, what else was tried, and what this now costs.

A commit is self-contained. It cannot lean on a PR description, an issue, or a
conversation, because in two years the reader has `git show` and nothing else.

### What makes a body worth reading

**Say what was broken, concretely.**
"Pressables rendered correctly and responded to nothing" is worth ten times
"fixed input handling".

**A number beats an adjective.**
"54ms a frame, 18fps" survives. "Was slow" does not.

**Name what it does not fix.**
The reader's next question is always "so is it fine now?", and answering it here
saves them finding out the hard way.

**Record the wrong turn when it was instructive.**
"Removing `debug` on reputation broke vide, whose `flags.luau` calls `debug.info`
on its first line" is the sentence that stops it happening again.

**Name a commit, do not cite its hash.**
A bare SHA in prose is opaque: "the cause is in ee149c7" makes a reader run
`git show` to learn what any sentence could have said directly. It is also
fragile, since any history rewrite turns it into a dangling reference, and worse
across repositories where it cannot be resolved at all.

Write what the other commit did. "The layer-root fix is upstream" survives a
rebase and needs no lookup.

The exception is a trailer, where the format carries the subject alongside the
hash and a tool reads it:

```
Fixes: 1234567890ab ("the subject line")
```

Skip the body when there genuinely is not one. `chore(assets): update the tray
icon` is complete.

---

## Pull requests

```
<one paragraph: what this is and why it exists>

## What changed
## What to look at
## Not done
```

**The opening paragraph is the whole PR to most readers.**
Write it as though it is the only part that gets read, because it usually is.

**What changed** is grouped by area rather than being a commit list, since the
commits are one click away.

**What to look at** is the section reviewers want and almost nobody writes.
Point at the two or three places where a mistake would be expensive, or where
the reasoning is not obvious. This is the difference between a review and a
skim.

**Not done** is not an apology. It sets the boundary of the claim, so a reviewer
does not report a known gap as a finding and a user does not meet it as a
surprise.

Do not describe the review process, the number of commits, or how long it took.

### Run-in headings

A section is usually a short series of entries, each opening with a bolded
run-in heading. Three shapes, chosen by what follows:

**A full stop, then a new line.**
When the description runs to a sentence or more, break the line after the
heading. The section then reads as a series of distinct entries rather than one
wall, and a reader skimming the bold text alone gets the shape of the change.

**One line**, when the heading is short and what follows is a fragment.

**A colon and a list**, when what follows is enumerable:

- Use an unordered list when the items are peers.
- Use an ordered list when sequence or precedence matters.
- Keep items to one line each. An item wanting a paragraph is an entry of its
  own.

Do not mix shapes inside one section. Pick the one that fits the content and
stay with it.

---

## Release notes

```
## <version> - <date>

<one line: what this release is for>

### Added / Changed / Fixed
### Breaking, with migration
```

Structure follows [Keep a Changelog](https://keepachangelog.com). The sections
are conventional so a reader can go straight to the one they came for.

**Written for someone who does not read this codebase.**
Name the feature, not the module. "Widgets can float transparently on the
desktop", not "added `Surface::Overlay`".

**Every breaking change carries its migration inline.**
A breaking change without the fix beside it is a bug report addressed to your
users. [rbx-dom](https://github.com/rojo-rbx/rbx-dom) is the reference here: its
3.0.0 entry puts a paragraph on what to do before the list of what broke,
including the fact that most callers need do nothing.

**One line per change, and a paragraph only when one is owed.**
A change nobody has to act on gets a line. A change that alters behaviour people
depend on gets as much prose as it takes.

---

## READMEs and repository descriptions

The reader has been here for four seconds and is deciding whether to leave.

```
# Name

<one or two sentences: what it is, plainly>

## Running it
## <the two or three things a reader needs next>
## License
```

**Say what it is, not what it enables.**
"A desktop applet platform. Widgets are written in Luau and run on Aether" tells
someone what they are looking at. "Enables fast, lightweight workflow utilities
authored as typed Luau modules" is the same sentence with the information taken
out. If a phrase would fit any project in the category, it is not doing work.

**No second introduction.**
A tagline followed by an "Overview" that restates it is the most common README
failure. Say it once, then move to something the reader cannot infer.

**Running it comes early.**
Before architecture, before philosophy. The reader wants to know whether they can
try it.

**Architecture only where it earns the space.**
A diagram is worth including when the shape is the point and prose would take a
paragraph. It is not worth including as decoration, and it should never come
before the reader knows what the project is.

**No decorative horizontal rules.**
Headings already separate sections. A `---` between every one is visual noise
that makes a short document look long.

**No emoji in the title.**

### Repository descriptions

One sentence, under about 100 characters, in the same voice as the README's first
line. It appears in search results and next to the name in a list, so it should
read as a definition rather than a slogan:

```
A headless UI framework for Luau. One component runs in Roblox, on the desktop, and in CI.
```

Not a tagline, not a promise, and no em dash.

---

## The rule underneath all of them

Write the thing you would want to find. Every one of these is read by someone
under time pressure trying to answer a specific question, and the writing is
good exactly when it answers that question and stops.
