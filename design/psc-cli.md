# Design: psc CLI (platform-agnostic core)

> Status: **current**. The `psc` management CLI lives in Rust (`core/cli`); PowerShell is a thin
> bridge. This is the authoritative reference for the CLI — architecture and the full command
> surface as it runs today.
> Related docs: `design/hooks.md` (hooks), `design/menu.md` (menu/TUI), `design/filter-matching.md` (filter).

## 1. Goal

Make the module's self-management CLI (`psc add …`, `psc config …`, …) a **platform-agnostic
Rust executable**, so the same core serves PowerShell today and any other shell/CLI host later.
PowerShell keeps only host-specific integration (interactive menu, `trigger_key` re-binding,
module self-update, spawning).

## 2. Architecture: separate binaries — do NOT nest the CLI under `psc-menu`

`psc-menu` is a **hot path**: it is spawned on every Tab keystroke. It must stay small and start
fast. The management CLI needs **HTTP (reqwest + TLS)**, which would add megabytes and TLS-init
cost to every completion invocation if merged into the same binary. They also have different
lifecycles, and future shells need only the engine.

- `psc-menu` (`core/engine`): **no HTTP**. Pure compute + display. Stays lean.
- `psc` (`core/cli`): the executable implements the whole `psc` command surface; no PowerShell
  logic is needed to "register" the subcommands (see the Dispatch section below for the host
  entry point). Adds `reqwest` (rustls) only here.
- Both link shared workspace crates (single data model, no duplicated parsing).

## 3. Data discovery

The CLI operates on a module data directory, passed by the host:

- Primary: `--data <dir>` argument; fallback: env `PSC_DATA_DIR`.
- Files the CLI reads/writes (all under `<data>`):
  - `settings.json` — local completion list (`alias`), all config (`config`, incl. `config.completion`).
    Written **atomically** (pid-suffixed temp file + rename) so a crash mid-write can never leave a
    half-written file; a corrupt file is backed up to `settings.json.corrupt` on load and defaults
    are used instead of silently dropping the damaged content. Concurrent `psc` processes writing
    the same file are last-write-wins — avoid racing two config edits.
  - `temp/completions.json` — remote index (`update` versions + `meta` per completion: stable `id`,
    url/description per language).
  - `temp/library-changes.json` — single JSON recording library state changes for the module:
    `{ update, added, removed, renamed: [[old, new], ...] }`.
  - `temp/module-update.txt`, `temp/last-update.txt` — module update tracking.
  - `completions/<name>/` — installed completion files (config.json, language/*.json, hooks.lua, `.update`).
  - `completions/psc/language/<lang>.json` — psc's own manifest (module-side `info` templates).

### Rename detection

Each completion's `config.json` carries a stable `id` (random UUID, generated at creation, never
changed). `temp/completions.json` records it under `meta.<name>.id`. Both `psc update` (real-time)
and the background `check` compare each locally installed completion's `id` against the remote
index: if a local id now maps to a *different* remote name, the completion was **renamed
upstream**. The old name is excluded from `added`/`removed` in `temp/library-changes.json` and
recorded under `renamed: [[old, new], ...]`; the module renders it in the `[Update]` block as
`old -> new`. Running `psc update --old` (or naming the old completion) migrates it automatically —
downloads the new files, moves the per-completion settings (`alias`, `config.completion.<old>`
incl. `enable_hooks`) to the new name, and removes the old directory. Renamed entries persist in
`library-changes.json` until actually migrated (only `added`/`removed` are consumed on display).

## 4. Dispatch

`psc` is a PowerShell function (`PSCompletions`, aliased to `psc` in `PSCompletions.ps1`) in
`module/PSCompletions/PSCompletions.psm1` — the **entry point users type**. The function:

- intercepts every invocation,
- handles some commands natively in PowerShell (no-arg info page, nuclear `--reset`,
  `config menu trigger_key` re-binding, interactive confirms for `add --all` / `rm --all`),
- forwards the rest to the Rust binary `psc.exe` (`core/cli`) via `_forward_psc`, passing
  `--data <data dir>` (and `--json` when structured output is wanted).

### 4.1 Global flags (parsed by Rust `parse_args`)

Stripped from anywhere in the argument list before subcommand dispatch:

| Flag | Meaning |
| --- | --- |
| `--data <dir>` / `--data=<dir>` | Data directory. Overrides `PSC_DATA_DIR` env var. Required by the binary. |
| `--json` | Structured JSON output (used by the PowerShell wrapper). |
| `--language <lang>` | Only used by `init` (bootstrap default language when settings are missing). |
| `--result <file>` | Only used by `init` (write the init JSON payload to a file). |

## 5. Command surface matrix

| Command | Arguments | Options | Network | Implemented in | Notes |
| --- | --- | --- | --- | --- | --- |
| `add` | `<name>...` | `--all` | yes | Rust + PS wrapper | `--all` gets an interactive confirm |
| `rm` | `<name>...` | `--all` | `--all`: no (keeps `psc`) | Rust + PS wrapper | `--all` confirms; `psc` itself is always kept |
| `update` | `[<name>...]` | `--all`, `--old` | yes | Rust + PS wrapper | no-arg = real-time check |
| `list` | — | — | no | Rust + PS wrapper | local aggregate; `--json` |
| `info` | `<name>...` | — | no | Rust + PS wrapper | includes `Path` |
| `config` | `[core\|menu\|context] <key> [<value>]` | `--reset` | no | Rust + PS wrapper | all config keys, grouped |
| `completion` | `[<name> [<key> [<value>]]]` | `--reset` | no | Rust + PS wrapper | per-completion special config |
| `alias` | `[add <name> <alias>...\|rm <name> <alias>...]` | `--reset` | no | Rust + PS wrapper | no-arg lists all |
| `--reset` | — | — | no | **PS only** | nuclear reset, top-level flag |
| `init` | — | — | no | Rust | internal, module bootstrap |
| `check` | — | — | yes | Rust | internal, background update check |
| *(no args)* | — | — | — | PS | re-init + interactive info page |

## 6. Per-command reference

Syntax notation: `<value>` = required argument, `[<value>]` = optional, `...` = one or more, `|` = alternatives.

### 6.1 `add` — install completions

```
psc add <name>...
psc add --all
```

- **Behavior**: downloads the remote index, then installs each named completion. `--all` installs every available completion, with an interactive confirm.
  Each installed completion: files are copied into `completions/<name>/`, `.update` records the
  remote version, and settings are refreshed (`refresh_settings_after_add` builds the
  trigger-alias map). An already-installed name follows the update path (no error).
- **Errors**: no args → `Too few parameters.`; unknown name → `<name> is not an available completion.`;
  download failure → `error: <err>`.
- **Output**: with `--json`, per-completion results `{completion, ok, error}`; plain text
  `<name>: Added.` otherwise. Any error → exit code `FAILURE`.
- **PS wrapper**: computes targets (if `--all`, all known completions; else the args), shows the
  `--all` confirm + a "please wait" notice, forwards with `--json`, then `init_data()` and renders
  the rich `info.add.done` / `info.update.done` template per added completion.

### 6.2 `alias` — manage trigger aliases

```
psc alias                           # list all trigger aliases
psc alias add <name> <alias>...
psc alias rm  <name> <alias>...
psc alias --reset                   # restore every completion's aliases
```

- **Behavior**: no-arg lists `name: alias1 alias2` (JSON: `[{completion, aliases}]`).
  `add`/`rm` operate on a single installed completion (the name must be in `settings.alias`).
  `--reset` restores every completion's aliases from its `config.json` `alias` array (falling back
  to the bare name). Alias has only `add`/`rm` as subcommands — a bare completion name under
  `alias` is not a valid form (`alias <name>` / `alias <name> --reset` → `Invalid subcommand.`).
- **Validation (add)**: no wildcards (`*`/`?`); the reserved name `PSCompletions` is rejected;
  an alias already present for that completion is rejected; an alias colliding with another
  completion's trigger alias is rejected (`cmd_exist`).
- **Validation (rm)**: refuses to remove the last remaining alias of a completion (`alias_unique`).
- **Errors**: too few params → `Too few parameters.`; name not installed →
  `<name>: Completion not added.`; per-alias errors: `has_wildcard`, `cmd_exist`, `alias_exist`.
- **PS wrapper**: `alias add` pre-checks for collisions with real commands (`cmd_exist`, before
  forwarding); no-arg lists all trigger aliases wrapped as `{Completion, Alias}` objects; other
  invocations forward raw.

### 6.3 `completion` — per-completion special configuration

```
psc completion                       # completions with non-default special config
psc completion <name>                # that completion's special config
psc completion <name> <key>          # get value
psc completion <name> <key> <value>  # set value
psc completion --reset               # reset all completions' special config
psc completion <name> --reset        # reset one completion's special config
psc completion <name> <key> --reset  # reset one key
```

- **Keys** (`COMPLETION_KEYS`): `language`, `enable_tip`, `enable_tip_usage`, `enable_tip_example`,
  plus `enable_hooks` — valid only when the completion's `config.json` declares `hooks` (setting it
  elsewhere is rejected); absent means enabled, `false`/`0` disables that completion's hooks. Keys
  that already exist in `config.completion[<name>]` are also accepted (per-completion hooks config,
  etc.). **`psc`'s own hooks cannot be disabled** (`psc completion psc enable_hooks 0` is rejected) —
  they power the module's management completions.
- **Validation**: `<name>` must be installed; `enable_`/`disable_` keys accept only the numbers
  `0`/`1` and are stored as JSON numbers (same as `config` boolean keys).
- **Output**: no-arg → `name: language=zh-CN enable_tip=0` (JSON: `[{completion, config}]`);
  get → `key: value` (JSON `{completion, key, value}`); set → `Completion config updated.`.
- **PS wrapper**: `completion <name> <key>` (3 args) prints the value only; reset/set forwards raw.

### 6.4 `config` — module configuration

```
psc config [core|menu|context]        # list all keys in a group
psc config <group> <key>              # get value
psc config <group> <key> <value>      # set value
psc config --reset                    # reset all keys to defaults
psc config <group> --reset            # reset all keys in a group
psc config <group> <key> --reset      # reset one key
```

- **Groups** (`CONFIG_GROUPS`): `core`, `menu`, `context` — open namespaces (a future domain is a
  new group, never a reshaped existing one).
- **Validation** (in Rust): `language` non-empty; `url` empty or `http(s)://…`;
  `show_mode` ∈ `auto|inline-follow|altscreen-follow|altscreen-top|altscreen-bottom`; `filter_mode` ∈ `subsequence|wildcard`;
  `enable_*` values `0`/`1`. Boolean keys are stored as JSON numbers (`1`/`0`).
- **Output**: list → per group a `[group]` header, then `  key: value` per line
  (JSON: `[{group, key, value}, …]`); get → `key: value` (JSON `{key, value}`); set →
  `Module config updated.`
- **PS wrapper**: no-arg → objects `{Key, Value}`; `config <group> <key>` (2 args) prints the
  value only; `--reset`/set forwards raw. Setting `trigger_key` re-binds PSReadLine
  (`Set-PSReadLineKeyHandler`) — validated via an actual binding attempt before Rust persists it.

### 6.5 `info` — completion metadata

```
psc info <name>...
```

- **Behavior**: per name, prints (when present): `Name`, `Alias`, `Url`, `Description` (from
  remote index meta, localized), `Path` (if installed), `Update` (remote version in `.update`),
  `Updated` (unix timestamp of `.update`).
- **Errors**: no args → `Too few parameters.`; a name that is neither installed/linked nor in the
  remote library → `<name> is not an available completion.` (FAILURE).
- **PS wrapper**: converts each entry to `{Name, Alias, Url, Description, Path, Update, Updated}`
  with `Updated` as a local `DateTimeOffset`.

### 6.6 `list` — installed completions

```
psc list
```

- **Behavior**: prints installed completion names plus extra trigger aliases: `name  alias1 alias2`.
- **Output**: text default; `--json` → `[{completion, aliases}]`.
- **PS wrapper**: → `{Completion, Alias}`.

### 6.7 `rm` — remove completions

```
psc rm <name>...
psc rm --all
```

- **Behavior**: `--all` removes every installed completion except `psc` itself (interactive
  confirm; `psc` is kept — it is the module's own completion and init re-adds it anyway, so no
  network re-fetch happens here); otherwise the named ones. Each removal drops the entry from
  `settings.alias` and `config.completion`, removes the name from `temp/library-changes.json`
  (`update`), and removes the completion entry from disk. `rm --all` with nothing to remove
  (e.g. only `psc` installed) is a silent no-op.
- **Data/directory sync**: `rm` treats a name as present if it is registered in `settings.alias`
  **or** its entry exists on disk. A directory that exists without a config entry (manual copy or
  a link whose config drifted) is still removed — the explicit name is the user's intent, and
  `rm` doubles as drift repair. A name with neither is an error.
- **Link handling**: a completion that is a symlink/junction (a local-dev link from
  `scripts/link-completion.ps1`) is removed **as a link only** — the linked local source stays
  intact. `symlink_metadata().is_symlink()` detects junctions too (Windows junction is reported
  as a symlink), and link removal never touches the target.
- **Errors**: no args → `Too few parameters.`; name in neither the registry nor the remote
  library → `<name> is not an available completion.`; in the remote library but not installed →
  `<name>: Completion not added.`
- **Output**: the Rust binary prints `Removed.` once — only if at least one completion was
  actually removed (a fully-failed `rm` prints only the errors and exits `FAILURE`); the PS
  wrapper renders `info.rm.done` per removed completion.

### 6.8 `update` — update completions

```
psc update                    # real-time library check, no write
psc update <name>...          # update named completions (naming = intent to update)
psc update --old              # update every out-of-date completion
psc update --all              # update every installed completion
```

- **Behavior**: always downloads the index first. A completion is "out of date" when its local
  `.update` differs from the remote version (symlinked completions are skipped).
  - **Named update** (`update <name>...`): updates the named completions **unconditionally** —
    naming a completion IS the intent to update it (also the way to repair a corrupted or
    manually-removed file).
  - **`--old`**: updates only the **out-of-date** completions (the normal "keep everything
    current" path).
  - **`--all`**: updates **every installed** completion (a full sweep).
  - **No-arg = real-time check**: writes `temp/library-changes.json` and reports the library
    status (out-of-date completions + newly added/removed/renamed completions), mirroring the
    startup notification.
  - After any successful update, the remaining out-of-date names are written back to
    `temp/library-changes.json` (`update`) so the next startup does not re-report them.
- **Errors**: name not installed and not in the remote list → `<name> is not an available completion.`;
  installed but not in the remote list → `<name>: Completion not added.`; download failure →
  `error: <err>`.
- **Output**: with `--json`, per-completion results `{completion, ok, error}` (renames add
  `renamed_from`); plain text otherwise. Any failure → exit `FAILURE`.
- **PS wrapper**: forwards `--all` / `--old` / the named arguments with `--json`, then renders
  `info.update.done` per successful result (migrated renames show `old -> new` in the name line),
  red errors for failures — so a partial failure still shows the successful ones.

### 6.9 `--reset` — nuclear reset (PowerShell only, top-level flag)

```
psc --reset
```

- Implemented in the psm1 switch (not Rust). Shows an interactive confirmation; on Enter it
  deletes the module data directory contents (everything except module source) and re-initializes.


### 6.10 `init` / `check` — internal commands (not user-facing)

- `init`: bootstraps `settings.json` when missing/empty (default data from the installed
  completions dir and a language hint), builds `aliasMap`, reads `temp/module-update.txt`, resolves
  URLs, loads the psc `info` templates, sanitizes the config, and emits one large JSON payload (or
  writes it to `--result`). Called by the module on import. The payload includes `new_version` (the
  newer module version found by a previous `check`, or `null`) so the module's update notification
  reads it from the parsed data. Library state changes are read separately by the module from
  `temp/library-changes.json` (`render_library_changes`), not via this payload.
- `check`: background update check gated by `temp/last-update.txt` (runs at most every 6 hours).
  Refreshes `temp/completions.json`, writes the added/removed diff, the out-of-date list, and the
  renamed completions (same id-based detection as `psc update`) to `temp/library-changes.json`,
  checks the module version against the **running** module version (passed as `check <version>`,
  compared against `module/version.json` via `--data`'s urls, with the project site as an extra
  fallback) into `temp/module-update.txt`.

### 6.11 `psc` with no arguments

- PowerShell default branch: prints the module info page (`_help`). Not a management command.
  The full init sequence (`init_data()` → `start_job()` → `handle_completion()`) runs once at
  module **import time**, not per no-arg call.
- Rust binary run with no arguments prints a bare `print_help` fallback (usage lines only); it is
  not a subcommand — the module wrapper intercepts the no-arg case before reaching the binary.

## 7. Configuration inventory (current)

All keys live in one object (`settings.json` → `config`), managed through `config <group> <key>`.

**`core`** (tool-level, distribution-agnostic):

| Key | Type / range | Default |
| --- | --- | --- |
| `url` | string, empty or `http(s)://…` | `""` (auto GitHub/Gitee by language) |
| `language` | string | `en-US` (Rust fallback; the module bootstraps `$PSUICulture` via `--language` at init) |
| `enable_auto_alias_setup` | bool | `true` |

**`menu`** (completion menu):

| Key | Type / range | Default |
| --- | --- | --- |
| `show_mode` | `auto` / `inline-follow` / `altscreen-follow` / `altscreen-top` / `altscreen-bottom` | `auto` |
| `enable_tip` | bool | `true` |
| `enable_tip_usage` | bool | `true` |
| `enable_tip_example` | bool | `true` |
| `trigger_key` | string | `Tab` |
| `filter_mode` | `subsequence` / `wildcard` | `wildcard` |
| `enable_apply_when_single` | bool | `false` |
| `enable_apply_when_no_match` | bool | `false` |
| `enable_list_loop` | bool | `true` |
| `enable_native_completion` | bool | `true` |
| `enable_sort_by_history` | bool | `true` |
| `enable_cache` | bool | `true` |
| `enable_append_space` | bool | `true` |
| `enable_path_trailing_separator` | bool | `true` |
| `color_focus` | string | `red` |
| `color_match` | string | `cyan` |

**`context`** (context indicator symbols):

| Key | Type / range | Default |
| --- | --- | --- |
| `switch` | string | `~` |
| `stay` | string | `?` |

Per-completion special config (separate `config.completion[<name>]` object, managed by
`completion`): `language`, `enable_tip`, `enable_tip_usage`, `enable_tip_example`, plus
per-completion custom keys (`enable_hooks` and any `config` keys the manifest defines).

`enable_hooks` needs no entry in `config.completion` to take effect (unlike the four standard
keys it is not auto-seeded — absent means "enabled"; the one exception is a
`config.json` declaring `"hooks": false`, which seeds `enable_hooks=false` on first install so the
completion's dynamic hooks are disabled by default), but it is valid **only** on a completion
whose `config.json` declares `hooks`. The module runs a completion's `hooks.lua`
only when the file exists **and** `config.completion[<name>].enable_hooks` is not `false`.
Absent or unset defaults to enabled; setting it to `false` (or `0`) disables that completion's
hooks without touching the files. `completion --reset` restores it by removing the stored value
(back to enabled — or back to `false` for a `"hooks": false` completion, whose declared default is
disabled). Setting or reading `enable_hooks` on a completion whose `config.json` does not declare
`hooks` is rejected (`This completion has no dynamic hooks.`) and is not written.

## 8. Reset matrix (current)

| Target | Command |
| --- | --- |
| Any config key — all | `config --reset` (skips `language`) |
| Any config key — a group | `config <group> --reset` (skips `language`) |
| Any config key — one | `config <group> <key> --reset` (`language` is rejected) |
| Per-completion config — all | `completion --reset` |
| Per-completion config — one completion / key | `completion <name> --reset` / `completion <name> <key> --reset` |
| Aliases — all | `alias --reset` |
| Everything | `psc --reset` (interactive) |

`language` is **not resettable**: it has no fixed default in the config registry — the module
bootstraps it from `$PSUICulture` via `--language` at init, and Rust falls back to `en-US` when
no language is supplied. All/group resets skip it; `config <group> language --reset` is rejected.
The completion also omits `--reset` for the `language` key (the psc hook removes the bubbled-up
option at that level).

The completion order file is **not** resettable by design — it is a transient cache, regenerated
on demand.

## 9. Output & localization

- Embedded bilingual (en/zh) CLI messages (`msg_cli`) — the psc manifest `info` templates are
  bound to PowerShell expressions (`$PSCompletions.*`) and cannot be evaluated by a Rust CLI.
- **All output (including error text) goes to stdout; success/failure is expressed by the exit
  code.** Error messages are rendered by the PowerShell wrapper as readable colored hints —
  deliberately **not** written to stderr: PowerShell (5.1, and 7.3+ with
  `$PSNativeCommandUseErrorActionPreference`) treats native stderr as an error stream (red
  `ErrorRecord`s, possible exceptions), which would break the interactive UX this CLI hosts.
  (One exception: running the bare binary without `--data`/`PSC_DATA_DIR` prints a usage note to
  stderr — the module path always passes `--data`, so this never happens in normal use.)
- Text by default; query commands (`list`/`info`/`config`/`completion`/`alias`) accept `--json`.
  Action/status commands judge success by **exit code**.
- ANSI color when stdout is a TTY, stripped otherwise.

## 10. PowerShell module bridge

- `PSCompletions` function: no-arg → interactive info page (unchanged); with args → spawn
  `psc <args>` via `_forward_psc` (pass `--data <module data dir>`), forward stdout/stderr/exit.
- `config menu trigger_key` re-binds PSReadLine (`Set-PSReadLineKeyHandler`) — the one host-side
  validation that stays in PowerShell (validate-then-persist).
- Interactive confirms for `add --all` and `rm --all` in the wrapper.
- Module self-update stays PowerShell (PowerShellGet/git).

## 11. Workspace layout (current)

```
core/
├── Cargo.toml            # [workspace] members = ["engine", "cli"]
├── engine/               # psc-menu: engine + TUI (no network deps)
│   └── src/{lib.rs, engine/, menu/, bin/psc-menu.rs}
└── cli/                  # psc: data layer + commands + reqwest
    └── src/{lib.rs, data/, net.rs, bin/psc.rs}

design/                   # design docs (this directory)
└── *.md
```

## 12. Risks & validation

- **Behavior parity**: each command reproduces param validation, localized messages, and exit
  semantics.
- **Data rebuild**: `add`/`rm`/`alias` trigger a settings rebuild + `refresh_settings_after_add`
  so module state stays consistent.
- Validation: Rust unit tests in `core/cli` cover settings/completions.json parsing and the
  settings rebuild; the module's behavior is exercised end-to-end by `scripts/check-completion.ps1`
  and manual smoke runs of each command.
