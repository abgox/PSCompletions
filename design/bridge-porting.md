# Porting a shell: procedure and verification

Read `design/bridge.md` first: it holds the **rules** a port must satisfy (§9 the capability checklist, §10 porting lessons, §12 the native path, §13 who owns the terminal when the menu dies).
This file is the **procedure** — the order to work in, and what must be verified before a port may be called done.

## A port is not done until both halves are true

1. **The automated suites pass.** A new port adds `scripts/bridge/test.<shell>`, organised like the existing ones, and `scripts/bridge/test-all.sh` gains its entry. That gate is the **floor**, not the proof: a payload can look right and still rank wrongly, or drop a status nothing reads.
2. **The operator has run the by-hand pass below**, for that shell, in a real terminal.

**Ask the operator to run the by-hand pass.
Never declare a port finished from a green gate** — every defect the pass found was invisible to a green gate (see `design/bridge.md` §10).

## What the automated suites must cover (the floor)

| Category | What it pins |
| --- | --- |
| Dispatch / routing | command word vs argument; path-shaped tokens; `git<Tab>` (the command word itself is still being typed) vs `git <Tab>` |
| Apply rules | end of line, mid-word, a following word, an attached value (`--x=`), `enable_append_space`, multi-line buffers, a container (never a trailing space) |
| Word boundary | escapes and quotes (`/tmp/psc\ t/`, `'/tmp/psc t/'`) — the pick replaces the whole word |
| Native path | payload travels in a file (never argv/env); the display is the leaf; items forward `arg_tokens` + `treat_last_as_complete`; `status: input` reaches the caller as text |
| Escaping | the host's own insertion form, differentially against the host (as fish's suite does) |
| Config | every engine-side key forwarded; the hooks gate; the language resolution (per-completion → declared → global) |
| History | the host's history format normalised to plain command lines |
| Watchdog | the restore covers every mode the engine enables, and the queued tty input is dropped |
| Output | status colored, queries plain (`design/psc-cli.md`) |

## The by-hand pass (only a real terminal shows these)

**The menu itself**
- `git <Tab>`: position, size, filter row, counter, a long list, tips.
- Type a prefix, then Tab: does the menu open **narrowed**? (the `arg_tokens` contract)

**Leaving the menu**
- `Esc`: the line is untouched, the cursor returns, no residue — with the menu above *and* below.
- Selecting: only the word under the cursor is replaced; the cursor lands correctly.
- `psc <Tab>` → descend a level → `Esc`: still clean.

**The native path**
- A `pyt<Tab>`-style capture with hundreds of candidates must not fail (payload in a file).
- A path slot with a space (`cd /tmp/psc\ t/`): the pick **replaces** the word, never concatenates.
- A capture whose pending word matches an item: the filter is filled (`^pyt`), matches first.
- `cd /tmp/<Tab>`: **no** filter — a leaf display has no genuine prefix to offer.

**The watchdog**
- Open the menu, `kill -STOP` the menu process, wait 30–45 s: the menu must vanish, the line must stay clean, the shell must keep working, and moving the mouse must not flood the line.
- Do it **per shell**: the implementations differ (bash coproc, zsh `read -t`, fish python).

**Confirmations and notifications**
- `psc rm --all` / `psc --reset`: the prompt appears, and **Enter means proceed** — verify with the cancel path only, then check `psc list` is unchanged.
- A pending-change tail: its position; `added`/`removed` one-shot; `update`/`renamed` persistent.

**Flags**
- `enable_apply_when_single`: turn it on — with a filter that leaves exactly one candidate, the pick is applied without pressing Enter.
- `enable_apply_when_no_match`: a no-match filter plus one more key writes the filter text.
- `trigger_key`: change it, then a **new** shell honours it while the old key returns to the host.

**The environment**
- A real prompt, vi/emacs key modes, existing `bind`/`abbr`, tmux, the user's common commands.
- Where the source line goes: **last** in the rc for bash/zsh (`set -o vi` / `bindkey -v` reset keymaps); fish is order-tolerant (`bind` writes a user layer).
- A command that takes no arguments (`psc add`): no stray `:` in the message.
