<h1 align="center"><a href="https://pscompletions.abgox.com">PSCompletions</a></h1>

<p align="center">
    <a href="README.md">English</a> |
    <span>简体中文</span> |
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
    <a href="../index/completions.zh-CN.md">
        <img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fabgox%2FPSCompletions%2Frefs%2Fheads%2Findex%2Fcompletions.json&query=%24.count&label=completions" alt="completions" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/dt/PSCompletions" alt="PowerShell Gallery" />
    </a>
    <a href="https://github.com/abgox/PSCompletions">
        <img src="https://img.shields.io/github/created-at/abgox/PSCompletions" alt="created" />
    </a>
</p>

<p align="center">
    <a href="https://pscompletions.abgox.com">
        <img src="https://pscompletions.abgox.com/og-image.svg" alt="PSCompletions — Powerful Shell Completions"/>
    </a>
</p>

## 介绍

**Powerful Shell Completions** - 适用于 PowerShell 和其他 Shell 的强大的命令补全器，由 Rust 与 Lua 驱动。

- [一个引擎，多个 Shell](https://pscompletions.abgox.com/docs/shells)
- [内置的补全库](../index/completions.zh-CN.md)
- [更强大的补全菜单](https://pscompletions.abgox.com/docs/completion-menu)
- [多语言支持: en-US、zh-CN 等](https://pscompletions.abgox.com/docs/language)
- [基于命令历史的补全项动态排序](https://pscompletions.abgox.com/docs/sort-completion-items)

## 演示

![demo](https://pscompletions.abgox.com/demo.zh-CN.gif)

## 获取

1. 安装它
   - PowerShell - 安装模块

     ```powershell
     Install-Module PSCompletions # Install-PSResource PSCompletions
     ```

   - bash / zsh / fish - 运行 [安装脚本](install.sh)

     ```shell
     curl -fsSL https://raw.githubusercontent.com/abgox/PSCompletions/main/install.sh | sh
     ```

   - [Scoop](https://scoop.sh)

     ```shell
     scoop install pscompletions # scoop install abyss/abgox.PSCompletions
     ```

2. 加载它
   - PowerShell - [直接导入模块](https://pscompletions.abgox.com/docs/direct-import-module)

     ```powershell
     Import-Module PSCompletions
     ```

   - bash / zsh / fish - [安装脚本](install.sh) 会告诉你如何加载

3. 使用它

   ```shell
   psc
   ```

   ```shell
   psc add git
   ```

## 新的变化

请查看 [更新日志](./module/CHANGELOG.zh-CN.md)

## 贡献

请查看 [贡献指南](./.github/contributing.md)

## 支持

<!-- 每位赞助商一行，新加入的放在最后： `- [名称](https://…) — 一句话介绍。` -->

> [!TIP]
>
> 如果你喜欢这个项目，欢迎给它 Star ⭐️，也欢迎 [赞助](https://pscompletions.abgox.com/docs/sponsors)

## 致谢

- [PSReadLine](https://github.com/PowerShell/PSReadLine) - PowerShell 的编辑与补全基础
- [fzf](https://github.com/junegunn/fzf)/[PSFzf](https://github.com/kelleyma49/PSFzf) - [补全菜单](https://pscompletions.abgox.com/docs/completion-menu) 的 UI 参考

## License

[MIT](./LICENSE) © [abgox](https://me.abgox.com)
