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

Everything below the ASCII rule is preference rather than policy. Nothing here is
enforced by a gate in this repository: it is how it reads when it reads well.

```
<type>(<scope>): <subject>

<what was wrong, or what was wanted>

<why this approach, and what it costs>
```

Type and scope follow the conventional-commit scopes, mapped to directories in
this repository. The subject is imperative and
lowercase: "fix the layer root", not "fixed" or "Fixes".

A subject that opens with an article or a quantifier is a statement rather than
an instruction, however true it is. "a surface is a permission" and "one pump for
the thread" both describe the result; say what applying the commit does.

Scope is required, except for `docs` and `chore`. Those routinely span the whole
repository, and `docs(docs)` is not information; a `feat` or a `fix` always
happened somewhere, so it always says where.

**The body's job is the WHY.**
The diff already says what changed and nobody needs it restated. What the diff
cannot say is what was wrong, what else was tried, and what this now costs.

A commit is self-contained. It cannot lean on a PR description, an issue, or a
conversation, because in two years the reader has `git show` and nothing else.

**Write the subject and stop.** That is the default, not a terse option. Most
commits need no body, and one added out of habit buries the few that matter.

Before writing a body, say what it tells a reader that the subject and the diff
do not. If the answer takes a moment to find, there is no body to write.

### Do not name the planning notes

`.artifacts/` is not published. A commit or a pull request that says "milestone 9
step B", "ADR-012" or "the sprint plan" names something the reader cannot open,
and it dates the moment the plan moves on.

Say what the work is FOR. Not "milestone 9 step B", but "an applet asks the host
for the surface it draws into". The theme stays true after the numbering has been
forgotten, and it is the part a reader needed anyway.

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

**Most commits do not need a body.**
The rules above say what a good body contains, not that every commit owes one.
A body is earned by a why the diff cannot show, and most changes do not have
one. The subject alone is the correct output more often than not.

Three short paragraphs is already a long body. Past that, a commit is usually
doing two things and wants to be two commits. A body that restates the diff,
narrates the process, or recaps numbers CI already prints is noise: it buries
the commits whose bodies do matter.

**Do not write `owner/repo#N`, and do not paste an issue or pull request URL.**
GitHub autolinks both in commit messages. Against a repository you do not own
that puts a permanent cross-reference on THEIR timeline, which cannot be
deleted, edited away, or undone by rewriting your own history. Write "centau/vide
pull request 89" instead. Source comments are fine; file contents do not
autolink.

This is the hash rule again: say the thing, do not link the thing.

### Authorship

Commits and pull requests are authored by the person landing them. No
`Co-Authored-By` trailer naming a tool, and no generated-by footer in a pull
request body.

The trailer means "a person to contact", which a tool is not. It also cannot be
removed later without rewriting published history, so the default is to leave it
out. A generated-by footer does worse than the trailer: it invites a reader to
judge the prose above it by the tool named under it.

This is the one worth being strict about. A trailer cannot be removed later
without rewriting published history, so it never goes in.

---

## Pull requests

**Most pull requests are a paragraph.** Say what was wrong, say what you did,
stop. If a list of changes helps, use a list. Nothing else is owed.

```
Window events had no idea which window they came from, which is fine with
one window and useless with two. Needed before an applet can ask for a
popover, since a tooltip creates and destroys a surface constantly.

- events are tagged with a surface id
- WM_DESTROY no longer posts WM_QUIT; the first window to close was
  killing the process
- poll moved off Window onto a Pump, since PeekMessage drains the whole
  thread anyway

Tests for both, checked they fail without the fix.
```

That is a complete pull request for a real change to the event loop. It is not
a summary of a longer one that was cut down.

### When sections earn their place

Add headings only when a reader has to navigate rather than read: several
independent areas in one branch, or a reviewer who was not in the work and needs
orienting. Two or three hundred words do not need signposting, and a heading over
a single paragraph is decoration.

When a pull request is genuinely large, these are the useful sections:

- **What changed**, grouped by area rather than listing commits.
- **What to look at**, naming the two or three places where a mistake would be
  expensive. Reviewers want this and almost nobody writes it.
- **Not done**, which sets the boundary of the claim so a known gap is not
  reported as a finding.

### Run-in headings

Inside a section that is already earning its place, an entry may open with a
bolded run-in heading. This is for a list of distinct items, not a default: when
every paragraph on a page opens in bold, the bold has stopped meaning anything
and the page reads as though it was generated rather than written.

Three shapes, chosen by what follows:

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
A headless UI framework for Luau. One component runs on the engine, on the desktop, and in CI.
```

Not a tagline, not a promise, and no em dash.

---

## The rule underneath all of them

Write the thing you would want to find. Every one of these is read by someone
under time pressure trying to answer a specific question, and the writing is
good exactly when it answers that question and stops.
