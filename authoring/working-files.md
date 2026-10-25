# Working files (`WIP/`)

Writing or auditing a completion generates working material: analysis scripts, `--help` dumps, parsed tables, diff plans, batch logs, translation dictionaries, snapshots.
The rule is `R-20` in `../AGENTS.md`; this file is the mechanism — where the material goes, and what happens to it at the end of a task.

## One directory per completion

Everything a task generates goes in **`WIP/<tool>/`**, where `<tool>` is the completion's directory name.
Below that, the tree is **free**: collection and review are exploratory, and the layout follows whatever the next step of the analysis needs.
One shape that has worked:

```
WIP/<tool>/
├── TODO.md        # session record: phases, current step, exact resume command
├── README.md      # what this task is, what has been verified so far
├── help/          # <cmd> <sub> --help dumps, one file per page
├── plan.json      # write-once diff plan — see maintenance.md §Scripted realignment
└── *.py / *.ps1   # analysis scripts, one set per completion
```

A maintenance pass leaves five kinds of evidence, so the next update diffs against a record instead of re-deriving one:

- `source-options.json` — the table you harvested, with the surface it came from and that surface's version;
- `coverage.json` — documented spellings minus manifest spellings (empty), plus the manifest-only list;
- `slots.json` — one row per value slot with its kind, source, verdict and reason (see [`collecting-info.md`](collecting-info.md) §Record every value slot while you collect);
- `deleted.json` — every removed spelling with the CLI's refusal text;
- `README.md` — the before/after counts, the batches, and what is left undone.

The example is a starting point, not a schema.
A tool with many subcommands may get one subdirectory per command with its own dumps and proposed additions under each; a small tool may be a single flat directory.
Nothing here is checked, and nothing here is a defect: the only fixed part is the `WIP/<tool>/` directory itself, so that two completions in flight never share one.

**Not a shared system temp directory.** A temp directory looks equivalent and is not: it has no per-task isolation, so two completions written concurrently overwrite each other's scripts (`parse.py`, `fetch.ps1`), and the collision is silent until one of them parses the other's data.
Inside the project the material is also visible to whoever reviews the work, which is the point of keeping it.

A `README.md` in the directory costs a minute and tells the next reader — often the operator mid-review — what each file is without opening it.

## The session record (`TODO.md`)

Every task gets a `TODO.md` before collection starts.
It is the **first file read when a session resumes** and the **last file written before a session ends**, because the chat history is the one thing a context limit actually destroys.

`README.md` records the task and its evidence; `TODO.md` records **state**:

- the one-line goal and the source/version, plus whether the binary is installed;
- the phase checklist (preflight, collect, coverage diff, rebuild, translate, slots, hooks, gates, guide, commit), each marked done or not;
- the **next step as an executable command or a file path** — never "continue the tool";
- open questions, blockers, and the installs still needed;
- the evidence files produced so far, and the gate status;
- a `Session log` of date + what changed + what is next.

A template:

```markdown
# <tool> — session record

Goal: maintain <tool> <version> and derive guide lessons.
Source: `help/` (version), binary installed: yes/no.

## Phases
- [x] preflight
- [ ] collect
...

## Next
Run: `python3 WIP/<tool>/compare.py`
Then: rebuild `en-US.json` from `source.json`.

## Open
- ...

## Session log
- 2026-10-01: collected all pages; coverage 0 missing.
```

The exactness of the next step is the point: "next: rebuild" is not resumable; "next: run `python3 WIP/<tool>/compare.py`, then apply `plan.json` to `en-US.json`" is.
This file is working material like the rest of `WIP/` — never committed, deleted only with the directory, on the operator's confirmation.

## It is a pipeline artifact, never repo content

`WIP/` serves exactly one task — writing a completion, or auditing one — and ends with that task.
So it is **never committed and never pushed**, and it is **never gitignored either**:

- **Visible beats hidden.** An ignored directory drops out of `git status`, which is the one place the operator looks at the end of a session. Kept visible, it shows exactly which tasks still owe a cleanup.
- **Staging is allowed; committing and pushing are not.** Staging `WIP/` for a comparison (`git diff --cached`) is a legitimate use; a commit and a push are not. A commit of a completion carries `completions/<tool>/` and nothing else.
- **The end of the task is the operator's call, not the agent's.** The agent cannot know whether the author has accepted the result, so "the gates are green" is not the end of the task and is not a deletion trigger.

## The lifecycle

1. **Create it at the start of collection.** `collecting-info.md` §Knowing when collection is complete already emits to `WIP/<tool>/tree.json`; a large audit lays the batch structure out up front (`maintenance.md` §Large audits).
2. **Keep it through the gates.** The material is the evidence behind every value in the manifest. A plan file is write-once, and a verification report is written *beside* the plan, never over it.
3. **Hand it over, do not tidy it.** When the completion is done — gates clean, translation done — report the directory, its file count and total size, and ask whether to delete it. `R-20`.
   In a colocated Jujutsu working copy the operator can move the working copy between sessions (`jj new`, `jj undo`, a rebase); material held only by the previous working copy is then no longer on disk. Report the directory at hand-off rather than after the session, and check `jj op log` before assuming lost material is unrecoverable.
4. **Delete only on confirmation.** The operator reviews after the gates, and a review that finds a wrong value needs the dumps and the diff plan to fix it fast. Deleting before that point is the one thing this rule forbids.

## Pipeline script hygiene

Three habits that cost minutes and save re-derivations:

- **Guard the entry point.** A pipeline script (`parse.py`, `gen.py`) ends with `if __name__ == "__main__":`, never a bare `main()` call — a debug script that imports the module to reuse one function otherwise re-runs the whole pipeline and rewrites its outputs as a side effect.
- **Re-run the full pipeline after editing any stage.** A `parsed.json` older than the `parse.py` that supposedly produced it explains every "the fix had no effect" mystery; when results look stale, compare mtimes before re-debugging.
- **Script bulk insertions into manifests; parse-check after every hand edit.**
Appending nodes by text-splicing at an array tail silently eats closers, and the parse error surfaces far from the cause.
Beyond a handful of entries use a load/append/dump script; either way, prove the file still parses before writing the next batch.
- **`__pycache__/` is generated output.** Python writes it beside the scripts on first run; it is never reviewed and never staged — remove it with the directory.

## Running a script is the dangerous step

Writing a script is cheap; running it is not — a script runs with the author's full filesystem access, and a wrong path in a delete call destroys what no gate can rebuild.
The same test applies to a **single command**: `rm`, `rmdir`, `mv`, `cp`, `truncate`, `dd`, shell redirection, `chmod` / `chown`, and archive extraction are reviewed exactly like a script, and a delete or overwrite outside `WIP/<tool>/` is a proposal until the operator confirms it (`R-26`).
Think three times before every run, and treat this section as harder than every other rule in this file:

- **Read the whole script before running it.** No blind runs — not "it looks standard", not "I only changed one line". A deletion can hide in a helper, an import-time side effect, or a default argument (`shutil.rmtree(path)` where `path` fell back to something wide). If you did not read it, you do not run it.
- **Never run a deletion outside `WIP/<tool>/` without explicit operator confirmation.** `rm -rf`, `shutil.rmtree`, `os.remove`, `remove_dir_all`, `git clean -fdx` — against anything outside the task directory, each of these is a proposal, not a command: state exactly what will be removed and wait for confirmation. Version control is not a safety net — the recorded incident deleted `.git` along with the tree, so there was nothing to revert to, and ready-to-release work was permanently lost. See [`D38`](../decisions/authoring.md#d38).
- **Scripts write where the task needs; only removal needs confirmation.** Writing is recoverable — git restores any overwritten file, so pipeline scripts do their normal job (dumps under `WIP/<tool>/`, realignments into `completions/`) without asking. Deletion is not: once the tree (or `.git` itself) is gone there is nothing to check out from. Nothing ever writes into `.git/` directly — only git itself goes there.
- **Mutate last, preview first.** Prefer a `--dry-run` / print-the-plan pass before any run that creates, moves, or rewrites files outside `WIP/`; read the plan output before the real run.
- **Python specifics.** `pathlib` writes stay under `WIP/<tool>/` (resolve the path and check the prefix when it is built from variables); `subprocess` calls are read with the same care as the script itself — a shell string concatenates the same way in every language.

## What never happens

- **Nothing is deleted unilaterally** — not when the gates pass, not at the end of a session, not "to leave the tree clean". The recorded failure mode: an agent declared a completion finished, deleted the scripts it had generated, and the author then found defects — so the whole analysis had to be regenerated from zero, with the original probes, the parsed tables and the diff plan all gone.
- **No `WIP/` content in a commit or a push**, and no `.gitignore` entry for it either.
- **No shared temp directory** for two completions, and no scratch written inside `completions/<tool>/` — that directory holds the completion itself.
- **No selective tidy-up.** Either the operator confirmed the whole directory goes, or all of it stays; a half-deleted directory is the worst state, because the missing file is always the one the rework needs.
