# Working files (`WIP/`)

Writing or auditing a completion generates working material: analysis scripts, `--help`
dumps, parsed tables, diff plans, batch logs, translation dictionaries, snapshots. The
rule is `R-20` in `../AGENTS.md`; this file is the mechanism — where the material goes,
and what happens to it at the end of a task.

## One directory per completion

Everything a task generates goes in **`WIP/<tool>/`**, where `<tool>` is the completion's
directory name. Below that, the tree is **free**: collection and review are exploratory, and
the layout follows whatever the next step of the analysis needs. One shape that has worked:

```
WIP/<tool>/
├── README.md      # what this task is, what has been verified so far
├── help/          # <cmd> <sub> --help dumps, one file per page
├── plan.json      # write-once diff plan — see maintenance.md §Scripted realignment
└── *.py / *.ps1   # analysis scripts, one set per completion
```

The example is a starting point, not a schema. A tool with many subcommands may get one
subdirectory per command with its own dumps and proposed additions under each; a small tool
may be a single flat directory. Nothing here is checked, and nothing here is a defect: the
only fixed part is the `WIP/<tool>/` directory itself, so that two completions in flight
never share one.

**Not a shared system temp directory.** A temp directory looks equivalent and is not: it
has no per-task isolation, so two completions written concurrently overwrite each other's
scripts (`parse.py`, `fetch.ps1`), and the collision is silent until one of them parses the
other's data. Inside the project the material is also visible to whoever reviews the work,
which is the point of keeping it.

A `README.md` in the directory costs a minute and tells the next reader — often the
operator mid-review — what each file is without opening it.

## It is a pipeline artifact, never repo content

`WIP/` serves exactly one task — writing a completion, or auditing one — and ends with that
task. So it is **never committed and never pushed**, and it is **never gitignored either**:

- **Visible beats hidden.** An ignored directory drops out of `git status`, which is the one
  place the operator looks at the end of a session. Kept visible, it shows exactly which
  tasks still owe a cleanup.
- **Staging is allowed, pushing is not.** Staging `WIP/` for a comparison
  (`git diff --cached`) is a legitimate use; the pushed history is not. A commit of a
  completion carries `completions/<tool>/` and nothing else.
- **The end of the task is the operator's call, not the agent's.** The agent cannot know
  whether the author has accepted the result, so "the gates are green" is not the end of the
  task and is not a deletion trigger.

## The lifecycle

1. **Create it at the start of collection.** `collecting-info.md` §Knowing when
   collection is complete already emits to `WIP/<tool>/tree.json`; a large audit lays the
   batch structure out up front (`maintenance.md` §Large audits).
2. **Keep it through the gates.** The material is the evidence behind every value in the
   manifest. A plan file is write-once, and a verification report is written *beside* the
   plan, never over it.
3. **Hand it over, do not tidy it.** When the completion is done — gates clean,
   translation done — report the directory, its file count and total size, and ask whether
   to delete it. `R-20`.
4. **Delete only on confirmation.** The operator reviews after the gates, and a review
   that finds a wrong value needs the dumps and the diff plan to fix it fast. Deleting
   before that point is the one thing this rule forbids.

## What never happens

- **Nothing is deleted unilaterally** — not when the gates pass, not at the end of a
  session, not "to leave the tree clean". The recorded failure mode: an agent declared a
  completion finished, deleted the scripts it had generated, and the author then found
  defects — so the whole analysis had to be regenerated from zero, with the original probes,
  the parsed tables and the diff plan all gone.
- **No `WIP/` content in a commit or a push**, and no `.gitignore` entry for it either.
- **No shared temp directory** for two completions, and no scratch written inside
  `completions/<tool>/` — that directory holds the completion itself.
- **No selective tidy-up.** Either the operator confirmed the whole directory goes, or all
  of it stays; a half-deleted directory is the worst state, because the missing file is
  always the one the rework needs.
