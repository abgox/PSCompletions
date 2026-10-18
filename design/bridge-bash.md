# Design: Bridge reference — bash

> Bash-specific notes for `module/PSCompletions/PSCompletions.bash`.
> Generic duties live in `bridge.md`; the template language is `templates.md`.
> Check every item off (or its equivalent) before a port is done.

## Status

Shipped in the module package (`module/PSCompletions/PSCompletions.bash`, one `source` line to use).
Requires bash 5.0+ (every mainstream system since ~2020; macOS's 3.2 needs
`brew install bash`), python3, and the module's `bin/<platform>-<arch>`.
Load is loud about missing deps (`bash` version, python fallback `python3`→`python`).
Covered: build mode, native fallback (`complete -F` → `compgen`), `psc` forwarding,
history ordering, hooks gate, `sudo` unwrap, rm confirm, notification tail, template
rendering. Tested headless by `scripts/bridge/test.bash`.

## Static data is a first-class input

The PowerShell bridge renders management UX from the psc manifest's `info` section
(descriptions, confirms, hints). A port must consume those static templates, not just
the manifest tree. Bash renders through the engine (`_psc_tpl` → `psc tpl --version …`):
the template grammar and the `<@Color>` markup both live there, and the bridge only
decides *which* template to render.

## Parity with the PowerShell bridge

Covered (verified by `scripts/bridge/test.bash`): build mode, native fallback
(unknown command **and** path-shaped pending token), `psc` forwarding, history ordering
(`enable_sort_by_history`), hooks gate (`enable_hooks`, psc exempt), manifest language,
`sudo` unwrap + exe-suffix strip, wildcard guard, rm confirm, `psc --reset`, notification
tail, template rendering, and the full menu config (`filter_mode`, `show_mode`, list loop,
apply-when-single/no-match, colors, tip toggles via `raw_config`, filter hint + stale hint,
`switch`/`stay`, `trigger_key`), the word-level apply rules, and management output
termination (every printed line ends with a newline).

**Fresh machine**: with no data dir at all (never imported the PowerShell module), the
first `_psc_init` bootstraps the data dir and seeds the bundled `psc` completion from the
module package before `psc init`, so a first run works offline.

**Terminal ownership**: the menu reads keypresses from the tty, so it must stay in the
shell's foreground process group. Bash's `coproc` happens to leave it there — do not move
the spawn behind anything that gives the child a process group of its own (job control, a
`$( )` wrapper), or the menu will be `SIGTTIN`-stopped on its first read and silently
never appear. (Unlike zsh, bash's `$( )` subshells do **not** get a group of their own, so
`coproc` inside a command substitution still works — verified; do not rely on the reverse.)
See `bridge.md` §4 and the zsh counterpart in `bridge-zsh.md`.

**Native candidate quoting**: `compgen -f` / `COMPREPLY` hand back the **raw** name, so
this bridge quotes on apply (`pick="'$pick'"`) and its `[[ -d ]]` test works on the plain
path. zsh's counterpart is the opposite — `compadd` receives names already escaped
(`az\ zdir`), so it must unescape before testing the filesystem. Both are correct; neither
generalises to the other shell.

**Config support**: which config keys this bridge implements itself, and which belong to
the menu engine, is tabulated in `design/config-support.md`.

**Trigger key**: `trigger_key` is bound once, at load. `psc config menu trigger_key <k>`
therefore takes effect in the **next** shell, and the current session keeps the previous
key working as well — deliberately: `bind -r` does not restore readline's binding for that
key, so unbinding would leave it dead (a `bind -x` command shadows `complete`, it does not
replace it). A fresh shell binds exactly the configured key and leaves Tab at readline's
default.

**Output shape is by design**: a text host prints the CLI's text — a table would still be
text, so there is nothing to re-render (`bridge.md` §7). A structured host (PowerShell,
nushell) consumes `--json` and emits host values instead.

**Remaining gaps** (the reference list for a future port):

| Gap | PS behavior | Bash today |
| --- | --- | --- |
| `show_mode` follow placement | the input-line row is reported, so `auto`/`inline-follow`/`altscreen-follow` place the menu at the input line (no visual jump) | the row is unknown, so those modes collapse to the top; `altscreen-top` / `altscreen-bottom` still work |
| Language fallback | downloads a missing `config.json` before resolving | read-only; falls back to module language |
| `enable_native_completion=0` | runs the host's own completion menu (`MenuComplete`) | returns without completing (readline has no per-key fallback) |
| Native item types | maps `ResultType` (containers → trailing separator, quote rules) | infers a directory from the filesystem (bash has no typed results) |

The `show_mode` row is a **readline limitation**, not a missing wire: the cursor *row* has
no API (PowerShell reads `RawUI.CursorPosition`; bash does not expose one). Querying the
terminal (DSR `\e[6n`) would cost a round-trip *per Tab* — unacceptable over SSH. The
proper fix, if wanted, is engine-side: query once when the menu starts, before entering
the alternate screen, so every shell benefits. Until then `altscreen-bottom` is the
closest stand-in for the follow experience (the prompt usually sits near the bottom).

`_psc_apply` covers the word-level cases PS handles: end-of-line, mid-word
(replacement extends over the rest of the token), after-space, a following word
(no extra space), attached `=` values, engine `nospace`, and `enable_append_space`.
`scripts/bridge/test.bash` asserts each.

## Performance

The per-Tab cost is dominated by process forks to the JSON helper (python). Budget:

- **Cached across Tabs**: alias map, module config, per-completion language, hooks
  gate, `grep -P` capability probe. `_psc_init` clears them all when state changes.
- **Python forks run with `-S`** (skip `site` init): halves startup (~20→10 ms).
- Remaining per-Tab: tokenize (~2 ms), input build (~28 ms, one python), result
  parse (~15 ms, one python). Everything else is bash builtins.
- The engine's own 10-second result cache (see `menu.md`) removes the rebuild for
  repeated opens; the bridge cost is only paid once per open regardless.

Reduce forks further only with care: hand-rolling JSON in bash trades ~20 ms for
quoting bugs — not worth it.

## Porting lessons

- **JSON needs a helper**: shells without native JSON (bash) must shell out for every
  build/parse — pin one (python3 over jq: more universal) and route *all* JSON through
  it, never hand-roll quoting.
- **One builder, two callers**: the input assembler is used by the live bridge and the
  headless tests. Extract it once; testing a copy tests nothing.
- **Headless test harness**: the engine rewrites the input file with built items even
  when the TUI dies — launch, kill, assert the file. Fixture = symlinked repo
  completions + minimal settings/index + a scratch git repo for live hook output.
- **The management completion is a special citizen**: `psc` hooks need `data`
  (settings/index/completions paths + live config), per-completion `config`, and global
  config — an empty build context yields an empty `add` menu. Pass the full context for
  every command, not just `psc`.
- **Mirror the gates host-side**: `enable_hooks` (psc exempt), manifest language
  (per-completion → module → declared-first), `sudo` unwrap. The engine trusts what the
  bridge sends.
- **Order is opt-in**: empty order paths silently disable ranking *and* the background
  recompute. Pass real paths plus top-level `order` (history/cmd/aliases/path); ranking
  takes effect from the second open (the first open writes the files).
- **Result shapes differ by mode**: build mode returns text, items mode returns an index
  the host maps. Thread `nospace` through to apply in both.
- **`=` values arrive prefixed**: the engine re-attaches the head into `completion_text`;
  the host replaces the whole word and adds no space.
- **Drive native handlers faithfully**: registered completions (`complete -F`) need the
  full readline illusion (`COMP_WORDS` with the trailing empty word, `CWORD`, `LINE`,
  `POINT`); only fall back to dumb enumeration when unregistered. Expand `~` for lookup,
  map it back for replacement.
- **Destructive commands confirm host-side**: the CLI never prompts — `rm --all` needs
  its own confirm in every bridge.
- **Reimplement the notification tail**: one-shot consumption of `added`/`removed`,
  persistent `update`/`renamed`/`module`; render via the shared templates
  (`_psc_tpl update_info` / `module.update`), never ad-hoc text.
- **`add`/`rm`/`update` results render from `--json`**: run the command once in JSON
  mode and format from templates — never double-run (a second `rm` would fail) and
  never print the raw binary text.
- **Never swallow `min_area`**: append a line comment hint instead of silent cancel.
- **Shell gotchas (bash)**: command substitution strips NUL (use `\x1f` or files);
  `bind -x` only in interactive shells (guard it); no nested quoting inside `$(( ))`;
  every embedded script needs its imports linted; `grep -oP` is absent on macOS (keep a
  fallback); **never `${2:-{}}`** — bash ends
  `:-` defaults at the first `}`, silently appending a literal `}` to every value
  (test `$#` instead). Target bash 5.0+ (the modern floor; macOS's 3.2 needs a newer
  bash installed).

## Where the source line goes

Put `source "${module}PSCompletions.bash"` **last** in `~/.bashrc` (or at least after anything
that switches key modes). `set -o vi` / `bind -v` swap keymaps, and a binding made before that
switch stops firing — the menu then survives only inside the session that never switched. Our
binding itself lives on the default keymap, so sourcing last is enough.
