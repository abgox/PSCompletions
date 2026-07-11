# PSCompletions

A completion manager for a better and simpler tab-completion experience in PowerShell.

## Project Structure

```
PSCompletions/
├── completions/              # All completion definitions
│   └── <command>/
│       ├── config.json       # Completion config (language, hooks, alias)
│       ├── hooks.ps1         # Dynamic completions (only if hooks: true)
│       └── language/
│           ├── en-US.json    # English completion data
│           └── zh-CN.json    # Chinese completion data
├── completions.json          # Completion index (DO NOT manually edit, auto-updated by CI/CD)
├── schema/                   # JSON Schema definitions (for IDE validation)
├── scripts/                  # Utility scripts
│   ├── create-completion.ps1 # Create new completion from template
│   ├── compare-json.ps1      # Compare completion differences (includes sorting)
│   ├── sort-json.ps1         # Sort and optimize completion JSON (called by compare-json.ps1)
│   ├── link-completion.ps1   # Link completion dir for local testing
│   ├── template/             # Template files for new completions
│   └── language/             # Localized text for scripts themselves
└── module/PSCompletions/     # PowerShell module
    ├── PSCompletions.psd1    # Module manifest
    ├── PSCompletions.psm1    # Module entry point
    └── PSCompletions.ps1     # Initialization script
```

## Completion Data Structure

> **Important**: Before modifying any completion data, read `schema/completion-manifest.en-US.json` to understand the strict structure definition. This ensures correct field types and formats.

Each completion's `language/<locale>.json` file contains these top-level fields:

```json
{
  "meta": {
    "url": "https://example.com/",
    "description": ["Short description of the tool"]
  },
  "root": [...],           // List of subcommands
  "option": [...],         // Root-level options (e.g., --version)
  "common_option": [...]   // Common options shared by all subcommands (e.g., --help)
}
```

### Field Descriptions

- `root`, `option`, `common_option` are optional. If empty, remove the field entirely instead of keeping an empty array.

#### `root` - Subcommand List

Each subcommand is an item object:

```json
{
  "name": "install",           // Required: the longest/full name
  "alias": ["i"],              // Optional: remaining shorter names
  "tip": [                     // Optional: tooltip info array
    "U: install [FLAGS] [TOOL@VERSION]...",  // Usage line (U: = Usage)
    "Install a tool version"                  // Description line
  ],
  "repeat": 1,                 // Optional: not set = no repeat, number = max repetitions
  "option": [...],             // Optional: options for this subcommand
  "next": [...]                // Optional: next-level completions (sub-subcommands or argument values)
}
```

**Naming convention**: `name` should be the longest/full name, and `alias` should contain the remaining shorter names.

> **Important**: If `name` contains spaces, it MUST be wrapped in quotes (single or double) to pass schema validation.

#### `option` - Options

Options are also item objects, but cannot nest `option` (only `next`):

```json
{
  "name": "--force",
  "alias": ["-f"],
  "tip": ["U: -f, --force", "Force reinstall even if already installed"],
  "next": 0 // 0 means user needs to input a value
}
```

#### `next` Field

- `next: 0` - User needs to freely input a value
- `next: [...]` - Fixed list of completion options

**Important**: If the description mentions specific allowed values, add them as `next` items instead of using `next: 0`. This enables better completion suggestions.

#### Duplicate Prevention

Within the same level (same array), there should be no duplicate `name` values:

- `root` array: no duplicate subcommand names
- `option` array: no duplicate option names
- `common_option` array: no duplicate option names
- `next` array: no duplicate item names

#### `option` vs `common_option`

Do NOT duplicate the same option in both `option` and `common_option`. Pick one based on where it's available:

| Availability                                              | Where to put                     |
| --------------------------------------------------------- | -------------------------------- |
| Only at root level (e.g., `--version`)                    | `option`                         |
| At root AND all subcommands (e.g., `--help`, `--verbose`) | `common_option`                  |
| Only for specific subcommands                             | That subcommand's `option` array |

- `option` items are shown **only at the root command level**
- `common_option` items are shown **for all completions** — root level and every subcommand
- If a subcommand has its own `option` array, do NOT repeat options from `common_option` — they are already available

Typical pattern: `--help` goes in `common_option` (works everywhere), `--version` goes in `option` (root-level only).

#### `tip` Format Rules

- Each array element is one line, no line breaks allowed
- Spaces required between Chinese/English characters
- **Usage line** (`U:` prefix): List aliases with different separators for commands vs options
  - Subcommands use `|`: `U: add|install <app>`
  - Options use `,`: `U: -g, --global` or `U: -g, --global <xxx>`
- **Usage line must start from the current command level, NOT the root command**
  - Root level subcommand: `U: install [FLAGS]` (not `U: tool install [FLAGS]`)
  - Nested subcommand: `U: config set <key> <value>` (not `U: tool config set <key> <value>`)
  - The usage line shows how to invoke THIS command, so it starts with this command's name
- **Description line**: Brief explanation of what this item does
- **Example line**: `E: scoop install git` or `E: --color always`
- If `tip` exists, it must contain at least a description line — cannot be only a usage line

## Completion `config.json`

```json
{
  "language": ["en-US", "zh-CN"], // Required: available languages
  "alias": ["cmd", "cmd.exe"], // Optional: trigger aliases
  "hooks": true // Optional: enable dynamic completions
}
```

- `language` (required): Array of locale strings corresponding to files in `language/`
- `hooks` (boolean): Set `true` to enable `hooks.ps1` for dynamic completions. If not needed, remove this field.
- `alias` (array): Alternative command names that trigger this completion. If not set, the directory name is used.

## Adding New Completions

> **Scope**: Only modify files within `completions/<command>/`. Do not modify other project files unless explicitly required.

### Steps

1. **Create completion directory and files**

   Run the creation script to copy template files to `completions/<command>/` via `pwsh`:

   ```powershell
   .\scripts\create-completion.ps1 <command>
   ```

   The template includes `hooks: true` in `config.json` and a `hooks.ps1` file. If dynamic completions are not needed, remove `hooks: true` from `config.json` and delete `hooks.ps1`.

2. **Collect command information**

   Get from `<command> --help` or official docs:
   - All subcommands and their descriptions
   - **Each subcommand's options and arguments**
   - Option aliases
   - Value types for options (fixed value list vs free input)

3. **Write completion data**

   Fill in JSON files following the schema. For reference, see high-quality completions like `git`, `jj`, `npm`, `cargo`. Make sure to include all subcommands, all options for each subcommand, and common options in `common_option`.

4. **Verify and sort (required)**

   ```powershell
   .\scripts\compare-json.ps1 <command>
   ```

   This will show structural differences between different languages, and untranslated tips. Fix all reported issues before considering the task complete.

## Dynamic Completions (hooks.ps1)

For dynamic completions (reading from local files, environment variables, or running commands), create a `hooks.ps1`. See `scripts/template/hooks.ps1` for the standard template and `completions/git/hooks.ps1` for a real-world example.

Key API:

- `$PSCompletions.tokens` - Parsed token array, each with `text` and `type` properties
- Token types: `command`, `option`, `unknown`, `value`
- `$PSCompletions.pending` - The pending (incomplete) token, with `text` and `type` properties
- `$PSCompletions.return_completion($name, $tip, $symbol)` - Create a completion item

## Updating Completions

When a tool releases a new version with new subcommands or options:

1. Run `<command> --help` or check the official changelog for changes
2. Compare the current completion with the actual CLI output to identify differences
3. Add/update in `language/en-US.json`, then sync to `language/zh-CN.json`
4. Run `.\scripts\compare-json.ps1 <command>` to verify

> **Note**: `compare-json.ps1` also runs `sort-json.ps1` internally. The sorting logic may change many fields — focus on the content differences, not formatting changes.

## Translating Completions

1. **Keep structure consistent** - The translated file's JSON structure must match the English file exactly
2. **Only translate tip content** - `name`, `alias`, and other fields don't need translation
3. **Space between Chinese and English** - Spaces required between Chinese and English/numbers
4. **Don't translate proper nouns** - Command names, option names, tool names stay as-is
