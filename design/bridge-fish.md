# Design: Bridge reference — fish

> fish-specific notes for `module/PSCompletions/PSCompletions.fish`.
> Generic duties live in `bridge.md`; the template language is `templates.md`.
> Check every item off (or its equivalent) before a port is done.

## Status

Shipped in the module package (`module/PSCompletions/PSCompletions.fish`), loaded by one `source` line or — preferred, because conf.d is read before `config.fish` and a later key mode switch can then still be wrapped — a symlink into `~/.config/fish/conf.d/`.
Because that install makes the *sourced* path a link, the bridge resolves its own path (`path resolve`) before looking for the binaries and the bundled `psc` completion next to it: `status --current-filename` returns the link, not the module.
Requires fish 4.0+ and python3 (3.8+); the binaries come from the module package.
Load is loud about missing dependencies.
Covered: build mode, the native ask (`complete -C` → items menu) with the host hand-off when native completion is off, `psc` forwarding, history ordering (over a normalised copy of fish's own history file), hooks gate, `sudo` unwrap + exe-suffix strip, wildcard guard, `rm --all` / `--reset` confirm, notification tail, template rendering, the full menu config, the word-level apply rules, and candidate escaping.
Tested headless by `scripts/bridge/test.fish` (routing, apply, escaping differential, history normalisation, key mapping, config forwarding, management text); the terminal-ownership property needs a real pty and is covered by `scripts/bridge/test-pgrp.py`.

## fish mapping (vs bash / zsh)

| Concern | bash / zsh | fish |
| --- | --- | --- |
| Trigger | `bind -x` / `zle -N` + `bindkey` | `bind [-M mode] <key-name> _psc_complete` (`default` and `insert`) |
| Line / cursor | `$READLINE_LINE`+`$READLINE_POINT` / `$LBUFFER`+`$RBUFFER` | `commandline -b` / `commandline -C`; set with `-r` / `-C` / `-f repaint` |
| Tokenize | `grep -oP` / zsh regex loop | `string match -r -a` (same grammar) |
| Assoc arrays | `declare -A` / `typeset -A` | two parallel lists + `contains -i` (`_psc_map_get`) |
| Lowercase | `${v,,}` / `${(L)v}` | `string lower` |
| Word splitting | splits on spaces (needs quoting) | splits on **newlines only** — values with spaces survive |
| Stderr line + timeout | `coproc` + `read -t` | no `read -t`: one python watchdog (`_psc_spawn`) relays the heartbeat and kills after 30 s |
| Menu process group | coproc keeps the shell's / needs `no_monitor` + no subshell | command substitution keeps the shell's group — the spawn may sit in one |
| Temp-file id | `$EPOCHREALTIME` | `random` + `$fish_pid` |
| One-key confirm | `read -n1 -s` | `read -n 1 -s -p '> '` |
| Coloring a status line | raw `\033[32m…` | `set_color green` / `normal` (emits codes even when piped) |
| JSON payloads | heredoc `python3 -` | inline `python3 -c '…'` — no heredoc in fish |
| History file | plain lines / `: ts:0;cmd` | YAML-ish `- cmd: …` + `when:` — normalised before `--sort` (`_psc_hist`) |

## Config support

Which config keys this bridge implements itself, and which belong to the menu engine, is tabulated in `design/config-support.md`.

## Native path: the host answers

`complete -C '<line up to cursor>'` is an **ask**, not an interception: fish's completion engine answers with `candidate<TAB>description` per line and always answers something (an unknown command falls back to path completion), so no capture and no enumeration fallback are needed.
Candidates are **raw** names — nothing is pre-escaped, like bash's `compgen` and unlike zsh's `compadd` — so the picked one goes through `_psc_escape` before insertion.
Descriptions become item **tips**, so the menu shows them like manifest tips.

With `enable_native_completion=0` fish **hands the trigger back** to its own completion (`commandline -f complete`): fish has the per-key fallback bash and zsh lack, so this branch matches the PS bridge's `MenuComplete` instead of completing nothing.

## Parity with the PowerShell bridge

| Difference | PS behavior | fish today |
| --- | --- | --- |
| Native candidate types | `ResultType` maps containers/quoting | a container is recognised from the candidate text (`complete -C` appends `/`); no filesystem probe |
| Container separator | appended when `enable_path_trailing_separator=1` | fish's candidate already carries the `/`, so the key decides whether it **stays** (off → stripped); a container never takes a trailing space either way |
| `enable_native_completion=0` | runs the host menu (`MenuComplete`) | same: hands off to fish's own completion |
| `show_mode` follow placement | input-line row reported | row unknown → `auto`/follow render at top; `altscreen-top`/`bottom` work |
| Language fallback | downloads a missing `config.json` | read-only; falls back to module language |
| `trigger_key` applies | live (PSReadLine re-binds) | next shell; the current session keeps the previous key working |

## Porting lessons (fish)

- **No heredoc.** Every python payload is an inline single-quoted `-c` string. Inside fish single quotes only `\'` and `\\` are escapes, so a payload's `'` is written `\'` (and a literal `\\` would be `\\\\` — no payload needs one). A `\"` inside a python f-string expression is the one shape to avoid (python rejects it).
- **`--argument-names` gives the rest to the *last* name.** A list parameter must be last (`_psc_map_get <keys-name> <key> <values…>`); in the middle it silently collapses to one element, which looked like "the alias map is empty".
- **A file-level `set -l` is invisible inside functions** — shared setup in a test or script must be `set -g` (`$ROOT`, `$BIN`), or the function sees an empty value.
- **Glob character classes do not match** in `switch` / `string match -q` (`Ctrl+[A-Za-z]` never matched `Ctrl+E`); only `string match -r` does. Use explicit `test` comparisons or a regex.
- **`'…\'` is an escaped quote**, not a backslash: a single-quoted literal ending in a backslash leaves the string open and swallows the rest of the file. Use double quotes (`".\\"`) for those.
- **Quote every `math` expression** (`math "2 + 2 * $n"`): an unquoted `*` globs against the working directory and the expression becomes garbage.
- **`commandline` is interactive-only.** Anything it touches is split into a pure function plus a thin editor wrapper (`_psc_apply_text`, `_psc_route`, `_psc_key_for`), so the headless suite can assert the rules and only the wiring needs a pty.
- **`status` is read-only** — `set -l status $res[1]` fails ("Tried to modify the special variable 'status' with the wrong scope") and leaves `$status` reporting the last command's exit code, so the pick was silently dropped and the trigger fell through to fish's own completion. Use another name (`st`); see `bridge.md` §10.
- **Escape candidates the way fish itself does.** `string escape` quotes a leading `~`, which disables tilde expansion, while fish's own completion inserts `a\ b/` with backslashes and leaves `~` bare. `_psc_escape` reproduces that (differentially verified for `space ' " $ * ( ) [ ] { } < > & | ; # \ ~ ^ %`; `! = : @ + ,` stay bare).
- **`set_color` emits escape codes even when stdout is a pipe**, so a captured status line can be asserted; put the reset before the newline (`printf` the text, then `set_color normal`, then a newline) so the next prompt is not left colored.
- **fish 4 queries the terminal at startup** (`ESC[?u`, `ESC]11;?`, XTGETTCAP `ESC P+q…`) and blocks before drawing its first prompt until they are answered. A pty test that only needs the shell (a stub menu) drives it with `TERM=dumb`; a test that runs the real TUI must answer the queries.
- **`bind` validates key names itself** (`bind: unknown modifier`) — `bind --key-names` lists only unmodified keys, so it cannot check `shift-tab` or `ctrl-space`.
- **fish's history file is not plain command lines** (`- cmd: …`), and the engine's ordering reads one command per line, so `_psc_hist` hands it a normalised copy, rebuilt only when the source file is newer.
- **`psc init --flat` is read, not parsed.** `_psc_read_flat` uses `read -z` on NUL-delimited `A`/`C` records; the first Tab starts no Python for init.

## Where the source line goes (and why fish is order-tolerant)

fish is the odd one out: `bind` writes a **user layer**, which survives `fish_vi_key_bindings`, `fish_default_key_bindings` and friends.
A conf.d symlink (or a `source` in `config.fish`) therefore works in any order, which is why the fish bridge needs no "source last" rule — `bind --preset` and the user binding coexist, and the user binding wins.
