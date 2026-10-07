# Maintenance

Two recurring jobs: updating a completion for a new tool version, and translating to another
language.

## Updating an existing completion (new tool version)

1. Get the new version's `--help` output or changelog.
2. Compare with the existing `en-US.json` — new subcommands, new options, changed
   defaults, deprecated flags.
3. Update `en-US.json` first, then sync structural changes to `zh-CN.json` and other
   languages.
4. Run `.\scripts\compare-json.ps1 <command>` and fix every reported issue.
5. Re-run `.\scripts\check-hook-targets.ps1 <command>` if a `hooks.lua` exists — renaming
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

Run `.\scripts\compare-json.ps1 <command>` for the language you translated — it must come
back clean for both languages.
