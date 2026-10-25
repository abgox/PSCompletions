# The Manifest

The manifest as data: what the generated files look like, what each field means, and how text is formatted.
Field *semantics* and engine behaviour are defined in [`../design/completion.md`](../design/completion.md); the strict, actually validated definition is [`../schema/completion-manifest.en-US.json`](../schema/completion-manifest.en-US.json).
Read the schema first — this file is the practical reading of it.

Rule statements are `R-xx` in `../AGENTS.md`.

## Scaffold

`./scripts/create-completion.ps1 <command>` generates:

```
completions/<command>/
├── config.json           # { "id": "<uuid>", "language": ["en-US", "zh-CN"] }
└── language/
    ├── en-US.json        # template content, needs a full rewrite
    └── zh-CN.json        # template content, needs a full rewrite
```

The script creates **static completions only**.
For dynamic completions, hand-write `hooks.lua` — see [`hooks.md`](hooks.md) and `../design/hooks.md §9`.
There is no automatic hooks generation; every hook is bespoke.

Before writing, skim a few existing completions to match the house style — e.g. `completions/git/` (deep nesting, hooks), `completions/psc/` (dynamic tips via hooks), or a simple tool like `completions/fd/`.

## Minimal example

```json
{
  "meta": {
    "url": "https://example.com",
    "description": ["A tool to do something"]
  },
  "next": [
    {
      "name": "init",
      "tip": ["Initialize a new project."]
    },
    {
      "name": "build",
      "alias": ["b"],
      "usage": ["b|build [OPTIONS]"],
      "tip": ["Build the project"],
      "option": [
        {
          "name": "--output",
          "alias": ["-o"],
          "usage": ["-o, --output <DIR>"],
          "tip": ["Output directory"],
          "next": []
        }
      ]
    },
    {
      "name": "deploy",
      "usage": ["deploy <ENV>"],
      "tip": ["Deploy to a target environment."],
      "option": [
        {
          "name": "--tag",
          "usage": ["--tag <TAG>"],
          "tip": ["Image tag to deploy."],
          "next": []
        },
        {
          "name": "--dry-run",
          "tip": ["Preview the deploy without applying."]
        }
      ],
      "next": [
        {
          "name": "status",
          "tip": ["Show deployment status."]
        },
        {
          "name": "rollback",
          "usage": ["rollback <VERSION>"],
          "tip": ["Revert to a previous version."]
        }
      ]
    }
  ],
  "option": [
    {
      "name": "--version",
      "alias": ["-v"],
      "usage": ["-v, --version"],
      "tip": ["Show version."]
    },
    {
      "name": "--dry-run",
      "tip": ["Dry run without making changes"]
    }
  ],
  "global_option": [
    {
      "name": "--help",
      "alias": ["-h"],
      "usage": ["-h, --help"],
      "tip": ["Show help."]
    },
    {
      "name": "--verbose",
      "tip": [
        "Enable verbose output.",
        "Can be repeated twice for more detail."
      ],
      "repeat": 2
    }
  ]
}
```

**Reading it:**

- `build`'s `option` holds options specific to the `build` subcommand (e.g. `-o`).
- `build` has **no `next` field** — it is a command. See `R-01` in `../AGENTS.md`.
- `--output` (an option) **does** have `next: []` — it takes a value but has no static candidates. This is correct.
- `deploy` shows a **nested scenario**: a command that has both `option` (its own flags like `--tag`) and `next` (its sub-subcommands like `status`, `rollback`). Note that `deploy` itself has no `next: []`, `--tag` has `next: []`, `--dry-run` has no `next` (boolean, no value), `status` has no `next` (leaf command), and `rollback` has no `next` (its value is expressed by `usage <VERSION>`, not by `next`).
- Top-level `option` is root-level options, available before any subcommand.
- `global_option` is appended at every level. A flag that **many** subcommands share *verbatim* belongs here even when the root itself rejects it; when only a **few** take it, or the entries differ per subcommand, put it on each of those subcommands' own `option` instead. The trade-off and its measurement: [`D16`](../decisions/authoring.md#d16).
- `repeat: 2` means the option can appear up to twice; use `repeat: 99` only when the exact limit is unknown.
- **A single-command tool has no `next`.** Put its flags in root `option` and record its positional arguments in the slot inventory; the manifest has no root positional field, and inventing a root `next` entry for them would make the menu treat a value as a command. Native completion owns path positions.
- Empty arrays must be removed entirely — do not keep `"option": []`.
- **When adding options to a command that has no `option` field yet, create it.** Some commands (like `git bisect`) are modeled with only `next` (subcommands) and no `option` field. When you discover options that belong to such a command, add an `option` array and populate it. This is a practical authoring note — the rule above still applies: if you end up with an empty `option` array, remove it entirely.

## Reference completions

When you want to see how a finished completion looks end to end — manifest shape and `hooks.lua` alike — start with these before browsing the other completions.
Each is standard in the aspect named; read it for that aspect, not as a template to clone:

- `git` — deep `next` nesting, command/option aliases, ref-shaped dynamic candidates
- `jj` — `format="json"` reads, `mount_items` reuse
- `cargo` — structured command output first (`cargo metadata`), file fallback, version tips
- `psc-link` — Use callback functions in the `tip` to implement lazy loading
- `scoop` — `json_batch`/`glob` over manifests, `shell=true` shims
- `brew` — many producers over one `run_batch`, root `next` mount
- `gh` — one JSON shape per producer, batched sibling queries, no retries
- `mise` — `--json` machine output, `tool@version` candidates
- `uv` — installed-subset producers matched to the slot (`uninstall` takes installed only)
- `hf` — one flag with per-command value sets (`--flavor` under jobs vs Spaces hardware, AND-anchored option specs), machine-readable (`-q`) list queries feeding sibling slots

Only after these stop answering the question at hand, broaden to the rest of `completions/`.
For hook patterns specifically, `../design/hooks.md` §9 keeps its own list — same files, organized by pattern rather than by completion.

## `config.json`

```jsonc
{
  "id": "<uuid>",
  "version": "git 2.56.0",
  // "hooks": true,
  // "alias": [...],
  "language": ["en-US", "zh-CN"]
}
```

- `id` (required) — random UUID generated at creation by `create-completion.ps1`, never changes. The engine uses it to detect upstream renames.
- `version` (required) — the CLI version this completion was written and checked against: the baseline for future updates (see collecting-info for extraction rules: preferred form, bare numbers, package-manager fallback, and the `0.0.0` placeholder when no version source exists). Nothing parses it. When a newer version is installed, re-check the completion and refresh this field.
- `language` (required) — language array, corresponding to files in the `language/` directory.
- `hooks` (optional) — `true` means dynamic hooks are enabled by default (install writes no `enable_hooks` entry, since absence already means enabled); `false` means `hooks.lua` exists but is disabled by default (install writes `enable_hooks=0`; users enable it with `psc completion <name> enable_hooks 1`). Omit when there is no `hooks.lua`.
- `alias` (optional) — alternative command names that trigger this completion.
  - **The directory name is the command the user actually types.** Do not name a directory after a project's full name when users type a shorter binary (`hx`, not `helix`; `python3`, not `python`) — the directory list is read by users, so it must match their input.
  - **If not set**, the directory name is used as the trigger name.
  - **If set**, the directory name is **ignored** — only the names in this array are used, so **the directory name must be repeated inside it**. An `alias` that omits it silently kills that trigger.
  - **Only add `alias` when upstream officially recognizes more than one name.** Check what upstream actually says — do not reason from the project's full name:
    - `hx` has **no** `alias`. `helix` is only the product name (`hx --version` reports "helix 25.07.1"), and no platform installs a `helix` command, so an alias would invent a trigger and could hijack a user's own command of that name.
    - `python3` **does**: PEP 394 makes `python3` canonical on POSIX, while the CPython Windows docs recommend `python` and describe `python3` as "not meant to be widely used or recommended". Both are official, on different platforms.
  - When only one name is officially valid, **omit `alias` entirely** and let the user configure their own triggers after install (`psc alias add <name> <alias>...`) — guessing aliases is how trigger conflicts get created.
  - **Omit `.cmd`, `.exe`, `.bat` suffixes** — just use the command name (`git`, not `git.exe`).
- **`@` in a directory name is an ownership marker, never a trigger** — `AAA@author`, `AAA@local`, `AAA@uutils`. Directory names must be unique, so this is how two same-named tools — different authors, or different implementations — are told apart.
  - **The part before the `@` is the command name, character for character.** Do not force a case: most commands are all lowercase, but a command genuinely spelled `N_m3u8DL-RE` keeps its capitals, because the directory name serves the user's input rather than typography.
  - **The part after the `@` names the source, never the platform**, following the source's own spelling and case. Do not write `@Linux` / `@MacOS` / `@Windows`. A completion describes an *implementation*; the platform it runs on is an unstable axis — a platform may ship one implementation and later another — and uutils itself runs on every platform, which is exactly why the existing splits are `@uutils` and not `@Linux`. When two *projects* provide the same command on different platforms (`cut` as BSD vs GNU), name the project: `cut@BSD`. uutils spells itself lowercase (`cut@uutils`); GNU and BSD spell themselves uppercase (`cut@GNU`, `cut@BSD`).
  - **Once a command has variants, every variant carries its suffix — there is no bare "default".** A bare name hides which implementation it documents, and every default is somebody's subjective choice. A user installs exactly the variant matching their system. Keeping the suffix single-valued also removes the need for a double suffix: a macOS user running uutils wants "uutils's `cut`" (`cut@uutils`), not "macOS's `cut`".
  - **A directory whose name contains `@` MUST declare `alias` with the real command name** — triggers are claim-ordered (a word two completions claim belongs to the later claim, `design/psc-cli.md` §6.2), and nobody types `AAA@author`, so without an alias the completion is unreachable. This does not contradict the rule above: there `alias` carries another *officially recognized* name; here it carries the *only trigger that works*. The marker itself can never collide with a real author handle — it is a label for humans, and no component of the engine splits or matches on `@` (verified across all 46 Rust sources), so the engine treats the whole directory name as opaque. `@` is also a legal path character in URLs and on both filesystems.
  - `@local` marks a local draft (gitignored, see `.gitignore`). Unlike a dot-directory it is visible from a plain `ls completions/`.

## Field semantics in use

For the full definitions of `meta`, `next`, `option`, `global_option`, and `info`, see [`../design/completion.md`](../design/completion.md).
The manifest's own `config` field is covered below.

### Per-completion config (`config`)

An array of tunable settings for this command.
Each entry is `name` + `value` + `tip`, plus an optional `values`:

```json
{
  "config": [
    {
      "name": "max_commit",
      "value": 30,
      "values": [-1, 30],
      "tip": [
        "The maximum number of commits the hook parses. Default to 30.",
        "Use -1 to parse all commits, which slows loading."
      ]
    }
  ]
}
```

The engine merges three layers, later overriding earlier: global config → these defaults → the user's override (`psc completion <name> <key> <value>`).
A hook reads the result as `psc.config`, where every declared key always has a value, so no `or` fallback is needed.
`values` is what gets offered when the user completes `psc completion <name> <key>` — it is discovery surface, not documentation.

**A `name` starting with `enable` or `disable` is machine-constrained.** The schema forces `value` to `0` or `1` and `values` to exactly `[0, 1]`.
Any other name accepts `string` or `number` freely.

**Do not reach for it by default.** Every key lands in `psc completion` for every user of this completion, and nothing will flag an unnecessary one.
Adding a key requires asking the author first — `R-15`.

**When it is justified**: all three existing uses are the same shape — a knob controlling **how much work a hook does**:

| Completion | Key | Tunes |
| --- | --- | --- |
| `git` | `max_commit` | how many commits the hook parses (`-1` = all, slower) |
| `scoop` | `exclude_buckets` | which buckets the hook scans |
| `scoop-install` | `exclude_buckets` | same |

The shared factor is that the right value genuinely varies per user *and per machine* — commit history depth, bucket count — while the cost of doing more work is real.
If a proposed key can be phrased as a user *preference* about display or behaviour, it belongs in the `menu` config group, not here; if a CLI flag already covers it, it is an `option`.

> **Two different orderings — do not confuse them.** In the JSON structure, `name` is the longest (canonical) form and `alias` lists the remaining forms **longest → shortest** (the data model: `name` is the item's identity).
> In the `usage` line, the same forms are shown **shortest → longest** (`-f, --force`, `rm|remove`) — a display convention that matches CLI `--help`.
> Keep them as they are; the `usage` order is not a mistake.
> If a `name` or `alias` contains spaces, wrap it in quotes: `"hello world"` or `'hello world'` (see the schema for validation).
>
> **"Longest" is a convention, not a claim about the tool.** `../scripts/sort-json.ps1` puts the longest form in `name` on every run, so this is guaranteed for you and a `psc.on` target can always be written as `name` — but nothing is *wrong* when a manifest's `name` is the tool's shorter form (`k3d config create` vs the CLI's `init`, `svn praise` vs `blame`).
> `name` / `alias` carries no hierarchy; the CLI's own primary name may well be the shorter one.

**Boolean options** (no value needed): do not include `next`.
A boolean the CLI accepts in negated form is **two entries** (`--foo` / `--no-foo`), each with a plain-form `usage`; the `--[no-]` notation is that form, not a single-entry exception.
Acceptance is established by that notation or by invocation (`R-06`) — a name derived from the prefix alone is not evidence.
**A tool-wide `--no-` switch is still per option.** Some CLIs accept `--no-<flag>` for every reversible boolean; that is a probe per boolean, not a derivation rule — curl 8.23.0 accepted 100 of 121 probed forms and refused 21 with `the given option cannot be reversed with a --no- prefix`. Add a negative entry only for the forms that answered the acceptance signal.
The negative entry's `tip` states what it disables; when the reference documents only the positive direction, use the mechanical sentence `Disable --foo.` (Chinese `禁用 --foo。`) instead of repeating the positive description, which would misdescribe it.
See [`D33`](../decisions/authoring.md#d33) for the trade-off.

**Options that take a value**: use `next: [...]` when you know the value's shape (allowed values or representative examples), otherwise `next: []`.
**A value-taking option must declare `next` regardless of whether it has a `usage` placeholder** — the `compare-json` check keys on `usage <...>`, so an option with only a tip (e.g. `dotnet --roll-forward`) would otherwise be treated as a boolean switch and go unflagged.
A positional alias recorded as an option (`-r` for `<REVSETS>`) is value-taking too: give it both the `usage` placeholder and `next`, or the menu stops completing after it.

**A closed enumeration is worth listing** even though every value is knowable at authoring time — the test is whether the user would otherwise have to know an unfamiliar name, not how many entries there are.
A probe reporting "has `next` but no Commands section" is then expected noise, not a defect, provided the `usage` has no positional placeholder.
Reasoning and evidence: [`D13`](../decisions/authoring.md#d13).

**A REPL's commands are not subcommands.** A tool whose real surface is an interactive prompt (`sqlite3`'s `.tables`, `.schema`) does not get that surface as root `next`, because the prompt is not argv.
When a flag takes a command string (`sqlite3 -cmd '.tables'`), the dot-commands are valid whole values for that option, so they belong in its `next`; the interactive prompt itself stays uncompleted.
Record the distinction in the slot inventory: the flag is `next`, the prompt is `none`.

**Repeatable options**: add `"repeat": N`, where N is the max number of times the option can appear.
`repeat` counts appearances of the option itself — the menu keeps offering the flag until the count is reached — and says nothing about the value's shape (a separator-joined list is `separator`'s job, below).
This is not a hook's `multiple`, which says one occurrence accepts more than one value or positional argument; they are different axes, and a repeated option needs no `multiple` because each occurrence creates a fresh slot. See [`../design/hooks.md`](../design/hooks.md) §`multiple` is not `repeat`.
A boolean flag carries `repeat` only when the CLI tolerates the repetition (e.g. `-v -v`); use `99` only when the limit is unknown or effectively unlimited:

```json
{
  "name": "--exclude",
  "alias": ["-e"],
  "usage": ["-e, --exclude <path>"],
  "tip": [
    "Exclude a path (can be used multiple times)"
  ],
  "repeat": 99,
  "next": []
}
```

For example, `-include a -include b` is `repeat`; a command like `apt install a b` is the `multiple` shape and belongs to the hook, not to `repeat`.
A count option (`action="count"`, `-v -v`) carries its documented cap as the number — pipx documents `--quiet` 2 and `--verbose` 3 — rather than `99`.

**`next` for options** — prefer `next: [...]` over `next: []` whenever you know the value's shape well enough to give representative examples; keep `next: []` only for genuinely free-form values.
Every item in `next` is an object with a `name`: `"next": [{"name": "json"}, {"name": "text"}]`. A bare string (`"next": ["json"]`) fails schema validation; `sort-json.ps1` orders the objects by name.
If `hooks: true` is set, dynamically generated completions are **appended** to the static array, not replaced.
See [`../design/completion.md`](../design/completion.md) for the full `next` semantics.

**`separator` for list values** — an option whose value is a separator-joined list (`--exclude a,b,c`) declares `"separator": ","` (any non-empty string except whitespace or `=`; typically `,` or `;`).
Requires `next` (boolean flags must not carry it).
Selecting a candidate replaces only the current segment and adds **no** trailing space — the user types the separator to continue, Space to finish.
`usage` should show the shape (`--exclude <A,B,...>`).
See [`../design/completion.md`](../design/completion.md) for the full semantics.

## Duplicates

An option counts as a duplicate only if it is **fully structurally identical** to a `global_option` entry — same `name`, `alias`, `tip`, `usage`, `example`, `separator`, `next`, `option`, and all nested substructure.
If the description or `next` differs in any way, they are **different** options: when you reach a subcommand context, the module uses the subcommand's own `option` (it overrides the parent/root `option`, never `global_option`).
Fix a duplicate by removing the subcommand or root copy and keeping the one in `global_option` — the module appends `global_option` at every level, so the copy is redundant, except for a flag only a **few** subcommands take.
The gates fail only the verbatim copy; a shared spelling with differing content is normal per R-11 and is not reported.

**A child either inherits its options or declares them — never both.** Option resolution walks up the ancestor chain and the first non-empty `option` wins outright (`option_source` in `core/engine/src/engine/completion.rs`; see [`../design/completion.md`](../design/completion.md)): a child with no `option` of its own is offered its nearest ancestor's (or root's) flags, while a child that declares any `option` sees only its own array — the parent's flags disappear from that context.
Absent and empty count the same (empty arrays are removed outright), so the switch flips on the first real entry.
Two consequences: never copy a parent's flags onto a child that needs none of its own — `zoxide import --merge` is the worked case, where all six `import` children accept `--merge` yet none declares it, and re-declaring it would change nothing in the menu while adding translation and drift cost.
And when a child gains its first own flag, re-declare every parent flag it should keep, or those completions silently vanish.

A re-declaration asserts acceptance at that level: only re-declare what the page lists or a probe proves.
An unprobed parent flag stays out — a missing suggestion costs the user nothing, an asserted-but-rejected row is wrong data.
When sweeping a level is cheap, sweep it and re-declare what passes; when the level below needs an order of magnitude more probes, leave those pages as listed and note the gap in `WIP/<tool>/README.md`.

No duplicate `name` within the same array.
A spelling can also appear in the **command list and the option list at once**. `brew commands` prints `--version`, but brew's `--version` prints and exits, so it is an option; recording it in both `next` and `option` shows the row twice, and the `next` copy switches context. The gates compare one array at a time, so this duplicate is invisible — decide the owner by behaviour, not by which list printed the spelling.
The same ownership applies when a **command's alias** is an option spelling: Bundler 4.0.23's `version` command registers `-v` and `--version` as command aliases, but both spellings print and exit, so the root `--version` option owns them and the command keeps only its own name.
`compare-json.ps1` reports spelling collisions (`name` plus each `alias`) inside one array as `DuplicateItems`, naming each side's arity — see [`validation.md`](validation.md).

A spelling admits one owner even when the page documents it for two options with different arity (`git shortlog` lists `-n` for both `--numbered` and `--max-count <n>`).
Give the short form to the option the bare spelling actually selects — verified by invocation — and leave the other with its long form only.
Arity does not make the two compatible: the engine resolves a typed word by first match on the spelling alone, so the second row would insert a token the resolver attributes to the first, and its `next` candidates would never appear.

## `tip` / `usage` / `example` format

Every item may carry three text arrays.
`tip` is the description (shown under `[Description]`); `usage` and `example` are optional and shown under `[Usage]` / `[Example]`.

- Each array element is one line; no inline line breaks.

- **Split multi-sentence tips at sentence boundaries** (`R-19`). The split point is `.` / `?` / `!` followed by a space and a capital letter (English), or 。/！/？/； (Chinese — e.g. `说明文字。第二句` splits after `。`). Do not split mid-sentence or at commas unless the result is genuinely two independent thoughts; when in doubt, keep one line.

- **An inline default marker belongs to its own sentence.** CLAs write the default value in parentheses at the end of the description — `Format output as: text, json. (text)`, `Number of items to list per page. (30)`, glab's `(true)` / `(gitlab.com)` / `(default checks 'Environment variables → Local → Global')`. Keep the value, and render it as a trailing sentence in the same tip line so it reads as a statement rather than a fragment: `Output format: text or json. (default text)` / `Items per page. (default 30)`. Do not drop it (the default is the fact a user most wants) and do not leave the bare English fragment standing alone after the split.
- **Do not mandate trailing punctuation.** A `tip` line may end in `.`, `?`, `:`, `)`, a closing quote, or nothing at all. `tip` is display text — the engine never parses it, so a rule about it has no enforcement point. Every other rule here guards a defect the engine will mis-handle. See [`D32`](../decisions/authoring.md#d32).
- Spaces are required between Chinese and English characters (enforced by `validate-completion.ps1`).
- `tip` — the description line. If `tip` exists, it should be a real description; a CLI that prints an option with no description still gets one, because an empty string is a schema error, not a way to omit the field. Do not put `U:` / `E:`-prefixed lines in it — those belong in `usage` / `example`. A `tip` is shown without its surrounding help text, so it must be self-contained: drop dangling cross-references (`see above`, `see below`, `as described above`) or inline the referenced fact when it is short (e.g. `--cherry-mark`: `Like --cherry-pick but mark equivalent commits with = rather than omitting them` — no `(see below)`). Experimental commands and options keep the upstream `EXPERIMENTAL:` prefix (uppercase + colon, e.g. `EXPERIMENTAL: Show when files were last modified.`); deprecated ones are noted inline (e.g. `"(deprecated, use --new-flag instead)"`). Entries that document a platform-specific topic which is **not usable on the current platform** are kept and marked `(Windows only)` / `(macOS only)` — keeping the topic preserves `gh help mintty`-style discoverability, and the marker makes the limitation visible before the user tries it.
- `usage` — invocation syntax. **Not mandatory; add it when it conveys something the name
  alone does not.**
  - **Must add `usage` when** the item has an alias — the short form must be shown (`-f, --force`, `rm|remove`).
  - **Should add `usage` when** (recommended, not mandatory) the item takes a value and you know its shape — e.g. `--output <FILE>`, `add <PACKAGE>`. Skip it when the value's nature is unknown or unknowable (e.g. hook-provided free input behind `next: []`) — a vague usage adds nothing.
  - **A command with a positional argument should carry `usage`.** It is the manifest's only record of that positional slot: the slot inventory reads the placeholder from it ([`collecting-info.md`](collecting-info.md) §Record every value slot while you collect), and without it the next maintenance re-derives the position from the CLI reference.
  - **One invocation shape per line; alias and value share the line.** When an item has both an alias and a value shape, combine them into a single line — `ls|list [<owner>]`, `-f, --format <FORMAT>` — not an alias-only line plus an invocation line. Array elements are display lines, not alternatives, so a second line reads as a second shape. A genuinely different invocation (e.g. `cl|changelist --remove <PATH...>` beside `cl|changelist <CHANGELIST> <PATH...>`) is the case that earns a second line.
  - **Value syntax follows the CLI**: copy the value placeholder from the tool's own `--help` — its **name** as well as its separator. The tool writes `--upgrade-package <UPGRADE_PACKAGE>`, so write that, not a paraphrase like `--upgrade-package <PACKAGE>`. The separator is a space by default (`--opt <VAL>`), and `=` only when the CLI itself uses `=` (e.g. `esbuild --certfile=<FILE>`). Same for short flags: `-U, --unified <n>` (space) unless the CLI only accepts the attached form.
  - **A value the CLI only accepts attached carries the `=` in `name`**: declare `"name": "--lint="`, so the row inserts `--lint=` with the cursor after it and the candidates fill the segment ([`../design/completion.md`](../design/completion.md) §5); `--lint fatal` is read as another argument, and no gate sees the difference.
    - Only for a required value. An optional value keeps the bare `name` — the bare flag is the common form — with `[=file]` in `usage` and one `tip` line saying the value must be attached.
    - A path or free-form value whose space form works stays on the space form: the PowerShell host only routes a pending word that starts with a path prefix, so `--file=<TAB>` never reaches native path completion.
    - A short spelling that glues its value (`-Lfatal`) stays in `alias`; the trailing `=` belongs to the long form, and a short form that also rejects the space form follows the two bullets below.
    - **A glued-only form with a closed value set can be modelled as one spelling per value**: `-O<level>` → `-O0`, `-O1`, … `-Oz`, each with its own `tip`, no `next`, and no `usage` (it would only repeat the name).
      This is the fallback for a spelling that accepts nothing else: the moment the CLI also takes the space form, use the standard shape (space + `next`, or `=` where the tool itself prints it), which keeps the value menu and native path completion.
      The row is a complete legal word, so insertion, filtering and discovery all work; `next` would put a value behind a space the CLI rejects.
      Keep the bare spelling only when the tool documents it as its own form (`-O` is level 1), never because the parser tolerated it (`xxhsum -H` alone hashes stdin while only `-H#` is documented).
      **Weigh the price before choosing this shape**: the rows join the context's own option list and compete with every other option there, so one option's values can fill the first screen and push everything else off it, while a `next` value costs nothing until the option is chosen; each row also carries its own `tip`, duplicated in both language files.
      A handful stays a readable cluster (`-O0`…`-Oz` reads as one option); a large set is a genuine choice between crowding the list and offering no candidates, so decide it per option, and when the rows would dominate keep the bare spelling with one `tip` line saying the value must be attached.
    - **A glued-only form with a free-form value keeps the bare spelling**: `-D<m>` or `-V:<TAG>` has no candidates to filter, so give it one `tip` line saying the value must be attached and declare no `next`; a `next` would open an empty value menu behind an illegal space. See [`D55`](../decisions/authoring.md#d55) for why this is the model rather than a field.
  - **Transcribe the tool's argument syntax as its help prints it.** Copy the placeholder, separator, and optionality markers (`<UPGRADE_PACKAGE>`, `[<owner>]`, `=`, `|`) — but not bare framework boilerplate (`[command]`, `[--flags]`, `[OPTIONS]`, `[COMMAND]`) and never the root command name (§`usage` starts from the current command level below); those add nothing the menu does not already show.
  - **Three optional shapes are standard, not special cases:**
    - *Optional value* `--opt[=<VAL>]` — keep whatever the CLI writes, with `next: []`.
    - *Closed enumeration* `--opt=(a|b)` — the enumeration in `usage` tells the user only two values are possible, and `next` lets them pick one directly (`git add --chmod=(+|-)x` with `next` of `+x` / `-x`).
    - *Glued short-option value* `-U<n>` — normalise to the space form `-U, --unified <n>` (git's `parse-options` accepts both, so nothing is lost); when the CLI accepts nothing else (e.g. `-C<NUM>`), model the glued form as one spelling per value or as a bare spelling with a `tip` (above), not as `usage` text alone.
  - **May add `usage` when** (allowed, not required) the item has no alias and no value, but it still documents something useful (e.g. important sub-options).
  - **Must not add `usage` when** the item has no alias and no value and the line would just repeat the name — e.g. a boolean flag `--dry-run` with `--dry-run`, or a subcommand `build` with `build`. That is meaningless.
  - In the rare case a usage line needs a brief explanation, use the object form `{ "cmd": ..., "desc": ... }` (both required).
  - Subcommands use `|`: `add|install <APP>`. Options use `,`: `-f, --format <FORMAT>`.
  - **Always order short → long**: `rm|remove`, `-g, --global`. Never reverse.
  - **`usage` starts from the current command level; never include the root command name.** Each level describes only its own invocation syntax. For `git worktree add <PATH>`, the path is `root → worktree → add`, so `add`'s usage is `add <PATH>`, not `worktree add <path>`.
- `example` — optional; add when examples clarify usage. Each item is a plain string, or an object `{ "cmd": ..., "desc": ... }` when an explanation is wanted — **both** `cmd` and `desc` are required in object form (use a plain string when there is no explanation). Multiple examples are separate array elements. Skip when `usage` is sufficient.
- **Field order in the JSON**: `name`, `alias`, `usage`, `tip`, `example`, then `repeat` / `separator` / `option` / `next`.

**`usage` examples — correct vs wrong:**

```jsonc
// Has alias → usage is required (shows the short form)
{ "name": "--force", "alias": ["-f"], "usage": ["-f, --force"], "tip": ["Force action"] }

// Has argument and you know the value → usage is recommended (shows what to write)
{ "name": "--output", "usage": ["--output <FILE>"], "tip": ["Output path"], "next": [] }

// Has argument but the value is unknown → usage may be omitted (next is still required)
{ "name": "--script", "tip": ["Run the given script"], "next": [] }  // OK — no usage

// No alias, no argument → usage must NOT be added
{ "name": "--dry-run", "tip": ["Dry run without changes"] }  // CORRECT
{ "name": "--dry-run", "usage": ["--dry-run"], "tip": ["Dry run"] }  // WRONG — meaningless
```
