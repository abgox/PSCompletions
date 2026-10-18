# Design: Info template language

> The single template syntax for every `info` template in completion manifests.
> Any bridge renders it without host logic. Companion: `bridge.md` (duties).

The language is deliberately minimal — variables, fallback, list loops with cap,
conditionals, one quoting filter — and freezes everything else as literal text, so a
bridge renders it with plain string substitution and never evaluates host code.

The **engine** renders it — `psc tpl <dotted.info.path> [--ctx <json>] [--version <v>]
[--no-color] [--markup] [--explain]`, or `psc tpl --stdin` with a `{data, ctx, sep}` request
([`psc-cli.md`](psc-cli.md) §6.11): a host names the template (or hands over the value it already
holds) and passes the data it holds, and the engine prints the result. The language has exactly
one implementation, so no host carries rendering logic of its own.

Two of those flags are for whoever edits a template: `--lint` checks one statically — unclosed or
unknown directives, unknown filters, an `@`-name the renderer does not define, a `.` outside a
loop — and exits non-zero on a finding; `--explain` renders and then reports what the renderer did
with each name: resolved, unresolved, or kept verbatim.

## Naming

**Host keys and item fields are PascalCase; the engine's own names are `@` plus lowercase;
directives and filters are lowercase.**

Context keys and item fields (`{{Completion}}`, `{{NewVersion}}`, `{{.Name}}`) carry the
PascalCase signature so a placeholder stands out inside prose and shell text (and matches
the PowerShell host's identifier convention). Directives and their attributes stay
lowercase: `{{#each}}`, `{{#if}}`, `{{#unless}}`, `{{else}}`, `{{/each}}`, `limit=N`,
`sep='…'`, and the `quote` filter.

The `@` namespace is the engine's own, and never mixes with the caller's data: a host may
use any name — even `More` — without colliding with the engine. `{{@more}}` is implemented;
`@index`, `@key`, `@first` and `@last` are the reserved spellings for loop metadata.

A key is nameable when it is made of letters, digits, `_` or `-`, with `.` separating
nesting. It may not start with `@` (the engine's namespace) or `.` (the current item), and a
key outside the set — a space, `|`, `{`, `}` — cannot be named by a template at all. Case is
matched literally; nothing attaches meaning to it.

## Syntax

Plain text with two additions. Colors (`<@Cyan>` etc.) are unchanged and mapped by
each renderer (unknown color → reset).

- `{{Path}}` — dotted lookup (`Completion`, `Config.Language`, `Renamed`);
  missing → empty.
- `{{.}}` / `{{.Field}}` / `{{.0}}` — the current `each` item. **Outside `each`
  they stay literal** (podman's Go-template docs `{{range .}}...{{.Name}}` survive
  untouched), as does any `{{unknown keyword ...}}` or an `@`-name the engine does not
  define.
- `{{Value}}` / `{{Owner}}` / `{{Language}}` / `{{Rejected}}` — single-value
  templates (set confirmation, ownership warning, rejected input).
- `{{A or B or C}}` — first present, non-empty value wins (`{{Display or Completion}}`).
- `{{#each List [limit=N] [sep='…']}}...{{else}}...{{/each}}` — iterate a list
  (non-list → `else` branch). `limit` renders the first `N` items, `sep` joins the
  iterations without newlines. After a capped loop, `{{@more}}` is the skipped count
  (0 when uncapped); it survives the loop, which is what a `… (+{{@more}}) more` tail
  after `{{/each}}` reads. The grammar has no arithmetic, so the count is provided
  rather than computed by the template.
- `{{#if Path}}...{{else}}...{{/if}}` — truthiness: missing/empty/`0`/`false` → false.
- `{{#unless Path}}...{{else}}...{{/unless}}` — the same, with the branches swapped.
- `{{Path|quote}}` — shell-quote a value whose surrounding whitespace would otherwise
  disappear: an all-space or padded value becomes `"..."` (or `'...'` when it contains `"` and no
  `'`). A value that is genuinely empty never reaches the filter — an empty value is treated as
  absent, so the tag renders nothing.
  Filters are a pipeline, applied left to right; an unknown one keeps the token.
- A **container** value (array/object) is data like any other: it renders as its **JSON text**,
  with or without a filter — the same "value printed as-is" rule. A template that wants a list on
  screen iterates it with `{{#each}}`.
- `{{! … }}` — a comment, dropped; it ends at the first `}}`.
- `{{> Path}}` — render another `info.<Path>` template with the same context.
- `\{{` — a literal `{{`; the backslash is dropped.

**A resolved value is data, never a template.** What a lookup produces is printed as-is,
so a completion tip or a remote description that contains braces is never interpreted —
`{{> …}}` is the only way one template pulls in another.

`{{else}}` is optional in every block. Directives and attributes that cannot be read — a
`.`-path with no current item, a spec that is not a path — and malformed tags render
literally (visible bug over silent corruption); a block that cannot be read keeps its
**whole block**, body included.

## Render context

Bridges build the same context (missing keys → empty):

| Key | Shape | Source |
| --- | --- | --- |
| `Completion` | string | target completion |
| `Display` | string | rename display (`old -> new`), else empty |
| `Alias` | string[] | trigger aliases (fallback: `[Completion]`) |
| `Configs` | `{Name, Value, Tip, Current?}[]` | manifest `config` array + `enable_hooks` row when the manifest declares `hooks` |
| `Added` / `Removed` / `Update` | string[] | library changes |
| `Renamed` | `[old, new][]` | library changes |
| `Version` / `NewVersion` | string | installed / remote module version |
| `Value` / `Owner` / `Language` / `Rejected` | string | single-value templates |
| `@more` | int | items skipped by the last capped `each` |

## Conformance

The engine is the only renderer, so the guarantee is a test rather than a comparison
between implementations: `core/cli/tests/fixtures/psc_tpl.json` pairs every template the
shipped `psc` completion carries with the exact text it renders to, and
`core/cli/src/tpl.rs` unit-tests the grammar itself. A change to the grammar or to a
template that alters a user-visible byte fails there, which is the only reliable check —
whitespace and quoting drift is otherwise invisible.

## Coverage

The psc completion's `info` section (`completions/psc/language/*.json`) is the language's only
source, and the engine is its only renderer.

The maintenance scripts' own messages (`scripts/language/*.json` for `sort-json`,
`compare-json`, `create-completion`, `link-completion`, `check-hook-targets`) are **plain
`{Name}` placeholders** filled by `Format-PscText` (`scripts/utils.ps1`): those scripts must run
in a fresh clone, where no engine binary has been built yet.

## Authoring conventions

- **Blank lines separate repeated items only.** Sections sit tight: no blank line
  below a heading or below a list section (`[Trigger Alias]` → aliases →
  `[Special Configuration]`, no gaps). Multi-item blocks (`configs`) use
  `sep='\n\n'` so the gap is *between* items, never before the first or after the
  last.
- **A loop's body carries its own newlines.** `sep` is a joiner; the last iteration
  has no trailing separator, so a trailing blank needs an explicit `\n` after
  `{{/each}}` (only when intended).

## Renderer implementation notes

Rules the renderer satisfies:

- **No host code, ever.** Rendering is data-in/text-out: a host supplies values and
  prints the result. Unknown or malformed constructs render literally — never
  evaluated, never silently dropped.
- **Item fields are `.X`.** Inside `each`, `{{Name}}` reads the *context* (outer),
  not the item; the item is `{{.Name}}`. This is deliberate (no shadowing), and it
  is what keeps Go-template docs literal.
- **`@more` is read after the loop.** It holds the last capped `each`'s skipped count
  and must remain readable *after* `{{/each}}`.
- **One truthiness rule.** `0`, `false`, `''` and an empty container are all false;
  the templates never depend on a language's coercion to decide it.
- **Byte-parity is the only reliable check.** A template that renders wrongly usually
  differs only in whitespace or quoting, so the fixture pins the exact bytes.
