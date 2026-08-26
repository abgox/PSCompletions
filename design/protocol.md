# Engine protocol (`psc-menu`)

`psc-menu` is the completion engine, host-agnostic: any shell host drives it purely through this
JSON contract. There is no in-process API to bind — only the files and flags below.

## Modes

| Mode | Invocation | Purpose |
| --- | --- | --- |
| `menu` (default) | `psc-menu <input.json> --result <out.json>` | interactive TUI menu; build mode builds + ranks candidates first when the input carries a `build` context instead of `items` |
| `sort` | `psc-menu --sort <input.json> --result <out.json>` | rank host-provided items |

All files are UTF-8 JSON. Results always travel via `--result <file>` (never stdout, avoiding
encoding issues). The default mode reads keypresses from the console and renders to stdout.

### Developer / diagnostic flags (not host-facing)

These exist for testing and CI, not for shell hosts to drive:

| Flag | Purpose |
| --- | --- |
| `--self-test` | Run the in-binary smoke test (parse a bundled sample, build state, exercise filter/layout); exits `SUCCESS`/`FAILURE` without touching the terminal. Used by CI to verify each build. |
| `--panic-test` | Deliberately panic to exercise the panic hook (diagnose output.json error-state writing). |

The candidate-building pipeline lives only in the menu's build mode (a `build` context, see below);
there is no separate headless `--complete` mode — a future shell that needs candidates without a
menu reuses the same build path.

## Shared types

### `Item` (menu candidate, `--menu` input)
```json
{ "completion_text": "add", "list_item_text": "add", "symbol": "~",
  "tip": "Add files", "usage": "add <FILE>", "example": null, "result_type": null }
```
- `list_item_text` — the rendered row text.
- `symbol` — predict-symbol display character (`~` switch / `?` stay / empty). For items the
  host provides, the host pre-maps it; in build mode the engine resolves it (see below).
- `tip` / `usage` / `example` — description box text; `null`/absent = no section.
- `completion_text` / `result_type` — kept for the host-side contract (applying the selection).

### `LuaItem` (built / ranked candidate, build mode + `--sort`)
```json
{ "text": "add", "tip": "Add files", "usage": null, "example": null,
  "symbol": "switch", "repeat": 0 }
```
- `text` — completion text (also the row text).
- `symbol` — **config key** (`switch` / `stay`) or empty, not the display character.
- `repeat` — how many times the item may be appended.

### `Config` (menu options)
```json
{ "filter_hint": "", "filter_hint_stale": "", "flags": { "enable_list_loop": true, "filter_mode": "wildcard",
  "enable_apply_when_single": false, "enable_apply_when_no_match": false, "show_mode": "auto" },
  "context_switch": "~", "context_stay": "?",
  "raw_config": { "completion": { "enable_tip": 1 }, "global": {}, "default": { "enable_tip_usage": 1 } } }
```
- `show_mode`: `auto` / `inline-follow` / `altscreen-follow` / `altscreen-top` / `altscreen-bottom`.
- `context_switch` / `context_stay` — the display characters the engine uses to resolve
  `switch` / `stay` symbols in build mode.
- `raw_config` — layered config for the three tip toggles (`enable_tip` / `enable_tip_usage` /
  `enable_tip_example`): the engine resolves them per-completion → global → default (stored as
  `1`/`0` numbers), then folds them into `flags`. The host no longer sends those three toggles
  directly in `flags`.

### `TerminalInfo`
```json
{ "cursor": { "x": 0, "y": 5 }, "buffer": { "w": 120, "h": 30 },
  "window": { "top": 0, "h": 30 }, "platform": "windows" }
```
- `window` — visible window (BufferSize spans the whole scrollback); layout is clipped to it.
  `null`/absent = the whole buffer is the viewport.
- `platform` — `windows` / `unix`.

### `OrderInfo` (background order recompute)
```json
{ "history": "<PSReadLine history path>", "cmd": "git", "aliases": ["git", "g"],
  "path": "<order output file>" }
```
`--menu` spawns a background thread that reads `history`, tallies usage, and atomically writes
the per-command order file plus the shared `_paths.json` / `_commands.json` (see `design/menu.md`).

## 1. `--menu` input

```json
{
  "items": [ { "list_item_text": "add", "symbol": "~" } ],
  "config": { "flags": {}, "context_switch": "~", "context_stay": "?" },
  "terminal": { "cursor": { "y": 5 }, "buffer": { "w": 120, "h": 30 }, "platform": "windows" },
  "order": { "history": "...", "cmd": "git", "aliases": ["git"], "path": "..." },
  "order_dir": "<order cache directory>",
  "menu_dir": "<menu temp directory>",
  "initial_filter": "^to"
}
```

Fields: `items` | `build`, `config`, `terminal`, `order`?, `order_dir`, `menu_dir`,
`initial_filter`?.

`order_dir` (optional, always set by the module) is the order-cache directory; the engine prunes
stale files (older than 90 days) from it in a background thread on each menu open.

`menu_dir` (optional, always set by the module) is the menu temp directory (`temp/menu`); the engine
prunes stale files (older than 30 minutes) from it in a background thread on each menu open — a
fallback for input/output files orphaned by a crashed or force-killed menu session (normal
invocations delete them immediately).

### Build mode

Installed commands omit `items` and pass a build context instead; the engine builds + ranks the
candidates itself before rendering:

```json
{ "build": { "cmd": "git", "arg_tokens": ["add"], "treat_last_as_complete": false,
             "manifest": "<manifest .json path>", "hooks": true, "cwd": "...",
             "config": { }, "global_config": { "enable_cache": true, "language": "en-US" },
             "data": { }, "cache_dir": "...", "log_dir": "...",
             "order": { "cmd_order": "...", "paths_order": "...", "commands_order": "..." } },
  "config": { }, "terminal": { } }
```
- `manifest` — the language manifest file path.
- `hooks` — whether to run `hooks.lua` (path derived from the manifest).
- `config` — per-completion config (manifest `config` keys + special keys), exposed to hooks as
  `psc.config`.
- `global_config` — the full global config (`menu` group etc.), for build-stage switches such as
  `enable_cache` (result caching) and `language` (hook `psc.language`).
- `data` — module-level runtime data (`psc` completion only): settings/completions paths + live
  config; empty/absent elsewhere.
- `cache_dir` — result-cache directory (`temp/cache`); empty disables caching (see
  `design/menu.md`).
- `log_dir` — `psc.log` debug-output directory (`temp/log`); empty disables logging.
- `order` — history-order file paths used to rank the candidates (see `design/menu.md`).
- Build produces `Item`s: the engine resolves the manifest tree, runs hooks, order-sorts, maps
  `switch` / `stay` symbols through `context_switch` / `context_stay`, and derives
  `initial_filter` from the pending token (unless the host already set one).

## 2. `--menu` result

```json
{ "status": "selected", "index": 3 }
{ "status": "selected", "index": 3, "completion_text": "add", "result_type": null }
{ "status": "cancel" }
{ "status": "input", "text": "some-filter" }
{ "status": "min_area" }
{ "status": "error", "message": "..." }
```

- `selected` — an item was applied. In build mode the engine also returns
  `completion_text` / `result_type` (the host has no item list to index into); with `items`
  the host indexes `items[index]`.
- `input` — no-match auto-apply: a following append applies the filter text (leading `^`
  stripped). Not produced by Enter.
- `cancel` — nothing was applied. **When `cancel` is due to no candidates, nothing was
  rendered** (no `covered_*`, no terminal writes) — the host must not restore anything.
- Optional on `selected`/`cancel`: `is_show_above`, `covered_top`, `covered_bottom`,
  `alternate`. `covered_*` give the exact row range to restore; **their absence means nothing
  was drawn, so no restore** (writing back would make PSReadLine repaint its prediction list).

## 3. `--sort`

Input:
```json
{ "items": [LuaItem...], "order": { "cmd_order": "...", "paths_order": "...", "commands_order": "..." },
  "tokens": ["npm"], "treat_last_as_complete": false }
```
- `items` — host-provided candidates to rank.
- `order` — order-file paths (optional; `_commands.json` / `_paths.json` are the shared
  global files).
- `tokens` — the input line's tokens as the host tokenized them (including the first one).
- `treat_last_as_complete` — whether the last token is complete (a space followed it).

**Shared-file rule**: the shared global order files are strictly scoped. `_commands.json` applies
**only when the completion targets the first token** — i.e. `tokens.len() == 1` and
`!treat_last_as_complete` (completing the root command, e.g. `g<Tab>`). Once the command is
complete (`npm <Tab>`) or more tokens follow (`git st<Tab>`), bare-word candidates rank against
the per-command order file only. `_paths.json` is not depth-gated but matches only **explicit
path candidates** (item text containing `/` or `\`, e.g. `cd .\src\<Tab>`); bare words never
consult it — a subcommand sharing a name with a directory in path history must not inherit its
weight.

Result: a `LuaItem` array in ranked order (descending score, stable — items without a score
keep their relative order).

## Contract notes

- **No candidates → no render**: an empty candidate list makes `--menu` return `cancel`
  without touching the terminal (no alternate screen, no buffer writes, no output).
- **Terminal resize**: the engine monitors for terminal resize events during the menu session
  and re-renders accordingly. The host-provided `terminal` dimensions are used for the initial
  layout; subsequent resizes are handled internally by the engine.
- **Symbol keys vs characters**: built items carry `switch` / `stay` keys; the display
  character is resolved by the engine (build mode) or the host (native items).
- **Restore is driven by `covered_*`**: the host restores exactly that row range; nothing to
  restore when the fields are absent.
- **Tokenization is duplicated by necessity**: the host tokenizes the input buffer
  (`input_pattern`, required before the engine is invoked, to pick the command and split
  `arg_tokens`), and the engine tokenizes history lines (`order::tokenize`). They share one
  grammar (`(?:"[^"]*"|'[^']*'|\S)+`) — keep both in sync when the semantics change.
