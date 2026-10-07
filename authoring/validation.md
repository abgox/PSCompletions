# Validation

Three gates, what each can and cannot see, and the checklists that cover the rest.

## The gates

| Gate | Command | What it checks |
| --- | --- | --- |
| Structure, usage, translation | `.\scripts\compare-json.ps1 <command>` | manifest shape, `usage` forms, `next` on options and commands, cross-language structure and translation completeness |
| Schema, config, hooks presence | `.\scripts\validate-completion.ps1 <command>` | JSON schema, `config.json` fields, `hooks` flag vs `hooks.lua` presence, Chinese/English spacing |
| Hook targets | `.\scripts\check-hook-targets.ps1 <command>` | resolves every `psc.on` target against the manifest |

Run with `<command>` to check one completion, or with `-All` for every completion (slower).
Without arguments `compare-json.ps1` checks only recently changed or uncommitted
completions.

**Fix every reported item until both run clean.** After changes stabilise, re-run
`compare-json.ps1 <command>` to confirm there are no _content_ differences.

### What the gates cannot see

- `check-hook-targets.ps1` is **mandatory whenever a `hooks.lua` exists or was touched.**
  It is the only check that catches a dangling `psc.on` target or one written as an alias —
  both fail silently at runtime. `compare-json` and `validate-completion` look at internal
  consistency only.
- **`compare-json` does not report a missing alias.** Record aliases exhaustively
  (`R-03`); nothing flags an omission.
- **`validate-completion` only checks that `hooks.lua` exists and is non-empty** — a clean
  gate says nothing about whether it compiles. Run
  `luac -p completions/<cmd>/hooks.lua` yourself. See
  [`tooling.md`](tooling.md).
- **The subcommand probe is manual** (`R-02`). `compare-json` and `validate-completion`
  both pass a "parent command modeled as a leaf" defect silently.
- **Everything in the portability audit below is manual.** Nothing scans for
  author-machine paths or Windows-only invocations.
- **Tip content is never verified.** `compare-json` checks that a `tip` exists and is
  translated; it never checks whether the tip is semantically accurate. A tip that understates
  what a flag does (e.g., "skip test compile" when it actually skips compilation *and*
  execution) passes every gate. Verify tip content against the CLI's own behaviour when you
  author or edit one.
- **Regex scanners cannot enumerate content reliably.** Ad-hoc regex searches for hook
  violations (e.g., scanning for `psc.glob` usage to find R-10 violations) miss dominant
  idioms (`ipairs(psc.glob(...))`), indirect references (local variable then `name = X`), and
  produce false positives on legitimate patterns. Content enumeration requires reading the
  source; a scanner is a starting point, not a verification.

## `compare-json` reports

These are the structural and usage issues `compare-json` raises. The usage-check buckets are
declared in the `DiffStats` class at `../scripts/psc-tools.cs:300-308` (the class opens at
line 290 and also holds the structural-diff buckets); `compare-json.ps1` only reads it back
as `$result.stats` at line 142 — it does not implement the checks itself. **If you add or
change a check there, update this table in the same commit.**

| Reported issue | Trigger | Fix |
| --- | --- | --- |
| Missing usage | item has an **alias** but no `usage` field | add `usage` showing `short, long` (option) or `short \| long` (subcommand) |
| Meaningless usage | no alias, no `next`, and the `usage` just repeats the name | remove the `usage` field |
| usage too simple | the `usage` equals the name, but the item has an alias or `next` | make the `usage` show the alias and/or a value placeholder, or remove it |
| usage order wrong | a long form comes before its short form | order short → long: `-s, --long` / `short \| long` |
| usage separator wrong | an option uses `\|`, or a subcommand uses `,` | options use `,`; subcommands use `\|` |
| option value without `next` | an option has `usage <...>` but no `next` field | add `next: []` (free-form value) or `next: [...]` (known candidates) |
| `next: []` on a command | an item inside a `next` array has an empty `next` | omit `next` for leaf commands, or fill in real subcommands |
| `usage` repeats root command | a `usage` line starts with the root command name | start `usage` at the current level (e.g. `add <PATH>`, not `worktree add <PATH>`) |

`../scripts/validate-completion.ps1` additionally reports `cfg_aliasExtension`
(`config.json` `alias` with a `.cmd` / `.exe` / `.bat` suffix) and `i18n_spacing`
(missing space between Chinese and English). Those two do not need manual checking.

**Option vs subcommand**: an item is treated as an option (expecting `,`) when its name
starts with `-`, even if it lives inside a `next` array.

### Options inside `next`

Options normally go in `option` / `global_option`. Some flag-only tools (no subcommands —
e.g. `gpg`, `eslint`) put every flag in `next`; this works, but the module then treats a
flag as a command that switches context, so chaining flags after it can stop completing.
Prefer `option` for flags.

### Leaf value items

Leaf values inside a `next` array follow the same rules as commands: with an alias they
also need a `usage` field (e.g. `all|world|everybody`).

## Pre-completion checklist

### The machine checked these — confirm the gates ran clean

`compare-json.ps1`, `validate-completion.ps1`, and (when hooks exist)
`check-hook-targets.ps1` all report zero. This covers: duplicate `name` in any array;
`next: []` on a command; missing or meaningless or too-simple `usage`; usage ordering and
separators; `usage` repeating the root command; an option with `usage <...>` but no
`next`; every item with an alias having a `usage`; duplicate options; `config.json`
`alias` extensions; Chinese/English spacing; identical structure between languages; and
schema conformance.

### These need judgment — the scripts cannot see them

- [ ] **Subcommand probe run for every command (≤2 levels).** `--help` shows a commands
  section ⟺ the manifest has a non-empty `next`. See `R-02` and
  [`collecting-info.md`](collecting-info.md).
- [ ] **Every command-level alias the CLI lists is recorded**, no length cutoff. See `R-03`.
- [ ] **Every subcommand in `--help` is in `next`**, including sub-subcommands.
- [ ] **Every option of every subcommand is captured**, not just top-level `--help`
  options.
- [ ] **Options with fixed allowed values use `next: [...]`, not `next: []`**; options whose
  value has a recognizable shape (status codes, numbers, times, IDs) provide representative
  examples via `next: [...]`.
- [ ] **`repeat` only on `option` / `global_option` entries, and only when the CLI actually
  allows repetition.**
- [ ] **No option appears in both a subcommand's `option` and `global_option`** unless it is
  genuinely the shared form.
- [ ] **Every `tip` has a real description line**, not just a usage line.
- [ ] **`hooks.lua` compiles** (`luac -p`) and every `psc.on` target resolves.
- [ ] **Portability audit run** — see below.

All items satisfied = task complete.

## Portability audit

The data is cross-platform but was often authored on Windows, and **none of these are
visible to the validation scripts**. Run through this list for every completion you review.

- [ ] **No author-machine paths in text.**
  `grep -rn 'C:\\Users\|/Users/\|%[A-Za-z]\+%' completions/<cmd>/` must return nothing. A
  default value that varies per user machine (e.g. a GnuPG keyring path) must never appear
  as-is.
- [ ] **Paths in `tip` / `usage` / `example` are platform-neutral by default** —
  `~/.gnupg/pubring.kbx`, `/home/<user>/`. **Exception: when a value is genuinely
  platform-specific** (the tool itself documents different defaults per platform, and the
  two forms are not interchangeable), it is correct — and sometimes necessary — to show
  both, as separate `tip` lines: `"Windows: %LOCALAPPDATA%\\..."` / `"Linux:
  ~/.config/..."`. Per-platform pairs are **not** a defect; copying a single machine's path
  is. Prefer the neutral form whenever one exists, and use the pair only when no neutral
  form exists.
- [ ] **No Windows-only commands or options** in the manifest. If the tool genuinely offers
  them and they are documented, keep them and mark the tip `(Windows only)` /
  `(macOS only)`.
- [ ] **Platform-specific invocations are guarded, not avoided** (`R-13`) — a call to
  `powershell.exe` / `cmd.exe` / `wmic`, or a registry lookup, must sit behind
  `psc.platform == "windows"`, so it simply does not run elsewhere. Hooks already do this
  (`nssm`, `volta`, `scoop`); the defect is an **unguarded** call, not the call itself. A
  `.exe` / `.cmd` suffix *check* (e.g. npm bin-shim probing) is a test, not an invocation,
  and needs no guard.
- [ ] **Path-shaped assumptions hold on a case-sensitive filesystem** — completions of file
  names or directories must not assume case-insensitive matching.
- [ ] **`config.json` `alias` has no `.exe` / `.cmd` / `.bat`** — already covered by
  `validate-completion.ps1`; re-check when adding one.
