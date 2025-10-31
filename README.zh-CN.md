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
> - [PowerShell(pwsh)](https://learn.microsoft.com/powershell/scripting/overview): 跨平台的 PowerShell (Core)。运行 `pwsh`/`pwsh.exe` 启动
> - [Windows PowerShell](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell): Windows 系统内置的 PowerShell (Desktop)。运行 `powershell`/`powershell.exe` 启动
> - 它们都可以使用 `PSCompletions`，但是更推荐 [PowerShell(pwsh)](https://learn.microsoft.com/powershell/scripting/overview)

一个命令补全管理模块，用于在 `PowerShell` 中更简单、更方便地使用命令补全。

- [更强大的补全菜单](#关于补全菜单 "点击查看相关详情")
- [集中管理补全](./completions.zh-CN.md "点击查看可添加补全列表！")
- 动态排序补全项(根据使用频次)
- `en-US`,`zh-CN`,... 多语言切换
- [与 argc-completions 结合使用](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions "点击查看如何实现")

## Demo

> [!Tip]
>
> - 如果这里无法显示，[可前往官网查看](https://pscompletions.abgox.com)
> - [点击查看 Bilibili 中的介绍及教学视频](https://www.bilibili.com/video/BV15Gp7zmE2e)

![demo](https://pscompletions.abgox.com/demo.zh-CN.gif)

## 新的变化

- 请查阅 [更新日志](./module/CHANGELOG.zh-CN.md)

## 常见问题

- 请查阅 [常见问题](https://pscompletions.abgox.com/faq)

## 贡献

- 请查阅 [贡献指南](./.github/contributing.md)

## 安装

1. 安装模块:

   - 普通安装

     ```powershell
     Install-Module PSCompletions -Scope CurrentUser
     ```

   - 静默安装:

     ```powershell
     Install-Module PSCompletions -Scope CurrentUser -Repository PSGallery -Force
     ```

   - 使用 [Scoop](https://scoop.sh/) 安装

     - 添加 [abyss](https://abyss.abgox.com) bucket ([Github](https://github.com/abgox/abyss) 或 [Gitee](https://gitee.com/abgox/abyss))
     - 安装它

       ```shell
       scoop install abyss/abgox.PSCompletions
       ```

2. 导入模块:
   ```powershell
   Import-Module PSCompletions
   ```
   - 如果不想每次启动 `PowerShell` 都需要导入 `PSCompletions` 模块，你可以使用以下命令将导入语句写入 `$Profile` 中
     ```powershell
     "Import-Module PSCompletions" >> $Profile
     ```
   - 推荐将 `Import-Module PSCompletions` 添加到 `$Profile` 中靠前的位置，避免出现 [编码问题](https://pscompletions.abgox.com/faq/output-encoding)

## 卸载

```powershell
Uninstall-Module PSCompletions
```

## 使用

> [!Tip]
>
> - [可用补全列表](./completions.zh-CN.md "当前可添加的所有补全，更多的补全正在添加中！")
> - 如果补全列表里没有你想要的补全，你可以 [提交 issue](https://github.com/abgox/PSCompletions/issues "点击提交 issue")
> - 也可以 [与 argc-completions 结合使用](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions "点击查看如何实现")

以 `git` 补全为例

1. 添加补全: `psc add git`
2. 然后你就可以输入 `git`，按下 `Space`(空格键) 和 `Tab` 键获取命令补全
3. 关于 `psc` 的命令用法，你只需要输入 `psc` 然后按下 `Space`(空格键) 和 `Tab` 键触发补全，通过 [补全提示信息](#关于补全提示信息) 来了解

## Tips

### 关于补全触发按键

- 模块默认使用 `Tab` 键作为补全菜单触发按键
- 你可以使用 `psc menu config trigger_key <key>` 去设置它

> [!Warning]
>
> - 如果需要指定 `Set-PSReadLineKeyHandler -Key <key> -Function <MenuComplete|Complete>`
> - 请放在 `Import-Module PSCompletions` 之前

### 关于补全菜单

- 除了 `PowerShell` 内置的补全菜单，`PSCompletions` 模块还提供了一个更强大的补全菜单。

  - 配置: `psc menu config enable_menu 1` (默认开启)
  - 可通过 `psc menu config` 中的其他配置项控制它的相关行为

- 它只在 Windows 中可用，因为在 Linux/MacOS 中 [PowerShell 没有实现相关底层方法](https://github.com/cspotcode/PS-GuiCompletion/issues/13#issuecomment-620084134)

- 相关的按键绑定:

  1. 选用当前选中的补全项: `Enter`(回车) / `Space`(空格)
     - 当只有一个补全项时，也可以使用 `Tab`
  2. 删除过滤字符: `Backspace`(退格)
  3. 退出补全菜单: `Esc` / `Ctrl + c`
     - 当过滤区域没有字符时，也可以使用 `Backspace`(退格) 退出补全菜单
  4. 选择补全项:

     |  选择上一项   | 选择下一项 |
     | :-----------: | :--------: |
     |     `Up`      |   `Down`   |
     |    `Left`     |  `Right`   |
     | `Shift + Tab` |   `Tab`    |
     |  `Ctrl + u`   | `Ctrl + d` |
     |  `Ctrl + p`   | `Ctrl + n` |

- 补全菜单的所有配置，你可以输入 `psc menu` 然后按下 `Space`(空格键) 和 `Tab` 键触发补全，通过 [补全提示信息](#关于补全提示信息) 来了解
  - 对于配置的值，`1` 表示 `true`，`0` 表示 `false` (这适用于 `PSCompletions` 的所有配置)
  - 一些常见的菜单行为:
    - 只有一个补全项时自动应用: `psc menu config enable_enter_when_single 1`
    - 使用前缀匹配进行过滤: `psc menu config enable_prefix_match_in_filter 1`
      - 如果为 `0`，则使用模糊匹配，支持使用 `*` 和 `?` 通配符
    - ...

#### 关于菜单增强

- 配置: `psc menu config enable_menu_enhance 1` (默认开启)
- `PSCompletions` 对于补全有两种实现

  - [Set-PSReadLineKeyHandler](https://learn.microsoft.com/powershell/module/psreadline/set-psreadlinekeyhandler)

    - 默认使用此实现
      - 前提: 配置项 `enable_menu` 和 `enable_menu_enhance` 同时为 `1`
    - 它不再需要循环为所有补全命令注册 [Register-ArgumentCompleter](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter)，理论上加载速度会更快
    - 它使用 [TabExpansion2](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/tabexpansion2) 全局管理补全，不局限于 `psc add` 添加的补全
      - 路径补全: `cd`/`.\`/`..\`/`~\`/...
      - 内置命令补全: `Get-*`/`Set-*`/`New-*`/...
      - 通过 [Register-ArgumentCompleter](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter) 注册的补全
      - [与 argc-completions 结合使用](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions)
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

### 关于特殊符号

> [!Tip]
>
> - 由于 Windows Terminal 的变更导致在补全菜单中无法正常显示 😄🤔😎，因此将更换它们。
> - 相关的 issue: https://github.com/microsoft/terminal/issues/18242
> - 变化如下:
>   - `😄` => `~`
>   - `🤔` => `?`
>   - `😎` => `!`

- 补全项后面的特殊符号用于在按下 `Tab` 键之前提前感知是否有可用的补全项

  - 只有通过 `psc add` 添加的补全中才存在
  - 你可以使用 `psc menu symbol <type> <symbol>` 来自定义
  - 例如，你可以替换成空字符串来隐藏它们
    - `psc menu symbol SpaceTab ""`
    - `psc menu symbol OptionTab ""`
    - `psc menu symbol WriteSpaceTab ""`

- `~`,`?`,`!` : 如果出现多个，表示符合多个条件

  - `~` : 表示选用当前选中的补全后，可以按下 `Tab` 键继续获取补全
  - `?` : 表示选用当前选中的 [(通用)选项类补全](#关于选项类补全) 后，可以按下 `Tab` 键继续获取当前的补全项列表
  - `!` : 表示选用当前选中的 [(通用)选项类补全](#关于选项类补全) 后，你可以再输入一个字符串，然后按下 `Tab` 键继续获取当前的补全项列表

    - 如果字符串有空格，请使用 `"` 或 `'` 包裹，如 `"test content"`
    - 如果同时还有 `~`，表示有预设的补全项，你可以不输入字符串，直接按下 `Tab` 键继续获取它们

### 关于补全提示信息

- 补全提示信息只是辅助，你也可以使用 `psc menu config enable_tip 0` 全局禁用补全提示信息

  - 默认启用补全提示信息: `psc menu config enable_tip 1`
  - 也可以禁用特定补全的提示信息，如 `git`
    - `psc completion git enable_tip 0`

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

- `Global language`: 默认为当前的系统语言
  - `psc config language` 可以查看全局的语言配置
  - `psc config language zh-CN` 可以更改全局的语言配置
- `Completion language`: 为指定的补全设置的语言
  - 例如: `psc completion git language en-US`
- `Available language`: 每一个补全的 `config.json` 文件中有一个 `language` 属性，它的值是一个可用的语言列表

#### 确定语言

1. 如果有 `Completion language`，优先使用它，没有则使用 `Global language`
2. 确定最终使用的语言:
   - 判断第一步确定的值是否存在于 `Available language` 中
   - 如果存在，则使用它
   - 如果不存在，直接使用 `Available language` 中的第一种语言(一般为 `en-US`)

### 关于路径补全

- 以 `git` 为例，当输入 `git add`，此时按下 `Space`(空格键) 和 `Tab` 键，不会触发路径补全，只会触发模块提供的命令补全
- 如果你希望触发路径补全，你需要输入内容，且内容符合正则 `^(?:\.\.?|~)?(?:[/\\]).*`
- 比如:

  - 输入 `./` 或 `.\` 后按下 `Tab` 以获取 **子目录** 或 **文件** 的路径补全
  - 输入 `../` 或 `..\` 后按下 `Tab` 以获取 **父级目录** 或 **文件** 的路径补全
  - 输入 `/` 或 `\` 后按下 `Tab` 以获取 **同级目录** 的路径补全
  - 更多的: `~/` / `../../` ...

- 因此，你应该输入 `git add ./` 这样的命令再按下 `Tab` 键来获取路径补全

## 致谢

- [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion): 模块的补全菜单受到它的启发

## 补全列表

- [简体中文](./completions.zh-CN.md)
- [English](./completions.md)
