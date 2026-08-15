<h1 align="center">✨<a href="https://pscompletions.abgox.com">PSCompletions(psc)</a>✨</h1>

<p align="center">
    <a href="README.zh-CN.md">简体中文</a> |
    <a href="https://www.powershellgallery.com/packages/PSCompletions">Powershell Gallery</a> |
    <a href="https://github.com/abgox/PSCompletions">GitHub</a> |
    <a href="https://gitee.com/abgox/PSCompletions">Gitee</a> |
    <a href="https://gitcode.com/abgox/PSCompletions">GitCode</a>
</p>

<p align="center">
    <a href="https://github.com/abgox/PSCompletions/blob/main/LICENSE">
        <img src="https://img.shields.io/github/license/abgox/PSCompletions" alt="license" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/v/PSCompletions?label=version" alt="module version" />
    </a>
    <a href="./completions.md">
        <img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fabgox%2FPSCompletions%2Frefs%2Fheads%2Fmain%2Fcompletions.json&query=%24.count&label=completions" alt="completions" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/dt/PSCompletions" alt="PowerShell Gallery" />
    </a>
    <a href="https://github.com/abgox/PSCompletions">
        <img src="https://img.shields.io/github/created-at/abgox/PSCompletions" alt="created" />
    </a>
</p>

## Introduce

A completion manager for a better and simpler tab-completion experience in [PowerShell](https://microsoft.com/powershell), built with [Rust and Lua](https://pscompletions.abgox.com/docs/how-it-works).

- [Built-in completion library.](./completions.md)
- [Powerful module completion menu.](https://pscompletions.abgox.com/docs/module-completion-menu)
- [Support multiple languages: en-US, zh-CN, etc.](https://pscompletions.abgox.com/docs/language)
- [Sort completion items dynamically based on command history.](https://pscompletions.abgox.com/docs/sort-completion-items)

## Demo

![demo](https://pscompletions.abgox.com/demo.gif)

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

   - [Scoop](https://scoop.sh)
     - Add the [abyss](https://abyss.abgox.com) bucket via [GitHub](https://github.com/abgox/abyss) or [Gitee](https://gitee.com/abgox/abyss).
     - Install it.

       ```shell
       scoop install abyss/abgox.PSCompletions
       ```

2. [Import the module.](https://pscompletions.abgox.com/docs/direct-import-module)

   ```powershell
   Import-Module PSCompletions
   ```

## How to use

- [Built-in completion library](./completions.md): add a completion with `psc add git`.
- [Native completion integration](https://pscompletions.abgox.com/docs/native-completion): use PowerShell's native completions.
  - If a command has an official completion, a similar command may be run:

    ```powershell
    xxx completion powershell | Out-String | Invoke-Expression
    ```

  - Register completions with the PowerShell argument completer:

    ```powershell
    Register-ArgumentCompleter -Native -CommandName <Name> -ScriptBlock { ... }
    ```

  - Use other completion libraries, e.g. [Carapace](https://pscompletions.abgox.com/docs/tools/carapace)

## What's new

See the [changelog](./module/CHANGELOG.md) for details.

## Contribution

See the [contribution guide](./.github/contributing.md) for details.

## Support

If you like this project, feel free to give it a Star ⭐️ or [Donate 💰](https://me.abgox.com/donate).

## Acknowledgements

- **Used**: [PSReadLine](https://github.com/PowerShell/PSReadLine) — A built-in PowerShell module that enhances the command-line completion experience.
- **Inspired by**: [The module completion menu](https://pscompletions.abgox.com/docs/module-completion-menu) is inspired by:
  - [fzf](https://github.com/junegunn/fzf): A general-purpose command-line fuzzy finder.
  - [PSFzf](https://github.com/kelleyma49/PSFzf): Fuzzy-finder integration for PowerShell.
  - [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion): GUI-style tab-completion menu for PowerShell (an early V6 inspiration).

## License

[MIT](./LICENSE) © [abgox](https://me.abgox.com)
