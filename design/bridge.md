# Design: Shell bridge layer (host responsibilities)

> What the shell side owns vs the Rust binaries, and what a new shell must provide to host this system.
> The PowerShell implementation (`module/PSCompletions/`) is the reference; the concepts below are shell-agnostic.
> Companion docs: `protocol.md` (engine contract), `psc-cli.md` (management CLI), `menu.md` (rendering).

The binaries never touch the interactive session: they compute (`psc`) and draw (`psc-menu`) but cannot read the input line, bind keys, or restore the screen.
The **bridge** (one per shell) owns everything session-side, in eight duties.
A port must cover all eight; the checklist in §9 says what the shell must expose for each.

Layout: each shell's bridge is **one self-contained file at the module root**, `PSCompletions.<ext>` (`PSCompletions.bash`, `PSCompletions.zsh`, …; the PowerShell bridge is the module itself), carrying the interpreter shebang like every other script in the repo.
Inline the template renderer and any helpers — no subdirectory, no shared file.
Add a per-shell directory only if that invariant actually breaks.

## 1. Lifecycle

- Resolve the data dir once (override env → platform default); seed it if empty. The platform default must **match the module's**: `%APPDATA%\com.abgox\PSCompletions` (Windows), `~/Library/Application Support/com.abgox/PSCompletions` (macOS), `${XDG_DATA_HOME:-~/.local/share}/com.abgox/PSCompletions` (else) — so the shell bridge and the PowerShell module share one data dir. Legacy migration applies only to a host that had a prior data layout (PowerShell); a first-time shell just resolves/creates the dir and reads whatever is there. Discover both binaries by platform-arch, and register the trigger key.
- **Trigger ownership is unified**: the bridge rebinds the shell's completion key to its own entry (`Set-PSReadLineKeyHandler Tab → menu.script`) and owns every trigger press — installed and native completions alike go through one dispatch (§2). Changing `trigger_key` rebinds live (persist only after the bind succeeds). Ports on shells that cannot replace the native trigger cannot do this: the fallback is owning a *different* key and leaving the native key alone — two menus coexist, and the unified dispatch is lost. Say so in the port notes.
- **Lazy init**: nothing expensive happens at import. The first trigger runs `psc init` (single source of truth: settings, aliasMap, urls, info templates, defaults) and caches it in memory; every management command refreshes it afterwards (`init_data`).

## 2. Trigger + dispatch

- On the trigger key: snapshot buffer + cursor, keep only the **command being edited** (see the separator rule below), tokenize with the shared grammar (`(?:"[^"]*"|'[^']*'|\S)+` — must match `order::tokenize`), strip executable suffixes, resolve the first word through the trigger map (with `sudo` unwrap), and decide: **build mode** only when the first word is installed **and** the pending token is not path-shaped; otherwise the **native path** below. Both conditions matter — routing every installed-command line to build mode silently drops path completion (a path-shaped word must reach the host's own completer even for an installed command).
- **A separator ends a command; a brace does not.** Only the text after the last unquoted separator (`|`, `;`, `&`, `&&`, `||`) before the cursor is the command being edited, so *its* first word is the one to resolve (`git status | grep <Tab>` completes `grep`, not `git`). With no separator the whole prefix is one command; an empty segment (the line ends on a separator) has no command to resolve and takes the native path, which is what completes a command name there. Quotes and `\` hide a separator, `>&` / `&>` are redirections rather than separators, and a `{ … }` is never one. See [`D42`](../decisions/bridge.md#d42).
- **Native path, three branches** (not one): when the first word is unknown to the
  library (uninstalled / path / root-prefix words) **or the pending token is path-shaped**
(`^["']?(?:[A-Za-z]:[/\\]|(?:\.\.?|~)?[/\\])`, where native matching wins), the bridge obtains candidates from the host and renders them **in our menu** (history-ranked through `--sort`) — the native system is a data source, never a UI.
Host items may carry `tip`/`usage`/`example`, and a port should fill them from whatever the host exposes (PS takes TabExpansion2's tooltips; zsh takes `compadd -d` descriptions).
In order:
  1. **ask** the host's completion API (PS: `TabExpansion2`; bash: drive the registered `complete -F` handler, `COMPREPLY` out);
  2. **capture** where no API exists (zsh intercepts `compadd` — `bridge-zsh.md`);
  3. **enumerate** ourselves when the host has no completion system at all (a bare zsh without `compinit`) or nothing for this context: command names in command position, otherwise path entries (bash: `compgen -c` / `compgen -f`). The text must be **rebuilt from what the user typed** (`al` → `alpha`, not the glob's `./alpha`), or the result is a path the user never asked for. Only with native integration off does the bridge step aside and invoke the host menu (`MenuComplete`); a port without any host-completion capability needs just that "re-emit the original key" fallback.
- **Host candidates may be escaped or quoted for insertion.** zsh's `compadd` receives `az\ zdir` / `'a b'`; bash's `compgen` returns the raw name and relies on the caller to quote. Unescape before anything that touches the filesystem (a `-d` test on the escaped spelling silently fails, so a directory loses its separator) and for the menu's display, and re-quote only where the host did not (bash's native apply).
- The completion **context** changes only on apply; the bridge replaces exactly the word under the cursor (space/quote-aware boundaries), never the whole line.

## 3. Context assembly
- Per trigger, assemble the engine input: build context (manifest path in the per-completion language, hooks gate, cwd, per-completion + global config, order paths, cache/log dirs) or mapped native items; plus menu config, terminal geometry **with the visible window** (scrollback size alone breaks layout math), order state, data/order/menu dirs, and any pending `initial_filter`.
- The manifest language resolution (per-completion → module → declared-first) and the `enable_hooks` gate live here, not in the engine. The module language is read from `settings.json` (`config.language`) — **never** from a per-session cache: `psc` (management) may run before the first Tab has populated one, and it must not print in the wrong language just because the menu has not been triggered yet.

## 4. Process driving

- Spawn one menu process per trigger with console inheritance (it reads keypresses directly); results travel via `--result` files (GUID-named, retried deletes), never stdout. `--sort` is a separate short-lived call with its own timeout.
- **The menu must own the terminal.** It reads keypresses from the tty, and a read from a background process group is stopped by `SIGTTIN`: the menu starts, stops, and the trigger looks like it did nothing while the shell stays usable. Spawn it so it stays in the shell's own (foreground) process group — bash's `coproc` does this; zsh needs `MONITOR` off **and** the spawn kept out of a `<( )` / `$( )` subshell, which gets a process group of its own. Details per shell: `bridge-bash.md`, `bridge-zsh.md`. Consequence for the result channel: since the spawn must not sit behind a subshell, the decoded result cannot come back through stdout (`$( )`) — hand it to the caller through host variables instead (zsh: `_PSC_SPAWN_*`).
- **Watchdog**: the engine heartbeats on stderr every 15 s; 30 s of silence kills the process, emits the alternate-screen leave sequence (harmless if never entered), and reports `menu unavailable` below the input line — never on it.
- **Process groups and bindings are only observable in a real terminal.** A headless suite can assert candidate sets, the input JSON, the parser and the apply rules, but not "which process group the menu landed in" or "which key is bound" — both fail silently and look like "the trigger did nothing". Assert them with a pty test (`scripts/bridge/test-pgrp.py`: the menu's pgid must equal the shell's).

## 5. Screen stewardship

- Save only the covered region before spawning (never the input line — buffer save/restore corrupts true-color prompts); restore exactly `covered_*` on exit, the whole region on abnormal death, and nothing on a no-render cancel (a rewrite would repaint the shell's own predictions). Alternate-screen exits skip restore; cursor position is always re-seated by the bridge. Gate out below 5 rows (`min_area`).

## 6. Result application

- Apply the engine's verdict: `selected` → suffix rules (append space unless `=`-attached, `nospace`, or a following word continues; native container types get separators; quote-aware trimming) then word replace; `input` → insert filter text; `cancel` / `min_area` → line untouched plus hint.

## 7. Management forwarding

- Forward `psc` subcommands to the binary with UTF-8 output decoding, **exit-code-first**
error handling (non-zero renders red text and stops), `--json` parsing with fallback, per-command result rendering, post-command `init_data` refresh, interactive confirms (`rm --all`, `--reset`), and host side-effects that the CLI cannot do itself (trigger-key rebind, psc seed restore).
A confirmed destructive operation is then **authorised**: the host adds `--yes` to the invocation, because the engine never prompts ([`json.md`](json.md) §7).
- **Output shape is the CLI's, in every host.** A read prints the CLI's text as it stands — a query plain, a status message green or red — and nothing re-renders it: that text *is* the human view ([`psc-cli.md`](psc-cli.md) §Text output shape), so a port carries no format of its own and N shells show one presentation. `--json` is the machine contract for anything a caller wants to slice (`jq`, `ConvertFrom-Json`); a host does not build objects out of it for display, because the raw data is already the better surface for that.
- Rendered template text is a **fragment**: it carries no trailing newline, so the **caller** terminates each line it prints. A missed terminator is invisible in bash but loud in zsh, which marks an unterminated line with `PROMPT_EOL_MARK` (`%`) and pads it; both bridges assert the property (`rendered-line-terminated`, see §8's `notification-line-terminated`).
- The CLI's own messages are **plain text** (`core/cli/src/messages.rs`), so coloring them is the bridge's job — the convention comes from the PS bridge's `_forward_psc`: forwarded output is **green on success, red on failure**. Asserted by `status green on success` / `status red on failure` in both suites. The `info` templates are not this: the engine renders them ([`templates.md`](templates.md)).
- **`--json` anywhere in the invocation means the machine contract.** The bridge hands the whole invocation to the engine uncolored and renders nothing itself, so a caller always gets parseable JSON — `psc config core language --json` and `psc rm <name> --json` included. The check sits **before** the confirms, so a machine caller is never prompted: it gets the engine's `needs_confirmation` refusal instead ([`json.md`](json.md) §7). Asserted by `json-is-never-colored` in all three suites.

## 8. Notifications

- After every management command, render pending state from `change.json`: module updates persist until acted on — and only a remote version newer than the installed one counts as an update, so an equal value stays silent; library `added`/`removed` are one-shot (consumed on display), `update`/`renamed` persist. A command that already rendered them sets the skip flag for the tail; `--self-update` sets the module skip the same way, since it just reported the module state itself.

## 9. Port checklist (what the shell must expose)

**The gate first: a shell is only ported when the bridge can own the trigger key *and* write the result back.** Concretely the host must allow both of:

1. **Own the trigger.** Pressing the configured trigger key must run *our* code. Either the host lets a binding be replaced (bash/zsh/fish) or it exposes a hook the host itself runs on that key (nu's external completer runs when Tab is pressed). A host whose built-in binding cannot be taken over — and which offers no such hook — gets **no bridge**: a menu that can never open is worse than none.
2. **Write the line back.** Our code must be able to read the input line (or its tokens) and replace text in it — our TUI decides, the host inserts. A host that can only *display* completions would force its own menu, which is the thing the port exists to avoid.

**The procedure for a new port — the order to work in, the automated floor, and the by-hand pass the operator must run — is `design/bridge-porting.md`.** Everything else is negotiable (`bridge-fish.md` drops the enumeration branch, bash and zsh differ in their native paths); this one is not.
Both halves hold for every shipped bridge — bash/zsh/fish rebind the key.
nushell was prototyped in full and **rejected** on the first half: its built-in `Tab` cannot be replaced, and the only configuration that runs an external completer is one where `config.nu` errors.
The evidence and the alternatives are in [`decisions/bridge.md#d40`](../decisions/bridge.md#d40).

| Duty | Required capability |
| --- | --- |
| 1 | env vars, platform-distro detection, file IO (UTF-8, atomic write), keybinding API (**replaceable** trigger binding, or a host-run hook on that key), bundled-file lookup |
| 2 | keypress interception, line buffer + cursor read, regex tokenize, alias table lookup, native completion API **or** a way to capture the host's candidates, a candidate enumeration of its own for hosts without a completion system, wildcard test |
| 3 | JSON build/parse, per-command config store, history-file path, cwd |
| 4 | process spawn with inherited TTY **in the shell's own process group**, stderr line watch, kill, GUID/unique names |
| 5 | terminal geometry (cursor, buffer, **visible window**), region save/restore **or** always-alternate-screen, cursor repositioning, output-encoding switch |
| 6 | word-boundary replace, suffix/quote rules (**container → separator, never a space**; attached `=`; `nospace`; a following word), unescaping host candidates before filesystem/display use, typed-result mapping (for native items) |
| 7 | exit-code capture, colored output, single-key confirm prompt plus the `--yes` that authorises what it confirmed, and `--json` parsing for the action results the templates render |
| 8 | persistent JSON state file read/write |

A shell missing region save/restore can still port by always using the alternate screen (the engine already does on Unix); a shell without a native completion API simply skips the fallback path.
Everything else is mandatory.

### Hard requirements found while porting

Four of these were found the hard way — a by-hand pass, not a suite — so they belong to the checklist a future port reads *before* writing code:

1. **Carry payloads in a file, never in argv or the environment.** A host completion can return thousands of entries; one argument or environment variable is capped at 128 KB, and the zsh port hit that with a plain `pyt` + Tab (`argument list too long`).
2. **Own the terminal after an abnormal menu exit** (watchdog kill, crash). The engine turns on mouse capture / alternate screen / hidden cursor through crossterm and a clean exit turns them off; a killed one cannot. Restore the whole set *and* drop the input already queued on the tty — see §13.
3. **Know where the host's key binding layer sits.** fish's `bind` writes a user layer that survives `fish_vi_key_bindings`; bash's `set -o vi` and zsh's `bindkey -v` switch keymaps and drop a binding made earlier, so those two rc files must source the bridge **last** (or at least after any key-mode setup). See `bridge-bash.md` / `bridge-zsh.md`.
4. **Beware transport hazards for `-`-leading words.** fish's `echo` swallows a lone `--` as its own end-of-options marker, so `psc --<Tab>` reached the engine with an empty pending token and opened an unfiltered menu. Emit arguments with `printf` (or an equivalent that does not parse its operands), never with bare `echo`.

## 10. Porting lessons

Each port keeps its own `bridge-<shell>.md` (start with `bridge-bash.md` — the worked example — and `bridge-zsh.md`).
The short version: route all JSON through one helper, share one input builder between bridge and tests, pass the full build context (especially for `psc`), mirror the gates host-side, wire order paths explicitly, and reimplement confirms + notifications + `min_area` host-side (the CLI does none of them).

The cross-cutting lessons, in one place:

- **Account for every config key, per shell.** Keys split in two: **engine-side** (the bridge only forwards them — because `raw_config` carries every scalar, a *new* scalar needs no bridge change) and **host-side** (the bridge implements the behaviour itself: `trigger_key`, `enable_native_completion`, `enable_append_space`, `enable_path_trailing_separator`, `enable_sort_by_history`, `enable_hooks`, `language`). `design/config-support.md` is the table; it is the thing that stops "is this supported?" from being guesswork. A host-side row without a test is indistinguishable from "not supported", so every port adds its cases — and records the rows it deliberately does not honour, with the reason.
- **The static data is a spec, not strings.** The psc manifest's `info` section is the user-facing surface (help page, confirms, hints, result blocks); a port that only forwards raw binary text silently loses all of it. Read `templates.md` and implement the renderer before wiring any command that prints text.
- **One text engine, three renderers.** All user-facing text flows through `templates.md`; a private substitutor per bridge is how drift starts. The reference renderer + parity check catches it.
- **Result rendering mirrors `add`.** `update`/`rm` render the same per-item blocks; errors render red, ownership warnings yellow, success green — driven by the templates, not hardcoded per command.
- **`psc`'s own completion is a special citizen.** Its hooks need `data` (settings/index/completions paths + live config); an empty build context yields an empty `add` menu.
- **Gates live host-side.** `enable_hooks`, manifest language, `sudo` unwrap, the `rm --all` confirmation prompt, watchdog, notification tail, `min_area` — the CLI does none of them. (The *authorisation* behind that prompt is the engine's: it refuses a destructive operation without `--yes`, which the host supplies once the human has confirmed — [`json.md`](json.md) §7.) Also wire the **menu config** (filter/show mode, tip toggles, hint text, switch/stay symbols, sort-by-history) — they are host-supplied and silently default if omitted.
- **Word replacement covers the whole token.** Applying with the cursor mid-word must replace from word start through the rest of the token (not only up to the cursor), and the trailing-space rule keys on the *original* after-cursor text.
- **`Rest` survives the loop.** A capped `each` leaves its skipped count readable *after* `{{/each}}`; renderers set it every iteration and never clear it.
- **Exe-suffix and trigger-key are host concerns.** Strip `.exe`/`.cmd`/`.bat` from the command word; map the configured trigger key to the host's own key syntax (PowerShell key names differ from readline sequences; keys the host cannot express fall back with a warning).
- **Dispatch has two conditions, not one.** Build mode needs *both* an installed command *and* a non-path-shaped pending token; a path-shaped word goes to the host completer even for an installed command. Copying only "installed → build" silently loses path completion.
- **`show_mode`'s follow placement needs the input-line row.** A host that cannot report the cursor row (readline) can only offer top/bottom pinning; don't fake the row — degrade and document.
- **Seed the management completion on a fresh machine.** A shell that was never installed alongside PowerShell starts with no data dir: bootstrap it *and* copy the bundled `psc` completion from the module package before the first `psc init`, so a first run works offline (the CLI's self-heal is network-only).
- **The output file is the test surface.** The engine rewrites `input.json` with the built items even when the TUI is killed, so a headless harness can assert every subcommand's candidates without a terminal.
- **A failed trigger hides behind the host's own completion.** When the trigger function errors and returns non-zero, the shell falls through to the completion it would have run anyway, so the line still completes and the defect looks like success — the more so when the native rules were modelled on that very behaviour. Assert a verdict the host could *not* have produced (the pty test drives a stub menu answering `hello`), and scan the session for shell errors: `test-pgrp.py` checks both for every shell.
- **Read-only specials cannot be shadowed.** `status` is the exit-status variable in zsh and fish; `local status=x` / `set -l status $x` fails and leaves `$status` pointing at the last command's exit code, which then reads as "not selected". Name the local something else (`st`).
- **Expectations come from the contract, not from the implementation.** Asserting what the code already does ("the first two arg tokens are …") verifies nothing and locks the bug in: the fish port's arg-token loop dropped its last token whenever the line ended in a space, so `psc add <Tab>` built the *root* context while every single-index assertion still passed. Assert the whole list against the engine's input semantics (`arg_tokens` = everything between the command word and the pending token, `treat_last_as_complete` marking the empty one), and drive routing→build end to end (`psc add <Tab>` must show `psc add`'s candidates, not `psc`'s).
- **`arg_tokens` carries the pending token.** Everything after the command word, the unfinished one included, with `treat_last_as_complete` saying whether the last is finished: the engine uses that token as the partial match, pre-fills the menu filter from it (`^text`) and drops it from the context walk. Dropping it builds the *parent* context, so `psc al<Tab>` listed the whole root unfiltered and `git add <Tab>` showed git's subcommands. Porting the index math (bash is 0-based, zsh and fish are 1-based) is where a port gets this wrong — twice, in this bridge — so re-derive the bounds and assert the whole list, not single indices.

## 11. By-hand verification (only what no script can observe)

`scripts/bridge/test-all.sh` is the machine-checkable half, and it is the gate: the candidate sets per context, routing and arg tokens, the apply rules, candidate escaping, config forwarding, the order block, key mapping and binding, the management text, and — through the pty test — the menu's process group, the trigger's apply path and the absence of shell errors.
Do **not** re-check any of that by hand, and do not add a hand step for something a suite can assert: a thing that can be asserted belongs in a suite, where it stays checked.

What remains is what a script cannot see.
Walk it once per bridge, per shell:

**The menu itself** (a script reads the input JSON, never the screen)

- Placement and size: the menu hugs the right row for `show_mode`, never covers the prompt, and leaves the covered region as it found it.
- The tip box: content, wrapping, placement, and scrolling for a tip longer than its box.
- The filter row: the localized `filter_hint` (dimmed when empty), `filter_hint_stale` after the data ages, matched characters highlighted in `color_match`, focus in `color_focus`.
- Navigation feel: `enable_list_loop` wrap-around, the counter, and the scrollbar/rail on a long list.
- A large candidate set (a big directory, a completion with hundreds of items): scrolling and latency, not just correctness.
- Non-ASCII and wide candidates (CJK tips, an emoji in a path): no misalignment or truncation.
- `min_area`: shrink the terminal to three or four rows and trigger — the menu must decline and the hint must land below the input line, not on it.
- Mouse: wheel, single click, double click (`menu.md`'s bindings).
- Resize the window while the menu is open.
- The worst-looking prompt the user has (a right prompt, a multi-line prompt, a framework prompt): the menu's own placement and the return to that prompt.

**What the menu leaves behind on the line and the screen**

- Cancel (`Esc`): the line is character-for-character what it was, the cursor is where it was, no color or stray glyph remains.
- Apply: the cursor is where the rules say it is — especially an `=`-attached value (behind the `=`) and a directory (behind the separator).
- An alternate-screen exit: prior output intact, no half-drawn menu rows.
- A menu killed while running (stop the engine process): the watchdog ends it, the terminal is usable, and the shell does not sit in a broken state.
- **Multi-line buffers**: the rules are unit-tested, the `commandline`/readline wiring is not — put the cursor mid-word on the *second* line of a two-line command and trigger.
- The same for the other wired-only rules on the real line: `~`, quotes, a word after the cursor, an attached `=` value, and a directory candidate's separator.

**Interactive and time-shaped flows** (a script can call the function; only a human sees the real keypress)

- Both confirms (`rm --all`, `--reset`): the prompt reads correctly, a bare Enter confirms (the operation proceeds, and for `rm --all` the host then adds `--yes`), any other key cancels with nothing deleted.
- A real `add`/`update` on a slow or failing network: items appear as they finish, failures are red, the exit code is non-zero.
- The notification tail: pending state appends after a management command; `added`/`removed` show once, `update`/`renamed` persist, and both survive a new shell.

**Across sessions**

- A `trigger_key` change: the current shell keeps the old key working, the *next* one binds the new key (and restores the shell's own binding on the old one — verify the key is not dead).
- First run on a machine with no data directory: seeding works offline, and `psc init` behaves with and without network.
- `enable_apply_when_single` / `enable_apply_when_no_match`: whether the automatic apply feels right or fires when the user did not mean it.

**The user's own environment** (the suites run against a fixture data dir and a bare shell)

- The real data dir with everything installed, on the commands they actually use.
- Key modes: vi key bindings, and any `bind`/`abbr`/`fish_user_key_bindings` (or `bindkey`, `bind -x`) of their own that could shadow or be shadowed.
- A terminal multiplexer (reflow, paste, a different `TERM`).
- Their language setting through a full session.

## 12. Native path: three rules every bridge shares

The native path (§2: host candidates rendered in our own menu) is where the shells differ most, so three rules are fixed for all of them.

1. **The candidate payload must not travel in argv or the environment.** A host completion can return thousands of entries (`compgen -f`, a compsys capture, `complete -C`), and a single argument or environment variable is capped at 128 KB — the zsh bridge hit exactly that with a plain `pyt` + Tab (`argument list too long`). Put the payload in a file instead. Today each bridge writes a bridge-private `temp/menu/psc-*-<id>-cands.txt` (format: its own choice), hands the reader only the path, and deletes it once the menu input exists.
2. **The display is the leaf; the inserted text is the whole candidate.** The hosts disagree on what one candidate is: zsh's compsys and PS's `ListItemText` render the entry name (`az zdir/`), while `compgen -f` returns a single text with the typed directory prefix attached (`/tmp/psc t/az zdir/`). The menu shows the leaf (`list_item_text`, the PS convention) and applies the full text (`completion_text`), so all four hosts look alike.
3. **The word under the cursor is found by an escape- and quote-aware scan.** A path with a space arrives escaped (`/tmp/psc\ t/`) from zsh and fish, and quoted (`'/tmp/psc t/'`) from bash and PS. Splitting on a bare space cuts that word apart, so the pick was concatenated after the old text instead of replacing it. Each bridge carries one helper (`_psc_word_start`) that treats `\X` as a literal pair and tracks quote state; its result is the replacement range in that shell's own indexing convention.

## 13. Who owns the terminal when the menu dies

A menu the host kills (watchdog) or that crashes cannot clean up after itself, so on every abnormal exit the host owns two things:

1. **Restore the modes the menu enabled.** The engine turns them on through crossterm (`EnableMouseCapture`, `EnterAlternateScreen`, `cursor::Hide`, bracketed paste) and a clean exit turns them off itself; a killed one cannot: write the whole set — `\e[?1006l\e[?1003l\e[?1002l\e[?1000l\e[?1015l\e[?1049l\e[?25h\e[?2004l`.
2. **Drop the input the terminal already queued.** The mouse reports the terminal sent while the menu was up are still in the tty input buffer, and the shell reads them as literal text on the line. bash / zsh: `termios.tcflush(TCIFLUSH)`; fish: the same, on the monitor's tty fd; PowerShell: `$Host.UI.RawUI.FlushInputBuffer()` — **not implemented in the module yet**: its abnormal-exit cleanup sits inside the Windows-only buffer-save gate, and a leftover mouse mode does not merely dirty the line there — PSReadLine parses the reports as VT sequences and dies on the embedded coordinates.

Leaving mouse capture on is the worst of these: every mouse move then floods the line and the shell is unusable until `reset` — the bash port hit exactly that in the by-hand pass.
A watchdog is what makes the situation reachable at all, so a host that gains one needs both halves in the same commit.

Every shell suite asserts both (the escape set must cover the modes, the bridge must reference the flush): a missing restore is invisible to every other gate.

## 14. What a bridge may touch in the user's shell

A user sources the bridge into an rc file that already carries plenty, so the surface stays narrow and auditable.
The 2026-10 review of the three ports found exactly this.

**Names.** Everything is namespaced: `_psc_*` functions, `_PSC_*` globals (bash/zsh declare four associative arrays, fish a handful of `set -g`).
One intended claim: the **`psc`** command, the module's own CLI entry — it shadows a real `psc` if the user has one, which is documented rather than avoidable.

**One key.** Only the configured trigger key is bound (`bind -x` / `bindkey` / `bind -M default|insert`); nothing else is touched and nothing is unbound.
Which binding wins is decided by order (hence "source last" in the bash/zsh docs) and by fish's user layer.
With `enable_native_completion=0` the host's own completion on that key is given up — that is what the key does.

**No prompt hooks.** `PROMPT_COMMAND`, `precmd`/`preexec` and `chpwd` are never set, so the bridge never runs per prompt.
History is read on demand and normalised into a private copy (bash's `#<epoch>` lines, zsh's extended-history prefix, fish's YAML); the user's history file is never written.

**No lasting shell state.** bash changes no `shopt`/`set`; zsh's two are scoped (`localoptions`, and a save/restore inside the capture); fish keeps to `_PSC_*`.
`PSCOMPLETIONS_DATA_DIR` is set as a **shell** variable rather than exported: every child receives its data directory explicitly (`--data`), and a value already present is honoured — that is the documented override.

**The completion systems are probed, never modified.** bash reads `complete -p` and drives the user's handler with `COMP_*`; zsh shadows `compadd` for the duration of one capture and restores it; fish runs `complete -C`.
Nothing is registered or replaced.
One interaction to know: a host that replaces Tab itself (the `fzf-tab` style) and runs its own UI can fight the capture — the same order question as above.
