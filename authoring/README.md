# Authoring

How to write and maintain a completion. This directory holds the working material —
procedure, field reference, examples, checklists — that is not carried in `AGENTS.md`
because it is not needed at every step of every task.

> **Canonical order.** `../AGENTS.md` carries the hard rules (`R-xx`): the ones that
> must hold at all times and that the validation scripts cannot see. This directory is
> reference and procedure. Where the two disagree, `../AGENTS.md` wins.

## Who reads what

- Writing or updating completions / hooks → `../AGENTS.md` first, then the docs below.
- Working on the engine / menu / CLI → `../design/`.
- Asking *why* a rule or a mechanism is shaped the way it is → `../decisions/`.

## Index

| Doc | Covers |
| --- | --- |
| [`collecting-info.md`](collecting-info.md) | Gathering facts from the CLI: recursive `--help` traversal, reading help by section, the subcommand probe, ground-truth verification, enumeration sources, alternative collection paths |
| [`manifest.md`](manifest.md) | The manifest as data: scaffold output, full worked example, field semantics, the `config.json` catalog, `tip` / `usage` / `example` format, duplicates |
| [`hooks.md`](hooks.md) | When a hook is warranted, the slot rule, and the path-candidate ban with its one exception |
| [`validation.md`](validation.md) | The three gates — what each reports and how to fix it, the pre-completion checklist, the portability audit |
| [`maintenance.md`](maintenance.md) | Updating an existing completion for a new tool version, translating to another language |
| [`tooling.md`](tooling.md) | `pwsh` vs `powershell.exe`, `ajv-cli`, `luac -p`, recovering schema error paths |

## Which question goes where

| Question | Answer lives in |
| --- | --- |
| "What must I never get wrong?" | `../AGENTS.md` — the `R-xx` rules |
| "How do I do this task?" | here |
| "What does this field do, and why?" | `../design/completion.md` |
| "Why is the rule shaped this way?" | `../decisions/` |

## Conventions

- **Language**: English, matching `../AGENTS.md` and `../design/`.
- **Procedure, not semantics.** Field *meaning* and engine behaviour belong in
  `../design/completion.md`; a worked example or a step belongs here. Do not restate an
  engine contract in order to explain a step — link to it.
- **Cross-references** are written as markdown links that resolve from the file that
  contains them (e.g. `../design/completion.md`). `scripts/check-doc-links.ps1` verifies
  that they resolve; a dead link here is a defect.
- **Rule statements are not duplicated here.** The rule statement is in `../AGENTS.md`;
  this directory may add mechanism, examples, and depth, but must not offer a second
  wording of the same rule.
