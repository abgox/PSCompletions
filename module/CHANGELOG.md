<p align="center">
    <a href="./CHANGELOG-CN.md">简体中文</a>|
    <a href="./CHANGELOG.md">English</a>
</p>

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
