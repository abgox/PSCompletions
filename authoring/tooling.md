# Tooling & environment

The three things that break silently if you get them wrong.

## Always use PowerShell 7 (`pwsh`)

Use `pwsh` for any file write or script execution. Windows PowerShell 5.1
(`powershell.exe`) writes a UTF-8 **BOM** with `Set-Content -Encoding utf8` and misreads
UTF-8 without BOM as the system ANSI code page (e.g. GBK), silently corrupting Unicode
characters (`→`, `—`, Chinese text).

Prefer the editor or write tools for file edits. If you must write files from a shell, run
`pwsh -NoProfile` scripts.

### Read `$LASTEXITCODE` only after a direct redirect

Never read it at the end of a pipeline (`... | Select-Object -First N`) — a
pipeline stage can clobber it. Probes read through a pipe returned 2, 66, and
empty for commands whose direct-redirect code was 0, and every one had to be
re-probed. Redirect to a file first, then read the code:

```
& dart help bogus > out.txt 2>&1; $LASTEXITCODE
```

Encoding conventions:

- Rust sources are UTF-8 without BOM.
- PowerShell module files are UTF-8 with BOM (`utf8bom`, see
  `../.vscode/settings.json`).

## `@jirutka/ajv-cli` is a hard dependency of `validate-completion.ps1`

```
npm install --global @jirutka/ajv-cli
```

`validate-completion.ps1` throws with this install command when `ajv` is not on `PATH`.

It is invoked as `ajv validate --strict=false --all-errors --errors=json --validate-formats=false -s <schema> -- <data>`,
and **each flag is load-bearing**:

- `--strict=false` because the schemas carry `markdownDescription` (a VSCode-only
  annotation) which strict mode rejects as an unknown keyword.
- `--all-errors` because ajv otherwise stops at the first failure.
- `--errors=json` because the default `pretty` format is human-readable text that
  `ConvertFrom-Json` cannot read. The error array goes to **stdout** (the
  `<file> valid|invalid` summary stays on stderr).
- `--validate-formats=false` because `format` (only `uri` on `meta.url`) has no
  validator without the `ajv-formats` package — ajv merely warns
  (`unknown format "uri" ignored`, two lines per file) and ignores it. The real
  URL check is the `pattern` / `not` rules. The flag only silences the warning;
  validation is unchanged.
- Data files are **positional** (after `--`); the old `ajv-cli -d` flag does not
  exist in this fork.
- `--merge-errors` keeps its default (`true`): one concise entry per instance path
  (`message` + `instancePath` + `schemaPath`), which is all the script consumes.

Errors come back on **stdout**, with the instance path and the failing schema rule:

```
next[35].next[0].option[3].tip[0]: must not be empty  [#/allOf/1/items/minLength]
```

### Recovering a schema error message

The `errorMessage` texts in `../schema/*.json` are **not** printed by the script, and no
mainstream CLI can print them (ajv v8 moved the keyword to the `ajv-errors` plugin, which
fails to compile these schemas; python-jsonschema ignores it). **VSCode does honour them**,
so the friendly wording reaches whoever edits a manifest in the editor, and
`Get-I18nSpacingIssues` independently enforces the most valuable one ("Chinese and English
must be separated by a space").

The rule pointer is enough to recover the wording by hand: `#/allOf/1/items/minLength`
names a constraint inside a `definitions` entry, and opening that entry says what it means.

**Do not script that lookup.** ajv renumbers `allOf` indices after `$ref` resolution, so an
automatic resolver attaches the *wrong* message whenever a `$ref` sits in between — and a
confidently wrong message is the same trap as the previous `Test-Json` helper, which
reported the wrong path entirely: an empty `tip` deep in `podman` was blamed on
`meta/description`, and it surfaced only the first error.

## `luac -p` is a required extra step

`validate-completion.ps1` only checks that `hooks.lua` exists and is non-empty, so a clean
gate says nothing about whether it compiles:

```
luac -p completions/<cmd>/hooks.lua
```

## A missing tool is a blocker, not a skip

Every check above is mandatory for the task it belongs to. When a required
tool is not found, do not quietly drop its gate and report the task as
complete. Instead, in order:

1. **Search thoroughly** — alternate names, versioned binaries,
   and `bin` directories outside `PATH` (linuxbrew, mise shims,
   `~/.local/bin`). One failed lookup proves nothing.
2. **Ask before installing.** Installing a tool mutates the operator's
   machine (global package installs, disk, network) — state what is
   missing, which gate it blocks, and the exact install command
   (e.g. `npm install --global @jirutka/ajv-cli`), then wait for confirmation.
   Never auto-install silently.
3. **On confirmation, install and re-run the blocked gate.** On refusal,
   or when installation is impossible, stop and state exactly which
   verifications were left undone — never report the task as complete
   with a gate quietly dropped.
