# Design: The Cross-Platform TUI Menu (Rust)

> Status: **current**. The completion menu is a Rust subprocess (`psc-menu.exe` / `psc-menu`)
> rendered with ratatui + crossterm; PowerShell no longer draws menus.
> Filter matching spec: `design/filter-matching.md`. CLI docs: `design/psc-cli.md`.

## 1. Process model

```
Tab pressed
  → module_completion_menu_script (PowerShell)
      → get_completion (installed command) hands a **build context** (cmd/arg_tokens/manifest/
        hooks/order paths), not items — the engine builds and ranks the candidates itself
      → show_module_menu(build)                        ← Rust menu, single process
           1.  assemble input.json: `build` context + config + terminal (no items)
           2.  write to the temp dir
           3.  (Windows) save only the region the menu covers (see "Input line never
               saved/restored" below)
           4.  spawn psc-menu <input.json> --result <output.json> (UTF-8) — one process
           5.  engine: build items from manifest + hooks, order-sort, render menu
           6.  wait, read output.json
           7.  (Windows) restore covered region (restore contract: see §2 `covered_*`)
           8.  reposition the cursor
           9.  selected → handle_menu_output (engine returns the item's text in build mode)
  → native fallback (uninstalled / path / root-prefix commands): TabExpansion2 items →
      engine `--sort` ranking → menu with items (not build)
  → failure / timeout / missing binary → error message, return $null (no RawUI fallback)
```

**Boundary**: `handle_menu_output` (suffix, trailing-separator, quoting) depends on the
PowerShell buffer context and stays in PowerShell. With host-provided `items` Rust returns the
selected **index**; in build mode it also returns the item's `completion_text` / `result_type`
(the host has no item list to index into).

### Terms: selecting vs applying

The menu keeps two actions apart:

- **Selecting** (`select`) — moving the highlight to an item. It never touches the input line and never changes the completion context; only the
  highlight and the counter move.
- **Applying** (`apply`) — confirming the current selection into the input line. **`Tab` applies directly when the
  filter leaves exactly one match** (there is nothing to cycle through, so it confirms instead).
  The completion **context** (and thus the next menu content) changes only when an item is
  applied. A **predict symbol** (`~`/`?`, see `design/completion.md`) tells you what *applying*
  that item does — not what selecting it does.

In the result contract below, `status: "selected"` means "the user applied an item" (it carries
the applied index); the Rust menu itself never edits the input line.

### Key & mouse bindings

The menu's input handling is the **user-visible contract**:

| Action | Bindings |
| --- | --- |
| Apply the selected item | `Space` / `Enter` / double-click; **`Tab` when exactly one item remains** |
| Select previous item | `Up` / `Shift+Tab` / `Ctrl+u` / `Ctrl+p` / `Ctrl+k` |
| Select next item | `Down` / `Tab` / `Ctrl+d` / `Ctrl+n` / `Ctrl+j` |
| Move the filter cursor | `Left` / `Right` / `Home` / `End` |
| Delete a filter character | `Backspace` (before cursor) / `Delete` (after cursor) |
| Exit the menu | `Esc` / `Ctrl+c`; `Backspace` / `Delete` when the filter is empty |

| Mouse | Behavior |
| --- | --- |
| Wheel | moves the selection; scrolls the description box when over it |
| Left click | selects the item under the cursor |
| Double-click (within 400 ms) | applies the selected item |

## 2. Data contract

### input.json (PowerShell → Rust, UTF-8)

```json
{
  "items": [
    { "completion_text": "add", "list_item_text": "add", "symbol": "~", "result_type": 16 }
  ],
  "config": {
    "filter_hint": "",
    "flags": {
      "enable_list_loop": true,
      "filter_mode": "wildcard",
      "enable_apply_when_single": false,
      "enable_apply_when_no_match": false,
      "show_mode": "auto"
    },
    "context_switch": "~",
    "context_stay": "?",
    "raw_config": { "completion": { "enable_tip": 1 }, "global": {}, "default": {} }
  },
  "terminal": { "cursor": { "x": 0, "y": 5 }, "buffer": { "w": 120, "h": 30 },
                "window": { "top": 0, "h": 30 }, "platform": "windows" }
}
```

> `symbol` is the **display character** for the predict symbol. In **build mode** the engine
> resolves the manifest's `switch`/`stay` keys through `context_switch` / `context_stay` when
> mapping candidates into items; for host-provided items the host supplies the display character
> directly (the engine renders it verbatim). The three tip toggles (`enable_tip` /
> `enable_tip_usage` / `enable_tip_example`) travel in `raw_config`
> (completion → global → default layers) and the engine folds them into `flags` — they are not
> sent directly in `flags`. Installed commands may omit `items` and pass a `build` context
> instead — the engine then builds and ranks the candidates itself
> (`cmd`/`arg_tokens`/`manifest`/`hooks`/`order`).
> `window.top/h` is the visible window (BufferSize spans the whole scrollback); layout space is
> clipped to the visible window.

### output.json (Rust → PowerShell)

```json
{ "status": "selected", "index": 3 }
{ "status": "selected", "index": 3, "completion_text": "add", "result_type": 16 }  // build mode
{ "status": "cancel" }
{ "status": "input", "text": "some-filter" }   // no-match auto-apply: a following append applies the filter text (^ prefix stripped)
{ "status": "min_area" }                        // terminal too small; PowerShell keeps the input line and appends a `#`-commented hint
{ "status": "error", "message": "..." }
```

> **Filter vs. input line**: the filter row is a *filter*, not the input line. `Enter`/`Space`
> always applies the current selection and never submits filter text — the filter only drives
> matching. The only path for filter text to reach the command line is the no-match auto-apply:
> with `enable_apply_when_no_match`, when the filter matches nothing a warning is shown and the
> previous list is restored; pressing a **following key (append)** applies the filter text
> (leading `^` stripped). Hence the `status: input` entry above is produced by that append
> apply, not by Enter.

Optional fields accompany `selected`/`cancel`/`input` when relevant:

- `is_show_above` — whether the menu drew above the cursor (true may cover the prompt region);
  informational only — the module does not act on it. `None` when nothing was drawn
  (min_area / apply-when-single / empty list).
- `covered_top` / `covered_bottom` — the exact covered row range for **minimal restore**
  (only these rows are restored; untouched rows above keep true color). **Their absence means
  nothing was drawn, so the host restores nothing** — writing back would make PSReadLine
  repaint its prediction list (e.g. a no-candidate cancel).
- `alternate` — whether the alternate screen was used (PowerShell then skips buffer save/restore;
  the terminal restores the main screen itself).

Results travel via a temp file (atuin's `--result-file` scheme), avoiding stdout/encoding issues.

### Completion resolve → option resolution (bubbling)

In build mode the engine builds a tree from the manifest (`next` = subcommands, `option` = options,
`global_option` = options shown at every level) and resolves the token path into a context node.
Candidates at a context are: the node's `next`, its **effective option source**, and the tree's
`global_option`.

The **effective option source bubbles up the ancestor chain** (child → parent → … → root):

1. If the current context node has a non-empty `option` array, use it.
2. Otherwise walk up to the parent node; use the nearest ancestor that has a non-empty `option`.
3. If no ancestor has an option, fall back to the tree's root `option` array.

`global_option` items are always appended on top of the effective source.

Example: for `psc config menu enable_append_space`, the context node `enable_append_space` first
resolves its **own** `option` (it declares `--reset` → "Reset this config key to its default.").
A sibling that declared no option (e.g. a hypothetical bare group node) would bubble to `menu`,
then `config` — so a root option named the same as a deeper one never shadows the deeper
declaration. The option a level shows is the one declared at the **nearest** level that has one,
which is what makes per-group / per-key flags (e.g. `--reset`) precise instead of leaking a
root-level flag into deep contexts.

### Tip data (`tip` / `usage` / `example`)

- The input JSON carries `tip` / `usage` / `example` on each item, resolved by the host shell
  from the completion manifest / hooks. The menu draws the selected item's description box
  directly from these fields.
- The engine strips ANSI escapes from the list text and the tip fields when caching them, so
  description text renders cleanly.
- Empty/absent tips stay "unresolved": the layout optimistically assumes a tip may appear and
  only real content is cached.
- `enable_tip=false` → no description box, no tip parsing.
- The menu writes a `HBT` heartbeat line to stderr every 15 s so an idle menu stays alive;
  PowerShell's reader loop times out and kills the process after **30 s without any line**
  as a safety net.

## 3. Rendering strategy

- **Windows**: normally PowerShell saves the "above" or "below" region with `GetBufferContents`
  before spawning; Rust draws the overlay + tip inside that region with ratatui
  `Viewport::Fixed(rect)`; on exit PowerShell `SetBufferContents` restores the covered region.
  When the **alternate screen** is used instead (see `show_mode` below), the buffer
  save/restore is skipped — the terminal restores the main screen itself.
- **Unix**: Rust always uses `Viewport::Fullscreen` + the alternate screen
  (`EnterAlternateScreen`/`LeaveAlternateScreen`); the terminal restores the main screen itself.
  `show_mode`'s rendering intent is ignored — the alternate screen is always used; the value
  still picks the *position* (see below).
- **Alternate-screen decision** (Windows only) follows `show_mode`'s rendering intent:
  `altscreen-follow` / `altscreen-top` / `altscreen-bottom` always use the alternate screen;
  `inline-follow` never does (always renders in the main buffer); `auto` (default) uses it only
  when the space below the cursor cannot fit the minimum menu footprint
  (`core/engine/src/menu/state.rs::below_required`). An invalid value is normalized to `auto`
  by the CLI's `sanitize_config` before it reaches the engine. On Unix the rendering intent is
  moot (always alternate).
- **Menu position** (both the alternate-screen start and the main-buffer offset):
  `inline-follow` / `altscreen-follow` place the menu at the input line and flip above when the
  space above is larger; `auto` renders inline **pinned below** (it never flips in the main
  buffer) and on the alternate screen is delegated to `altscreen-follow`; `altscreen-top` pins
  it to the top; `altscreen-bottom` pins it to the bottom (menu grows upward from the last row).
  The engine enters the alternate screen first (the terminal saves the input-line cursor to
  restore on leave), then moves the cursor to the menu start — so a cursor near the bottom never
  leaves the menu with no usable height.
- **Killed menu process**: when the 30 s watchdog kills the menu, the process never gets to send
  `LeaveAlternateScreen`, so the terminal stays on the alternate screen. PowerShell compensates
  by emitting `ESC[?1049l` right after `Kill()` (harmless when no alternate screen was entered);
  the buffer-restore and cursor-reset then act on the main screen.

### Background coverage & the restore contract

- When the menu opens below the cursor, the engine blanks the viewport underneath with the
  terminal background so PSReadLine's command-history prediction list never shows through. The
  forced-blank mechanics (diff flags, the `draw_tip` clearing constraint) are render internals —
  see `core/engine/src/menu/ui.rs`; the contract is only the behavior: covered text never shows
  through and the description region clears cleanly on the first frame.


## 4. Minimal layout

**no width computation, no configurable width, no following the input cursor**:

- **Pinned to column 0**: the full-width separator line + right scrollbar span the whole line
  and do not move with the cursor.
- **Filter prompt line (own row)**: `>` in **red** ("red = input/selected" language), content in
  the default color; with an empty filter and a hint present, the hint is dimmed (from the psc
  completion's `info.filter_hint`, localized). The row sits on the side nearest the input
  line (bottom for below-facing, top for above-facing).
- **Match highlight**: matched filter characters are drawn segmented in the emphasis color (cyan):
  subsequence mode highlights char-by-char, plain mode takes the first matching substring;
  wildcard mode highlights the literal segments matched between `*`/`**` (the wildcard
  characters themselves are not highlighted).
- **Counter row**: `current(red)/total(default)` + a separator line.
- **Left rail + selection mark**: every row has a `▍` rail (the selected row turns **red**, the
  rest dark grey); the selected row's text is prefixed with a red `>` (echoing the filter row),
  text shifted one column right for the "pop-out" offset — a **double focus marker** with the
  rail, moving with the selection.
- **Selected row**: indicated by the red rail + red brackets together; the text itself is not
  emphasized (bold/underline render inconsistently across terminals).
- **Right proportional scrollbar**: same dark grey `│` as the rail/separators; height ∝
  visible/total (a large list ≈ one line, a small list fills the rail), position ∝ scroll offset
  (offset=0 at top).
- **Description panel (bordered container)**: a dynamic-width rounded-border box (`╭╮╰╯`)
  visually distinct from the completion menu; placed on the side **away from the input** (below
  the list when below-facing, above when above-facing).
  - **Dynamic width**: content width = min(longest natural line, available terminal width), plus
    border/padding; short descriptions shrink the box.
  - **Overflow scroll**: when content exceeds the available height, a proportional scrollbar
    appears in the box's right padding column; the mouse wheel scrolls the description when
    inside the box, the list when inside the list.
  - **Gap coverage**: the description panel sits flush against the menu (its border is the
    separator — there is no gap row), so no stale terminal content can show between them.
- **Colors**: text in the terminal's default foreground; emphasis is **red** (`>` prompts,
  counter position, selected slider) and **cyan** (match highlight); structural grey for
  rail/separators/scrollbar/description border; **yellow** for the no-match warning circle
  (solid `●` shown on the counter row when the filter matches nothing).
- **Orientation**: flips automatically by available space above/below (fzf `--layout=reverse` idea).
- **Mouse**: left click selects; double-click within 400 ms confirms; wheel moves the selection
  (scrolls the description when over the box).
- **Zero width computation**: items left-aligned and truncated at the screen edge; description
  width computed from content, never by scanning the list.
- **Background coverage**: the menu area + description container are covered with forced-blank
  default-background cells so covered terminal text never leaks through. The emission mechanics
  (diff flags, the `"space + ITALIC"` pitfall) are render internals — see
  `core/engine/src/menu/ui.rs`; the contract is only the behavior: covered text never shows
  through.
- **Height allocation (extreme-height adaptation)**: a terminal buffer under **5 rows** is
  reported `min_area` immediately (filter + counter + 1 item need at least 3 rows; the extra
  headroom above the 3-row floor is the entry gate — both the engine and the host use `< 5`);
  **completion items win** — at very tight space the description is dropped and all usable space
  goes to the list. The description box height descends through a few tiers as space shrinks and
  the list is capped (`list_limit`); the concrete row counts / tier thresholds live in
  `core/engine/src/menu/state.rs` and `ui.rs`. Layout space is clipped to the **visible window**
  (module passes `window.top/h`;
  BufferSize spans the whole scrollback).
  - **Input line is never saved/restored**: whatever the orientation, only the covered region is
    saved/restored — the input line (prompt) is never touched. The console buffer stores only
    16-color, so `GetBufferContents`/`SetBufferContents` would corrupt the true-color prompt of
    Oh My Posh/Starship and PSReadLine inline prediction; the input line survives by never being
    touched.
- **Minimal restore**: the exact covered row range is tracked across frames and written as
  `covered_top/bottom` (restore contract in §2); PowerShell restores only those rows, so
  untouched terminal content above keeps its true color.

## 5. Menu config (current)

Live menu behavior is driven by the `menu` config group (`psc config menu <key>`). The values
default as follows (see `design/psc-cli.md` for the full inventory). Boolean keys are **stored as
`1`/`0` numbers**; the `bool` / `true` / `false` below express their logical meaning:

| Key | Type / range | Default | Notes |
| --- | --- | --- | --- |
| `show_mode` | `auto` / `inline-follow` / `altscreen-follow` / `altscreen-top` / `altscreen-bottom` | `auto` | see "Alternate-screen decision & menu position" below |
| `enable_tip` | bool | `true` | master tip switch; `false` → no tip data is shown |
| `enable_tip_usage` | bool | `true` | show the `[Usage]` tip section |
| `enable_tip_example` | bool | `true` | show the `[Example]` tip section |
| `trigger_key` | string | `Tab` | PS re-binds PSReadLine |
| `filter_mode` | `subsequence` / `wildcard` | `wildcard` | see `design/filter-matching.md` |
| `enable_apply_when_single` | bool | `false` | auto-apply when filtering leaves exactly one match (no Enter needed) |
| `enable_apply_when_no_match` | bool | `false` | no-match warning; a following append applies the filter text |
| `enable_list_loop` | bool | `true` | wrap-around scrolling |
| `enable_native_completion` | bool | `true` | use the native completion path |
| `enable_sort_by_history` | bool | `true` | history ordering |
| `enable_cache` | bool | `true` | cache the built completion result (static resolve + hook output) for 10 s, so quickly re-opening the same menu skips the rebuild |
| `enable_append_space` | bool | `true` | append a space after applying |
| `enable_path_trailing_separator` | bool | `true` | trailing `\`/`/` on path completions |

**Result cache** (`enable_cache`, default `true`): the engine caches the **built completion
result** (static resolve + hook output) so re-opening the same menu within 10 s skips the
rebuild — a big win for slow hooks (e.g. scoop scanning ~2700 manifests ≈ 600 ms).

- **Signature** = hash of `cmd` + `arg_tokens` + `treat_last_as_complete` + `manifest` path +
  `manifest` mtime + `hooks.lua` mtime + `cwd` + the per-completion `config` (the same value
  exposed to hooks as `psc.config`; the global config is not part of the signature). `hooks.lua`'s
  *path* is excluded (it is fixed per completion, implied by `cmd`); its *mtime* is included so an
  updated hook invalidates stale results. `manifest` includes the language variant (en-US vs zh-CN).
- **Storage**: one JSON file per signature (`created` + items) in `temp/cache/<hash>.json`.
  Hashes keep file names fixed-size and free of path separators.
- **TTL**: 10 s from the file's `created` timestamp (never refreshed by hits). Expired files are
  removed: the hit file lazily in the load path, the rest swept on each store.
- **Caching applies to every completion** (with or without hooks) — a fast completion pays one
  extra tiny disk read, a slow one skips the rebuild. Disable per-user via
  `psc config menu enable_cache 0`.

Boolean keys are stored as JSON numbers (`1`/`0`); `psc config` accepts only `0`/`1` on input.

**Fixed / not configurable**: the menu is fully Rust-driven with no theme, color, or width
configuration — text uses the terminal default foreground; emphasis is red (`>` prompts, counter
position, selected rail) and cyan (match highlight); structure is dark grey (rail/separators/
scrollbar/description border); items are zero-width (pinned left, truncated). The filter prompt
is `>`, the counter reads `current/total` (separator `/`); the predict-symbol characters
themselves (`~` / `?`) come from the `context` config group. `psc menu` and `psc reset menu` are
not commands.

## 6. Order / history sorting

Ordering lives in the TUI process:

- Per-command order files are named by **URL-encoding the command name**
  (`[uri]::EscapeDataString`, e.g. `git.json`, `foo bar.json` → `foo%20bar.json`), and the shared
  files live in `_shared/` (`_paths.json` / `_commands.json`) so they can never collide with a
  per-command file. Unlike the result cache (hashes), order file names stay readable because the
  command name is short and URL-encoding already keeps them path-safe.
- The module packs `history`/`cmd`/`aliases`/`path` into input.json (`OrderInfo`); the Rust
  menu reads history, counts, and atomically writes the order file on a **background thread**
  while displayed.
- **Ranking runs in the engine**: build mode (manifest candidates) and `--sort` (native-fallback
  items) both apply the same order-file ranking before the menu opens — the module only hands
  the order paths over.
- **Algorithm (two weighted dimensions, multiplied)**:
  - **Smooth time decay** `1 + 120×(rel/total)^8` — continuous gradient (human time perception
    is gradual), sharply peaked at the newest end (the last one or two uses dominate, so
    consecutive runs of a command surface first), a floor of `+1`
    so older use accumulates by pure frequency without being forgotten.
  - **Position weight** `((i+1)/N)^2` — the last position (deepest selection) weights `1.0`; early
    "prefix" positions decay quadratically so `config` in `psc config menu …` is not overcounted.
    The most recent use only breaks ties.
- Only the last 1000 lines are scanned; keys lowercased and quotes stripped. The engine ranks
  items by the order-file value (descending, stable); items without a score keep their order.
- **Three ranking sources**, consulted in order for a non-path item: the **per-command** order
  file (that command's own history, e.g. `git.json`), then `_commands.json` — the shared
  command-use frequency across all commands, used for root-command completion (`g<Tab>`) and as
  the fallback when a command has no per-command entry. Path items bypass all three and rank by
  leaf name against `_paths.json` instead.
- **Shared files apply only while the first token is being completed** — root-command completion
  (`g<Tab>`) and path completion (`.\src\<Tab>`), whose candidates are command names or real paths.
  The engine derives this from the raw input tokens the module passes with each request (one
  unfinished token = still completing the first one); in
  **build mode** and in **native mode once the command is complete** (`npm <Tab>`, candidates are
  the tool's own subcommands/options/values), only the per-command order file is consulted — a
  subcommand such as `npm ls` must not pick up the root-command frequency of `ls` from
  `_commands.json` (nor a path score from `_paths.json`). Unscored candidates keep their manifest
  order (stable sort).
- **Path items** (containing `/` or `\`) rank by segment name against `_paths.json` — the shared
  path-use history scores **every segment** of a path token, not just the leaf: `.\scripts\build.ps1`
  credits both `scripts` and `build.ps1`. A **directory** candidate (trailing separator, e.g.
  `.\src\`) ranks under its own name (`src`), so frequently entered directories (and their files)
  surface first at every level of completion.

## 7. Engineering structure (current)

```
core/engine/                 # psc-menu crate: engine + TUI
├── Cargo.toml
└── src/
    ├── lib.rs
    ├── engine/
    │   ├── completion.rs    # tree building + context resolution
    │   └── hooks/           # Lua hook runtime + psc.* API
    │       ├── mod.rs       # types + run_hook entry
    │       ├── runner.rs    # sandbox + execution (deadline, instruction hook)
    │       ├── bindings.rs  # psc table construction (context values + API bindings)
    │       ├── api/         # capability functions
    │       │   ├── mod.rs   # shared helpers + re-exports
    │       │   ├── run.rs   # run family
    │       │   ├── fs.rs    # file-system family
    │       │   ├── formats.rs # json/toml/yaml + psc.log
    │       │   └── items.rs # item-building family
    │       ├── helpers.rs   # helper functions (trim/typed/mount_items/...)
    │       └── tests.rs     # tests
    └── menu/
        ├── app.rs           # key loop + state transitions
        ├── state.rs         # selection/page/offset/filter state (+ match_segments)
        ├── ui.rs            # layout & drawing (platform branches: Fixed / Fullscreen)
        ├── model.rs         # Input/Output serde structs (+ OrderInfo)
        ├── order.rs         # history ordering (background thread)
        └── filter.rs        # filter matching (see design/filter-matching.md)

module/PSCompletions/bin/<platform>-<arch>/psc-menu(.exe)
```

The workspace `core/Cargo.toml` sets the release profile: `opt-level = "z"`, `lto = true`,
`codegen-units = 1`, `strip = true`, `panic = "abort"`.

## 8. Robustness

- release uses `panic = "abort"` (so `catch_unwind` is inert); `main` installs a **panic hook**
  that writes `{"status":"error"}` to output.json before aborting, so a crash never looks like a
  silent death (diagnose with `--panic-test`).
- The `HBT` heartbeat writes to stderr with non-panicking `writeln!`; a closed pipe does not crash.
- PowerShell: a process that exits cleanly without output.json is treated as **cancel** (usually
  the user Ctrl+C'ing the subprocess) — no RawUI fallback; timeout/exception still fail.

## 9. Known constraints & decisions

- `Viewport::Fixed` relies on the buffer size PowerShell passes; a resize mid-menu uses the passed
  value.
- Config numeric fields are `i32`, stored as JSON numbers.
- Layout is "optimistically has tip" while a tip is unresolved (list compressed); an item without
  a tip leaves right-side space, recomputed at the next filter.
- PowerShell 5.1's `$IsWindows` is empty; platform detection uses `$PSEdition -eq 'Desktop' -or $IsWindows`.
- Rust failures show an error and return — there is no RawUI menu fallback.
- A single keypress on Windows emits Press+Release events; `handle_key` ignores
  `KeyEventKind::Release` so a key moves the selection exactly one step.
- On exit, `show_module_menu` restores the cursor (Rust's `SetBufferContents`-based restore only
  covers content); the prompt is not repainted manually.
