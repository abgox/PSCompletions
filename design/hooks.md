# PSCompletions Lua Hooks

> Status: **current**. Dynamic completions run as Lua scripts inside the Rust core process.
> This is the authoritative reference for the hooks subsystem — architecture, contract, and the
> full `psc.*` API. Operating manual for the completions workflow: `AGENTS.md`.
>
> **Editor experience**: `types/psc.lua` models the `psc` global and `completions`
> with EmmyLua annotations — with the VSCode "Lua" extension you get autocomplete and argument
> checks inside `completions/*/hooks.lua`.

## 1. Role of hooks

Static manifests capture a tool's fixed structure (subcommands, options, aliases, tooltips).
Dynamic values — things that depend on **runtime local state** (git branches, npm scripts,
installed packages, files, env vars) — cannot be known at authoring time. Hooks fill that gap:

- Hook output is **merged** with the static items, never a replacement.
- The hook runs only when the tool's `config.json` has `"hooks": true` and `hooks.lua` exists.

## 2. Architecture

```
Rust core process:
  manifest parse → build tree → context resolution → seed live list (static expansion) → run Lua hook (top-level + psc.on handlers) → build items → menu → output

PowerShell thin bridge:
  capture line/cursor → write context JSON → spawn core → apply the selected item
```

- Lua runs **in-process** via `mlua` (no separate interpreter process, no IPC cost).
- Rust **pre-parses the context** (subcommand path, pending token, last option, completed
  tokens) and exposes it as `psc.*` values, so hooks never rebuild it from raw input.
- The `completions` global is the **live candidate list**, seeded once with the static expansion
  (one row per alias form). Hook top-level code and `psc.on` handlers mutate it directly via
  `psc.add` or plain Lua table operations; whatever it holds when the hook finishes is what the
  menu shows (after repeat filtering and symbol/tip overrides).
- `psc.on(spec, handler)` registrations are evaluated **at most once per build**,
  handlers run sequentially.

## 3. Hook contract

The `hooks.lua` script's **top-level body** is unconditional direct manipulation, and
`psc.on(spec, handler)` registrations are conditional direct manipulation — both
operate on the same live `completions` list.

> Encoding: a leading UTF-8 BOM is stripped before execution (Windows editors often emit
> one), mirroring the BOM-tolerant read of static manifests.

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
- Top-level code and `psc.on` handlers mutate `completions` directly: `psc.add(item)` appends,
  `completions[i] = ...` / `table.insert` can rewrite.
- Return `nil` (or nothing) → live list is the result. Returning an explicit array **replaces**
  the live list entirely (documented: do not mix a replacing return with `psc.on` in the same file;
  the engine warns when an explicit return discards `psc.on` contributions).
- Completion item shape: `{ name, tip?, usage?, example?, repeat_count? }`.
  `usage` / `example` are optional text lines shown as the `[Usage]` / `[Example]` tip sections.
  `repeat_count` defaults to `0` (a used item is filtered from the next menu); set N to keep
  offering it until N uses. The field is `repeat_count` because `repeat` is a Lua keyword.
- **`text` is an engine-internal field**: everywhere a hook can see an item, it is the `name` key.
  Do not read or write `text` on items.
- The menu performs filtering/prefix matching; hooks return the **full candidate set** via the live list.
  Dynamic items added via `psc.add`/`psc.on` are ordered **before** static items so contextual completions are visible first; history-based ranking (`order.rs`) then applies within that sequence.

## 4. psc.\* Context Values

| Field | Meaning |
| --- | --- |
| `psc.tokens` | **Completed** tokens, each `{ name, type, input }`. `name` is the **canonical** name of a known command/option (alias input still points at the main name); `type` ∈ `command`/`option`/`value`/`unknown`; `input` is the user's raw input (possibly an alias, lowercased). **Excludes the word being typed.** A token consumed as an option's value (even a non-matching one) has `type = "value"`; `"unknown"` only appears outside an option's value position. |
| `psc.typing` | The token currently being typed (unfinished): `name`/`type`/`input` (same shape as a token element, `name` is best-effort and often empty) plus `option_like` — whether the input starts with `-` (heuristic, not definitive). Opposite of `tokens`: one is in progress, the other completed. When completing an option's value position, `type` is `"value"` (even for free-form values). |
| `psc.config` | The current command's **final** completion config, merged by the engine from three layers (later layers override earlier): **global config** (`psc config menu`, e.g. `enable_tip`) → **manifest `config` array defaults** (e.g. `max_commit: 30`) → **per-completion overrides** (`psc completion <name>`, e.g. `max_commit: 50`). Every key always has a value — no manual `or` fallback needed. Built-in keys: `enable_tip` / `enable_tip_usage` / `enable_tip_example` (bool, default `true`), `language` (same as the module's current language). Empty table when unconfigured (never nil). |
| `psc.manifest` | The parsed manifest (JSON → table); hooks can read static data (e.g. git config keys). |
| `psc._data` | **psc completion only** — aggregated module data (`settings.json`/`completions.json`) surfaced when manifest is `completions/psc`, else nil |
| `psc.cwd` | The current working directory. |
| `psc.platform` | The current system platform. (`"windows"` / `"macos"` / `"linux"`) |

## 5. psc.\* Capability Functions (Rust)

The functions split into three groups: **completion-item** (build/manipulate completion
items), **data acquisition** (fetch data from the system), and **data operations** (generic
array/string tools).

### Completion-item

| Function | Returns | Description |
| --- | --- | --- |
| `psc.items(elements, fn?)` | `psc_item[]` | Convert each element into a completion item. Without second arg the element itself is `name`; with a function `fn(elem)` returns the item table (`nil` skips). |
| `psc.mount_items(manifest_path)` | `psc_item[]` | **Pure transform** (like `psc.items`): convert the **direct children** of a manifest `next`/`option` array into completion items — returns an array, does **not** add to `completions` (inject via `psc.add`); **no recursion**. The path starts from the **manifest root object** (any top-level field: `"next"`, `"info"`, ...) and descends by name to the target item — **segments match by name, exactly, case-sensitive** — e.g. `psc.mount_items({ "next", "config", "set", "next" })` = the children of `manifest.next.config.set.next`. **Intermediate segments navigate through `next` arrays only** (an `option` array cannot be traversed mid-path). The **last** element selects the source array and **must** be `"next"` or `"option"` — any other last element converts nothing. Each child keeps its `name`/`tip`/`usage`/`example`; **Deeper levels are handled by the engine's own `next` navigation** (selecting a child whose manifest entry has a `next` enters that context), or by calling `mount_items` again with a longer path built from `psc.tokens`; to convert both `next` and `option` of the same node, call twice. |
| `psc.add(item_or_items)` | `psc_item\|psc_item[]\|nil` | Append to the **live candidate list** (routes to the current accumulation target). `item_or_items` is a single item table or an array of tables; empty/missing `name` is skipped. Returns the stored entry table(s) **by reference** — post-call edits apply (e.g. `local e = psc.add({name="x"}); e.tip="new"`). Nil when nothing added. |
| `psc.on(spec, handler)` | — (nothing) | Declarative registration — bind a zero-arg `handler` to a location (root / command chain / option value position). Returns nothing: injection happens only inside the handler via `psc.add` / direct `completions` ops. Fires only while the location's slot is still unfilled; `spec.multiple = true` keeps matching after it was filled. See **Declarative `psc.on`** below. |
| `psc.token(spec?)` | `psc_token\|nil` | Find the **first** `psc.tokens` entry matching `spec` (`{name?, type?, case_sensitive?}`); `nil` spec or empty table → first token (any type); `name` filters by canonical name, `type` filters by `command`/`option`/`value`/`unknown` (e.g. `{type="command"}` checks existence of any command). Case-insensitive by default, `case_sensitive=true` for exact.|

### Data acquisition

| Function | Returns | Description |
| --- | --- | --- |
| `psc.run(argv, opts?)` | `string[]\|table\|nil` | Run a command, return stdout **as an array of lines**; **nil on failure/timeout** (incl. a non-zero exit). Default timeout 5000ms; stdout is drained concurrently (no deadlock on large output); stderr discarded. `opts`: `timeout` (ms), `cwd`, `format` (`"json"`/`"toml"`/`"yaml"` — parses stdout and returns the parsed table, nil when unparseable), `shell` (bool — run through the system shell, `cmd /c` on Windows / `sh -c` elsewhere; use it for batch/PowerShell shims like `scoop`), `env` (table — key-value pairs injected into the child process environment, merged with the inherited env), `capture_fd` (integer — captures an extra file descriptor, e.g. `8` for Python argcomplete which writes completions to fd 8, redirected to stdout via `8>&1`). |
| `psc.run_batch(cmds, opts?)` | `table<number, string[]\|table\|nil>` | Run **multiple commands in parallel**; results in input order. Same `opts` as `run` (parallel commands are of the same format); a failed/unparseable command yields nil at its index. |
| `psc.read(path)` | `string?` | Read a file as UTF-8 text; nil on failure. Resolved relative to `psc.cwd`. |
| `psc.read_batch({path,...})` | `table<path, string?>` | Read **multiple files in parallel**; `{ [original-path] = content }`, nil for a missing/unreadable file. |
| `psc.json(path)` / `psc.json_batch(paths)` | `table?` / `table<path, table?>` | Read + parse JSON. Single: nil on failure. Batch: nil at a path for a missing/unparseable file. |
| `psc.toml(path)` / `psc.toml_batch(paths)` | `table?` / `table<path, table?>` | Read + parse TOML. Single: nil on failure. Batch: nil at a path for a missing/unparseable file. |
| `psc.yaml(path)` / `psc.yaml_batch(paths)` | `table?` / `table<path, table?>` | Read + parse YAML. Single: nil on failure. Batch: nil at a path for a missing/unparseable file. |
| `psc.ls(path)` | `psc_path_entry[]?` | Directory entries `{name, path, is_dir, is_link}` (`path` is the entry's full resolved path); nil if the directory does not exist (an empty dir yields an empty array). `is_dir` follows symlinks (a symlink to a directory counts as a directory). |
| `psc.ls_batch({dir,...})` | `table<number, psc_path_entry[]?>` | List **multiple directories in parallel**; results in input order, nil at an index for a missing dir. |
| `psc.glob(pattern)` | `string[]?` | Glob matching (supports `*`/`?`/`**` and `{a,b}` alternation via `globset`); the pattern resolves against `psc.cwd` (an absolute pattern ignores it); results are absolute and deduplicated; the walk respects `.gitignore`/`.ignore`/`.git/info/exclude` (like `ripgrep`) — ignored files are not returned; nil for an invalid pattern (a valid pattern with no match yields an empty array). |
| `psc.path(...)` | `string` | Normalize/join path segments into one path using the **native platform separator** (`\` on Windows, `/` elsewhere): a single argument normalizes its separators (on Windows `/` → `\`), multiple arguments are joined with that separator. Duplicate separators collapse (`psc.path("a/", "/b")` → `"a\b"` on Windows, `"a/b"` elsewhere); a leading separator (absolute segment) and a drive root like `C:\` are preserved. |
| `psc.exist(path)` | `boolean` | Whether the path exists (follows symlinks). |
| `psc.env(name)` | `string?` | Environment variable; nil if unset. |
| `psc.which(name)` | `string?` | Full path of the first executable found in PATH (PATHEXT on Windows, exec bit on Unix); nil when not found. |

> **Batch convention**: the `*_batch` suffix processes a whole group at once (parallel under the
> hood, but that is an implementation detail). Run/ls batches return results **in input order**;
> read/json/toml/yaml batches return `{ [original-path] = value }` maps. **Failure semantics are
> strict**: a failed/unreadable/unparseable entry yields **nil** at that position, matching the
> single-value APIs — hooks guard with `or {}` / `if x then` / `x and x.field`. `glob` needs no
> batch — one `**` call covers a whole tree.

### Data operations

| Function | Description |
| --- | --- |
| `psc.concat(...)` | Merge any number of arrays (variadic). |
| `psc.split(text, separator?)` | Split a string into an array by `separator` (default a space). |
| `psc.join(value, separator?)` | Accept a **string** (returned as-is) or an **array** (elements joined; non-strings are tostring'd), separated by `separator` (default a space). Useful to normalize a manifest field that may be a string OR an array (e.g. `psc.join(c.description, "\n")`). |
| `psc.contains(haystack, needle, opts?)` | Membership / pattern check. **Default**: `haystack` is a **string** (exact equality) or an **array** (exact membership), `needle` matched exactly (case-insensitive, `opts.case_sensitive` true makes it exact). **`opts.pattern` true**: `haystack` may be a **string or an array** — a string is matched against `needle` as a Lua pattern, an array matches when any element does (handles manifest fields that may be a string OR an array). |
| `psc.eq(a, b, opts?)` | String equality; **case-insensitive by default**, `opts.case_sensitive` true → exact. A **nil** argument never matches (returns `false`, never errors). |
| `psc.trim(text, opts?)` | Trim characters; whitespace by default, `opts.chars` (a string whose characters form the trim set) overrides it (an empty string trims nothing). `opts.mode` is `"start"`/`"end"`/`"both"` (default `"both"`). |

> **Optional behavior goes in an `opts` table** (`contains`'s
> `case_sensitive`/`pattern`, `trim`'s `mode`/`chars`, `run`'s `timeout`/`cwd`/`format`) — keys self-explain at the
> call site, extensible, consistent across the API.

## 6. Mental model

```lua
-- declarative (recommended): registrations run only when the location matches
psc.on({ command = "exec" }, function()
    for _, line in ipairs(psc.run({ "tool", "list" }) or {}) do
        psc.add({ name = line })
    end
end)
```

Inside a handler, empty results need no explicit guard — `psc.add` is a no-op on an
empty array or empty name:

```lua
psc.on({}, function()
    psc.add(psc.items(psc.run({ "git", "branch" }) or {}))              -- one item per line
    psc.add(psc.items(psc.ls("dir") or {}, function(e) return { name = e.name } end))
    psc.add(psc.mount_items({ "next", "config", "set", "next" }))
    -- return value is the stored table(s) by reference: post-call edits apply
    local e = psc.add({ name = "x" })
    e.tip = "new tip"
end)
```

Only branch on a result inside a handler when you genuinely need to (e.g. "no output → fall back") — use `completions` or `#items`.

## 7. Critical Semantics (pitfalls — follow these)

0. **Failure semantics are strict**: every data API returns `nil` on failure (`read`/`json`/
   `toml`/`yaml`/`env`/`which`, `run`/`run` with `format`/`ls`/`glob`, and each `*_batch`
   element). A "success but empty" result is distinct from failure — `run`/`ls`/`glob` yield an
   empty array on success with nothing to show, nil only on actual failure. Hooks guard with
   `or {}` (iterate), `if x then` (branch), or `x and x.field` (index) — the LSP surfaces these
   as optional types. No API throws on I/O or parse failure — a hook never crashes on bad input, it
   degrades to empty.

0. **Every API tolerates `nil` arguments** — passing a nil never crashes the hook; it
   yields the empty result for that API's type (`nil` for single-value readers and lookups
   like `token`, `false` for predicates like `exist`/`contains`/`eq`, an empty array for
   list/batch builders).
   `add` becomes a no-op. A nil element inside a batch list or `run` argv
   is skipped. **Callers are still responsible** for not applying operators to a nil result
   (`#psc.run(x)` when `run` returns nil fails) — guard with `or {}` as above.

1. **`psc.tokens` excludes the word being typed**; the partial word lives in `psc.typing`.
	   Therefore:
	   - `psc.tokens[#psc.tokens]` = **the last completed token**. Use it to detect "currently
	     completing an option's value" (e.g. `scoop install -a x86<TAB>` → last completed token is `-a`).
	   - `psc.token({name=name})` only finds **completed** tokens — the partial word being typed never
	     counts. An option-consumed value matches as `type = "value"` (not `"unknown"`).
 2. **Case — insensitive by default**:
    - **Name-matching APIs are case-insensitive by default** (`psc.contains`,
      `psc.token`, `psc.eq`)
    - **Token/input values keep the user's original casing** — `psc.tokens[].name` is the
      **canonical** name (aliases expanded, e.g. `-m` → `--move`), `psc.tokens[].input` is the raw
      input, **not lowercased**. Compare against literals with `psc.eq` (single value) /
      `psc.contains` (a list) or `psc.token({name="--move"})` instead of `==`.
3. **Lua patterns ≠ regex**: Lua patterns escape with `%` where regex uses `\` — `\d`→`%d`,
   `\w`→`%w`, `\s`→`%s`. Escape literal metacharacters too — `-` is the (lazy) quantifier, so a
    literal dash must be `%-` (e.g. `^%-%-` matches a leading `--`). This applies to
    `psc.contains` with `{ pattern = true }`.
4. **`gsub` returns two values** (string + replacement count). When used as the last argument of
   `table.insert` etc., or assigned to a single variable, wrap in parentheses:
   `table.insert(x, (s:gsub(" | ", "\n")))` or `local t = (s:gsub(...))`.
 5. **Manifest fields may be a string OR an array** (e.g. scoop's `description`, `pre_install`):
    check with Lua primitives, don't branch on `type(x) == "string"`. A **string** field is
    truthy in Lua when present (`if c.link`), an **array** field needs an explicit emptiness
    check because Lua empty tables are truthy (`if c.persist and next(c.persist) ~= nil`).
 6. **Encoding**: `psc.run` output goes through `from_utf8_lossy`; non-UTF-8 (e.g. GBK) content
    becomes `�`. Strip NULs from wsl's UTF-16 output with `line:gsub("%z","")`.
 7. **Do not reconstruct context from raw input**: use `psc.tokens` (filter by `type`) or
  	    `psc.token({type="command"})` / `psc.token({type="option"})` for the subcommand/option
  	    path, and `psc.tokens`/`psc.token` for "what was typed". Raw input is not canonical.
 	 8. **"Command/option wins" — option value vs known command/option**: an option that declares
 	    `next` (even empty) consumes the next token as its value — **unless** that token matches a
 	    known command or option, in which case the option acts as a flag (does not consume the
 	    token). After consuming a value, the context automatically resets to the nearest command
 	    context, so subcommands remain reachable. This means `psc.on({ option = "--flag" }, ...)`
 	    fires only when the next token is genuinely a free-form value, not a known command/option.

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

When several subcommands share the same value list, define the list **once** in the manifest (as
the `next` of a chosen node, e.g. `config` → `set` → `next`) and mount it from a handler with
`psc.mount_items({ "next", "config", "set", "next" })` — it returns the **direct children** of
that array with their tips. This keeps the values (and their localized tips) in the manifest
instead of hardcoding them in the hook:

```lua
psc.on({ command = { "config", "set" } }, function()
    psc.add(psc.mount_items({ "next", "config", "set", "next" }))
end)
```

### Declarative `psc.on`

The core primitive of the declarative hooks style: instead of branching on context and
stuffing a global table, declare where dynamic candidates live and who handles them.
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

- `spec.command` — command chain from the root (canonical names; string or array of
	  strings). `""` is a wildcard matching any command at that position; `{"", "set"}` matches
	  any depth-1 command's `set` child. Injects when the current layer chain equals it (segment-wise,
	  `""` matches any, others case-insensitive). The chain is **root-anchored**: its length
	  must equal the typed command depth. **Slot gating**: this pins the first positional
	  argument after the chain — by default an `unknown` token after the chain (a typed value
	  the engine does not recognize) suppresses injection, because the slot is already filled;
	  `multiple = true` keeps matching through any number of positional arguments.
- `spec.option` — an option chain matched as a **suffix** of the completed option sequence
	  (string = a length-1 chain; array = a contiguous suffix, in order). Option values never
	  enter the sequence, so `--move val --copy` still matches `{"--move","--copy"}`. `""`
	  wildcards a segment; other segments must start with `-`. The suffix is deliberately
	  NOT root-anchored: the option sequence has no root, and full anchoring would silently
	  break every existing single-option spec. An option with `next` (empty or not) consumes
	  the next token as its value (`type = "value"`), subject to "command/option wins" — a
	  known command or option takes priority, making the option act as a flag. After value
	  consumption, the context resets to the nearest command context, so subsequent
	  subcommands remain completable. **Slot gating**: this pins the value slot of the chain's
	  last option — by default injection requires that slot to be still unfilled (the last
	  completed token must be that option); once a value has been typed, `multiple = true` is
	  required to keep matching.
- `spec = {}` or omitted keys — targets the root context (the first positional argument).
	  `command` and `option` may coexist
	  as AND — both must match to inject (e.g. `{ command="install", option={"--color","--arch"} }`
	  = under `install` with the option sequence ending `--color, --arch`).
- `spec.multiple` — boolean, default `false`. The location's slot may keep matching after it
	  has been filled once. Command side: `{ command = "rebase" }` fires at `git rebase <Tab>`
	  but not `git rebase abcdefg <Tab>`; `{ command = "rebase", multiple = true }` fires at both
	  and at every further positional argument (known static values and dynamic `unknown`
	  inputs alike).
- **Spec arrays** — `spec` may be an array of spec tables (OR): any matching element injects;
	  each element independently follows the single-spec rules (including AND). Mixing named
	  keys with array elements in one table raises.
- Returns **nothing** — the placeholder table is gone; all output is via direct `psc.add` /
  `completions` ops inside the handler.
- Validation (failures are logged to `error.log` — a 1 MB-capped, 7-day-age-rotated file in
  `data/temp/log/`; see §12 — registration becomes inert — never a process fault):
  unknown spec keys raise; `command` segments must be strings, empty array rejected (omit to target root),
  `""` is wildcard; `option` segments must start with `-` (or be `""` wildcards), empty array rejected;
  the last named segment of each chain is resolved through the manifest at
  registration time (unknown targets raise, aliases accepted). For `AND` specs (`command`+`option`) either unknown side makes the whole spec inert (logged); single-key unknown still raises.
- Each registration runs **at most once per build** (inject only); handlers run sequentially.
- Handler is zero-arg, manipulates candidates via `psc.add` / direct `completions` ops; errors are
	  logged, partial mutations persist, siblings unaffected; `psc.on` inside a handler is a recursion error.

Injected items are part of the live list (no separate merge step) and participate in repeat filtering
like any dynamic item. Returning an explicit array from the hook still **replaces** the live list
(the engine warns when an explicit return discards `psc.on` contributions).

Boundaries (v1): `--opt=value` equals-form value positions are not detected.

### Localized tips

`tip` (in `psc.add`) accepts a **localized table** keyed by language code, so the
same item shows a translated description per user language:

```lua
psc.add({
    name = "svc",
    tip = {
        ["en-US"] = "Windows service",
        ["zh-CN"] = "Windows 服务",
    },
})
```

The engine picks the entry matching `psc.config.language`, falling back to `"en-US"`, then the first
entry. `en-US` is the required fallback key; `zh-CN` is optional. The language keys are declared
as named fields on `psc_localized` in `types/psc.lua`, so the editor completes `["en-US"]` /
`["zh-CN"]` inside the table literal and explains each key on hover. Extra language codes remain
allowed via the index signature.

## 9. Style Guide

This section is normative for AI and human authors. `design/hooks.md` is the style authority.

- **Comments — why only, one line**: explain *why* when the code is not self-evident, not *what*. Keep a single short line in **English**. Do not add a file header like `-- <tool> dynamic completions` or section labels like `-- node commands` — the `psc.on` spec already says it. Generic headers and what-only section comments are forbidden.
- **Registration — merge same handler**: multiple `psc.on` with the same handler must be a single array spec — `psc.on({{ option = "--a" }, { option = "--b" }}, add_files)` — not three separate `psc.on(..., add_files)` calls. See `§8 Declarative psc.on` for the `spec[]` OR form.
- **Targets — validate against the manifest before adding**: every `command`/`option` in a spec must exist in `completions/<cmd>/language/en-US.json` and be a location that actually takes a runtime value — commands need a positional placeholder (`usage` with `<...>`/`[...]` or a free-form position), options need `next: []`/`next: [...]` (value-taking).
- **Naming — `add_*` for candidates**: prefer `local function add_*()` for candidate producers and pass the named function to `psc.on`. Helpers that only load config are `load_*`/`get_*` and are never registered directly. Anonymous `function() ... end` is allowed for one-off handlers that do not warrant a separate `add_*` abstraction; only avoid the redundant wrapper `psc.on({}, function() add_x() end)` — pass `add_x` directly: `psc.on({}, add_x)`.
- **Guards — `or {}` for iteration**: iterate with `psc.run(...) or {}` / `psc.glob(...) or {}` / `psc.ls(...) or {}`. Branch only when a fallback is needed (`if data then ... return end`).
- **Early return — bare `return`**: use bare `return` (not `return nil`) to exit a helper/handler early — both mean `nil` per `§3 Hook contract`, but bare `return` is idiomatic and matches `git`/`jj`/`scoop`; never `return { ... }` in a file that uses `psc.on` (it discards `psc.on` contributions, `runner.rs:152` warns).
- **Layout — helpers then registrations**: put all `local function add_*/load_*` at the top, then all `psc.on` blocks together at the bottom, with a blank line between each `psc.on` block.
- **Cleanliness — no debug/sandbox leakage**: remove `psc.log` before committing (`types/psc.lua` marks it `@deprecated`); never `require`/`io`/`os.execute`/`os.getenv` etc. — sandbox `§11` forbids them.
- **Formatting — Lua idioms**: follow `git`/`jj`/`scoop`/`zoxide`:
  - tables/arrays do **not** add a trailing comma on the last element (`{ option = "--a" }` / `{ command = "exec" }`) — keep it clean;
  - `psc.on` specs: single spec `psc.on({ command = "exec" }, add_x)` on one line; multi-spec array `psc.on({{...},{...}}, add_x)` with one spec per line;
  - no semicolons; 4-space indent; keep lines short (wrap long `psc.run` arg lists).
- **References — when in doubt, copy the canonicals**: `completions/git/hooks.lua` (array `psc.on` merging, `--`/`type` value handling, `psc.run` `or {}`), `completions/jj/hooks.lua` (`psc.run` with `format="json"` + fallback, `psc.mount_items`), `completions/scoop/hooks.lua` (complex manifests, `psc.json_batch`/`psc.glob`, `psc.join` for `string|array` tips, `shell=true` for shims), `completions/zoxide/hooks.lua` (minimal `psc.on` with `multiple`). Skim one before writing a new hook.

## 10. Performance: parallel primitives

The menu waits for the hook to finish before showing, so a slow hook delays every Tab press.
Hooks run in a **single Lua thread**; parallelism is deliberately confined to the Rust `*_batch`
API (signatures in the §5 table). The `*_batch` primitives run on a **bounded worker pool** and
return the **full** result, so hook behavior is identical to a sequential loop — only wall-clock
time improves. Use them when iterating over many **independent** items; keep sequential logic when
each step depends on the previous one's result (a two-pass parallel fetch can break such
dependencies, e.g. bucket manifests needing `i.bucket` from the first pass):

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

## 11. Security

- **Sandbox**: Lua sees only `psc.*` + a restricted standard library. The safe, side-effect-free
  libs `table`/`string`/`math`/`utf8`/`coroutine` are available; `os` keeps only the harmless
  time/locale functions (`time`/`date`/`clock`/`difftime`/`setlocale`). All direct system access is
  disabled — `io`, `package`/`require`, `dofile`/`loadfile`/`load`, `debug`, and
  `os.execute`/`os.exit`/`os.remove`/`os.rename`/`os.tmpname` are removed; `os.getenv` is removed
  too (use `psc.env` instead, the single entry for environment variables). Reading files goes
  through `psc.read`/`psc.json`/`psc.ls`/`psc.glob`; subprocesses go through `psc.run`
  (timeout, captured output, cross-platform).
- **Timeout**: `psc.run` defaults to a 5 s timeout for a single subprocess, and the whole hook
  script is capped at 10 s (checked by an instruction-count hook) so neither a hung command nor an
  infinite Lua loop can block completion. The cap covers Lua instructions and subprocess waits;
  **file reads (`psc.read`/`psc.json`/`psc.ls`/`psc.glob`) are not timed** — a hung network share
  can block them (a known limitation, not a sandbox escape).
- **Read-only files**: file APIs are read-only.
- **Windows shim executables**: `psc.run` spawns the command directly — on Windows, batch/powerShell
  **shims** (e.g. `scoop`'s extension-less wrapper) cannot be spawned that way. Run them through the
  shell instead: `psc.run({ "scoop", "config" }, { shell = true })`. (Or wrap manually with
  `cmd /c` when you need precise control.) Prefer `psc.which` first when in doubt.
- **Trust model**: a completion's `hooks.lua` runs with the full `psc.*` power — `psc.run` can
  execute arbitrary subprocesses in the user's cwd, and `psc.read`/`psc.glob` can read any file.
  The sandbox only constrains the Lua standard library, not the `psc.*` surface. Installing a
  third-party completion therefore means trusting its hooks; the repo's completions are reviewed,
  but verify before installing from elsewhere.

## 12. Logging: `psc.log` (debug) and `error.log` (runtime)

Two append-only logs live side-by-side in the host-provided `log_dir` (`data/temp/log/`), share
the same rotation/retention and the same “empty dir disables silently” rule:

- `debug.log` — written by `psc.log(...)` (dev-time, explicit). Sits apart from the layer-A
  pure-data functions:

  ```lua
  psc.log(branches)                   -- data/temp/log/debug.log
  psc.log(fn())                       -- every returned value, one per line
  ```

  Accepts **any number of arguments** and appends a formatted dump of each
  (any type, recursively expanded: primitives, tables with numeric keys `[N]` first then sorted
  string keys, functions as `<function>`, cyclic references as `<cycle>`, long strings
  truncated) to `debug.log` — one line per value. A multi-return call like
  `psc.log(fn())` prints every value; none is mistaken for a file name.

- `error.log` — written by the engine on hook runtime failures (spec validation, unknown
  target, handler panic, recursion; see §8). Same directory as `debug.log`
  (`data/temp/log/error.log`); never a process fault — the failing registration/handler is
  inert, siblings/partial mutations persist.

Common rules (applied by the engine on each append to either file):

- Each line is prefixed with a local timestamp (`YYYY-MM-DD HH:MM:SS`).
- **Size cap (1 MB)**: when the file exceeds 1 MB, the front half is dropped and the tail
  is kept from the next complete line, prepended with a `[truncated]` marker.
- **Age (7 days)**: an mtime older than 7 days is removed before appending, so long-unused
  logs are reset.
- Empty `log_dir` (host not configured) disables both logs silently.

`psc.log` is a **development-time** tool. In `types/psc.lua` it is marked `@deprecated` so the editor
highlights every `psc.log` call in `hooks.lua`, reminding the author to remove it before shipping.
