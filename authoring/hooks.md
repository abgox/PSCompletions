# Dynamic completions (`hooks.lua`)

Use hooks when a static list cannot know the real values at authoring time — they depend
on **runtime local state**: git branches, npm scripts, installed packages, files,
environment variables. Dynamic items are **merged** with the static JSON items, not a
replacement.

> **Before writing a `hooks.lua`, read
> [`../design/hooks.md`](../design/hooks.md)** — it is the authoritative reference for the
> `psc.*` API, the prelude helpers, and the PowerShell→Lua semantics rules
> (case-sensitivity, pending-token exclusion, array and `-match` gotchas). **Style is
> defined there too** — follow `../design/hooks.md §9 Style Guide` (declarative `psc.on`,
> validated targets, merged array specs, short why-only comments, `add_*` naming,
> `or {}` guards).

If `config.json` has `hooks: true` but no dynamic behaviour is actually needed, remove
`hooks: true` and delete `hooks.lua`.

## The slot rule

Inject a value kind only where the CLI itself accepts it — check `--help` usage, docs, and
examples, not the manifest alone. Never offer files at a context whose slot takes
subcommands, names, keys, or nothing — e.g., offering a config file at a `build` subcommand
slot where only subcommand names are valid. If a slot accepts files but the
manifest shows no placeholder, add the `usage` placeholder (`[FILES]...`) so the slot
is documented.

For allowed `psc.ls` candidates in a relative file or directory slot, use `entry.name` as
the completion `name`; use `entry.path` only when the slot requires an absolute path, or as
a tip.

## The path-candidate rule

**Hooks do not offer file paths as candidates.** Native path completion owns paths. A hook's file
list is unbounded by construction — it grows with the repository — so it buries the subcommands and
options the user is actually looking for, and the user usually already knows where their own file
is. A hook's job is the state the CLI cannot itself enumerate (branches, packages, services, keys),
not paths.

This is a ban, not a judgment call. It does not depend on *how* the path was obtained: `psc.glob`
with or without a wildcard (`psc.glob(".env")` is still `psc.glob`), a `psc.ls` of the current
directory, and a `psc.run` of `ls` all count the same. Keying the rule on the API would only let an
author route around it by picking a different one — which is the drift a hard rule exists to
prevent.

**The exception is a slot that takes a *name* the CLI cannot enumerate itself**, sourced from a
known directory. `hugo --theme` wants a theme *name*, not a path, so `psc.ls("themes")` stands;
`typst init` wants a package *name*, so `psc.ls` over the package cache stands. All three of these
must hold:

- the directory is **known and fixed** — `themes/`, not "any directory in the tree"
- the candidate surfaced is `entry.name`, never `entry.path`
- the CLI's slot takes a **name**, not a path

Where a slot wants a path and there is nothing to enumerate, offer nothing and let native path
completion take it.

**`psc.glob` is a free means.** It may find the files that hold data the CLI cannot enumerate, as
long as the path never becomes the selectable value. `scoop` globs `bucket/**/*.json` across every
bucket, reads the manifests with `psc.json_batch`, and offers the app **names** they contain;
`scoop-checkver` does the same over its own bucket directory. Remove the glob and the hook can
enumerate nothing at all — there is no CLI call that lists installable apps, and nothing to move
into `next: [...]`. `ssh-keygen` reads `known_hosts` and offers hostnames.

**A bare filename is not a way around this.** Stripping the directory off a discovered path fixes
nothing: a repo-wide `**/*.json` still yields a repository-sized list of names, so the original
objection stands. And when the slot takes a path, a basename is usually a *broken* argument —
`lazydocker --file compose.yaml` when the file actually lives in a subdirectory produces a command
that fails. The test is what the slot accepts, not the shape of the string. If the slot takes a
name, offering a name is right however you derived it — `typst init` over the package cache,
`codex resume` from session filenames, `sfsu info` from manifest filenames. If it takes a path,
native completion owns it.

A path in a `tip` is explanatory text. It is not what makes an offering legal, and not what makes
one illegal.

**Offering a path has one shape**, so it is auditable: a `psc.add`, `psc.items` or `psc.concat`
receiving a `psc.glob` / `psc.ls` / `psc.ls_batch` result. Two forms — direct
(`psc.add(psc.items(psc.glob("x") or {}))`) and by iteration
(`for _, p in ipairs(psc.glob("x") or {}) do psc.add({ name = p }) end`), the latter being the
common one. Reading a file is not an offering and stays permitted: `if psc.glob("x") then` guards,
and iterating a glob to feed `psc.run` / `psc.json` reads the tree for context rather than
surfacing it. `hugo`'s `psc.ls("themes")` is the exception above, in practice.

See `../design/hooks.md §9` for the full rule with worked examples.

## Targets and validation

`psc.on` targets refer to the `name` field of manifest items. Two defects fail silently at
runtime and no other gate catches them — a dangling target, and a target written as an
alias instead of a `name`. Always run
`.\scripts\check-hook-targets.ps1 <command>` whenever a `hooks.lua` exists or was touched,
and `luac -p completions/<cmd>/hooks.lua` because nothing checks whether it compiles. See
[`validation.md`](validation.md).
