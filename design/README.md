# Design

Design documents for the PSCompletions system. These record **what the system is and why it is
built that way** — the decisions, constraints, and current state of the implementation. They are
the knowledge base for maintainers and for AI agents working on the repo.

> **Who reads what**:
> - Writing or updating completions / hooks → `AGENTS.md` first, then `hooks.md`.
> - Working on the engine / menu / CLI → the docs below.

## Index

| Doc | Status | Covers | Audience |
| --- | --- | --- | --- |
| [`README.md`](README.md) | — | this index | everyone |
| [`architecture.md`](architecture.md) | current | Project architecture: repo layout, the two Rust binaries (`psc-menu` / `psc`), end-to-end data flow, module responsibilities | everyone |
| [`completion.md`](completion.md) | current | The completion system: context & tree, resolve, predict symbols (`switch`/`stay`), repeat filtering, manifest format | engine developers, completion authors |
| [`menu.md`](menu.md) | current | The cross-platform TUI menu (Rust `psc-menu`): process model, input/output contract, lazy-tip protocol, rendering, minimal layout, menu config, ordering, robustness | engine / menu developers |
| [`protocol.md`](protocol.md) | current | The **engine contract** (`psc-menu` `--menu` / `--sort`): file-based JSON input/result schemas, shared types, build mode, restore rules — the host-agnostic surface any shell drives | engine developers, shell-host porters |
| [`filter-matching.md`](filter-matching.md) | current | How the menu filter matches items (subsequence / wildcard modes, `^` and `*` semantics) | engine developers, menu users |
| [`hooks.md`](hooks.md) | current | The Lua hooks subsystem: architecture, the **authoritative `psc.*` API reference** (context values, capability functions, prelude helpers, pitfalls, patterns, parallel primitives, security) | completion / hook authors, engine developers |
| [`psc-cli.md`](psc-cli.md) | current | The `psc` management CLI: architecture (separate binaries, data discovery, module bridge, workspace), dispatch, per-command syntax/behavior/errors, config inventory, reset matrix | CLI / module developers, completion authors for `psc` |

## Conventions

- **Language**: English (all design docs, matching `AGENTS.md`).
- **Present tense, current state only**: docs describe how the system **runs today** — not plans,
  proposals, or migration records. Historical/old-version content is deliberately dropped; when a
  doc disagrees with the code, fix the doc.
- **Cross-references** between docs use paths relative to the repo root (e.g. `design/menu.md`).
- **Scope**: these docs describe the system; the operative how-to for the completions workflow
  lives in `AGENTS.md`.
- **Granularity — contracts, decisions, invariants, not implementation**: a design doc records
  (1) cross-boundary contracts (protocol fields, API signatures, user-visible behavior,
  security/sandbox edges), (2) design decisions and their rationale, and (3) invariants and
  pitfalls that are easy to regress. It does **not** mirror implementation internals — render
  mechanics (diff flags, draw order), pixel/row layout constants, timing constants, and other
  `how the code does it today` details live in code comments and tests instead. When an
  implementation detail is worth mentioning, state the intent in one line and point at the code
  (e.g. `see core/engine/src/menu/ui.rs`) rather than reproducing it.
