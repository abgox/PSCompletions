# Conventions

Why a commit subject is a plain sentence with two reserved prefixes, and why the changelog groups
the way it does. The rules themselves are in `AGENTS.md` §Commit and changelog subjects.

## The two prefixes are kept for different reasons

`completions:` is a **label** — nothing reads it. It survives on volume: the completion library is
the largest single category of change here and grows without bound. Up to `release: 8.0.1` it was
the most-used prefix, with the engine-side prefixes together a fraction of it, and the library only
gets bigger. A reader scanning the engine's history needs to filter the library *out*, not to find
it — the library already has an index of its own, generated into the `index` branch.

`release` is a **switch** — `.github/workflows/ci.yml` reads it and runs `build-binaries` and
`publish-module`. It stays a bare prefix because nothing else in a release commit needs grouping:
the version bump carries `module/version.json` and both changelogs, and that is the whole of it.

The asymmetry is the point. A reserved prefix has to be paid for — by volume, or by a machine that
reads it.

## Rejected: a closed scope vocabulary on commits

The first version of this rule gave every commit a scope from a closed table — `cli`, `engine`,
`menu`, `net`, `templates`, `hooks`, `bridge`, `module`, and so on — each mapped to a directory.

It was rejected after counting what it produced. The table's entries drifted the moment they
existed: `scripts` against `script`, `workflows` against `workflow`, `README` against `docs`, plus
one-off words (`tpl`, `render`, `style`, `PSCompletions`) used exactly once. None of those words
carry information a reader wants; they exist only to satisfy the requirement that a scope be
chosen. Removing the requirement removes the drift.

It also forced a scope onto changes that have no area at all: a `.gitattributes` edit had to be
dressed up as `chore(git):`, because no row covered repo-level files. A plain sentence says it
directly.

What replaces it: the subject names the area in words whenever the area is not obvious, which is
what a sentence does naturally and what `git log --grep` can still find.

## Rejected: grouping the changelog by our modules

The changelog keeps grouping, but not by our layering. An engine-internal change that a user feels
through the menu is `menu:`, not `engine:` — the user's mental model is what survives a refactor,
and our module boundaries do not. `net.rs` and `tpl.rs` have no group for the same reason.

Grouping by what ships also settles the two online things. The completion library and `install.sh`
are fetched live, so no version can describe them and neither appears in the changelog; how to
install lives in the README, where a user actually looks.

## The body is not hard-wrapped

A body bullet is one complete sentence on one line, however long that line runs. Fixed-column
wrapping at 72 or 80 was a transport convention — `git format-patch` and an 80-column terminal —
not a content one, and it costs more than it buys here:

- a wrapped bullet is no longer a line, so the structure of the body is invisible in `git log` and
  `grep '^- '` stops working
- editing one word re-wraps the whole paragraph
- copied text arrives with stray line breaks
- GitHub, where a body is actually read, wraps visually anyway

Nothing in this repository reads a body. The only machine check is the `release` prefix on the
*subject*, so the body answers to a human reader and nothing else. If a bullet grows long, split it
into two bullets — do not wrap it.

## Capitalization and mood follow the standards

The two surfaces differ in capitalization because the standards that govern them differ, not because
of any preference here. A commit subject follows Angular's commit guidelines — what Conventional
Commits is built on — which require the summary to be imperative, not capitalized, and free of a
trailing period; the practical test is that it completes "This commit will …". A changelog follows
Keep a Changelog, whose sections and entries are capitalized, whose section names are past
participles (`Added`, `Fixed`), and whose guiding principle is that a changelog is for humans, not
machines.

## Overturn condition

- If the completion library stops being the dominant category, or stops being one directory, the
  `completions:` label loses what it is paid for and goes.
- If no workflow reads `release` any more, it becomes a third prefix with nothing behind it, and
  the honest form is a plain sentence again.
- If a changelog entry ever needs a group outside the six, that is a signal the user-facing surface
  changed — not that the list was too short.
- If anything ever parses a commit body, the one-sentence-per-line format has to be revisited. That
  format is safe precisely because no tool reads a body.
