<p align="center">
    <a href="./CHANGELOG-CN.md">简体中文</a>|
    <a href="./CHANGELOG.md">English</a>
</p>

## 5.0.4 (2024/9/1)

- Fix the issue that the `psc rm *` command will reset all configuration items.
- Other optimizations and fixes.

## 5.0.3 (2024/8/31)

- Fix the error that the `psc` subcommand runs into an error.
- Other optimizations and fixes.

## 5.0.2 (2024/8/31)

- Remove unnecessary file I/O operations.
- Other optimizations and fixes.

## 5.0.1 (2024/8/31)

- Fix the issue that `psc` did not add after updating the module version.

## 5.0.0 (2024/8/30)

- Reduce file I/O operations and optimize initialization method to improve first load speed.
  - Remove the **alias.txt** file in each completion directory, and use **data.json** to store data.
- Merge configuration data file **config.json** into **data.json**.
  - Note: If you use scoop to install `PSCompletions`, please check the manifest (persist) to update to **data.json**.
- Modify the name of almost all configuration items.
  - The name of the configuration item has been modified, and it will not affect normal use. When the version is updated, it will automatically migrate the old configuration item to the new configuration item.
  - For example:
    - `update` => `enable_completions_update`
    - `module_update` => `enable_module_update`
    - `menu_show_tip` => `enable_tip`
    - ...
- Remove two configuration items: `github` and `gitee`.
  - If you need to customize the url, please use the `url` configuration item.
  - `psc config url <url>`
- Other optimizations and fixes.

## 4.3.3 (2024/8/27)

- Fix an error that occurred when `menu_is_prefix_match` was enabled, due to the input after public prefix extraction.

## 4.3.2 (2024/8/18)

- Fix a method(`show_module_menu`) parameter type conversion error.

## 4.3.1 (2024/8/18)

- Add a configuration item `menu_is_loop`, controlling whether the menu is looped, with a default value of `1`.
  - Disable it: `psc menu config menu_is_loop 0`
- Optimize the migration logic of old versions.

## 4.3.0 (2024/8/15)

- Fix module update issue in `Windows PowerShell`.
- Fix dynamic completion sorting failure.
- Fix a issue in version comparison.
  - To avoid version comparison errors, this version number is changed from `4.2.10` to `4.3.0`.

## 4.2.9 (2024/8/15)

- Fix some issues.
- Optimize some logic, improve performance.

## 4.2.8 (2024/8/12)

- Fix a rendering error caused by a boundary case.

## 4.2.7 (2024/8/12)

- `PSCompletions` module will take up two global names, `$PSCompletions` (variable) and `PSCompletions` (function).
  - Now, they are both read-only, and trying to overwrite will have an error, preventing accidental operation from causing the module to fail.
  - However, `PSCompletions` (function) can be configured to change the function name.
- Add a configuration item `function_name`, with a default value of `PSCompletions`.
  - Setting: `psc config function_name <name>`
  - Use in the following case:
    - When you need to define a function, the name must be `PSCompletions`.
    - You can use `function_name` to rename the function of this module to a non-conflicting name.
  - Note:
    - `PSCompletions` (function) can be configured, but `$PSCompletions` (variable) cannot be modified.
- When you need to define a variable, the name must be `$PSCompletions`.
- It cannot be solved, either you don't use `PSCompletions` module, or you give the variable you define a different name.
- Simple processing of ToolTip information for `PowerShell` commands, optimized display.
- When the menu is displayed, filtering by input characters no longer changes the width of the menu.
- Fix a bug where you could set an existing command as an alias.
- Optimize logical operations, remove some unnecessary operations.

## 4.2.6 (2024/8/10)

- Fix a bug where the list of completions list was empty.
- If using `Windows PowerShell` and using a command-line theme (such as oh-my-posh), it may cause the current line and nearby text and icons to be distorted when the completion menu is displayed above the current line.
  - Solution:
    1. Disable the command-line theme.
    2. Try to make the completion menu display below the current line. (Only if the current line is above the middle of the window.)
    3. Do not use `Windows PowerShell`, use [`PowerShell`](https://github.com/PowerShell/PowerShell).
       - `Windows PowerShell` is really bad, there are always many small issues.

## 4.2.5 (2024/8/10)

- If prefix match (`menu_is_prefix_match`) is enabled in the completion menu, only the value of completion is extracted when there's a common prefix.
- Optimize the logic of completion update.

## 4.2.4 (2024/8/10)

- Fix an issue where `Windows PowerShell` module loading failed because a code file used LF line breaks.
  - For code files , replace LF line breaks to CRLF line breaks and replace UTF-8 to UTF-8-BOM encoding.
- Fix an issue where initialization imports were missing in non-Windows environments.
- Change the source file directory structure.

## 4.2.3 (2024/8/9)

- Fix an issue where the `menu_show_tip` configuration for specific completions was invalid.
- Fix an issue where the menu was rendered incorrectly when filtering completions.

## 4.2.2 (2024/8/9)

- No longer checks for updates immediately after using `psc update *` update completion.

## 4.2.1 (2024/8/9)

- Fix a small issue when migrating to the new version.

## 4.2.0 (2024/8/9)

- Add three `menu` configurations:

  1. `menu_trigger_key`: Default value is `Tab`, which is used to set the trigger key of the completion menu.
     - Setting: `psc menu config menu_trigger_key <key>`
  2. `menu_enhance`: Default value is `1`, which is used to enable or disable the enhanced completion menu feature.
     - Disable it: `psc menu config menu_enhance 0`
     - When enabled, `PSCompletions` will intercept all completions and uses the completion menu provided by `PSCompletions` to render completions.
     - For example, commands such as `Get-*`, `Set-*` in `PowerShell` will use the completion menu provided by `PSCompletions` to render the completion.
     - Note: This setting only takes effect if `menu_enable` is also enabled.
     - [About menu enhance](../README.md#about-menu-enhance)
  3. `menu_show_tip_when_enhance`: Default value is `1`, which is used to control whether to show command tips for completions that are not added through `psc add`.
     - Disable it: `psc menu config menu_show_tip_when_enhance 0`
     - Use together with `menu_enhance`.

- Fix an issue where multi-byte characters(such as Chinese characters) could cause partial rendering errors in the menu.

  - This is useful with `menu_enhance`.
  - For example, when using the `cd` command, even if the path completion contains Chinese or other multi-byte characters, the menu will render correctly.

- Completion tips now support automatic line wrapping based on available width.

  - For a better experience, the default value of the `menu_tip_follow_cursor` config has been changed from `0` to `1`.

- Refactored code by reorganizing the source file directory structure and extracting common code.
- Use multi-threading to optimize performance and remove some redundant code.
- Fixed some other issues.
- Cleaned up the code.

## 4.1.0 (2024/8/7)

- Now `Windows PowerShell` can use the completion menu provided by `PSCompletions`.
  - But, due to rendering problems, the border style of the completion menu cannot be customized.
- Fix some other issues.
- Change the directory structure of the source code file.
- Clean up the code.

## 4.0.9 (2024/7/20)

- Add two commands: add/remove all completions.
  - `psc add *`
  - `psc rm *`
- Optimize the logic processing of `common_options`.
- Fix the problem of module update.
- Change the directory structure of the source code file.
- Clean up the code.

## 4.0.7 (2024/7/6)

- Replace `ForEach-Object` with `foreach`.
  - `ForEach-Object` has unexpected results in some special cases.
- Clean up some code

## 4.0.6 (2024/5/20)

- A default configuration color was mistakenly written, fix it.

## 4.0.5 (2024/5/20)

- Fix some issues about the special configurations of completion.
- Fix an issue where configuration changes did not take immediate effect due to caching.
- Add the `completion` subcommand to the `reset` command to reset (remove) the special configuration of completion.
- Fix some other issues.

## 4.0.4 (2024/5/20)

- Fix a bug where the completion tip area, filter area and status area flashes when scrolling the completion list.
- Fix some other minor issues.

## 4.0.3 (2024/5/18)

- Fix a bug where the completion tip was displayed incorrectly because the terminal output encoding was modified.
  - You must import the `PSCompletions` module first, and then modify the terminal output encoding. Otherwise, it will still display incorrectly.
- Change the default value of `menu_tip_cover_buffer` from `0` to `1`.
  - This configuration means that the completion tip will cover the buffer content by default, which is mainly when the completion tip is displayed above, it will cover all the buffer content above, which will make the background look cleaner.
  - Of course, the buffer content covered by the completion tip will be restored when the completion menu exits.
  - You can disable it by running `psc menu config menu_tip_cover_buffer 0`.
- Fix some other minor issues.

## 4.0.2 (2024/5/15)

- A test environment configuration was not deleted, fix it.

## 4.0.1 (2024/5/15)

- A default configuration color was mistakenly written, fix it.

## 4.0.0 (2024/5/15)

- If you are using the `PSCompletions` module with **administrator permission**, you should remove the `PSCompletions` module and install the latest version with **user permission**.

  - Full module installation command: `Install-Module PSCompletions -Scope CurrentUser`

- This version completely rewrites the module, and solves many inappropriate places, so it's completely incompatible with the old version configuration and completion.
  1.  Performance optimization:
      - Improve module loading speed.
      - Improve completion response speed.
  2.  Completion menu:
      - Completely rewrite the completion menu, which greatly improves the stability of the menu rendering, and solves many rendering bugs from the root.
      - The completion menu now has many configuration items, you can trigger completion by running `psc menu`, then learn about them by completion tip.
      - For example: `menu_show_tip`, which can control whether the completion tip is displayed.
        - If you are familiar with the command, it's recommended to disable the completion tip.
        - This configuration can also be set separately for each completion, refer to `psc completion` for command.
  3.  Completion alias:
      - Now completion alias supports multiple, you can add as many as you like. Theoretically, you can add an infinite number of aliases.
      - For example, you can add `.\scoop.ps1` as an alias, which can be useful in some cases.
  4.  Decoupling of completion file and module.
      - Add/update/translate completions now doesn't involve module core code. (Except if hooks are needed.)
      - Use json schema to control the type of json file, which makes it easier for contributors to create PR for the completion repository.
      - For example, if you think the description of a command is not good, you can modify its json file and create a PR.
  5.  Language:
      - Now the module supports any language, and the module determines the language based on the language configuration and each completion's config.json file.
      - It means that more languages can be supported in the future by simply writing the corresponding json file.
  6.  Other:
      - Added some key mappings, which allows you to select completion items in the completion menu using various key combinations. You can choose one that suits you.
        |Select previous item|Select next item|
        |:-:|:-:|
        |`Up`|`Down`|
        |`Left`|`Right`|
        |`Shift + Tab`|`Tab`|
        |`Shift + Space`|`Space`|
        |`Ctrl + u`|`Ctrl + d`|
        |`Ctrl + p`|`Ctrl + n`|
      - The symbol is now placed behind the completion item, and the symbol is no longer displayed in the completion tip.
      - ...
