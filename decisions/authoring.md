# Authoring decisions (completions)

The rationale behind the rules in `AGENTS.md`.
This file answers *why a rule reads the way it does* — the measurement behind it, the alternative that was rejected, and the condition under which it should be overturned.
It does **not** restate the rules: an author following `AGENTS.md` never needs this file, and a change to a rule belongs in `AGENTS.md`, not here.

Scope: decisions made while **writing or maintaining completions** — static manifests and `hooks.lua` alike.
Decisions about the engine, the menu, or the `psc` CLI are system design and live in `design/`.

Each entry is *decision → where the rule lives → why → evidence → overturn if*.
Several entries deliberately have **no rule at all**; they are marked, with the reason, because "we tried this and it was wrong" is worth more here than silence.

When a ruling changes a rule, change the rule in `AGENTS.md` and add or amend the entry here in the same commit — a reason must never live longer than the rule it justifies.

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
| D8            | [Every alias must be recorded](#d8) |
| D9            | [Read `--help` by section](#d9) |
| —             | [Option lines have three silent-corruption traps](#option-traps) |
| D10           | [Platform-specific topics stay, marked](#d10) |
| D11           | [Paths are platform-neutral by default](#d11) |
| D15           | [404 does not mean "cannot be installed"](#d15) |
| D5            | [Upstream is authoritative; a locally missing command is not a deletion reason](#d5) |
| D31           | [An unverified fallback is dead code](#d31) |
| D32           | [Trailing punctuation is not a rule](#d32) |
| D17           | [The directory name is the command the user types](#d17) |
| D21           | [`@` names the source, never the platform](#d21) |
| D16           | [Global option is a sharing mechanism, not a validity claim](#d16) |
| D23           | [Fill hook gaps while you still have the context](#d23) |
| D24           | [A forwarding command's subcommand table is the union of its implementations](#d24) |
| D18           | [Hooks do not offer file paths as candidates; probe tools are tiered](#d18) |
| D19           | [A Windows-only element needs a platform guard](#d19) |
| —             | [Platform guards and probe discipline for GUI/TUI tools](#gui-probe) |
| D6            | [The platform checklist has one home](#d6) |
| D26           | [Data-writing scripts must resolve aliases too](#d26) |
| D27           | [Grouping psc.on specs](#d27) |
| D28           | [A checker's own coverage must be measured](#d28) |
| D33           | [Complementary options are not aliases](#d33) |
| D34           | [Tips are multi-line arrays; split multi-sentence content](#d34) |
| D35           | [No order is prescribed for enumerations](#d35) |
| D36           | [A shadow with a differing tip is kept, silently](#d36) |
| D37           | [Working files live in `WIP/`, deleted on confirmation](#d37) |
| D38           | [Running a script is the dangerous step](#d38) |
| —             | [Option-dispatched chains are recorded nested, surfaced by hook](#opt-chains) |
| —             | [Build-dependent sets are runtime state](#build-sets) |
| —             | [Join tests on wrapped lines are windowed to the junction](#join-window) |
| —             | [A help command mounts the table instead of duplicating it](#mount-help) |
| D39           | [Probes are contained because the killer is transitive](#d39) |
| D43           | [A help page is evidence only after its completeness is shown](#d43) |
| D44           | [Completeness needs its own measurement](#d44) |
| D45           | [Rebuild from the source instead of patching the diff](#d45) |
| D46           | [Hook decisions are a by-product of collection](#d46) |
| D47           | [A hook target names a slot, not a command](#d47) |
| D48           | [A shared constant set is mounted, not copied](#d48) |
| D49           | [Completion inserts a whole value, not a fragment](#d49) |
| D50           | [No hooks is a decision, not a default](#d50) |
| D51           | [A command with a possible side effect is authorized before it runs](#d51) |
| D53           | [A wrapper's passthrough modules are a scope decision](#d53) |
| D54           | [A suppressed flag is not a documented spelling](#d54) |
| D56           | [A bare flag and its attached value are two entries](#d56) |

<a id="d1"></a>

## Value placeholder syntax follows the CLI (D1)

**Decision**: `usage` writes the value placeholder the way the tool's own `--help` writes it — the **name** as well as the separator: `--opt <VAL>` with a space by default, `--opt=<VAL>` only when the CLI itself uses `=`.
The name is copied, not paraphrased.

**Rule lives in**: `authoring/manifest.md` §`tip` / `usage` / `example` format.

**Why**: the usage line is read next to what the user is about to type.
A shape the tool would reject is noise in the one place the user is checking the shape.
A paraphrased placeholder (`<PACKAGE>` where the CLI writes `<UPGRADE_PACKAGE>`) is the same failure one degree softer: the line the user checks against the tool's own `--help` no longer matches it.

**Evidence**: uv 0.13.0's manifest carried 47 paraphrased placeholders against 669 copied verbatim, concentrated in the `--*-package` / `--*-group` / `--output-*` families.
The original text named only the separator, and a reviewer read the name out of scope — the ambiguity survived a full audit because no gate compares a placeholder against the CLI.

---

<a id="d2-2"></a>

## The three optional option shapes are standard, not special cases (D2b–D2e)

**Decision**: `--opt[=<VAL>]` (optional value) keeps whatever the CLI writes; `--opt=(a|b)` (closed enumeration) is a standard shape; a glued short-option value `-U<n>` normalises to `-U, --unified <n>` unless the CLI accepts nothing else.
`separator` keeps its existing spec.
A negatable `--[no-]` switch is **two entries** (`--foo` / `--no-foo`), never one `[no-]` line.

**Rule lives in**: `authoring/manifest.md` §`tip` / `usage` / `example` format.

**Why**: each shape promises something different to the user.
A closed enumeration says "only these two are possible", which `usage` conveys and a bare `<VAL>` does not; `next` then lets them pick one directly.
The glued form is a man-page convention that git's `parse-options` happens to accept either way, so normalising it loses nothing and removes a per-item decision.

**Rejected alternatives for the negatable switch**: (a) split every one into two entries — chosen, because it is both the existing majority and the clearest at completion time, since the user can pick `--no-verify` directly; (b) allow the `[no-]` form on its own — rejected, it hides one of the two flags from the menu; (c) a hybrid keyed on "high frequency", rejected as needing a definition of frequency that does not exist.
`compare-json` accepts both forms, so the choice was never forced by a gate.

**Overturn if**: a tool's own `--help` leads with `--[no-]` *and* both directions are in common use — then a single `[no-]` line is more honest to the CLI, and report it here when first used.

---

<a id="d13"></a>

## A closed enumeration is worth listing (D13)

**Decision**: when a slot takes a fixed set of values, list them even though every value is knowable at authoring time.
Stated as guidance with the trade-off attached, not as a hard rule.

**Rule lives in**: `authoring/manifest.md` §Field semantics in use.

**Why**: the reasoning that keeps *hooks* out of a slot — "can this value be determined while writing?" — does not apply to a fixed set.
The CLI itself presents these as a list, and the test is whether the user would otherwise have to know an unfamiliar name.

**Evidence**: `stripe resources` lists the API resource names, none of which a user could guess.

**Overturn if**: a set is unbounded in practice.
`**/*.{js,ts}` is not a small filtered set — it is the whole repository, and listing it buries the static candidates.

---

<a id="d3-12"></a>

## The manifest has no `name`/`alias` hierarchy (D3, D12)

**Decision**: `name` is always the longest form because `scripts/sort-json.ps1` enforces that on every run, so "which form is primary" was never an open question.
It is still **not** a semantic claim about the tool: the CLI's own primary name may be the shorter one, and the only hard requirement is that both forms appear in `usage`.

**Rule lives in**: `authoring/manifest.md` §Field semantics in use.

**Why**: `k3d config create` is dispatched by the CLI as `init`; `svn praise` as `blame`.
Having inverted a manifest against the tool's preference is not a defect, and a note in the tip saying which form the tool prefers was tried and reverted — it reads as an apology for the data.

---

<a id="d30"></a>

## Hook targets are written in the longest form (D30)

**Decision**: a `psc.on` target names the canonical `name`, which is the longest form.
Because `sort-json` guarantees it, no per-file comment is needed to explain that.

**Rule lives in**: `design/hooks.md` §9; `authoring/manifest.md` §Field semantics in use.

**Why**: `psc.on` matches command segments against the canonical name only, and the canonical is the manifest's own `name` (`canonical_name()` in `core/engine/src/engine/completion.rs`).
`sort-json` puts the longest form there, so "write the longest" cannot be got wrong.
A tool whose own primary name is shorter — jj's `evolog`, mise's `ls` — is therefore not an error, and reporting it as one would mean treating the tool's preference as a defect.

**Evidence**: nine hook targets across the repository named an alias and so could never fire.
They were silent — the hook simply never ran and the slot stayed empty — and neither other gate looked, because both only check internal consistency.
All nine were found by `scripts/check-hook-targets.ps1`, which exists for exactly this.

**Overturn if**: the tie-break rule changes; then this becomes a per-file judgement again.

---

<a id="d7"></a>

## A subcommand list must be probed, not inferred (D7)

**Decision**: for every command in the manifest, run `<cmd> <sub> --help` and look for a commands section.
Output present → the manifest needs a non-empty `next`.
Output absent while the manifest has one is not a verdict on its own, because `next` is dual-purpose (subcommands, or candidate values for a positional slot) — judge it from the command's `usage`.

**Rule lives in**: `authoring/collecting-info.md` §The subcommand probe; `authoring/validation.md`.

**Why**: `compare-json` and `validate-completion` only check internal consistency, so a parent modelled as a leaf passes both.
Five such instances existed in `gh` alone, and `netlify teams list` was an invented subcommand whose `--help` quietly printed its parent's help.

---

<a id="d8"></a>

## Every alias must be recorded (D8)

**Decision**: record every alias the CLI lists — command-level *and* option-level — with no length cutoff.
A spelling the tool documents but hides from `--help` is still an alias the CLI lists; decide by invocation, not by `--help`.
Aliases are **scoped to the page that lists them**: the same short form legally belongs to different long options on different pages, so harvest per page and never merge into one global table.

**Rule lives in**: `AGENTS.md` `R-03`; `authoring/collecting-info.md` §Aliases the `--help` hides; `authoring/validation.md` §pre-completion checklist.

**Why**: `compare-json` validates an alias that is already recorded but never reports a *missing* one, so nothing else will.
A missing alias is a functional gap: the user cannot discover the short form exists.
A global alias table fails the same way in reverse: it credits a short form to every page, so the menu offers `auth status -t` for `--template` while the CLI gives `-t` to `--show-token` there.

**Evidence**: uv 0.13.0 hid 58 option aliases from `--help` while its own reference listed and accepted every one — `--config-settings`, `--compile`, `--force-reinstall`, `--trusted-host`, `--no-cache-dir`, `-t` on `auth login --token`, and the pip-compat `--constraint` / `--requirement`.
A prior audit of the same tool passed every gate with all 58 missing, because the rule and the checklist were both scoped to command-level aliases.
The same invocation probe deleted 5 stale command aliases (`i`, `rm`) that the CLI answered with `unrecognized subcommand`.
gh 2.102.0 supplied the per-page case: `-t` is `--show-token`'s short form on `gh auth status` but `--template`'s on almost every other page, and `gh auth status --jq` carries no `-q` at all — the previous gh manifest had merged both into one table and shipped the two wrong rows.

---

<a id="d9"></a>

## Read `--help` by section (D9)

**Decision**: decide what a help section is by its name.
A section whose name ends in `COMMANDS` is the commands section; `HELP TOPICS` is documentation; option descriptions and trailing prose are neither.

**Rule lives in**: `authoring/collecting-info.md`.

**Why**: scraping the wrong section invents commands that do not exist — `gh mintty` comes from a trailing `NOTE`, `gh api`'s `--hostname` from a stray line.
A blacklist of section names is worse than the rule: the word `gh` appears inside an `EXAMPLES` section.

---

<a id="option-traps"></a>

## Option lines have three silent-corruption traps

**Decision**: take an option's description from the text *after* the flag and its placeholder, and anchor the flag at the start of the line.

**Rule lives in**: `authoring/collecting-info.md`.

**Why**: in `--file-type string Set file type…`, `string` is a placeholder, so a faithful transcription writes it into the tip; in ` -a, --append Append files…`, the comma belongs to the short form, so a parser that treats it as a separator splits one option into two.
A third trap: the value name a framework prints into the flag head (`--value --field`, `-f, --force --hostname`) is not a flag of that option — drop it from the flag list, and decide value-vs-boolean by invocation.
All three produce a manifest that passes every gate and is wrong.

---

<a id="d10"></a>

## Platform-specific topics stay, marked (D10)

**Decision**: keep a documented command or option that is unusable on the current platform, and mark it `(Windows only)` / `(macOS only)`.

**Rule lives in**: `authoring/manifest.md` §`tip` / `usage` / `example` format.

**Why**: removing it loses `gh help mintty`-style discoverability; the marker makes the limitation visible before the user tries.

---

<a id="d11"></a>

## Paths are platform-neutral by default (D11)

**Decision**: `grep -rn 'C:\\Users\|/Users/\|%[A-Za-z]\+%' completions/<cmd>/` must return nothing.
Prefer a neutral form (`~/.gnupg/pubring.kbx`, `/home/<user>/`); show **both** platform forms only when the tool documents different defaults per platform and they are not interchangeable.

**Rule lives in**: `authoring/validation.md` §Portability audit.

**Why**: a default that varies per machine leaks the author's machine and is wrong for everyone else.
A per-platform pair is a fact about the tool; one machine's path is an artefact.

---

<a id="d15"></a>

## 404 does not mean "cannot be installed" (D15)

**Decision**: before recording a tool as skipped, find its real package name.
Many ship as scoped packages: `rspack` → `@rspack/cli`, `rsbuild` → `@rsbuild/core`, `ionic` → `@ionic/cli`, `rsdoctor` → `@rsdoctor/cli` (not `@rsdoctor/core`, which is a library with no bin).
Verify with `npm view <pkg> version` and `npm view <pkg> bin`.

**Rule lives in**: `authoring/collecting-info.md` §Alternative patterns.

**Why**: a name that 404s on the registry reads as "unavailable" and silently shrinks the completion set.

---

<a id="d5"></a>

## Upstream is authoritative; a locally missing command is not a deletion reason (D5)

**Decision**: when the local binary and `meta.url`'s upstream disagree, trust the upstream docs /
command list. Delete only when upstream has removed it, or the CLI rejects it locally **and**
upstream has no such command.
Documentation topics and shell-library entry points are never encoded.
"The CLI rejects it" is established by *invocation*, never by reading: run the flag with no value and read the error text — `unknown argument '--x'` / `unexpected argument '--x' found` means the CLI refuses it, `a value is required for '--x <X>'` means it still accepts it and was only hidden from `--help`.
Absence from `--help` is not evidence of removal.

**Rule lives in**: `authoring/maintenance.md`.

**Evidence**: both directions occur.
`format-rev` / `history` landed upstream in 2026-05 while the local 2.53.0 had neither — deleting them would have been wrong.
`survey` does not exist upstream at all — keeping it would have been wrong.
The `--help`-silent-but-accepted half is equally real and easier to mishandle: `uv` 0.12.21 hides `--from` and `--constraint` while accepting both, and the inverse is how real deletions happen — five ruff-era flags in `uv` 0.12.21's `check` (`--all`, `--diff`, `--ignore`, `--select`, `--watch`) were present in the manifest, absent from the current help, and all five answered `unknown argument`, so they went.

---

<a id="d31"></a>

## An unverified fallback is dead code (D31)

**Decision**: a hook reads one shape of a query and stops.
A fallback whose only stated reason is "the first read might fail" is dead code — no reachable state gets to it:

1. **The structured path succeeds** — the handler returns at once, the fallback never runs.
2. **It returns a valid but empty result** — the fallback does run, but the CLI is already saying "no data", so the second read is a duplicate subprocess whose own result is almost certainly empty too.
3. **It returns `nil`** — the command failed (no auth, no such repository, a build without the argument), and the plaintext path fails identically.

A fallback is justified only by *evidence* that a specific CLI cannot serve the first shape, and that evidence is an invocation — the same footing as the deletion test in D5.
A retry between two **forms of the same query** (`copilot plugins list` → `copilot plugin list`) is a different thing and is allowed; §10.1 of `design/hooks.md` covers its cost, because the second command must run even when the first succeeds.

**Rule lives in**: `design/hooks.md` §9 Style Guide, "One shape per producer".

**Why**: the prohibition was already written, yet violations shipped in the repo and none of the three gates — `compare-json`, `validate-completion`, `check-hook-targets` — can see them, because it is an internal property of one function.
A prohibition that keeps being violated is a suggestion, not a rule; stating the reachable states is what makes it checkable by inspection.

**Overturn if**: a version is documented as accepting the flag but returning a non-zero exit for a valid query.
That is the one state where a fallback earns its keep, and it would have to be shown by invocation — assuming it is not evidence.

---

<a id="d32"></a>

## Trailing punctuation is not a rule (D32)

**Decision**: whether a `tip` line ends in terminal punctuation is the author's choice.
It was written as a mandatory rule, measured against the repo, and withdrawn.

**Rule lives in**: `AGENTS.md` §Format judgment calls, where it is now stated as an explicit non-rule.
The text-format guidance itself is in `authoring/manifest.md`; the pre-completion checklist item that enforced it is removed.

**Evidence**: the repo holds two conventions at once, and they divide by completion rather than by line — some completions end every tip with terminal punctuation, others end with nothing.
So there was no single practice to enforce, only one side to prefer over the other, which is a taste call dressed as a standard.
The counts behind that observation were taken once and drift as completions land, so they were dropped rather than pinned; the split is what mattered, and it does not depend on any count.

**Why it was withdrawn**: `tip` is display text under `[Description]`.
The engine never parses it and nothing downstream branches on a period, so a rule here has no enforcement point and no user-visible effect.
Every other checklist item guards a defect the engine will mis-handle — `next: []` on a command, a missing `usage` on an aliased item, a duplicate `name`, a `U:`-prefixed line sitting in `tip` instead of `usage`.
This one guarded only taste, and its cost was pure editing: nothing else about a completion changes when a period is added or removed.
It also fought its own source of truth — clap omits the period in most descriptions, so the rule made faithful transcription the exception and required an edit per line.
Finally, the completions this directory names as style references are all no-period, so the rule told an author to follow `git` and then to write something `git` does not do.

**What stayed**: the corrected `uv` lines were kept, because that change was never really about the rule.
It closed a real en/zh disagreement — the English line ended at `` `--refresh` `` while the Chinese counterpart ended the same sentence in `。
`, so the two languages rendered the same description differently.
The scoped enumeration convention also survives, since `Possible values:` / `可能值:` is one named tip shape rather than a general mandate.

**Overturn if**: something starts parsing `tip` — a menu feature that groups or sorts on it, a filter that matches it, a diff that treats punctuation as content.
Then the cost stops being nil and the argument reopens.
Until then a rule with no enforcement point is a tax levied on every future completion for nothing.

---

<a id="d17"></a>

## The directory name is the command the user types (D17)

**Decision**: name a completion directory after the command the user actually types, and add `alias` only when upstream officially recognises more than one name.

**Rule lives in**: `authoring/manifest.md` §`config.json`.

**Why**: the directory list is read by users, so it must match their input.
`hx` has no `alias` — `helix` is only the product name and no platform installs a `helix` command, so an alias would invent a trigger and could hijack a user's own command.
`python3` does have one: PEP 394 makes it canonical on POSIX while the Windows docs recommend `python`.
When only one name is officially valid, omit `alias` and let the user configure their own triggers after install.

**Overturn if**: `python4` appears — re-evaluate rather than pre-emptively adding a directory per version, which recreates the pressure to keep one directory per release.

---

<a id="d21"></a>

## `@` names the source, never the platform (D21)

**Decision**: the part after `@` names the implementation's source, following the source's own spelling and case (`@uutils`, `@GNU`, `@BSD`), never the platform.
The part before `@` matches the command name character for character.
Once a command has variants, **every** variant carries its suffix — there is no bare "default", because a bare name hides which implementation it documents and every default is somebody's subjective choice.
A user installs exactly the variant matching their system, so same-word collisions are misuse, not a case to resolve.

**Rule lives in**: `authoring/manifest.md` §`config.json`.

**Why**: a completion describes an *implementation*, and the platform it runs on is an unstable axis — uutils itself runs everywhere, which is why the existing split is `@uutils` and not `@Linux`.
Keeping the suffix single-valued also removes the need for a double suffix.
The case follows the source project's own spelling: uutils is lowercase, GNU and BSD are uppercase.
A directory containing `@` must declare `alias`, because triggers are first-come-first-served and nobody types `AAA@author`.

---

<a id="d16"></a>

## Global option is a sharing mechanism, not a validity claim (D16)

**Decision**: a flag shared verbatim by many subcommands belongs in `global_option` even when the root itself rejects it.
Keep it on a subcommand's own `option` when only a few subcommands take it, or when the entries differ per subcommand.

**Rule lives in**: `authoring/collecting-info.md`; `design/completion.md` §`option` vs `global_option`.

**Why**: duplicating the entry across N subcommands costs N copies to write and N edits per wording change; leaving it in `global_option` costs the user one `unexpected argument` on the commands that reject it, which the CLI explains immediately.
The menu entry is not a claim that the flag is valid — the CLI is always the validator.

**Evidence**: most of cargo's subcommands accept `--manifest-path`, but `cargo --manifest-path` errors.
`gitk` / `gitweb` / `gui` cannot run under a Homebrew build but ship separately on Debian/Fedora/Arch, and `lfs` / `scalar` / `svn` follow the same shape.
Second datum: `hf --token` is listed verbatim on 133 pages of `hf` 2.2.0 and rejected on the rest (`hf version --token` errors), and it still belongs in `global_option`.

**Note**: a contradicting third row survived in a staging copy of `design/completion.md` for weeks, which sent the same "misplaced flag" proposal back for review twice.
The cost trade-off is stated in `design/completion.md` precisely so it cannot be re-derived from a stale copy.

---

<a id="d23"></a>

## Fill hook gaps while you still have the context (D23)

**Decision**: when a review has already produced the full command tree and its help, do not fix only the bug and leave the hook gaps for later.
Walk every command path, extract the positional placeholders from each `usage`, and check the difference against the existing `psc.on` targets.
Three slot classes explicitly get no hook: a name the user invents (`label create <name>`), a value too thin to be worth a round trip (`ssh-key delete <id>`), and a slot that does not take that value at all.

**Rule lives in**: `design/hooks.md` §9.

**Why**: context is not always available.
A review that has the tree in hand is the cheapest possible moment to find the gaps, and the placeholder inventory is mechanical.

**Evidence**: a placeholders-only first pass nearly attached a repository name to `repo deploy-key add`, whose slot takes a key file.
The classification is a screen, not a verdict — the command's own `usage` decides.

---

<a id="d24"></a>

## A forwarding command's subcommand table is the union of its implementations (D24)

**Decision**: when `<cmd>` only forwards to a provider (`podman compose`'s man page says the commands and flags are handed straight to the compose provider), the subcommand table is the **union** of all known implementations, not a snapshot of one.

**Rule lives in**: `design/hooks.md` §9.

**Why**: the manifest documents the command as the user experiences it, and different installs provide different subcommands.
`podman-compose` has `inspect` / `list`; `docker-compose` does not.

**Verification**: a forwarding command often answers an unknown command with the top-level usage and rc 0 or 1, which is indistinguishable from a real command missing from `--help`.
Set a fake control command and compare.
Write the wrapper's own tip to say the subcommands belong to the provider.

**Order of collection**: run what runs locally → read the source's command registration for what does not → official docs last, because docs lag.

---

<a id="d18"></a>

## Hooks do not offer file paths as candidates; probe tools are tiered (D18)

**Decision**: no hook offers a file path as a completion candidate.
The rule is about the *offering*, not the API — `psc.glob` (with or without a wildcard), a `psc.ls` of the current directory, and a `psc.run` of `ls` all count the same.
There are two exceptions and they must not be merged, because they bound the set in different currencies.
The first is a known directory whose *names* the CLI cannot enumerate itself, surfaced as `entry.name` rather than `entry.path` (`psc.ls("themes")` for `hugo --theme`) — bounded by a directory that is fixed and ships with the tool.
The second is a **CLI-filtered subset**: the hook runs a command whose own answer *is* the candidate set (`git status --porcelain` for modified files, `git ls-files` for tracked files), which is bounded by what the user did and stays small in a repository of any size.
It is legal only when the answer also carries state native completion cannot reach — a status code, not the bare path.

**Rule lives in**: `AGENTS.md` `R-10`.
The mechanism for telling the two exceptions apart is in `authoring/hooks.md`; the probe-tool tiering stays here: run what runs, read source for what does not, docs last.

**Why**: native path completion works inside the current directory and once the user has typed a prefix, so a hook adds nothing the shell cannot already give it — and a hook's file list is unbounded by construction, growing with the repository.
A criterion that carves out an exception answers the *kind* of file and never bounds the *count*, so the exception kept needing to be narrowed until it was no longer a standard at all.
A ban cannot be reinterpreted, which is what this rule needs.
The CLI-filtered case does not reintroduce that problem: its bound is not a kind but the user's own actions, so the count stays put however large the tree.
Answering only the count half of it is what keeps the two exceptions from eating each other — a set that is filtered but returns the whole repo is exactly what the ban was written for, and it looks identical to the legal case until someone runs the query.

**Evidence**: native completion reaches every one of those files once the user has typed a prefix, and the user normally already knows where their own config lives.
The only candidate with genuine discovery value was learning that a config has an alternative spelling (`biome.json` or `biome.jsonc`), which is a convenience rather than a need.
`buf`'s `**/*.proto` was injected into 17 slots, several of which (`--path`, `--exclude-path`, `--against`) want directory paths rather than `.proto` files.

**Cost**: `act`'s `.env`/`.secrets`/`.vars`/`.input`, `buf`'s `buf.yaml`/`buf.work.yaml`/ `buf.gen.yaml`/`{.netrc,_netrc}`/`**/*.proto`/`**/*.wasm`, `fastfetch`'s `fastfetch.{json,toml}` and `hugo`'s config globs are removed.
`hugo`'s `psc.ls("themes")` survives, because it surfaces names rather than paths.

**Overturn if**: a case arrives where the CLI takes a path, the file is a named artifact whose spelling the user cannot guess, and native completion demonstrably cannot help.
That criterion governs the *name* exception only; the CLI-filtered one is already licensed by `R-10` and does not need it.
What would reopen the CLI-filtered case is a set that is filtered in form but still grows with the repository — a status query that recurses the whole tree returns an answer that looks bounded and is not, and the first question in `authoring/hooks.md` is what tells them apart.

---

<a id="d19"></a>

## A Windows-only element needs a platform guard (D19)

**Decision**: prefer a portable path first, and put any Windows-only element — environment variable, program invocation, or platform-only data — behind `if psc.platform == "windows"`, with a non-empty check where the value can be empty.
A guarded branch is then verified on that platform before the hook is called done — under WSL2, by proposing the one interop run to the operator and executing it on their word.

**Rule lives in**: `design/hooks.md`, beside `psc.platform`; `AGENTS.md` `R-13`.

**Evidence**: `psc.platform` is in the hook prelude, and five hooks already branch on it — `nssm`, `volta`, `scoop`, `scoop-install`, `scoop-update`.
Three of those (`nssm`, `scoop`, `scoop-install`) guard the whole hook with an early `return`, so everything below is Windows-only by construction.
No hook in the repo invokes a Windows-only binary unguarded.

**Why**: `APPDATA` is always empty on Linux, and `psc.path("")` degrades to a path relative to the current directory — so the lookup silently succeeds somewhere wrong.
`HOME or USERPROFILE or ""` is safe on its own; the dangerous shape is narrower, a Windows-only variable as the first link of an `or ""` chain.
A program call fails the same way, only louder: `powershell.exe` has no Linux equivalent, so an unguarded call errors instead of silently succeeding somewhere wrong.
Either way the defect is the missing guard, and the guard is already expressible.

**Why it was narrowed**: the rule was previously written as an absolute ban — "`hooks.lua` invokes no Windows-only program".
It forbade something the prelude exists to express, and it had no case in the repo to point at: enforced, it would have disqualified `nssm` itself.

**Verification is the other half**: a guard decides *where* a branch runs, not whether it works there, and nothing in the toolchain executes it — `check-hook-targets` resolves the target, `luac -p` compiles the file.
WSL2 makes the Windows side reachable for exactly this, and the proposal has to come from the agent rather than from the operator noticing the host; the command itself still waits for authorization (`R-26`).
rsync 3.5.1's `--address` producer is the case: its first character class dropped every zone-suffixed IPv6 line (`fe80::…%18`) and reported success, because `ip`'s output has no zone while `Get-NetIPAddress` always does on link-local.
The zone is also the part that must stay — rsync hands `--address` to `getaddrinfo()`, which is what accepts it — and only the interop run made that visible.

**Overturn if**: the guard cannot prevent cross-platform failure — for instance hooks are evaluated on every platform regardless of `psc.platform`.
Then the call itself is unsafe and the ban returns.

---

<a id="gui-probe"></a>

## Platform guards and probe discipline for GUI/TUI tools

**Decision**: a GUI or TUI tool is only ever read with `--help`, never invoked flag by flag, and no "accepted / rejected" conclusion is drawn from it.

**Rule lives in**: `AGENTS.md` `R-02`; `authoring/collecting-info.md`.
The reason is here.

**Why**: `code <flag>` opens a window per invocation and was enough to lock the operator's machine.
A GUI tool's exit code and output say nothing about whether a flag is valid.

---

<a id="d6"></a>

## The platform checklist has one home (D6)

**Decision**: the per-review platform checklist lives in `authoring/validation.md` §Portability audit as its own section; no second copy is maintained anywhere.

**Why**: a checklist that exists in two places is a checklist that will be updated in one of them.
This entry exists so the identifier resolves.

---

<a id="d26"></a>

## Data-writing scripts must resolve aliases too (D26)

**Decision**: any script that writes manifest data must index an option by both its `name` and its `alias` entries, the same way the hook-target checker does.

**Enforced by**: `scripts/check-hook-targets.ps1`.
Deliberately **not** restated in `AGENTS.md` — a rule the tooling already guarantees does not need prose, and prose about it would suggest an exception that does not exist.

**Why**: a script that matched only `name` reported working manifest entries as missing, which nearly deleted correct data.

---

<a id="d27"></a>

## Grouping psc.on specs (D27)

**Decision**: one `psc.on` per producer — one handler, one source, one kind — and several targets that share that handler go into one array spec.
Split registrations only when the trigger conditions differ, with a one-line comment saying why.
A single target is not wrapped in an array, and specs are not regrouped by command — the API takes a command and an option, not a command-group.

Two producers that serve the same slots are two registrations, never one handler calling two helpers; order is registration order, so an order-sensitive pair is simply declared in that order.
A combined handler is reserved for interleaving (`commit, branch, commit`) or a producer that consumes another's output.
Identical target lists are shared as one local table passed to each `psc.on`, not copied per producer.

**Rule lives in**: `design/hooks.md` §9; the procedure is `authoring/hooks.md` §One producer per registration.

**Why**: merging is exactly the edit that can silently drop a target, which is why the grouping was settled by counting the checker's targets before and after rather than by preference.
A single target stays unwrapped, because `psc.on` takes `psc_on_spec | psc_on_spec[]` and wrapping one target implies a group that is not there.
Atomicity is what makes a handler checkable: its query can be probed on its own (`R-17`), and the slot inventory can name the producer behind a row.
A combined handler hides both, and it does not even buy ordering — the engine already runs matching handlers in script order.

**Evidence**: jj 0.46.0's first pass used one handler that called the common revsets, the dynamic revset log, and the bookmark listing at the same 23 locations.
Splitting it surfaced that the "common" values were constants with invalid quoted forms, and that bookmarks were a different source with a different tip.
The engine order is structural, not incidental: `bindings.rs` calls a matching handler as its `psc.on` executes, and `runner.rs` keeps insertion order among dynamic items before moving them ahead of static ones.
What registration order cannot control is the final menu order — history ranking reorders the merged list — so a display priority is not a reason to combine handlers.

**Overturn if**: `psc.on` gains several handlers per location or an explicit ordering key — then one registration can express the pair and the atomicity cost disappears.

---

<a id="d28"></a>

## A checker's own coverage must be measured (D28)

**Decision**: when a checker gains a capability, quantify how much more it now looks at before looking at what it reports.

**Enforced by**: `scripts/check-hook-targets.ps1` (header comment).
Deliberately not prose in `AGENTS.md` — this is about how to build a checker, not how to write a manifest.

**Evidence**: extracting only *inner* groups from a `psc.on` spec left **238 targets across 53 files completely unchecked** while the checker reported success.
The target count went from 1159 to 1397 once it was fixed.
A count of failures alone would never have shown the blind spot, because an unchecked target cannot fail.

---

<a id="d33"></a>

## Complementary options are not aliases (D33)

**Decision**: a boolean the CLI accepts in negated form is two **complementary options** (enable/disable), not an alias and not a single entry.
They are modeled as **separate entries**, each with its own `name` and `tip`, and an accepted negative form is a menu candidate like any other spelling.
The `alias` field is reserved for **true synonyms** — the same option under different names (e.g. `-a` for `--all`, `-o` for `--only`, `--colour` for `--color`).

**Rule lives in**: `AGENTS.md` `R-18`.

**Why**: a complementary pair where the CLI writes `--foo, --no-foo` means both forms are accepted by the parser, but they **set opposite values** — they are not interchangeable.
Collapsing them into one entry with `alias: ["--no-foo"]` loses the semantic distinction: a user who types `--no-foo` expects to disable the feature, not to enable it under a longer name.
The same applies to other negation patterns: `--[no-]sparse`, `--[no-]dangling`, `--gpg-sign, --no-gpg-sign`.

True synonyms are options that do the exact same thing under different names — short/long forms (`-a` / `--all`), regional spelling variants (`--color` / `--colour`), or historical aliases (`-C` / `--reuse-message`).
They belong in `alias` because the user expects either spelling to produce identical behavior.

**Scope**: the rule does not depend on how the negation is printed — a `--[no-]x` line, an explicit `--no-x` term, or a form only invocation reveals all produce two entries.
Which spellings are actually accepted is settled by that notation or by invocation, never by prefixing `--no-`: git 2.56.0 accepted 1 248 of the probed negative forms and refused 437.
curl 8.23.0 shows the other distribution: its `--no-` switch is generic across booleans, and probing 121 booleans accepted 100 while refusing 21 with `the given option cannot be reversed with a --no- prefix`, so even a tool-wide rule is a per-option probe.

**Evidence**: during the `git` completion audit (against git 2.56.0), multiple instances of complementary options being incorrectly modeled as aliases were found and corrected — `--keep-cr`/`--no-keep-cr`, `--rerere-autoupdate`/`--no-rerere-autoupdate`, `--verify`/`--no-verify`, `--sparse`/`--no-sparse`, `--include-edges`/`--no-include-edges`, `--overwrite-ignore`/`--no-overwrite-ignore`, `--recurse-submodules`/`--no-recurse-submodules`, `--gpg-sign`/`--no-gpg-sign`.
The validation scripts do not catch this because both forms are valid JSON and both pass `compare-json`; the defect is semantic, not structural.

Conversely, `--color`/`--colour` are true synonyms (regional spelling variants) and should be modeled as aliases.

**Overturn if**: a tool's own `--help` leads with `--[no-]` *and* both directions are in common use — then a single `[no-]` line is more honest to the CLI.
Until then, the two-entry form is the default because it is both the existing majority and the clearest at completion time.

---

<a id="d34"></a>

## Tips are multi-line arrays; split multi-sentence content (D34)

**Decision**: a `tip` is an array of lines, and each element renders as one visible line in the menu.
When the source `--help` contains multiple sentences, split them at sentence boundaries so each line is a self-contained thought.
Cramming an entire paragraph into one array element defeats the purpose of the array and produces an unreadable wall of text in the completion menu.

**Rule lives in**: `AGENTS.md` `R-19`.

**Why**: the completion menu displays `tip` lines as separate lines under `[Description]`.
A single long line is visually indistinguishable from a paragraph, while multiple short lines are scannable.
The array format exists specifically to support this; not using it is like writing a novel as one sentence.

**Evidence**: during the `git` completion audit (against git 2.56.0), many options had single-line tips containing multiple sentences.
After applying the rule, the tips became more readable and the JSON structure better reflected the logical structure of the content.

**Overturn if**: the menu implementation changes to support automatic line wrapping or paragraph formatting, making the array format unnecessary.
Until then, manual splitting is the only way to control how text appears in the menu.

---

<a id="d35"></a>

## No order is prescribed for enumerations (D35)

**Decision**: value enumerations carry no order requirement.
`next: [...]` is reordered by `sort-json.ps1` on every run whatever an author writes, and the trailing `Possible values:` tip line is display text — CLI order, alphabetical order, or anything else.
The two are independent; neither has to match the other.

**Rule lives in**: `AGENTS.md` `R-08`.

**Why**: `scripts/sort-json.ps1` reorders every named array on every run (case-insensitive, by name), so authoring order in `next` is moot by construction.
The alphabetical mandate this entry used to state was extended to the tip line by convention and had no enforcement point — the same reasoning that withdrew the trailing-punctuation rule in D32.
A mandate about display order that nothing checks is a tax on the next reviewer, who has to decide whether the stale lines in front of them are a defect or the rule.

**Evidence**: bat 0.26.1 declares `--wrap` values as `auto, never, character` (help text and the clap `value_parser` agree), yet the manifest holds `auto, character, never` — the script's doing, on every completion carrying an enumeration.
uv 0.13.0's manifest held 126 `Possible values:` tip lines in CLI order while the paired `next` arrays were alphabetical; a review re-sorted all 126 as rule violations, and the operator then ruled the line's order free — candidate order is the engine's concern, and the tip line's order is nobody's.

**Overturn if**: something starts parsing the tip line — a menu feature that groups or filters on it, a diff that treats its order as content.
Until then the order is the author's choice.

---

<a id="d36"></a>

## A shadow with a differing tip is kept, silently (D36)

**Decision**: a subcommand option sharing a spelling with a `global_option` entry stays local when its content differs (a context-specific tip); only a fully identical copy is removed.
The gates fail the identical copy and say nothing about the shadow — no report, no listing.

**Rule lives in**: `authoring/manifest.md` §Duplicates (identical vs different); `AGENTS.md` `R-11` (differing entries go on the subcommand).

**Why**: an identical copy gives the user nothing the global entry does not already say, so it is noise by construction.
A differing tip documents what the flag means in that context, which the global tip understates — removing it loses information the CLI itself provides.

**Evidence**: `brew install --debug` ("If brewing fails, open an interactive debugging session inside the temporary build directory") vs global `--debug` ("Display any debugging information"); `brew tests --debug` ("Enable debugging using ruby/debug, or surface the standard odebug output"); `brew desc -d` / `--description` vs global `-d` / `--debug`.
All three read from the CLI's own `--help` (against Homebrew 7.0.9).

**Overturn if**: a shadowing tip proves wrong against the CLI — then the tip is corrected, not the placement.

---

<a id="d37"></a>

## Working files live in `WIP/`, deleted on confirmation (D37)
**Decision**: every artifact a task generates — analysis scripts, `--help` dumps, parsed tables, diff plans, batch logs, translation dictionaries — goes in `WIP/<tool>/`, one directory per completion, and stays there until the operator confirms deletion.
The author reports the directory at hand-off instead of tidying it away.

**Rule lives in**: `AGENTS.md` `R-20`; the mechanism is `authoring/working-files.md`.

**Why**: the operator reviews *after* the gates, and a review that finds a wrong value needs the dumps and the plan to fix it fast — the material is the cheapest rework path that exists, and "the audit is done" is not the moment it stops being needed.
A shared system temp directory fails the same task in the other direction: there is no per-task isolation, so two completions written concurrently overwrite each other's scripts, and the collision surfaces only when one parses the other's data.

**Evidence**: the previous guidance said the opposite in two places — the large-audit step read "Delete the scratch directory when the audit is done", and the collection-completeness section read "delete it before you commit".
Both were written for tree hygiene and neither anticipated the review window that follows a clean gate run.
The recorded failure behind the retention half: an agent declared a completion finished and deleted the scripts it had generated; the author then found defects, and the analysis had to be regenerated from zero because the probes, the parsed tables and the diff plan were gone.
The collision half is the operator's own report of concurrent completions sharing one temp directory; it is recorded as reported, because a collision leaves nothing in the tree to point at afterwards.

**Rejected alternatives**: (a) delete automatically once the gates run clean — rejected, it removes the rework material before anyone has looked at the manifest; (b) keep using a system temp directory with a per-task subdirectory — rejected, the isolation buys back the collision but the material is invisible to whoever reviews the work and belongs to no cleanup decision; (c) name the directory `review/`, the spelling the two old references used — rejected, that directory also holds the audit trackers at its top level, and its name describes the activity rather than the material; (d) name it `temp/` — rejected, `scripts/check-doc-links.ps1` excludes `temp/` from doc-link checks by design (its header names `temp/` as engine runtime scratch, not repo files), so a reference into it would go unchecked; (e) add `WIP/` to `.gitignore` so the tree stays clean — rejected, an ignored directory drops out of `git status`, which is the one place the operator sees which tasks still owe a cleanup, and the record itself is worth keeping visible; staging for a comparison stays allowed, a commit and a push are closed to it.

**Overturn if**: nothing in a `WIP/<tool>/` directory is ever read a second time across many completions — then retention is pure disk cost, and the answer is archiving on confirmation, not this rule.
The naming half is overturned by any tooling that starts resolving `WIP/` paths without reading the directory first.

<a id="d38"></a>

## Running a script is the dangerous step (D38)

**Decision**: writing a script is cheap, running it is not — a script runs with the author's full filesystem access.
Every script is read in full before it runs, and nothing that deletes outside `WIP/<tool>/` runs without explicit operator confirmation.
Ordinary writes need no confirmation (git restores any overwritten file); deletion does, because once the tree — or `.git` itself — is gone there is nothing to check out from, and nothing ever writes into `.git/` directly.

**Rule lives in**: `authoring/working-files.md` §Running a script is the dangerous step.

**Why**: a wrong path in a delete call destroys what no gate can rebuild.
Deletion can hide in a helper, an import-time side effect, or a default argument — skimming the changed lines is not reviewing the script.

**Evidence**: an agent-written Python script, run without a full read, deleted this entire project — working tree and version control alike (`.git` included).
There was nothing to check out, no history to consult, no reflog to mine: recovery meant reconstructing from memory and fragments, against extreme resistance, and it never truly completed.
Many ready-to-release completion definitions were permanently lost.
That was the first tree-wide wipe; a second one, with a different mechanism (a probe transitively triggering deletion in the tool under test), is recorded in [`D39`](#d39).

**Rejected alternatives**: (a) run first, review on failure — rejected, failure here means data loss, and the failure mode leaves no output to review; (b) only review scripts that obviously delete — rejected, the delete hid behind an unreviewed path expression, which is exactly what "obviously" misses; (c) rely on git to recover — rejected, the incident deleted `.git` itself along with the tree, so there was nothing to revert to and ready-to-release work was permanently lost; (d) forbid agents from running scripts at all — rejected, collection and validation cannot be done without running them; the answer is review-before-run, not never-run.

**Overturn if**: script execution moves into a sandbox that cannot touch the tree outside `WIP/<tool>/` — then the read-before-run rule relaxes to sandbox hygiene, but the confirmation rule for deletions stays until the sandbox itself is the thing being tested.

---

<a id="opt-chains"></a>

## Option-dispatched chains are recorded nested, surfaced by hook

**Decision**: when a CLI dispatches subcommands through an option value (`fresh --cmd daemon list`), the chain is modelled under the option's `next` (root `next` stays empty — the bare form is not a command), deeper levels are recorded as nested `next` / `option` even though static navigation cannot reach them, and a hook surfaces them only if the depth is worth it.

**Rule lives in**: `authoring/collecting-info.md` §Option-dispatched command chains.
Deliberately **not** an `R-xx` rule — there is no must here, only procedure and a scope decision that belongs to the operator.

**Why**: the engine resets to the nearest command context once an option value is consumed (`completion.rs`), so `--cmd <TAB>` completes while `--cmd daemon <TAB>` statically offers nothing.
Recording the tree anyway keeps one source of truth a hook can mount; inventing root-level subcommands instead would complete invocations the CLI rejects.

**Evidence**: fresh 0.5.3 takes the rest of the line as one `--cmd` chain (repeating `--cmd` is rejected as an unknown command) and `fresh daemon list` opens a file, so the ten top-level words are values, not subcommands.

**Overturn if**: the engine learns to navigate option-value chains — then the nesting becomes reachable, the hook is deleted, and this entry goes with it.

---

<a id="build-sets"></a>

## Build-dependent sets are runtime state

**Decision**: `R-16`'s "known at authoring time" test is judged per machine, not per author.
A set that varies by build or installation — drivers, devices, installed components — belongs in a hook even when the author can enumerate it here, because a manifest frozen from one build is wrong on the next.

**Rule lives in**: `AGENTS.md` `R-16` (the per-machine sentence).

**Why**: the alternative is a manifest that is exactly right on the author's machine and silently wrong everywhere else, with no gate able to tell — the same failure shape `R-16` already prohibits for dynamic tips, moved one layer out.
Size is still not the test: a hundred decoders go in a hook for the same reason ten drivers do.

**Evidence**: mpv 0.41.0's `--vo=help` lists eleven drivers on this machine (`gpu-next`, `vdpau`, `xv`, `wlshm` …); other builds offer `d3d11`, `cocoa`, or fewer.
`--audio-device=help` answers per sound server.

**Overturn if**: completions gain per-build manifest variants — then each variant freezes its own correct set and the hook is unnecessary.

---

<a id="join-window"></a>

## Join tests on wrapped lines are windowed to the junction

**Decision**: any accept/reject test that decides how to rejoin a wrapped help line inspects only the junction (tens of characters around the break), never the whole accumulated string.

**Rule lives in**: `authoring/collecting-info.md` §Joining wrapped help lines.
No `R-xx` rule — harvest scripts are pipeline artifacts whose internals prose cannot enforce; this entry exists so the next author does not re-derive the failure.

**Why**: the accumulated string already contains the option head, whose spelling matches every token test and flips the verdict.
Two successive windows failed the same way on `[default: no-` + `revisions]`: the full-string test matched the head `/ --no-revisions` and stripped a hyphen that belongs to the value, and so did the trailing-80-characters retry — the head was inside that window too.
Only the junction window (`out[-40:]` plus the next line) decided correctly.

**Overturn if**: harvesting stops joining text blindly (a grammar-based parser that keeps structure instead of reflowing lines) — then there is no join test left to window.

---

<a id="mount-help"></a>

## A help command mounts the table instead of duplicating it

**Decision**: when a CLI's `help` command takes the tool's own subcommands as values, the manifest models `help` as a leaf and a hook mounts the root `next` at its slot.
The list is defined once, never copied.

**Rule lives in**: `design/hooks.md` §Mounting shared values.
Not an `R-xx` rule — it is a conditional preference (three gating conditions), and the mechanism it leans on lives in design.

**Why**: `R-16` bans a *second* source of constants; mounting keeps exactly one (the manifest — tips and localizations ride along), so the letter holds while the duplication cost disappears.
The alternative — a verbatim copy under `help` — drifts on every added or removed command, in two languages, and no gate compares the two copies because both are internally consistent.
The four existing `help` tables (`gh`, `go`, `rclone`, `diny`) are all documentation topics with zero overlap against the root commands, which is precisely the case that stays static: the test is set identity, not size.

**Evidence**: dart 3.13.5 takes its own 15 commands at `dart help <command>` (`dart help bogus` is rejected); the hook is three lines plus `hooks: true`.

**Overturn if**: mounted children observably stop behaving like their static twins (navigation, repeat filtering diverge) — then the equivalence claim fails and duplication returns.
A gate that diffs duplicated tables would remove the drift half of the argument, but not the translation-doubling half.

**First observed false branch**: a wrapper CLI whose `help` slot takes the *wrapped tool's* subcommands, not its own (`x-cmd codex help` prints native codex help: `Usage: codex [OPTIONS] [PROMPT]`).
Mounting the module's own `next` there mounts the wrong table.
Verify what the slot takes — the tool's own list or the downstream tool's — before mounting; a passthrough slot stays a leaf with `help [COMMAND]` usage and no hook.

---

<a id="d39"></a>

## Probes are contained because the killer is transitive (D39)

**Decision**: collection probes run with scratch CWD, never the repo (`R-22`), and `--help`-appended probes are trusted only on framework parsers — hand-rolled dispatchers get source-first plus canary treatment (`R-23`).
Mechanism lives in `authoring/collecting-info.md` §Probe containment.

**Rule lives in**: `AGENTS.md` `R-22`, `R-23`.

**Why**: reading the harvest script before running it (D38) is necessary but not sufficient — the killer lives N hops away in the tool's own code, and no reading of the author's script inspects it.
Only end-to-end reproduction reveals such a chain, which is exactly what a pre-run read cannot do.
Containment bounds the loss when the judgment is wrong (the same probe in scratch loses scratch); shape validation catches the misjudgment on the first probe instead of the last.

**Evidence**: this is the project's second tree-wide wipe, and it differs from the first in mechanism, not in cost.
The first ([`D38`](#d38)) was a delete call inside the author's own script, run without a full read.
Here the harvest script was clean and audited (zero delete calls, all writes under `WIP/`): it ran `x-cmd gram tarm --help` → a dispatcher arm with no `-h` handling ran `find '--help'`, which printed its 45-line help to stdout with exit 0 → a `while read` loop fed those lines to `realpath`, which resolves every line against the existing parent (CWD) → `[ -d CWD ]` held → tar backup → `rm -rf CWD`, exit 0 throughout.
Four links, none owned by the author, each reasonable alone.
A non-dispatcher sibling makes the same point: brew 7.0.10's `casks` prints the catalogue and `mcp-server` starts a server on `--help`, so `brew help <cmd>` is the safe surface even though the parser is framework-built.

**Rejected alternatives**: (a) "read scripts harder" — rejected, the author's scripts were byte-clean; the defect was in the CLI under test; (b) ban live probes for hand-rolled CLIs — rejected, most such leaves print help fine (hundreds ran clean in the same session), and the ban would cost the primary evidence source for entire tool families; (c) trust the exit code — rejected, every link in the chain exited 0.

**Overturn if**: probe execution moves into a sandbox that cannot touch the tree — then the CWD law relaxes to sandbox hygiene, but the canary stays as the execution detector; or hand-rolled dispatchers stop shipping — then the parser test collapses to a sentence.

---

<a id="d43"></a>

## A help page is evidence only after its completeness is shown (D43)

**Decision**: before harvesting, check that the page lists the whole surface; when it defers to another surface or shows fewer options than the command has, fall back to the fuller source — the tool's own verbose help, the installed manual source, the documentation of the pinned release — instead of transcribing the short page.

**Rule lives in**: `authoring/collecting-info.md` §Prove the help page is complete; the completeness requirement itself is `R-24`.

**Why**: a reduced page is not a smaller truth, it is a different one: options it omits read as absent, and options it repeats read as present twice.

**Evidence**: git 2.56.0 — `git log -h` printed four options (the final manifest holds 199), `git show -h` reprinted log's block, `git diff-files -h` printed only "common diff options".
A parser tuned on such a page produced 565 false missing and 1 313 false extra spellings before the source was switched to the installed man pages.

**Overturn if**: a framework generates its short help from the same registry as its full help, so the short page provably enumerates everything — then the completeness check is cheap enough to skip for that tool.

---

<a id="d44"></a>

## Completeness needs its own measurement (D44)

**Decision**: measure option coverage as a diff between the pinned source's spellings and the manifest's `name` + `alias`; the difference must be empty, and every manifest-only spelling is settled by invocation.
The result is recorded in the task's artifacts, not inferred from a gate.

**Rule lives in**: `AGENTS.md` `R-24`; the checklist item is in `authoring/validation.md`.

**Why**: `compare-json` and `validate-completion` compare the manifest with itself.
They certify that what is written is well-formed and translated; they cannot certify that nothing is absent, which is the failure mode a sweep exists to fix.

**Evidence**: the git manifest passed all three gates with 2 113 option entries while the 2.56.0 documentation held 4 737; 101 leaf commands had no `option` array at all.
x-cmd 0.10.12's root help matched 312/312 modules while 23 modules were missing 180 options; a root-only diff would have certified it complete.

**Rejected alternative**: a CI completeness gate — CI has no source set.
Storing one duplicates the manifest almost one-to-one and drifts with it, and a count or digest proves nothing about identity.
The local measurement plus the recorded artifacts is the honest form until the manifest can carry a verifiable source digest.

**Overturn if**: completions gain a per-command source digest that CI can verify against a pinned release.

---

<a id="d45"></a>

## Rebuild from the source instead of patching the diff (D45)

**Decision**: harvest the source into a table, plan once, apply in batches to both languages, and re-run the gates; do not add the missing entries by hand on top of the existing array.

**Rule lives in**: `authoring/maintenance.md` §Scripted realignment and §Large audits.

**Why**: a partial apply leaves a manifest that is neither the old one nor the new one, and a second pass has to reconstruct which entries the first one already wrote.
Identity in this data model is the spelling, so a re-run that does not dedupe by `name`, keep existing aliases and skip alias-covered source spellings duplicates entries and splits synonyms.

**Evidence**: three passes over the git manifest produced `config`'s `--all` three times, split `refs --python` from its `--shell` / `--perl` / `--tcl` aliases, and paired `commit -n` with `--verify` instead of `--no-verify`.
The converged pipeline — dedupe, alias union, alias-covered skip, usage rebuild, collision assertion — ran clean over 118 commands and 91 parent contexts.

**Rejected alternatives**: (a) hand-add only the entries the diff lists — rejected: the diff is against one page's spelling set, and every added entry still needs a tip and a translation; (b) regenerate both languages from the source and discard the old translations — rejected: the dictionary is the expensive artifact, and a key-based merge preserves it.

**Overturn if**: the source diff becomes identity-addressed — stable IDs that survive renames and reorders — so an incremental apply no longer has to guess which existing entry a source row denotes.

---

<a id="d46"></a>

## Hook decisions are a by-product of collection (D46)

**Decision**: record every value slot and its verdict while the command is collected (`slots.json`), not in a later hooks pass; a hooks review is then a diff against `psc.on` targets.

**Rule lives in**: `authoring/collecting-info.md` §Record every value slot while you collect; the checklist is in `authoring/validation.md`; the slot rule it applies is `R-09` / `R-10` / `R-16`, and the coverage property it feeds is `R-25`.

**Why**: the slot's kind, its enumerating query and whether it deserves a hook are decided from the same page that supplies the options.
Deferring the decision forces a second full reading of every help page, and it degrades the review into "do the existing targets resolve?" — the wrong question, because it cannot see a slot nobody covers.

**Evidence**: the git sweep added 2 623 options and rebuilt 91 parent contexts; the hooks pass that followed could verify only that 82 targets resolve.
A coverage audit then required re-reading and re-probing commands whose slot data — placeholder and value-ness — was already in the rebuilt manifest.
The inventory would have made that a set difference.

**Rejected alternative**: a separate hooks audit after the manifest is complete — rejected: it re-reads every page to recover facts already collected, and it measures target resolution rather than slot coverage.

**Overturn if**: manifests carry a machine-readable slot inventory that a script can regenerate for free — then recording it by hand is redundant, and the review stays a diff either way.

---

<a id="d47"></a>

## A hook target names a slot, not a command (D47)

**Decision**: before adding a target, name the slot it fires at — an option that takes a value, or the command's first unfilled positional. A second positional, the argument of a valueless flag, and a name the user invents are not targetable; when a command-level target still serves a related flag slot, the compromise is recorded in the slot inventory.

**Rule lives in**: `design/hooks.md` §9; `authoring/hooks.md` §Slot → producer; `R-25`.

**Why**: `check-hook-targets` validates that a command or option spelling resolves in the manifest; it cannot see whether the engine has a slot to fire at. A target on a valueless flag or on a second positional resolves and never fires, and a command target on a command whose first positional is a path or a new name offers the wrong candidates.

**Evidence**: in the git 2.56.0 sweep, `branch -d` and `tag -d` are valueless flags, so their option targets could never fire; `worktree add`'s commit-ish is the second positional; `tag` creation and `tag -d` share the first positional, so the command target serves deletion and also offers existing tags while creating. The slot inventory made all three visible in one diff.

**Overturn if**: the engine can target an argument index or a named slot — then second positionals become targetable and the shared-position compromise disappears.

---

<a id="d48"></a>

## A shared constant set is mounted, not copied (D48)

**Decision**: a constant set that serves one slot lives in that slot's `next`; one that serves several lives once as a chosen node's `next` and is mounted with `psc.mount_items` at the other slots. Hardcoding the list in Lua is not an alternative — it is a second source.

**Rule lives in**: `AGENTS.md` `R-16`; the mechanism is `design/hooks.md` §Mounting shared values defined in the manifest; the procedure is `authoring/hooks.md` §Shared constant sets.

**Why**: the cost is entries × slots, not entries. Copying keeps the values visible without hooks but creates one edit per slot per language, and the copies drift silently because no gate compares them. Mounting keeps the manifest as the only source and costs one registration. The home slot already displays its own `next`, so it is excluded from the mount targets; mounting there would inject every name twice.

**Evidence**: jj 0.46.0 offered six common revsets at 90 value slots. Copying them into `next` produced 540 entries per language — 1 080 across both — for six values. The old threshold read "below a handful of entries the duplication is cheaper", which looked at the six and missed the 90; the same sentence would approve 600 values at one slot and reject six values at 90 slots, the exact inversion. The mounted form is one path plus six lines of data, and a seventh revset is one line.

**Rejected alternatives**: (a) copy into every `next` — the bloat above, and N places to update in two languages; (b) hardcode the list in Lua — smaller, but the manifest stops describing its own candidates and any tips or translations are lost; (c) keep a threshold on entry count — the wrong axis, which is how this case passed review.

**Overturn if**: the manifest gains an include or named-set mechanism a slot's `next` can reference directly — then no hook is needed, the home becomes an ordinary reference, and this entry goes with the mount.

---

<a id="d49"></a>

## Completion inserts a whole value, not a fragment (D49)

**Decision**: a slot with its own syntax is completed at **whole-value** granularity. When the reference lists a value the user can pass as the whole value, it belongs in `next`, even though the surrounding slot is a mini-language — `--cert-type DER`, `--write-out '%{http_code}'`, `-vf scale`. Fragments that would be rejected alone (`Content-Type` without `: value`) do not become candidates, and `separator` is used only when the CLI itself splits the value.

**Rule lives in**: `authoring/hooks.md` §Composite and paired values; `authoring/manifest.md` §Options that take a value.

**Why**: the engine inserts one value, so the test is whether that value is valid at the slot — not whether it contains syntax. Declaring every composite slot free text throws away exactly the names a user would otherwise type by hand, which is the job completion exists to remove; listing fragments goes the other way and inserts arguments the CLI rejects.

**Evidence**: curl 8.23.0 — `--cert-type` and `--key-type` list their types, and `--write-out`'s manual lists 53 `%{...}` variables; each is a valid whole value and is now a `next` candidate. `-H "Name: value"` and `--resolve host:port:addr` have no such list, and a bare header or host fragment is not a valid value, so those stay free text with `repeat` and a shape-only `usage`. ffmpeg's `-vf scale` is the same distinction: `scale` is a valid filter with defaults, while the arguments after `=` are not separately completable.

**Rejected alternatives**: (a) mark every composite slot `free-text` — the earlier rule, which dropped usable values; (b) list fragments — the menu inserts a bare name where a complete expression is required; (c) parse the typed prefix in a hook — the engine has no in-string completion, so it would be dead code.

**Overturn if**: the engine gains substring completion (a slot can declare a grammar and an insertion point), or the CLI exposes these expressions as structured fields instead of one string.

---

<a id="d50"></a>

## No hooks is a decision, not a default (D50)

**Decision**: every completion records the slot inventory and settles every slot, with or without `hooks.lua`. A completion that ends with no hooks still goes through the pass, and every `none` or `native` row names the sources checked — the CLI, the OS, a project file, a config/state file, or a completion protocol.

**Rule lives in**: `AGENTS.md` `R-25`; `authoring/collecting-info.md` §Record every value slot while you collect; `authoring/maintenance.md` step 5.

**Why**: `check-hook-targets` only inspects targets that exist, so a completion with no `hooks.lua` has nothing to check and the question disappears. The update workflow used to make the hook re-decision conditional on an existing hook file, and a type-based slot pass then reads “no CLI query” as “no source”.

**Evidence**: curl 8.23.0 — the first pass declared “no hooks” from the slot types; `--interface` and `--dns-interface` are machine-local interface names the OS can enumerate, and they were missed until a review asked. The inventory held 91 free-text rows, two of which were names with a real source.

**Rejected alternatives**: (a) rely on `check-hook-targets` — it cannot report a missing producer; (b) ask only when the tool “looks dynamic” — that is the same type-based shortcut that failed; (c) require a `hooks.lua` for every completion — a producer with nothing to read would be noise.

**Overturn if**: a checker can enumerate candidate sources per slot, or the engine reports slots that no producer serves; then the manual decision becomes a verification.

---

<a id="d51"></a>

## A command with a possible side effect is authorized before it runs (D51)

**Decision**: before running a command that can delete, move, overwrite or truncate files, change permissions, install or update, or change repository, service or network state — on any platform — state the exact command, what it changes, and how that is undone, then wait for authorization. Writes confined to `WIP/<tool>/` or the completion being edited are the task itself; deletion is never exempt. Cross-platform commands (WSL interop, emulators, remote shells) are read-only probes, not runtime paths.

**Rule lives in**: `AGENTS.md` `R-26`; `authoring/tooling.md` §Classify a command before running it; `authoring/working-files.md` §Running a script is the dangerous step.

**Why**: a command runs with the operator's full filesystem and network access, and a chat log does not show them what is about to run. Deletion, move and overwrite are irreversible when version control is gone, and a command that looks like a query can still touch state — `winget` sources, a service, a scheduled task. The authorization step is the only review point before that happens, and it costs one message.

**Evidence**: during curl 8.23.0, `netsh.exe interface show interface`, `winget.exe --version`, `cmd.exe /c ver` and `powershell.exe -NoProfile` were run through WSL interop without prior authorization. All four were read-only and nothing changed, but the step was skipped; the `netsh.exe` output (localized Chinese, with a dashed separator line) still corrected a parser written from an English example, which is why the probe was useful, not why it was allowed to run unasked. In the same project, `Remove-Item WIP/git, WIP/jj` ran only after explicit confirmation (the correct shape), and the recorded tree-wide wipe ([`D38`](#d38)) shows what one unguarded delete can do.

**Rejected alternatives**: (a) guard only deletes — `mv`, `cp`, `truncate` and redirection change state too; (b) ask for everything — reading files and `--help` would drown the operator; (c) trust a command because it looks read-only or because it is cross-platform — the shape is not proof of the side effect; (d) ask once for all future commands — the next one may not be a query.

**Overturn if**: commands run in a sandbox that cannot write outside `WIP/` or reach the network, or the operator grants a standing authorization for a named read-only category such as `--version` and `--help`.

---

<a id="d53"></a>

## A wrapper's passthrough modules are a scope decision (D53)

**Decision**: when a wrapper's module `--help` is the wrapped tool's own page, mirroring that tool's full option set is a deliberate scope choice, not an automatic completeness requirement. Decide per module, record the decision, and keep the wrapper's native pages complete.

**Rule lives in**: `authoring/collecting-info.md` §Aggregators and wrapper tools; `AGENTS.md` `R-24`.

**Why**: the wrapper adds no new data for that module; mirroring duplicates another completion and its translations, and the wrapper's own page may not list the flags at all. The native modules — where the wrapper defines its own subcommands and options — are the ones a completeness diff can measure.

**Evidence**: x-cmd 0.10.12 — 35 of 312 modules hand `--help` to the wrapped tool (`npm`, `lua`, `cp`, `open`, …). The 23 native pages were missing 180 options; adding them brought the native diff to zero. The root list matched 312/312 throughout, which is why the module pass was needed at all.

**Rejected alternatives**: (a) mirror every passthrough module — copies dozens of tools into one completion and can never be kept in step; (b) skip every non-native page as “not our surface” — loses the wrapper's own options on pages that mix both, which is why the page is classified before the decision.

**Overturn if**: a wrapper exposes a stable machine-readable pass-through schema that can be generated once and versioned with the wrapper, or its passthrough modules become its own documented surface.

---

<a id="d54"></a>

## A suppressed flag is not a documented spelling (D54)

**Decision**: a flag the tool's own source suppresses (`help=argparse.SUPPRESS`, a development-only switch) stays out of the manifest even though the parser accepts it. An inverse the visible help names in prose (`(inverse: --allow-…)`) is documented and gets its own entry (`R-18`).

**Rule lives in**: `AGENTS.md` `R-24`; the collection mechanism is in `authoring/collecting-info.md` §Aliases the `--help` hides and §A definition line is not a synonym list.

**Why**: "the CLI accepts it" and "the CLI documents it" are different questions, and `R-24` measures the second. A suppressed flag is accepted, so invocation cannot separate it from a hidden-but-documented spelling; only the source's `help=` argument can. Including every suppressed flag would put internal diagnostics (`--debug-serialize`, `--dump-graph`) in the menu, where they compete with the flags a user is looking for.

**Evidence**: mypy 2.4.0 registers 47 invertible pairs, and four are suppressed in both directions (`--check-unreachable`, `--allow-empty-bodies`, `--no-local-partial-types`, `--fast-module-lookup`). All four were probed and accepted, and all four stayed out. The same release names 45 inverses in visible descriptions while registering them with `help=SUPPRESS`; those are documented, so every one was recorded and probed.

**Rejected alternative**: include every accepted spelling and rely on the menu filter — rejected: the menu shows all of them on every Tab press, and a name the tool hides is usually hidden because it is unstable or internal.

**Overturn if**: a tool documents a suppressed flag as user-facing (its reference or release notes) while hiding it from `--help` — then the documentation, not the `help=` argument, decides, and the flag goes in.

---

<a id="d55"></a>

## An attached value is modelled in the spelling, never in a field (D55)

**Decision**: the manifest has no per-spelling field describing how a spelling joins its value. An attached value is carried by the spelling itself: a separator the CLI requires (`=` or another) goes into `name`/`alias`, a glued-only value with a closed set may become one spelling per value, and a glued-only free-form value keeps the bare spelling with one `tip` line and no `next`. Whenever the CLI also accepts the space form, that form with `next` is the model — glue is never preferred.

**Rule lives in**: `authoring/manifest.md` §`usage` — `A value the CLI only accepts attached carries the = in name`; `authoring/validation.md` §These need judgment.

**Why**: a per-spelling join map has to answer *which forms the CLI accepts* — space, attached, or both, required or optional — while a menu only needs to know *what it inserts*. The wider contract brings a second token parser for every join string, a bare-spelling rule (the row must not re-offer itself), prefix shadowing (a glued `-W` swallows every `-W…` spelling), a token shape hooks must understand, and a legacy read path for the encoding it replaces. The separator case, which is the one with real weight, is already carried per spelling by the trailing `=`.

**The cost of the alternative chosen**: a spelling row is a candidate in its context's own option list, so a closed set written as rows competes with every other option there and can fill the first screen, and each row needs its own `tip`, which is a translation of its own. A `next` value costs nothing until the option is chosen. That trade is the author's to weigh per option, which is why the guide states it instead of setting a limit.

**Evidence**: gcc 14.2.0 accepts `-O2` and `-std=c11` and rejects `-O 2` (`2: linker input file not found`) and `-std c11` (`unrecognized command-line option '-std'`); its level set is closed, so rows insert legal words. xxhsum 0.8.4 documents `-H#` and tolerates a bare `-H`, which is not a form to record. Dart 3.13.6 accepts `-Dkey=value` and rejects `-D key=value` (`Could not find a command named "foo=bar"`), the free-form glued case where there is nothing to filter and only a space to delete. mpv 0.41.0 rejects `--volume 50` outright (`option requires parameter … use '--volume=value'`), showing that the separator case, not the glue case, is where a missing suffix loses real completions.

**Rejected alternatives**: (a) a per-spelling `join` map (`"join": {"-W": ""}`) — pays the parser and shadowing cost above for glued spellings alone; (b) a boolean `glued` marker — cannot express a `:` join or two spellings of one option that attach differently (`--define=` vs `-D`); (c) keep two encodings and gate their agreement — doubles the data a gate must keep in step; (d) infer the join from `usage` — `usage` is display text and the engine never parses it.

**Overturn if**: a glued or `:`-joined slot appears whose candidates are dynamic (hook-provided) or too numerous to write as rows while the CLI rejects the space form; then splitting the typed word is the only way to offer candidates, and the parser returns as a real need rather than a hypothetical one.

<a id="d56"></a>

## A bare flag and its attached value are two entries (D56)

**Decision**: when a CLI accepts a bare flag and only the attached form of its value (`--x`, `--x=value`, never `--x value`), the manifest declares **two entries**: `--x` for the flag and `--x=` with `next` for the value. Resolution prefers the entry whose spelling matches the typed form and falls back to the other when a manifest declares only one, so the split is additive.

**Rule lives in**: `authoring/manifest.md` §`usage` (the attached-value bullet); the resolution contract is in `design/completion.md` §5.

**Why**: one entry cannot express that grammar. Declaring `--x` with `next` (even `next: []`) makes the engine take the next word as the value, so a positional after the flag (`git pull --rebase origin main`) is swallowed and its slot never completes; declaring only `--x=` hides the bare flag from the menu, and a typed bare `--x` resolves to the value-taking entry, swallowing the same word. The two entries are the only model where each form is a legal, selectable whole value, and the bare one carries **no** `next` so the flag leaves the positionals alone.

**Evidence**: git 2.56.0's `git pull --rebase` accepts `--rebase=merges --dry-run origin main` while `--rebase true --dry-run` reads `true` as the repository (`fatal: 'true' does not appear to be a git repository`). With one entry the completion either stopped completing `origin`/`main` (the reported defect) or offered `true` as a space-separated argument the CLI rejects. Measured with `psc-menu` build mode against a scratch repository: with the bare entry keeping `next: []`, `git pull --rebase <TAB>` produced no candidates because the frontier became its empty value slot; removing `next` restored `origin`/`upstream` there. The engine previously resolved a typed bare `--x` to whichever entry came first in the array, so two entries were order-dependent; `find_option_node` now selects by the use's form, and the single-declaration fallback is covered by `eq_declared_name_matches_bare_and_keeps_eq_on_insert` and `explicit_bare_and_attached_entries_win_over_fallback`.

**Rejected alternatives**: (a) one `--x` entry with `next` — the space form is invalid and the positional is swallowed; (b) one `--x=` entry — the flag disappears from the menu and a typed bare `--x` still consumes the next word; (c) infer the form from `usage` at resolve time — `usage` is display text and the engine never parses it.

**Overturn if**: the engine gains an explicit optional-value / attached-only field on the option, or per-spelling join metadata — then one entry can describe both forms and the second row goes.
