# Design: Bridge reference — zsh

> zsh-specific notes for `module/PSCompletions/PSCompletions.zsh`.
> Generic duties live in `bridge.md`; the template language is `templates.md`.
> Check every item off (or its equivalent) before a port is done.

## Status

Shipped in the module package (`module/PSCompletions/PSCompletions.zsh`, one `source` line in `~/.zshrc`).
Requires zsh 5.0+ and python3 (3.8+); the binaries come from the module package.
Load is loud about missing dependencies.
Covered: build mode, native capture (compadd interception → items menu) with the enumeration and hand-off fallbacks, `psc` forwarding, history ordering, hooks gate, `sudo` unwrap + exe-suffix strip, wildcard guard, rm/`--reset` confirm, notification tail, template rendering, the full menu config, and the word-level apply rules.
Tested headless by `scripts/bridge/test.zsh` (including the compadd parser and the enumeration fallback); the terminal-ownership property needs a real pty and is covered by `scripts/bridge/test-pgrp.py`.

## zsh mapping (vs bash)

| Concern | bash | zsh |
| --- | --- | --- |
| Trigger | `bind -x` (`bind -x '"\t": _psc_complete'`) | `zle -N _psc_complete` + `bindkey '^I' _psc_complete` |
| Line / cursor | `$READLINE_LINE` / `$READLINE_POINT` | `$LBUFFER` / `$RBUFFER` |
| Tokenize | `grep -oP` (fallback python) | native `[[ =~ ]]` loop (no fork) |
| Lowercase | `${v,,}` | `${(L)v}` |
| Assoc arrays | `declare -A` | `typeset -A` |
| Split fields | `mapfile` | `${reply[@]}` built by the regex loop |
| Stderr line + timeout | `coproc` + `read -t 1 -u` | `coproc` + `read -t 1 -p` |
| Menu process group | `coproc` keeps the shell's | needs `setopt localoptions no_monitor`, and the spawn must not run behind `<( )`/`$( )` |
| Temp-file id | `$EPOCHREALTIME` (bash 5) | `zmodload zsh/datetime` then `$EPOCHREALTIME` |
| One-key confirm | `read -n1 -s` | `read -s -k 1` |

## Config support

Which config keys this bridge implements itself, and which belong to the menu engine, is tabulated in `design/config-support.md`.

## Native path: capture first, hand-off as the fallback

Both branches of `bridge.md` §2 exist here:

- **Capture** (default): compsys has no "give me the candidates" API, so the bridge runs the real completion with `compadd` intercepted (`_psc_capture` → `_psc_compadd_parse`) and renders the result in our menu through the items path (`_psc_items_menu`, ported from the bash bridge). Descriptions (`-d`, which `_describe` and `_arguments` build on) become item **tips** — the menu shows them in its description box exactly like manifest tips.
- **Enumerate** (no compsys): a bare zsh without `compinit` has no completion to capture, so the bridge enumerates the candidates itself — command names in command position, otherwise path entries — exactly like the bash bridge's `compgen` fallback (`_psc_enumerate`). The completion text rebuilds what was typed (`al` → `alpha`, `~/` stays `~/`), so the result is what the user expects rather than a glob-shaped path.
- **Hand-off** (last resort): nothing captured and nothing to enumerate, so `zle expand-or-complete` runs and zsh draws its own menu.

The parser models the `compadd` options of `zshcompwid(1)` that decide *what the candidates are*: `-a`/`-k` (the trailing arguments are array / associative-array **names**, resolved by dynamic scope), clustered short options (`-ld descs` = `-l -d descs`), `-P`/`-S` (inserted **and** displayed), `-p`/`-s` (inserted only), `-d` (per-candidate descriptions → tips), and `-O`/`-A`/`-D` (matches stored elsewhere, so that call contributes no candidates).
Anything not modelled (`-W`, `-M`, `-F`, groups, explanations, `-U`/`-q`/…) is ignored rather than guessed.

Capture is compsys-internal, so it stays shallow by design:

| What | Behaviour |
| --- | --- |
| Paths | candidates arrive as compsys generated them (often full paths); the in-line part (`IPREFIX`) is stripped for display, and applying replaces the whole word (plus a `/` for directories) |
| No compsys | enumerated by the bridge instead (see above): dirs get `/`, files do not |
| Re-expansion | none: no `**`/glob expansion, no `_expand` of `$var` / `=cmd` |
| zsh's own menu | not reproduced: no grouping/coloring by tag (`-J`/`-V` are skipped), and zsh's *command-line* cycling (repeated Tab replacing the word via `AUTO_MENU` / `menu-complete`) is replaced by our menu — inside it, `Tab`/`Shift+Tab` (or `↓`/`↑`) step the selection and `enable_list_loop` wraps, `Enter`/`Space` commits |
| History ranking | applied: candidates are deduped by completion text and ranked through `psc-menu --sort`, the same input the bash bridge builds |
| `enable_native_completion=0` | turns all three branches off (the widget returns without completing) — the same shape as bash |

## Parity with the PowerShell bridge

| Difference | PS behavior | zsh today |
| --- | --- | --- |
| Native candidates in our menu | `TabExpansion2` items rendered in our menu | captured via `compadd` interception, see above |
| Native candidate types | `ResultType` maps containers/quoting | inferred from the filesystem (`/` suffix on directories) |
| `show_mode` follow placement | input-line row reported | row unknown → `auto`/follow render at top; `altscreen-top`/`bottom` work |
| Language fallback | downloads a missing `config.json` | read-only; falls back to module language |
| `trigger_key` applies | live (PSReadLine re-binds) | next shell; the current session keeps the previous key working, see below |

## Porting lessons (zsh)

- **A widget runs inside the line editor.** `zle -I` before spawning the TUI (so it owns the terminal) and `zle reset-prompt` after; otherwise zsh repaints over the menu.
- **A background process group cannot read the tty.** A `read` on `/dev/tty` from a process group that is not the foreground one is stopped by `SIGTTIN` — no error, no output, the menu just never appears while the shell stays responsive. `setopt localoptions no_monitor` before the `coproc` keeps it in the shell's group; the call must also stay in the shell, because a `<( )` / `$( )` subshell is given a group of its own (which is why the spawn result cannot be *printed* either — it sets `_PSC_SPAWN_{STATUS,WORDS,NOSPACE}`).
- **`status` is read-only** — `local status` fails with `read-only variable: status`. Name the variable something else (`st`).
- **A valueless `local` prints when it runs again.** `local x` re-executed (anything declared inside a loop) makes zsh write `x=<current value>` to the terminal — no xtrace involved, and it lands *above* the menu. Give every local a value. This one cost an afternoon: the parser's three in-loop locals printed on every iteration, which looked exactly like xtrace with an empty `PS4`.
- **`compadd` names parameters, so locals must not shadow them.** `-a`/`-k`/`-d` take a parameter *name* that is resolved by dynamic scope; a local of the same name in the parser silently wins (`_psc_descs` shadowed a caller array called `descs`). Hence the `_psc_` prefix on every local there.
- **`local` prints when it runs again, and `:h`/`:t` do not split a trailing slash.**
`local x` re-executed (anything declared inside a loop) makes zsh write `x=<value>` to the terminal — no xtrace involved, and it lands *above* the menu; give every local a value.
Separately, `${/home/u/:t}` is `u`, not empty, so a path prefix must be split explicitly (`[[ $p == */ ]]` first) when globbing a directory.
- **Some keys are prefix keys in the host's completion system.** After `compinit`, `^X` is the completion-system prefix, so binding a widget to plain `^X` never fires (the same trap for any `trigger_key` that collides with a prefix sequence). Bind a key that is not a prefix, or expect it to be swallowed.
- **A trigger key can be taken, but not given back.** `bindkey -r` removes our binding without restoring zle's default — afterwards `bindkey '^I'` prints nothing and Tab is dead until the shell restarts — and the key we took may have had a meaning of its own (`^@` is `set-mark-command`). So the configured key is bound at load only: a runtime `psc config menu trigger_key <k>` applies to the next shell, and the current session keeps the old key working. A fresh shell binds exactly the configured key and leaves Tab at `expand-or-complete`.
- **An unterminated line is visible.** zsh prints `PROMPT_EOL_MARK` (`%`) and pads to the line end whenever the last write did not end in a newline, so any rendered fragment printed without `print` / `echo` shows up here first (bash has no equivalent marker). Assert it, do not eyeball it.
- **`read -k 1` needs a terminal.** Outside a TTY it fails and leaves the variable empty; treat empty *or* a newline as "Enter".
- **`print "--- x ---"` fails** — `print` reads a leading `-` as options; use `print --`.
- **`~` in `case` patterns is tilde-expanded** — write `\~/*` when matching a leading `~`.
- **`$EPOCHREALTIME` needs `zmodload zsh/datetime`.**
- **`psc init --flat` is read, not parsed.** `_psc_read_flat` reads NUL-delimited `A`/`C` records with `read -d $'\0'`; the first Tab starts no Python for init.
- **Wrap in a function to build an array.** `reply=(...)` inside a helper is the idiom; `${reply[@]}` then reads it out (no `mapfile`).

## Where the source line goes

Put `source "${module}PSCompletions.zsh"` **last** in `~/.zshrc` (or at least after anything that switches keymaps).
`bindkey -v` resets all keymaps, and a binding made before it stops firing.
Sourcing last is enough — no keymap-specific duplication is needed.
