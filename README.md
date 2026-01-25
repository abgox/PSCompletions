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
> - [PowerShell(pwsh)](https://microsoft.com/powershell): A cross-platform PowerShell (Core). Start it by running `pwsh`/`pwsh.exe`.
> - [Windows PowerShell](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell): A PowerShell (Desktop) which is built-in on Windows system. Start it by running `powershell`/`powershell.exe`.
> - They can both use `PSCompletions`, but [PowerShell(pwsh)](https://microsoft.com/powershell) is more recommended.

A completion manager for a better and simpler tab-completion experience in `PowerShell`.

- [Built-in completion library.](./completions.md)
- [More powerful module completion menu.](https://pscompletions.abgox.com/faq/module-completion-menu)
- [Support multiple languages: en-US, zh-CN, etc.](https://pscompletions.abgox.com/faq/language)
- [Sort completion items dynamically based on command history.](https://pscompletions.abgox.com/faq/sort-completion-items)
- Work with other tools.
  - [argc-completions](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions)
  - [Carapace](https://pscompletions.abgox.com/faq/pscompletions-and-carapace)
  - [PSFzf](https://pscompletions.abgox.com/faq/pscompletions-and-psfzf)

## Demo

> [!Tip]
>
> - If it cannot be displayed here, [you can check it on the official website](https://pscompletions.abgox.com).
> - [Click to view the videos on Bilibili.](https://www.bilibili.com/video/BV15Gp7zmE2e)

![demo](https://pscompletions.abgox.com/demo.gif)

## What's new

See the [Changelog](./module/CHANGELOG.md) for details.

## FAQ

See the [FAQ](https://pscompletions.abgox.com/faq).

## Contribution

See the [Contribution Guide](./.github/contributing.md) for details.

## How to install

1. Install the module.
   - [Install-Module](https://learn.microsoft.com/powershell/module/powershellget/install-module)

     ```powershell
     Install-Module PSCompletions
     ```

   - [Install-PSResource](https://learn.microsoft.com/powershell/module/microsoft.powershell.psresourceget/install-psresource)

     ```powershell
     Install-PSResource PSCompletions
     ```

   - [Scoop](https://scoop.sh/)
     - Add the [abyss](https://abyss.abgox.com) bucket via [Github](https://github.com/abgox/abyss) or [Gitee](https://gitee.com/abgox/abyss).

     - Install it.

       ```shell
       scoop install abyss/abgox.PSCompletions
       ```

2. Import the module.

   ```powershell
   Import-Module PSCompletions
   ```

> [!Tip]
>
> - If you use `. $Profile`, please run `psc` to reload the module's key bindings and data.
> - Refer to: https://pscompletions.abgox.com/faq/source-profile

## How to use

- Use the [built-in completion library](./completions.md), like `git`.
  1. Add completion: `psc add git`
  2. Then you can enter `git`, press `Space` and `Tab` key to get command completion.

- Use official completion or other completion libraries.
  - If there is an official completion for `xxx`, a similar command may be run:

    ```powershell
    xxx completion powershell | Out-String | Invoke-Expression
    ```

  - Work with other completion libraries: [argc-completions](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions), [Carapace](https://pscompletions.abgox.com/faq/pscompletions-and-carapace)

  - For more details, please refer to: https://pscompletions.abgox.com/faq/menu-enhance

- Use [PSFzf](https://github.com/kelleyma49/PSFzf) as the completion menu, refer to [Work with PSFzf](https://pscompletions.abgox.com/faq/pscompletions-and-psfzf).

## Acknowledgements

- [PSReadLine](https://github.com/PowerShell/PSReadLine): A built-in module in PowerShell, which is used to enhance command line editing experience.
  - PSCompletions uses `Set-PSReadLineKeyHandler` and `Get-PSReadLineOption`.
- [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion): GUI-style tab-completion menu for PowerShell.
  - [The module completion menu](https://pscompletions.abgox.com/faq/module-completion-menu) of PSCompletions is inspired by it.

## Available Completions

- [English](./completions.md)
- [简体中文](./completions.zh-CN.md)
