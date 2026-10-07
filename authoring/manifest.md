# The Manifest

The manifest as data: what the generated files look like, what each field means, and how
text is formatted. Field *semantics* and engine behaviour are defined in
[`../design/completion.md`](../design/completion.md); the strict, actually validated
definition is
[`../schema/completion-manifest.en-US.json`](../schema/completion-manifest.en-US.json).
Read the schema first — this file is the practical reading of it.

Rule statements are `R-xx` in `../AGENTS.md`.

## Scaffold

`.\scripts\create-completion.ps1 <command>` generates:

```
completions/<command>/
├── config.json           # { "id": "<uuid>", "language": ["en-US", "zh-CN"] }
└── language/
    ├── en-US.json        # template content, needs a full rewrite
    └── zh-CN.json        # template content, needs a full rewrite
```

The script creates **static completions only**. For dynamic completions, hand-write
`hooks.lua` — see [`hooks.md`](hooks.md) and `../design/hooks.md §9`. There is no
automatic hooks generation; every hook is bespoke.

Before writing, skim a few existing completions to match the house style — e.g.
`completions/git/` (deep nesting, hooks), `completions/psc/` (dynamic tips via hooks), or
a simple tool like `completions/fd/`.

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
- `--output` (an option) **does** have `next: []` — it takes a value but has no static
  candidates. This is correct.
- `deploy` shows a **nested scenario**: a command that has both `option` (its own flags
  like `--tag`) and `next` (its sub-subcommands like `status`, `rollback`). Note that
  `deploy` itself has no `next: []`, `--tag` has `next: []`, `--dry-run` has no `next`
  (boolean, no value), `status` has no `next` (leaf command), and `rollback` has no
  `next` (its value is expressed by `usage <VERSION>`, not by `next`).
- Top-level `option` is root-level options, available before any subcommand.
- `global_option` is appended at every level. A flag that **many** subcommands share
  *verbatim* belongs here even when the root itself rejects it; when only a **few** take
  it, or the entries differ per subcommand, put it on each of those subcommands' own
  `option` instead. The trade-off and its measurement:
  [`D16`](../decisions/authoring.md#d16).
- `repeat: 2` means the option can appear up to twice; use `repeat: 99` only when the
  exact limit is unknown.
- Empty arrays must be removed entirely — do not keep `"option": []`.

## `config.json`

```jsonc
{
  "id": "<uuid>",
  "language": ["en-US", "zh-CN"],
  // "alias": [...],
  // "hooks": true
}
```

- `id` (required) — random UUID generated at creation by `create-completion.ps1`, never
  changes. The engine uses it to detect upstream renames.
- `language` (required) — language array, corresponding to files in the `language/`
  directory.
- `alias` (optional) — alternative command names that trigger this completion.
  - **The directory name is the command the user actually types.** Do not name a
    directory after a project's full name when users type a shorter binary (`hx`, not
    `helix`; `python3`, not `python`) — the directory list is read by users, so it must
    match their input.
  - **If not set**, the directory name is used as the trigger name.
  - **If set**, the directory name is **ignored** — only the names in this array are
    used, so **the directory name must be repeated inside it** (`alias: ["python3",
    "python"]` for a `python3/` directory). An `alias` that omits it silently kills
    that trigger.
  - **Only add `alias` when upstream officially recognizes more than one name.** Check
    what upstream actually says — do not reason from the project's full name:
    - `hx` has **no** `alias`. `helix` is only the product name (`hx --version` reports
      "helix 25.07.1"), and no platform installs a `helix` command, so an alias would
      invent a trigger and could hijack a user's own command of that name.
    - `python3` **does**: PEP 394 makes `python3` canonical on POSIX, while the CPython
      Windows docs recommend `python` and describe `python3` as "not meant to be widely
      used or recommended". Both are official, on different platforms.
  - When only one name is officially valid, **omit `alias` entirely** and let the user
    configure their own triggers after install (`psc alias add <name> <alias>...`) —
    guessing aliases is how trigger conflicts get created.
  - **Omit `.cmd`, `.exe`, `.bat` suffixes** — just use the command name (`git`, not
    `git.exe`).
- **`@` in a directory name is an ownership marker, never a trigger** — `AAA@author`,
  `AAA@local`, `AAA@uutils`. Directory names must be unique, so this is how two
  same-named tools — different authors, or different implementations — are told apart.
  - **The part before the `@` is the command name, character for character.** Do not
    force a case: most commands are all lowercase, but a command genuinely spelled
    `N_m3u8DL-RE` keeps its capitals, because the directory name serves the user's input
    rather than typography.
  - **The part after the `@` names the source, never the platform**, following the
    source's own spelling and case. Do not write `@Linux` / `@MacOS` / `@Windows`. A
    completion describes an *implementation*; the platform it runs on is an unstable
    axis — a platform may ship one implementation and later another — and uutils itself
    runs on every platform, which is exactly why the existing splits are `@uutils` and
    not `@Linux`. When two *projects* provide the same command on different platforms
    (`cut` as BSD vs GNU), name the project: `cut@BSD`. uutils spells itself lowercase
    (`cut@uutils`); GNU and BSD spell themselves uppercase (`cut@GNU`, `cut@BSD`).
  - **Once a command has variants, every variant carries its suffix — there is no bare
    "default".** A bare name hides which implementation it documents, and every default
    is somebody's subjective choice. A user installs exactly the variant matching their
    system. Keeping the suffix single-valued also removes the need for a double suffix: a
    macOS user running uutils wants "uutils's `cut`" (`cut@uutils`), not "macOS's
    `cut`".
  - **A directory whose name contains `@` MUST declare `alias` with the real command
    name** — triggers are first-come-first-served (`filter_owned_triggers` in
    `../core/cli/src/validate.rs` leaves a word with whoever claimed it first and
    silently skips later claimants), and nobody types `AAA@author`, so without an alias
    the completion is unreachable. This does not contradict the rule above: there `alias`
    carries another *officially recognized* name; here it carries the *only trigger that
    works*. The marker itself can never collide with a real author handle — it is a label
    for humans, and no component of the engine splits or matches on `@` (verified across
    all 46 Rust sources), so the engine treats the whole directory name as opaque. `@` is
    also a legal path character in URLs and on both filesystems.
  - `@local` marks a local draft (gitignored, see `.gitignore`). Unlike a dot-directory
    it is visible from a plain `ls completions/`.
- `hooks` (optional) — `true` means dynamic hooks are enabled by default (install writes
  no `enable_hooks` entry, since absence already means enabled); `false` means
  `hooks.lua` exists but is disabled by default (install writes `enable_hooks=0`; users
  enable it with `psc completion <name> enable_hooks 1`). Omit when there is no
  `hooks.lua`.

## Field semantics in use

For the full definitions of `meta`, `next`, `option`, `global_option`, and `info`, see
[`../design/completion.md`](../design/completion.md). The manifest's own `config` field is
covered below.

### Per-completion config (`config`)

An array of tunable settings for this command. Each entry is `name` + `value` + `tip`, plus an
optional `values`:

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

The engine merges three layers, later overriding earlier: global config → these defaults → the
user's override (`psc completion <name> <key> <value>`). A hook reads the result as
`psc.config`, where every declared key always has a value, so no `or` fallback is needed.
`values` is what gets offered when the user completes `psc completion <name> <key>` — it is
discovery surface, not documentation.

**A `name` starting with `enable` or `disable` is machine-constrained.** The schema forces
`value` to `0` or `1` and `values` to exactly `[0, 1]`. Any other name accepts `string` or
`number` freely.

**Do not reach for it by default.** Every key lands in `psc completion` for every user of this
completion, and nothing will flag an unnecessary one. Adding a key requires asking the author
first — `R-15`.

**When it is justified**: all three existing uses are the same shape — a knob controlling **how
much work a hook does**:

| Completion | Key | Tunes |
| --- | --- | --- |
| `git` | `max_commit` | how many commits the hook parses (`-1` = all, slower) |
| `scoop` | `exclude_buckets` | which buckets the hook scans |
| `scoop-install` | `exclude_buckets` | same |

The shared factor is that the right value genuinely varies per user *and per machine* — commit
history depth, bucket count — while the cost of doing more work is real. If a proposed key can
be phrased as a user *preference* about display or behaviour, it belongs in the `menu` config
group, not here; if a CLI flag already covers it, it is an `option`.

> **Two different orderings — do not confuse them.** In the JSON structure, `name` is the
> longest (canonical) form and `alias` lists the remaining forms **longest → shortest**
> (the data model: `name` is the item's identity). In the `usage` line, the same forms are
> shown **shortest → longest** (`-f, --force`, `rm|remove`) — a display convention that
> matches CLI `--help`. Keep them as they are; the `usage` order is not a mistake. If a
> `name` or `alias` contains spaces, wrap it in quotes: `"hello world"` or
> `'hello world'` (see the schema for validation).
>
> **"Longest" is a convention, not a claim about the tool.** `../scripts/sort-json.ps1`
> puts the longest form in `name` on every run, so this is guaranteed for you and a
> `psc.on` target can always be written as `name` — but nothing is *wrong* when a
> manifest's `name` is the tool's shorter form (`k3d config create` vs the CLI's `init`,
> `svn praise` vs `blame`). `name` / `alias` carries no hierarchy; the CLI's own primary
> name may well be the shorter one.

**Boolean options** (no value needed): do not include `next`. A negatable `--[no-]`
switch is modeled as **two entries** (`--foo` / `--no-foo`, each with a plain-form
`usage`) — never a single `--[no-]` usage line.

**Options that take a value**: use `next: [...]` when you know the value's shape (allowed
values or representative examples), otherwise `next: []`. **A value-taking option must
declare `next` regardless of whether it has a `usage` placeholder** — the `compare-json`
check keys on `usage <...>`, so an option with only a tip (e.g. `dotnet --roll-forward`)
would otherwise be treated as a boolean switch and go unflagged.

**A closed enumeration is worth listing** even though every value is knowable at authoring
time — the test is whether the user would otherwise have to know an unfamiliar name, not
how many entries there are. A probe reporting "has `next` but no Commands section" is then
expected noise, not a defect, provided the `usage` has no positional placeholder. Reasoning
and evidence: [`D13`](../decisions/authoring.md#d13).

**Repeatable options**: add `"repeat": N`, where N is the max number of times the option
can appear. Use a specific number when known (e.g. `2` for `-v -v`); use `99` only when
the limit is unknown or effectively unlimited:

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

**`next` for options** — prefer `next: [...]` over `next: []` whenever you know the
value's shape well enough to give representative examples; keep `next: []` only for
genuinely free-form values. If `hooks: true` is set, dynamically generated completions
are **appended** to the static array, not replaced. See
[`../design/completion.md`](../design/completion.md) for the full `next` semantics.

**`separator` for list values** — an option whose value is a separator-joined list
(`--exclude a,b,c`) declares `"separator": ","` (any non-empty string except whitespace or
`=`; typically `,` or `;`). Requires `next` (boolean flags must not carry it). Selecting a
candidate replaces only the current segment and adds **no** trailing space — the user
types the separator to continue, Space to finish. `usage` should show the shape
(`--exclude <A,B,...>`). See
[`../design/completion.md`](../design/completion.md) for the full semantics.

## Duplicates

An option counts as a duplicate only if it is **fully structurally identical** to a
`global_option` entry — same `name`, `alias`, `tip`, `usage`, `example`, `separator`,
`next`, `option`, and all nested substructure. If the description or `next` differs in any
way, they are **different** options: when you reach a subcommand context, the module uses
the subcommand's own `option` (it overrides the `global_option`). Fix a duplicate by
removing the subcommand or root copy and keeping the one in `global_option` — the module
appends `global_option` at every level, so the copy is redundant, except for a flag only a
**few** subcommands take.

No duplicate `name` within the same array. `compare-json.ps1` matches by `name` and
silently overwrites duplicates without error.

## `tip` / `usage` / `example` format

Every item may carry three text arrays. `tip` is the description (shown under
`[Description]`); `usage` and `example` are optional and shown under `[Usage]` /
`[Example]`.

- Each array element is one line; no inline line breaks.
- **Do not mandate trailing punctuation.** A `tip` line may end in `.`, `?`, `:`, `)`, a
  closing quote, or nothing at all. `tip` is display text — the engine never parses it, so
  a rule about it has no enforcement point. Every other rule here guards a defect the
  engine will mis-handle. See
  [`D32`](../decisions/authoring.md#d32).
- Spaces are required between Chinese and English characters (enforced by
  `validate-completion.ps1`).
- `tip` — the description line. If `tip` exists, it should be a real description; do not
  put `U:` / `E:`-prefixed lines in it — those belong in `usage` / `example`.
  Experimental commands and options keep the upstream `EXPERIMENTAL:` prefix (uppercase +
  colon, e.g. `EXPERIMENTAL: Show when files were last modified.`); deprecated ones are
  noted inline (e.g. `"(deprecated, use --new-flag instead)"`). Entries that document a
  platform-specific topic which is **not usable on the current platform** are kept and
  marked `(Windows only)` / `(macOS only)` — keeping the topic preserves
  `gh help mintty`-style discoverability, and the marker makes the limitation visible
  before the user tries it.
- `usage` — invocation syntax. **Not mandatory; add it when it conveys something the name
  alone does not.**
  - **Must add `usage` when** the item has an alias — the short form must be shown
    (`-f, --force`, `rm|remove`).
  - **Should add `usage` when** (recommended, not mandatory) the item takes a value and
    you know its shape — e.g. `--output <FILE>`, `add <PACKAGE>`. Skip it when the value's
    nature is unknown or unknowable (e.g. hook-provided free input behind `next: []`) — a
    vague usage adds nothing.
  - **Value syntax follows the CLI**: write the value placeholder the way the tool's own
    `--help` writes it — `--opt <VAL>` (space) by default, `--opt=<VAL>` only when the
    CLI itself uses `=` (e.g. `esbuild --certfile=<FILE>`). Same for short flags:
    `-U, --unified <n>` (space) unless the CLI only accepts the attached form.
  - **Three optional shapes are standard, not special cases:**
    - *Optional value* `--opt[=<VAL>]` — keep whatever the CLI writes, with `next: []`.
    - *Closed enumeration* `--opt=(a|b)` — the enumeration in `usage` tells the user only
      two values are possible, and `next` lets them pick one directly (`git add
      --chmod=(+|-)x` with `next` of `+x` / `-x`).
    - *Glued short-option value* `-U<n>` — normalise to the space form
      `-U, --unified <n>` (git's `parse-options` accepts both, so nothing is lost), and
      copy the CLI verbatim only when it accepts nothing else (e.g. `-C<NUM>`).
  - **May add `usage` when** (allowed, not required) the item has no alias and no value,
    but it still documents something useful (e.g. important sub-options).
  - **Must not add `usage` when** the item has no alias and no value and the line would
    just repeat the name — e.g. a boolean flag `--dry-run` with `--dry-run`, or a
    subcommand `build` with `build`. That is meaningless.
  - In the rare case a usage line needs a brief explanation, use the object form
    `{ "cmd": ..., "desc": ... }` (both required).
  - Subcommands use `|`: `add|install <APP>`. Options use `,`: `-f, --format <FORMAT>`.
  - **Always order short → long**: `rm|remove`, `-g, --global`. Never reverse.
  - **`usage` starts from the current command level; never include the root command
    name.** Each level describes only its own invocation syntax. For `git worktree add
    <PATH>`, the path is `root → worktree → add`, so `add`'s usage is `add <PATH>`, not
    `worktree add <path>`.
- `example` — optional; add when examples clarify usage. Each item is a plain string, or
  an object `{ "cmd": ..., "desc": ... }` when an explanation is wanted — **both** `cmd`
  and `desc` are required in object form (use a plain string when there is no
  explanation). Multiple examples are separate array elements. Skip when `usage` is
  sufficient.
- **Field order in the JSON**: `name`, `alias`, `usage`, `tip`, `example`, then
  `repeat` / `separator` / `option` / `next`.

**`usage` examples — correct vs wrong:**

```jsonc
// Has alias → usage is required (shows the short form)
{ "name": "--force", "alias": ["-f"], "usage": ["-f, --force"], "tip": ["Force action"] }

// Has argument and you know the value → usage is recommended (shows what to write)
{ "name": "--output", "usage": ["--output <FILE>"], "tip": ["Output path"], "next": [] }

// Has argument but the value is unknown → usage may be omitted
{ "name": "--script", "tip": ["Run the given script"] }  // OK — no usage

// No alias, no argument → usage must NOT be added
{ "name": "--dry-run", "tip": ["Dry run without changes"] }  // CORRECT
{ "name": "--dry-run", "usage": ["--dry-run"], "tip": ["Dry run"] }  // WRONG — meaningless
```
