<h1 align="center">✨<a href="https://pscompletions.abgox.com">PSCompletions(psc)</a>✨</h1>

<p align="center">
    <a href="README.md">English</a> |
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
    <a href="./completions.zh-CN.md">
        <img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fabgox%2FPSCompletions%2Frefs%2Fheads%2Fmain%2Fcompletions.json&query=%24.count&label=completions" alt="completions" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/dt/PSCompletions" alt="PowerShell Gallery" />
    </a>
    <a href="https://github.com/abgox/PSCompletions">
        <img src="https://img.shields.io/github/created-at/abgox/PSCompletions" alt="created" />
    </a>
</p>

## 介绍

一个补全管理器，为 [PowerShell](https://microsoft.com/powershell) 带来更出色、更简便的 Tab 补全体验，基于 [Rust + Lua](https://pscompletions.abgox.com/docs/how-it-works) 构建。

- [内置的补全库](./completions.zh-CN.md)
- [强大的模块补全菜单](https://pscompletions.abgox.com/docs/module-completion-menu)
- [支持多种语言: en-US、zh-CN 等](https://pscompletions.abgox.com/docs/language)
- [根据命令历史记录动态排序补全项](https://pscompletions.abgox.com/docs/sort-completion-items)

## 演示

![demo](https://pscompletions.abgox.com/demo.gif)

## 安装

1. 安装模块
   - [Install-Module](https://learn.microsoft.com/powershell/module/powershellget/install-module)

     ```powershell
     Install-Module PSCompletions
     ```

   - [Install-PSResource](https://learn.microsoft.com/powershell/module/microsoft.powershell.psresourceget/install-psresource)

     ```powershell
     Install-PSResource PSCompletions
     ```

   - [Scoop](https://scoop.sh)
     - 添加 [abyss](https://abyss.abgox.com) bucket ([GitHub](https://github.com/abgox/abyss) 或 [Gitee](https://gitee.com/abgox/abyss))
     - 安装它

       ```shell
       scoop install abyss/abgox.PSCompletions
       ```

2. [导入模块](https://pscompletions.abgox.com/docs/direct-import-module)

   ```powershell
   Import-Module PSCompletions
   ```

## 使用

- [内置补全库](./completions.zh-CN.md): 使用 `psc add git` 添加补全
- [原生补全集成](https://pscompletions.abgox.com/docs/native-completion): 使用 PowerShell 的原生补全
  - 如果命令存在官方补全，可以使用类似的命令:

    ```powershell
    xxx completion powershell | Out-String | Invoke-Expression
    ```

  - 使用 PowerShell 参数补全器:

    ```powershell
    Register-ArgumentCompleter -Native -CommandName <Name> -ScriptBlock { ... }
    ```

  - 使用其他的补全库，例如 [Carapace](https://pscompletions.abgox.com/docs/tools/carapace)

## 新的变化

请查看 [更新日志](./module/CHANGELOG.zh-CN.md)

## 贡献

请查看 [贡献指南](./.github/contributing.md)

## 支持

如果你喜欢这个项目，欢迎给它 Star ⭐️ 或 [赞赏 💰](https://me.abgox.com/donate)

## 致谢

- **使用**: [PSReadLine](https://github.com/PowerShell/PSReadLine) — PowerShell 内置模块，增强命令行补全体验
- **启发**: [模块补全菜单](https://pscompletions.abgox.com/docs/module-completion-menu) 受到了以下项目的启发:
  - [fzf](https://github.com/junegunn/fzf): 通用命令行模糊查找器
  - [PSFzf](https://github.com/kelleyma49/PSFzf): 将 fzf 集成到 PowerShell 的模糊查找
  - [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion): PowerShell 的图形化补全菜单（早期 V6 版本的启发）

## License

[MIT](./LICENSE) © [abgox](https://me.abgox.com)
