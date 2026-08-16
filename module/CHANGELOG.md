# Module Changelog

[简体中文](./CHANGELOG.zh-CN.md)

## 7.1.0

- Improved the output of completion state changes and the update logic.
- Added a stable `id` to every completion's `config.json`, enabling rename detection and automatic migration.

## 7.0.3

- Fixed `psc.run` executing in the terminal's startup directory instead of the current working directory.

## 7.0.2

- Fixed duplicate output when updating completions.
- Unified the values of boolean configuration to 1/0.

## 7.0.1

- Fixed the command parameter verification error.
- Fixed the color of command output.

## 7.0.0

### A New Cross-Platform Interactive Menu

- **Minimal visuals**: red focus, cyan highlight, clean and simple
- **Rust-native rendering**: replaces the old PowerShell rendering with much better rendering and smoothness
- **Available everywhere**: a consistent interactive completion experience on Windows PowerShell 5.1 / PowerShell 7 / Linux / macOS

### A Standalone Completion Engine

- Parsing, context resolution, dynamic script execution, and candidate generation are all done independently by the Rust binary
- No longer coupled to a specific shell, laying the groundwork for future shells

### More Powerful Completion Filtering

- **Wildcard fuzzy matching**: no need to remember full names, `g*t` matches both `git` and `gist`; matching characters are highlighted in real time as you type
- **Quick subsequence switching**: a leading `*` temporarily switches to subsequence matching in wildcard mode, e.g. `*vscode` quickly locates `Visual Studio Code`
- **Prefix anchoring**: `^git` restricts matches to items starting with `git`, more precise filtering

### Smarter Completion Ordering

- The ordering algorithm was fully upgraded: **time decay** + **position weighting**, so recently and deeply used commands rank higher
- Path completions are ordered by segment; directories and files are ranked by usage history, with frequently visited directories shown first

### Dynamic Completions (Lua)

- Dynamic completions migrated from PowerShell scripts to **Lua**: embedded in the Rust engine for faster startup and more stable parsing
- Scripts run in an isolated sandbox: restricted standard library, command timeouts, read-only files

### Completion Information Tips

- Tips upgraded to structured containers: `[Usage]`, `[Description]`, `[Example]`
- Size adapts to content, with wheel scrolling for multi-line content

### Completion Predict Symbols

- Simpler semantics: a symbol means there are more completions to pick after applying
  - `switch`: switches to a new context after applying, default `~`
  - `stay`: stays in the current context after applying, default `?`
- The symbol follows the current selection and is shown next to the counter, keeping the list clean

### Prefix Pre-filtering

- Opening the menu after typing some text auto-filters by what you typed, straight to the target
- Clearing the pre-filter falls back to the full completion list

### Mouse Support

- Click to select, double-click to apply, wheel to browse, covering the whole completion menu

## [Older versions](./archive/CHANGELOG.md)
