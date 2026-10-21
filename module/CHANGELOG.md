# Changelog

English | [简体中文](./CHANGELOG.zh-CN.md)

## Unreleased

- cli: Fixed `psc --self-update` for scoop installs, whether it runs through the `modules\PSCompletions` link or an `apps\<name>` directory
- bridge: Stopped repeating the module update notice after `psc --self-update`

## 8.0.2

- bridge: Fixed selection failing on git bash when python writes CRLF
- bridge: Stopped coloring single-value completion reads
- bridge: Stopped notifying about a module update when the installed version is already current
- bridge: Stopped listing updatable completions twice after a bare `psc update`
- cli: `psc --json` reports the installed version instead of the library baseline
- cli: Fixed the mixed path separators that `psc --json` and `psc info` printed on Windows

## 8.0.1

- cli: `psc --self-update` no longer repeats what the install script already printed
- cli: Self-update failures are reported in the module language
- bridge: Fixed failing to load because the package carried Windows line endings

## 8.0.0

> PSCompletions (psc) is now a general-purpose completion manager — one engine, many shells.

### One Engine, Many Shells

- **bash, zsh and fish arrive**: the same engine and the same interactive menu now serve bash, zsh and fish as well as Windows PowerShell 5.1 and PowerShell 7
- **Install without PowerShell**: `install.sh`
- **The same experience everywhere**: the trigger key, the menu, filtering, history ordering, the tips and more
- **Native completions stay in step**: when a shell supplies its own candidates, the engine derives the filter and answers by index
- **The same output everywhere**: `psc list` / `info` / `alias` / `config` / `completion` print the engine's text in every shell

### Other Changes

- cli: `--json` — every command can answer with one machine-readable object
- cli: `--self-update` — update PSCompletions itself
- cli: A non-official completion source warns on first use
- cli: `psc add --all` is gone — install what you need, so completion variants are not overwritten
- cli: trigger-alias ownership follows the declaration order — a word two completions claim belongs to the later one
- menu: A leading `sudo` is transparent for completion and history ranking, and history ordering now distinguishes case
- menu: a separator (`|`, `;`, `&`, `&&`, `||`) starts a new command for completion — `git status | grep <Tab>` completes `grep`, and a separator inside quotes stays text
- hooks: `psc.mount_items` mirrors the manifest path chain and includes aliases
- hooks: `tip` / `usage` / `example` accept a lazily-evaluated function and the `{ cmd, desc }` form
- completion: `config.json` records a `version` — the command version it was written and checked against
- chore: Other optimizations and fixes.

## [Older versions](./archive/CHANGELOG.md)
