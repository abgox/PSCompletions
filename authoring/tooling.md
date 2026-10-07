# Tooling & environment

The three things that break silently if you get them wrong.

## Always use PowerShell 7 (`pwsh`)

Use `pwsh` for any file write or script execution. Windows PowerShell 5.1
(`powershell.exe`) writes a UTF-8 **BOM** with `Set-Content -Encoding utf8` and misreads
UTF-8 without BOM as the system ANSI code page (e.g. GBK), silently corrupting Unicode
characters (`→`, `—`, Chinese text).

Prefer the editor or write tools for file edits. If you must write files from a shell, run
`pwsh -NoProfile` scripts.

Encoding conventions:

- Rust sources are UTF-8 without BOM.
- PowerShell module files are UTF-8 with BOM (`utf8bom`, see
  `../.vscode/settings.json`).

## `ajv-cli` is a hard dependency of `validate-completion.ps1`

```
npm install -g ajv-cli
```

`validate-completion.ps1` throws with this install command when `ajv` is not on `PATH`.

It is invoked as `ajv validate --strict=false --all-errors --errors=json`, and **each flag
is load-bearing**:

- `--strict=false` because the schemas carry `markdownDescription` (a VSCode-only
  annotation) which strict mode rejects as an unknown keyword.
- `--all-errors` because ajv otherwise stops at the first failure.
- `--errors=json` because the default `js` format is a JS object literal that
  `ConvertFrom-Json` cannot read.

Errors come back on **stderr**, with the instance path and the failing schema rule:

```
next[35].next[0].option[3].tip[0]: must NOT be fewer than 1 characters  [#/allOf/1/items/minLength]
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
