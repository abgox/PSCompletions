# Design: Filter Matching (completion menu filter)

> Reference for how the completion menu filter matches items.
> Companion docs: `design/psc-cli.md` (CLI surface), `design/hooks.md` (hooks).

## 1. Two matching modes

The menu filter has two mutually exclusive modes, chosen by the `menu` group config
`filter_mode` (default `"wildcard"`):

| Mode | Config value | Default behavior |
| --- | --- | --- |
| Subsequence | `subsequence` | chars match **in order**, non-contiguously, **all chars literal** |
| Wildcard | `wildcard` | `*` wildcards; everything else literal (contiguous) |

Both modes are case-insensitive at the **ASCII level** (`eq_ignore_ascii_case`): `A` matches `a`
and vice versa, but non-ASCII letters (e.g. `é` vs `É`) do **not** fold — matching is ordinal, not
culture/Unicode-aware. The filter matches against the item's **rendered row text**
(`list_item_text`), not the completion text or aliases.

## 2. Subsequence mode

- Every char of the filter must appear in the item text **in order**, not
  necessarily contiguously. **`*`, `?`, `**` have no special meaning — they are
  ordinary literal characters.**
  - `vscode` → matches `Visual Studio Code`.
- **`^` prefix**: anchors the **first pattern char** at the start of the item; the
  rest still matches as subsequence.
  - `^add` → the item starts with `a`, and `dd` appears in order afterwards.
  - `^*add` → the item starts with the literal `*`, then `add` in order (the `*`
    is a literal pattern char, and `^` anchors it).

## 3. Wildcard mode

- **`*`** — matches any number of characters (including zero).
  - `a*b` → `ab`, `acb`, `a123b`, …
- **`**`** — the escape for a literal `*` (greedy pairing, left to right).
  - `a**b` → the literal substring `a*b`.
  - `a***b` → `a*` (literal) then anything, then `b`.
- **Leading single `*` (not `**`) forces subsequence mode.** The marker is
  stripped and the rest is subsequence-matched with **every char literal** (no
  `**` escape, no `?`/`*` special meaning).
  - `*abc` → subsequence `a-b-c` (not contiguous).
  - `*a*b` → subsequence `a`, literal `*`, `b` in order.
  - `*^abc` → subsequence of the literal chars `^`, `a`, `b`, `c` (the `^` is
    literal because it is not the first char of the filter).
- **Every other character is literal**, including `?`, `[`, `]`, backtick and
  backslash.
- **`^` prefix**: anchors the **whole** pattern at the start of the item.
  - `^git` → the item starts with `git`.

## 4. `^` and `*` are mode-dependent / position-dependent

- `^` only acts as the prefix marker at the **very first char** of the filter.
  Elsewhere it is a literal.
- `*` at the start only forces subsequence in **wildcard** mode. In subsequence
  mode it is a literal char.

| Filter | Subsequence config | Wildcard config |
| --- | --- | --- |
| `abc` | subsequence `a-b-c` | contains `abc` |
| `^abc` | `a` anchored + `bc` subsequence | starts with `abc` |
| `*abc` | literal `*abc` subsequence | force subsequence: `a-b-c` |
| `^*abc` | `*` anchored + `abc` subsequence | force subsequence: `a` anchored + `bc` |
| `**abc` | literal `**abc` subsequence | contains literal `*abc` |
| `^**abc` | `*` anchored + `*abc` subsequence | starts with literal `*abc` |
| `a*b` | subsequence `a-*-b` | `a` any `b` |
| `a**b` | subsequence `a-**-b` | contains literal `a*b` |
| `a?b` | subsequence `a-?-b` | contains literal `a?b` |
| `^a*b` | `a` anchored + `*-b` subsequence | starts with `a`, any, then `b` |
| `*a*b` | literal `*a*b` subsequence | force subsequence: `a-*-b` (literal `*`) |
| `*a**b` | literal `*a**b` subsequence | force subsequence: `a-`**`-b` (literal) |
| `*^abc` | literal `*^abc` subsequence | force subsequence: literal `^abc` |
| `^^abc` | `^` anchored + `abc` subsequence | starts with literal `^abc` |

## 4.1 Edge cases

- **Empty filter** matches **every** item (the full list is returned unchanged); a filter
  consisting only of whitespace is treated as a literal string (a space cannot be typed into
  the filter — the space key applies the selection — so this is unreachable in practice).
- **No end anchor**: there is no `$` operator. Only `^` anchors to the start of the item;
  everything else is a contains/subsequence match. `$` is an ordinary literal character.
- **No length cap**: each keystroke re-scans the full candidate list linearly (with the
  highlight pass for the selected row); there is no index or substring cache. Candidate lists
  are typically tens to a few hundred items, so this is fine; very large lists (thousands)
  would benefit from caching, which is currently out of scope.

## 5. Design decisions

- **`?` is a literal character** (no single-char wildcard). PowerShell `-like` heritage proved
  almost never useful for completion names; treating `?` literally keeps the grammar minimal.
- **`**` self-escape for a literal `*`.** Escaping is rare (names rarely contain
  `*`); a self-documenting "double star = literal star" keeps the grammar minimal.
- **`*` at the start forces subsequence in wildcard mode.** A leading `*` is
  otherwise redundant in wildcard mode (the pattern is already wrapped in a
  wildcard), so reusing it costs nothing and gives a quick way to switch to fuzzy
  matching. In subsequence mode `*` stays literal (no force marker).
- **`^` anchors "the start"; the granularity follows the mode** — subsequence
  anchors the first pattern char, wildcard anchors the whole pattern.

## 6. Implementation

- `core/engine/src/menu/filter.rs`:
  - `filter_items` — entry point: strips a leading `^`, resolves mode (subsequence
    config, or wildcard with `**` / leading-`*` / plain), then matches.
  - `subsequence_match` / `prefix_subsequence_match` — subsequence mode.
  - `parse_wildcard` — tokenizes into `Pat` (`Lit` / `Any`).
  - `wildcard_match` — wildcard matching with backtracking.
  - `wildcard_segments` / `wildcard_highlight` — highlight byte ranges.
- `state.rs::match_segments` — public highlight entry used by the menu UI; resolves
  the mode exactly like `filter_items` so highlights always match.
- Config: `filter_mode` (`menu` group).

## 7. Examples

Representative real-world filters (the full per-filter behavior across both modes lives in the
table in §4):

| Filter | Mode | Matches |
| --- | --- | --- |
| `g*t` | wildcard | `git`, `gist`, `g--t` |
| `*vscode` | wildcard | force subsequence: `v-s-c-o-d-e` in order |
| `gt` | subsequence | `gta`, `git`, `great` |
| `?` | either | literal `?` in both modes |
