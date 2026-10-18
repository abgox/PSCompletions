# Design: config support across the bridges

One place that says, for every config key, **which layer acts on it** and whether each
shell bridge honours it. Without this, "supported" is guesswork: a key can look wired up
while one shell silently ignores it, and a new key can be added with no one noticing that
three bridges owe it an implementation.

`design/menu.md` stays canonical for types, ranges and defaults; this file only records
**who implements what** and where it is asserted.

## Two layers

- **Engine** (`psc-menu`): the bridge only forwards these; behaviour is identical in every
  shell, so there is no per-bridge code and nothing for a bridge's tests to prove beyond
  the forwarding itself.
- **Bridge**: the shell must implement it itself (the engine never sees it). Every row in
  the second table is a per-bridge promise and must have a test in each bridge's suite.

## Engine-side keys

`show_mode`, `filter_mode`, `enable_list_loop`, `enable_apply_when_single` (the "only one
match → no pick needed" behaviour; PS hands it to the menu input, the engine acts on it),
`enable_apply_when_no_match`, `color_focus`, `color_match`, `enable_tip`,
`enable_tip_usage`, `enable_tip_example`, `enable_cache` (the engine's 10 s built-candidate
cache — **not** the bridges' session caches, which hold settings and are not gated by it),
and the `switch` / `stay` context symbols.

They reach the engine through three channels: the `flags` block, `context_switch` /
`context_stay`, and `raw_config.global` — the bridges pass **every scalar** config entry
through `raw_config`, so a new engine-side scalar needs no bridge change at all. That
forwarding is asserted (`menu config forwarded` in every suite), which is also what makes
"no bridge work needed" a claim rather than an assumption.

## Bridge-side keys

| Key | PS | bash | zsh | fish | Notes | Asserted by |
| --- | --- | --- | --- | --- | --- | --- |
| `trigger_key` | ✓ live (PSReadLine) | ✓ bound at load | ✓ bound at load | ✓ bound at load (`default` + `insert` keymaps) | a runtime change applies to the **next** shell; the current session keeps the previous key working, because unbinding it would leave that key dead (`bindkey -r`/`bind -r` do not restore the shell's own binding, and fish cannot list or unbind a modified key) | `read_trigger_key` cases; fish: `key …`, `trigger bound (default)` / `(insert)` |
| `enable_native_completion` | ✓ host menu (`MenuComplete`) | ✓ capture / `compgen` fallback | ✓ capture / enumeration fallback | ✓ ask (`complete -C`) | `0` → bash/zsh complete nothing at all; **fish hands the trigger to its own completion** (`commandline -f complete`) — it has the per-key fallback they lack, so this matches PS | bash/zsh: `native off returns 1`; fish: `native off hands off` |
| `enable_append_space` | ✓ | ✓ | ✓ | ✓ | a space is appended only for an **ordinary** candidate. No space for: the engine's `nospace`, a completion ending in `=` (attached value — the cursor stays behind it), a word that already follows the cursor, or a **container (directory)** — a container never takes a space, and its separator is a separate concern (`enable_path_trailing_separator`). PS additionally suppresses it for non-path result *types* (Method/Property/Variable/Type/Namespace), which shell captures carry no type information for | `_psc_apply` cases; bash: `suffix: …` cases; fish: `apply-*` cases; all: `pick dir + separator on` / `off` |
| `enable_path_trailing_separator` | ✓ container separator | ✓ directory → `/` | ✓ same | ✓ same, except that fish's candidates **already** carry the `/`, so `0` strips it instead of not adding it | only decides *whether* the separator is present; a directory without it still gets no trailing space | `pick dir + separator on` / `off` in all three suites |
| `enable_sort_by_history` | ✓ | ✓ `--sort` pass over the candidates | ✓ `_psc_sort_candidates` (`--sort`, same input) | ✓ `_psc_sort_native` (`--sort`, same input) | without it native items keep the host's own order; candidates are deduped by completion text before ranking so display/tip stay aligned. The engine reads **plain command lines**, so a host whose history file is not one-per-line must normalise it — and each bridge now does, in `_psc_hist`, writing a copy that is rebuilt only when the source is newer: fish always (YAML-ish `- cmd: …`), zsh under `setopt extended_history` (`: <beginning>:<elapsed>;cmd`, stripped), bash under `HISTTIMEFORMAT` (`#<epoch>` lines, dropped). The strip is a no-op for a plain file, so it cannot misfire | `sort_by_history adds order`; `history-normalised` (bash, zsh); fish: `history-path`, `history-lines`; zsh: `sort keeps candidates and their tips`, `sort_by_history off is a no-op` |
| `enable_hooks` (per-completion) | ✓ | ✓ gate | ✓ gate | ✓ gate | `psc` itself is exempt | hooks-gate cases |
| `language` | ✓ | ✓ | ✓ | ✓ | resolved from `settings.json`, never from the per-session cache (a bare `psc` before the first Tab must not print in the wrong language) | `lang-without-init` |

## Adding a key

1. **Engine-side** → no bridge work. If it is a scalar it is already forwarded through
   `raw_config`; if it is not, extend the `flags` / context plumbing in every bridge.
2. **Bridge-side** → implement it in *every* bridge, add the row above, and add a case to
   each suite (`scripts/bridge/test.bash`, `scripts/bridge/test.zsh`,
   `scripts/bridge/test.fish`). A row without a test is a defect in this table, not a
   documentation gap: the whole point is that unverified support is indistinguishable from
   no support.
