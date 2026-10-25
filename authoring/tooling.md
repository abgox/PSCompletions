# Tooling & environment

The three things that break silently if you get them wrong.

## Shell: use what the machine provides

There is no mandated shell — use whichever is available and fits the step: `bash` / `sh` / `zsh` on macOS and Linux, `pwsh` on Windows or wherever it is installed.
The one hard rule is to never write files with Windows PowerShell 5.1 (`powershell.exe`): it writes a UTF-8 **BOM** with `Set-Content -Encoding utf8` and misreads UTF-8 without BOM as the system ANSI code page (e.g. GBK), silently corrupting Unicode characters (`→`, `—`, Chinese text).
On POSIX the native shell writes UTF-8 without BOM, which is what the JSON and Lua sources expect.

The repository's own scripts under `scripts/` are PowerShell (`.ps1`) and still need `pwsh` on every platform — that is a dependency of the scripts, not a preference for the commands around them.
Do not install a second shell just to satisfy a style rule; the gates only need `pwsh`.

Prefer the editor or write tools for file edits.
If you write files from a shell, use that shell's own facilities (heredoc, `printf`) rather than embedding another shell's syntax, and run `pwsh -NoProfile` for a `.ps1` step.
When the outer command runner is PowerShell on Linux, POSIX loops, `&&` chains and heredocs do not parse there: wrap that step explicitly in `bash -lc '…'` (or write the loop in PowerShell) instead of assuming the runner's shell is the one the snippet was written for. The failure is a `ParserError` before the command runs, not a wrong result.

### Read the exit code directly, not through a pipeline

Under PowerShell this is `$LASTEXITCODE`; under a POSIX shell it is `$?`.
Never read it at the end of a pipeline (`... | Select-Object -First N`, `... | head`) — a pipeline stage can clobber it.
Probes read through a pipe returned 2, 66, and empty for commands whose direct-redirect code was 0, and every one had to be re-probed.
Redirect to a file first, then read the code:

```
& dart help bogus > out.txt 2>&1; $LASTEXITCODE     # PowerShell
dart help bogus > out.txt 2>&1; echo $?             # POSIX
```

Encoding conventions:

- Rust sources are UTF-8 without BOM.
- JSON manifests and Lua hooks are UTF-8 without BOM (the native POSIX shell's default).
- PowerShell module files are UTF-8 with BOM (`utf8bom`, see `../.vscode/settings.json`).

## Classify a command before running it

Reading is free; changing is not.
Before running a command, put it in one of two classes:

- **Read-only** — `--help`, `--version`, `list` / `show` / `status`, `cat`, `ls`, `grep`, `command -v`. No authorization needed.
- **Side-effecting** — anything that writes or deletes files, changes repository, service or package state, installs or updates, mutates a remote system, or whose flags you cannot classify. State the exact command, what it changes, and how it is undone, then wait for the operator's authorization (`R-26`).

The filesystem cases are the ones to slow down for: `rm`, `rmdir`, `mv`, `cp`, `install`, `truncate`, `dd`, `tee`, shell redirection (`>`, `>>`), in-place editors, `chmod` / `chown` / `touch`, and archive extraction.
`git clean`, `git reset --hard` and `jj abandon` change tracked state as surely as a file write.
Writes confined to `WIP/<tool>/` or the completion files being edited are the task itself and do not need a per-command question; deletion anywhere — `WIP/` included — waits for the operator (`R-20`).

Some tools only read with the right flag: `jj log` snapshots the working copy unless `--ignore-working-copy` is added, and a VCS command can write locks or reflog entries.
If the read-only form is not provable, ask rather than assume.
`scripts/sort-json.ps1` and the other repository scripts are task work and may write the completion files they own; a destructive command outside `WIP/<tool>/` still needs explicit confirmation ([`working-files.md`](working-files.md) §Running a script is the dangerous step).

## WSL interop is a probe window, not a runtime path

When the maintenance host is WSL2 (`uname -r` contains `microsoft`, `/mnt/c` exists), Windows executables are reachable: `cmd.exe`, `powershell.exe`, `winget.exe`, `netsh.exe`, plus `wslpath` for path translation.
Use them to collect and probe Windows-only surfaces instead of falling back to docs: `winget.exe --version`, `netsh.exe interface show interface`, `cmd.exe /c <cmd> --help`.

That is also how a `psc.platform == "windows"` hook branch is verified: write it for the Windows host, run the same query here, and match its real output — including a localized header and the separator line, which a parser written from an English example will miss.
The `--interface` producer in `curl` was corrected this way: the real `netsh.exe` output was Chinese and had a dashed separator line.

**A guarded branch is not done until it ran there, and proposing that run is your job.** As soon as a `psc.platform` branch exists, check whether this host can reach that platform (`uname -r` contains `microsoft` on WSL2) and ask the operator for one interop run of the branch's own query, naming the exact command — the operator should never have to point the host out, but the run itself waits for their word (`R-26`).
The rsync `--address` producer is the pinned case (rsync 3.5.1): `Get-NetIPAddress` prints a zone suffix on link-local IPv6 (`fe80::…%18`), and the first character class dropped every such line silently — only the interop run showed it, and the zone has to stay because rsync passes `--address` to `getaddrinfo()`.
When the operator declines, or the platform cannot be reached at all, write the branch from its documented output shape and list it under Open in `WIP/<tool>/TODO.md`.

It does **not** make the hook cross-platform.
A hook runs under the host's own platform: under WSL that is Linux, and `powershell.exe` / `cmd.exe` / `winget.exe` is still an unguarded Windows invocation (`R-13`).
Interop is also optional (`/etc/wsl.conf`) and may be absent; treat it as an opportunistic source, not a dependency.

Encoding: `cmd.exe` prints OEM/GBK, so decode it as such; `powershell.exe` here is 5.1 and writes a BOM — never use it to write repository files (see the shell section).

**Authorization and read-only.** These are still another platform's programs, and a chat log does not show the operator what is about to run.
Before the first one, state the exact command and what it only reads, then wait for authorization (`R-26`).
`--version`, `--help`, `list`, `show` and `status` are probes; an installer, updater, service control, or any command whose side effects are unproven is not.

## `@jirutka/ajv-cli` is a hard dependency of `validate-completion.ps1`

```
npm install --global @jirutka/ajv-cli
```

`validate-completion.ps1` throws with this install command when `ajv` is not on `PATH`.

It is invoked as `ajv validate --strict=false --all-errors --errors=json --validate-formats=false -s <schema> -- <data>`, and **each flag is load-bearing**:

- `--strict=false` because the schemas carry `markdownDescription` (a VSCode-only annotation) which strict mode rejects as an unknown keyword.
- `--all-errors` because ajv otherwise stops at the first failure.
- `--errors=json` because the default `pretty` format is human-readable text that `ConvertFrom-Json` cannot read. The error array goes to **stdout** (the `<file> valid|invalid` summary stays on stderr).
- `--validate-formats=false` because `format` (only `uri` on `meta.url`) has no validator without the `ajv-formats` package — ajv merely warns (`unknown format "uri" ignored`, two lines per file) and ignores it. The real URL check is the `pattern` / `not` rules. The flag only silences the warning; validation is unchanged.
- Data files are **positional** (after `--`); the old `ajv-cli -d` flag does not exist in this fork.
- `--merge-errors` keeps its default (`true`): one concise entry per instance path (`message` + `instancePath` + `schemaPath`), which is all the script consumes.

Errors come back on **stdout**, with the instance path and the failing schema rule:

```
next[35].next[0].option[3].tip[0]: must not be empty  [#/allOf/1/items/minLength]
```

### Recovering a schema error message

The `errorMessage` texts in `../schema/*.json` are **not** printed by the script, and no mainstream CLI can print them (ajv v8 moved the keyword to the `ajv-errors` plugin, which fails to compile these schemas; python-jsonschema ignores it).
**VSCode does honour them**, so the friendly wording reaches whoever edits a manifest in the editor, and `Get-I18nSpacingIssues` independently enforces the most valuable one ("Chinese and English must be separated by a space").

The rule pointer is enough to recover the wording by hand: `#/allOf/1/items/minLength` names a constraint inside a `definitions` entry, and opening that entry says what it means.

**Do not script that lookup.** ajv renumbers `allOf` indices after `$ref` resolution, so an automatic resolver attaches the *wrong* message whenever a `$ref` sits in between — and a confidently wrong message is the same trap as the previous `Test-Json` helper, which reported the wrong path entirely: an empty `tip` deep in `podman` was blamed on `meta/description`, and it surfaced only the first error.

## `luac -p` is a required extra step

`validate-completion.ps1` only checks that `hooks.lua` exists and is non-empty, so a clean gate says nothing about whether it compiles:

```
luac -p completions/<cmd>/hooks.lua
```

## A missing tool is a blocker, not a skip

Every check above is mandatory for the task it belongs to.
When a required tool is not found, do not quietly drop its gate and report the task as complete.
Instead, in order:

1. **Search thoroughly** — alternate names, versioned binaries, and `bin` directories outside `PATH` (linuxbrew, mise shims, `~/.local/bin`). One failed lookup proves nothing.
2. **Ask before installing.** Installing a tool mutates the operator's machine (global package installs, disk, network) — state what is missing, which gate it blocks, and the exact install command (e.g. `npm install --global @jirutka/ajv-cli`), then wait for confirmation. Never auto-install silently.
3. **On confirmation, install and re-run the blocked gate.** On refusal, or when installation is impossible, stop and state exactly which verifications were left undone — never report the task as complete with a gate quietly dropped.
