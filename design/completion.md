# Design: Completion System (context, resolve, predict symbols, manifest)

> The core of the system: how a manifest becomes the menu. Covers the completion tree,
> context resolution, predict symbols, repeat filtering, and the manifest format.
> Companion docs: `architecture.md` (repo layout), `hooks.md` (dynamic values), `menu.md`
> (TUI rendering), `filter-matching.md` (menu filter).

## 1. Completion context

Every command has its own **completion context** — what appears in its menu. A context is
made of **subcommands** (`next`) and **options** (`option`); `global_option` items are
available at every level.

The engine builds a **`Tree`** from the manifest: `next` (root subcommands), `options`
(root options), `global_options`. Each node is a **`Node`** — either a subcommand or an
option — carrying `name`, `aliases`, `tip`/`usage`/`example`, `repeat`, and its own
`next`/`option` children.

Typing `git <Tab>` builds the menu from git's root context. Applying a subcommand switches
**to that subcommand's context**; applying an option stays in the current context
(unless the option itself defines `next`/`option` values, which switches into the option's
context).

**Context walking**: the candidate set is strictly the **current node's own** `next` array
(resolve never falls back to a previous command's context). Applying a subcommand pushes its
node as the new current context; a "known" (already-typed) subcommand is filtered out of the
menu by the repeat rule, not by inheriting an outer context.

**Option resolution (bubbling)**: the options offered in a context come from the current
node's own `option`; if the node has none, they bubble **up the ancestor chain** — the
nearest ancestor that declares an `option` wins, and only if no ancestor has one do the
tree's root `option` items apply. `global_option` is always appended. Place a flag on the
**most precise level** where it is valid.

## 2. Resolve (engine)

`resolve(tree, arg_tokens, treat_last_as_complete)` walks the typed tokens and produces a
`ResolvedContext`:

| Field | Meaning |
| --- | --- |
| `path` | Subcommand path of **canonical names** (aliases expanded, case-normalized). |
| `layers` | Typed context-switch chain: `(kind, canonical)` tuples — commands always; options when they have a `next` array (even empty) or a non-empty `option` array. Drives **declarative location matching** (`psc.on` spec matching). |
| `pending` | The **unfinished last token** (the word being typed); `None` when the line ends with a space. |
| `opts` | All completed options' **canonical names**, in order (aliases expanded; symmetrical to `path`). The most recent is `opts[#opts]`. |
| `tokens` | Completed tokens: `{ text, type, canonical? }` — excludes pending. |

Each token is classified as `command` / `option` / `value` / `unknown`:
- Known commands/options push a `command`/`option` token with a **`canonical`** = the main
  (longest) name — alias input normalizes to it.
- Values of options become `value` tokens (even when the value is not in the option's static
  candidates). The engine implements **"command/option wins"**: an option with `next` (even
  empty) consumes the next token as its value — unless that token matches a known command or
  option, in which case the option acts as a flag and the token is classified as `command`/`option`.
- Anything else is `unknown`.
- `used` counts each command/option by its canonical name for **repeat** tracking.
- The candidate `seen` filter (resolve phase) collects **command** tokens only — option-layer
  candidate values and unknown words never consume a static subcommand's candidate slot.
- After consuming a value, the context resets to the nearest command context, so subcommands
  remain reachable.

The generation phase returns the **full candidate set of the current context** — it does
**not** pre-filter by pending; filtering is left to the menu via `initial_filter`
(`^<pending>`).

## 3. Predict symbols

**Terminology — selecting vs applying**: *selecting* moves the menu highlight to an item (no
effect on the input line or the context); *applying* confirms it into the input line. A predict
symbol describes what **applying** the item does — the context change happens only on apply, so
the symbol is a promise about the apply outcome, not about selecting (highlighting) the item.

Each menu item may carry a **predict symbol** showing how applying it changes the context:

| Symbol | Config item | Meaning |
| --- | --- | --- |
| `~` | `switch` | Apply → **switch to a new context** — `peek(input+[candidate])` has non-`global` candidates beyond `parent(input)` |
| `?` | `stay` | Apply → **stay in current layer** — no new layer, but `peek(input+[candidate])` still has non-`global` candidates (e.g. `scoop install -u` keeps `apps`) |
| — | — | No follow-up beyond `global_option` (leaf like `scoop checkup` whose `peek` is only `--help/--version`) |

**Engine judgement**: static `has_static_candidates(next/option non-empty)` → immediate `~` (fast path, e.g. `git stash`); otherwise async `peek_predict_symbol` in `menu/protocol.rs`:

- `has_new = peek - parent - global ≠ ∅` → `switch(~)` (`install`→`7zip` new)
- `!has_new && peek - global ≠ ∅ && candidate.is_option && !is_global` → `stay(?)` (`-u` stays in `install` layer)
- else `None` (`checkup` only `global`)

`global_option` and parent-inherited `option` are excluded first, avoiding `scoop --help` being misjudged as `~`.

**Display**: the item's `symbol` is a **config key** (`switch`/`stay`). In build mode the
engine maps it to a display character through `context_switch` / `context_stay`
(user-configurable via `psc config context switch|stay`, defaults `~` / `?`). The menu no
longer prints the symbol on every item — it shows **the current selected item's** symbol next
to the counter (e.g. `03/15 ~`), so the list stays clean and the symbol follows the selection.

## 4. Repeat filtering

`repeat` on an option/command limits how many times it may appear:

- **Static** (resolve phase): `used` counts by canonical name; an item with `repeat == 0`
  that was already used is dropped, and one with `repeat > 0` is dropped once
  `used >= repeat`.
- **Dynamic** (after `run_hook`): only the hook's **added** items are filtered against the
  same rule using `context.tokens` — the count keys on `canonical` (so alias input counts as
  the main name). Static items are **skipped** here (their repeat was already enforced in the
  resolve phase), so an entered *value* is never mistaken for a used static subcommand
  (e.g. `git --exec-path add` keeps the static `add`). Values do count for dynamic items,
  though: after `git branch main`, a hook-added `main` is hidden. `psc.add`'s `repeat`
  parameter defaults to `0` (a used item is hidden after first use); set N to keep offering
  it until N uses.

A large number (e.g. `99`) effectively means "no practical limit" — no special-casing in the
engine.

## 5. Manifest format

A completion lives in `completions/<command>/`:

```
config.json        { "language": ["en-US","zh-CN"], "alias": [...], "hooks": true, "id": "<uuid>" }
hooks.lua          present only when config.json has "hooks": true
language/en-US.json  the manifest (single source of truth)
language/zh-CN.json  translated copy (same structure, only tip/usage/example localized)
```

Top-level manifest fields:

| Field | Required | Meaning |
| --- | --- | --- |
| `meta` | yes | `url`, `description` |
| `next` | no | Subcommand list (each may carry `alias`, `usage`, `tip`, `option`, `next`) |
| `option` | no | Root-level options (available before any subcommand) |
| `global_option` | no | Options available at **every** level |
| `config` | no | Per-completion configurable settings (advanced) |
| `info` | no | Extra data for the module/hooks (advanced; see `completions/psc/`) |

**`next` semantics**:

| `next` value | Meaning | Predict symbol |
| --- | --- | --- |
| `[...]` (non-empty) | A fixed list of values to complete from | `~` |
| `[]` (empty) | **Options only** — no static candidates; async `peek` may upgrade to `?` if staying layer still has non-`global` candidates | — initially, `?` if stay |
| (omitted) | Command has no sub-subcommands; value is conveyed by `usage` placeholder | — |

> **Rule**: `[]` (empty array) is **forbidden for commands** — commands only have a subcommand
> layer (`[...]`) or nothing. `[]` is **allowed for options** — it means "this option takes a
> free-form value with no static candidates".

**`option` vs `global_option`**:

| Availability | Where |
| --- | --- |
| Only at root level (e.g. `--version`) | `option` |
| At root **and** all subcommands (e.g. `--help`) | `global_option` |
| Only for a specific subcommand | That subcommand's `option` |

Subcommand's own `option` inherits `global_option` — never repeat it.

**Manifest is data, not code** — `tip`/`usage`/`example`/`description` are **plain text**.
`usage`/`example` entries may also be a `{ "cmd", "desc" }` object (both keys required by
convention — see `AGENTS.md` §`tip`/`usage`/`example` Format Rules), rendered as `cmd  # desc`
(the engine joins with two spaces + ` # `; a missing `desc` renders just `cmd`).
Dynamic tip content (live values, file reads) is produced by the completion's `hooks.lua`
(`design/hooks.md`), which renders the final text when the menu is built.

## 6. Cross-references

- `hooks.md` — Lua hooks: dynamic items, `psc.add`, the authoritative `psc.*` API.
- `menu.md` — how items are rendered, the counter + predict-symbol display, filtering.
- `filter-matching.md` — how the menu filter matches items.
- `AGENTS.md` — operative rules for writing completions (workflow, validation, format rules).
- **JSON Schemas** (`schema/`) — strict machine-validated definitions:
  - [`completion-manifest.en-US.json`](../schema/completion-manifest.en-US.json) — the manifest format (en-US annotations).
  - [`completion-config.en-US.json`](../schema/completion-config.en-US.json) — the per-completion `config.json` format.
  - Bilingual copies (`*.zh-CN.json`) carry Chinese annotations.
