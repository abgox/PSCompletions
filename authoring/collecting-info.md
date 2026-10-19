# Collecting Command Info

Facts about a CLI come from the CLI, not from assumption — the manifest is only as good as the help text behind it.
The rules are `R-02` … `R-08` in `../AGENTS.md`; this file gives the mechanism.

## Traversal

Collect help for **every** subcommand, not just the top level.
Do not assume a command has no subcommands without checking its `--help` output — many have sub-subcommands that are not obvious from the top-level help.

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

For each subcommand record: full name, **every alias** (command-level and option-level), description, every option (including aliases, whether it takes a value), and whether any option or parameter has a fixed set of allowed values — this decides how the value is encoded, see [`manifest.md`](manifest.md).
Aliases hidden from `--help` are collected separately, see §Aliases the `--help` hides below.

> When you run `<command> <subcommand> --help`, the first line is typically the description.
> Use it as the `tip` value.

Concrete example:

```powershell
git --help          # top-level commands: add, commit, push, ...
git add --help      # options for `add`
git commit --help   # options for `commit` (it has no sub-subcommands)
git push --help     # options for `push`
```

### Checking for entirely missing commands

An option-by-option audit never finds a command that is absent from the manifest altogether.
Compare `help -a` (or the tool's command list) against manifest `name` **plus** `alias` — a command modeled as another entry's alias (e.g. `blame` under `annotate`) is covered.
Genuinely absent entries are usually the most-used ones, which is why nobody noticed.
A removed GUI tool, shell-library entry points, and documentation topics are never encoded (`R-04`, [`D5`](../decisions/authoring.md#d5)); everything else upstream lists gets an entry.

### Checking for description updates

When collecting help, also check whether descriptions have changed:

- Commands previously marked `[experimental]` may no longer be experimental — update the description.
- Descriptions may have been rewritten — update to match current help output.
- For a command's one-line description, take the **short** description, not the first line of `--help`. Some tools print the *long* description there — several paragraphs before the usage line — so the short form lives in the shell-completion enumeration (`gh __complete ""`) or the manual's command index. Comparing against the long text reports drift on every command at once, and "fixing" it copies paragraphs into one-line tips.

## Five collection mistakes that produce wrong data silently

| Mistake | What to do instead |
| --- | --- |
| Searching for a flag anywhere in the help with `--h` | **Anchor at the start of the line** — prose gets mistaken for options |
| Decoding the probe's output as text | Read bytes; a `UnicodeDecodeError` is not a refusal |
| Probing a subcommand's options as `<tool> <flag>` | Use `<tool> <sub> <flag>` |
| Treating "parent and child print the same first line" as proof of a fake command | The first line proves nothing (cobra prints `NAME:`, some tools print a version banner) |
| Comparing only the `name` field | **Compare `name` *and* `alias`** — a long form stored as an alias reads as missing |

## Read `--help` by section — prose is not a command

Help output mixes several kinds of lines, and scraping the wrong section invents subcommands that do not exist.

| Help section | What it is | How to encode |
| --- | --- | --- |
| `COMMANDS` / `AVAILABLE COMMANDS` | real subcommands | `next` entries |
| `HELP TOPICS` / `HELP TOPICS AND GUIDES` | documentation topics, not commands | keep as **top-level** entries, never as a command's `next` |
| option descriptions, trailing prose (`NOTE: ...`, `The GitHub hostname ...`) | neither | never encode as a subcommand |

Real examples of what this prevents: `gh mintty > NOTE` and `gh api > GH_HOST` (the latter is actually the `--hostname` **option**).

**Decide a section by its name, not by what it is not.** Each tool names its sections differently — gh has `AVAILABLE COMMANDS` / `GENERAL COMMANDS` / `TARGETED COMMANDS`, podman has `Available Commands`, git's `help -a` is two columns — so treat a section whose name ends in `COMMANDS` as the commands section and require its entries to be bare command words.
A blacklist (skip `FLAGS`, `ARGUMENTS`, `EXAMPLES`…) gets fooled by the word `gh` appearing inside an `EXAMPLES` section.

## Three ways option lines silently corrupt the data

All three produce a manifest that passes every gate and is wrong:

```
--file-type string        Set file type to use for the artifact (layer)
                           ^^^^^^^ a placeholder, not part of the description
  -a, --append            Append files to an existing artifact
     ^ the short form shares the line; the comma is not a placeholder
```

A parser that transcribes faithfully ends up with the type name inside the `tip`, or splits one option into two entries.
Take the description from the text after the flag and its placeholder, and anchor the flag at the start of the line.

### A fourth trap: prose that starts with a flag

Anchoring at the start of the line is necessary but not sufficient: a wrapped description continuation lands on its own line starting with `--x` (`--tool-call-parser lfm2").`, `--status.`), and so does an example fragment (`--template ...`).
Harvest flag-anchored lines only below the `Options:` header and only at entry indent — description continuations indent deeper.

### A third trap: the value name that looks like a flag

Some frameworks print the option's *value name* into the flag line, and the value name can be another option's spelling:

```
      --value --field            Value to set on the field named by --field
  -f, --force --hostname         Force setup even if the host is not known
```

`--field` is not an alias of `--value`, and `--hostname` is not an alias of `--force` — both are the value name the framework lifted out of the description.
**A word in the flag head that also appears in the description — verbatim (`--field` in "named by --field") or by stem (`--hostname` beside "host") — is a value name, not a flag of that option**; drop it from the flag list.
Whether the option takes a value at all is a separate question (§Determining whether an option takes a value): the word's presence proves nothing either way — one of the two lines above is a boolean that carries a value-looking word, the other genuinely takes a value, and only invocation tells them apart.

### Joining wrapped help lines

Terminal-width wrapping breaks lines mid-token, and each break class wants a different join — enumerate every wrap in the corpus before choosing, because a rule tuned on one class silently mangles the other:

- A trailing hyphen either continues an identifier (`[default: no-` + `ok]` keeps it) or is hyphenation added by the wrapper (`downl-` + `oad` strips it). There is no local spelling test that always separates them; in hf's 184 dumps every trailing hyphen wanted keeping, so the join keeps it and says why. Whatever test you write, window it to the junction — never to the whole accumulated string, which already contains the option head and matches every token test (see [`join-window`](../decisions/authoring.md#join-window)).
- A mid-word split with no hyphen at all (`hugg ingface`) cannot be rejoined mechanically — translate the line correctly by hand and leave the source alone.
- A marker split across lines (`[alias:` at end of line, the name on the next) needs lookahead plus consuming the continuation line; otherwise the alias is lost (an `R-03` gap) and its text pollutes the tip. A marker standing alone on the next line belongs to the previous entry.

### Usage continuations that name other invocations

A `Usage:` block often lists several invocation shapes, one per line:

```
Usage: pyenv install [-f] [-kvp] <version>[:<alias>]...
       pyenv install [-f] [-kvp] <definition-file>[:<alias>]
       pyenv install -l|--list [--bare]
```

Every indented line starting with the command word is a separate usage shape, not a wrap of the first — record each as its own `usage`, and never let one leak into the description.
A tip reading `pyenv install [-f] ...` is a usage line misfiled as prose (pyenv shipped exactly that before the fix).
The description starts after the usage block, at the first non-indented paragraph.

## Aliases the `--help` hides

A tool often accepts spellings its `--help` does not print — `hide = true` aliases, or short forms the local build merged away.
The parser still accepts them, so they belong in the manifest (`R-03`); `--help` is not the collection surface for them.
The tool's own reference is: each option is a heading that carries every spelling, so an option documented as `--config-setting`, `--config-settings`, `-C` offers all three.
Harvest the headings for every command, then let the CLI decide each one:

```
<cmd> --config-settings     # error: a value is required for '--config-setting <...>'
                           #   → accepted; the message names the canonical option
<cmd> --no-such-flag       # error: unexpected argument '--no-such-flag' found
                           #   → refused; delete
```

The error naming the canonical option is the acceptance signal; `unexpected argument` is the refusal signal (`R-06`).
Neither source alone settles it — a docs heading can outlive the code, and `--help` hides live spellings.
Command aliases take the same probe one level out: `uv python i --help` answering `unrecognized subcommand` deletes the alias whatever older releases accepted.

## The subcommand probe

For each command in the manifest — down to 2 levels, which covers nearly every tool — run:

```
<cmd> <sub> --help | grep -E 'AVAILABLE COMMANDS|^Commands:'
```

The pattern is a sample, not the rule — `R-07` is: *a section whose name ends in `COMMANDS`*.
One tool groups its pages as `CORE COMMANDS` / `GENERAL COMMANDS` / `TARGETED COMMANDS` / `ADDITIONAL COMMANDS`, so the sample pattern finds nothing while the manifest looks complete.
Grep `COMMANDS\s*$` and read the entries as bare command words.

The same page usually carries an **`ALIASES` section** listing the command's shortcuts — the spellings `R-03` requires that no flag list shows.
Harvest it per page (see §Aliases are scoped to the page that lists them).

**Direction 1 — a hard check.** Output present → the manifest **must** have a non-empty `next`.
Output absent while the manifest has none → correct.
This one-line check catches the "parent command modeled as a leaf" defect (5 instances in `gh` alone), which `compare-json` and `validate-completion` both pass silently because they only check internal consistency.

**Direction 2 — not a verdict.** Output absent while the manifest **does** have `next` proves nothing, because `next` is deliberately a **dual-purpose field**:

| `next` holds | Example | Engine behaviour |
| --- | --- | --- |
| subcommands (enter a context) | `git remote` → `add` / `remove` / `rename` / `set-url` | moves into a new context |
| candidate values for one slot | `volta list [TOOL]` → `all` / `node` / `npm` / `yarn` / `pnpm`; `stripe resources` → 89 API resource names | fills the current slot |

So judge this direction from the command's own `usage`:

- `usage` **has a positional placeholder** (`<TOOL>`, `[TOOL]`) → the `next` entries are candidate values. Legitimate, leave it alone.
- `usage` has **no placeholder** → the `next` entries claim to be subcommands, so verify.

### Knowing when collection is complete

The traversal above tells you how to walk the tree; it does not tell you that you have walked all of it.
Nothing in the gates does either — `compare-json` and `validate-completion` compare the manifest against *itself*, so a manifest with 21 of 48 commands, or with 61 subcommands carrying no options at all, passes clean.
That is not a hypothetical: `glab` shipped that way.

So close the loop mechanically.
Emit what you collected to a scratch file (`WIP/<tool>/tree.json`), then diff it against the manifest as **sets of spellings**:

```
collected command spellings  −  manifest name+alias  =  Missing   (must be empty)
manifest name+alias          −  collected            =  Extra    (must be empty)
```

Both directions matter: `Missing` is the forgotten subtree, `Extra` is an entry the CLI does not accept (see `R-06`).
Run the same diff for options at every level, and compare the *alias set* of each entry, not just the name — a command modelled without its `[aliases: ...]` line shows up here and nowhere else (`R-03`).

The scratch directory is working material: it stays until the operator says otherwise (`R-20`, [`working-files.md`](working-files.md)).

### Save the pages you read

Recommended, not required — but the kind of recommendation that pays for itself on the second read.
As you traverse, save each `--help` page to its own file under `WIP/<tool>/help/` (one file per page, e.g. `root.txt`, `config.txt`).
The next pass — yours when a gate reports something odd, or the operator's during review — starts from the evidence instead of re-running the CLI.
This is the same directory `R-20` already keeps until the operator says otherwise, so there is nowhere extra to clean up; see [`working-files.md`](working-files.md) for the layout.

### Aliases are scoped to the page that lists them

Harvest `alias`/shorthand **per command page**, never into one global table.
The same spelling belongs to different long forms on different pages: `glab` uses `-a` for `--all` on one page and `-a` for `--assignee` on another, and `-e` for both `--epic` and `--time-estimate`.
A global map merges those and produces two options in one context claiming the same short form.
`compare-json` catches the collision — but only after you have written the entries, and the fix is to re-scope, not to rename.

### Ground-truth verification
Use it in either direction, and whenever a `next` child is suspect:

```
<cmd> <child-from-manifest> --help
  prints the PARENT's help  →  that "subcommand" does not exist (defect)
  prints the child's own help / argument docs  →  it exists (or it was a value all along)
```

`netlify teams list` is the worked example: the manifest invented a `list` under the leaf command `teams`, and `netlify teams list --help` quietly prints `teams`' own help instead of failing.

A parent-help reprint is only half the verdict: the help pager may simply lack a page for a real command.
Before deleting on that signal, check the dispatch table and the handler behind it — an arm plus a defined function with a real body means the command exists and only its documentation is missing (76 such cases in one tool, all kept).
Delete only when no dispatch path and no implementation back the name.

### A shared arm line is not one command

A hand-written dispatcher often lists several spellings on one `case` arm.
Whether they are aliases or distinct commands is decided by the action, mechanically: an action that names its handler literally (`___x_cmd_git_commit "$@"`) runs the same code for every spelling — true synonyms, one entry.
An action that expands per spelling (`___x_cmd_hub_"$op"`, `___x_cmd_ajv_"$op"`) runs one function per name — distinct commands that happen to share a line; collapsing them loses commands no gate will report.
Check for `$op` (or the framework's equivalent per-name expansion) before merging.
`_`-prefixed spellings are the author's own plumbing marks, never user input — drop them outright (`R-04`, shell-library entry points).

### Reading the result

If `MISSING` holds the CLI's primary name while `EXTRA` holds the manifest's alias, the two sides simply disagree on which form is longer — **this is not a defect and needs no fix**.
`name` / `alias` is a data-model distinction with no hierarchy; "longest wins" is only a `sort-json` convention, and a CLI's own primary form may well be the shorter one.
The only real requirement is that **both forms appear in `usage`**, so the user recognises either.
`psc.on` in `hooks.lua` refers to the `name` field, but that is likewise just an identifier.

### Option-dispatched command chains

Some CLIs dispatch subcommands through an option value rather than as bare words (`fresh --cmd daemon list`).
The words after the option look like subcommands but are not: the ground-truth probe is the bare form — `fresh daemon list` opens a file in the editor, so root `next` stays empty and the chain is modelled under the option's own `next`.

Static navigation reaches exactly one level under such an option: once an option value is consumed, the engine resets to the nearest command context (see [`design/completion.md`](../design/completion.md) §Resolve), so the menu completes `--cmd <TAB>` but never `--cmd daemon <TAB>` on its own.
Record the deeper levels anyway as nested `next` / `option` (the schema allows both on a value item) — the data is truthful and hook-mountable — and surface them with a hook only if the depth is worth it: `psc.on({ option = "--cmd", multiple = true })` plus token inspection reaches every level the static tree cannot.
Agree that scope with the operator before writing either half.

### An option diff must subtract the global set first

Build the global set once — from the top-level `--help`, or from the tool's dedicated global options list (`minikube options`) — then subtract it from every per-command diff.
clap repeats the same global flags in **every** subcommand's `--help`, so a naive per-command comparison reports each of them as missing at every level, and the spurious entries swamp the real ones.
The reverse failure is worse than the inflated count — seeing the globals as `EXTRA` in every command, the cheap reaction is to delete them from the manifest, and [`D16`](../decisions/authoring.md#d16) says they belong in `global_option` and there alone.

### Placing `--version` / `--help`: probe the level, not the help text

A top-level `--help` that lists `-V` says nothing about whether subcommands accept it — clap reprints the flag under every subcommand either way.
Run the flag under each subcommand and read the result:

| Result | Ruling |
| --- | --- |
| exit 0, version printed | **accepts** — accepted (nearly) everywhere goes in `global_option` |
| `unknown argument` / `unexpected argument`, non-zero exit | **rejects** — root-only, stays in root `option` |

`global_option` is offered at the root too (see [`design/completion.md`](../design/completion.md) §`option` vs `global_option`), so the global placement costs root nothing.
Accepted under only a few subcommands → each of those subcommands' own `option`, per `R-11`.
On a tool with no subcommands the placement is inert — leave it as is.

Worked contrast: zoxide 0.10.0 prints its version under every subcommand (`zoxide add --version` → `zoxide-add 0.10.0`, exit 0), so its `--version` is global; git 2.56.0 refuses it below root (`git log --version` → `fatal: unrecognized argument`, exit 128), so its `--version` stays root-only.

While probing, record the version into `config.json` `version` — it is the baseline the next update diffs against.
Refresh it whenever you re-verify the completion against a new CLI release.
What counts as "the version" is a judgment call:

| Version output | Record |
| --- | --- |
| Full name plus number (`git 2.56.0`/`Scoop v0.6.0`) | the whole line, trimmed — **preferred**, keep the tool's own name in front; drop a trailing platform tag (`on "linux_x64"`) — it identifies the machine, not the build, and false-positives on cross-platform updates |
| Bare number only (`1.2.3`) | the number as-is |
| No version flag, but installed via a package manager | query the manager for the probed binary (`brew list --versions <pkg>`, `pip show <pkg>`, `npm ls <pkg>`…) — first confirm `which <cmd>` resolves to that install, or the number may describe a different copy; record per the same rules above. A manager lookup is evidence, not invention |
| No version output at all, and no manager owns the binary | **ask the operator** which string to record — never invent one; with their word, `0.0.0` is the standing placeholder for "no version source" |

"When in doubt, ask" (`AGENTS.md`) applies here: a guessed version poisons every future drift comparison, while `0.0.0` honestly marks "nothing to compare against yet".

## Enumerating option values

Help text often lists an option's allowed or example values — recognize them and map them to `next: [...]`:

- "Possible values: a, b, c" / "Valid values: ..." / "Values: ..."
- parenthesized groups: `(a | b | c)` or `(a, b, c)`
- bracketed groups: `[a|b|c]` or `[a, b, c]`
- a list right after the option's placeholder in the usage line

Even when the help shows no such list, if an option's value has a recognizable shape
(status codes, numbers, IDs, time formats), add a few **representative example values**
via `next: [...]` so users can pick one instead of typing blindly (e.g. `--status-code` → `[200, 404, 500]`, `--since <TIME>` → `["2024-01-01", "1h"]`).
Keep `next: []` only for genuinely free-form values.

**`[possible values: a, b, c]` is the most reliable source of all.** clap writes the allowed set inline in the option's own description line — it is machine-generated, not prose, so it cannot mislead the way a `(a|b)` or a trailing list can.
Extract it into `next: [...]` per `R-08` and add the trailing tip line `Possible values: a, b, c` (English) / `可能值: a, b, c` (Chinese).
Element order is not prescribed — `sort-json.ps1` reorders every named array on every run, and the tip line is display text (see [`D35`](../decisions/authoring.md#d35)).
A `--help` line carrying `[possible values: ...]` always yields a non-empty `next`.

### When the help has no `[possible values]`

`R-08` covers clap's inline enumeration.
Most CLIs never give one.
In this order:

1. **A rejected value reveals the validator.** Submit a deliberately wrong value and read the error. `ruff rule E` → `error: invalid value 'E' for '[RULE]'`, `tip: a similar value exists: 'E999'`. The error names the slot and shows the expected shape — here, a full rule code rather than a prefix.
2. **A metadata subcommand with a machine-readable format.** `ruff rule --all --output-format json` returns 971 rules, each carrying `code`, `linter` and `name`. Look for `list`, `--all`, `-o json`, `--format json` — or a self-completion entry point (`<cmd> --complete`), which echoes the command's own flags and value candidates. This is the authoritative enumeration when the help has none, and it is machine-generated, so it cannot mislead the way prose can.
3. **Probe each candidate before writing it.** Deriving a set from a code table and never running the CLI is how a wrong set lands: a value the CLI silently ignores looks identical to a valid one until you try a member that does not exist.
4. **An error that enumerates the set.** Some CLIs answer a bad value with the full candidate list (`Unknown package type 'bogus'. Valid types: plugin, theme, language`). Copy the list — it is the CLI's own enumeration, as authoritative as item 2 — then still probe each member per item 3 before writing it.

**Validity is per slot, not per string.** `E` is a legal `ruff check --select` selector and an illegal `ruff rule` argument.
Legality depends on the slot a value fills, so when candidates move between options — or a hook's set moves into a manifest — verify each one against *that* option.

## Determining whether an option takes a value

`R-01` makes it mandatory: a value-taking option declares `next`, a boolean must not.
Guessing wrong is a **silent** failure — no gate reads it, the menu offers the flag, and the user's next keystroke brings candidates for a slot that does not exist.

Some tools print the shape for you (`--opt <VAL>`, `--opt=<VAL>`), so read it straight off the flag line.
Many do not: `glab` prints **no placeholder at all** for any of its 333 flags (`-F --field Add a parameter of inferred type.`), so `--help` alone cannot answer the question.
Three sources, in order:

1. **A placeholder in `--help`** — `-A, --after-context <NUM>` means value; a bare `-s, --case-sensitive` means boolean.
2. **The tool's own reference** — man page, `--help all`, online docs: an `ARGUMENTS` section or a usage line that spells out the value.
3. **Invoke it with no value** — the decisive source when 1 and 2 are silent:

   ```
   <cmd> <sub> --flag            # no value
   ```

   | Result | Ruling |
   | --- | --- |
   | `a value is required for '--flag <VAL>'` (wording varies by framework) | **value-taking** — declare `next` |
   | accepted (the flag simply took effect) | **boolean** — declare no `next` |
   | `unknown argument` / `unexpected argument` / `unrecognized ...` | **not a flag at all** — delete (`R-06`) |

Run the probe against a page that lists the flag and that terminates quickly.
Two caveats from practice: an interactive or network-bound command (`glab auth login --device`) hangs until timeout, so classify those from documentation instead; and a probe that errors for an unrelated reason (no auth, no repository) still tells you the answer, because the argument check happens during parsing, before the command runs.

To test acceptance without side effects, append `--help`: `<cmd> <sub> --flag --help`.
On a framework parser (clap, cobra, …) an unknown flag still fails at parse while a known one prints help and never executes — no directories created, no servers started, nothing applied — because the framework intercepts help before dispatch and a known option never consumes `--help` as its value, so the probe stays discriminating.
On a hand-written dispatcher none of that holds (see §Probe containment below) — qualify the tool first, then probe.
Read the error text, not the exit code: when the flag is consumed and the command then complains about a missing positional, the flag is accepted — only an error naming the flag itself is a rejection, and a usage dump alone decides nothing.

### Probe containment

`R-22` and `R-23` exist because the killer is transitive: it lives N hops away in the tool's own code, not in the harvest script, so reading the harvest script (D38) cannot see it — only reproduction reveals it.
The recorded case ([`D39`](../decisions/authoring.md#d39), the project's second tree-wide wipe) ran a `--help`-appended probe into a dispatcher arm with no `-h` handling; the tool executed, printed a zero-exit non-help output, and removed CWD itself.
Four links, none owned by the author; the probe exited 0 throughout.

Three laws, in priority order:

1. **Scratch CWD, always (`R-22`).** Set the shell `workdir` (or subprocess `cwd`) to a scratch directory for every probe run — `/tmp/opencode/<tool>/` or `WIP/<tool>/` — never the repo root. Containment does not judge the probe; it bounds the loss when the judgment is wrong. Had the probe above run in scratch, the loss would have been scratch.
2. **Qualify the parser before batch-probing (`R-23`).** A binary that is a shell script, or a dispatcher read that shows `case` arms without `-h`, is hand-rolled: `--help` reaches it as data. Read one dispatcher and one leaf for `-h` handling; whatever lacks it goes source-only (usage lines, header comments, `case` arms — the tool's own reference per §Aliases the `--help` hides), with no live probes for that subtree.
3. **Canary the first probe of each new shape (`R-23`).** A canary is a scratch directory holding a few files plus a `.git`. Run the shape once, diff before/after, and read the output: help-shaped (NAME/DESCRIPTION for that command) means proceed; execution output — especially a zero-exit non-help output — means stop and go source-only. The same check applies to hook-producer queries before registering them (`R-17`): prove print-and-exit in the canary first.

A value-taking option whose shape is genuinely unknowable still declares `next: []` — the placeholder in `usage` is what may be omitted (`authoring/manifest.md`).

## `separator` — prove the split, then declare it

Help text saying "comma-separated" is not evidence.
Three probes:

```
<cmd> --opt X,Y      → accepted
<cmd> --opt X Y      → rejected
<cmd> --opt X,BOGUS  → names only `BOGUS`
```

The third is decisive.
If the bad member is reported on its own, the CLI tokenises on the comma, so `separator: ","` is required.
If `X,BOGUS` is rejected as one unknown value, the CLI does not split and declaring `separator` would be wrong.

Declare it on the value-taking option and show the repeated shape in `usage` (`--select <RULE_CODE,...>`).
`compare-json` checks only the form — comma versus pipe, via `usageSeparator` — and never whether the CLI actually splits, so both directions are silent wrong: declaring it when the CLI does not split, and omitting it when the CLI does.

**Prose reading "comma-separated or repeat the flag" is evidence of `repeat`, not `separator`.**
Several CLIs (`glab`: *"Multiple labels can be comma-separated or specified by repeating the flag"*) offer both spellings, which reads like a split but is not one — submitting `a,b` as a single value is refused and the flag is repeated instead.
Run the same three probes; when the third shows the CLI does **not** tokenise on the comma, declare `repeat: 99` and no `separator`.
That the option repeats *at all* is answered the same way, by prose or by a probe.

**A framework's type word is not evidence either.** One prints `strings` on every list flag, which means the flag repeats *and* its value is comma-split at parse time — two different claims, neither readable off the type word.
Run the three probes and declare what they show; where both hold, `separator` and `repeat` are both true.
That the same framework's completions in this repo carry `repeat` alone is a record of what the probes found, not a rule about the framework.

## Proving what a flag does

Help text saying "skip tests" does not tell you whether it skips compilation, execution, or both.
Two flags with similar descriptions often differ in what they suppress — `skipTests` compiles test sources but skips execution, while `maven.test.skip` skips compilation entirely.

**Make it fail, then see which flag suppresses the failure.** Create a build that fails for a known reason, then run it under each flag:

```
<cmd> test                           → BUILD FAILURE  (baseline: the failure reproduces)
<cmd> -DskipTests test               → BUILD FAILURE  (still compiles; only runs are skipped)
<cmd> -Dmaven.test.skip=true test    → BUILD SUCCESS  (compilation is suppressed too)
```

The flag that turns FAILURE into SUCCESS is the one that suppresses the compile step.
The baseline run is essential — without it you cannot tell whether a SUCCESS means "the flag worked" or "the failure never reproduced in the first place."

### Trust the probe before trusting the result

Before concluding that a producer is broken, confirm the probe itself is correct.
Submit a value that must fail and verify it does:

```
<cmd> --projects no-such-module  → fails   (probe is sound)
<cmd> --projects child           → succeeds
```

If the negative control passes, the probe is wrong, not the producer.
A probe that cannot fail cannot distinguish anything, and a sound conclusion drawn from it is wrong.

## Alternative patterns

- If the tool uses a `help` subcommand instead of `--help`, use `<command> help <subcommand>`.
- If the tool advertises a fuller help surface, harvest it too. Dart's own help says "Run `dart help -v run` for details" — the verbose pages revealed dozens of options the terse ones hide. Union by spelling; where both wordings exist, keep the one with the fuller enum set and leave the rest alone.
- If `--help` output is sparse or missing option descriptions, check official docs.
- If updating an existing completion for a new version, check changelogs and release notes — see [`maintenance.md`](maintenance.md).
- **If the tool is not installed locally**, fetch its docs instead: official website, GitHub README, or `--help` output shown in the project's docs or release notes. Do not skip a subcommand's options just because you can't run it — dig until you have them.
- **A registry 404 is not "cannot be installed."** Many tools ship as scoped packages under a different name (`rspack` → `@rspack/cli`, `rsbuild` → `@rsbuild/core`, `ionic` → `@ionic/cli`), so a bare-name lookup fails even though the tool is installable. Look up the real package name in the tool's own docs, then `npm view <pkg> bin` — that returns the executable the user actually types, which is what `config.json` `alias` must record (`R-14`). Only then is a skip legitimate. See [`D15`](../decisions/authoring.md#d15).
