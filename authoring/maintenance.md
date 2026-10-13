# Maintenance

Two recurring jobs: updating a completion for a new tool version, and translating to another
language.

## Updating an existing completion (new tool version)

1. Get the new version's `--help` output or changelog.
2. Compare with the existing `en-US.json` — new subcommands, new options, changed
   defaults, deprecated flags.
3. Update `en-US.json` first, then sync structural changes to `zh-CN.json` and other
   languages.
4. Run `./scripts/compare-json.ps1 <command>` and fix every reported issue.
5. Re-run `./scripts/check-hook-targets.ps1 <command>` if a `hooks.lua` exists — renaming
   or removing a manifest item breaks its `psc.on` targets silently.

### Delete only on evidence

A locally missing command is **not** a deletion reason (`R-04`). Delete only when upstream
has removed it, or the CLI rejects it locally **and** upstream has no such command. Never
encode documentation topics (`HELP TOPICS`) or shell-library entry points. Why, and the two
directions the rule was derived from: [`D5`](../decisions/authoring.md#d5).

**Do not delete options just because a changelog says "deprecated"** unless you have
confirmed the CLI no longer accepts the parameter. Keep the entry and note it in the
description (e.g. `"(deprecated, use --new-flag instead)"`).

### The confirmation is an invocation, and its result decides

The evidence is the CLI's own error text, so run the flag with no value:

| Result | Ruling |
| --- | --- |
| `unknown argument '--x'` | **delete** — the CLI refuses it |
| `a value is required for '--x <X>'` | **keep** — hidden from `--help` but still accepted |
| `unexpected argument '--x' found` | **delete** — refused outright |

`--help` being silent about a flag is not evidence of removal — a CLI hides flags between
versions while still accepting them. The converse also happens: a flag the help *does*
list may be gone. The error text settles both directions, and nothing in `--help` does.

A renamed pair that shares a short alias keeps the alias on the current long form only; the
older synonym keeps its long form without the alias, so both stay completable. See
[`D31`](../decisions/authoring.md#d31) for the same invocation test applied to hook code.

## Translation (`zh-CN.json` and other languages)

1. Structure must be identical to `en-US.json` — same nesting, same array order, same
   entries.
2. Only translate `tip` / `usage` / `example` content. `name`, `alias`, `repeat`, and the
   values inside `next` stay as-is.
3. Spaces between Chinese and English characters (enforced by
   `validate-completion.ps1`).
4. Do not translate proper nouns — command names, option names, and tool names stay as-is.
5. When a `tip` value is a proper noun that cannot be translated, append a trailing space so
   `compare-json.ps1` does not flag it as untranslated. For example, `"Chromium"` →
   `"Chromium "`.
6. A large `next` array of identifiers (rule codes, config keys) raises the same question at once:
   translating each one into prose usually distorts it, and leaving it identical fails the gate.
   Pick one of the three deliberately — translate, append a trailing space (item 5), or omit the
   `tip` and let the bare `name` carry the entry.

### How the untranslated check actually works

`compare-json` does not ask "is this translated?" — it asks "does this differ from `en-US`?"

- **Only `tip` is enforced.** `usage` and `example` pass while identical to the base language
  (`identicalOk` in `scripts/psc-tools.cs`), which is correct: they are the CLI's own syntax, not
  prose.
- The comparison is **case-insensitive** and **untrimmed**. Uppercasing an identifier does not
  count as translating it; a real character difference is required, which is exactly why the
  trailing-space trick works.
- Text wrapped in `{{...}}` counts as a template and may be identical. Reserve it for genuine i18n
  placeholders, not identifiers.
- **No CJK check exists.** "A translated tip should carry at least one Chinese character" is an
  author judgement, not a gate. The scripts cannot see it.

Run `./scripts/compare-json.ps1 <command>` for the language you translated — it must come
back clean for both languages.

### Translate from a dictionary, and never overwrite a translation

A large completion repeats the same handful of descriptions many times over — `glab` needed
936 distinct strings to cover 2 451 tips, with `Select another repository…` appearing on 161
pages. Two consequences for the workflow:

- **Build an `english tip -> translated tip` dictionary first, then apply it.** One entry
  serves every occurrence, and the same wording gets the same translation everywhere instead
  of drifting per page. Keys are the `tip` array joined with `\n`, so a multi-line tip is one key.
- **Any regeneration or generation script must merge by key, never deep-copy.** Copying
  `en-US.json` into the translated file to "fill in the structure" silently discards every
  translation that already exists — the copy is identical to the base, which is precisely
  what `compare-json` calls untranslated. Walk the tree and carry each existing translated
  tip over, then apply the dictionary to what is left. A dictionary entry is only ever
  applied where the target-language tip still equals the English tip (i.e. still
  untranslated) — never over an existing translation.

`schema` still applies: the structure must end up identical to `en-US.json`.

### Scripted realignment: immutable plans, no subtree copies, no reverts

Bringing a stale manifest back in line is a pipeline — harvest the CLI's truth into a table,
diff the table into a plan, apply the plan, translate from a dictionary. Three habits keep the
pipeline from eating its own output:

- **A plan file is write-once.** Regenerating the plan after applying it overwrites it with an
  empty diff — a verification pass reads the *current* tree, so it must write its report
  elsewhere. The plan you applied is the record of what changed; keep it until the completion
  is committed.
- **Mirror structure by field, never by reference.** Copying a `next` subtree from the base
  language into the translation replaces the translated children with untranslated ones, and a
  subtree held by reference makes one file's edits appear in the other. Copy the language-
  neutral fields (`usage`, `alias`, the *values* of `next`, `repeat`) and the tips from the
  dictionary; a command tree changes only where you change it explicitly.
- **Snapshot before applying, and recover from the snapshot.** `git checkout -- <file>`
  restores the last *commit*, discarding every uncommitted edit — both language files and
  `hooks.lua` at once. Copy the files aside before a large scripted pass and recover from that
  copy; `git` is for committed states, not for undoing this morning.

## Large audits (many missing options)

When 20+ entries or 5+ commands need verification, batch the work instead of doing it
in one pass. Batching changes the bookkeeping, not the evidence bar — every command and
option still gets its own `--help` check (`R-02` … `R-08`).

1. Create scratch `WIP/<tool>/`: a `README.md` (batch log + priority list, commands
   sorted by missing count) and one directory per command for its help output and
   proposed additions (`en` / `zh` JSON — options and, where applicable, subcommands).
2. Work in batches of 3–6 commands: write `en-US.json` first, then translate (steps 1–4
   of §Translation above), then run **all three gates** and fix every reported issue
   before the next batch — `compare-json` alone is not enough (`validate-completion`
   owns schema and spacing; `check-hook-targets` owns hook targets). What each report
   means is in [`validation.md`](validation.md).
3. Log each batch (commands covered, options added, duplicates or alias collisions hit,
   validation result).
4. Keep the scratch directory — it is working material, not part of the completion, and it
   is exactly what a review sends work back to. Hand it over (path, file count, size) and
   delete it only when the operator confirms (`R-20`,
   [`working-files.md`](working-files.md)).

## Proposing the commit

When the operator confirms the task is done — or the gates, translation, and judgment
checks are all complete — draft the commit message and ask whether to commit now. Never
commit unilaterally: committing publishes, and batching, squashing, or holding back is the
operator's call (`R-21` in `../AGENTS.md`).

One completion per commit. A batch of completions shares one commit only when every item
takes the same action (`add`, `update`); mixed actions are split into
separate commits, because the body carries no per-item action word.

Format — one completion (the first line carries everything):

```
feat(completions): add sudo@sudo-project (Sudo 1.9.16p2)
```

Format — two or more completions (the first line classifies, the body lists;
the first line never names completions):

```
feat(completions): add

- sudo@sudo-project (Sudo 1.9.16p2)
- sudoedit@sudo-project (Sudo 1.9.16p2)
- sudo@Microsoft (Sudo for Windows 1.0.1)
```

```
feat(completions): update

- scoop (Scoop v0.6.0)
- abgox.scoop-i18n (2026.10.05.141200)
```

- The word after the colon is the one shared action: `add` for new completions,
  `update` for existing ones changed for a new tool version (`fix` / `remove`
  follow the same shape). The body lists one completion per line, no per-item
  action word.
- `(<Upstream> <version>)` is the CLI version the manifest was verified against — the
  baseline the next update diffs against, not decoration. Take it from `<cmd> --version`
  (or the tool's equivalent) run during collection. When the completion was authored from
  docs alone with no versioned binary available, mark it approximate:
  `(~<Upstream> <version>, docs)`.
- Always keep the `<Upstream>` name, even when it repeats the directory stem
  (`jjui (jjui 0.10.11)`). A conditional rule ("keep it only when it adds information")
  costs a judgment call per line; an unconditional one costs a redundant word. And the
  name pays off exactly where it matters: variant families sharing one command word
  (`sudo@sudo-project (Sudo 1.9.16p2)` vs `sudo@Microsoft (Sudo for Windows 1.0.1)`),
  or a binary whose name hides its project (`ya (Ya 26.9.1)`). `<Upstream>` is the name
  the tool calls itself in its own version output — not the directory stem.
