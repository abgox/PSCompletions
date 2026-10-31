# PSCompletions Lua Hooks

> Status: **current**.
> Dynamic completions run as Lua scripts inside the Rust core process.
> This is the authoritative reference for the hooks subsystem — architecture, contract, and the full `psc.*` API.
> Operating manual for the completions workflow: `AGENTS.md`.
>
> **Editor experience**: `types/psc.lua` models the `psc` global and `completions` with EmmyLua annotations — with the VSCode "Lua" extension you get autocomplete and argument checks inside `completions/*/hooks.lua`.
>
> Scoping rule for `types/psc.lua`: it models only APIs usable by **every** hook.
> Members that exist engine-wide but are meaningful to a single completion (e.g. `psc._data`, which is psc-only) stay out, so they never compete for attention in other authors' completion lists.
> Single-completion capabilities live in that completion's own `hooks.lua` (suppressing the LSP diagnostic locally if needed).

## 1. Role of hooks

Static manifests capture a tool's fixed structure (subcommands, options, aliases, tooltips).
Dynamic values — things that depend on **runtime local state** (git branches, npm scripts, installed packages, files, env vars) — cannot be known at authoring time.
Hooks fill that gap:

- Hook output is **merged** with the static items, never a replacement.
- The hook runs only when the tool's `config.json` has `"hooks": true` and `hooks.lua` exists.

## 2. Architecture

```
Rust core process:
  manifest parse → build tree → context resolution → seed live list (static expansion) → run Lua hook (top-level + psc.on handlers, VM kept alive for lazy tips) → build items → menu → output

PowerShell thin bridge:
  capture line/cursor → write context JSON → spawn core → apply the selected item
```

- Lua runs **in-process** via `mlua` (no separate interpreter process, no IPC cost).
- Rust **pre-parses the context** (subcommand path, pending token, last option, completed tokens) and exposes it as `psc.*` values, so hooks never rebuild it from raw input.
- The `completions` global is the **live candidate list**, seeded once with the static expansion (one row per alias form). Hook top-level code and `psc.on` handlers mutate it directly via `psc.add` or plain Lua table operations; whatever it holds when the hook finishes is what the menu shows (after repeat filtering and symbol/tip overrides).
- `psc.on(spec, handler)` registrations are evaluated **at most once per build**, handlers run sequentially.

## 3. Hook contract

The `hooks.lua` script's **top-level body** is unconditional direct manipulation, and `psc.on(spec, handler)` registrations are conditional direct manipulation — both operate on the same live `completions` list.

> Encoding: a leading UTF-8 BOM is stripped before execution (Windows editors often emit one), mirroring the BOM-tolerant read of static manifests.

```lua
-- declarative: runs only when the current position matches spec
psc.on({ command = "exec" }, function()
    for _, line in ipairs(psc.run({ "tool", "list" }) or {}) do
        psc.add({ name = line })
    end
end)

-- option-value anchor
psc.on({ option = "--arch" }, function()
    psc.add({ name = "x86_64" })
end)
```

- `completions` — live candidate list, seeded with static items. Items use the **`name`** key.
- Top-level code and `psc.on` handlers mutate `completions` directly: `psc.add(item)` appends, `completions[i] = ...` / `table.insert` can rewrite.
- Return `nil` (or nothing) → live list is the result. Returning an explicit array **replaces**
the live list entirely (documented: do not mix a replacing return with `psc.on` in the same file; the engine warns when an explicit return discards `psc.on` contributions).
Returning anything else (e.g. a string) is an error.
Malformed rows (non-table, missing/blank `name`) are skipped, never fatal.
- Completion item shape: `{ name, tip?, usage?, example?, symbol?, repeat?/repeat_count?, nospace?, is_option? }`. `usage` / `example` are optional text lines shown as the `[Usage]` / `[Example]` tip sections — each accepts a plain string or a `{ cmd, desc }` object (rendered `cmd  # desc`, just `cmd` without `desc`), mirroring the manifest's object entries. `tip` accepts a plain string or a
  localized table; an absent `tip` falls back to `name`. All three also accept a **function**
(lazy — see below); a function tip has no name-fallback (unresolved reads back empty).
- **`is_option` is engine-internal**, like `nospace`: the declared type of the static node the row came from, round-tripped so a hook-preserved static item keeps it. Absent means the row is hook-injected and no manifest declares it. Consumers compare rows by the manifest's own rule (options case-sensitively, commands case-insensitively) instead of guessing from a leading `-`.
- **`text` is an engine-internal field**: everywhere a hook can see an item, it is the `name` key. Do not read or write `text` on items.
- The menu performs filtering/prefix matching; hooks return the **full candidate set** via the live list. Dynamic items added via `psc.add`/`psc.on` are ordered **before** static items so contextual completions are visible first; history-based ranking (`order.rs`) then applies within that sequence.

### Lazy `tip` / `usage` / `example` functions

Pass a zero-arg function instead of a value and it is evaluated **once, when its row is selected** (highlighted) — not when the hook runs, not on apply:

```lua
-- scoop-style: list names now (cheap), parse each manifest on selection
for _, app in ipairs(names) do
    psc.add({ name = app, tip = function()
        local m = psc.json(bucket_file(app))
        return m and m.description
    end })
end
```

- The closure sees hook locals and the full `psc.*` API (upvalues are preserved — the hook VM stays alive for the menu session). It returns a string, a localized table (`tip`) / `{ cmd, desc }` object (`usage` / `example`), or nil (no text).
- Each field resolves at most once and is cached; errors and timeouts resolve empty (logged once to `error.log`, never retried, never fatal).
- **Budget**: one evaluation gets 5 seconds (matches `psc.run`'s default timeout; a manifest parse is milliseconds). Keep callbacks to fast local reads — evaluation is synchronous on the main thread and blocks navigation while it runs. The budget shares the process-global deadline slot with background symbol peeks; if the two overlap, budgets may stretch or cut early — both sides degrade gracefully (empty tip / missing symbol), never fatal.
- **Result cache is bypassed** while any lazy callback is pending: cached items could never replay their functions. Re-running is cheap by design (names only).
- A callback must not rely on `psc.add` (the live list is already snapshotted — appends land nowhere visible).

### Async evaluation (future)

Evaluation is synchronous today: a slow callback blocks navigation up to its 5 s budget.
True separation needs a dedicated VM-owner thread (mlua values are `!Send`, so the session VM cannot move to a worker) with a request channel from the menu loop — queued per-row evaluations, current selection first, stale results dropped by generation, same 5 s cap per callback.
Do that when real hooks (not fixtures) prove the synchronous hitch user-visible; until then the budget + keep-it-fast rule stands.

## 4. psc.\* Context Values

| Field | Meaning |
| --- | --- |
| `psc.tokens` | **Completed** tokens, each `{ name, type, input }`. `name` is the **canonical** name of a known command/option (alias input still points at the main name); `type` ∈ `command`/`option`/`value`/`unknown`; `input` is the user's raw input (possibly an alias, original casing kept — compare with `psc.eq` / `psc.contains`). **Excludes the word being typed.** A token consumed as an option's value (even a non-matching one) has `type = "value"`; `"unknown"` only appears outside an option's value position. An `=`-attached word (`--format=json`) appears as two tokens — `option` (input keeps the `=`, name is the `=`-stripped canonical) + `value` — mirroring the space-separated form, so existing "last token is the option" checks keep working. |
| `psc.typing` | The token currently being typed (unfinished): `name`/`type`/`input` (same shape as a token element, `name` is best-effort and often empty) plus `option_like` — whether the input starts with `-` (heuristic, not definitive). Opposite of `tokens`: one is in progress, the other completed. When completing an option's value position, `type` is `"value"` (even for free-form values). For `--format=j<TAB>`, typing carries the value segment only (`j`). For separator lists (`--exclude a,b<TAB>`), typing is likewise the tail segment (`b`); completed segments stay engine-internal and a finished list is a single `value` token. |
| `psc.config` | The current command's **final** completion config, merged by the engine from three layers (later layers override earlier): **global config** (`psc config menu`, e.g. `enable_tip`) → **manifest `config` array defaults** (e.g. `max_commit: 30`) → **per-completion overrides** (`psc completion <name>`, e.g. `max_commit: 50`). Every key always has a value — no manual `or` fallback needed. Built-in keys: `enable_tip` / `enable_tip_usage` / `enable_tip_example` (bool, default `true`), `language` (same as the module's current language). Empty table when unconfigured (never nil). |
| `psc.manifest` | The parsed manifest (JSON → table); hooks can read static data (e.g. git config keys). |
| `psc._data` | **psc completion only** — aggregated module data (`settings.json`/`completions.json`) surfaced when manifest is `completions/psc`, else an empty object |
| `psc.cwd` | The current working directory. |
| `psc.platform` | The current system platform. (`"windows"` / `"macos"` / `"linux"`) |

> **A Windows-only environment variable needs a platform guard.** `APPDATA` is always empty on Linux, and `psc.path("")` degrades to a path relative to the current directory, so the lookup silently succeeds somewhere wrong.
> Prefer a portable path first and put the Windows one behind a non-empty check:
>
> ```lua -- wrong local cfg = psc.json(psc.path(psc.env("APPDATA") or "", "Claude", "settings.json"))
>
> -- right local home = psc.env("HOME") or psc.env("USERPROFILE") or "" local cfg = psc.json(psc.path(home, ".claude", "settings.json")) if not cfg and psc.platform == "windows" then local appdata = psc.env("APPDATA") or "" if appdata ~= "" then cfg = psc.json(psc.path(appdata, "Claude", "settings.json")) end end ```
>
> `HOME or USERPROFILE or ""` is safe on its own — `HOME` exists on Linux.
> The dangerous shape is narrower: a **Windows-only variable as the first link of an `or ""` chain**.
> The worked counter-example is `completions/claude/hooks.lua`, which still gets this wrong.
> Background: [`decisions/authoring.md`](../decisions/authoring.md#d19).

## 5. psc.\* Capability Functions (Rust)

The functions split into three groups: **completion-item** (build/manipulate completion items), **data acquisition** (fetch data from the system), and **data operations** (generic array/string tools).

### Completion-item

| Function | Returns | Description |
| --- | --- | --- |
| `psc.items(elements, fn?)` | `psc_item[]` | Convert each element into a completion item. Without second arg the element itself is `name`; with a function `fn(elem)` returns the item table (`nil` skips). A non-function second arg falls back to plain mapping. |
| `psc.mount_items(manifest_path)` | `psc_item[]` | **Pure transform** (like `psc.items`): resolve `manifest_path` from the **manifest root** and convert the **direct children** of the array it lands on into completion items — returns an array, does **not** add to `completions` (inject via `psc.add`); **no recursion**. The chain mirrors the manifest structure exactly, segment by segment (exact, case-sensitive): at an **object** the segment is a plain key lookup — any key that actually exists (`next`, `option`) — and at an **array** it matches an item's `name`; no segment may be skipped. The path must land on an **array** (mounts its children) or on a single **item object** with a `name` (mounts that item); anything else converts nothing. Examples: `{ "next" }` = the root's subcommands; `{ "next", "config", "next", "set", "next" }` = the children of `manifest.next.config.next.set.next`. Each child keeps its `name`/`tip`/`usage`/`example`, with `alias` forms expanded as separate items sharing the same tip, like the static menu; **deeper levels are handled by the engine's own `next` navigation** (selecting a child whose manifest entry has a `next` enters that context), or by calling `mount_items` again with a longer path built from `psc.tokens`. |
| `psc.add(item_or_items)` | `psc_item\|psc_item[]\|nil` | Append to the **live candidate list** (routes to the current accumulation target). `item_or_items` is a single item table or an array of tables; empty/missing `name` is skipped. Returns the stored entry table(s) **by reference** — post-call edits apply (e.g. `local e = psc.add({name="x"}); e.tip="new"`). Nil when nothing added. |
| `psc.on(spec, handler)` | — (nothing) | Declarative registration — bind a zero-arg `handler` to a location (root / command chain / option value position). Returns nothing: injection happens only inside the handler via `psc.add` / direct `completions` ops. Fires only while the location's slot is still unfilled; `spec.multiple = true` keeps matching after it was filled. See **Declarative `psc.on`** below. |
| `psc.token(spec?)` | `psc_token\|nil` | Find the **first** `psc.tokens` entry matching `spec` (`{name?, type?, case_sensitive?}`, or a bare name string as shorthand); `nil` spec, empty table, or empty string → first token (any type); `name` filters by canonical name, `type` filters by `command`/`option`/`value`/`unknown` (an unknown `type` is an error, never a silent match-all). Case-insensitive by default, `case_sensitive=true` for exact.|

### Data acquisition

| Function | Returns | Description |
| --- | --- | --- |
| `psc.run(argv, opts?)` | `string[]\|table\|nil` | Run a command, return stdout **as an array of lines**; **nil on failure/timeout** (incl. a non-zero exit). Default timeout 5000ms; stdout is drained concurrently (no deadlock on large output); stderr discarded; **stdin is `/dev/null`, never inherited** (the engine is reading the terminal, so a child that read stdin would eat the user's keystrokes). `opts`: `timeout` (ms), `cwd`, `format` (`"json"`/`"toml"`/`"yaml"` — parses stdout and returns the parsed table, nil when unparseable), `shell` (bool — run through the system shell, `cmd /c` on Windows / `sh -c` elsewhere; use it for batch/PowerShell shims like `scoop`), `env` (table — key-value pairs injected into the child process environment, merged with the inherited env), `capture_fd` (integer — captures an extra file descriptor, e.g. `8` for Python argcomplete which writes completions to fd 8, redirected to stdout via `8>&1`). |
| `psc.run_batch(cmds, opts?)` | `table<number, string[]\|table\|nil>` | Run **multiple commands in parallel**; results in input order. Same `opts` as `run` (parallel commands are of the same format); a failed/unparseable command yields nil at its index. |
| `psc.read(path)` | `string?` | Read a file as UTF-8 text; nil on failure. Resolved relative to `psc.cwd`. |
| `psc.read_batch({path,...})` | `table<path, string?>` | Read **multiple files in parallel**; `{ [original-path] = content }`, nil for a missing/unreadable file. |
| `psc.json(path)` / `psc.json_batch(paths)` | `table?` / `table<path, table?>` | Read + parse JSON (JSON5 supported). Single: nil on failure. Batch: nil at a path for a missing/unparseable file. |
| `psc.toml(path)` / `psc.toml_batch(paths)` | `table?` / `table<path, table?>` | Read + parse TOML. Single: nil on failure. Batch: nil at a path for a missing/unparseable file. |
| `psc.yaml(path)` / `psc.yaml_batch(paths)` | `table?` / `table<path, table?>` | Read + parse YAML. Single: nil on failure. Batch: nil at a path for a missing/unparseable file. |
| `psc.ls(path)` | `psc_path_entry[]?` | Directory entries `{name, path, is_dir, is_link}` (`path` is the entry's full resolved path); nil if the directory does not exist (an empty dir yields an empty array). `is_dir` follows symlinks (a symlink to a directory counts as a directory). |
| `psc.ls_batch({dir,...})` | `table<number, psc_path_entry[]?>` | List **multiple directories in parallel**; results in input order, nil at an index for a missing dir. |
| `psc.glob(pattern)` | `string[]?` | Glob matching (supports `*`/`?`/`**` and `{a,b}` alternation via `globset`); the pattern resolves against `psc.cwd` (an absolute pattern ignores it); results are absolute and deduplicated; the walk respects `.gitignore`/`.ignore`/`.git/info/exclude` (like `ripgrep`) — ignored files are not returned; nil for an invalid pattern (a valid pattern with no match yields an empty array). Bounded: the walk stops after 500 ms (or the hook's remaining time, whichever comes first) and returns the matches found so far (see §11). |
| `psc.path(...)` | `string` | Normalize/join path segments into one path using the **native platform separator** (`\` on Windows, `/` elsewhere): a single argument normalizes its separators (on Windows `/` → `\`), multiple arguments are joined with that separator. Duplicate separators collapse (`psc.path("a/", "/b")` → `"a\b"` on Windows, `"a/b"` elsewhere); a leading separator (absolute segment) and a drive root like `C:\` are preserved. |
| `psc.exist(path)` | `boolean` | Whether the path exists (follows symlinks). |
| `psc.env(name)` | `string?` | Environment variable; nil if unset. |
| `psc.which(name)` | `string?` | Full path of the first executable found in PATH (PATHEXT on Windows, exec bit on Unix); nil when not found. |

> **Batch convention**: the `*_batch` suffix processes a whole group at once (parallel under the hood, but that is an implementation detail).
> Run/ls batches return results **in input order**; read/json/toml/yaml batches return `{ [original-path] = value }` maps.
> **Failure semantics are strict**: a failed/unreadable/unparseable entry yields **nil** at that position, matching the single-value APIs — hooks guard with `or {}` / `if x then` / `x and x.field`.
> `glob` needs no batch — one `**` call covers a whole tree.

### Data operations

| Function | Description |
| --- | --- |
| `psc.concat(...)` | Merge any number of arrays (variadic). |
| `psc.split(text, separator?)` | Split a string into an array by `separator` (default a space). |
| `psc.join(value, separator?)` | Accept a **string** (returned as-is) or an **array** (elements joined; non-strings are tostring'd), separated by `separator` (default a space). Useful to normalize a manifest field that may be a string OR an array (e.g. `psc.join(c.description, "\n")`). |
| `psc.contains(haystack, needle, opts?)` | Membership / pattern check. **Default**: `haystack` is a **string** (exact equality) or an **array** (exact membership), `needle` matched exactly (case-insensitive, `opts.case_sensitive` true makes it exact). **`opts.pattern` true**: `haystack` may be a **string or an array** — a string is matched against `needle` as a Lua pattern, an array matches when any element does (handles manifest fields that may be a string OR an array). |
| `psc.eq(a, b, opts?)` | String equality; **case-insensitive by default**, `opts.case_sensitive` true → exact. A **nil** argument never matches (returns `false`, never errors). |
| `psc.trim(text, opts?)` | Trim characters; whitespace by default, `opts.chars` (a string whose characters form the trim set) overrides it (an empty string trims nothing). `opts.mode` is `"start"`/`"end"`/`"both"` (default `"both"`). |

> **Optional behavior goes in an `opts` table** (`contains`'s `case_sensitive`/`pattern`, `trim`'s `mode`/`chars`, `run`'s `timeout`/`cwd`/`format`) — keys self-explain at the call site, extensible, consistent across the API.

## 6. Mental model

```lua
-- declarative (recommended): registrations run only when the location matches
psc.on({ command = "exec" }, function()
    for _, line in ipairs(psc.run({ "tool", "list" }) or {}) do
        psc.add({ name = line })
    end
end)
```

Inside a handler, empty results need no explicit guard — `psc.add` is a no-op on an empty array or empty name:

```lua
psc.on({}, function()
    psc.add(psc.items(psc.run({ "git", "branch" }) or {}))              -- one item per line
    psc.add(psc.items(psc.ls("dir") or {}, function(e) return { name = e.name } end))
    psc.add(psc.mount_items({ "next", "config", "next", "set", "next" }))
    -- return value is the stored table(s) by reference: post-call edits apply
    local e = psc.add({ name = "x" })
    e.tip = "new tip"
end)
```

Only branch on a result inside a handler when you genuinely need to (e.g. "no output → fall back") — use `completions` or `#items`.

## 7. Critical Semantics (pitfalls — follow these)

0. **Failure semantics are strict**: every data API returns `nil` on failure (`read`/`json`/ `toml`/`yaml`/`env`/`which`, `run`/`run` with `format`/`ls`/`glob`, and each `*_batch` element). A "success but empty" result is distinct from failure — `run`/`ls`/`glob` yield an empty array on success with nothing to show, nil only on actual failure. Hooks guard with `or {}` (iterate), `if x then` (branch), or `x and x.field` (index) — the LSP surfaces these as optional types. No API throws on I/O or parse failure — a hook never crashes on bad input, it degrades to empty.

0. **Every API tolerates `nil` arguments** — passing a nil never crashes the hook; it yields the empty result for that API's type (`nil` for single-value readers and lookups like `token`, `false` for predicates like `exist`/`contains`/`eq`, an empty array for list/batch builders). `add` becomes a no-op. A nil element inside a batch list or `run` argv is skipped. **Callers are still responsible** for not applying operators to a nil result (`#psc.run(x)` when `run` returns nil fails) — guard with `or {}` as above.

1. **`psc.tokens` excludes the word being typed**; the partial word lives in `psc.typing`. Therefore:
	   - `psc.tokens[#psc.tokens]` = **the last completed token**. Use it to detect "currently completing an option's value" (e.g. `scoop install -a x86<TAB>` → last completed token is `-a`).
	   - `psc.token({name=name})` only finds **completed** tokens — the partial word being typed never counts. An option-consumed value matches as `type = "value"` (not `"unknown"`).
 2. **Case — insensitive by default**:
    - **Name-matching APIs are case-insensitive by default** (`psc.contains`, `psc.token`, `psc.eq`)
    - **Token/input values keep the user's original casing** — `psc.tokens[].name` is the **canonical** name (aliases expanded, e.g. `-m` → `--move`), `psc.tokens[].input` is the raw input, **not lowercased**. Compare against literals with `psc.eq` (single value) / `psc.contains` (a list) or `psc.token({name="--move"})` instead of `==`.
3. **Lua patterns ≠ regex**: Lua patterns escape with `%` where regex uses `\` — `\d`→`%d`, `\w`→`%w`, `\s`→`%s`. Escape literal metacharacters too — `-` is the (lazy) quantifier, so a literal dash must be `%-` (e.g. `^%-%-` matches a leading `--`). This applies to `psc.contains` with `{ pattern = true }`.
4. **`gsub` returns two values** (string + replacement count). When used as the last argument of `table.insert` etc., or assigned to a single variable, wrap in parentheses: `table.insert(x, (s:gsub(" | ", "\n")))` or `local t = (s:gsub(...))`.
 5. **Manifest fields may be a string OR an array** (e.g. scoop's `description`, `pre_install`): check with Lua primitives, don't branch on `type(x) == "string"`. A **string** field is truthy in Lua when present (`if c.link`), an **array** field needs an explicit emptiness check because Lua empty tables are truthy (`if c.persist and next(c.persist) ~= nil`).
 6. **Encoding**: `psc.run` output goes through `from_utf8_lossy`; non-UTF-8 (e.g. GBK) content becomes `�`. Strip NULs from wsl's UTF-16 output with `line:gsub("%z","")`.
 7. **Do not reconstruct context from raw input**: use `psc.tokens` (filter by `type`) or `psc.token({type="command"})` / `psc.token({type="option"})` for the subcommand/option path, and `psc.tokens`/`psc.token` for "what was typed". Raw input is not canonical.
 	 8. **"Command/option wins" — option value vs known command/option**: an option that declares `next` (even empty) consumes the next token as its value — **unless** that token matches a known command or option, in which case the option acts as a flag (does not consume the token). After consuming a value, the context automatically resets to the nearest command context, so subcommands remain reachable. This means `psc.on({ option = "--flag" }, ...)` fires only when the next token is genuinely a free-form value, not a known command/option.

## 8. Common Pattern

Everything is declarative — each dynamic location owns its own `psc.on`:

```lua
-- command-chain anchor
psc.on({ command = "exec" }, function()
    psc.add(psc.items(psc.run({ "tool", "list" }) or {}))
end)

-- option-value anchor
psc.on({ option = "--arch" }, function()
    psc.add({ name = "x86_64" })
end)

-- root
psc.on({}, function()
    psc.add({ name = "bin" })
end)
```

No explicit return needed: `nil` → live list.

### Mounting shared values defined in the manifest

When several subcommands share the same value list, define the list **once** in the manifest (as the `next` of a chosen node, e.g. `config` → `set` → `next`) and mount it from a handler with `psc.mount_items({ "next", "config", "next", "set", "next" })` — it returns the **direct children** of that array with their tips.
This keeps the values (and their localized tips) in the manifest instead of hardcoding them in the hook:

```lua
psc.on({ command = { "config", "set" } }, function()
    psc.add(psc.mount_items({ "next", "config", "next", "set", "next" }))
end)
```

The same single-source rule covers a `help`-style command whose slot takes the tool's own subcommands (`dart help <command>`): mount the root table instead of duplicating it — every added or removed command would otherwise need the same edit in two places, in two languages, and no gate compares the two copies:

```lua
psc.on({ command = "help" }, function()
    psc.add(psc.mount_items({ "next" }))
end)
```

Three conditions, all required.
The value set is **exactly** the static set — prove it by rejection (`dart help bogus` answers `Could not find a command named` with a non-zero exit) and by diffing the listing against the manifest.
The slot takes **names**, not documentation — a `help` that takes topics (`gh`, `go`, `rclone` all do) keeps its own static `next`, even where spellings coincide.
And the **copy count** is big enough to matter: compare entries × slots, not entries alone.
Six values pasted into ninety slots is 540 entries in each language, while six values in one slot is not worth a hook; below a handful of copies the duplication is cheaper than the hook file, the `hooks: true` flag, and the checker run.
The home node keeps its own static `next`, so the values still work there when a user disables hooks; the mounted slots lose them, which is the price of one source.
Mounting re-surfaces the manifest entries — tips and localizations included — so it creates no second source, which is why this is not an `R-16` violation.

Mounting is not querying: it reads no runtime state and shells out to nothing, so it has no staleness class of its own — it goes stale exactly when the manifest it mounts goes stale, and the update audit that refreshes the table refreshes the help slot in the same edit.
A hook that shells out to enumerate its values is different in both directions: it tracks upstream additions for free, but when its query shape changes it degrades to a silent empty slot that no gate re-checks until someone touches the hook.
Static tables stale the third way (upstream adds a value; the `--help` diff at the next update catches it).
Judge each slot by which staleness it can afford: mounted commands, queried dynamics, static topics.

The handful threshold above is not about CPU — a mount costs none.
It is about the disabled-hook empty slot (a user-disabled hook offers nothing; a static copy always works), the gate surface a hook file carries (`luac`, `check-hook-targets`, re-probing on every touch), and the typo radius (a wrong `mount_items` path converts nothing, silently).
A few lines of duplication carry none of that.

### Declarative `psc.on`

The core primitive of the declarative hooks style: instead of branching on context and stuffing a global table, declare where dynamic candidates live and who handles them.
The location leads, the handler hangs last — like a route + handler.

```lua
psc.on({ command = "exec" }, function()
    psc.add({ name = "mybin", repeat_count = 99 })
end)
-- multiple: the location's slot keeps matching after it has been filled —
-- `git rebase <Tab>` and `git rebase xxx <Tab>` (selected or typed) both fire.
psc.on({ command = "rebase", multiple = true }, function()
    psc.add({ name = "yyy" })
end)
-- the same switch where the command takes any number of names: after
-- `apt install a`, the next Tab must still list packages.
psc.on({ command = "install", multiple = true }, add_available)
psc.on({ command = { "", "set" } }, function()  -- "" wildcards any segment at that position
    psc.add({ name = "value" })
end)
psc.on({ option  = "--arch" }, function()
    psc.add({ name = "x86_64" })
end)
-- Option CHAIN: suffix of the completed option sequence (contiguous, in order;
-- option values never enter the sequence; `""` wildcards a segment). Not anchored
-- at a root — the option sequence has no root.
psc.on({ command = "branch", option = { "--move", "--copy" } }, function()
    psc.add({ name = "both" })
end)
-- Spec ARRAY: elements are ORed; each element follows the single-spec rules.
psc.on({
    { command = "config" },
    { command = "install", option = "--arch" },
}, function()
    psc.add({ name = "hit" })
end)
psc.on({}, function()  -- root
    psc.add({ name = "bin" })
end)
```

Contract:

- `spec.command` — command chain from the root (canonical names; string or array of strings). `""` is a wildcard matching any command at that position; `{"", "set"}` matches any depth-1 command's `set` child. Injects when the current layer chain equals it (segment-wise, `""` matches any, others case-insensitive). The chain is **root-anchored**: its length must equal the typed command depth. **Slot gating**: this pins the first positional argument after the chain — by default an `unknown` token after the chain (a typed value the engine does not recognize) suppresses injection, because the slot is already filled; `multiple = true` keeps matching through any number of positional arguments.
- `spec.option` — an option chain matched as a **suffix** of the completed option sequence (string = a length-1 chain; array = a contiguous suffix, in order). Option values never enter the sequence, so `--move val --copy` still matches `{"--move","--copy"}`. `""` wildcards a segment; other segments must start with `-`. A trailing `=` in a segment is not identity (`"--format="` matches `--format`, including its `=`-attached uses). The suffix is deliberately NOT root-anchored: the option sequence has no root, and full anchoring would silently break every existing single-option spec. An option with `next` (empty or not) consumes the next token as its value (`type = "value"`), subject to "command/option wins" — a known command or option takes priority, making the option act as a flag. After value consumption, the context resets to the nearest command context, so subsequent subcommands remain completable. **Slot gating**: this pins the value slot of the chain's last option — by default injection requires that slot to be still unfilled (the last completed token must be that option); once a value has been typed, `multiple = true` is required to keep matching.
- `spec = {}` or omitted keys — targets the root context (the first positional argument). `command` and `option` may coexist as AND — both must match to inject (e.g. `{ command="install", option={"--color","--arch"} }` = under `install` with the option sequence ending `--color, --arch`).
- `spec.multiple` — boolean, default `false`. The location's slot may keep matching after it has been filled once. **In one line: `false` runs the handler at the location's first unfilled slot only; `true` runs it at every argument position of that location.** The everyday case is a command taking **any number of names** — after `apt install a`, the next Tab must still list packages (the `install` example above); without `multiple` that slot has nothing left to offer. `git rebase <Tab>` is the free-form twin: `{ command = "rebase" }` fires there but not at `git rebase abcdefg <Tab>`, while `multiple = true` fires at both and at every further positional argument (known static values and dynamic `unknown` inputs alike). The static menu is built from the manifest regardless, so a handler that must *act* at a deeper position — not merely inject there — needs `multiple = true` or it silently skips it: once a value has been typed, the context resets to the nearest command ([`completion.md`](completion.md) §2), whose options and subcommands are still offered. Stripping an option the CLI rejects below the location is the typical case. This is not the manifest's `repeat`; see §`multiple` is not `repeat`.
- **Spec arrays** — `spec` may be an array of spec tables (OR): any matching element injects; each element independently follows the single-spec rules (including AND). Mixing named keys with array elements in one table raises.
- Returns **nothing** — there is no placeholder table; all output goes through direct `psc.add` / `completions` ops inside the handler.
- Validation (failures are logged to `error.log` — a 1 MB-capped, 7-day-age-rotated file in `data/temp/log/`; see §12 — registration becomes inert — never a process fault): unknown spec keys raise; `command` segments must be strings, empty array rejected (omit to target root), `""` is wildcard — a `next` entry may itself be option-shaped (`--self-update`), so `command` is deliberately not shape-constrained; `option` segments must start with `-` (or be `""` wildcards), empty array rejected; the last named segment of each chain is resolved through the manifest at registration time — **in the position the key declares**: a `command` target must be declared in a `next` array (a subcommand), an `option` target in an `option` / `global_option` array. A name the manifest declares as the other kind raises with that reason, not a bare "unknown" (unknown targets raise, aliases accepted). For `AND` specs (`command`+`option`) either unknown side makes the whole spec inert (logged); single-key unknown still raises.
- Each registration runs **at most once per build** (inject only); handlers run sequentially.
- Handler is zero-arg, manipulates candidates via `psc.add` / direct `completions` ops; errors are logged, partial mutations persist, siblings unaffected; `psc.on` inside a handler is a recursion error.

### `multiple` is not `repeat`

`multiple` describes the **arity of one slot**: after the first value or positional is filled, does the same location accept another one?
`repeat` describes **how many times the item itself may appear** in the command line.
They are independent, and a repeated option does not need `multiple`: the next occurrence is a new option token with a fresh, unfilled value slot, so the target fires again.

| Shape | Example | Where it is declared |
| --- | --- | --- |
| the same flag appears twice | `-include a -include b` | manifest `repeat: 99`; no `multiple` |
| one occurrence accepts several values | `--cmd daemon list`; `apt install a b` | hook `multiple = true` |
| one value is split on a separator | `--select a,b` | manifest `separator: ","` |

```lua
-- Each -include is a separate occurrence; no multiple.
psc.on({ option = "-include" }, add_profiles)

-- One occurrence carries a chain of values.
psc.on({ option = "--cmd", multiple = true }, add_chain)

-- One command occurrence takes any number of names.
psc.on({ command = "install", multiple = true }, add_packages)
```

Setting `multiple` on a one-value option does not make the option repeat; it keeps the target matching after that slot is filled, which is only correct when the CLI accepts another argument there.

Injected items are part of the live list (no separate merge step) and participate in repeat filtering like any dynamic item.
Returning an explicit array from the hook still **replaces** the live list (the engine warns when an explicit return discards `psc.on` contributions).

Boundaries: `--opt=value` equals-form value positions are detected — the option counts as completed and the tail is the value slot, so hooks see the same shape as the space-separated form.
A valueless flag written with `=` is not split; the whole word stays one token.

### Localized tips

`tip` (in `psc.add`) accepts a **localized table** keyed by language code, so the same item shows a translated description per user language:

```lua
psc.add({
    name = "svc",
    tip = {
        ["en-US"] = "Windows service",
        ["zh-CN"] = "Windows 服务",
    },
})
```

The engine picks the entry matching the loaded manifest's language variant (the host resolves it per-completion first, then global), falling back to `"en-US"`, then the first entry.
`en-US` is the required fallback key; `zh-CN` is optional.
The language keys are declared as named fields on `psc_localized` in `types/psc.lua`, so the editor completes `["en-US"]` / `["zh-CN"]` inside the table literal and explains each key on hover.
Extra language codes remain allowed via the index signature.

## 9. Style Guide

This section is normative for AI and human authors.
`design/hooks.md` is the style authority.

- **Comments — why only, one line**: explain *why* when the code is not self-evident, not *what*. Keep a single short line in **English**. Do not add a file header like `-- <tool> dynamic completions` or section labels like `-- node commands` — the `psc.on` spec already says it. Generic headers and what-only section comments are forbidden.
- **Registration — one producer per `psc.on`**: `psc.on` takes either one spec or an array of them (`psc_on_spec|psc_on_spec[]`, any spec matching), so both shapes are valid API; the *grouping* is a style decision, and `psc.on` has no per-command multi-handler entry, which fixes the axis you can group on.
  - **One handler, one source.** A producer reads one source — one `psc.run`, one `psc.mount_items`, one fixed table — and adds one kind. Filtering and computed tips belong to that producer; a second source (commits and bookmarks, installed and available packages) is a second producer. Injected items are **not deduplicated**: two registrations that both offer a name show two rows, so split by source to make an overlap visible and leave a static home out of the mount that would re-offer it.
  - **Every target a producer serves goes in that producer's single spec array.** `psc.on({{ option = "--a" }, { option = "--b" }}, add_files)`, not three calls to `add_files`.
  - **Split registrations only when the trigger conditions differ, and say why.** The test: *would the two groups still read correctly merged into one array?* If yes, merge. If no, keep them apart — and each split block carries its own one-line `why` comment, because that is the only record of the intent. Without the comment a reader cannot tell a deliberate split from a stray extra call, and an uncommented second block is a trap: the next person to add a path option has to guess which block it belongs to. The same handler under two conditions is still one producer, registered twice.
  - **Order is registration order.** A matching handler runs as the script reaches its `psc.on`, and its items append in that order; injected items are then shown before static ones. "Commits first, then branches" is therefore two registrations in that order — never one handler that adds both. Keep order-sensitive blocks adjacent and say why. What registration order cannot promise is the final menu order: history ranking reorders the merged list, so a display priority is a menu feature, not a grouping decision.
  - **A combined handler is the exception.** Use it only when candidates must interleave (`commit, branch, commit`) or one producer consumes another's output; one handler, one why comment. Every other case is one `psc.on` per producer.
  - **Share the target list, not the handler.** When two producers serve identical locations, put the spec array in a local and pass it to both calls — `psc.on(REVSET_SLOTS, add_commit)` and `psc.on(REVSET_SLOTS, add_branch)`; `psc.on` only reads the table. Copying the array per producer is the cost of this rule and is avoidable; when the lists differ by a slot, give each its own name and say why.
  - **One target needs no array.** Write the bare spec: `psc.on({ option = "--netrc-file" }, add_netrc)`. Do not wrap a lone target in `{ { ... } }` for the sake of looking uniform.
  - **Do not group by command.** When one command needs several producers it must appear in each of their arrays — `git merge` is listed by `add_branch`, `add_head`, `add_commit` and `add_tag`, and those four arrays share fifteen identical targets. That repetition is a consequence of the API, not a mistake to be tidied away; there is no spelling of "call two handlers when the user typed `merge`".
  - **The inventory is the reverse map.** Code states producer → locations; the slot inventory ([`../authoring/collecting-info.md`](../authoring/collecting-info.md) §Record every value slot while you collect) states command → producers. They must agree (`R-25`), which is why the code never needs a command-centric grouping.
  - **One spec per array.** The same location listed twice in one array injects twice; merging blocks is the edit that introduces it.
  - After any change, `./scripts/check-hook-targets.ps1 [name...]` — merging blocks is exactly the edit that can silently drop a target.
- **Targets — validate against the manifest before adding**: every `command`/`option` in a spec must exist in `completions/<cmd>/language/en-US.json` and be a location that actually takes a runtime value — commands need a positional placeholder (`usage` with `<...>`/`[...]` or a free-form position), options need `next: []`/`next: [...]` (value-taking). **Match the value kind to the slot**: judge by what the CLI itself accepts there — its `--help` usage, docs, and examples — not by the manifest alone. Never offer files at a context whose slot takes subcommands, names, keys, or nothing — e.g., offering a config file at a `build` subcommand slot where only subcommand names are valid. If a slot accepts files but the manifest shows no placeholder, add the `usage` placeholder (`[FILES]...`) so the slot is documented. For allowed `psc.ls` candidates in a relative file or directory slot, use `entry.name` as the completion `name`; use `entry.path` only when the slot requires an absolute path or as a tip.
- **A target names a slot, not a command that accepts the value.** An `option` target requires that option to take a value (`next`); the value of a valueless flag is a positional *after* it, and only a command target reaches it. A command target fires at the **first** unfilled positional, so a second positional (`<path> [<commit-ish>]`) is not targetable. A slot the user invents (`<new-name>`, `<key>`) gets no enumerating producer even when the same command's flag slot serves existing values; the compromise is recorded in the slot inventory.
- **A value kind is not one producer.** One slot may accept several kinds of name (a revision, a branch, a tag), and each kind is a separate producer with its own query and tip; offer the kinds the slot actually accepts, and record which ones you left out and why.
- **File candidates — hooks do not do path completion; native completion owns paths.** Default to no file candidates. Native path completion works **inside the current directory** and only once the user has typed a path prefix (`./`, `../`, `/`, `C:\`, `~/`); it never searches by name at a depth the user has not typed. A hook's file list is **unbounded by construction** — it grows with the repository — so it buries the subcommands and options the user is actually looking for, and the user normally already knows where their own file is. A hook adds nothing the shell cannot already give it, so the rule is a ban rather than a boundary.

**No hook may offer a file path as a completion candidate**, and this does not depend on how the path was obtained: `psc.glob` with or without a wildcard (`psc.glob(".env")` is still `psc.glob`), a `psc.ls` of the current directory, and a `psc.run` of `ls` all count the same.
Keying the rule on the API would only let an author route around it by picking another one — which is the drift a hard rule exists to prevent.
A fixed system list the slot itself accepts is the path-shaped case that is not a filesystem enumeration, and it is described below.

One exception is a **slot that takes a *name* the CLI cannot enumerate itself**, sourced from a known directory — `hugo --theme` wants a theme *name*, not a path, so `psc.ls("themes")` stands; `typst init` wants a package *name*, so `psc.ls` over the package cache stands.
All three of these must hold: the directory is known and fixed (`themes/`, not "any directory in the tree"), the candidate surfaced is `entry.name` and never `entry.path`, and the CLI's slot takes a name rather than a path.
Where a slot wants a path and there is nothing to enumerate, offer nothing and let native path completion take it.

A **fixed system list the slot itself accepts** is a value set, not an enumeration, even when its entries are paths.
`chsh --shell` accepts only a shell listed in `/etc/shells`, so `chsh`'s hook reads that file and offers its entries (`chsh`: a handful of entries, no glob and no directory walk).
All of these must hold: the file is the CLI's own validity rule for the slot, the set is small and bounded by configuration rather than by a tree, the CLI has no command that lists it, and native completion cannot tell a legal entry from any other file.
A directory of candidates that merely look related is still the banned case.

A **CLI-filtered subset** is a separate case and is not this exception: the hook runs a command whose own answer *is* the candidate set, so the set is bounded by what the user did rather than by how big the repository is.
It is legal only when the answer also carries something native completion cannot produce — a status code, not the bare path.
The two-question test that keeps it apart from general path browsing is in `../authoring/hooks.md`.

**The API is free; only the offering is banned.** `psc.glob` may discover the files that hold data the CLI cannot enumerate, provided the path never becomes the selectable value.
`scoop` globs `**/*.json` across every bucket and offers the app **names** read out of those manifests with `psc.json_batch` — no CLI call lists installable apps, so the glob is the only source and nothing can be moved into `next`.
`pm2` globs `ecosystem.config.*` and offers `name = p`: the path *is* the candidate, so it is out.

A **bare filename** is not a workaround.
Stripping the directory leaves a repository-sized list, so the objection stands; and a basename in a path slot is usually a broken argument.
What decides it is the slot's expected kind, not the shape of the string.
A path in a `tip` is explanatory text — it neither licenses an offering nor invalidates one.

Never register one handler that injects the same candidate list into several unrelated contexts (`{ command = "check" }, { command = "ci" }, { command = "format" }` all offering the same list) — the candidates then compete with each context's own options.
A **wandering** path handler has no slot to be registered at: those contexts have nothing to do with paths, so the list is noise everywhere it lands.
That is a claim about unrelated contexts, not about paths in general — a CLI-filtered subset has a real slot, and the two-question test in `../authoring/hooks.md` is what separates it from general path browsing.
- **Target names — the longest form, and check them mechanically**: `psc.on` matches a `command` segment against the **canonical** name (`bindings.rs` calls a segment *"an exact canonical name"*) and anchors the chain at the root, so a target naming an **alias** never fires — silently, with nothing reported. A manifest that stores `add` as an alias of `stage` cannot be targeted as `command = "add"`. Which spelling to write is not a judgement call: `sort-json.ps1` puts the longest form in `name` on every run, so **write the longest form** and the script has already made it canonical. A tool whose own primary name is shorter — jj's `evolog`, mise's `ls` — is normal and is not an error, because the tool's preference is not what `psc.on` compares against. Verify with `./scripts/check-hook-targets.ps1 [name...]`, which resolves every target against the manifest; it is the only check that catches this, since `compare-json` and `validate-completion` only look at internal consistency. Nine were found this way across the repository, all of this one kind. To find a canonical name: `python3 -c "import json;d=json.load(open('completions/X/language/en-US.json'));print([(i['name'],i.get('alias')) for i in d['next']])"`. Copy the manifest's spelling exactly, `=` included: an attached-value option is declared `--vo=`, so the target is `option = "--vo="`, not `"--vo"` — the engine strips one trailing `=` when matching, but `check-hook-targets.ps1` resolves the target literally, so the short form fails the gate.
- **Data — never write an empty tip**: some CLIs list an option with no description at all (podman does this for `--help` in some contexts), and a parser that transcribes faithfully will emit `"tip": [""]`, which the schema rejects. Substitute a generic description or drop the field; do not pass the empty string through.
- **One shape per producer — no plaintext retry**: read the structured form and stop there. A fallback earns its keep only from *evidence that a build cannot serve the first shape*; one justified by "the first read might fail" is dead code, because every reachable state either returns before it or reaches it with a valid empty result and turns it into a duplicate read. A retry between two forms of the same query is a different thing and is allowed (§10.1).

  ```lua
  -- right
  local data = psc.run({ "gh", "pr", "list", "--json", "number,title" }, { format = "json" }) or {}
  for _, pr in ipairs(data) do ... end

  -- wrong: a nil from format=json means the command itself failed -- no auth, no
  -- such repository, a field this build does not know -- and the retry returns
  -- nothing either, while hiding the reason. An empty menu says less than a
  -- command that visibly failed.
  if data then ... return end
  for _, line in ipairs(psc.run({ "gh", "pr", "list" }) or {}) do ... end
  ```
- **Offer every kind of a value at the same slots**: if a slot accepts one kind of ref it generally accepts the others. Tags are refs, so a branch-completion hook that fires in twenty-five places and a tag hook that fires in six leave `git describe` — whose entire job is resolving a tag — offering branches and commits but no tag. Keep the target lists of same-kind producers in step. Narrow deliberately where a kind is rarely wanted, and say why: remote branches go to `checkout`/`switch` only, because spreading `origin/*` through `log`/`describe` buries the local refs.
- **Do not reshape what a tool already prints**: ask for the form you want instead of post-processing. `git branch -r --format=%(refname:lstrip=2)` followed by a Lua `^origin/(.+)$` strip produced a name that collided with the local branch of the same name, and only ever worked for the remote literally called `origin`. `--format=%(refname:short)` needs no cleanup and behaves the same for every remote.
- **Naming — `add_*` for candidates**: prefer `local function add_*()` for candidate producers and pass the named function to `psc.on`. Helpers that only load config are `load_*`/`get_*` and are never registered directly. Anonymous `function() ... end` is allowed for one-off handlers that do not warrant a separate `add_*` abstraction; only avoid the redundant wrapper `psc.on({}, function() add_x() end)` — pass `add_x` directly: `psc.on({}, add_x)`.
- **Guards — `or {}` for iteration**: iterate with `psc.run(...) or {}` / `psc.glob(...) or {}` / `psc.ls(...) or {}`. Branch only when a fallback is needed (`if data then ... return end`).
- **Mapping — `psc.items` for pure mapping, loops for logic**: a loop body that only turns each result into a `name` (`for _, x in ipairs(...) do psc.add({ name = x }) end`) must be `psc.add(psc.items(... or {}))` instead; when the body parses, filters, or builds tips, keep the explicit `for` loop. Never force one form into the other's shape.
- **Early return — bare `return`**: use bare `return` (not `return nil`) to exit a helper/handler early — both mean `nil` per `§3 Hook contract`, but bare `return` is idiomatic and matches `git`/`jj`/`scoop`; never `return { ... }` in a file that uses `psc.on` (it discards `psc.on` contributions, `runner.rs:154` warns).
- **Layout — helpers then registrations**: put all `local function add_*/load_*` at the top, then all `psc.on` blocks together at the bottom, with a blank line between each `psc.on` block.
- **Cleanliness — no debug/sandbox leakage**: remove `psc.log` before committing (`types/psc.lua` marks it `@deprecated`); never `require`/`io`/`os.execute`/`os.getenv` etc. — sandbox `§11` forbids them.
- **Formatting — Lua idioms**: follow `git`/`jj`/`scoop`/`zoxide`:
  - tables/arrays do **not** add a trailing comma on the last element (`{ option = "--a" }` / `{ command = "exec" }`) — keep it clean;
  - `psc.on` specs: single spec `psc.on({ command = "exec" }, add_x)` on one line; multi-spec array `psc.on({{...},{...}}, add_x)` with one spec per line;
  - no semicolons; 4-space indent; keep lines short (wrap long `psc.run` arg lists).
- **References — when in doubt, copy the canonicals**: `completions/git/hooks.lua` (array `psc.on` merging, `--`/`type` value handling, `psc.run` `or {}`, `psc.run_batch` for a fixed command list, ref-shaped candidates), `completions/jj/hooks.lua` (`psc.run` with `format="json"`, `psc.mount_items`), `completions/gh/hooks.lua` (ten producers, one JSON shape each, no retries, two sibling queries batched), `completions/kind/hooks.lua` (`run_batch` for a real per-item fan-out inside a fallback chain), `completions/scoop/hooks.lua` (complex manifests, `psc.json_batch`/`psc.glob`, `psc.join` for `string|array` tips, `shell=true` for shims), `completions/zoxide/hooks.lua` (minimal `psc.on` with `multiple`). Skim one before writing a new hook, and run `./scripts/check-hook-targets.ps1` afterwards.

## 10. Performance: parallel primitives

The menu waits for the hook to finish before showing, so a slow hook delays every Tab press.
Hooks run in a **single Lua thread**; parallelism is deliberately confined to the Rust `*_batch` API (signatures in the §5 table).
Spec validation is equally one-shot: the engine walks the manifest **once** per hook run into a target index, so registering N specs never costs N walks no matter how large the manifest is.
The `*_batch` primitives run on a **bounded worker pool** and return the **full** result, so hook behavior is identical to a sequential loop — only wall-clock time improves.
Use them when iterating over many **independent** items; keep sequential logic when each step depends on the previous one's result (a two-pass parallel fetch can break such dependencies, e.g. bucket manifests needing `i.bucket` from the first pass):

```lua
-- Sequential: N file reads one after another
local names = {}
for _, m in ipairs(psc.glob("buckets/**/*.json")) do
    local c = psc.json(m)
    if c and c.name then names[#names + 1] = c.name end
end

-- Parallel: collect paths, parse them all at once
local names = {}
local maps = psc.json_batch(psc.glob("buckets/**/*.json"))
for _, c in pairs(maps) do
    if c and c.name then names[#names + 1] = c.name end
end
```

Do **not** spawn threads from Lua.

### 10.1 Two hand-written calls, not just a loop

The example above is fan-out over N items.
A producer that issues **two separate `psc.run` calls** is the same question and needs the same answer: if the second does not consume the first's output, batch them.

```lua
-- wrong: two independent queries, run one after the other
for _, b in ipairs(psc.run({ "git", "branch", "--format=%(refname:lstrip=2)" }) or {}) do
    if not b:match("^%(.+ detach") then psc.add({ name = b, tip = "branch" }) end
end
for _, b in ipairs(psc.run({ "git", "branch", "-r", "--format=%(refname:short)" }) or {}) do
    if not b:match("/HEAD$") then psc.add({ name = b, tip = "remote branch" }) end
end

-- right
local r = psc.run_batch({
    { "git", "branch", "--format=%(refname:lstrip=2)" },
    { "git", "branch", "-r", "--format=%(refname:short)" }
}) or {}
for _, b in ipairs(r[1] or {}) do
    if not b:match("^%(.+ detach") then psc.add({ name = b, tip = "branch" }) end
end
for _, b in ipairs(r[2] or {}) do
    if not b:match("/HEAD$") then psc.add({ name = b, tip = "remote branch" }) end
end
```

Wall clock is rarely the reason — two `git branch` calls in a small repository measured 6.0 ms against 4.3 ms.
The better reasons are that `run_batch` drains stdout concurrently, so a query with large output (`git branch -r` on a repo with many remotes) cannot wedge on a full pipe, and that the rewrite costs nothing in clarity.

**The trap: a retry chain looks identical and must stay sequential.** The second command should not run at all when the first succeeded, so batching it changes behaviour, not just timing:

```lua
-- retry, NOT batchable
local lines = psc.run({ "copilot", "plugins", "list" })
if not lines then lines = psc.run({ "copilot", "plugin", "list" }) end

-- also a retry, and harder to see: the fallback is inside the expression
local lines = psc.run({ "sfsu", "list" }) or psc.run({ "scoop", "list" }, { shell = true })
```

Neither shape can be detected by looking for an early `return` or a deeper indentation — the second call sits at the same level in both.
Decide by asking whether the second command is *wanted* when the first succeeds, not by looking at the code's shape.

## 11. Security

- **Sandbox**: Lua sees only `psc.*` + a restricted standard library. The safe, side-effect-free libs `table`/`string`/`math`/`utf8`/`coroutine` are available; `os` keeps only the harmless time/locale functions (`time`/`date`/`clock`/`difftime`/`setlocale`). All direct system access is disabled — `io`, `package`/`require`, `dofile`/`loadfile`/`load`, `debug`, and `os.execute`/`os.exit`/`os.remove`/`os.rename`/`os.tmpname` are removed; `os.getenv` is removed too (use `psc.env` instead, the single entry for environment variables). Reading files goes through `psc.read`/`psc.json`/`psc.ls`/`psc.glob`; subprocesses go through `psc.run` (timeout, captured output, cross-platform).
- **Timeout**: `psc.run` defaults to a 5 s timeout for a single subprocess, and the whole hook script is capped at 10 s (checked by an instruction-count hook) so neither a hung command nor an infinite Lua loop can block completion. The cap covers Lua instructions and subprocess waits. Blocking file APIs are **not** covered by the instruction-count hook (a native walk executes no Lua instructions, so the VM hook can never fire mid-call); `psc.glob` therefore carries its own **500 ms budget** and stops there, and `psc.read`/`psc.json`/`psc.ls` stay untimed — a hung network share can still block those (a known limitation, not a sandbox escape).
- **Glob is time-bounded, not count-bounded**: the 500 ms budget is per `glob` call and is deliberately far below the 10 s hook cap — a completion menu that waits seconds is broken no matter what it finds. A walk that runs out of time returns the matches it already found, so the result is a **partial** array (the shallowest matches arrive first, and those are nearly always the wanted ones) rather than a hang. There is deliberately **no** match-count cap: the menu scrolls without a practical item limit, so a result is never truncated merely for being large. A hook that needs completeness over a huge tree must not rely on `glob` — narrow the pattern instead. Note the budget is per call, so a hook making several `glob` calls spends up to 500 ms each.
- **Read-only files**: file APIs are read-only.
- **Windows shim executables**: `psc.run` spawns the command directly — on Windows, batch/powerShell **shims** (e.g. `scoop`'s extension-less wrapper) cannot be spawned that way. Run them through the shell instead: `psc.run({ "scoop", "config" }, { shell = true })`. (Or wrap manually with `cmd /c` when you need precise control.) Prefer `psc.which` first when in doubt.
- **Trust model**: a completion's `hooks.lua` runs with the full `psc.*` power — `psc.run` can execute arbitrary subprocesses in the user's cwd, and `psc.read`/`psc.glob` can read any file. Installing a completion means trusting its hooks; see `trust.md` for the sandbox guarantees, official sources, and the custom-source warning.

## 12. Logging: `psc.log` (debug) and `error.log` (runtime)

Two append-only logs live side-by-side in the host-provided `log_dir` (`data/temp/log/`), share the same rotation/retention and the same “empty dir disables silently” rule:

- `debug.log` — written by `psc.log(...)` (dev-time, explicit). Sits apart from the layer-A pure-data functions:

  ```lua
  psc.log(branches)                   -- data/temp/log/debug.log
  psc.log(fn())                       -- every returned value, one per line
  ```

Accepts **any number of arguments** and appends a formatted dump of each (any type, recursively expanded: primitives, tables with numeric keys `[N]` first then sorted string keys, functions as `<function>`, cyclic references as `<cycle>`, long strings truncated) to `debug.log` — one line per value.
A multi-return call like `psc.log(fn())` prints every value; none is mistaken for a file name.

- `error.log` — written by the engine on hook runtime failures (spec validation, unknown target, handler panic, recursion; see §8). Same directory as `debug.log` (`data/temp/log/error.log`); never a process fault — the failing registration/handler is inert, siblings/partial mutations persist.

Common rules (applied by the engine on each append to either file):

- Each line is prefixed with a local timestamp (`YYYY-MM-DD HH:MM:SS`).
- **Size cap (1 MB)**: when the file exceeds 1 MB, the front half is dropped and the tail is kept from the next complete line, prepended with a `[truncated]` marker.
- **Age (7 days)**: an mtime older than 7 days is removed before appending, so long-unused logs are reset.
- Empty `log_dir` (host not configured) disables both logs silently.

`psc.log` is a **development-time** tool.
In `types/psc.lua` it is marked `@deprecated` so the editor highlights every `psc.log` call in `hooks.lua`, reminding the author to remove it before shipping.
