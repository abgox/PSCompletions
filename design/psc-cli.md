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
- Both link the shared `psc-common` crate (BOM-tolerant text reads).

## 3. Data discovery

The CLI operates on one resolved data directory. The PowerShell host resolves it once and always passes it explicitly:

- `PSCOMPLETIONS_DATA_DIR` — optional install-time/user override read by the PowerShell host when non-empty.
- Otherwise the host uses the platform default: `%APPDATA%\com.abgox\PSCompletions` on Windows,
  `~/Library/Application Support/com.abgox/PSCompletions` on macOS, and
  `${XDG_DATA_HOME:-$HOME/.local/share}/com.abgox/PSCompletions` on Linux.
- The host passes the resolved directory as `--data <dir>` to `psc`; the Rust binary keeps its
  existing direct-invocation fallback to the same environment variable when no `--data` is given.
- Files the CLI reads/writes (all under `<data>`):
  - `settings.json` — local completion list (`alias`), all config (`config`, incl. `config.completion`).
    Written **atomically** (pid-suffixed temp file + rename) so a crash mid-write can never leave a
    half-written file; a corrupt file is backed up to `settings.json.corrupt` on load and defaults
    are used instead of silently dropping the damaged content. Concurrent `psc` processes writing
    the same file are last-write-wins — avoid racing two config edits.
  - `temp/completions.json` — remote index (`update` versions + `meta` per completion: stable `id`,
    url/description per language).
  - `temp/change.json` — single JSON recording pending notifications for the module:
    `{ update, added, removed, renamed: [[old, new], ...], module: "x.y.z", last_check: <unix-timestamp> }`.
    `module` is the newest remote module version whenever it was fetched (the module compares it
    against its installed version at render time; on a fetch failure the previous value is kept).
    `last_check` is stamped by every `add`/`update` and drives the menu's stale-update hint
    (when older than 7 days). Loading is per-field tolerant (one malformed field falls back
    to its own default); unparseable content is backed up to `change.json.corrupt`.
   - `temp/order/` — per-command history-order caches (menu ranking). Rebuilt on use; the menu
    engine prunes stale files (older than 90 days) in a background thread on each menu open
    (`cleanup_stale_order_files`), so it never delays the TUI.
  - `temp/menu/` — transient menu input/output.json files. Deleted immediately after each menu;
    the menu engine prunes stale files (older than 30 minutes, e.g. left by a force-closed
    terminal) in a background thread on each menu open (`cleanup_stale_menu_files`).
  - `completions/<name>/` — installed completion files (config.json, language/*.json, hooks.lua, `.update`).
  - `temp/*.<pid>.tmp` + `completions/*.<pid>.old` — crash residue from staged downloads
    (a killed process never cleans its own staging); swept when older than a day on
    `add`/`update`/`init` runs (the only commands that stage anything).
  - `completions/psc/language/<lang>.json` — psc's own manifest (module-side `info` templates).

### Rename detection

Each completion's `config.json` carries a stable `id` (random UUID, generated at creation, never
changed). `temp/completions.json` records it under `meta.<name>.id`. `psc update` (real-time)
compares each locally installed completion's `id` against the remote
index: if a local id now maps to a *different* remote name, the completion was **renamed
upstream**. The old name is excluded from `added`/`removed` in `temp/change.json` and
recorded under `renamed: [[old, new], ...]`; the module renders it in the `[Update]` block as
`old -> new`. Running `psc update --old` (or naming the old completion) migrates it automatically —
downloads the new files, moves the per-completion settings (`alias`, `config.completion.<old>`
incl. `enable_hooks`) to the new name, and removes the old directory. Renamed entries persist in
`change.json` until actually migrated (only `added`/`removed` are consumed on display).

## 4. Dispatch

`psc` is a PowerShell function (`PSCompletions`, aliased to `psc` in `PSCompletions.ps1`) in
`module/PSCompletions/PSCompletions.psm1` — the **entry point users type**. The function:

- intercepts every invocation,
- handles some commands natively in PowerShell (no-arg info page, nuclear `--reset`,
  `config menu trigger_key` re-binding, interactive confirm for `rm --all`),
- forwards the rest to the Rust binary `psc.exe` (`core/cli`) via `_forward_psc`, passing
  `--data <data dir>` (and `--json` when structured output is wanted).

### 4.1 Global flags (parsed by Rust `parse_args`)

Stripped from anywhere in the argument list before subcommand dispatch:

| Flag | Meaning |
| --- | --- |
| `--data <dir>` / `--data=<dir>` | Data directory. The PowerShell host always passes its resolved directory; when invoking the binary directly, this overrides `PSCOMPLETIONS_DATA_DIR`. |
| `--json` | Structured JSON output (used by the PowerShell wrapper) — the contract is [`json.md`](json.md). |
| `--yes` | Authorise a destructive operation (`rm --all`, any `--reset`). The engine never prompts: the hosts ask the human and add this flag themselves. |
| `--language <lang>` | Only used by `init` (bootstrap default language when settings are missing). |
| `--result <file>` | Only used by `init` (write the init JSON payload to a file). |

## 5. Command surface matrix

| Command | Arguments | Options | Network | Implemented in | Notes |
| --- | --- | --- | --- | --- | --- |
| `add` | `<name>...` | — | yes | Rust + PS wrapper | installs each named completion |
| `rm` | `<name>...` | `--all` | no | Rust + PS wrapper | `--all` is confirmed by the host, which then passes `--yes`; `psc` itself is always kept |
| `update` | `[<name>...]` | `--all`, `--old` | yes | Rust + PS wrapper | no-arg = real-time check |
| `list` | — | — | no | Rust + PS wrapper | local aggregate; `--json` |
| `info` | `[<name>...]` | — | no | Rust + PS wrapper | no-arg = list all installed; includes `Path` |
| `config` | `[core\|menu\|context] <key> [<value>]` | `--reset` | no | Rust + PS wrapper | all config keys, grouped |
| `completion` | `[<name> [<key> [<value>]]]` | `--reset` | no | Rust + PS wrapper | per-completion special config |
| `alias` | `[add <name> <alias>...\|rm <name> <alias>...]` | `--reset` | no | Rust + PS wrapper | no-arg lists all |
| `--reset` | — | — | no | **Host only** | nuclear reset, performed by the host itself — it never reaches the engine |
| `init` | — | — | on missing psc files | Rust | internal, module bootstrap |
| `tpl` | `<dotted.info.path>` | `--ctx <json>`, `--no-color` | no | Rust | internal, renders one `info` template for a host |
| *(no args)* | — | — | — | PS | re-init + interactive info page |

Every destructive operation (`rm --all`, any `--reset`) needs `--yes` in the engine; the hosts ask
the human and add it themselves ([`json.md`](json.md) §7).

## 6. Per-command reference

Syntax notation: `<value>` = required argument, `[<value>]` = optional, `...` = one or more, `|` = alternatives.

### 6.1 `add` — install completions

```
psc add <name>...
```

- **Behavior**: downloads the remote index, then installs each named completion.
  Multiple completions download concurrently (8 workers) and each completion's files
  download in parallel.
  Each installed completion: files are copied into `completions/<name>/`, `.update` records the
  remote version, and settings are refreshed (`refresh_settings_after_add` builds the
  trigger-alias map). `add` always reinstalls: the whole per-completion entry (trigger
  aliases + `config.completion`) is dropped and rebuilt from remote defaults (like `rm` +
  `add`; customizations are reset). An already-installed name is reinstalled without error
  and still reports `Added.`.
- **Errors**: no args → `Too few parameters.`; unknown name → `<name>: is not an available completion.`;
  download failure → `error: <err>`. A downloaded `config.json` without a usable `id`
  is refused — nothing lands, the installed version stays intact.
- **Output**: with `--json`, `data.completions` carries one result per name — `{name, ok, error?}`;
  plain text `<name>: Added.` otherwise. A failed item fails the run:
  exit code `1` ([`json.md`](json.md) §6).
- **PS wrapper**: forwards with `--json`, then `init_data()` and renders
  the rich `info.add.done` / `info.update.done` template per added completion.

### 6.2 `alias` — manage trigger aliases

```
psc alias                           # list all trigger aliases
psc alias add <name> <alias>...
psc alias rm  <name> <alias>...
psc alias --reset                   # restore every completion's aliases
```

- **Behavior**: no-arg lists `name: alias1 alias2` (JSON: `{"aliases": [{name, alias}]}`).
  Trigger aliases only open the completion menu — they never create execution
  aliases (execution aliases are the user's own `Set-Alias` business).
  `add`/`rm` operate on a single installed completion (the name must be in `settings.alias`).
  `--reset` restores every completion's aliases from its `config.json` `alias` array (falling back
  to the bare name). Alias has only `add`/`rm` as subcommands — a bare completion name under
  `alias` is not a valid form (`alias <name>` / `alias <name> --reset` → `Invalid subcommand.`).
- **Validation (add)**: no wildcards (`*`/`?`); the reserved name `PSCompletions` is rejected.
  Nothing else is rejected: a word another completion claims, and a word the completion already
  has, are both accepted — see the claim order below.
- **Claim order decides: the last claim wins.** `settings.alias` is order-preserving and the hosts
  build their `word -> completion` table by inserting in it, so a word two completions claim
  belongs to the one whose claim is later. A **declaration** moves a completion to the end of that
  order: install, `alias add` and `--reset` all do, so re-declaring a word the completion already
  has is the explicit way to take it back from a later claim (the list itself is unchanged).
  `alias rm` is a subtraction, not a declaration, and leaves the order alone. Conflicts are not
  resolved and not reported; `psc alias` lists the current ownership in claim order, which is how
  a user sees that a later completion took a word over.
- **JSON payloads** ([`json.md`](json.md) §8): `add` → `{name, alias, rejected}`, where each
  rejected word carries `{alias, error: {code, message}}`; `rm` → `{name, alias}`;
  `alias <add|rm> <name> --reset` → `{name, alias}`; `alias --reset` → `{aliases}`.
- **Errors**: the envelope's `code` is `too_few_params` / `invalid_subcommand` / `not_installed`;
  per-alias codes are `alias_wildcard`, `alias_reserved`, `alias_not_found`.
- **PS wrapper**: forwards the CLI's text.

### 6.3 `completion` — per-completion special configuration

```
psc completion                       # completions with non-default special config
psc completion <name>                # that completion's special config
psc completion <name> <key>          # get value
psc completion <name> <key> <value>  # set value
psc completion --reset               # reset all completions' special config
psc completion <name> --reset        # reset one completion's special config
psc completion <name> <key> --reset  # reset one key (exactly one; surplus args are rejected)
```

- **Keys** (`COMPLETION_KEYS`): `language`, `enable_tip`, `enable_tip_usage`, `enable_tip_example`,
  plus `enable_hooks` — valid only when the completion's `config.json` declares `hooks` (setting it
  elsewhere is rejected); absent means enabled, `0` disables that completion's hooks. Keys
  that already exist in `config.completion[<name>]` are also accepted (per-completion hooks config,
  etc.). **`psc`'s own hooks cannot be disabled** (`psc completion psc enable_hooks 0` is rejected) —
  they power the module's management completions.
- **Validation**: `<name>` must be installed; `enable_`/`disable_` keys accept only the numbers
  `0`/`1` and are stored as JSON numbers (same as `config` boolean keys).
- **Output**: no-arg → `name: language=zh-CN enable_tip=0`
  (JSON: `{"completions": [{name, config}]}`); get → `key: value`
  (JSON: `{"name", "key", "value"}`); set → `Completion config updated.`
  (JSON: `{"name", "key", "value", "old"}` — the item the get answers with, plus the value it
  replaced); `--reset` → the resulting state, the same shape the read of that scope answers with
  ([`json.md`](json.md) §8).
- **PS wrapper**: forwards the CLI's text; reset/set forwards raw.

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
- **Output**: list → per group a `[group]` header and then its `key: value` rows, both at
  column 0 (JSON: `{"config": [{group, key, value}…]}`); get → `key: value` (JSON `{"key", "value"}`); set →
  `Module config updated.` (JSON `{"key", "value", "old"}` — the item the get answers with, plus the
  value it replaced); `--reset` → the resulting state, the same shape the read of that scope answers
  with ([`json.md`](json.md) §8).
- **PS wrapper**: forwards the CLI's text; `--reset`/set forwards raw. Setting `trigger_key`
  re-binds PSReadLine (`Set-PSReadLineKeyHandler`) — validated via an actual binding attempt
  before Rust persists it.

### 6.5 `info` — completion metadata

```
psc info                # list all installed completions
psc info <name>...      # per-name metadata
```

- **Behavior**: no-arg lists all installed completions (same as `list` but with full metadata
  per entry). Per name, prints (when present): `Alias`, `Url`, `Path` (if installed), `Update`
  (remote version in `.update`), `Updated` (unix timestamp of `.update`), and **last**
  `Description` (from remote index meta, localized) — last because it is the one value authored as
  lines, and a multi-line block between single-line rows reads as a break in the record.
- **Errors**: a name that is neither installed/linked nor in the remote library →
  `<name>: is not an available completion.` A failed entry is an **error line**, not a block entry:
  it names itself and takes no `[name]` heading, even when other names in the run succeed. In both
  modes the run exits `1` (a failed entry fails
  the run, [`json.md`](json.md) §6). The `--json` entry is
  `{name, ok, alias, url, description, path, update, updated}` with `null` for an absent field and
  `{code, message}` for the failure.
- **PS wrapper**: forwards the CLI's text — one presentation for every host, `--json` being the
  machine contract.

### 6.6 `list` — installed completions

```
psc list
```

- **Behavior**: prints the completions **recorded in `settings.alias`** plus their trigger aliases:
  `name: alias1, alias2`. A directory dropped into `completions/` by hand is not listed here — it was
  never recorded — but `rm` still removes it, because `rm` works from the directory (below).
- **Output**: text default; `--json` → `{"completions": [{name, alias}]}`.
- **PS wrapper**: forwards the CLI's text.

### 6.7 `rm` — remove completions

```
psc rm <name>...
psc rm --all                # --all absorbs co-args: extras are ignored
```

- **Behavior**: `--all` removes every installed completion except `psc` itself (the host
  confirms and passes `--yes`; `psc` is kept — it is the module's own completion and init re-adds it anyway, so no
  network re-fetch happens here); otherwise the named ones. Each removal drops the entry from
  `settings.alias` and `config.completion`, drops the name from every notification list in
  `temp/change.json` (`update`/`added`/`removed`/`renamed`), and removes
  the completion entry from disk. `rm --all` with nothing to remove
  (e.g. only `psc` installed) is a silent no-op.
- **Data/directory sync**: `rm` treats a name as present if it is registered in `settings.alias`
  **or** its entry exists on disk (`symlink_metadata`, so a dangling link still counts and can
  be removed). A directory that exists without a config entry (manual copy or
  a link whose config drifted) is still removed — the explicit name is the user's intent, and
  `rm` doubles as drift repair. A name with neither is an error.
- **Link handling**: a completion that is a symlink/junction (a local-dev link from
  `scripts/link-completion.ps1`) is removed **as a link only** — the linked local source stays
  intact. `symlink_metadata().is_symlink()` detects junctions too (Windows junction is reported
  as a symlink), and link removal never touches the target.
- **Name validity**: a name must be a single path-free token — no `/`, `\`, `:`, spaces or control
  characters, and not `.`, `..` or empty. It is validated **before any filesystem access**, so
  `psc rm ..\..\victim` is rejected instead of resolving outside the library directory. An invalid
  name reports the same `<name>: is not an available completion.` as an unknown one. The same rule
  covers `rm` / `update` / `completion` / `alias`.
- **Errors**: no args → `Too few parameters.`; name in neither the registry nor the remote
  library → `<name>: is not an available completion.`; in the remote library but not installed →
  `<name>: Completion not added.`
- **Output**: with `--json`, `data.completions` carries `{name, ok, error?}` per name (an empty
  `rm --all` is a successful no-op with an empty list); the Rust binary prints `Removed.` once in
  text mode — only if at least one completion was actually removed (a fully-failed `rm` prints only
  the errors) — and the PS wrapper renders `info.rm.done` per removed completion. A failed item
  fails the run: exit code `1`.

### 6.8 `update` — update completions

```
psc update                    # real-time library check, no write
psc update <name>...          # update named completions (naming = intent to update)
psc update --old              # update every out-of-date completion
psc update --all              # update every installed completion
```

- **Behavior**: always downloads the index first. A completion is "out of date" when its local
  `.update` differs from the remote version (symlinked completions are skipped).
  - **Named update** (`update <name>...`): re-downloads the named completions
    **unconditionally** — naming a completion IS the intent to update it (also the way to
    repair a corrupted or manually-removed file). A name that exists only in the remote
    index is installed by naming it. Settings are patched, never overwritten:
    a missing/empty trigger entry is filled from remote defaults, per-completion config
    only fills missing keys, and trigger customizations survive. Any non-flag token counts
    as a name (`update --foo` targets a completion literally named `--foo`); `--all` wins
    over `--old` when both are passed, and a **mode flag wins over a name** — a name there is
    redundant, not an error: `--all <name>` re-fetches everything, the name included, and
    `--old <name>` follows the out-of-date set, saying so when that set is empty. A name the flag's
    set cannot cover (`--all <not installed>`) is not installed by the run — `--all` means the
    installed completions.
  - **`--old`**: updates only the **out-of-date** completions (the normal "keep everything
    current" path). Settings are patched as above, never overwritten.
  - **`--all`**: updates every installed completion that exists in the remote `completions.json`
    index (settings patched as above). Completions not found in the remote index (e.g.
    locally-linked or manually-added completions) are silently skipped.
  - **No-arg = real-time check**: writes `temp/change.json` and reports the library
    status (out-of-date completions + newly added/removed/renamed completions), mirroring the
    startup notification.
  - After any successful update, the remaining out-of-date names are written back to
    `temp/change.json` (`update`) so the next startup does not re-report them.
- **Errors**: name not installed and not in the remote list → `<name>: is not an available completion.`;
  installed but not in the remote list → `<name>: is not in the completion library.` (code
  `not_in_library`); download failure →
  `error: <err>`. Same `id` refusal as `add` (nothing lands on failure).
- **Output**: with `--json`, `data.completions` carries `{name, ok, error?}` per name (a migrated
  rename adds `renamed_from`); the no-argument check answers the four library-change lists
  (`update` / `added` / `removed` / `renamed`) instead; plain text otherwise. An empty result set
  (nothing out of date, nothing eligible) prints `All completions are up to date.` in text mode —
  the same reply the no-argument check and the module's `info.update.no` give. A failed item fails
  the run: exit `1`. A locally-linked completion is reported (`ok: false`, code `not_updated`) but
  does not fail the run — a link is a deliberate choice, not an error.
- **PS wrapper**: forwards `--all` / `--old` / the named arguments with `--json`, then renders
  `info.update.done` per successful result (migrated renames show `old -> new` in the name line),
  red errors for failures — so a partial failure still shows the successful ones.

### 6.9 `--reset` — nuclear reset (host-only, top-level flag)

```
psc --reset
```

- Implemented by the hosts (not Rust): the PowerShell switch and each shell bridge. Shows an
  interactive confirmation; on Enter it deletes the resolved data directory contents, restores the
  bundled `psc` completion, and re-initializes. It never reaches the engine, so it needs no
  `--yes`.


### 6.10 `init` — internal command (not user-facing)

- `init`: bootstraps `settings.json` when missing/empty (default data from the installed
  completions dir and a language hint), builds `aliasMap`, resolves
  URLs, loads the psc `info` templates, sanitizes the config, and emits one large JSON payload (or
  writes it to `--result`): `aliasMap`, `urls` (full mirror list) + `url` (first), `info`
  templates, sanitized `config`, and `default_config`. `aliasMap` is built in the `settings.alias`
  claim order, so a word two completions claim resolves to the later claim. Called by the module on
  first completion trigger (lazy initialization,
  not at import time). Library state
  changes are read separately by the module from `temp/change.json`
  (`render_library_changes`), not via this payload. When the psc completion's key files are
  missing, `init` re-fetches them over the network (the only network path in `init`).

### 6.11 `tpl` — internal command (not user-facing)

```
psc tpl <dotted.info.path> [--ctx <json>] [--version <v>] [--no-color] [--markup] [--explain]
psc tpl --stdin [--version <v>] [--no-color] [--markup] [--explain]
psc tpl <path> --lint
```

- **Behavior**: renders one template from the `psc` completion's `info` object
  (`completions/psc/language/<lang>.json`) and prints the result. The language is the `psc`
  completion's own: its declared list decides, a per-completion override beats the module
  language, and `--language`/settings supply the module language.
- **`--ctx`**: the values the template reads (`Version`, `NewVersion`, record lists, counts). The
  engine never invents them — a host knows its own version and its own records. A malformed
  `--ctx` renders as an empty context rather than aborting.
- **`--stdin`**: the same rendering for a host that holds the template *value* rather than a path:
  the request is `{data, ctx, sep}`, so a value with quotes and newlines needs no argument
  quoting, and a large context no argument limit.
- **`--version`**: fills `Version` when the context does not carry one (the module's version lives
  in the module directory, not the data dir). **`--markup`**: leaves the `<@Color>` markup as text
  for a host that colors it itself. **`--lint`** / **`--explain`**: the two authoring checks —
  [`templates.md`](templates.md).
- **Grammar**: the `{{…}}` mini-language, its three value channels, the naming rules and what is
  deliberately absent — [`templates.md`](templates.md). A directive the renderer cannot read keeps
  its whole block, and an expression it cannot read keeps its token, so nothing is ever silently
  dropped.
- `core/cli/tests/fixtures/psc_tpl.json` freezes the rendering of every template that ships.
- **Output**: text on stdout, colored by default (the callers capture stdout, so a TTY test inside
  the engine would answer "no" and silently drop the color); `--no-color` strips the markup. A
  trailing reset follows the colored text. No `--json` form.
- **Failure**: an unknown path prints nothing and exits `1`, so a caller can fall back to its own
  text; a missing path argument prints the usage line and exits `1`.
- **Purpose**: the hosts (the PowerShell module, the shell bridges) name the template and pass
  their data, so the `{{…}}` grammar has exactly one implementation.

### 6.12 `psc` with no arguments

- PowerShell default branch: prints the module info page (`_help`). Not a management command.
  The full init sequence (`init_data()` → alias/trigger-key rebinding) runs once on first
  Tab/psc (**lazy initialization**), not per no-arg call.
- Rust binary run with no arguments prints a bare `print_help` fallback (usage lines only); it is
  not a subcommand — the module wrapper intercepts the no-arg case before reaching the binary.

## 7. Configuration inventory (current)

All keys live in one object (`settings.json` → `config`), managed through `config <group> <key>`.

**`core`** (tool-level, distribution-agnostic):

| Key | Type / range | Default |
| --- | --- | --- |
| `url` | string, empty or `http(s)://…` | `""` (auto: Gitee/GitHub by language, then the Pages root; raw-style bases ending in `main` are tried on the `index` branch first, then the legacy layout; a custom URL is tried as-is). Setting a non-official URL (anything outside the psc manifest's `config core url` candidates, see `design/trust.md`) prints a trust warning. |
| `language` | string | `en-US` (Rust fallback; the module bootstraps `$PSUICulture` via `--language` at init) |

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
`config.json` declaring `"hooks": false`, which seeds `enable_hooks=0` on first install so the
completion's dynamic hooks are disabled by default), but it is valid **only** on a completion
whose `config.json` declares `hooks`. The module runs a completion's `hooks.lua`
only when the file exists **and** `config.completion[<name>].enable_hooks` is not `0`.
Absent or unset defaults to enabled; setting it to `0` disables that completion's
hooks without touching the files. `completion --reset` restores it by removing the stored value
(back to enabled — or back to `0` for a `"hooks": false` completion, whose declared default is
disabled). Setting or reading `enable_hooks` on a completion whose `config.json` does not declare
`hooks` is rejected (`This completion has no dynamic hooks.`) and is not written.

**Fetch policy**: one shared blocking client (30 s timeout, connection pool). Each URL is
retried once on transient failures (connect/timeout/429/5xx, 200 ms pause); other errors are
final. Mirrors are tried in order with per-URL isolation — a slow mirror delays its own slot
only.

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

- Embedded bilingual (en/zh) CLI messages (`msg_cli`) — plain text, no templating. The psc
  completion's `info` templates carry their own `{{…}}` grammar (§6.11) and are rendered by the
  `tpl` command when a host asks for one.
- **All output goes to stdout.** Error messages are rendered by the PowerShell wrapper as
  readable colored hints — deliberately **not** written to stderr: PowerShell (5.1, and 7.3+ with
  `$PSNativeCommandUseErrorActionPreference`) treats native stderr as an error stream (red
  `ErrorRecord`s, possible exceptions), which would break the interactive UX this CLI hosts.
  (One exception: running the bare binary without `--data`/`PSCOMPLETIONS_DATA_DIR` prints a usage note to
  stderr — the module path always passes `--data`, so this never happens in normal use.)
- Text by default; every command accepts `--json`, except the internal `tpl`, which exists to hand
  back text.
- **Output contract (two modes, no exceptions)** — the full specification is
  [`json.md`](json.md):
  - **Text mode** (no `--json`): human-readable lines; success/failure is expressed by the
    exit code.
  - **`--json` mode**: stdout is **always valid JSON** — exactly one envelope object per run
    (`{ok, data, meta}`, or `{ok: false, error: {code, message, details?}, meta}`), never a bare
    array. A whole-command failure is the envelope's `error`; a per-item failure is an `ok: false`
    entry inside `data` (`add` / `rm` / `update` / `info`). The PowerShell wrapper and the shell
    bridges render that payload without branching on exit codes.
  - **Exit codes** apply in both modes: `0` everything succeeded, `1` something failed (including
    any per-item failure), `2` a usage/parameter error or a destructive operation without `--yes`.
    The exit code is the signal a script sees without parsing the payload.
  - **Sole exemption**: a `psc` invocation with no command word — bare, or flags only
    (`psc --json`) — is not a command execution: there is no failure to express. The engine prints
    its usage text and exits `0`; every host shows the module's **info page** instead (the engine
    cannot render it, since the module version it prints lives in the module directory).
- ANSI color when stdout is a TTY, stripped otherwise. The internal `tpl` is the exception: it
  colors by default and takes `--no-color`, because its callers capture stdout, where a TTY test
  would answer "no" and silently drop the color.

## 10. PowerShell module bridge

- `PSCompletions` function: no-arg → interactive info page (unchanged); with args → spawn
  `psc <args>` via `_forward_psc` (pass `--data <resolved data dir>`), forward stdout/stderr/exit.
- `config menu trigger_key` re-binds PSReadLine (`Set-PSReadLineKeyHandler`) — the one host-side
  validation that stays in PowerShell (validate-then-persist).
- Interactive confirm for `rm --all` in the wrapper, which then adds `--yes`; a group `--reset`
  is authorised outright (not destructive enough to ask about) — see [`json.md`](json.md) §7.
- Module self-update stays PowerShell (PowerShellGet/git).

## 11. Workspace layout (current)

```
core/
├── Cargo.toml            # [workspace] members = ["common", "engine", "cli"]
├── common/               # psc-common: dependency-free shared helpers (strip_bom, read_text)
├── engine/               # psc-menu: engine + TUI (no network deps)
│   └── src/
│       ├── lib.rs        # strip_bom re-export
│       ├── engine/       # completion tree/resolve + hooks/ runtime (hooks/api/, runner.rs, bindings.rs)
│       ├── menu/         # app/, state/(mod+tests), filter, model, order, protocol, ui
│       └── bin/psc-menu.rs  # entry: menu/sort/self-test modes + build-mode assembly
└── cli/                  # psc: data layer + commands + reqwest
    └── src/
        ├── lib.rs        # module declarations (commands/data/input/messages/net/output/postcheck/run/validate)
        ├── commands/     # one file per command (+ own tests); run_parallel in mod.rs
        ├── data/         # settings/index/library-changes + config registry
        ├── net.rs        # downloads, mirror fallback, staged commits
        ├── input.rs      # argv parsing + data-dir normalization + help text
        ├── output.rs     # Out sink, <@Tag> color markup, --json envelope (ok/err/fail/meta)
        ├── messages.rs   # embedded bilingual CLI messages (msg_cli)
        ├── validate.rs   # completion-name status/validation helpers
        ├── postcheck.rs  # change.json diff + psc self-heal + module version fetch
        └── bin/psc.rs    # thin entry: forwards argv to psc_cli::run::run

design/                   # design docs (this directory)
└── *.md
```

## 12. Risks & validation

- **Behavior parity**: each command reproduces param validation, localized messages, and exit
  semantics.
- **Data rebuild**: `add`/`rm`/`alias` trigger a settings rebuild + `refresh_settings_after_add`
  so module state stays consistent.
- Validation: Rust unit tests in `core/cli` cover settings/completions.json parsing and the
  settings rebuild; the module's behavior is covered by manual smoke runs of each command.

## Text output shape (the human view)

Every host reads this text directly — PowerShell included, which forwards it rather than building
objects out of `--json` — so the human view has a fixed, deliberately plain shape.
Two levels only, and **a form never repeats what the caller already named**:

| Form | Shape |
| --- | --- |
| `psc config` / `psc completion` (nothing named) | a `[group]` heading, then its rows — `key: value`, both at column 0 |
| `psc config <group>` / `psc completion <name>` | the rows alone (`key: value`) — the caller named the group |
| `psc config <group> <key>` / `psc completion <name> <key>` | the value alone, unquoted — the caller named the key |
| `psc list` / `psc alias` | one record per line: `name: value, value` (a single level, so no headers) |
| `psc info` (nothing named) / several names | a `[name]` heading, then its `Label: value` rows — the heading delimits, so there are no blank lines |
| `psc info <name>` (one name) | the rows alone, at column 0 — and no `Name:` row: the caller said it |

Rules that hold across all of them:

- **A per-item report follows the arguments, not the finish order.** `add` and `update` run their
  names on a worker pool; each result — its text line and its entry in the JSON array alike — is
  emitted in argument order.
- **`description` is the one field that can carry several lines, and it always starts on its own**:
  the label alone (`description:`), then the value — one line or several, one rule. The value is a
  string, in the index's own form (a completion's `meta.description` is an array, joined with `\n`),
  and the JSON reports that same string.
- **Color is status, never data.** Only messages that report an action (`add`, `rm`, `update`,
  the setters, `init`) are colored; every query is plain text.
- **A listing keeps an empty or space-padded value visible** (`url: ""`) — the shell convention
  for an empty argument — while a single-key read answers with the raw value (an empty line).
- **`--json` is the machine contract.** It mirrors the same hierarchy; scripts parse it rather
  than the human view, which is free to be phrased for people.
- **Rows are never indented.** A `[heading]` delimits on its own, exactly like an ini section —
  indentation bought nothing and cost readability (and parsing) in several places.
- **A component is never mentioned twice**: no key in a single-key read, no group header under a
  named group.
