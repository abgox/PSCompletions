# Authoring decisions (completions)

The rationale behind the rules in `AGENTS.md`. This file answers *why a rule reads the way it
does* — the measurement behind it, the alternative that was rejected, and the condition under
which it should be overturned. It does **not** restate the rules: an author following
`AGENTS.md` never needs this file, and a change to a rule belongs in `AGENTS.md`, not here.

Scope: decisions made while **writing or maintaining completions** — static manifests and
`hooks.lua` alike. Decisions about the engine, the menu, or the `psc` CLI are system design
and live in `design/`.

Each entry is *decision → where the rule lives → why → evidence → overturn if*. Several entries deliberately have **no rule at all**; they are marked, with the reason, because
"we tried this and it was wrong" is worth more here than silence.

When a ruling changes a rule, change the rule in `AGENTS.md` and add or amend the entry here in the same
commit — a reason must never live longer than the rule it justifies.

---

## Index

| # | Entry |
| --- | --- |
| D1            | [Value placeholder syntax follows the CLI](#d1) |
| D2b–D2e       | [The three optional option shapes are standard, not special cases](#d2-2) |
| D13           | [A closed enumeration is worth listing](#d13) |
| D3, D12       | [The manifest has no `name`/`alias` hierarchy](#d3-12) |
| D30           | [Hook targets are written in the longest form](#d30) |
| D7            | [A subcommand list must be probed, not inferred](#d7) |
| D8            | [Every command-level alias must be recorded](#d8) |
| D9            | [Read `--help` by section](#d9) |
| —             | [Option lines have two silent-corruption traps](#option-traps) |
| D10           | [Platform-specific topics stay, marked](#d10) |
| D11           | [Paths are platform-neutral by default](#d11) |
| D15           | [404 does not mean "cannot be installed"](#d15) |
| D4, D20, D22  | [The inclusion criterion: can it be dispatched?](#d4-20-22) |
| D5            | [Upstream is authoritative; a locally missing command is not a deletion reason](#d5) |
| D17           | [The directory name is the command the user types](#d17) |
| D21           | [`@` names the source, never the platform](#d21) |
| D16           | [Global option is a sharing mechanism, not a validity claim](#d16) |
| D23           | [Fill hook gaps while you still have the context](#d23) |
| D24           | [A forwarding command's subcommand table is the union of its implementations](#d24) |
| D18           | [File globs fall into three classes; probe tools are tiered](#d18) |
| D19           | [A Windows-only environment variable needs a platform guard](#d19) |
| —             | [Platform guards and probe discipline for GUI/TUI tools](#gui-probe) |
| D6            | [The Linux re-audit checklist](#d6) |
| D26           | [Data-writing scripts must resolve aliases too](#d26) |
| D27           | [Grouping psc.on specs](#d27) |
| D28           | [A checker's own coverage must be measured](#d28) |
| D14, D25, D29 | [Deliberately not merged](#d14-25-29) |

<a id="d1"></a>

## Value placeholder syntax follows the CLI (D1)

**Decision**: `usage` writes the value placeholder the way the tool's own `--help` writes it —
`--opt <VAL>` with a space by default, `--opt=<VAL>` only when the CLI itself uses `=`.

**Rule lives in**: `AGENTS.md` §`tip` / `usage` / `example` Format Rules.

**Why**: the usage line is read next to what the user is about to type. A shape the tool would
reject is noise in the one place the user is checking the shape.

---

<a id="d2-2"></a>

## The three optional option shapes are standard, not special cases (D2b–D2e)

**Decision**: `--opt[=<VAL>]` (optional value) keeps whatever the CLI writes; `--opt=(a|b)`
(closed enumeration) is a standard shape; a glued short-option value `-U<n>` normalises to
`-U, --unified <n>` unless the CLI accepts nothing else. `separator` keeps its existing spec.
A negatable `--[no-]` switch is **two entries** (`--foo` / `--no-foo`), never one `[no-]` line.

**Rule lives in**: `AGENTS.md` §`tip` / `usage` / `example` Format Rules.

**Why**: each shape promises something different to the user. A closed enumeration says "only
these two are possible", which `usage` conveys and a bare `<VAL>` does not; `next` then lets
them pick one directly. The glued form is a man-page convention that git's `parse-options`
happens to accept either way, so normalising it loses nothing and removes a per-item decision.

**Rejected alternatives for the negatable switch**: (a) split every one into two entries — chosen,
because it is both the existing majority and the clearest at completion time, since the user can
pick `--no-verify` directly; (b) allow the `[no-]` form on its own — rejected, it hides one of the
two flags from the menu; (c) a hybrid keyed on "high frequency", rejected as needing a definition
of frequency that does not exist. `compare-json` accepts both forms, so the choice was never
forced by a gate.

**Overturn if**: a tool's own `--help` leads with `--[no-]` *and* both directions are in common
use — then a single `[no-]` line is more honest to the CLI, and report it here when first used.

---

<a id="d13"></a>

## A closed enumeration is worth listing (D13)

**Decision**: when a slot takes a fixed set of values, list them even though every value is
knowable at authoring time. Stated as guidance with the trade-off attached, not as a hard rule.

**Rule lives in**: `AGENTS.md` §Manifest Field Summary.

**Why**: the reasoning that keeps *hooks* out of a slot — "can this value be determined while
writing?" — does not apply to a fixed set. The CLI itself presents these as a list, and the
test is whether the user would otherwise have to know an unfamiliar name.

**Evidence**: `stripe resources` lists the API resource names, none of which a user could guess.

**Overturn if**: a set is unbounded in practice. `**/*.{js,ts}` is not a small filtered set —
it is the whole repository, and listing it buries the static candidates.

---

<a id="d3-12"></a>

## The manifest has no `name`/`alias` hierarchy (D3, D12)

**Decision**: `name` is always the longest form because `scripts/sort-json.ps1` enforces that on
every run, so "which form is primary" was never an open question. It is still **not** a semantic
claim about the tool: the CLI's own primary name may be the shorter one, and the only hard
requirement is that both forms appear in `usage`.

**Rule lives in**: `AGENTS.md` §Manifest Field Summary.

**Why**: `k3d config create` is dispatched by the CLI as `init`; `svn praise` as `blame`. Having
inverted a manifest against the tool's preference is not a defect, and a note in the tip saying
which form the tool prefers was tried and reverted — it reads as an apology for the data.

---

<a id="d30"></a>

## Hook targets are written in the longest form (D30)

**Decision**: a `psc.on` target names the canonical `name`, which is the longest form. Because
`sort-json` guarantees it, no per-file comment is needed to explain that.

**Rule lives in**: `design/hooks.md` §9; `AGENTS.md` §Manifest Field Summary.

**Why**: `psc.on` matches command segments against the canonical name only, and the canonical is
the manifest's own `name` (`canonical_name()` in `core/engine/src/engine/completion.rs`).
`sort-json` puts the longest form there, so "write the longest" cannot be got wrong. A tool whose
own primary name is shorter — jj's `evolog`, mise's `ls` — is therefore not an error, and
reporting it as one would mean treating the tool's preference as a defect.

**Evidence**: nine hook targets across the repository named an alias and so could never fire. They
were silent — the hook simply never ran and the slot stayed empty — and neither other gate looked,
because both only check internal consistency. All nine were found by
`scripts/check-hook-targets.ps1`, which exists for exactly this.

**Overturn if**: the tie-break rule changes; then this becomes a per-file judgement again.

---

<a id="d7"></a>

## A subcommand list must be probed, not inferred (D7)

**Decision**: for every command in the manifest, run `<cmd> <sub> --help` and look for a
commands section. Output present → the manifest needs a non-empty `next`. Output absent while
the manifest has one is not a verdict on its own, because `next` is dual-purpose (subcommands, or
candidate values for a positional slot) — judge it from the command's `usage`.

**Rule lives in**: `AGENTS.md` §Collecting Command Info; §Pre-completion Checklist.

**Why**: `compare-json` and `validate-completion` only check internal consistency, so a parent
modelled as a leaf passes both. Five such instances existed in `gh` alone, and `netlify teams
list` was an invented subcommand whose `--help` quietly printed its parent's help.

---

<a id="d8"></a>

## Every command-level alias must be recorded (D8)

**Decision**: record every alias the CLI lists, with no length cutoff.

**Rule lives in**: `AGENTS.md` §Collecting Command Info.

**Why**: `compare-json` validates an alias that is already recorded but never reports a *missing*
one, so nothing else will. A missing alias is a functional gap: the user cannot discover the
short form exists.

---

<a id="d9"></a>

## Read `--help` by section (D9)

**Decision**: decide what a help section is by its name. A section whose name ends in `COMMANDS`
is the commands section; `HELP TOPICS` is documentation; option descriptions and trailing prose
are neither.

**Rule lives in**: `AGENTS.md` §Collecting Command Info.

**Why**: scraping the wrong section invents commands that do not exist — `gh mintty` comes from a
trailing `NOTE`, `gh api`'s `--hostname` from a stray line. A blacklist of section names is worse
than the rule: the word `gh` appears inside an `EXAMPLES` section.

---

<a id="option-traps"></a>

## Option lines have two silent-corruption traps

**Decision**: take an option's description from the text *after* the flag and its placeholder, and
anchor the flag at the start of the line.

**Rule lives in**: `AGENTS.md` §Collecting Command Info.

**Why**: in `--file-type string        Set file type…`, `string` is a placeholder, so a faithful
transcription writes it into the tip; in `  -a, --append            Append files…`, the comma
belongs to the short form, so a parser that treats it as a separator splits one option into two.
Both produce a manifest that passes every gate and is wrong.

---

<a id="d10"></a>

## Platform-specific topics stay, marked (D10)

**Decision**: keep a documented command or option that is unusable on the current platform, and
mark it `(Windows only)` / `(macOS only)`.

**Rule lives in**: `AGENTS.md` §`tip` / `usage` / `example` Format Rules.

**Why**: removing it loses `gh help mintty`-style discoverability; the marker makes the limitation
visible before the user tries.

---

<a id="d11"></a>

## Paths are platform-neutral by default (D11)

**Decision**: `grep -rn 'C:\\Users\|/Users/\|%[A-Za-z]\+%' completions/<cmd>/` must return
nothing. Prefer a neutral form (`~/.gnupg/pubring.kbx`, `/home/<user>/`); show **both** platform
forms only when the tool documents different defaults per platform and they are not
interchangeable.

**Rule lives in**: `AGENTS.md` §Linux re-audit Checklist.

**Why**: a default that varies per machine leaks the author's machine and is wrong for everyone
else. A per-platform pair is a fact about the tool; one machine's path is an artefact.

---

<a id="d15"></a>

## 404 does not mean "cannot be installed" (D15)

**Decision**: before recording a tool as skipped, find its real package name. Many ship as scoped
packages: `rspack` → `@rspack/cli`, `rsbuild` → `@rsbuild/core`, `ionic` → `@ionic/cli`,
`rsdoctor` → `@rsdoctor/cli` (not `@rsdoctor/core`, which is a library with no bin). Verify with
`npm view <pkg> version` and `npm view <pkg> bin`.

**Rule lives in**: `AGENTS.md` §Linux re-audit Checklist.

**Why**: a name that 404s on the registry reads as "unavailable" and silently shrinks the
completion set.

---

<a id="d4-20-22"></a>

## The inclusion criterion: can it be dispatched? (D4, D20, D22)

**Decision**, consolidating three earlier rulings:

1. **Dispatch is the only test for membership.** Prerequisite configuration, rarity, and whether
   the user would type it are all irrelevant — the menu *is* the discovery surface, and deciding
   by a property the user cannot know in advance would stop the completion from doing its job.
2. **Not installed or not runnable here is not a reason to exclude.** `gitk` / `gitweb` (Homebrew
   builds no Tcl/Tk), `lfs` / `scalar` / `svn` (not installed) all stay. Whether to *delete* an
   entry is the version-skew question below.
3. **Extensions are judged by dispatch, not by being a separate binary.** If the parent dispatches
   it, it goes in the parent's manifest: `cargo fmt` (a rustup component), `docker compose`, even
   `podman compose` (a different binary entirely).
4. **The only exclusions are "not a command at all"**: `citool` (a Perl GUI git removed),
   shell-library entry points such as `sh-i18n` / `sh-setup` (the real sibling is
   `sh-i18n--envsubst`), and documentation topics.
5. **Never draw a porcelain / plumbing line.** The manifest already carries `daemon`,
   `http-backend`, `imap-send`, `mailsplit`; pruning "internal" commands after that contradicts
   itself.

**Rule lives in**: `AGENTS.md` §Collecting Command Info.

**Evidence**: the git manifest carried 129 core commands while 26 dispatchable ones were missing.
`git flow` had been deleted on the reasoning that it was a third-party extension — but
`git flow --help` answers `git: 'flow' is not a git command`, so git itself had stopped
dispatching it. That is a statement about git, not about extensions.

**Verification**: `git --list-cmds=main` gives the authoritative builtin list; then
`git <cmd> --help` per entry — exit code 16 means found without a man page, 0 means found with
one, and both count as dispatchable. Only `is not a git command` does not.

---

<a id="d5"></a>

## Upstream is authoritative; a locally missing command is not a deletion reason (D5)

**Decision**: when the local binary and `meta.url`'s upstream disagree, trust the upstream docs /
command list. Delete only when upstream has removed it, or the CLI rejects it locally **and**
upstream has no such command. Documentation topics and shell-library entry points are never
encoded.

**Rule lives in**: `AGENTS.md` §Updating Existing Completions.

**Evidence**: both directions occur. `format-rev` / `history` landed upstream in 2026-05 while the
local 2.53.0 had neither — deleting them would have been wrong. `survey` does not exist upstream at
all — keeping it would have been wrong.

---

<a id="d17"></a>

## The directory name is the command the user types (D17)

**Decision**: name a completion directory after the command the user actually types, and add
`alias` only when upstream officially recognises more than one name.

**Rule lives in**: `AGENTS.md` §`config.json` Structure.

**Why**: the directory list is read by users, so it must match their input. `hx` has no `alias` —
`helix` is only the product name and no platform installs a `helix` command, so an alias would
invent a trigger and could hijack a user's own command. `python3` does have one: PEP 394 makes it
canonical on POSIX while the Windows docs recommend `python`. When only one name is officially
valid, omit `alias` and let the user configure their own triggers after install.

**Overturn if**: `python4` appears — re-evaluate rather than pre-emptively adding a directory per
version, which recreates the pressure to keep one directory per release.

---

<a id="d21"></a>

## `@` names the source, never the platform (D21)

**Decision**: the part after `@` names the implementation's source, following the source's own
spelling and case (`@uutils`, `@GNU`, `@BSD`), never the platform. The part before `@` matches
the command name character for character. Once a command has variants, **every** variant carries
its suffix — there is no bare "default", because a bare name hides which implementation it
documents and every default is somebody's subjective choice. A user installs exactly the variant
matching their system, so same-word collisions are misuse, not a case to resolve.

**Rule lives in**: `AGENTS.md` §`config.json` Structure.

**Why**: a completion describes an *implementation*, and the platform it runs on is an unstable
axis — uutils itself runs everywhere, which is why the existing split is `@uutils` and not
`@Linux`. Keeping the suffix single-valued also removes the need for a double suffix. The case
follows the source project's own spelling: uutils is lowercase, GNU and BSD are uppercase. A
directory containing `@` must declare `alias`, because triggers are first-come-first-served and
nobody types `AAA@author`.

---

<a id="d16"></a>

## Global option is a sharing mechanism, not a validity claim (D16)

**Decision**: a flag shared verbatim by many subcommands belongs in `global_option` even when the
root itself rejects it. Keep it on a subcommand's own `option` when only a few subcommands take
it, or when the entries differ per subcommand.

**Rule lives in**: `AGENTS.md` §Collecting Command Info; `design/completion.md` §`option` vs
`global_option`.

**Why**: duplicating the entry across N subcommands costs N copies to write and N edits per
wording change; leaving it in `global_option` costs the user one `unexpected argument` on the
commands that reject it, which the CLI explains immediately. The menu entry is not a claim that
the flag is valid — the CLI is always the validator.

**Evidence**: most of cargo's subcommands accept `--manifest-path`, but `cargo --manifest-path`
errors. `gitk` / `gitweb` / `gui` cannot run under a Homebrew build but ship separately on
Debian/Fedora/Arch, and `lfs` / `scalar` / `svn` follow the same shape.

**Note**: a contradicting third row survived in a staging copy of `design/completion.md` for
weeks, which sent the same "misplaced flag" proposal back for review twice. The cost trade-off is
stated in `design/completion.md` precisely so it cannot be re-derived from a stale copy.

---

<a id="d23"></a>

## Fill hook gaps while you still have the context (D23)

**Decision**: when a review has already produced the full command tree and its help, do not fix
only the bug and leave the hook gaps for later. Walk every command path, extract the positional
placeholders from each `usage`, and check the difference against the existing `psc.on` targets.
Three slot classes explicitly get no hook: a name the user invents (`label create <name>`), a
value too thin to be worth a round trip (`ssh-key delete <id>`), and a slot that does not take
that value at all.

**Rule lives in**: `design/hooks.md` §9.

**Why**: context is not always available. A review that has the tree in hand is the cheapest
possible moment to find the gaps, and the placeholder inventory is mechanical.

**Evidence**: a placeholders-only first pass nearly attached a repository name to
`repo deploy-key add`, whose slot takes a key file. The classification is a screen, not a verdict —
the command's own `usage` decides.

---

<a id="d24"></a>

## A forwarding command's subcommand table is the union of its implementations (D24)

**Decision**: when `<cmd>` only forwards to a provider (`podman compose`'s man page says the
commands and flags are handed straight to the compose provider), the subcommand table is the
**union** of all known implementations, not a snapshot of one.

**Rule lives in**: `design/hooks.md` §9.

**Why**: the manifest documents the command as the user experiences it, and different installs
provide different subcommands. `podman-compose` has `inspect` / `list`; `docker-compose` does not.

**Verification**: a forwarding command often answers an unknown command with the top-level usage
and rc 0 or 1, which is indistinguishable from a real command missing from `--help`. Set a fake
control command and compare. Write the wrapper's own tip to say the subcommands belong to the
provider.

**Order of collection**: run what runs locally → read the source's command registration for what
does not → official docs last, because docs lag.

---

<a id="d18"></a>

## File globs fall into three classes; probe tools are tiered (D18)

**Decision**: a file glob is worth writing when the file is found **by name** at a depth the user
has not typed (`tsconfig*.json`, `.swcrc`, `Cargo.toml`, `wrangler.toml` — a recursive glob whose
last segment contains a literal name fragment). Leave "any file of this type somewhere"
(`**/*.{js,ts}`) to native path completion. An extension-only glob is allowed only when the tool
accepts no other kind of file in that slot and the format belongs to the tool rather than the
user (`buf` takes `.proto` and nothing else).

**Rule lives in**: `design/hooks.md` §9. The probe-tool tiering stays here: run what runs, read
source for what does not, docs last.

**Why**: native path completion works inside the current directory and once the user has typed a
prefix, so it can never find a named file at an untyped depth — that is the gap a hook must fill.
But `**/*.{js,ts}` is the whole repository by construction, and listing it buries the subcommands.

**Evidence**: the same distinction decided `tofu -var-file` (the tool owns the format, keep it) and
`docker build` (the user's own file, native completion is better) — which is why the question to ask is "whose file is it" and not "is it a glob".

---

<a id="d19"></a>

## A Windows-only environment variable needs a platform guard (D19)

**Decision**: prefer a portable path first, and put any Windows-only variable behind
`if psc.platform == "windows"` with a non-empty check.

**Rule lives in**: `design/hooks.md`, beside `psc.platform`.

**Why**: `APPDATA` is always empty on Linux, and `psc.path("")` degrades to a path relative to the
current directory — so the lookup silently succeeds somewhere wrong.
`HOME or USERPROFILE or ""` is safe on its own; the dangerous shape is narrower, a Windows-only
variable as the first link of an `or ""` chain.

---

<a id="gui-probe"></a>

## Platform guards and probe discipline for GUI/TUI tools

**Decision**: a GUI or TUI tool is only ever read with `--help`, never invoked flag by flag, and no
"accepted / rejected" conclusion is drawn from it.

**Rule lives in**: `AGENTS.md` (probe discipline); the reason is here.

**Why**: `code <flag>` opens a window per invocation and was enough to lock the operator's
machine. A GUI tool's exit code and output say nothing about whether a flag is valid.

---

<a id="d6"></a>

## The Linux re-audit checklist (D6)

**Decision**: the per-review platform checklist lives in `AGENTS.md` §Linux re-audit Checklist
as its own section; no second copy is maintained anywhere.

**Why**: a checklist that exists in two places is a checklist that will be updated in one of
them. This entry exists so the identifier resolves.

---

<a id="d26"></a>

## Data-writing scripts must resolve aliases too (D26)

**Decision**: any script that writes manifest data must index an option by both its `name` and
its `alias` entries, the same way the hook-target checker does.

**Enforced by**: `scripts/check-hook-targets.ps1`. Deliberately **not** restated in `AGENTS.md` —
a rule the tooling already guarantees does not need prose, and prose about it would suggest an
exception that does not exist.

**Why**: a script that matched only `name` reported working manifest entries as missing, which
nearly deleted correct data.

---

<a id="d27"></a>

## Grouping psc.on specs (D27)

**Decision**: several `psc.on` calls that share a handler go into one array spec. Split them only
when the reasons differ, with a one-line comment saying why. A single target is not wrapped in an
array, and specs are not regrouped by command — the API takes a command and an option, not a
command-group.

**Rule lives in**: `design/hooks.md` §9.

**Why**: merging is exactly the edit that can silently drop a target, which is why the grouping
was settled by counting the checker's targets before and after rather than by preference. A single
target stays unwrapped, because `psc.on` takes `psc_on_spec | psc_on_spec[]` and wrapping one
target implies a group that is not there.

---

<a id="d28"></a>

## A checker's own coverage must be measured (D28)

**Decision**: when a checker gains a capability, quantify how much more it now looks at before
looking at what it reports.

**Enforced by**: `scripts/check-hook-targets.ps1` (header comment). Deliberately not prose in
`AGENTS.md` — this is about how to build a checker, not how to write a manifest.

**Evidence**: extracting only *inner* groups from a `psc.on` spec left **238 targets across 53
files completely unchecked** while the checker reported success. The target count went from 1159
to 1397 once it was fixed. A count of failures alone would never have shown the blind spot, because
an unchecked target cannot fail.

---

<a id="d14-25-29"></a>

## Deliberately not merged (D14, D25, D29)

Three rulings are archived here rather than turned into rules, with the reason, because a rule
nobody can delete is worse than no rule. (D28 was archived for the same reason and has since been
given its own entry, because its measurement turned out to be worth keeping.)

**Rebuilding a completion wholesale is allowed when the gap is enormous** (plus delegating the
translation). It is a review-phase permission, not something an author needs while writing a
manifest.

**Run known-answer cases before trusting a checker, and calibrate the checker before trusting it
again.** The help reader behind the retired live-verification mode went through five versions and
each of the first four reported working targets as dead — every one a reader bug rather than a
manifest problem. This is how to build a checker, so it belongs with the checkers.

**Known gaps stay listed instead of being guessed at.** Deferred items: `docker buildx` (the
plugin is not installed locally, so `docker buildx` answers `unknown command`); `docker compose`
service names (the producer depends on the cwd's project context, which is a pattern-level
question, not one completion's); `cargo miri` / `cargo tauri` (listed by `cargo --list`, but
`cargo miri` answers `no such command`). In each case only the documentation is available, and
copying documentation is how invented subcommands happen.
