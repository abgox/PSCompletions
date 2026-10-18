<h1 align="center">✨<a href="https://pscompletions.abgox.com">PSCompletions(psc)</a>✨</h1>

<p align="center">
    <span>English</span> |
    <a href="README.zh-CN.md">简体中文</a> |
    <a href="https://www.powershellgallery.com/packages/PSCompletions">PowerShell Gallery</a> |
    <a href="https://github.com/abgox/PSCompletions">GitHub</a> |
    <a href="https://atomgit.com/abgox/PSCompletions">AtomGit</a> |
    <a href="https://gitee.com/abgox/PSCompletions">Gitee</a>
</p>

<p align="center">
    <a href="https://github.com/abgox/PSCompletions/blob/main/LICENSE">
        <img src="https://img.shields.io/github/license/abgox/PSCompletions" alt="license" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/v/PSCompletions?label=version" alt="module version" />
    </a>
    <a href="../index/completions.md">
        <img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fabgox%2FPSCompletions%2Frefs%2Fheads%2Findex%2Fcompletions.json&query=%24.count&label=completions" alt="completions" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/dt/PSCompletions" alt="PowerShell Gallery" />
    </a>
    <a href="https://github.com/abgox/PSCompletions">
        <img src="https://img.shields.io/github/created-at/abgox/PSCompletions" alt="created" />
    </a>
</p>

## Introduction

Powerful Shell Completions for [PowerShell and other shells](https://pscompletions.abgox.com/docs/shells), powered by Rust and Lua.

- [One engine, many shells.](https://pscompletions.abgox.com/docs/shells)
- [Built-in completion library.](../index/completions.md)
- [More powerful completion menu.](https://pscompletions.abgox.com/docs/completion-menu)
- [Multilingual support: en-US, zh-CN, etc.](https://pscompletions.abgox.com/docs/language)
- [Dynamic sorting of completion items based on command history.](https://pscompletions.abgox.com/docs/sort-completion-items)

## Demo

![demo](https://pscompletions.abgox.com/demo.gif)

## How to use

1. Install it.
   - [Install-Module](https://learn.microsoft.com/powershell/module/powershellget/install-module)

     ```powershell
     Install-Module PSCompletions
     ```

   - [Install-PSResource](https://learn.microsoft.com/powershell/module/microsoft.powershell.psresourceget/install-psresource)

     ```powershell
     Install-PSResource PSCompletions
     ```

   - [Scoop](https://scoop.sh)
     - Use [main](https://github.com/ScoopInstaller/Main) bucket

       ```shell
       scoop install pscompletions
       ```

     - Use [abyss](https://abyss.abgox.com) bucket

       ```shell
       scoop install abyss/abgox.PSCompletions
       ```

   - Linux / macOS, without PowerShell — run the [install script](install.sh):

     ```sh
     curl -fsSL https://raw.githubusercontent.com/abgox/PSCompletions/main/install.sh | sh
     ```

2. Load it.
   - PowerShell — [import the module directly](https://pscompletions.abgox.com/docs/direct-import-module):

     ```powershell
     Import-Module PSCompletions
     ```

   - bash / zsh / fish — run the [install script](install.sh), and it prints the content to add to your shell's rc file.

3. Use it.
   - [Built-in completion library](../index/completions.md): add a completion with `psc add git`.
   - [Native completion](https://pscompletions.abgox.com/docs/native-completion): each shell has its own mechanism — PowerShell argument completers, bash/zsh/fish native completion, …

## What's new

See the [changelog](./module/CHANGELOG.md) for details.

## Contribution

See the [contribution guide](./.github/contributing.md) for details.

## Support

If you like this project, feel free to give it a Star ⭐️ or [Donate 💰](https://me.abgox.com/donate).

## Acknowledgements

- [PSReadLine](https://github.com/PowerShell/PSReadLine) — PowerShell's editing and completion foundation.
- [fzf](https://github.com/junegunn/fzf)/[PSFzf](https://github.com/kelleyma49/PSFzf) — UI inspiration for the [completion menu](https://pscompletions.abgox.com/docs/completion-menu).

## License

[MIT](./LICENSE) © [abgox](https://me.abgox.com)
