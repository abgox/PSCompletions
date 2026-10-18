# Decisions — shell bridges

Why the bridge rules read the way they do. Same four layers as `README.md` describes: the rule
statement lives in `design/bridge.md` (and `AGENTS.md` for completions), the mechanism in
`design/bridge-*.md`, and the evidence behind a trade-off — plus the alternative that was
rejected and the condition that would overturn it — here. Numbering is shared with
`authoring.md`; do not restart it per file.

| Decision | |
| --- | --- |
| D40 | [A shell that cannot hand over the trigger gets no bridge](#d40) |
| D41 | [One presentation: the CLI's text, in every host](#d41) |
| D42 | [A separator ends a command; a brace does not](#d42) |

<a id="d40"></a>

## A shell that cannot hand over the trigger gets no bridge (D40)

**Rule it justifies**: `design/bridge.md` §9 — a port exists only when the bridge can (1) make
the configured trigger key run *its* code and (2) read the input line and write text back. All
shipped bridges keep the trigger key uniform (`Tab`) and all of them open **our** TUI; that
uniformity is the point, not a side effect.

**The case**: nushell 0.116.1 was prototyped in full — ~900 lines, `nu --ide-check` clean,
routing, application, candidate quoting and template rendering all verified (byte-identical
output against `scripts/bridge/render-check.py`) — and then **rejected**, the prototype deleted
with the decision. A rejected port leaves nothing behind: not a file in the module, not a
working directory, and no forward reference to either.

**Evidence**:

1. **The trigger cannot be handed over.** `$env.config.keybindings = <list>` is merged with nu's
   built-ins — assigning a *filtered* list still yields both entries with the built-in first, so
   `tab` stays `completion_menu` and our handler never runs. The only configuration in which the
   external completer *is* consulted is one where `config.nu` **aborts**: bisected with one run
   each — `external.enable` + `completer` alone → hook never runs; the same block plus the invalid
   `completions.algorithm = 'external'` line (which stops the config load) → hook runs, `spans`
   delivered. Building on that means deliberately breaking the user's configuration.
2. **Tab cannot be fed either.** In the hook's command-path form there is no line access, so it
   could not run our TUI; in the closure form it is never called on a healthy config.
3. **The prototype would rot.** In one working session the language changed under it four times:
   `get -i` → `get -o` (deprecated 0.106), `str downcase` → `str lowercase` (0.114), `set-env`
   removed, `char esc` no longer a valid character name. nu is at 0.116 with no 1.0, so the
   maintenance cost is not hypothetical.

**Rejected alternatives**: (a) ship it with the trigger key on a key nu leaves free (our TUI on
that key, Tab left to nu) — rejected: it buys one shell at the price of the uniformity every
other bridge has, and a user who expects `Tab` sees the host's menu instead of ours; (b) ship it
relying on the config-abort behaviour — rejected outright: it breaks the user's own configuration
and drops nu's default bindings; (c) generate static `complete` declarations from our manifests so
nu's own Tab shows our candidates — rejected as a different product (no TUI, and unknown commands
stay uncovered), not as a bridge; (d) loosen §9 to "a host-run hook counts" — the hook clause is
already in §9, and nu fails it in practice because the hook is not run on a healthy config.

**Overturn if**: a future nu lets a built-in binding be replaced (or runs an external/closure
completer on a clean config) **and** its API settles — then the gate is satisfiable and the port
starts again from `design/bridge.md` §9. Keeping the refusal is not a statement about nu's
quality; it is the price of one trigger key and one menu across shells.

---

<a id="d41"></a>

## One presentation: the CLI's text, in every host (D41)

**Rule it justifies**: `design/bridge.md` §7 — a read prints the CLI's text as it stands, and no
host re-renders it; `--json` is the machine contract. This overturns the earlier half of that
bullet, where a *structured host* (PowerShell, nushell) consumed `--json` and emitted host values.

**The case**: the PowerShell module wrapped its query commands in `[pscustomobject]` — `list` /
`alias` → `{Completion, Alias}`, `info` → `{Name, Alias, Url, Description, Path, Update, Updated}`
with a provider-resolved path and a real `DateTime`, `config` → `{Group, Key, Value}`, `completion`
→ `{Completion, Config}` — while bash / zsh / fish printed the CLI's text. Those paths now forward
the CLI's text like the other bridges; `_forward_psc -Plain` is what prints a read uncolored.

**Evidence**:

1. **One binary, one behavior.** The same command reads the same in bash, zsh, fish, nu and
   PowerShell, instead of each host deciding a shape of its own.
2. **The human view was already designed as the shared one.** `psc-cli.md` §Text output shape fixes
   every row shape and states "Color is status, never data … every query is plain text" — and
   `psc-cli.md`'s per-command sections were written as though every host read that text.
3. **`--json` is already the tested machine contract** (`json.md`, `core/cli/tests/json_contract.rs`),
   so scripting loses nothing — and the text keeps derived display the raw payload does not have
   (`info`'s `updated` is a UTC stamp, not unix seconds).

**Rejected alternatives**: (a) hand the `--json` payload over as host values (one line per command,
zero formatting, inherits the tested JSON contract) — rejected as the *default*: the same command
would then read differently per host, and the raw payload is not uniformly the better display
(`info`'s `updated` arrives as unix seconds, `alias` as an array in one cell), so the two shapes
would still not be equal in value; (b) keep the hand-written mapping — rejected: it duplicated rules
the engine already owned (`_value_str` re-implemented `output::key_line` / `value_quoted`) and had
no test at all (`scripts/` carries no PowerShell harness), so a payload field could stop reaching
the objects with nothing to catch it; (c) add an `-AsObject` / `--text` switch — rejected: a second
surface to document, test and keep in step, for something `--json` already provides.

**Overturn if**: the module's query display is reported as real friction for PowerShell users rather
than a one-step `psc list --json | ConvertFrom-Json` — then the payload-passthrough variant can
return for that host alone (it is one line per command and inherits the JSON contract), with the
text kept everywhere else. The hand-written mapping stays rejected either way.

---

<a id="d42"></a>

## A separator ends a command; a brace does not (D42)

**Rule it justifies**: `design/bridge.md` §2 — only the text after the last unquoted separator
before the cursor is the command being edited, with the separator set `|`, `;`, `&`, `&&`, `||`.

**The case**: every bridge resolved the first token of the *whole line*, so `git status | grep
<Tab>` opened **git's** menu and `grep` could not be completed. The same line with an uninstalled
first word worked by accident, because PowerShell's native fallback (`TabExpansion2`, an AST parse)
is pipeline-aware — so the defect was precisely the fast path taking over.

**Evidence**:

1. **The separators are the shells' control operators, and the hosts agree.** bash, zsh and fish
   each background on a lone `&` (`true & echo $!` prints a job id), and PowerShell's parser reports
   `Ampersand` for the call operator — which for completion means the same thing a separator means:
   the next word is a command (`& git <Tab>` completes git's arguments).
2. **A redirection is not a separator.** `2>&1` and `&>` must not split. PowerShell's lexer reports
   nothing for them (`git show 2>&1` yields no separator token), and the POSIX scan carries one rule
   for the pair.
3. **A brace is not a separator, in either direction.** Where `}` ends a block a separator is
   *required* after it — bash rejects `{ true; } echo x` outright, and fish answers `'}' does not
   take arguments. Did you forget a ';'?` — so splitting there adds nothing. Where it does not end a
   block, splitting breaks the line: PowerShell's `Where-Object { $_ } | Select-Object` continues the
   same command, zsh and fish expand `{a,b}` into two arguments, and bash's `${X}` puts an
   **unquoted** `}` inside a word. Quoting cannot separate the two cases, because every
   counter-example is unquoted.
4. **Quotes and escapes hide a separator**, so `--grep "a|b"` and `--format='%h|%s'` stay one
   argument. PowerShell gets that from the parser; the POSIX bridges from the quote state their word
   scanner already tracks.

**Rejected alternatives**: (a) split on a `|` *token* instead of scanning the text — rejected:
`status|grep` and `ls;git` glue the separator to a word, so the token view misses exactly the cases
where the wrong command is most likely; (b) split on `{` / `}` — rejected on the evidence above;
(c) resolve the first word of the whole line and let the host's completion cover the rest —
rejected: it is the behaviour that made `git status | grep <Tab>` unusable.

**Overturn if**: a host appears whose grammar treats one of these characters differently *and*
whose completion API cannot be consulted for the pipeline case — then that host's separator set is
narrowed, with the rule above kept as the default.
