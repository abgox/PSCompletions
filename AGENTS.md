# PSCompletions

A tab-completion manager for PowerShell. This repo maintains **completion definitions** for
many CLI tools: each tool has a JSON manifest describing its subcommands, options, aliases,
and tooltips. A PowerShell module reads these manifests at runtime so that typing
`git <Tab>` shows rich completions with explanations.

## Directives

Every file you produce **MUST** strictly conform to the rules here and in `authoring/`.

- **Follow every rule exactly.** Do not skip, relax, or reinterpret a specification.
- **Do not invent conventions.** If a rule does not cover the case you are facing, stop and
  ask the operator for guidance. Never assume or fabricate a rule to unblock yourself.
- **When in doubt, ask.** An incorrect assumption is far more costly than a clarifying
  question.
- **Do not guess advanced features.** Per-completion `config` keys, `info`, predict
  symbols, and the full `psc.*` API are documented in `design/` (or the official docs at
  https://pscompletions.abgox.com) — read them, or ask.

## Where things live

Four layers, one job each.

| Layer | Holds | Changes when |
| --- | --- | --- |
| **`AGENTS.md`** (here) | the `R-xx` rules — what must hold at all times — plus where to look | rarely |
| **`authoring/`** | procedure and reference: collecting CLI facts, field reference, gate reports, checklists | with every new CLI quirk found |
| **`design/`** | how the system runs today: manifest semantics, engine, hooks API, menu, protocol, `psc` CLI | when code changes |
| **`decisions/`** | the reasons: evidence, the rejected alternative, the overturn condition | when a trade-off needs recording, or a rule's premise is overturned |

A rule that needs its reasoning attached belongs here as one line plus a pointer to
`decisions/authoring.md`, not as a paragraph.

`decisions/` is **not** a mirror of this file. An entry belongs there when it carries something a
rule cannot: the evidence behind the trade-off, the alternative that was rejected, and the
condition under which the rule should be overturned — what you consult when the rules do not
decide the case in front of you. Most rule edits need no entry; writing one anyway restates the
rule in a second place that then drifts. Amend an entry when you change the rule it justifies,
delete it when its premise no longer holds, and add one only when a future reader would otherwise
have to re-derive the trade-off from scratch. A stale reason is worse than no reason: it reads as
authority.

**Canonical order: `AGENTS.md` > `authoring/` > `design/`.** The rule statement is here;
`authoring/` adds mechanism and examples and must not offer a second wording of the same
rule.

### Routing

Editing anything under `completions/` — new, update, review, or translate — MUST read
every file in `authoring/` (in the index order of `authoring/README.md`) and every file
in `decisions/` before any edit, plus `design/hooks.md §9` when a `hooks.lua` exists or
is planned. Follow references into `design/` whenever an authoring doc cites one
(`design/completion.md` for field semantics, `design/hooks.md` for the `psc.*` API).
The rows below do not exempt any file above, including files added later; they only say
where to spend extra attention per task.

| You are | Focus on |
| --- | --- |
| Writing a new completion | `authoring/collecting-info.md` → `authoring/manifest.md` → `authoring/validation.md` |
| Gathering facts from a CLI | `authoring/collecting-info.md` |
| Writing or reviewing manifest JSON | `authoring/manifest.md` |
| Writing a `hooks.lua` | `design/hooks.md §9`, then `authoring/hooks.md` |
| Updating an existing completion | `authoring/maintenance.md` |
| Translating to another language | `authoring/maintenance.md` |
| Leaving working files behind / finishing a task | `authoring/working-files.md` |
| Auditing a completion for portability | `authoring/validation.md` |
| Stuck on tooling | `authoring/tooling.md` |
| Working on the engine, menu, or protocol | `design/README.md` |
| Questioning or overturning a rule | `decisions/README.md` |

## Language and comment policy

- **English** for all documentation — this file, `authoring/`, `design/` — and for all
  `hooks.lua` comments. Do not introduce comments in other languages.
- **Short comments.** Explain *why* when the code is not self-evident, not *what* (the code
  already says that). Prefer one crisp line over a multi-line essay. Applies to `hooks.lua`
  and all source comments.
- **Exception — `types/psc.lua`** uses **bilingual descriptions: Chinese first, English
  after** (Chinese reads shorter, so it leads and stays visible in the editor's hover
  hint). Its comments surface as type hints for completion authors, so they are the
  exception to the English-only rule. `---@param` / `---@return` / `---@type` annotations
  keep English identifiers.

## Project structure

```
PSCompletions/
├── completions/              # completion definitions, one directory per tool
│   └── <command>/
│       ├── config.json       # id, language, alias, hooks
│       ├── hooks.lua         # dynamic completions (only when hooks: true)
│       └── language/
│           ├── en-US.json    # English data — single source of truth
│           └── zh-CN.json    # translated data
├── completions.json          # completion index — auto-generated by CI, DO NOT edit
├── WIP/                      # per-task working material (scripts, dumps, plans) — never committed
├── schema/                   # JSON Schema definitions
├── authoring/                # authoring procedure, field reference, gates, checklists
├── design/                   # how the system works today
├── decisions/                # why the rules are shaped this way
├── scripts/                  # validation, scaffolding, and maintenance scripts
├── types/psc.lua             # EmmyLua stubs for the psc.* API
└── module/PSCompletions/     # PowerShell host — do not edit when writing completions
```

**Scope reminder**: only _edit_ files under `completions/<command>/`. Running scripts under
`scripts/` is expected and required — the restriction applies to where you can *write*, not
which scripts you can *run*.

## The completion model

Every command has its own **completion context** — what appears in its menu. A context is
made of **subcommands** (`next`) and **options** (`option`); `global_option` items are
available at every level. The engine builds a tree from the manifest; selecting a
subcommand moves **into its context**, selecting an option stays (unless the option has
`next` / `option`).

```
git <Tab>             → add, branch, checkout, commit, ...   (next)
git add <Tab>         → --all, --patch, --dry-run, ...       (add's option)
git stash <Tab>       → apply, pop, show, ...                (stash's next)
git stash apply <Tab> → stash names supplied by hooks        (dynamic, via psc.add)
```

Context inheritance, option resolution (bubbling), the resolve walk, repeat filtering,
predict symbols, and the full manifest format are defined in
[`design/completion.md`](design/completion.md). The strict, actually validated definition
is [`schema/completion-manifest.en-US.json`](schema/completion-manifest.en-US.json).

### R-01 — the two `next` rules (they are opposite)

> Is this item a command (inside a `next` array)?
>
> - **YES** → `next` must be non-empty. No sub-subcommands? **Omit `next` entirely.**
>   `next: []` on a command is forbidden.
> - **NO** → is it an option (inside `option` / `global_option`)?
>   - Takes a value? → `next: []` (free-form) or `next: [...]` (known candidates).
>   - No value (boolean flag)? → **omit `next`**.

Commands must never carry `next: []`; value-taking options must always declare `next`.
Machine-enforced by `compare-json.ps1`.

**How you know which an option is, is collected, not assumed.** `--help` may not print a
placeholder at all (`glab` prints none for any of its 333 flags), and a value-taking option
mistyped as a boolean is invisible to every gate — the menu offers the flag and the next
keystroke brings candidates for a slot that does not exist. Decide by `--help` placeholder →
the tool's own reference → invoking it with no value, in that order; see
`authoring/collecting-info.md` §Determining whether an option takes a value.

## Workflow

1. **Generate scaffold**: `./scripts/create-completion.ps1 <command>`.
2. **Collect CLI info** — see `authoring/collecting-info.md`. Include the **subcommand
   probe** (`R-02`): a command with subcommands in the CLI must have a non-empty `next`, and
   no script can catch this for you.
3. **Write `en-US.json`** against the schema. After writing, review it against
   `authoring/manifest.md`.
4. **Self-check** — before running any tool, verify `R-01` by hand:
   - every item inside a `next` array does **NOT** have `next: []`
   - every item inside `option` / `global_option` with `usage <...>` **DOES** have `next`
5. **Decide on `hooks.lua`** — see `authoring/hooks.md` and `design/hooks.md §9`. If yes,
   set `"hooks": true`; if no, leave both absent. Do not add a placeholder.
6. **Run both gates on `en-US.json`**: `./scripts/compare-json.ps1 <command>`
   and `./scripts/validate-completion.ps1 <command>`. `compare-json` never
   checks schema — a structural defect (a bare-string `next`, an empty `tip`)
   passes it and surfaces only after translation, wasting the pass. The
   schema bucket must be clean now; translation deltas wait for step 9.
7. **Fix every reported issue** — see `authoring/validation.md` for what each report means.
   Re-run step 6 until clean — only then is `en-US.json` done.
8. **Translate to `zh-CN.json`** — see `authoring/maintenance.md`.
9. **Run again**: both gates must be clean for both languages.
10. **Hand off the working files** — report what `WIP/<tool>/` holds and ask whether to
    delete it; delete only on confirmation (`R-20`). See `authoring/working-files.md`.
11. **Propose the commit** — draft the message per `authoring/maintenance.md`
    §Proposing the commit and ask whether to commit now; never commit unilaterally
    (`R-21`).

### Judgment checks — the scripts cannot see these

Run these after the gates, before declaring the task complete.

- [ ] **Subcommand probe run for every command (≤2 levels)** — `R-02`.
- [ ] **Every alias the CLI lists is recorded** — command-level and option-level, no length
  cutoff, including spellings hidden from `--help` but documented in the tool's own reference —
  `R-03`.
- [ ] **Every subcommand and every option at every level is captured**, not just top-level
  `--help`.
- [ ] **Portability audit run** — `R-12`, `R-13`, in `authoring/validation.md`.
- [ ] **`hooks.lua` compiles** (`luac -p`) and every `psc.on` target resolves
  (`check-hook-targets.ps1`).
- [ ] **Every value a hook produces was probed against the CLI** — `R-17`.
- [ ] **Working files reported, not deleted** — `WIP/<tool>/` handed to the operator for
  the keep-or-delete decision; nothing removed unilaterally — `R-20`.

The full checklist, and the machine-checked half of it, is in
`authoring/validation.md`.

## Hard rules

Each is a silent failure — the validation scripts cannot see it. Evidence and overturn
conditions are in [`decisions/authoring.md`](decisions/authoring.md). `R-01` is stated above,
with the completion model.

**R-02 — Subcommand probe, both directions.** Run
`<cmd> <sub> --help | grep -E 'AVAILABLE COMMANDS|^Commands:'` for every command, to 2
levels. The pattern is a sample, not the rule — tools grouping pages as `CORE` / `GENERAL` /
`TARGETED COMMANDS` need `COMMANDS\s*$` (`R-07`; see `authoring/collecting-info.md`).
Output present → the manifest **must** have non-empty `next`; this one line catches
the "parent modeled as a leaf" defect that both gates pass silently. Output absent while the
manifest **does** have `next` proves nothing — judge that direction from `usage` (a
positional placeholder means the entries are candidate values, not subcommands) and verify
by invocation. See `authoring/collecting-info.md`.

**R-03 — Aliases are mandatory, not optional.** Record *every* alias the CLI lists —
command-level *and* option-level — no length cutoff, no "only the popular ones". A missing alias
is a functional gap: the user cannot discover that the short form exists. All forms must also
appear in `usage`. `compare-json` only validates that an *already recorded* alias has a `usage`;
it never reports a **missing** one. A spelling the tool documents but hides from `--help` is
still an alias the CLI lists — decide by invocation (`R-06`), not by `--help`. Aliases are
**scoped to the page that lists them**: the same short form legally belongs to different long
options on different pages, so harvest per page and never merge into one global table.

**R-04 — Upstream is authoritative.** Prerequisites, prior configuration, rarity, and being
uninstalled here are all **not** reasons to exclude a command — the menu *is* the discovery
surface. The only exclusions are "not a command at all": a removed GUI tool, shell-library
entry points, and documentation topics (`HELP TOPICS`). Never draw a porcelain / plumbing
line. Delete only per `R-06`. See [`D5`](decisions/authoring.md#d5).

**R-05 — An option diff must subtract the global set first.** Build the global set once,
then subtract it from every per-command diff. clap repeats global flags in *every*
subcommand's `--help`, so a naive comparison reports each as missing at every level. The
reverse failure is worse — seeing globals as `EXTRA` everywhere invites deleting them, and
they belong in `global_option` alone ([`D16`](decisions/authoring.md#d16)).

**R-06 — Deletion and keeping are decided by the invocation's error text.** Run the flag
with no value and read what the CLI says: `unknown argument` → delete; `a value is required
for '--x <X>'` → keep (hidden but accepted); `unexpected argument` → delete. `--help`
settles neither direction — a CLI hides flags between versions while still accepting them,
and a flag it lists may already be gone. See `authoring/maintenance.md`.

**R-07 — Read `--help` by section; prose is not a command.** A section whose name ends in
`COMMANDS` is the commands section and its entries must be bare command words. `HELP TOPICS`
entries stay top-level, never under a command's `next`. Option descriptions and trailing
prose are never subcommands. Decide by what a section *is named*, not by what it isn't.

**R-08 — `[possible values: a, b, c]` is the authoritative enumeration source.** It is
machine-generated inline in the option's own description line, so it cannot mislead the way
`(a|b)` or a trailing list can. Extract it into `next: [...]`, with the trailing tip line
`Possible values: ...` (English) / `可能值: ...` (Chinese). No order is
prescribed for either: `sort-json.ps1` reorders every named array on every run, and the tip line
is display text. Any `--help` line carrying it yields a non-empty `next`. See
[`D35`](decisions/authoring.md#d35).

**R-09 — Hook slot rule.** Inject a value kind only where the CLI itself accepts it — check
`--help` usage, docs, and examples, not the manifest alone. Never offer files at a context
whose slot takes subcommands, names, keys, or nothing. If a slot accepts files but the
manifest shows no placeholder, add the `usage` placeholder so the slot is documented.

**R-10 — Hooks do not offer file paths as candidates.** Native completion owns paths, and a hook's
file list is unbounded by construction — it grows with the repository — so it buries the subcommands
and options the user is actually looking for. The test is **what becomes the selectable value**, not
which API produced it: `psc.glob` (with or without a wildcard — `psc.glob(".env")` is still
`psc.glob`), a `psc.ls` of the current directory, and a `psc.run` of `ls` all count the same.

Offering a **bare filename** is not a way around this. Stripping the directory fixes nothing — a
repo-wide `**/*.json` still yields a repository-sized list — and into a path slot a basename is
usually a *broken* argument. The test is what the slot accepts, not the shape of the string.

`psc.glob` is a free **means**, not a trigger. When the CLI cannot enumerate the values a slot
accepts, the hook must — and a glob is often the only way to find the source files. `scoop` globs
`bucket/**/*.json` across every bucket and offers the app **names** extracted from those manifests;
`scoop-checkver` does the same over its own bucket directory. The path never reaches the menu — only
the name does — and without the glob there is no other source and no CLI call to move into `next`.
The path may itself be unknown to the user: `scoop` resolves the bucket directory via the `SCOOP`
environment variable, so neither the user nor the CLI knows where the manifests live — the hook
resolves the path and enumerates in one step.

The same principle applies to `psc.ls`: when the slot takes a **name** the CLI cannot enumerate
itself, sourced from a **known directory** — `hugo --theme` with `psc.ls("themes")`, `typst init`
over the package cache — surface `entry.name`, never `entry.path`. See `authoring/hooks.md`.

A **CLI-filtered subset** is not a violation. When the hook runs a command that itself selects a
meaningful subset of paths — `git status --porcelain` for modified files, `git ls-files` for
tracked files, `git diff --diff-filter=U` for conflicted files — the paths are already filtered
by the CLI, not dumped by the hook. The test is whether the path set comes from an
indiscriminate enumeration (`psc.glob`, `psc.ls`) or from the CLI's own filtering logic.

**R-11 — `global_option` is a sharing mechanism.** A flag that **many** subcommands share
*verbatim* belongs in `global_option`, even when the root itself rejects it. When only a
**few** take it, or the entries differ per subcommand, put it on each of those subcommands'
own `option`. Options do not merge down the tree: a child with no `option` of its own
is offered its nearest ancestor's (or root's), but the moment it declares one, the
parent's flags disappear from that context. So never copy a parent's `option` onto a child
that needs none of its own — and when a child gains its first flag, re-declare every
parent flag it should keep. For a meta-flag like `--version`, decide by invocation rather than
`--help`: run `<cmd> <sub> --version` under each subcommand — accepted (nearly) everywhere
goes to `global_option` (offered at root too, so root loses nothing), root-only stays in
root `option`. A `--help` that lists the flag settles nothing. The trade-off and its measurement:
[`D16`](decisions/authoring.md#d16).

**R-12 — Paths stay platform-neutral; no author-machine paths.** `tip` / `usage` / `example`
use `~/.gnupg/pubring.kbx`, `/home/<user>/`, never a copied machine path. When a value is
genuinely platform-specific and the two forms are not interchangeable, show both as separate
`tip` lines (`"Windows: ..."` / `"Linux: ..."`) — per-platform pairs are not a defect,
copying one machine's path is. File-name completions must not assume case-insensitive
matching.

**R-13 — A platform-specific invocation must be guarded, not avoided.** `psc.platform`
(`"windows"` / `"macos"` / `"linux"`) exists for this and hooks already branch on it (`nssm`,
`volta`, `scoop`): a Windows-only program behind `psc.platform == "windows"` is correct; an
*unguarded* `powershell.exe` / `cmd.exe` / `wmic` call is the defect. Platform-only data
(`C:\` paths, registry access) has no portable form and goes inside the guard too. See
`D19`.

**R-14 — `config.json` `alias` discipline.** Add `alias` only when upstream officially
recognizes more than one name — do not reason from the project's full name. When set, the
directory name is ignored, so **it must be repeated inside `alias`**, or that trigger
silently dies. The exception is a script shim (`psc-compare`, `psc-link`): the directory
name is internal, not a command anyone types, so `alias` lists only the invoking script
paths. A directory whose name contains `@` **must** declare `alias`, because
triggers are first-come-first-served and nobody types `AAA@author`. Omit `.exe` / `.cmd` /
`.bat` suffixes. See `authoring/manifest.md`.

**R-15 — A `config` entry is user-facing surface; ask before adding one.** Every key lands in
`psc completion` for every user of this completion, and no gate will flag an unnecessary one.
When a setting looks like it should be configurable, ask the author whether it should be — do
not add it because it seems reasonable. The three existing uses are all one shape (a knob on
how much work a hook does); `authoring/manifest.md` has the criterion.

**R-16 — A hook does not supply constant candidates.** If a candidate's value is known while
writing — a literal string, or a literal array iterated with `ipairs` — it belongs in the
manifest's `next: [...]`: the manifest already owns the mechanism (`next` is "a fixed list of
values to complete from"), and hooks **append** to `next` rather than replace it, so moving it is
a clean subtraction. This is a layering rule, not a size rule — `aws` lists 1405 static entries in
its manifest — and the test is whether the value is known at authoring time, not how many there
are. A producer whose only candidates are constants is a `next` array, not a hook: delete the
producer, and drop `"hooks": true` when nothing else remains.

A hook that computes **dynamic tips** for constant values is not a violation. `git`'s `add_head`
returns `{"HEAD", "FETCH_HEAD", "ORIG_HEAD", "MERGE_HEAD"}` — the values are constant, but the
tips are computed dynamically via `git show` (commit message, date, author). This information is
impossible to represent in a static manifest; the hook is adding value, not just supplying
candidates.

**Relocating is not verifying.** The move inherits the producer's errors, and a manifest value has
no self-verifying source — `compare-json` and `validate-completion` check structure, never truth,
so a clean run certifies the shape, not the content. Re-probe each value against the CLI as part of
the move; see `authoring/collecting-info.md`.

**R-17 — Touching a hook means auditing it.** No gate checks whether a hook's output resolves —
`compare-json` and `validate-completion` test structure and translation, never truth. A hook is
unverified until someone probes its output against the CLI, so when you edit one, treat the
producers you did not touch as equally unverified and re-probe them. See
`authoring/collecting-info.md`.

**R-18 — Complementary options are not aliases.** When a CLI lists `--xxx` and `--no-xxx`
together, they are **complementary options** (enable/disable) — model them as **separate
entries**, each with its own `name` and `tip`. The `alias` field is reserved for **true
synonyms** — the same option under different names (`-a` / `--all`, `--color` / `--colour`,
`-C` / `--reuse-message`). Why collapsing the pair loses meaning, and the overturn condition:
[`D33`](decisions/authoring.md#d33).

**R-19 — Tips are multi-line arrays; split multi-sentence content.** A `tip` is an array of
lines, and each element renders as one visible line in the menu. When the source `--help`
contains multiple sentences, split them at sentence boundaries so each line is a self-contained
thought — a paragraph crammed into one element renders as an unreadable wall of text. The split
points are defined in `authoring/manifest.md` §`tip` / `usage` / `example` format; rationale in
[`D34`](decisions/authoring.md#d34).

**R-20 — Working files live in `WIP/<tool>/` and are deleted only on the operator's
word.** Every artifact a task generates — analysis scripts, `--help` dumps, diff plans,
translation dictionaries — goes in `WIP/<tool>/`, one directory per completion, never in a
shared temp directory where two concurrent tasks overwrite each other's scripts; the layout
below that directory is the task's own choice. When the completion is done, report the
directory and ask whether to delete it — **never delete unilaterally**, because the operator
reviews after the gates and this material is what makes a rework fast. The material is a
pipeline artifact: never committed, never pushed, and never gitignored either, so the record
stays visible in the working tree. See `authoring/working-files.md`; rationale in
[`D37`](decisions/authoring.md#d37).

**R-21 — Propose the commit, never make it.** When a completion task is done — gates
clean, translation done, judgment checks passed — draft the commit message and ask the
operator whether to commit now. **Never commit unilaterally**: committing publishes, and
batching, squashing, or holding back is the operator's call. One completion per commit; a
batch shares one commit only when every item takes the same action. The message carries
each completion's verified CLI version — the baseline the next update diffs against. See
`authoring/maintenance.md` §Proposing the commit.

**R-22 — Collection probes never run with the repo as the working directory.** Every CLI
invocation a harvest script runs — `--help` probes, acceptance probes, producer probes
alike — executes with `workdir` set to a scratch directory (`/tmp/opencode/<tool>/` or
`WIP/<tool>/`), never the repo root or any irreplaceable tree. A probe that executes
destructively against CWD then destroys scratch. See [`D39`](decisions/authoring.md#d39).

**R-23 — `--help`-appended proves nothing on a hand-rolled parser.** The "appended `--help`
never executes" guarantee holds only for framework parsers (clap, cobra, …) that intercept
help before dispatch. A hand-written dispatcher — shell `case`, batch labels, a dynamic
`*)` fallthrough — consumes `--help` as an ordinary argument: an option's value (`$2`), a
positional operand, or a dispatch word, and then runs. Before batch-probing such a tool:
read one dispatcher and one leaf to confirm `-h` handling exists; run the first probe of
each new shape in a canary directory (a few files plus a `.git`) and diff afterwards; a
shape that executes instead of printing help goes source-only for that subtree — no live
probes. A zero-exit non-help output is the tell. See [`D39`](decisions/authoring.md#d39).

## Format judgment calls

These are judgment, not enforcement — the scripts cannot express them.

- **Trailing punctuation is not a rule.** A `tip` line may end in `.`, `?`, `:`, `)`, a
  closing quote, or nothing. `tip` is display text and the engine never parses it, so a rule
  about it has no enforcement point. See [`D32`](decisions/authoring.md#d32).
- **Spaces between Chinese and English characters are required** — enforced by
  `validate-completion.ps1`.
- **Experimental** items keep the upstream `EXPERIMENTAL:` prefix. **Deprecated** items are
  noted inline, not deleted (`R-06`).
- **Platform-specific topics that are unusable on the current platform are kept** and marked
  `(Windows only)` / `(macOS only)` — the marker makes the limitation visible before the
  user tries it.

## Gates

```
./scripts/compare-json.ps1 <command>         # structure, usage, translation
./scripts/validate-completion.ps1 <command>  # schema, config.json, spacing
./scripts/check-hook-targets.ps1 <command>   # psc.on targets — mandatory when hooks exist
```

Fix every reported item until they run clean. `check-hook-targets.ps1` is the **only** check
that catches a dangling `psc.on` target or one written as an alias — both fail silently at
runtime. What each gate cannot see, and how to read every report it does produce, is in
`authoring/validation.md`.

Environment prerequisites — `pwsh` not `powershell.exe`, `ajv-cli`, `luac -p`:
`authoring/tooling.md`.
