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
- [更强大的补全菜单](#关于补全菜单)
- [支持多种语言: en-US, zh-CN 等](#关于语言)
- 根据命令历史记录动态排序补全项
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

  - 更多详情，参考 [菜单增强](#关于菜单增强)

- 使用 [PSFzf](https://github.com/kelleyma49/PSFzf) 作为补全菜单，参考 [与 PSFzf 结合使用](https://pscompletions.abgox.com/faq/pscompletions-and-psfzf)

## Tips

### 关于补全菜单

- 除了 `PowerShell` 内置的补全菜单，`PSCompletions` 模块还提供了一个更强大的补全菜单。

  - 配置: `psc menu config enable_menu 1` (默认开启)
  - 相关的按键绑定可运行 `psc` 查看

- 它只在 Windows 中可用，因为在 Linux/MacOS 中 [PowerShell 没有实现相关底层方法](https://github.com/cspotcode/PS-GuiCompletion/issues/13#issuecomment-620084134)

- 补全菜单的所有配置，你可以输入 `psc menu` 然后按下 `Space`(空格键) 和 `Tab` 键触发补全，通过 [补全提示信息](#关于补全提示信息) 来了解
  - 对于配置的值，`1` 表示 `true`，`0` 表示 `false` (这适用于 `PSCompletions` 的所有配置)
  - 常见的菜单行为:
    - 只有一个补全项时自动应用: `psc menu config enable_enter_when_single 1`
    - ...

#### 关于菜单增强

- 配置: `psc menu config enable_menu_enhance 1` (默认开启)
- `PSCompletions` 对于补全有两种实现

  - [Set-PSReadLineKeyHandler](https://learn.microsoft.com/powershell/module/psreadline/set-psreadlinekeyhandler)

    - 默认使用此实现
      - 前提: 配置项 `enable_menu` 和 `enable_menu_enhance` 同时为 `1`
      - 它使用 `Set-PSReadLineKeyHandler -Key <Key> -ScriptBlock { ... }`
        - `<Key>` 是 `psc menu config trigger_key` 的值 (默认: `Tab`)
      - 因此，你不能再使用 `Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { ... }`
    - 它使用 [TabExpansion2](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/tabexpansion2) 全局管理补全，不局限于 `psc add` 添加的补全
      - 路径补全: `cd`/`.\`/`..\`/`~\`/...
      - 内置命令补全: `Get-*`/`Set-*`/`New-*`/...
      - 通过 [Register-ArgumentCompleter](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter) 注册的补全
      - 由 cli 或模块注册的补全
      - ...

  - [Register-ArgumentCompleter](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter)

    - 可以通过运行 `psc menu config enable_menu_enhance 0` 来使用它
    - 则模块的补全菜单只对通过 `psc add` 添加的补全生效

### 关于选项类补全

- 选项类补全，指的是像 `-*` 的命令补全，例如 `git config --global` 中的 `--global`
- 你应该优先使用选项类补全
- 以 `git` 补全为例，如果你想要输入 `git config user.name --global xxx`
- 你应该先补全 `--global`，然后再补全 `user.name`，最后输入名称 `xxx`

### 关于路径补全

- 以 `git` 为例，当输入 `git add`，此时按下 `Space`(空格键) 和 `Tab` 键，不会触发路径补全，只会触发模块提供的命令补全
- 如果你希望触发路径补全，你需要输入内容，且内容符合正则 `^(?:\.\.?|~)?(?:[/\\]).*`
- 比如:

  - 输入 `./` 或 `.\` 后按下 `Tab` 以获取 **子目录** 或 **文件** 的路径补全
  - 输入 `../` 或 `..\` 后按下 `Tab` 以获取 **父级目录** 或 **文件** 的路径补全
  - 输入 `/` 或 `\` 后按下 `Tab` 以获取 **同级目录** 的路径补全
  - 更多的: `~/`, `../../`, ...

- 因此，你应该输入 `git add ./` 这样的命令再按下 `Tab` 键来获取路径补全

### 关于特殊符号

> [!Tip]
>
> - 由于 Windows Terminal 的变更导致在补全菜单中无法正常显示 😄🤔😎，因此将更换它们。
> - 相关的 issue: https://github.com/microsoft/terminal/issues/18242
> - 更改为: `~`,`?`,`!`

- 补全项后面的特殊符号用于在按下 `Tab` 键之前提前感知是否有可用的补全项

  - 它们仅存在于 `psc add` 添加的补全中
  - 你可以使用 `psc menu symbol <type> <symbol>` 来自定义
  - 例如，你可以替换成空字符串来隐藏它们
    - `psc menu symbol SpaceTab ""`
    - `psc menu symbol OptionTab ""`
    - `psc menu symbol WriteSpaceTab ""`

- `~`,`?`,`!` : 如果出现多个，表示符合多个条件

  - `~` : 表示选用当前选中的补全后，可以按下 `Tab` 键继续获取补全
  - `?` : 表示选用当前选中的 [选项类补全](#关于选项类补全) 后，可以按下 `Tab` 键继续获取当前的补全项列表
  - `!` : 表示选用当前选中的 [选项类补全](#关于选项类补全) 后，你应该输入一个字符串，然后按下 `Tab` 键继续获取当前的补全项列表

    - 如果字符串有空格，请使用 `"` 或 `'` 包裹，如 `"test content"`
    - 如果同时还有 `~`，表示有预设的补全项，你可以不输入字符串，直接按下 `Tab` 键继续获取它们

### 关于补全提示信息

- 补全提示信息只是辅助，可按需使用

  - 禁用所有补全的提示信息: `psc menu config enable_tip 0`
  - 禁用特定补全的提示信息: `psc completion git enable_tip 0`

- 补全提示信息一般由三部分组成: 用法(Usage) + 描述(Description) + 举例(Example)
  ```txt
  U: install, add [-g, -u] [options] <app>
  这里是命令的描述说明
  (在 U: 和 E: 之间的内容都是命令描述)
  E: install xxx
     add -g xxx
  ```
- 示例解析:

  1.  用法: 以 `U:` 开头(Usage)

      - 命令名称: `install`
      - 命令别名: `add`
      - 必填参数: `<app>`
        - `app` 是对必填参数的简要概括
      - 可选参数: `-g` `-u`
      - `[options]` 表示泛指一些选项类参数

  2.  描述: 在 `U:` 和 `E:` 之间的内容
  3.  举例: 以 `E:` 开头(Example)

### 关于语言

> [!Tip]
>
> - `Global language`: 默认为当前的系统语言
>   - `psc config language` 可以查看全局的语言配置
>   - `psc config language zh-CN` 可以更改全局的语言配置
> - `Completion language`: 为指定的补全设置的语言
>   - 例如: `psc completion git language en-US`
> - `Available language`: 每一个补全的 `config.json` 文件中有一个 `language` 属性，它的值是一个可用的语言列表

1. 如果有 `Completion language`，优先使用它，没有则使用 `Global language`
2. 判断第一步确定的值是否存在于 `Available language` 中
   - 如果存在，则使用它
   - 如果不存在，直接使用 `Available language` 中的第一种语言: `en-US`

## 致谢

- [PSReadLine](https://github.com/PowerShell/PSReadLine): PowerShell 的一个内置模块，增强命令行编辑体验
  - PSCompletions 使用了 `Set-PSReadLineKeyHandler` 和 `Get-PSReadLineOption`
- [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion): 适用于 PowerShell 的 GUI 风格的制表符补全菜单
  - PSCompletions 的 [补全菜单](#关于补全菜单) 受到了它的启发

## 补全列表

- [简体中文](./completions.zh-CN.md)
- [English](./completions.md)
