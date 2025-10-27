<h1 align="center">✨<a href="https://pscompletions.abgox.com">PSCompletions(psc)</a>✨</h1>

<p align="center">
    <a href="README.zh-CN.md">简体中文</a> |
    <a href="README.md">English</a> |
    <a href="https://www.powershellgallery.com/packages/PSCompletions">Powershell Gallery</a> |
    <a href="https://github.com/abgox/PSCompletions">Github</a> |
    <a href="https://gitee.com/abgox/PSCompletions">Gitee</a>
</p>

<p align="center">
    <a href="https://github.com/abgox/PSCompletions/blob/main/LICENSE">
        <img src="https://img.shields.io/github/license/abgox/PSCompletions" alt="license" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/v/PSCompletions?label=version" alt="module version" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/dt/PSCompletions" alt="PowerShell Gallery" />
    </a>
    <a href="https://github.com/abgox/PSCompletions">
        <img src="https://img.shields.io/github/languages/code-size/abgox/PSCompletions" alt="code size" />
    </a>
    <a href="https://github.com/abgox/PSCompletions">
        <img src="https://img.shields.io/github/repo-size/abgox/PSCompletions" alt="repo size" />
    </a>
    <a href="https://github.com/abgox/PSCompletions">
        <img src="https://img.shields.io/github/created-at/abgox/PSCompletions" alt="created" />
    </a>
</p>

---

![socialify](https://abgox.com/github-socialify-PSCompletions.svg)

<p align="center">
  <strong>Star ⭐️ or <a href="https://abgox.com/donate">Donate 💰</a> if you like it!</strong>
</p>

## Introduce

> [!Tip]
>
> - [PowerShell(pwsh)](https://learn.microsoft.com/powershell/scripting/overview): A cross-platform PowerShell (Core). Start it by running `pwsh`/`pwsh.exe`.
> - [Windows PowerShell](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell): A PowerShell (Desktop) which is built-in on Windows system. Start it by running `powershell`/`powershell.exe`.
> - They can both use `PSCompletions`, but [PowerShell(pwsh)](https://learn.microsoft.com/powershell/scripting/overview) is more recommended.

A completion manager for better and simpler use completions in `PowerShell`.

- [More powerful completion menu.](#about-completion-menu "Click it to learn more about it.")
- [Manage completions together.](./completions.md "Click it to view the completion list that can be added.")
- Sort completion items dynamically by frequency of use.
- Switch between languages(`en-US`,`zh-CN`,...) freely.
- [Combined with argc-completions.](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions "Click to see what you need to do.")

## Demo

> [!Tip]
>
> - If it cannot be displayed here, [you can check it on the official website.](https://pscompletions.abgox.com).
> - [Click to view the videos on Bilibili.](https://www.bilibili.com/video/BV15Gp7zmE2e)

![demo](https://pscompletions.abgox.com/demo.gif)

## What's new

- See the [Changelog](./module/CHANGELOG.md) for details.

## FAQ

- See the [FAQ](https://pscompletions.abgox.com/faq).

## Contribution

- See the [Contribution Guide](./.github/contributing.md) for details.

## How to install

1. Install module:

   - Normal:

     ```powershell
     Install-Module PSCompletions -Scope CurrentUser
     ```

   - Install silently:

     ```powershell
     Install-Module PSCompletions -Scope CurrentUser -Repository PSGallery -Force
     ```

   - Use [Scoop](https://scoop.sh/):

     - Add the [abyss](https://abyss.abgox.com) bucket via [Github](https://github.com/abgox/abyss) or [Gitee](https://gitee.com/abgox/abyss).

     - Install it.

       ```shell
       scoop install abyss/abgox.PSCompletions
       ```

2. Import module:
   ```powershell
   Import-Module PSCompletions
   ```
   - Add it to your `$Profile` to make it permanent by running the following command.
     ```powershell
     "Import-Module PSCompletions" >> $Profile
     ```
   - Note: Recommend add `Import-Module PSCompletions` early in `$Profile` to avoid [the encoding issue](https://pscompletions.abgox.com/faq/output-encoding).

## How to uninstall

```powershell
Uninstall-Module PSCompletions
```

## How to use

> [!Tip]
>
> - [Available Completions.](./completions.md "All completions that can be added at present. More completions are adding!")
> - If it doesn't include the completion you want, you can [submit an issue](https://github.com/abgox/PSCompletions/issues "Click to submit an issue.").
> - You can also [combined with argc-completions.](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions "Click to see what you need to do.")

Take `git` as an example.

1. Add completion: `psc add git`
2. Then you can enter `git`, press `Space` and `Tab` key to get command completion.
3. For more usages on `psc`, you just need to enter `psc`, press `Space` and `Tab` key, and you will get all usages of `psc` by reading [the completion tip](#about-completion-tip).

## Tips

### About the completion trigger key

- `PSCompletions` uses the `Tab` key by default.
- You can set it by running `psc menu config trigger_key <key>`.

> [!Warning]
>
> - If you need `Set-PSReadLineKeyHandler -Key <key> -Function <MenuComplete|Complete>`
> - Please add it before `Import-Module PSCompletions`

### About completion menu

- In addition to the built-in completion menu of `PowerShell`, `PSCompletions` module also provides a more powerful completion menu.

  - Setting: `psc menu config enable_menu 1` (Default: `1`)
  - Its related behaviors can be controlled via other configuration items in `psc menu config`.

- It is only available in Windows, because [PowerShell in Linux/MacOS does not implement the relevant methods](https://github.com/cspotcode/PS-GuiCompletion/issues/13#issuecomment-620084134).

- Some key bindings in the module's completion menu.

  1. Apply the selected completion item: `Enter` / `Space`
     - You can also use `Tab` when there's only one completion.
  2. Delete filter characters: `Backspace`
  3. Exit the completion menu: `Esc` / `Ctrl + c`
     - You can also use `Backspace` when there're no characters in the filter area.
  4. Select completion item:

     | Select previous item | Select next item |
     | :------------------: | :--------------: |
     |         `Up`         |      `Down`      |
     |        `Left`        |     `Right`      |
     |    `Shift + Tab`     |      `Tab`       |
     |      `Ctrl + u`      |    `Ctrl + d`    |
     |      `Ctrl + p`      |    `Ctrl + n`    |

- All configurations of it, you can trigger completion by running `psc menu`, then learn about them by [the completion tip](#about-completion-tip).
  - For configured values, `1` means `true` and `0` means `false`. (It applies to all configurations of `PSCompletions`)
  - Some common menu behaviors:
    - Auto-apply when there's only one completion item: `psc menu config enable_enter_when_single 1`
    - Use prefix matching for filtering: `psc menu config enable_prefix_match_in_filter 1`
      - If it is `0`, fuzzy matching is used, and the `*` and `?` wildcards are supported.
    - ...

#### About menu enhance

- Setting: `psc menu config enable_menu_enhance 1` (Default: `1`)
- Now, `PSCompletions` has two completion implementations.

  - [Set-PSReadLineKeyHandler](https://learn.microsoft.com/powershell/module/psreadline/set-psreadlinekeyhandler)
    - It's used by default.
      - Requires: `enable_menu` and `enable_menu_enhance` both set to `1`.
    - It no longer needs to loop through registering [Register-ArgumentCompleter](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter) for all completions, which theoretically makes loading faster.
    - It use [TabExpansion2](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/tabexpansion2) to manage completions globally, not limited to those added by `psc add`.
      - Path completion such as `cd`/`.\`/`..\`/`~\`/...
      - Build-in commands such as `Get-*`/`Set-*`/`New-*`/...
      - Completion registered by [Register-ArgumentCompleter](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter)
      - [Combined with argc-completions.](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions)
      - Completion registered by cli or module.
      - ...
  - [Register-ArgumentCompleter](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter)
    - You can use it by running `psc menu config enable_menu_enhance 0`.
    - It only works for completions added by `psc add`.

### About option completion

- `Optional Completions`: some command completions that like `-*`, such as `--global` in `git config --global`.
- You should use option completion first.
- Taking `git` as an example, if you want to enter `git config user.name --global xxx`, you should use `--global` completion first, and then use `user.name`, and then enter the name `xxx`.
- For options ending with `=`, if there's completion definition, you can directly press the `Tab` key to get the completions.

### About special symbols

> [!Tip]
>
> - Due to changes in Windows Terminal, 😄🤔😎 cannot be displayed properly in the completion menu, so they will be replaced.
> - Related issue: https://github.com/microsoft/terminal/issues/18242
> - The changes are as follows:
>   - `😄` => `~`
>   - `🤔` => `?`
>   - `😎` => `!`

- Special symbols after the completion item are used to let you know in advance if completions are available before you press the `Tab` key.

  - They only exist in completions added by `psc add`.
  - They can be customized by running `psc menu symbol <type> <symbol>`
  - For example, you can replace them with empty strings to hide them.
    - `psc menu symbol SpaceTab ""`
    - `psc menu symbol OptionTab ""`
    - `psc menu symbol WriteSpaceTab ""`

- `~`,`?`,`!` : If there are multiple, you can choose the effect of one of them.
  - `~` : It means that after you apply it, you can press `Tab` key to continue to get completions.
  - `?` : It means that after you apply the [(General) option completion](#about-option-completion), you can press `Tab` key to continue to get current completion items in completion menu.
  - `!` : It means that after you apply the [(General) option completion](#about-option-completion), you can press enter a string, then press `Tab` key to continue to get current completion items in completion menu.
    - If the string has spaces, please use `"` or `'` to wrap it. e.g. `"test content"`
    - If there's also `~`, it means that there's some preset completions, you can press `Tab` key to continue to get them without entering a string.

### About completion tip

- The completion tip is only a helper, you can also disable the tip by running `psc menu config enable_tip 0`

  - It's enabled by default: `psc menu config enable_tip 1`
  - You can also disable the tip for a specific completion, such as `git`.
    - `psc completion git enable_tip 0`

- General structure of the completion tip: `Usage` + `Description` + `Example`

  ```txt
  U: install|add [-g|-u] [options] <app>
  This is a description of the command.
  E: install xxx
     add -g xxx
  ```

- Example Analysis:
  1. Usage: Begin with `U:`
     - command name: `install`
     - command alias: `add`
     - required parameters: `<app>`
       - `app` is a simple summary of the parameters.
     - optional parameters: `-g` `-u`
       - `[options]`: Some options.
  2. Description: The description of the command.
  3. Example: Begin with `E:`

### About language

- `Global language`: Default to the language of current system.
  - You can show it by running `psc config language`.
  - You can change it by running `psc config language zh-CN`.
- `Completion language`: The language set for the specified completion.
  - e.g. `psc completion git language en-US`.
- `Available language`: In the completion `config.json` file, there is a `language` attribute whose value is a list of available languages.

#### Determine language

1. If there is `Completion language`,use it. If not, use `Global language`.
2. Determine the final language:
   - Determine whether the value of the first step exists in `Available language`.
   - If it exists, use it.
   - If not, use the first of the `Available language`. (It's usually `en-US`)

### About path completion

- Take `git` for example, when entering `git add`, pressing the `Space` and `Tab` keys, path completion will not be triggered, only completion provided by the module will be triggered.
- If you want to trigger path completion, you need to enter a content which matches `^(?:\.\.?|~)?(?:[/\\]).*`.
- e.g.
  - Please enter `./` or `.\` and press `Tab` key to get path completion for the **subdirectory** or **file**.
  - Please enter `../` or `..\` and press `Tab` key to get path completion for the **parent directory** or **file**.
  - Please enter `/` or `\` and press `Tab` key to get path completion for the **sibling directory**.
  - More examples: `~/` / `../../` ...
- So you can enter `git add ./` and then press `Tab` key to get the path completion.

## Acknowledgements

- [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion): The completion menu provided by the module is inspired by it.

## Available Completions

- [English](./completions.md)
- [简体中文](./completions.zh-CN.md)
