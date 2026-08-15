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
  manifest parse → build tree → context resolution → run Lua hook → build items → menu → output

PowerShell thin bridge:
  capture line/cursor → write context JSON → spawn core → apply the selected item
```

- Lua runs **in-process** via `mlua` (no separate interpreter process, no IPC cost).
- Rust **pre-parses the context** (subcommand path, pending token, last option, completed
  tokens) and exposes it as `psc.*` values, so hooks never rebuild it from raw input.
- The hook script's top-level body is the completion logic: the engine pre-sets the `completions`
  global (static items) and the body's top-level `return` is the merged array (`nil` = static-only).

## 3. Hook contract

The `hooks.lua` script's **top-level body** IS the completion logic — there is no wrapper function.
`completions` is a global provided by the engine (the static item array); the body's top-level
`return` is the merged result:

```lua
if psc.current.option_like then
    return completions          -- completing an option name; static items are enough
end
local cs = {}
-- ... psc.* calls ...
return psc.merge(cs)
```

- `completions` — static item array, pre-set by the engine. Items use the **`name`** key.
- Return `nil` (or nothing) → static items only; return an array → **that array is used as-is**
  (the engine does **not** auto-merge static items — hooks append them explicitly via
  `psc.merge(cs)` / `psc.concat`).
- Completion item shape: `{ name, tip?, symbol?, usage?, example?, repeat_count? }`. `symbol` is the
  predict symbol **config key**: `"switch"` (`~`, switch to a new context) / `"stay"` (`?`, stay in
  the current context), or omit it for no symbol (nothing more to pick besides `global_option`).
  `usage` / `example` are optional text lines shown as the `[Usage]` / `[Example]` tip sections.
  `repeat_count` defaults to `0` (a used item is filtered from the next menu); set N to keep
  offering it until N uses. The field is `repeat_count` because `repeat` is a Lua keyword.
- **`text` is an engine-internal field**: everywhere a hook can see an item, it is the `name` key.
  Do not read or write `text` on items.
- The menu performs filtering/prefix matching; hooks return the **full candidate set**.

## 4. psc.\* Context Values

| Field | Meaning |
| --- | --- |
| `psc.cmds` | **Subcommand chain**: a filtered view of `psc.tokens` — the `name`s of its `type == "command"` entries (canonical names), **excluding the root command**. `git stash apply` → `["stash", "apply"]`; `cmds[1]` is the first, `cmds[#cmds]` the last. |
| `psc.tokens` | **Completed** tokens, each `{ name, type, input }`. `name` is the **canonical** name of a known command/option (alias input still points at the main name); `type` ∈ `command`/`option`/`value`/`unknown`; `input` is the user's raw input (possibly an alias, lowercased). **Excludes the word being typed.** |
| `psc.current` | The token currently being typed (unfinished): `name`/`type`/`input` (same shape as a token element, `name` is best-effort and often empty) plus `option_like` — whether the input starts with `-` (heuristic, not definitive). Opposite of `tokens`: one is in progress, the other completed. |
| `psc.opts` | **Option chain**: a filtered view of `psc.tokens` — the `name`s of its `type == "option"` entries (canonical names). `git branch -m -c` → `["--move", "--copy"]`. |
| `psc.config` | The current command's completion config (user-configured keys for this command, e.g. `psc.config.max_commit`); empty table when unconfigured (never nil). |
| `psc.manifest` | The parsed manifest (JSON → table); hooks can read static data (e.g. git config keys). |
| `psc.language` | The module's current language (`en-US` / `zh-CN`); picks the entry of a **localized tip table**. |
| `psc._data` | **psc completion only**|
| `psc.cwd` | The current working directory. |
| `psc.platform` | The current system platform. (`"windows"` / `"macos"` / `"linux"`) |

## 5. psc.\* Capability Functions (Rust)

The functions split into three groups: **completion-item** (build/manipulate completion
items), **data acquisition** (fetch data from the system), and **data operations** (generic
array/string tools).

### Completion-item

| Function | Returns | Description |
| --- | --- | --- |
| `psc.items(elements, fn?)` | `psc_item[]` | Convert each element into a completion item. **Without `fn`**, the element itself is the `name` (static; the element must be a string — other types are skipped). With `fn`, `fn(elem)` returns the item table; returning `nil` skips that element. The item table needs a `name` field (what `add` later reads). |
| `psc.mount_items(manifest_path)` | `psc_item[]` | Mount the **direct children** of a manifest `next`/`option` array as completion items (returns an array, does not add; **no recursion, no symbol**). The path starts from the **manifest root object** (any top-level field: `"next"`, `"info"`, ...) and descends by name to the target item — **segments match by name, exactly, case-sensitive** — e.g. `psc.mount_items({ "next", "config", "set", "next" })` = the children of `manifest.next.config.set.next`. **Intermediate segments navigate through `next` arrays only** (an `option` array cannot be traversed mid-path). The **last** element selects the source array and **must** be `"next"` or `"option"` — any other last element mounts nothing. Each child keeps its `name`/`tip`/`usage`/`example`; **no predict symbol is set** — a mounted item's symbol depends on the current context (what happens when selected there), not its original manifest position, so set it explicitly via `psc.set_symbol` when needed. **Deeper levels are handled by the engine's own `next` navigation** (selecting a child whose manifest entry has a `next` enters that context), or by calling `mount_items` again with a longer path built from `psc.cmds`; to mount both `next` and `option` of the same node, call twice. |
| `psc.add(cs, item_or_items)` | `integer` | Append a completion item (single table) or a batch (array of tables) to `cs`; returns the number actually added. **Empty or missing `name` is skipped** (no error); a stray `{ text = ... }` or a non-table element is dropped. `tip` defaults to the `name` when absent; may be a string or a **localized table**. |
| `psc.merge(cs)` | `psc_item[]` | End-of-hook convenience: return `cs` merged with the static `completions` (equivalent to `psc.concat(cs, completions)`). Used at the hook's final `return`. |
| `psc.set_symbol(name, symbol, opts?)` | — | Override the predict symbol of an item in the current context. `symbol` is `"switch"`/`"stay"`; any other value raises a Lua error. `name` matches **case-insensitively**; `opts.case_sensitive` true → exact. |
| `psc.set_tip(name, tip, opts?)` | — | Override or insert the tip of an item in the current context (same matching as `set_symbol`). `opts.mode` is `"set"` (default), `"prepend"`, or `"append"`; `opts.case_sensitive` true → exact. `tip` may be a string or a **localized table**; passing nil removes any previously-set tip. |
| `psc.has_unknown()` | `boolean` | Whether any **completed** unknown token exists (a value has been typed). |
| `psc.typed(name)` | `boolean` | Whether the canonical `name` appears among all completed tokens; an alias counts as its main name (matching the engine's repeat filter). Unknown/value tokens match by raw input. Case-insensitive. |
| `psc.typed_unknown(name)` | `boolean` | Whether `name` appears among completed **unknown** tokens (values only). Case-insensitive. |

### Data acquisition

| Function | Returns | Description |
| --- | --- | --- |
| `psc.run(argv, opts?)` | `string[]\|table\|nil` | Run a command, return stdout **as an array of lines**; **nil on failure/timeout** (incl. a non-zero exit). Default timeout 5000ms; stdout is drained concurrently (no deadlock on large output); stderr discarded. `opts`: `timeout` (ms), `cwd`, `format` (`"json"`/`"toml"`/`"yaml"` — parses stdout and returns the parsed table, nil when unparseable), `shell` (bool — run through the system shell, `cmd /c` on Windows / `sh -c` elsewhere; use it for batch/PowerShell shims like `scoop`). |
| `psc.run_batch(cmds, opts?)` | `table<number, string[]\|table\|nil>` | Run **multiple commands in parallel**; results in input order. Same `opts` as `run` (parallel commands are of the same format); a failed/unparseable command yields nil at its index. |
| `psc.read(path)` | `string?` | Read a file as UTF-8 text; nil on failure. Resolved relative to `psc.cwd`. |
| `psc.read_batch({path,...})` | `table<path, string?>` | Read **multiple files in parallel**; `{ [original-path] = content }`, nil for a missing/unreadable file. |
| `psc.json(path)` / `psc.json_batch(paths)` | `table?` / `table<path, table?>` | Read + parse JSON. Single: nil on failure. Batch: nil at a path for a missing/unparseable file. |
| `psc.toml(path)` / `psc.toml_batch(paths)` | `table?` / `table<path, table?>` | Read + parse TOML. Single: nil on failure. Batch: nil at a path for a missing/unparseable file. |
| `psc.yaml(path)` / `psc.yaml_batch(paths)` | `table?` / `table<path, table?>` | Read + parse YAML. Single: nil on failure. Batch: nil at a path for a missing/unparseable file. |
| `psc.ls(path)` | `psc_path_entry[]?` | Directory entries `{name, path, is_dir, is_link}` (`path` is the entry's full resolved path); nil if the directory does not exist (an empty dir yields an empty array). `is_dir` follows symlinks (a symlink to a directory counts as a directory). |
| `psc.ls_batch({dir,...})` | `table<number, psc_path_entry[]?>` | List **multiple directories in parallel**; results in input order, nil at an index for a missing dir. |
| `psc.glob(pattern)` | `string[]?` | Glob matching (supports `*`/`?`/`**`); the pattern resolves against `psc.cwd` and results are absolute; nil for an invalid pattern (a valid pattern with no match yields an empty array). |
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
| `psc.map(list, fn)` | Standard array map: apply `fn` to each element, return a new array of the same length; `fn` is required. |
| `psc.filter(list, fn)` | Generic array filter: keep the elements for which `fn` returns truthy (compacted; the complementary operation to `psc.map`). Filtering completion items by name is expressed with `fn` inspecting `it.name`. |
| `psc.concat(...)` | Merge any number of arrays (variadic). |
| `psc.split(text, separator?)` | Split a string into an array by `separator` (default a space). |
| `psc.join(value, separator?)` | Accept a **string** (returned as-is) or an **array** (elements joined; non-strings are tostring'd), separated by `separator` (default a space). Useful to normalize a manifest field that may be a string OR an array (e.g. `psc.join(c.description, "\n")`). |
| `psc.contains(haystack, needle, opts?)` | Membership / pattern check. **Default**: `haystack` is an array, `needle` matched exactly (case-insensitive, `opts.case_sensitive` true makes it exact). **`opts.pattern` true**: `haystack` may be a **string or an array** — a string is matched against `needle` as a Lua pattern, an array matches when any element does (handles manifest fields that may be a string OR an array). |
| `psc.eq(a, b, opts?)` | String equality; **case-insensitive by default**, `opts.case_sensitive` true → exact. A **nil** argument never matches (returns `false`, never errors). |
| `psc.trim(text, opts?)` | Trim whitespace; `opts.mode` is `"start"`/`"end"`/`"both"` (default `"both"`). |

> **Optional behavior goes in an `opts` table** (`contains`'s
> `case_sensitive`/`pattern`, `trim`'s `mode`, `run`'s `timeout`/`cwd`/`format`) — keys self-explain at the
> call site, extensible, consistent across the API.

## 6. Mental model

```
get data (psc.run / psc.ls / psc.json / ... or build your own table)
  → psc.items (or psc.map) turns it into completion items
  → psc.add(cs, ...) appends them
  → return psc.merge(cs)
```

Empty results need no explicit guard — `add` is a no-op on an empty array or empty name:

```lua
psc.add(cs, psc.items(psc.run({ "git", "branch" })))                  -- one item per line
psc.add(cs, psc.items(psc.ls("dir"), function(e) return { name = e.name } end))
psc.add(cs, psc.mount_items({ "next", "config", "set", "next" }))
```

Only branch on the result when you genuinely need to (e.g. "no output → fall back") — use `#items`.

## 7. Critical Semantics (pitfalls — follow these)

0. **Failure semantics are strict**: every data API returns `nil` on failure (`read`/`json`/
   `toml`/`yaml`/`env`/`which`, `run`/`run` with `format`/`ls`/`glob`, and each `*_batch`
   element). A "success but empty" result is distinct from failure — `run`/`ls`/`glob` yield an
   empty array on success with nothing to show, nil only on actual failure. Hooks guard with
   `or {}` (iterate), `if x then` (branch), or `x and x.field` (index) — the LSP surfaces these
   as optional types. `set_symbol`/`set_tip` validate their enum args and raise on invalid
   values. No API throws on I/O or parse failure — a hook never crashes on bad input, it
   degrades to empty.

0. **Every API tolerates `nil` arguments** — passing a nil (e.g. `psc.cmds[1]` at the root
   level, or `psc.tokens[#psc.tokens]` when nothing is completed) never crashes the hook; it
   yields the empty result for that API's type (`nil` for single-value readers, `false` for
   predicates like `exist`/`contains`/`typed`/`eq`, an empty array for list/batch builders).
   `set_symbol`/`set_tip`/`add` become no-ops. A nil element inside a batch list or `run` argv
   is skipped. **Callers are still responsible** for not applying operators to a nil result
   (`#psc.run(x)` when `run` returns nil fails) — guard with `or {}` as above.

1. **`psc.tokens` excludes the word being typed**; the partial word lives in `psc.current`.
   Therefore:
   - `psc.has_unknown()` = "a full value has been typed". `git checkout ma<TAB>` → has_unknown is
     false → branches are still offered.
   - `psc.tokens[#psc.tokens]` = **the last completed token**. Use it to detect "currently
     completing an option's value" (e.g. `scoop install -a x86<TAB>` → last completed token is `-a`).
   - `psc.typed_unknown(app)` never counts the partial word being typed.
 2. **Case — insensitive by default**:
    - **Name-matching APIs are case-insensitive by default** (`psc.set_symbol`,
      `psc.set_tip`, `psc.contains`, `psc.typed`, `psc.eq`)
    - **Token/input values keep the user's original casing** — `psc.cmds`/`psc.opts` are
      **canonical** (aliases expanded, e.g. `-m` → `--move`), `psc.tokens[].input` is the raw
      input, **not lowercased**. Compare against literals with `psc.eq` (single value) /
      `psc.contains` (a list) instead of `==`. Compare options against `psc.opts` **canonical**
      names (e.g. `psc.contains(psc.opts, "--move")`, not `"-m"`).
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
 7. **Do not reconstruct context from raw input**: use `psc.cmds` for the subcommand path,
    `psc.opts` for the completed options (the last one is `psc.opts[#psc.opts]`),
    `psc.has_unknown`/`psc.typed*` for "what values were typed". The three mean different things.

## 8. Common Pattern

```lua
if psc.current.option_like then
    return completions          -- completing an option; static items are enough
end
local cs = {}
local cmd1, cmd2 = psc.cmds[1], psc.cmds[2]

if psc.contains({ "a", "b" }, cmd1) and not psc.has_unknown() then
    psc.add(cs, psc.items(psc.run({ "tool", "list" })))       -- one item per line
elseif psc.eq(cmd1, "c") and psc.contains(psc.opts, "--x") then
    for _, v in ipairs({ "v1", "v2" }) do
        psc.add(cs, { name = v, tip = "tip for " .. v, symbol = "stay" })
    end
end
return psc.merge(cs)
```

### Mounting shared values defined in the manifest

When several subcommands share the same value list, define the list **once** in the manifest (as
the `next` of a chosen node, e.g. `config` → `set` → `next`) and mount it from hooks with
`psc.mount_items({ "next", "config", "set", "next" })` — it returns the **direct children** of
that array with their tips. This keeps the values (and their localized tips) in the manifest
instead of hardcoding them in the hook:

```lua
elseif psc.eq(cmd1, "config") and psc.contains({ "unset", "get" }, psc.cmds[#psc.cmds]) then
    psc.add(cs, psc.mount_items({ "next", "config", "set", "next" }))
end
```

For a deeper level, build a longer path from the current context (`psc.cmds`):

```lua
-- git config set user.name <TAB>: mount user.name's own next (if it has one)
elseif psc.eq(cmd1, "config") and psc.eq(cmd2, "set") and cmd3 then
    psc.add(cs, psc.mount_items({ "next", "config", "set", cmd3, "next" }))
end
```

### Localized tips

`tip` (in `psc.add`, `psc.set_tip`) accepts a **localized table** keyed by language code, so the
same item shows a translated description per user language:

```lua
psc.add(cs, {
    name = "svc",
    tip = {
        ["en-US"] = "Windows service",
        ["zh-CN"] = "Windows 服务",
    },
})
```

The engine picks the entry matching `psc.language`, falling back to `"en-US"`, then the first
entry. `en-US` is the required fallback key; `zh-CN` is optional. The language keys are declared
as named fields on `psc_localized` in `types/psc.lua`, so the editor completes `["en-US"]` /
`["zh-CN"]` inside the table literal and explains each key on hover. Extra language codes remain
allowed via the index signature.

## 9. Performance: parallel primitives

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

## 10. Security

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

## 11. `psc.log` — debug output

`psc.log` writes a log file and sits apart from the layer-A pure-data functions:

```lua
psc.log(branches)                   -- data/temp/log/debug.log
psc.log(fn())                       -- every returned value, one per line
```

- `psc.log(...)` accepts **any number of arguments** and appends a formatted dump of each
  (any type, recursively expanded: primitives, tables with numeric keys `[N]` first then sorted
  string keys, functions as `<function>`, cyclic references as `<cycle>`, long strings
  truncated) to `data/temp/log/debug.log` — one line per value. A multi-return call like
  `psc.log(fn())` prints every value; none is mistaken for a file name.
- Each line is prefixed with a local timestamp (`YYYY-MM-DD HH:MM:SS`).
- **Appends; never auto-cleaned** — remove the files manually when done.
- Empty log dir (host not configured) disables logging silently.
- A **development-time** tool. In `types/psc.lua` it is marked `@deprecated` so the editor
  highlights every `psc.log` call in `hooks.lua`, reminding the author to remove it before shipping.
