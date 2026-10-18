# Decisions — shell bridges

Why the bridge rules read the way they do. Same four layers as `README.md` describes: the rule
statement lives in `design/bridge.md` (and `AGENTS.md` for completions), the mechanism in
`design/bridge-*.md`, and the evidence behind a trade-off — plus the alternative that was
rejected and the condition that would overturn it — here. Numbering is shared with
`authoring.md`; do not restart it per file.

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
