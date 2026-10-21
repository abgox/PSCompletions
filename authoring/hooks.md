# Dynamic completions (`hooks.lua`)

Use hooks when a static list cannot know the real values at authoring time — they depend on **runtime local state**: git branches, npm scripts, installed packages, files, environment variables.
Dynamic items are **merged** with the static JSON items, not a replacement.

> **Before writing a `hooks.lua`, read [`../design/hooks.md`](../design/hooks.md)** — it is the authoritative reference for the `psc.*` API, the prelude helpers, and the PowerShell→Lua semantics rules (case-sensitivity, pending-token exclusion, array and `-match` gotchas).
> **Style is defined there too** — follow `../design/hooks.md §9 Style Guide` (declarative `psc.on`, validated targets, merged array specs, short why-only comments, `add_*` naming, `or {}` guards).

If `config.json` has `hooks: true` but no dynamic behaviour is actually needed, remove `hooks: true` and delete `hooks.lua`.

> For which finished completions read best as models (manifest and hooks alike), see [`manifest.md`](manifest.md) §Reference completions.

## The slot rule

Inject a value kind only where the CLI itself accepts it — check `--help` usage, docs, and examples, not the manifest alone.
Never offer files at a context whose slot takes subcommands, names, keys, or nothing — e.g., offering a config file at a `build` subcommand slot where only subcommand names are valid.
If a slot accepts files but the manifest shows no placeholder, add the `usage` placeholder (`[FILES]...`) so the slot is documented.

For allowed `psc.ls` candidates in a relative file or directory slot, use `entry.name` as the completion `name`; use `entry.path` only when the slot requires an absolute path, or as a tip.

The slot rule is applied when the slot is recorded, not in a later hooks pass: each value slot gets a `slots.json` row with its kind and verdict ([`collecting-info.md`](collecting-info.md) §Record every value slot while you collect).
That record turns a later review into a diff against `psc.on` targets instead of a second reading of every help page.

### Slot → producer

The verdict comes first, and it is the same for every tool:

| The slot | Verdict |
| --- | --- |
| holds a fixed set | `next: [...]` — not a hook |
| takes a name the CLI can enumerate | `hook` — one producer per source |
| takes a name only the user invents | `none` — no source exists |
| takes a path | `native` — the shell owns it |
| takes free text | `none` |

When the verdict is `hook`, the producer is whatever source enumerates that name — the tool's own listing command, a config file, a state file.
The table deliberately names no kinds: a slot's kind is what that CLI accepts, not a category this guide owns.
A repository tool enumerates branches, tags, commits and remotes; a package manager enumerates installed packages and versions; a service CLI enumerates clusters and namespaces.
Each is a producer with its own query and tip, and one slot may accept several kinds — a revision slot that offers only commits has left branches and tags out, and the inventory row says why.

Before adding a target, name the slot it fires at:

- an `option` target needs that option to take a value (`next`) — a valueless flag's value is a positional *after* it, reachable only by a command target;
- a command target fires at the **first** unfilled positional — a second positional (`<path> [<commit-ish>]`) cannot be targeted;
- a name the user invents gets no enumerating producer.

A target whose spelling resolves but whose slot does not exist is dead; `check-hook-targets` cannot see it, `R-25` can.

## One producer per registration

Give each producer its own `psc.on` and let it add one kind: `add_bookmark` reads the bookmark listing, `add_commit` reads the log, `add_tag` reads the tag listing.
A handler may filter and compute tips — the source it reads is what makes it atomic, not the number of `psc.add` calls.

Order is registration order, so an order-sensitive pair is two blocks in the intended order:

```lua
psc.on({ command = "merge" }, add_commit)
psc.on({ command = "merge" }, add_branch)
```

Do not fold them into one handler to force that order: it hides which source produced which row, and the slot inventory then cannot map a row back to a producer.
Combine only when the candidates must interleave (`commit, branch, commit`) or another producer's output feeds this one, and say why in one comment.
Registration order is injection order only — the menu's history ranking may still reorder the rows.

When two producers serve identical targets, keep one spec array in a local and pass it to both ([`../design/hooks.md`](../design/hooks.md) §9):

```lua
local REVSET_SLOTS = {
    { command = "show" },
    { option = "--revision" },
}

psc.on(REVSET_SLOTS, add_commit)
psc.on(REVSET_SLOTS, add_branch)
```

`psc.on` only reads the table, so the array is not copied per producer.
When the two lists differ by a slot — one producer deliberately excludes the static home, for instance — give each list its own name and say why.

## Composite and paired values

A value with its own syntax is completed as a **whole value**, not by splicing a fragment into the middle.
That does not make the slot free text by default: when the reference lists a value a user can pass as the whole value, put it in `next` even though the surrounding slot is a mini-language — `--cert-type DER`, `--write-out '%{http_code}'` and `-vf scale` are each valid whole values.
What stays out are fragments that would be rejected alone (`Content-Type` without `: value`, `host:port` without the address): the menu inserts a value, not a token inside one.
The test is validity at the slot, not the presence of syntax.

The same shape decides the option's other fields:

- `repeat: 99` when the CLI accepts the option once per item (`-H`, `-d`, `--resolve`): the user adds another pair, not a comma-separated list;
- `next` holds the whole values the reference offers (`-w`'s `%{http_code}`, `-vf`'s `scale`), or stays empty when there is no valid whole value;
- `separator` only when the CLI itself splits the value on that character;
- a `tip` or `example` that spells the pair (`Name: value`), because the menu cannot show the empty half.

The atoms are only documentation when they cannot stand alone: list the filter names in `tip` or `example`, or expose them on a different option that really takes a single name.
See [`manifest.md`](manifest.md) §`separator` for the split test.

## Shared constant sets

A constant set that serves one slot belongs in that slot's `next` (`R-16`).
When the same set serves many slots, copying it into each `next` creates one copy per slot, in every language, and an update has to find them all.

Define the set once as the `next` of a chosen command — one whose own positional takes it — then mount it wherever else it is accepted:

```lua
psc.on({
    { command = "show" },
    { option = "--revision" },
    -- ...
}, function()
    psc.add(psc.mount_items({ "next", "abandon", "next" }))
end)
```

`mount_items` resolves a plain key at an object and an item `name` at an array, so the path mirrors the manifest exactly ([`../design/hooks.md`](../design/hooks.md) §Mounting shared values defined in the manifest).
The values stay in the manifest — tips and translations included — and the hook only reads them; there is still one source.

Leave the home slot out of the mount producer's targets: it already shows its own `next`, and mounting there injects the same names a second time.
The mount target list is therefore the shared set's full target list minus the home.

A list hardcoded in Lua is not this pattern: it is a second source, and the rule still forbids it.
Record the home path as the `source` of every mounted slot in the inventory, so the next update knows where the values live.

## The path-candidate rule

**Hooks do not offer file paths as candidates.** Native path completion owns paths.
A hook's file list is unbounded by construction — it grows with the repository — so it buries the subcommands and options the user is actually looking for, and the user usually already knows where their own file is.
A hook's job is the state the CLI cannot itself enumerate (branches, packages, services, keys), not paths.

This is a ban, not a judgment call.
It does not depend on *how* the path was obtained: `psc.glob` with or without a wildcard (`psc.glob(".env")` is still `psc.glob`), a `psc.ls` of the current directory, and a `psc.run` of `ls` all count the same.
Keying the rule on the API would only let an author route around it by picking a different one — which is the drift a hard rule exists to prevent.

**The exception is a slot that takes a *name* the CLI cannot enumerate itself**, sourced from a known directory.
`hugo --theme` wants a theme *name*, not a path, so `psc.ls("themes")` stands; `typst init` wants a package *name*, so `psc.ls` over the package cache stands.
All three of these must hold:

- the directory is **known and fixed** — `themes/`, not "any directory in the tree"
- the candidate surfaced is `entry.name`, never `entry.path`
- the CLI's slot takes a **name**, not a path

Where a slot wants a path and there is nothing to enumerate, offer nothing and let native path completion take it.

The ban above covers sets the hook enumerates itself.
A second case is offered all over this repository and is not covered by it: a **CLI-filtered subset**, where the hook runs a command whose own answer *is* the candidate set.
The rule statement is `AGENTS.md` `R-10`; what is missing here is how to tell that case apart from the enumerated ones, and it takes two questions that must both answer yes.

1. **Is the set bounded by what the user did, rather than by how big the repository is?**
`psc.glob("**/*.json")` and `psc.ls(".")` grow with the tree and bury the menu.
`git status --porcelain` returns what changed, `git ls-files` returns what is tracked, `git diff --diff-filter=U` returns what is conflicted, and `svn status` returns what the working copy already knows is dirty.
Each is a function of the user's own actions, so it stays small in a repository of any size.
2. **Does the answer carry something native completion cannot produce?** A bare path does not — the shell hands the user that as soon as they type a prefix, which is the whole reason the enumerated cases are banned. A status code does: `modified`, `deleted`, `unversioned` and `conflicted` are state the shell has no access to at all. Where the candidate is only a path, nothing justifies the offering, so carry the status into the candidate's `tip`.

A set that passes the first question and fails the second is not worth registering.
A query that looks filtered but returns the tree has filtered nothing either, and that is the shape to watch for: it survives a glance and fails the first question.

**`psc.glob` is a free means.** It may find the files that hold data the CLI cannot enumerate, as long as the path never becomes the selectable value.
`scoop` globs `bucket/**/*.json` across every bucket, reads the manifests with `psc.json_batch`, and offers the app **names** they contain; `scoop-checkver` does the same over its own bucket directory.
Remove the glob and the hook can enumerate nothing at all — there is no CLI call that lists installable apps, and nothing to move into `next: [...]`.
`ssh-keygen` reads `known_hosts` and offers hostnames.

**A bare filename is not a way around this.** Stripping the directory off a discovered path fixes nothing: a repo-wide `**/*.json` still yields a repository-sized list of names, so the original objection stands.
And when the slot takes a path, a basename is usually a *broken* argument — `lazydocker --file compose.yaml` when the file actually lives in a subdirectory produces a command that fails.
The test is what the slot accepts, not the shape of the string.
If the slot takes a name, offering a name is right however you derived it — `typst init` over the package cache, `codex resume` from session filenames, `sfsu info` from manifest filenames.
If it takes a path, native completion owns it — unless the CLI's own query filtered the set, which is the case directly above.

A path in a `tip` is explanatory text.
It is not what makes an offering legal, and not what makes one illegal.

**Offering a path has one shape**, so it is auditable: a `psc.add`, `psc.items` or `psc.concat` receiving a `psc.glob` / `psc.ls` / `psc.ls_batch` result.
Two forms — direct (`psc.add(psc.items(psc.glob("x") or {}))`) and by iteration (`for _, p in ipairs(psc.glob("x") or {}) do psc.add({ name = p }) end`), the latter being the common one.
Reading a file is not an offering and stays permitted: `if psc.glob("x") then` guards, and iterating a glob to feed `psc.run` / `psc.json` reads the tree for context rather than surfacing it.
`hugo`'s `psc.ls("themes")` is the exception above, in practice.

See `../design/hooks.md §9` for the full rule with worked examples.

## Prove each producer's query against its own command

A producer's query is a contract with **one** subcommand, and sibling subcommands do not honour it.
`gh gist list` has no `--json` while every other `gh … list` beside it does, so a producer written by analogy to its neighbours returns nothing on every Tab press.
Before registering a producer, run its exact argv and read the answer:

- **A structured query** (`--format json`, `--json <fields>`) either parses or the CLI names the unknown field or flag. Field validation happens client-side, so this probe works without credentials and without a repository.
- **A plaintext query** needs its column layout confirmed from the tool's source or a real invocation — a column order assumed from a sibling is the same guess.
- **An auth-gated command** that answers `403` or `missing required scopes` has still proved the query shape: the argument check ran before the request did.

For the tools observed so far, non-TTY table output carries **no header row** — the header is printed for a terminal only — so a first-column parse does not need to skip one.
This is per-tool behaviour, not a guarantee: confirm that once, on a command that returns data, before relying on it for the rest.

## An informational query feeding a sibling slot — write it, don't ask

When the CLI itself offers a read-only informational command — `list`, `info`, `show`, `describe`, whatever the verb — whose output items are valid values at a sibling slot, that hook is the default, not a scope decision: write it without confirming first.
All four must hold:

- the query is read-only and side-effect free (it reports state, never installs / runs / creates it);
- each output item is provably valid at the target slot — same namespace, confirmed by running the query and by the slot's own `usage` / docs (`R-17`: probe each producer's query against its own command);
- the parse reads the CLI's own output shape (one item per line, or one field per line), verified against a real invocation, never assumed from a sibling command's layout;
- the slot takes names, not paths and not free text — a search box that accepts anything gets no producer, however query-like the source.

One tool's instance (`android`): a `skills list` whose block-start names feed `add` / `remove` / `update`, and an `sdk list` whose package column feeds `install` / `remove` / `update` — each query probed, each slot's `usage` carrying the matching placeholder.

Confirm scope with the operator outside this shape: the query needs credentials or hardware absent here, its with-data output shape is unobservable locally, the slot kind is unclear, the query is heavyweight or side-effecting, or the hook wants a new `config` key (`R-15`).

## Cases: the shapes that recur

Positive — write the hook:

- **A listing feeding its siblings.** One command enumerates a set, other commands consume it: `adb devices` serials feed `-s` / `-t` and `uninstall`; `android skills list` names feed `add` / `remove` / `update`; installed-app names feed `scoop uninstall` / `cleanup` / `update` / `cache show`. Read-only query, name-taking slots, each side probed — the previous section in its everyday form.
- **A mount instead of a copy.** A `help` taking the tool's own subcommands mounts root `next` (`dart help <command>`); the copy would drift in two languages with no gate comparing them. A `help` taking documentation topics (`gh`, `go`) stays static — different set, no mount.
- **Runtime state the manifest cannot freeze.** Installed packages, connected devices, per-build drivers: exactly right on the author's machine and silently wrong everywhere else (`R-16` per-machine sentence; `mpv` drivers).
- **OS state the CLI cannot enumerate.** Network interfaces (`curl --interface` via `ip` / `ifconfig` / `netsh`), audio devices, mounted volumes: the CLI takes the name but has no command that lists it. Query the OS behind `psc.platform`, and offer the name rather than a path.
- **An aggregator's own state.** A wrapper owns a package and module layer the wrapped tools do not: x-cmd's `env ls` names packages and `uninstall ls` names installed software. Query the wrapper for those slots, not the wrapped command.
- **A project manifest.** `package.json` supplies scripts for `npm run`, dependencies for `uninstall` / `upgrade` / `link` / `rebuild`, and top-level keys for `npm pkg get/set/delete`; read it once and guard when it is absent. Registry-wide names are not a local source, so `npm install <pkg>` stays unhooked.
- **A context selector changes the source.** `cargo --manifest-path`, `uv --directory` / `--project`, `terraform -chdir` and `kubectl --context` move the state a producer must read. Read the selector from `psc.tokens` and pass it to both the file read and the subprocess; a producer that ignores it silently completes the wrong project — cargo 1.99.0 and uv 0.13.4 did exactly that until their hooks were fixed.
- **The same noun has two sources.** `dotnet workload install` uses `workload search` (available workloads); `uninstall` and `update` use `workload list` (installed ones). Match the producer to the verb, not to the noun.

Negative — no hook:

- **The slot takes free text.** A search box (`skills find keyword`, `docs search <query>`) accepts anything; offering the known names narrows nothing and misreads the slot as closed.
- **The slot is a search term.** `dotnet package search <term>` and `dotnet tool search <term>` accept arbitrary text; offering installed packages/tools from `list` misreads the slot. The installed list belongs to remove/uninstall, not search.
- **The slot takes a path.** Native completion owns it (`R-10`): `--apks`, `--project <path>`, `open-file <path>` get a `usage` placeholder and nothing else.
- **The value is user-invented or too thin.** `label create <name>` (no source exists), `ssh-key delete <id>` (a round trip per keystroke for a value the user already knows).
- **The value is known at authoring time.** Fixed enums, agents, profiles go in manifest `next` (`R-16`) — a producer of constants is a `next` array, not a hook.
- **The query cannot be verified here.** Auth-gated, needs absent hardware, or empty locally with an unknown with-data shape (`android device remote`, `studio check`, `emulator list`) — deferred with the reason recorded in `WIP/<tool>/README.md`, never written blind.

## Targets and validation

`psc.on` targets refer to the `name` field of manifest items.
Two defects fail silently at runtime and no other gate catches them — a dangling target, and a target written as an alias instead of a `name`.
Always run `./scripts/check-hook-targets.ps1 <command>` whenever a `hooks.lua` exists or was touched, and `luac -p completions/<cmd>/hooks.lua` because nothing checks whether it compiles.
See [`validation.md`](validation.md).
