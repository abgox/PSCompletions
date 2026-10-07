# Collecting Command Info

Facts about a CLI come from the CLI, not from assumption — the manifest is only as good
as the help text behind it. The rules are `R-02` … `R-08` in `../AGENTS.md`; this file
gives the mechanism.

## Traversal

Collect help for **every** subcommand, not just the top level. Do not assume a command
has no subcommands without checking its `--help` output — many have sub-subcommands that
are not obvious from the top-level help.

```
1. Run: <command> --help
   → lists all top-level subcommands

2. For EACH subcommand:
   Run: <command> <subcommand> --help
   → check whether it has its own subcommands (look for a Commands section)

3. If it does, repeat for each of those:
   Run: <command> <subcommand> <sub-subcommand> --help

4. Record ALL options at every level
```

For each subcommand record: full name, **every command-level alias**, description, every
option (including aliases, whether it takes a value), and whether any option or
parameter has a fixed set of allowed values — this decides how the value is encoded,
see [`manifest.md`](manifest.md).

> When you run `<command> <subcommand> --help`, the first line is typically the
> description. Use it as the `tip` value.

Concrete example:

```powershell
git --help          # top-level commands: add, commit, push, ...
git add --help      # options for `add`
git commit --help   # options for `commit` (it has no sub-subcommands)
git push --help     # options for `push`
```

### Checking for description updates

When collecting help, also check whether descriptions have changed:

- Commands previously marked `[experimental]` may no longer be experimental — update the
  description.
- Descriptions may have been rewritten — update to match current help output.

## Five collection mistakes that produce wrong data silently

| Mistake | What to do instead |
| --- | --- |
| Searching for a flag anywhere in the help with `--h` | **Anchor at the start of the line** — prose gets mistaken for options |
| Decoding the probe's output as text | Read bytes; a `UnicodeDecodeError` is not a refusal |
| Probing a subcommand's options as `<tool> <flag>` | Use `<tool> <sub> <flag>` |
| Treating "parent and child print the same first line" as proof of a fake command | The first line proves nothing (cobra prints `NAME:`, some tools print a version banner) |
| Comparing only the `name` field | **Compare `name` *and* `alias`** — a long form stored as an alias reads as missing |

## Read `--help` by section — prose is not a command

Help output mixes several kinds of lines, and scraping the wrong section invents
subcommands that do not exist.

| Help section | What it is | How to encode |
| --- | --- | --- |
| `COMMANDS` / `AVAILABLE COMMANDS` | real subcommands | `next` entries |
| `HELP TOPICS` / `HELP TOPICS AND GUIDES` | documentation topics, not commands | keep as **top-level** entries, never as a command's `next` |
| option descriptions, trailing prose (`NOTE: ...`, `The GitHub hostname ...`) | neither | never encode as a subcommand |

Real examples of what this prevents: `gh mintty > NOTE` and `gh api > GH_HOST` (the
latter is actually the `--hostname` **option**).

**Decide a section by its name, not by what it is not.** Each tool names its sections
differently — gh has `AVAILABLE COMMANDS` / `GENERAL COMMANDS` / `TARGETED COMMANDS`,
podman has `Available Commands`, git's `help -a` is two columns — so treat a section
whose name ends in `COMMANDS` as the commands section and require its entries to be bare
command words. A blacklist (skip `FLAGS`, `ARGUMENTS`, `EXAMPLES`…) gets fooled by the
word `gh` appearing inside an `EXAMPLES` section.

## Two ways option lines silently corrupt the data

Both produce a manifest that passes every gate and is wrong:

```
--file-type string        Set file type to use for the artifact (layer)
                           ^^^^^^^ a placeholder, not part of the description
  -a, --append            Append files to an existing artifact
     ^ the short form shares the line; the comma is not a placeholder
```

A parser that transcribes faithfully ends up with the type name inside the `tip`, or
splits one option into two entries. Take the description from the text after the flag and
its placeholder, and anchor the flag at the start of the line.

## The subcommand probe

For each command in the manifest — down to 2 levels, which covers nearly every tool —
run:

```
<cmd> <sub> --help | grep -E 'AVAILABLE COMMANDS|^Commands:'
```

**Direction 1 — a hard check.** Output present → the manifest **must** have a non-empty
`next`. Output absent while the manifest has none → correct. This one-line check catches
the "parent command modeled as a leaf" defect (5 instances in `gh` alone), which
`compare-json` and `validate-completion` both pass silently because they only check
internal consistency.

**Direction 2 — not a verdict.** Output absent while the manifest **does** have `next`
proves nothing, because `next` is deliberately a **dual-purpose field**:

| `next` holds | Example | Engine behaviour |
| --- | --- | --- |
| subcommands (enter a context) | `git remote` → `add` / `remove` / `rename` / `set-url` | moves into a new context |
| candidate values for one slot | `volta list [TOOL]` → `all` / `node` / `npm` / `yarn` / `pnpm`; `stripe resources` → 89 API resource names | fills the current slot |

So judge this direction from the command's own `usage`:

- `usage` **has a positional placeholder** (`<TOOL>`, `[TOOL]`) → the `next` entries are
  candidate values. Legitimate, leave it alone.
- `usage` has **no placeholder** → the `next` entries claim to be subcommands, so
  verify.

### Ground-truth verification

Use it in either direction, and whenever a `next` child is suspect:

```
<cmd> <child-from-manifest> --help
  prints the PARENT's help  →  that "subcommand" does not exist (defect)
  prints the child's own help / argument docs  →  it exists (or it was a value all along)
```

`netlify teams list` is the worked example: the manifest invented a `list` under the leaf
command `teams`, and `netlify teams list --help` quietly prints `teams`' own help instead
of failing.

### Reading the result

If `MISSING` holds the CLI's primary name while `EXTRA` holds the manifest's alias, the
two sides simply disagree on which form is longer — **this is not a defect and needs no
fix**. `name` / `alias` is a data-model distinction with no hierarchy; "longest wins" is
only a `sort-json` convention, and a CLI's own primary form may well be the shorter one.
The only real requirement is that **both forms appear in `usage`**, so the user recognises
either. `psc.on` in `hooks.lua` refers to the `name` field, but that is likewise just an
identifier.

### An option diff must subtract the global set first

Build the global set once — from the top-level `--help`, or from the tool's dedicated
global options list (`minikube options`) — then subtract it from every per-command diff.
clap repeats the same global flags in **every** subcommand's `--help`, so a naive
per-command comparison reports each of them as missing at every level, and the spurious
entries swamp the real ones. The reverse failure is worse than the inflated count — seeing
the globals as `EXTRA` in every command, the cheap reaction is to delete them from the
manifest, and
[`D16`](../decisions/authoring.md#d16) says they belong in `global_option` and there
alone.

## Enumerating option values

Help text often lists an option's allowed or example values — recognize them and map them
to `next: [...]`:

- "Possible values: a, b, c" / "Valid values: ..." / "Values: ..."
- parenthesized groups: `(a | b | c)` or `(a, b, c)`
- bracketed groups: `[a|b|c]` or `[a, b, c]`
- a list right after the option's placeholder in the usage line

Even when the help shows no such list, if an option's value has a recognizable shape
(status codes, numbers, IDs, time formats), add a few **representative example values**
via `next: [...]` so users can pick one instead of typing blindly (e.g. `--status-code`
→ `[200, 404, 500]`, `--since <TIME>` → `["2024-01-01", "1h"]`). Keep `next: []` only
for genuinely free-form values.

**`[possible values: a, b, c]` is the most reliable source of all.** clap writes the
allowed set inline in the option's own description line — it is machine-generated, not
prose, so it cannot mislead the way a `(a|b)` or a trailing list can. Extract it into
`next: [...]` in the CLI's own order and add the trailing tip line
`Possible values: a, b, c` (English) / `可能值: a, b, c` (Chinese, **no trailing
period**). A `--help` line carrying `[possible values: ...]` always yields a non-empty
`next`.

### When the help has no `[possible values]`

`R-08` covers clap's inline enumeration. Most CLIs never give one. In this order:

1. **A rejected value reveals the validator.** Submit a deliberately wrong value and read the
   error. `ruff rule E` → `error: invalid value 'E' for '[RULE]'`, `tip: a similar value exists:
   'E999'`. The error names the slot and shows the expected shape — here, a full rule code rather
   than a prefix.
2. **A metadata subcommand with a machine-readable format.** `ruff rule --all --output-format
   json` returns 971 rules, each carrying `code`, `linter` and `name`. Look for `list`, `--all`,
   `-o json`, `--format json`. This is the authoritative enumeration when the help has none, and it
   is machine-generated, so it cannot mislead the way prose can.
3. **Probe each candidate before writing it.** Deriving a set from a code table and never running
   the CLI is how a wrong set lands: a value the CLI silently ignores looks identical to a valid
   one until you try a member that does not exist.

**Validity is per slot, not per string.** `E` is a legal `ruff check --select` selector and an
illegal `ruff rule` argument. Legality depends on the slot a value fills, so when candidates move
between options — or a hook's set moves into a manifest — verify each one against *that* option.

## `separator` — prove the split, then declare it

Help text saying "comma-separated" is not evidence. Three probes:

```
<cmd> --opt X,Y      → accepted
<cmd> --opt X Y      → rejected
<cmd> --opt X,BOGUS  → names only `BOGUS`
```

The third is decisive. If the bad member is reported on its own, the CLI tokenises on the comma, so
`separator: ","` is required. If `X,BOGUS` is rejected as one unknown value, the CLI does not split
and declaring `separator` would be wrong.

Declare it on the value-taking option and show the repeated shape in `usage`
(`--select <RULE_CODE,...>`). `compare-json` checks only the form — comma versus pipe, via
`usageSeparator` — and never whether the CLI actually splits, so both directions are silent wrong:
declaring it when the CLI does not split, and omitting it when the CLI does.

## Proving what a flag does

Help text saying "skip tests" does not tell you whether it skips compilation, execution, or
both. Two flags with similar descriptions often differ in what they suppress — `skipTests`
compiles test sources but skips execution, while `maven.test.skip` skips compilation entirely.

**Make it fail, then see which flag suppresses the failure.** Create a build that fails for a
known reason, then run it under each flag:

```
<cmd> test                           → BUILD FAILURE  (baseline: the failure reproduces)
<cmd> -DskipTests test               → BUILD FAILURE  (still compiles; only runs are skipped)
<cmd> -Dmaven.test.skip=true test    → BUILD SUCCESS  (compilation is suppressed too)
```

The flag that turns FAILURE into SUCCESS is the one that suppresses the compile step. The
baseline run is essential — without it you cannot tell whether a SUCCESS means "the flag
worked" or "the failure never reproduced in the first place."

### Trust the probe before trusting the result

Before concluding that a producer is broken, confirm the probe itself is correct. Submit a
value that must fail and verify it does:

```
<cmd> --projects no-such-module  → fails   (probe is sound)
<cmd> --projects child           → succeeds
```

If the negative control passes, the probe is wrong, not the producer. A probe that cannot
fail cannot distinguish anything, and a sound conclusion drawn from it is wrong.

## Alternative patterns

- If the tool uses a `help` subcommand instead of `--help`, use
  `<command> help <subcommand>`.
- If `--help` output is sparse or missing option descriptions, check official docs.
- If updating an existing completion for a new version, check changelogs and release
  notes — see [`maintenance.md`](maintenance.md).
- **If the tool is not installed locally**, fetch its docs instead: official website,
  GitHub README, or `--help` output shown in the project's docs or release notes. Do not
  skip a subcommand's options just because you can't run it — dig until you have them.
- **A registry 404 is not "cannot be installed."** Many tools ship as scoped packages under
  a different name (`rspack` → `@rspack/cli`, `rsbuild` → `@rsbuild/core`, `ionic` →
  `@ionic/cli`), so a bare-name lookup fails even though the tool is installable. Look up the
  real package name in the tool's own docs, then `npm view <pkg> bin` — that returns the
  executable the user actually types, which is what `config.json` `alias` must record
  (`R-14`). Only then is a skip legitimate. See [`D15`](../decisions/authoring.md#d15).
