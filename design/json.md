# Design: The `psc --json` contract

`--json` is the machine contract. A command has **one** model of what it has to report and emits
**one** rendering of it — the human text, or this JSON, whichever the mode asks for. Never both.
The JSON is the authoritative form: it carries the raw values, while the text may add display
conventions (quoting, color, indentation, a table layout). Both are derived from the same values,
so they cannot disagree about the data.

The engine's own flag parsing accepts `--json` anywhere in argv
(`core/cli/src/input.rs::parse_args`), and every command except the internal `tpl` honours it.

## 1. The envelope

Every command answers with **one object** — never a bare array, never a bare scalar:

```json
success: { "ok": true,  "data": …,   "meta": { … } }
failure: { "ok": false, "error": { "code": …, "message": …, "details": …? }, "meta": { … } }
```

- **`ok` is always present**, so a caller branches on a single key instead of guessing whether the
  payload is an array or testing `[0]`.
- **`data`** is that command's payload: a collection under a **named** key (`list` →
  `{"completions":[…]}`; `alias` → `{"aliases":[…]}` — the two are distinguishable by that key), or
  the item or state the command reports.
- A **per-item result** carries its own `ok`, and on failure the same `error` object shape as the
  envelope's (`add` / `rm` / `update` / `alias` / `info`).
- **`meta`** describes the run (§5), not the payload.

## 2. Keys

- All lowercase `snake_case`.
- **One-to-one with names the project already uses** — nothing invented, nothing translated: the
  remote index calls the version map `update`, so the JSON does too; the file is `completions.json`,
  so the key is `completions`.
- Keys under `file` carry **no format suffix** (`settings`, not `settings_json`): `file` already says
  it is a file, and a key with a dot in it needs `["…"]` in `jq`.
- A qualifier is added **only where two keys would otherwise collide** — `dir.completions` versus
  `file.completions` is settled by the parent object.
- **Plural for a countable collection, singular for a namespace**: `data.completions`,
  `data.aliases`; `data.config`, `meta`, `data`, `dir`, `file`. An **item** is singular: `name`,
  `alias`.
- **`alias` keeps the spelling of its sources** — the completion's `config.json`, `settings.json` and
  the template context all say `alias` — and its value is an **array** (`["git","g"]`). Flattening it
  into a space-separated string belongs to text/script rendering.
- An item identifies its completion as **`name`** everywhere (`list` / `alias` / `info` / `add` /
  `rm` / `update`): the envelope's `data.completions` already says these are completions, so
  repeating `completion` inside the item would be redundant.

## 3. Values

- **Raw JSON types**: a number is a number, a boolean is a boolean, an absent value is `null`.
- **JSON mode does no display work.** The text mode's automatic quoting (an empty value shown as
  `""`) exists only for text.
- **Fixed key sets**: a key is present and `null` rather than omitted, so a caller never has to probe
  whether a key exists.

## 4. Errors

```json
{ "ok": false,
  "error": { "code": "invalid_subcommand",
             "message": "Invalid subcommand: badgroup. Valid: core, menu, context",
             "details": { "token": "badgroup", "valid": ["core", "menu", "context"] } } }
```

- **`code`** is the stable identifier: lowercase snake_case, **never localized**, so a machine can
  branch on it.
- **`message`** is for a human and **is localized** (it follows the settings, or `--language`).
- **`details`** is optional and carries the parts a caller may need (the offending token, the valid
  set).
- A per-item error has the **same shape**.
- The codes in use: `too_few_params`, `invalid_subcommand`, `needs_confirmation`, `not_available`,
  `not_installed`, `not_updated`, `config_value`, `one_or_zero`, `no_hooks`, `psc_hooks_locked`,
  `language_no_reset`, `alias_wildcard`, `alias_reserved`, `alias_exists`, `alias_owned`,
  `alias_not_found`, `alias_unique`, `io`, `network`.

## 5. `meta`

```json
"meta": { "count": 4,
          "dir":  { "data": …, "completions": …, "temp": …, "menu": …, "cache": …, "log": …, "order": … },
          "file": { "settings": …, "completions": …, "change": …, "debug": …, "error": … } }
```

- **`count`** — how many items this payload carries, when it has any, so a script need not count
  them. A payload with no item count (a write, a single value) omits the key.
- **`dir` / `file`** group the paths by **type**: reading `dir.data` tells a caller it is a
  directory and `file.settings` that it is a file, with no guessing.
- The names are the ones the module uses (`PSCompletions.path`), only grouped differently.
- **No `root`.** The module keeps its `path.dir.root`, but the JSON does not carry it: the data
  directory comes from `--data` / the environment / the platform default and is **independent of the
  module root**, so a `root` explains none of the data paths. A caller looking for the binary already
  knows which one it ran (`argv[0]` / `current_exe()`), and every host has its own accessor
  (PowerShell's `psc_binary()`, the bridges' `$_PSC_BIN`) — hence no `--root` flag either.
- **The two log files are separate keys** (`file.debug`, `file.error`) under `dir.log`; they are
  unambiguous inside `file` and do not collide with the top-level `error` object (a different level).
  The engine derives them (`<log>/debug.log`, `<log>/error.log`) because it writes them; the module
  does not carry them (it only hands `dir.log` to the menu).
- **No version.** The engine knows only its own version; what a user cares about is the *module*
  version, which lives in the module directory and is unknown to the engine — carrying one would
  mislead.

## 6. Exit codes

| Code | Meaning |
| --- | --- |
| **0** | Everything succeeded (including a no-op). |
| **1** | Something failed: the command ran, but the envelope reported a failure, **or any per-item result did**. |
| **2** | Usage/parameter error: a bad flag, a missing argument, or a destructive operation without `--yes`. |

A per-item failure keeps the envelope's `ok` true (the command did produce a payload) and is
signalled by the exit code — the only thing a script sees without parsing. In text mode, which has no
envelope, the exit code carries the same meaning.

## 7. Interaction and destructive operations

**Interaction stays with the human's layer (the host); authorisation stays with the machine's (the
engine).**

| Layer | Duty |
| --- | --- |
| **Host** (PowerShell + the three shell bridges) | Asks about the two genuinely dangerous operations — `rm --all`, and the **root `--reset`** (which never goes through the CLI: the host performs it itself). Once confirmed, the host **adds `--yes`** to the invocation; the user never sees or needs the flag. A **group-level `--reset`** (`config` / `completion` / `alias`) is not confirmed — it is not destructive enough — but the host still authorises it. |
| **Engine** (the CLI) | **Never prompts.** A destructive operation must be explicitly authorised: without `--yes` it answers `needs_confirmation` and exits **2**. |

- **A `--json` invocation is never prompted**: a machine caller cannot press a key, so the host hands
  the invocation to the engine as it is. In the bridges and the module the `--json` check therefore
  sits **before** the confirmations.
- The engine's `--yes` requirement holds for **every** destructive operation (`rm --all` and every
  `--reset`), so a caller driving the engine directly — with no host to ask on its behalf — is
  stopped by `needs_confirmation`. That is a deliberate safety improvement.
- The three usages each land where they should:
  - `psc rm --all` → the host asks → Enter → the host adds `--yes` → it runs (the interactive flow is
    unchanged);
  - `psc --json rm --all` → no prompt → the engine refuses, so a script can decide;
  - `psc --json rm --all --yes` → it runs (ask once, then authorise — the usual script shape).

## 8. Per-command payloads

| Command | `data` |
| --- | --- |
| `list` | `{"completions": [{"name", "alias"}…]}` |
| `alias` | `{"aliases": [{"name", "alias"}…]}` — singular `alias` inside the item, matching `config.json` / `settings.json` / the template context; the collection key stays plural because it names a group |
| `alias add <name> <alias>…` | `{"name", "alias": […], "rejected": [{"alias", "error"}…]}` |
| `alias rm <name> <alias>…` | `{"name", "alias": […]}` |
| `alias --reset` | `{"aliases": […], "skipped": [{"alias", "owner"}…]}` |
| `alias add\|rm <name> --reset` | `{"name", "alias": […], "skipped": […]}` |
| `info` | `{"completions": [{"name", "ok", "alias", "url", "description", "path", "update", "updated"}…]}` — absent fields are `null`; an unknown name is an item with `ok: false` and an `error` |
| `config` / `config <group>` | `{"config": [{"group", "key", "value"}…]}` — `value` in its raw type |
| `config <group> <key>` | `{"key", "value"}` |
| `config <group> <key> <value>` | `{"key", "value", "old"}` — the item the read answers with, plus the value it replaced (`old` is `null` when the key had none), and `warning` when an unreviewed source takes effect |
| `config … --reset` | The resulting state, the same shape the read of that scope answers with: `{"config": […]}` for the whole config or one group, `{"key", "value"}` for one key |
| `completion` | `{"completions": [{"name", "config"}…]}` |
| `completion <name>` | `{"name", "config"}` |
| `completion <name> <key>` | `{"name", "key", "value"}` |
| `completion <name> <key> <value>` | `{"name", "key", "value", "old"}` |
| `completion … --reset` | The resulting state, the same shape the read of that scope answers with |
| `add` / `rm` / `update <name>…` | `{"completions": [{"name", "ok", "error"?}…]}` — plus `skipped` (aliases another completion owns) and `renamed_from` (a migrated rename) where they apply |
| `update` (no argument) | `{"update": […], "added": […], "removed": […], "renamed": [[old, new]…]}` — the library-change report, the same four lists `temp/change.json` carries |
| `<unknown command>` / a parameter error | `{"ok": false, "error": {…}}` |
| no command word (bare `psc`, or flags only) | Not a command execution: the **host prints the module's info page**. The engine keeps its own usage text as a fallback, because only the host knows the module version. |

Two cases deserve a note:

- **A write extends its read's shape instead of inventing a parallel one.** A single-value write
  answers the item a read of that key answers with and adds `old` — the value it replaced, `null`
  when there was none — which is the one fact a caller cannot derive, since it never read the key.
  A `--reset` restores a *set* rather than a single value, so it answers the resulting state exactly
  as the read of that scope does. `.data.value` therefore means "the value of this key" whether the
  command read it or wrote it.
- **A linked completion in `update` is reported, not failed.** `add` calls the same case a success
  (the link is kept); `update` reports `ok: false` with the `not_updated` code so the caller sees
  that nothing was fetched, but a local link is a deliberate choice rather than an error, so it does
  **not** fail the run.

## 9. Where this lives

- The envelope emitters: `core/cli/src/output.rs` — `ok` (success), `err` (the JSON failure
  envelope), `fail` (report in the run's own mode: text prints the line, JSON defers to `err`), and
  `meta`.
- The format's specification is the test file `core/cli/tests/json_contract.rs`: a shape change shows
  up there first.
- The hosts consume it: the PowerShell module reads `data.completions` and renders the items
  (`module/PSCompletions/PSCompletions.psm1`), and the three shell bridges render the same payload
  through `_psc_run_rendered`.
