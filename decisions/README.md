# Decisions

Why the rules read the way they do. One file per scope, split by subject so a future system-level
decision log does not have to share a file with authoring guidance.

| Doc | Scope |
| --- | --- |
| [`authoring.md`](authoring.md) | writing and maintaining completions — static manifests and `hooks.lua` |

## The three layers

| Layer | Home | Holds |
| --- | --- | --- |
| **Rules** | `AGENTS.md` | what an author follows every time. One to three sentences each, at most a one-line reason |
| **System** | `design/*.md` | how the system runs today. Present tense; history and migration records are deliberately excluded |
| **Reasons** | `decisions/*.md` (here) | the measurement behind a rule, the alternative that was rejected, and the condition under which it should be overturned |

A rule that only makes sense once you know *why* does not get longer in `AGENTS.md` — it gets one
line there and a section here. That is the whole point of the split: `AGENTS.md` is read while
writing a manifest, so anything that is not needed at that moment is noise there.

## What belongs here

- A ruling whose **evidence** would otherwise be lost — the measurement, the counter-example, the
  command that was deleted for a reason nobody remembers.
- A **trade-off** written as prose, where compressing it to a rule would hide the cost.
- A decision that was tried and **rejected**, with the reason. This is the most valuable kind and
  the easiest to lose.
- Anything a maintainer would want in order to **relax** a rule later: what forced it, and what
  would make it safe to change.

## What does not

- The rule itself. That belongs in `AGENTS.md`, and it is changed there, never here.
- Mechanics of how the system works. That is `design/`.
- Batch-by-batch narrative, superseded drafts, or who argued what. That is history, and history
  lives in the commit log.
- Tooling methods that belong to a specific script; those live in that script's header comment,
  which is where a maintainer editing the script will actually see them.

## Adding a ruling

One ruling, one commit, two files:

1. Change or add the rule in `AGENTS.md` (or `design/*.md` if it is a system fact).
2. Add or amend the entry here — decision, where the rule lives, why, evidence, and an overturn
   condition if one exists.

The reason must never live longer than the rule it justifies. A rule edited without its entry
here is how the two drift apart, and a drifted rule is worse than no rule: it looks authoritative
and nobody remembers what it was defending against.
