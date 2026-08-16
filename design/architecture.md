# Design: Project Architecture

> How the whole PSCompletions repository is laid out and how the pieces talk to each other.
> Companion docs: `completion.md` (context/resolve/manifest), `hooks.md` (Lua hooks),
> `menu.md` (TUI menu), `protocol.md` (engine JSON contract), `psc-cli.md` (management CLI),
> `filter-matching.md` (menu filter).

## 1. Overview

PSCompletions is a **tab-completion manager for PowerShell**. It keeps **completion
definitions** (JSON manifests describing each CLI tool's subcommands, options, aliases and
tooltips) plus optional **Lua hooks** for dynamic values, and renders them through a
**cross-platform Rust engine + TUI menu**. The whole completion pipeline (parse manifest →
resolve context → run hooks → produce candidates) runs in Rust, so behavior is identical on
Windows PowerShell 5.1 and PowerShell 7+.

## 2. Repository layout

```
PSCompletions/
├── completions/            # Completion definitions (the "data" of the system)
│   └── <command>/
│       ├── config.json     # Per-completion config: language, hooks flag, trigger alias, stable id
│       ├── hooks.lua       # Dynamic completions (present only when config.json has hooks: true)
│       └── language/
│           ├── en-US.json  # English completion data (single source of truth)
│           └── zh-CN.json  # Chinese translation (same structure)
├── completions.json        # Completion index — auto-generated, DO NOT edit
├── schema/                 # JSON Schemas (completion-manifest, completion-config)
├── scripts/                # Authoring / validation / CI tooling (PowerShell)
│   ├── create-completion.ps1       # scaffold a new completion from the template
│   ├── compare-json.ps1            # diff + sort en/zh manifests (validate a completion)
│   ├── sort-json.ps1               # normalize field order (called by compare-json)
│   ├── validate-completion.ps1     # full validation: schema + config.json + hooks.lua + compare rules
│   ├── check-completion.ps1        # CI/PR check: scan changed completions, post a report
│   ├── link-completion.ps1         # symlink a completion into the local module for live testing
│   ├── update-content.ps1          # CI: regenerate completions.json index + completions.md tables
│   ├── push-change.ps1             # CI: commit/push generated content back to main
│   ├── build-release.ps1           # local release build: cargo fmt + build (+zigbuild cross) → bin/
│   └── utils.ps1                   # shared helpers for the scripts
├── design/                 # This knowledge base (authoritative "how the system works")
├── types/                  # EmmyLua type stub for the psc.* API (editor LSP in hooks.lua)
├── module/PSCompletions/   # The PowerShell host (PSCompletions.psd1/.psm1/.ps1 + bin/)
└── core/                   # Rust workspace
    ├── engine/             # psc-menu: completion engine + TUI menu (a single binary)
    └── cli/                # psc: management CLI (a separate binary)
```

## 3. The two Rust binaries

**`core/engine` → `psc-menu`** — the runtime heart. Two modes driven by flags:

- (menu mode) `psc-menu <input.json> --result <out.json>`: renders the
  interactive TUI menu, handles keyboard/mouse, and writes back the selection / cancel /
  filter-text outcome. When the input carries a `build` context instead of `items`, the engine
  builds the candidates itself first (manifest → tree → resolve → run hooks → order-sort) — so
  installed-command completion runs in a **single process call**.
- `--sort <input.json> --result <out.json>`: ranks host-provided items (native fallback)
  against the history-order files.

**`core/cli` → `psc`** — the management CLI (installed as `psc`): `add`/`rm`/`update`/
`info`/`list`/`alias`/`completion`/`config`/`init`/`check`. It owns the **config registry** and
**key migration** (see `psc-cli.md`), reads/writes `settings.json`, and handles network
operations (fetching completions). Resets are handled by the host's `--reset` flag.

## 3.1 Building & shipping binaries

`scripts/build-release.ps1` is the local release path: it runs `cargo fmt --all`, then
`cargo build --release` (host) or `cargo zigbuild --release --target <triple>` (cross), and
copies `psc-menu` + `psc` into `module/PSCompletions/bin/<platform>-<arch>/`. The module picks
the right binary per platform/arch at import time. A host build is detected from
`$IsWindows`/`$IsMacOS` plus the process architecture; cross builds need `rustup target add
<triple>` (and zig for zigbuild).

The CI build job (`.github/workflows/ci.yml`) produces the same binaries on its own hosted
runners: plain `cargo build --release` (cross targets via the runner's toolchain), then uploads
them as build artifacts — it does not run `cargo fmt` or zigbuild.

## 4. End-to-end flow

```
user types `git <Tab>`
  │
  ▼
PowerShell host (PSCompletions.ps1)
  • splits the buffer into tokens, resolves trigger alias
  • assembles a menu input carrying a `build` context (cmd, arg_tokens, manifest, hooks,
    config, psc data, order paths) — not items
  • launches psc-menu (menu mode) as a child process
  │
  ▼
psc-menu (menu mode, build context)
  • builds the Tree from the manifest
  • resolve(): classifies tokens (command/option/value/unknown), walks context,
    tracks used/repeat, computes pending + canonical names
  • runs hooks.lua (if enabled) → merges dynamic items
  • order-sorts the candidates, derives initial_filter (^pending)
  • renders the TUI menu, handles keyboard/mouse
  • writes out.json: selected item index / cancel / filter text
  │
  ▼
PowerShell host applies the selection (PSConsoleReadLine::Replace); the
  psc-menu process writes the order files on a background thread for history-based
  sorting on the next menu (the host only passes the order paths)
```

## 5. Module responsibilities

The PowerShell host (`module/PSCompletions/PSCompletions.ps1`) is the **bridge**:

- Registers the Tab key handler, captures the buffer and cursor.
- Passes the `build` context into the menu process (the engine builds + ranks the candidates
  itself; installed-command completion is a single process call).
- Invokes the menu process, saves/restores the covered terminal region (input line is never
  saved/restored to preserve true-color prompts), and applies the chosen completion.
- Detects completion failure (stderr / exit code) and reports a clear error
  (`[PSCompletions] menu unavailable: ...`).
- `psc-menu` and `psc` binaries ship inside `module/PSCompletions/bin/`.

## 6. Where each concern is documented

| Concern | Doc |
| --- | --- |
| Completion context, resolve, predict symbols, manifest format | `completion.md` |
| Lua hooks (`psc.*` API, prelude, semantics) | `hooks.md` |
| TUI menu (process model, layout, tips, ordering) | `menu.md` |
| Engine JSON contract (`--menu` / `--sort` input & result schemas) | `protocol.md` |
| `psc` management CLI (commands, config registry, migration) | `psc-cli.md` |
| Menu filter matching (subsequence / wildcard) | `filter-matching.md` |
| How to author / validate completions (operative rules) | `AGENTS.md` |
