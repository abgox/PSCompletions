# Maintenance

Two recurring jobs: updating a completion for a new tool version, and translating to another language.

## Updating an existing completion (new tool version)

Before step 1, confirm the source belongs to the version being updated: compare `config.json` `version` with `<cmd> --version`.
When they differ, install the recorded release or collect from that release's documentation — a page from another release reports missing and stale options at once, and neither is evidence.
Prove the page lists the whole surface first: [`collecting-info.md`](collecting-info.md) §Prove the help page is complete.

1. Get the new version's `--help` output or changelog.
2. Compare with the existing `en-US.json` — new subcommands, new options, changed defaults, deprecated flags.
3. Update `en-US.json` first, then sync structural changes to `zh-CN.json` and other languages.
4. Run `./scripts/compare-json.ps1 <command>` and fix every reported issue.
5. Rebuild the slot inventory and decide hooks again, **even when the completion had none** (`R-25`): every value slot gets a row, and a `none` verdict names the sources checked — the CLI, the OS, a project file, a config or state file, or a completion protocol. "No hooks" is a result of that pass, not a reason to skip it.
6. Re-run `./scripts/check-hook-targets.ps1 <command>` if a `hooks.lua` exists — renaming or removing a manifest item breaks its `psc.on` targets silently.
7. Record the new CLI version in `config.json` `version` (verbatim first line of `<cmd> --version`); the gate requires it.

### Delete only on evidence

A locally missing command is **not** a deletion reason (`R-04`).
Delete only when upstream has removed it, or the CLI rejects it locally **and** upstream has no such command.
Never encode documentation topics (`HELP TOPICS`) or shell-library entry points.
Why, and the two directions the rule was derived from: [`D5`](../decisions/authoring.md#d5).

**Do not delete options just because a changelog says "deprecated"** unless you have confirmed the CLI no longer accepts the parameter.
Keep the entry and note it in the description (e.g. `"(deprecated, use --new-flag instead)"`).

### The confirmation is an invocation, and its result decides

The evidence is the CLI's own error text, so run the flag with no value:

| Result | Ruling |
| --- | --- |
| `unknown argument '--x'` | **delete** — the CLI refuses it |
| `a value is required for '--x <X>'` | **keep** — hidden from `--help` but still accepted |
| `unexpected argument '--x' found` | **delete** — refused outright |

`--help` being silent about a flag is not evidence of removal — a CLI hides flags between versions while still accepting them.
The converse also happens: a flag the help *does* list may be gone.
The error text settles both directions, and nothing in `--help` does.

A renamed pair that shares a short alias keeps the alias on the current long form only; the older synonym keeps its long form without the alias, so both stay completable.
See [`D31`](../decisions/authoring.md#d31) for the same invocation test applied to hook code.

## Translation (`zh-CN.json` and other languages)

**Prerequisite:** `en-US.json` passes `validate-completion.ps1` (schema bucket) before translation starts (`AGENTS.md` step 6).
`compare-json` does not check schema, so translating first turns every structural fix into a second translation pass.

1. Structure must be identical to `en-US.json` — same nesting, same array order, same entries.
2. Only translate `tip` / `usage` / `example` content. `name`, `alias`, `repeat`, and the values inside `next` stay as-is.
3. Spaces between Chinese and English characters (enforced by `validate-completion.ps1`).
4. Do not translate proper nouns — command names, option names, and tool names stay as-is.
5. When a `tip` value is a proper noun that cannot be translated, append a trailing space so `compare-json.ps1` does not flag it as untranslated. For example, `"Chromium"` → `"Chromium "`.
6. A large `next` array of identifiers (rule codes, config keys) raises the same question at once: translating each one into prose usually distorts it, and leaving it identical fails the gate. Pick one of the three deliberately — translate, append a trailing space (item 5), or omit the `tip` and let the bare `name` carry the entry.

### The CLI's own localized help is a dictionary

Before translating by hand, check whether the tool ships localized help: `LANG=zh_CN.UTF-8 <cmd> --help`.
x-cmd 0.10.12 printed Chinese module pages with the same option heads as the English pages; matching by spelling produced the translations for 184 new options without a hand-written dictionary.
Verify the localized page covers the same spellings as the English one — a missing entry is a hole to translate, not a translation.

### How the untranslated check actually works

`compare-json` does not ask "is this translated?" — it asks "does this differ from `en-US`?"

- **`tip` is enforced — and so is an object item's `desc`.** A plain `usage` / `example` string passes while identical to the base language (`identicalOk` in `scripts/psc-tools.cs`), which is correct: it is the CLI's own syntax, not prose. The object form `{ "cmd", "desc" }` is the exception — a `desc` exists to explain, so an identical one is untranslated by definition. A `desc` that is language-neutral by nature (a command line, a JSON shape) still needs a translated lead-in, e.g. `Output: …` / `输出: …`.
- The **`cmd`** of that same object is checked the other way: it must stay **identical** in both languages — a difference is reported as a semantic mismatch — because it is the literal invocation.
- The comparison is **case-insensitive**. Uppercasing an identifier does not count as translating it; a real character difference is required, which is why the trailing-space trick works on a **plain string** (those arrays are joined untrimmed). It does **not** work on an object item's `desc`: both sides are trimmed before the comparison.
- Text wrapped in `{{...}}` counts as a template and may be identical. Reserve it for genuine i18n placeholders, not identifiers.
- **No CJK check exists.** "A translated tip should carry at least one Chinese character" is an author judgement, not a gate. The scripts cannot see it.

Run `./scripts/compare-json.ps1 <command>` for the language you translated — it must come back clean for both languages.

### Translate from a dictionary, and never overwrite a translation

A large completion repeats the same handful of descriptions many times over — `glab` needed 936 distinct strings to cover 2 451 tips, with `Select another repository…` appearing on 161 pages.
Two consequences for the workflow:

- **Build an `english tip -> translated tip` dictionary first, then apply it.** One entry serves every occurrence, and the same wording gets the same translation everywhere instead of drifting per page. Keys are the `tip` array joined with `\n`, so a multi-line tip is one key.
- **Any regeneration or generation script must merge by key, never deep-copy.** Copying `en-US.json` into the translated file to "fill in the structure" silently discards every translation that already exists — the copy is identical to the base, which is precisely what `compare-json` calls untranslated. Walk the tree and carry each existing translated tip over, then apply the dictionary to what is left. A dictionary entry is only ever applied where the target-language tip still equals the English tip (i.e. still untranslated) — never over an existing translation.
- **Translate mechanical lines by rule, dictionary for the rest.** `Possible values: …`, `(default …)`, and template tips generated from one pattern (`Append 1 or more items to the --X list.`) translate deterministically — encode them as pattern rules applied first (mpv covered 724 of 3 118 lines that way; hf's enum and default lines likewise), and spend the dictionary on real prose. A coverage script that fails loudly on the remainder keeps the split honest.
- **Continuation lines are dictionary keys too.** When keys are per-line rather than joined, a multi-line tip contributes its fragments (`of PATH.`, `on a failed search.`) as separate keys — translate each as the continuation it is, not as a standalone sentence.
- **Rebuilds invalidate positional carry-over.** Carrying a translated line by position assumes the base-language array still has the shape it had when the translation was written. The moment a generator rule changes a split, drops a line, or joins two (an abbreviation guard, a dangling-line drop), every position after the edit silently points at the wrong translation — both files stay internally consistent, so no gate fires. After any rebuild, scan for it: every base line that is in the dictionary but whose translation differs is suspect (one option drifted by two positions this way) — realign those from the dictionary. Deterministic pattern rules are immune to this; run them before the carry-over, never after, so stale rule output cannot persist.

`schema` still applies: the structure must end up identical to `en-US.json`.

### Measure the translation, not the entry count

Count distinct tips, not entries: thousands of entries can carry an order of magnitude fewer distinct sentences, and the dictionary is what gets translated.
Look up the existing translation for the same sentence before translating it again — manual prose repeats across commands.
Generated tips are patterns, not prose: `Disable --foo.` / `禁用 --foo。` and `Possible values: …` / `可能值: …` are rules, not dictionary entries.
When several translators work in parallel, give each a fixed contract — same order as the key file, one output line per source line, the Chinese/Latin spacing rule — and run `compare-json` after every merged batch.

### Scripted realignment: immutable plans, no subtree copies, no reverts

Bringing a stale manifest back in line is a pipeline — harvest the CLI's truth into a table, diff the table into a plan, apply the plan, translate from a dictionary.
Three habits keep the pipeline from eating its own output:

- **A plan file is write-once.** Regenerating the plan after applying it overwrites it with an empty diff — a verification pass reads the *current* tree, so it must write its report elsewhere. The plan you applied is the record of what changed; keep it until the completion is committed.
- **Mirror structure by field, never by reference.** Copying a `next` subtree from the base language into the translation replaces the translated children with untranslated ones, and a subtree held by reference makes one file's edits appear in the other. Copy the language- neutral fields (`usage`, `alias`, the *values* of `next`, `repeat`) and the tips from the dictionary; a command tree changes only where you change it explicitly.
- **Snapshot before applying, and recover from the snapshot.** `git checkout -- <file>` restores the last *commit*, discarding every uncommitted edit — both language files and `hooks.lua` at once. Copy the files aside before a large scripted pass and recover from that copy; `git` is for committed states, not for undoing this morning.

### An apply must be idempotent

A partially applied manifest is a normal state — a crash, a failed gate, a second batch — so a re-run must converge instead of duplicating:

- dedupe entries by `name` before matching;
- keep every alias the manifest already records, even when the source term omits it;
- skip a source spelling that already exists as another entry's alias;
- rebuild `usage` after an alias change, or the line reports a form the item no longer has;
- assert no spelling collision in memory before writing; the gates see it only after the file is on disk.

## Large audits (many missing options)

When 20+ entries or 5+ commands need verification, batch the work instead of doing it in one pass.
Batching changes the bookkeeping, not the evidence bar — every command and option still gets its own `--help` check (`R-02` … `R-08`).
Measure before choosing batches: a per-command table of source spellings minus manifest spellings, sorted by the gap (`R-24`).
It separates "a release changed a handful" from "most of the surface is absent", and it decides the order — when the gap spans more than one batch, agree on that order with the operator before editing.

1. Create scratch `WIP/<tool>/`: a `TODO.md` session record (phases, next command, open questions — [`working-files.md`](working-files.md) §The session record), a `README.md` (batch log + priority list, commands sorted by missing count) and one directory per command for its help output and proposed additions (`en` / `zh` JSON — options and, where applicable, subcommands).
2. Work in batches of 3–6 commands: write `en-US.json` first, then translate (steps 1–4 of §Translation above), then run **all three gates** and fix every reported issue before the next batch — `compare-json` alone is not enough (`validate-completion` owns schema and spacing; `check-hook-targets` owns hook targets). What each report means is in [`validation.md`](validation.md).
3. Log each batch (commands covered, options added, duplicates or alias collisions hit, validation result) and the `slots.json` rows for its commands.
   A batch is done when every `verdict: hook` row maps to a `psc.on` target and every other ref/name slot carries a written reason.
4. Keep the scratch directory — it is working material, not part of the completion, and it is exactly what a review sends work back to. Hand it over (path, file count, size) and delete it only when the operator confirms (`R-20`, [`working-files.md`](working-files.md)).

## Proposing the commit

When the operator confirms the task is done — or the gates, translation, and judgment checks are all complete — draft the commit message and ask whether to commit now.
Never commit unilaterally: committing publishes, and batching, squashing, or holding back is the operator's call (`R-21` in `../AGENTS.md`).

Detect the VCS before committing, and let the repository decide: when `.jj` exists at the repository root the repo is Jujutsu-managed — commit with `jj describe` (or `jj commit`) even if a `.git` directory sits beside it, since that is only jj's git mirror in a colocated working copy.
With no `.jj`, use git.
The message format below applies to either.

Limit the commit to this completion's directory: the working copy often holds other in-flight work (`WIP/<other>/`, another completion), so commit by path — `jj commit <dir>` (`jj commit` takes filesets), or stage only that directory with git — never the whole working copy.

One completion per commit.
A batch of completions shares one commit only when every item takes the same action (`add`, `update`); mixed actions are split into separate commits, because the body carries no per-item action word.

Format — one completion (the subject carries everything):

```
completions: add sudo@sudo-project
```

Format — several completions with the same action (one line, names joined by `/`):

```
completions: add sudo@sudo-project/sudoedit@sudo-project/sudo@Microsoft
```

```
completions: update scoop/scoop-install/scoop-update
```

Move the batch into a body only when that line would be genuinely too long to read; the subject then stops after the action:

```
completions: add

- sudo@sudo-project
- sudoedit@sudo-project
- sudo@Microsoft
```

- The word after the colon is the one shared action: `add` for new completions, `update` for existing ones changed for a new tool version (`fix` / `remove` follow the same shape). The names follow on the same line, joined by `/`; in the body form there is one completion per line, with no per-item action word.
- The baseline CLI version lives in `config.json` `version`, not in the commit message: the verbatim first line of `<cmd> --version` (or the tool's equivalent) run during collection. Refresh it on every update — the gate requires it, and the next update diffs against it. Authored from docs alone with no versioned binary available? Record the docs-stated version as-is; the drift check will flag it for re-verification once a real binary is on hand.
- Quote the drafted message verbatim when asking whether to commit — no appended version strings, parenthetical notes, or explanations. Anything worth saying about the completion already has a home (`config.json` `version`, the handoff report); restating it beside the message invites the two to drift.
