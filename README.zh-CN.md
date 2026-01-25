<h1 align="center">✨<a href="https://pscompletions.abgox.com">PSCompletions(psc)</a>✨</h1>

<p align="center">
    <a href="README.md">English</a> |
    <a href="README.zh-CN.md">简体中文</a> |
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
  <strong>喜欢这个项目？请给它 Star ⭐️ 或 <a href="https://abgox.com/donate">赞赏 💰</a></strong>
</p>

## 介绍

> [!Tip]
>
> - [PowerShell(pwsh)](https://microsoft.com/powershell): 跨平台的 PowerShell (Core)，运行 `pwsh`/`pwsh.exe` 启动
> - [Windows PowerShell](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell): Windows 系统内置的 PowerShell (Desktop)，运行 `powershell`/`powershell.exe` 启动
> - 它们都可以使用 `PSCompletions`，但是更推荐 [PowerShell(pwsh)](https://microsoft.com/powershell)

一个补全管理器，为 `PowerShell` 带来更出色、更简便的 Tab 补全体验。

- [内置的补全库](./completions.zh-CN.md)
- [更强大的模块补全菜单](https://pscompletions.abgox.com/faq/module-completion-menu)
- [支持多种语言: en-US, zh-CN 等](https://pscompletions.abgox.com/faq/language)
- [根据命令历史记录动态排序补全项](https://pscompletions.abgox.com/faq/sort-completion-items)
- 与其他工具协作
  - [argc-completions](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions)
  - [Carapace](https://pscompletions.abgox.com/faq/pscompletions-and-carapace)
  - [PSFzf](https://pscompletions.abgox.com/faq/pscompletions-and-psfzf)

## 演示

> [!Tip]
>
> - 如果这里无法显示，[可前往官网查看](https://pscompletions.abgox.com)
> - [点击查看 Bilibili 中的介绍及教学视频](https://www.bilibili.com/video/BV15Gp7zmE2e)

![demo](https://pscompletions.abgox.com/demo.zh-CN.gif)

## 新的变化

请查阅 [更新日志](./module/CHANGELOG.zh-CN.md)

## 常见问题

请查阅 [常见问题](https://pscompletions.abgox.com/faq)

## 贡献

请查阅 [贡献指南](./.github/contributing.md)

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

   - [Scoop](https://scoop.sh/)
     - 添加 [abyss](https://abyss.abgox.com) bucket ([Github](https://github.com/abgox/abyss) 或 [Gitee](https://gitee.com/abgox/abyss))
     - 安装它

       ```shell
       scoop install abyss/abgox.PSCompletions
       ```

2. 导入模块

   ```powershell
   Import-Module PSCompletions
   ```

> [!Tip]
>
> - 如果使用了 `. $Profile`，请运行 `psc` 以重载模块的按键绑定及数据
> - 参考: https://pscompletions.abgox.com/faq/source-profile

## 使用

- 使用 [内置的补全库](./completions.zh-CN.md)，以 `git` 补全为例
  1. 使用 `psc add git` 添加补全
  2. 输入 `git`，按下 `Space`(空格键) 和 `Tab` 键获取命令补全

- 使用官方补全或其他的补全库
  - 如果存在官方补全，可以使用类似的命令

    ```powershell
    xxx completion powershell | Out-String | Invoke-Expression
    ```

  - 使用其他的补全库: [argc-completions](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions), [Carapace](https://pscompletions.abgox.com/faq/pscompletions-and-carapace)

  - 更多详情，参考: https://pscompletions.abgox.com/faq/menu-enhance

- 使用 [PSFzf](https://github.com/kelleyma49/PSFzf) 作为补全菜单，参考 [与 PSFzf 结合使用](https://pscompletions.abgox.com/faq/pscompletions-and-psfzf)

## 致谢

- [PSReadLine](https://github.com/PowerShell/PSReadLine): PowerShell 的一个内置模块，增强命令行编辑体验
  - PSCompletions 使用了 `Set-PSReadLineKeyHandler` 和 `Get-PSReadLineOption`
- [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion): 适用于 PowerShell 的 GUI 风格的制表符补全菜单
  - PSCompletions 的 [模块补全菜单](https://pscompletions.abgox.com/faq/module-completion-menu) 受到了它的启发

## 补全列表

- [简体中文](./completions.zh-CN.md)
- [English](./completions.md)
