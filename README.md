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

A completion manager for a better and simpler tab-completion experience in `PowerShell`.

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

See the [Changelog](./module/CHANGELOG.md) for details.

## FAQ

See the [FAQ](https://pscompletions.abgox.com/faq).

## Contribution

See the [Contribution Guide](./.github/contributing.md) for details.

## How to install

1. Install module:

   - Use [Install-Module](https://learn.microsoft.com/powershell/module/powershellget/install-module):

     ```powershell
     Install-Module PSCompletions -Scope CurrentUser
     ```

   - Use [Install-PSResource](https://learn.microsoft.com/powershell/module/microsoft.powershell.psresourceget/install-psresource):

     ```powershell
     Install-PSResource PSCompletions -Scope CurrentUser
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

## How to use

- Take `git` as an example.

  1. Add completion: `psc add git`
  2. Then you can enter `git`, press `Space` and `Tab` key to get command completion.

- Only use `PSCompletions` as a better completion menu without `psc add`.

  - If there is an official completion for `xxx`, a similar command can be run:

    ```powershell
    xxx completion powershell | Out-String | Invoke-Expression
    ```

  - [Combined with argc-completions.](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions "Click to see what you need to do.")

  - For more details, please refer to [About menu enhance](#about-menu-enhance).

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
  - You can run `psc` to view the related key bindings.

- It is only available in Windows, because [PowerShell in Linux/MacOS does not implement the relevant methods](https://github.com/cspotcode/PS-GuiCompletion/issues/13#issuecomment-620084134).

- All configurations of it, you can trigger completion by running `psc menu`, then learn about them by [the completion tip](#about-completion-tip).
  - For configured values, `1` means `true` and `0` means `false`. (It applies to all configurations of `PSCompletions`)
  - Some common menu behaviors:
    - Auto-apply when there's only one completion item: `psc menu config enable_enter_when_single 1`
    - ...

#### About menu enhance

- Setting: `psc menu config enable_menu_enhance 1` (Default: `1`)
- Now, `PSCompletions` has two completion implementations.

  - [Set-PSReadLineKeyHandler](https://learn.microsoft.com/powershell/module/psreadline/set-psreadlinekeyhandler)
    - It's used by default.
      - Requires: `enable_menu` and `enable_menu_enhance` both set to `1`.
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

### About path completion

- Take `git` for example, when entering `git add`, pressing the `Space` and `Tab` keys, path completion will not be triggered, only completion provided by the module will be triggered.
- If you want to trigger path completion, you need to enter a content which matches `^(?:\.\.?|~)?(?:[/\\]).*`.
- e.g.
  - Enter `./` or `.\` and press `Tab` key to get path completion for the **subdirectory** or **file**.
  - Enter `../` or `..\` and press `Tab` key to get path completion for the **parent directory** or **file**.
  - Enter `/` or `\` and press `Tab` key to get path completion for the **sibling directory**.
  - More examples: `~/` / `../../` ...
- So you can enter `git add ./` and then press `Tab` key to get the path completion.

### About special symbols

> [!Tip]
>
> - Due to changes in Windows Terminal, 😄🤔😎 cannot be displayed properly in the completion menu, so they will be replaced.
> - Related issue: https://github.com/microsoft/terminal/issues/18242
> - New symbols: `~`,`?`,`!`

- Special symbols after the completion item are used to let you know in advance if completions are available before you press the `Tab` key.

  - They only exist in completions added by `psc add`.
  - They can be customized by running `psc menu symbol <type> <symbol>`
  - For example, you can replace them with empty strings to hide them.
    - `psc menu symbol SpaceTab ""`
    - `psc menu symbol OptionTab ""`
    - `psc menu symbol WriteSpaceTab ""`

- `~`,`?`,`!` : If there are multiple, you can choose the effect of one of them.
  - `~` : It means that after you apply it, you can press `Tab` key to continue to get completions.
  - `?` : It means that after you apply the [option completion](#about-option-completion), you can press `Tab` key to continue to get current list of completion items.
  - `!` : It means that after you apply the [option completion](#about-option-completion), you should enter a string, then press `Tab` key to continue to get current list of completion items.
    - If the string has spaces, please use `"` or `'` to wrap it. e.g. `"test content"`
    - If there's also `~`, it means that there's some preset completions, you can press `Tab` key to continue to get them without entering a string.

### About completion tip

- The completion tip is only a helper and can be used as needed.

  - Disable it for all completions: `psc menu config enable_tip 0`
  - Disable it for a specific completion: `psc completion git enable_tip 0`

- General structure of the completion tip: `Usage` + `Description` + `Example`

  ```txt
  U: install, add [-g, -u] [options] <app>
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

## Acknowledgements

- [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion): The completion menu provided by the module is inspired by it.

## Available Completions

- [English](./completions.md)
- [简体中文](./completions.zh-CN.md)
