# Module Changelog

[简体中文](./CHANGELOG.zh-CN.md) | [English](./CHANGELOG.md)

## Unreleased

## 6.5.1

- Fix the problem of comparing completions.json files.

## 6.5.0

- psc command will ignore invalid sub-commands, and execute the same behavior.
  1. Reload module key bindings and data.
  2. Show module information.
- Add multiple pure color themes to the module completion menu.
  - Set them with `psc menu color_theme`.
  - Also recommend using `psc menu custom color` to customize.
- Improve completion update mechanism by switching to content-based hashing.
- Other optimizations and fixes.

## 6.4.0

- Add `enable_menu_show_below` configuration item.
  - Enable it: `psc menu config enable_menu_show_below 1`
  - When the module completion menu needs to be displayed above the cursor, scroll the content buffer to let the cursor return to the top, and display the menu below the cursor.
  - As long as you can accept that the old buffer content needs to be scrolled up to view, it is a perfect solution to solve the [buffer redraw problem](https://github.com/abgox/PSCompletions/issues/93).
- Remove the binding of `Left` and `Right` arrow keys.
  - They are also used to select the previous and next completion items, which are not common.
  - Now, they are reserved, and future versions may bind other functions to them.
- Fix completion trigger with path separator in root command.
  - Take `scoop-checkver` completion as an example, it uses `.\bin\checkver.ps1` as the root command.
  - Now, it can trigger completion as expected.
- Optimize the output of the module, making it more clear and readable.
- Other optimizations and fixes.

## 6.3.3

- Expose the module completion menu to allow external call.
  - You can bind the module completion menu directly using `Set-PSReadLineKeyHandler -Key <Key> -ScriptBlock $PSCompletions.menu.module_completion_menu_script`.
  - It will assume `enable_menu` and `enable_menu_enhance` are `1`, ignoring the actual configuration values.
  - It is not recommended to use it unless there is a special need and both `enable_menu` and `enable_menu_enhance` are actually `1`.
- Fix the issue that some special configurations are invalid due to the special behavior of logical comparison operators in PowerShell.
- Other optimizations and fixes.

## 6.3.2

- Fix the display of ToolTip.
- Improve the handling for the completion item when it is applied.
- Other optimizations and fixes.

## 6.3.1

- Use the hardcoded 'PSCompletions' as the exported function name. ([#129](https://github.com/abgox/PSCompletions/issues/129))
- Remove any possible ANSI color codes to display normally (only for the completion menu provided by the module).

## 6.3.0

- Now, run `psc` will reload the key bindings and data of the module, then print the help information.
  - In older versions, using `. $Profile` would invalidate the key bindings of the module.
  - Now, just run `psc` to restore the normal use of the module.
- Use the correct regional encoding when rendering the completion menu. ([#127](https://github.com/abgox/PSCompletions/issues/127))

## 6.2.6

- Handle errors silently when clearing change.txt file.

## 6.2.5

- Set the encoding before getting the buffer to ensure the consistency of redrawing.

## 6.2.4

- Optimize the way to obtain the original output encoding.
  - Previously, you had to import the `PSCompletions` module first to modify the encoding, otherwise it may cause encoding issues.
  - With the new way, there is no order limitation anymore.
- Other optimizations and fixes.

## 6.2.3

- Reuse `Add-Member` to avoid buffer access error. ([#122](https://github.com/abgox/PSCompletions/issues/122), [#124](https://github.com/abgox/PSCompletions/issues/124))
  - The [CompletionPredictor](https://www.powershellgallery.com/packages/completionpredictor) module will prevent PSCompletions from accessing the buffer, including related variables and methods.
  - Using `Add-Member` can avoid it, but the specific reason is not quite clear.
- Fix the problem that [CompletionPredictor](https://www.powershellgallery.com/packages/completionpredictor) module will cause core script to load multiple times.
- Fix the problem that command with wildcard will cause completion error.
  - Now, inputs like `[xxx]`, such as `[env]`, can also get relevant completion items.
- Other optimizations and fixes.

## 6.2.2

- Improve the width check to avoid some special cases when `enable_list_full_width` is `0`.
  - Recommend setting `enable_list_full_width` to `1`, as it is the current optimal experience.
  - Set: `psc menu config enable_list_full_width 1`
- Other optimizations and fixes.

## 6.2.1

- Add alias support for `$PSCompletions.argc_completions()`
  - Refer to: [Combine with argc-completions](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions).
  - Thanks to [@CallMeLaNN](https://github.com/CallMeLaNN) for the [implementation reference](https://github.com/sigoden/argc-completions/issues/65#issuecomment-3642388096).
- Strip possible ANSI escape codes from the completion items.
  - Refer to: [#121](https://github.com/abgox/PSCompletions/issues/121)
  - [PSCompletions can work normally with Carapace.](https://pscompletions.abgox.com/faq/pscompletions-and-carapace)
- Optimize command and alias checking.
- Other optimizations and fixes.

## 6.2.0

- Add `enable_list_full_width` configuration item, used to control whether the completion menu is displayed in full width.
  - Refer to: [#117](https://github.com/abgox/PSCompletions/issues/117)
  - It is enabled by default.
  - It can reduce the complexity of related calculations from `O(n)` to `O(1)`, comparable to the response performance of the native completion menu.
  - If you don't like the full-width display, please run `psc menu config enable_list_full_width 0`.
- Add `height_from_menu_top_to_cursor_when_below` configuration item for completion menu.
- Simplify the color theme of the completion menu.
  - Remove some redundant color configuration items.
  - Change the names of some color configuration items, you may need to re-set them if you have customizations.
- Use `single_line_round_border` as the default line theme for the completion menu.
- Remove newline characters in `tip` fields of all completion files, added automatically when loading completions.
- Disable completion suffix when there is a space after the cursor.
- Limit the value of `completion_suffix` to be one or more spaces.
- Fix the issue where special symbols (`~?!`) provided by the module are missing when `enable_tip` is `0`.
- Fix the issue where the completions of the `WriteSpaceTab` type are not working.
- Other performance optimizations and fixes.

## 6.1.0

- Completion library has some breaking changes, please update all completions after updating the module.
  - Update command: `psc update * --force`
- When filtering, ignore the special symbols (`~?!`) provided by the module in the completion items.
- Fix the issue where including `[` triggers a completion error.
- Fix the completion trigger timing of the root command.
- Many performance optimizations.

## 6.0.3

- Handle empty tip in menu rendering.

## 6.0.2

- Reduce unnecessary string matching and parsing.
- Check administrator permission.
  - If `-Scope AllUsers` is specified when installing the module, the module will be installed in the system-level directory.
  - In this case, the module can only be run with administrator permission.

## 6.0.1

- Reduce the redraw range of the buffer.

## 6.0.0

- Refactor the completion menu, which significantly improves the completion response speed.
- Remove the `enable_prefix_match_in_filter` configuration.
  - Now the filtering uses fuzzy matching, supporting three matchers: `^?*`
  - Use `^` instead of the previous prefix matcher.
- Remove some less commonly used configurations.
  - `enable_list_cover_buffer`
  - `enable_tip_cover_buffer`
  - `enable_selection_with_margin`
  - `width_from_menu_left_to_item`
  - `width_from_menu_right_to_item`
- Other optimizations and fixes.

## [Older versions](./archive/CHANGELOG.md)
