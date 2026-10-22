<h1 align="center"><a href="https://pscompletions.abgox.com">PSCompletions</a></h1>

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

Powerful Shell Completions for PowerShell and other shells, powered by Rust and Lua.

- [One engine, many shells.](https://pscompletions.abgox.com/docs/shells)
- [Built-in completion library.](../index/completions.md)
- [More powerful completion menu.](https://pscompletions.abgox.com/docs/completion-menu)
- [Multilingual support: en-US, zh-CN, etc.](https://pscompletions.abgox.com/docs/language)
- [Dynamic sorting of completion items based on command history.](https://pscompletions.abgox.com/docs/sort-completion-items)

## Demo

![demo](https://pscompletions.abgox.com/demo.gif)

## How to get

1. Install it.
   - PowerShell - install the module.

     ```powershell
     Install-Module PSCompletions # Install-PSResource PSCompletions
     ```

   - bash / zsh / fish - run the [install script](install.sh).

     ```shell
     curl -fsSL https://raw.githubusercontent.com/abgox/PSCompletions/main/install.sh | sh
     ```

   - [Scoop](https://scoop.sh)

     ```shell
     scoop install pscompletions # scoop install abyss/abgox.PSCompletions
     ```

2. Load it.
   - PowerShell - [import the module directly](https://pscompletions.abgox.com/docs/direct-import-module).

     ```powershell
     Import-Module PSCompletions
     ```

   - bash / zsh / fish - the [install script](install.sh) will tell you how to load it.

3. Use it.

   ```shell
   psc
   ```

   ```shell
   psc add git
   ```

## What's new

See the [changelog](./module/CHANGELOG.md) for details.

## Contribution

See the [contribution guide](./.github/contributing.md) for details.

## Support

<!-- One line per sponsor, newest last: `- [Name](https://…) — what they do.` -->

If you like this project, Star ⭐️ is always welcome, and so is [sponsorship](https://pscompletions.abgox.com/docs/sponsors).

## Acknowledgements

- [PSReadLine](https://github.com/PowerShell/PSReadLine) - PowerShell's editing and completion foundation.
- [fzf](https://github.com/junegunn/fzf)/[PSFzf](https://github.com/kelleyma49/PSFzf) - UI inspiration for the [completion menu](https://pscompletions.abgox.com/docs/completion-menu).

## License

[MIT](./LICENSE) © [abgox](https://me.abgox.com)
