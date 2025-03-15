<p align="center">
    <h1 align="center">✨<a href="https://pscompletions.abgox.com">PSCompletions(psc)</a>✨</h1>
</p>

<p align="center">
    <a href="README.md">English</a> |
    <a href="README-CN.md">简体中文</a> |
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
        <img src="https://img.shields.io/powershellgallery/dt/PSCompletions?color=%23008FC7" alt="PowerShell Gallery" />
    </a>
    <a href="https://img.shields.io/github/languages/code-size/abgox/PSCompletions.svg">
        <img src="https://img.shields.io/github/languages/code-size/abgox/PSCompletions.svg" alt="code size" />
    </a>
    <a href="https://img.shields.io/github/repo-size/abgox/PSCompletions.svg">
        <img src="https://img.shields.io/github/repo-size/abgox/PSCompletions.svg" alt="repo size" />
    </a>
    <a href="https://github.com/abgox/PSCompletions">
        <img src="https://img.shields.io/badge/created-2023--8--15-blue" alt="created" />
    </a>
</p>

---

## 介绍

> [!Tip]
>
> - [`PowerShell`](https://github.com/PowerShell/PowerShell): 跨平台的 PowerShell。运行 `pwsh`/`pwsh.exe` 启动
> - [`Windows PowerShell`](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell): Windows 系统内置的 PowerShell。运行 `powershell`/`powershell.exe` 启动
> - 它们都可以使用 `PSCompletions`, 但是更推荐 [`PowerShell`](https://github.com/PowerShell/PowerShell)

- 一个 `PowerShell` 补全管理模块，更好、更简单、更方便的使用和管理补全
- [集中管理补全](#补全列表 "点击查看可添加补全列表！")
- `en-US`,`zh-CN`,... 多语言切换
- 动态排序补全项(根据使用频次)
- [提供了一个更强大的补全菜单](#关于补全菜单 "点击查看相关详情")
- [与 argc-completions 结合使用](https://pscompletions.abgox.com/tips/pscompletions-and-argc-completions "点击查看如何实现")
  - [argc-completions 仓库](https://github.com/sigoden/argc-completions)

[**如果 `PSCompletions` 对你有所帮助，请考虑给它一个 Star ⭐**](#stars)

## 新的变化

- 请查阅 [更新日志](./module/CHANGELOG-CN.md)

## 常见问题

- 请查阅 [常见问题](https://pscompletions.abgox.com/FAQ)

## 安装

1. 打开 `PowerShell`
2. 安装模块:

   - 除非你确定始终会使用管理员权限打开 `PowerShell`，否则不要省略 `-Scope CurrentUser`

   ```powershell
   Install-Module PSCompletions -Scope CurrentUser
   ```

   - 静默安装:

   ```powershell
   Install-Module PSCompletions -Scope CurrentUser -Repository PSGallery -Force
   ```

3. 导入模块:
   ```powershell
   Import-Module PSCompletions
   ```
   - 如果不想每次启动 `PowerShell` 都需要导入 `PSCompletions` 模块，你可以使用以下命令将导入语句写入 `$PROFILE` 中
   ```powershell
   echo "Import-Module PSCompletions" >> $PROFILE
   ```

> [!Warning]
>
> - 导入 `PSCompletions` 后，就不要使用 `Set-PSReadLineKeyHandler -Key <key> -Function MenuComplete` 了
> - 因为 `PSCompletions` 使用了它，如果再次使用，会覆盖 `PSCompletions` 中的设置，导致 `PSCompletions` 补全菜单无法正常工作
> - 你应该通过 `PSCompletions` 中的配置去设置它
> - 详细配置请参考 [关于补全触发按键](#关于补全触发按键)
>
> ```diff
> + Import-Module PSCompletions
>
> - Set-PSReadLineKeyHandler -Key <key> -Function MenuComplete
> ```

## 卸载

1. 打开 `PowerShell`
2. 卸载模块:
   ```powershell
   Uninstall-Module PSCompletions
   ```

## 使用

> [!Tip]
>
> - [可用补全列表](#补全列表 "当前可添加的所有补全，更多的补全正在添加中！")
> - 如果补全列表里没有你想要的补全，你可以 [提交 issues](https://github.com/abgox/PSCompletions/issues "点击提交 issues")
> - 也可以 [与 argc-completions 结合使用](https://pscompletions.abgox.com/tips/pscompletions-and-argc-completions "点击查看如何实现")

- 以 `git` 补全为例

1. `psc add git`
2. 然后你就可以输入 `git`, 按下 `Space`(空格键) `Tab` 键来获得命令补全
3. 关于 `psc` 的更多命令用法，你只需要输入 `psc` 然后按下 `Space`(空格键) `Tab` 键触发补全，通过 [补全提示信息](#关于补全提示信息) 来了解

## Demo

![demo](https://pscompletions.abgox.com/demo-CN.gif)

## 贡献

- 请查阅 [CONTRIBUTING](./.github/contributing.md)

## Tips

### 关于补全触发按键

- 模块默认使用 `Tab` 键作为补全菜单触发按键
- 你可以使用 `psc menu config trigger_key <key>` 去设置它

> [!Warning]
>
> - 导入 `PSCompletions` 后，就不要使用 `Set-PSReadLineKeyHandler -Key <key> -Function MenuComplete` 了
> - 因为 `PSCompletions` 使用了它，如果再次使用，会覆盖 `PSCompletions` 中的设置，导致 `PSCompletions` 补全菜单无法正常工作
>
> ```diff
> + Import-Module PSCompletions
>
> - Set-PSReadLineKeyHandler -Key <key> -Function MenuComplete
> ```

### 关于补全更新

- 当打开 `PowerShell` 并导入 `PSCompletions` 模块后，`PSCompletions` 会开启一个后台作业去检查远程仓库中补全的状态
- 获取到更新后，会在下一次打开 `PowerShell` 并导入 `PSCompletions` 后显示补全更新提示

### 关于选项类补全

- 选项类补全，指的是像 `-*` 的命令补全，例如 `git config --global` 中的 `--global`
- 你应该优先使用选项类补全
- 以 `git` 补全为例，如果你想要输入 `git config user.name --global xxx`
- 你应该先补全 `--global`，然后再补全 `user.name`，最后输入名称 `xxx`

### 关于补全菜单

- 除了 `PowerShell` 内置的补全菜单，`PSCompletions` 模块还提供了一个更强大的补全菜单。
  - 配置: `psc menu config enable_menu 1` (默认开启)
- 模块提供的补全菜单基于 [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion) 的实现思路，感谢 [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion) !
- 模块提供的补全菜单可用的 Windows 环境：
  - `PowerShell` <img src="https://img.shields.io/badge/module%20version-v4.0.0+-4CAF50" alt="v4.0.0+ support" />
  - `Windows PowerShell` <img src="https://img.shields.io/badge/module%20version-v4.1.0+-4CAF50" alt="v4.1.0+ support" />
    - 由于 `Windows PowerShell` 渲染问题，补全菜单的边框样式无法自定义
    - 如果需要自定义，请使用 `PowerShell`
- 模块提供的补全菜单中的按键

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

- 补全菜单的所有配置, 你可以输入 `psc menu` 然后按下 `Space`(空格键) `Tab` 键触发补全，通过 [补全提示信息](#关于补全提示信息) 来了解
  - 对于配置的值，`1` 表示 `true`，`0` 表示 `false` (这适用于 `PSCompletions` 的所有配置)

#### 关于菜单增强 <img src="https://img.shields.io/badge/module%20version-v4.2.0+-4CAF50" alt="v4.2.0+ support" />

- 配置: `psc menu config enable_menu_enhance 1` (默认开启)
- 现在，`PSCompletions` 对于补全有两种实现

  1. [`Register-ArgumentCompleter`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter)

     - <img src="https://img.shields.io/badge/module%20version-v4.1.0-4CAF50" alt="v4.1.0 support" /> 及之前版本都使用此实现
     - <img src="https://img.shields.io/badge/module%20version-v4.2.0+-4CAF50" alt="v4.2.0+ support" />: 此实现变为可选
       - 你可以运行 `psc menu config enable_menu_enhance 0` 来继续使用它
       - 但并不推荐，它只能用于 `psc add` 添加的补全

  2. [`Set-PSReadLineKeyHandler`](https://learn.microsoft.com/powershell/module/psreadline/set-psreadlinekeyhandler)
     - <img src="https://img.shields.io/badge/module%20version-v4.2.0+-4CAF50" alt="v4.2.0+ support" />: 默认使用此实现
       - 需要 `enable_menu` 和 `enable_menu_enhance` 同时为 `1`
     - 它不再需要循环为所有补全命令注册 `Register-ArgumentCompleter`，理论上加载速度会更快
     - 同时使用 [`TabExpansion2`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/tabexpansion2) 全局管理补全，不局限于 `psc add` 添加的补全
       - 例如:
         - `cd`/`.\`/`..\`/`~\`/... 这样的路径补全
         - `Get-*`/`Set-*`/`New-*`/... 这样的内置命令补全
         - 通过 [`Register-ArgumentCompleter`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter) 注册的补全
         - [与 argc-completions 结合使用](https://pscompletions.abgox.com/tips/pscompletions-and-argc-completions)
         - 由 cli 或模块注册的补全
         - ...

### 关于特殊符号

> [!Tip]
>
> - 由于未来的 Windows Terminal 的变化，将导致在补全菜单中无法正常显示 😄🤔😎，因此这三个默认特殊符号将改变。
> - 相关的 issue: https://github.com/microsoft/terminal/issues/18242
> - 变化如下:
>   - `😄` => `»`
>   - `🤔` => `?`
>   - `😎` => `!`

- 补全项后面的特殊符号用于在按下 `Tab` 键之前提前感知是否有可用的补全项

  - 只有通过 `psc add` 添加的补全中才存在

  - 你可以将它们替换成空字符串来隐藏它们
    - `psc menu symbol SpaceTab ""`
    - `psc menu symbol OptionTab ""`
    - `psc menu symbol WriteSpaceTab ""`

- `»`,`?`,`!` : 如果出现多个, 表示符合多个条件, 可以选择其中一个效果

  - 定义:
    - `Normal Completions`: 子命令，例如在 `git` 中的 `add`/`pull`/`push`/`commit`/...
    - `Optional Completions`: 可选参数，例如在 `git add` 中的 `-g`/`-u`/...
    - `General Optional Completions`: 可以用在任何地方的通用可选参数，例如在 `git` 中的 `--help`/...
    - `Current Completions`: 当前的补全项列表
  - `»` : 表示选用当前选中的补全后, 可以按下 `Space`(空格键) 和 `Tab` 键继续获取补全
    - 可通过 `psc menu symbol SpaceTab <symbol>` 自定义此符号
  - `?` : 表示选用当前选中的补全(`Optional Completions` 或 `General Optional Completions`)后, 可以按下 `Space`(空格键) 和 `Tab` 键继续获取 `Current Completions`
    - 可通过 `psc menu symbol OptionTab <symbol>` 自定义此符号
  - `!` : 表示选用当前选中的补全(`Optional Completions` 或 `General Optional Completions`)后, 你可以按下 `Space`(空格键), 再输入一个字符串, 然后按下 `Space`(空格键) 和 `Tab` 键继续获取补全

    - 如果字符串有空格, 请使用 `"`(引号) 或 `'`(单引号) 包裹，如 `"test content"`
    - 如果同时还有 `»`, 表示有预设的补全项, 你可以不输入字符串, 直接按下 `Space`(空格键) 和 `Tab` 键继续获取它们
    - 可通过 `psc menu symbol WriteSpaceTab <symbol>` 自定义此符号

  - 所有补全都可以在输入部分字符后按下 `Tab` 键触发补全
  - 对于以 `=` 结尾的选项，如果有相关补全定义，则可以直接按下 `Tab` 键触发补全

### 关于补全提示信息

- 补全提示信息只是辅助, 你也可以使用 `psc menu config enable_tip 0` 来禁用补全提示信息

  - 启用补全提示信息: `psc menu config enable_tip 1`
  - 也可以禁用特定补全的提示信息，如 `psc`
    - `psc completion psc enable_tip 0`

- 补全提示信息一般由三部分组成: 用法(Usage) + 描述(Description) + 举例(Example)
  ```txt
  U: install|add [-g|-u] [options] <app>
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

1. 确定指定的语言: 如果有 `Completion language`，优先使用它，没有则使用 `Global language`
2. 确定最终使用的语言:
   - 判断第一步确定的值是否存在于 `Available language` 中
   - 如果存在，则使用它
   - 如果不存在，直接使用 `Available language` 中的第一种语言(一般为 `en-US`)

### 关于路径补全

- 以 `git` 为例，当输入 `git add`，此时按下 `Space` 和 `Tab` 键，不会触发路径补全，只会触发模块提供的命令补全
- 如果你希望触发路径补全，你需要输入内容，且内容符合正则 `^(?:\.\.?|~)?(?:[/\\]).*`
- 比如:

  - 输入 `./` 或 `.\` 后按下 `Tab` 以获取 **子目录** 或 **文件** 的路径补全
  - 输入 `../` 或 `..\` 后按下 `Tab` 以获取 **父级目录** 或 **文件** 的路径补全
  - 输入 `/` 或 `\` 后按下 `Tab` 以获取 **同级目录** 的路径补全
  - 更多的: `~/` / `../../` ...

- 因此，你应该输入 `git add ./` 这样的命令再按下 `Tab` 键来获取路径补全

## Stars

**如果 `PSCompletions` 对你有所帮助，请考虑给它一个 Star ⭐**

<a href="https://github.com/abgox/PSCompletions">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="http://reporoster.com/stars/abgox/PSCompletions"> <!-- light theme -->
    <img alt="stargazer-widget" src="http://reporoster.com/stars/dark/abgox/PSCompletions"> <!-- dark theme -->
  </picture>
</a>

## 赞赏支持

<a href='https://ko-fi.com/W7W817R6Z3' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://me.abgox.com/buy-me-a-coffee.png' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

![赞赏支持](https://me.abgox.com/support.png)

## 补全列表

- 说明

  - **`Completion`** ：可添加的补全。点击跳转命令官方网站，按照数字字母排序(0-9,a-z)。
    - 特殊情况: `abc(a)`，这表示你需要通过 `psc add abc` 去下载它，但默认使用 `a` 而不是 `abc` 去触发补全
  - **`Language`**: 支持的语言，以及完成进度

    - 这个进度是和 `config.json` 中定义的第一个语言相比，一般是 `en-US`

  - **`Description`**: 命令描述

<!-- prettier-ignore-start -->
|Completion|Language|Description|
|:-:|-|-|
|[7z](https://7-zip.org/)|[**en-US**](/completions/7z/language/en-US.json)<br>[**zh-CN(100%)**](/completions/7z/language/zh-CN.json)|7-Zip 的命令行 cli 程序。|
|[arch](https://github.com/uutils/coreutils)|[**en-US**](/completions/arch/language/en-US.json)<br>[**zh-CN(100%)**](/completions/arch/language/zh-CN.json)|显示当前系统架构。<br> 补全基于 [uutils/coreutils](https://github.com/uutils/coreutils) 编写。|
|[b2sum](https://github.com/uutils/coreutils)|[**en-US**](/completions/b2sum/language/en-US.json)<br>[**zh-CN(13.33%)**](/completions/b2sum/language/zh-CN.json)|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[b3sum](https://github.com/uutils/coreutils)|[**en-US**](/completions/b3sum/language/en-US.json)<br>[**zh-CN(13.33%)**](/completions/b3sum/language/zh-CN.json)|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[base32](https://github.com/uutils/coreutils)|[**en-US**](/completions/base32/language/en-US.json)<br>[**zh-CN(28.57%)**](/completions/base32/language/zh-CN.json)|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[base64](https://github.com/uutils/coreutils)|[**en-US**](/completions/base64/language/en-US.json)<br>[**zh-CN(28.57%)**](/completions/base64/language/zh-CN.json)|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[basename](https://github.com/uutils/coreutils)|[**en-US**](/completions/basename/language/en-US.json)<br>[**zh-CN(28.57%)**](/completions/basename/language/zh-CN.json)|Print NAME with any leading directory components removed.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[basenc](https://github.com/uutils/coreutils)|[**en-US**](/completions/basenc/language/en-US.json)<br>[**zh-CN(13.33%)**](/completions/basenc/language/zh-CN.json)|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[bun](https://bun.sh)|[**en-US**](/completions/bun/language/en-US.json)<br>[**zh-CN(100%)**](/completions/bun/language/zh-CN.json)|Bun - JavaScript 运行时和工具包。|
|[cargo](https://rustwiki.org/zh-CN/cargo/)|[**en-US**](/completions/cargo/language/en-US.json)<br>[**zh-CN(100%)**](/completions/cargo/language/zh-CN.json)|cargo - Rust 包管理器。|
|[chfs](http://iscute.cn/chfs)|[**en-US**](/completions/chfs/language/en-US.json)<br>[**zh-CN(100%)**](/completions/chfs/language/zh-CN.json)|CuteHttpFileServer - 一个免费的、HTTP协议的文件共享服务器。|
|[choco](https://chocolatey.org/)|[**en-US**](/completions/choco/language/en-US.json)<br>[**zh-CN(100%)**](/completions/choco/language/zh-CN.json)|choco(chocolatey) - 软件管理。|
|[cksum](https://github.com/uutils/coreutils)|[**en-US**](/completions/cksum/language/en-US.json)<br>[**zh-CN(20%)**](/completions/cksum/language/zh-CN.json)|Print CRC and size for each file.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[comm](https://github.com/uutils/coreutils)|[**en-US**](/completions/comm/language/en-US.json)<br>[**zh-CN(20%)**](/completions/comm/language/zh-CN.json)|Compare two sorted files line by line.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[conda](https://github.com/conda/conda)|[**en-US**](/completions/conda/language/en-US.json)<br>[**zh-CN(100%)**](/completions/conda/language/zh-CN.json)|conda - 二进制包和环境管理器。|
|[csplit](https://github.com/uutils/coreutils)|[**en-US**](/completions/csplit/language/en-US.json)<br>[**zh-CN(18.18%)**](/completions/csplit/language/zh-CN.json)|Split a file into sections determined by context lines.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[cut](https://github.com/uutils/coreutils)|[**en-US**](/completions/cut/language/en-US.json)<br>[**zh-CN(15.38%)**](/completions/cut/language/zh-CN.json)|Print specified byte or field columns from each line of stdin or the input files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[date](https://github.com/uutils/coreutils)|[**en-US**](/completions/date/language/en-US.json)<br>[**zh-CN(14.29%)**](/completions/date/language/zh-CN.json)|Print or set the system date and time.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[dd](https://github.com/uutils/coreutils)|[**en-US**](/completions/dd/language/en-US.json)<br>[**zh-CN(100%)**](/completions/dd/language/zh-CN.json)|复制并转换文件系统资源。<br> 补全基于 [uutils/coreutils](https://github.com/uutils/coreutils) 编写。|
|[deno](https://deno.com/)|[**en-US**](/completions/deno/language/en-US.json)<br>[**zh-CN(100%)**](/completions/deno/language/zh-CN.json)|Deno - 安全的 JavaScript 和 TypeScript 运行时。|
|[df](https://github.com/uutils/coreutils)|[**en-US**](/completions/df/language/en-US.json)<br>[**zh-CN(5.71%)**](/completions/df/language/zh-CN.json)|Show information about the file system on which each FILE resides, or all file systems by default.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[dircolors](https://github.com/uutils/coreutils)|[**en-US**](/completions/dircolors/language/en-US.json)<br>[**zh-CN(25%)**](/completions/dircolors/language/zh-CN.json)|Output commands to set the LS_COLORS environment variable.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[dirname](https://github.com/uutils/coreutils)|[**en-US**](/completions/dirname/language/en-US.json)<br>[**zh-CN(40%)**](/completions/dirname/language/zh-CN.json)|Strip last component from file name.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[docker](https://www.docker.com)|[**en-US**](/completions/docker/language/en-US.json)<br>[**zh-CN(100%)**](/completions/docker/language/zh-CN.json)|docker - 容器应用开发。|
|[du](https://github.com/uutils/coreutils)|[**en-US**](/completions/du/language/en-US.json)<br>[**zh-CN(2.17%)**](/completions/du/language/zh-CN.json)|Estimate file space usage.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[env](https://github.com/uutils/coreutils)|[**en-US**](/completions/env/language/en-US.json)<br>[**zh-CN(16.67%)**](/completions/env/language/zh-CN.json)|Set each NAME to VALUE in the environment and run COMMAND.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[factor](https://github.com/uutils/coreutils)|[**en-US**](/completions/factor/language/en-US.json)<br>[**zh-CN(20%)**](/completions/factor/language/zh-CN.json)|Print the prime factors of the given NUMBER(s).<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[fmt](https://github.com/uutils/coreutils)|[**en-US**](/completions/fmt/language/en-US.json)<br>[**zh-CN(11.76%)**](/completions/fmt/language/zh-CN.json)|Reformat paragraphs from input files (or stdin) to stdout.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[fnm](https://github.com/Schniz/fnm)|[**en-US**](/completions/fnm/language/en-US.json)<br>[**zh-CN(8.33%)**](/completions/fnm/language/zh-CN.json)|快速、简单的 Node.js 版本管理器，使用 Rust 构建。|
|[fold](https://github.com/uutils/coreutils)|[**en-US**](/completions/fold/language/en-US.json)<br>[**zh-CN(28.57%)**](/completions/fold/language/zh-CN.json)|Writes each file (or standard input if no files are given) to standard output whilst breaking long lines.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[git](https://git-scm.com)|[**en-US**](/completions/git/language/en-US.json)<br>[**zh-CN(100%)**](/completions/git/language/zh-CN.json)|Git - 版本控制系统。|
|[hashsum](https://github.com/uutils/coreutils)|[**en-US**](/completions/hashsum/language/en-US.json)<br>[**zh-CN(6.45%)**](/completions/hashsum/language/zh-CN.json)|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[head](https://github.com/uutils/coreutils)|[**en-US**](/completions/head/language/en-US.json)<br>[**zh-CN(22.22%)**](/completions/head/language/zh-CN.json)|Print the first 10 lines of each 'FILE' to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[join](https://github.com/uutils/coreutils)|[**en-US**](/completions/join/language/en-US.json)<br>[**zh-CN(11.11%)**](/completions/join/language/zh-CN.json)|For each pair of input lines with identical join fields, write a line to standard output.<br> The default join field is the first, delimited by blanks.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[kubectl](https://kubernetes.io/zh-cn/docs/reference/kubectl/)|[**en-US**](/completions/kubectl/language/en-US.json)<br>[**zh-CN(100%)**](/completions/kubectl/language/zh-CN.json)|Kubernetes 又称 K8s，是一个开源系统，用于自动化部署、扩展和管理容器化应用程序。<br> kubectl 是它的命令行工具|
|[link](https://github.com/uutils/coreutils)|[**en-US**](/completions/link/language/en-US.json)<br>[**zh-CN(100%)**](/completions/link/language/zh-CN.json)|调用 link 函数为现有的 FILE1 创建名为 FILE2 的链接。<br> 补全基于 [uutils/coreutils](https://github.com/uutils/coreutils) 编写。|
|[ln](https://github.com/uutils/coreutils)|[**en-US**](/completions/ln/language/en-US.json)<br>[**zh-CN(11.76%)**](/completions/ln/language/zh-CN.json)|Make links between files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[md5sum](https://github.com/uutils/coreutils)|[**en-US**](/completions/md5sum/language/en-US.json)<br>[**zh-CN(14.29%)**](/completions/md5sum/language/zh-CN.json)|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[mktemp](https://github.com/uutils/coreutils)|[**en-US**](/completions/mktemp/language/en-US.json)<br>[**zh-CN(20%)**](/completions/mktemp/language/zh-CN.json)|Create a temporary file or directory.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[ngrok](https://ngrok.com/)|[**en-US**](/completions/ngrok/language/en-US.json)<br>[**zh-CN(100%)**](/completions/ngrok/language/zh-CN.json)|ngrok - 面向开发人员的统一入口平台。<br> 将 localhost 连接到 Internet 以测试应用程序和 API。|
|[nl](https://github.com/uutils/coreutils)|[**en-US**](/completions/nl/language/en-US.json)<br>[**zh-CN(6.67%)**](/completions/nl/language/zh-CN.json)|Number lines of files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[npm](https://www.npmjs.com/)|[**en-US**](/completions/npm/language/en-US.json)<br>[**zh-CN(100%)**](/completions/npm/language/zh-CN.json)|npm - 软件包管理器。|
|[nproc](https://github.com/uutils/coreutils)|[**en-US**](/completions/nproc/language/en-US.json)<br>[**zh-CN(33.33%)**](/completions/nproc/language/zh-CN.json)|Print the number of cores available to the current process.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[nrm](https://github.com/Pana/nrm)|[**en-US**](/completions/nrm/language/en-US.json)<br>[**zh-CN(100%)**](/completions/nrm/language/zh-CN.json)|nrm - npm 镜像源管理。|
|[numfmt](https://github.com/uutils/coreutils)|[**en-US**](/completions/numfmt/language/en-US.json)<br>[**zh-CN(7.69%)**](/completions/numfmt/language/zh-CN.json)|Convert numbers from/to human-readable strings.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[nvm](https://github.com/nvm-sh/nvm)|[**en-US**](/completions/nvm/language/en-US.json)<br>[**zh-CN(100%)**](/completions/nvm/language/zh-CN.json)|nvm - node 版本管理器。|
|[od](https://github.com/uutils/coreutils)|[**en-US**](/completions/od/language/en-US.json)<br>[**zh-CN(4.65%)**](/completions/od/language/zh-CN.json)|Dump files in octal and other formats.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[oh-my-posh](https://ohmyposh.dev)|[**en-US**](/completions/oh-my-posh/language/en-US.json)<br>[**zh-CN(7.41%)**](/completions/oh-my-posh/language/zh-CN.json)|oh-my-posh 是一款跨平台工具，用于渲染你的终端提示符。|
|[paste](https://github.com/uutils/coreutils)|[**en-US**](/completions/paste/language/en-US.json)<br>[**zh-CN(28.57%)**](/completions/paste/language/zh-CN.json)|Write lines consisting of the sequentially corresponding lines from each 'FILE', separated by 'TAB's, to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[pdm](https://github.com/pdm-project/pdm)|[**en-US**](/completions/pdm/language/en-US.json)<br>[**zh-CN(0.31%)**](/completions/pdm/language/zh-CN.json)|A modern Python package and dependency manager supporting the latest PEP standards.|
|[pip](https://github.com/pypa/pip)|[**en-US**](/completions/pip/language/en-US.json)<br>[**zh-CN(99.42%)**](/completions/pip/language/zh-CN.json)|pip - Python 包管理器。|
|[pnpm](https://pnpm.io/zh/)|[**en-US**](/completions/pnpm/language/en-US.json)<br>[**zh-CN(100%)**](/completions/pnpm/language/zh-CN.json)|pnpm - 软件包管理器。|
|[powershell](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh?view=powershell-5.1)|[**en-US**](/completions/powershell/language/en-US.json)<br>[**zh-CN(100%)**](/completions/powershell/language/zh-CN.json)|Windows PowerShell 命令行 CLI. (powershell.exe)|
|[psc](https://github.com/abgox/PSCompletions)|[**en-US**](/completions/psc/language/en-US.json)<br>[**zh-CN(97.55%)**](/completions/psc/language/zh-CN.json)|PSCompletions 模块的补全提示<br> 它只能更新，不能移除<br> 如果移除它，将会自动重新添加|
|[pwsh](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh)|[**en-US**](/completions/pwsh/language/en-US.json)<br>[**zh-CN(100%)**](/completions/pwsh/language/zh-CN.json)|PowerShell 命令行 CLI。(pwsh.exe)|
|[python](https://www.python.org)|[**en-US**](/completions/python/language/en-US.json)<br>[**zh-CN(100%)**](/completions/python/language/zh-CN.json)|python - 命令行。|
|[scoop](https://scoop.sh)|[**en-US**](/completions/scoop/language/en-US.json)<br>[**zh-CN(100%)**](/completions/scoop/language/zh-CN.json)|Scoop - 软件管理|
|[sfsu](https://github.com/winpax/sfsu)|[**en-US**](/completions/sfsu/language/en-US.json)<br>[**zh-CN(6.67%)**](/completions/sfsu/language/zh-CN.json)|Scoop utilities that can replace the slowest parts of Scoop, and run anywhere from 30-100 times faster.|
|[volta](https://volta.sh)|[**en-US**](/completions/volta/language/en-US.json)<br>[**zh-CN(100%)**](/completions/volta/language/zh-CN.json)|volta - 无障碍 JavaScript 工具管理器。|
|[winget](https://github.com/microsoft/winget-cli)|[**en-US**](/completions/winget/language/en-US.json)<br>[**zh-CN(100%)**](/completions/winget/language/zh-CN.json)|WinGet - Windows 程序包管理器。|
|[wsh](https://github.com/wavetermdev/waveterm)|[**en-US**](/completions/wsh/language/en-US.json)<br>[**zh-CN(3.45%)**](/completions/wsh/language/zh-CN.json)|wsh is a small utility that lets you do cool things with Wave Terminal, right from the command line.|
|[wsl](https://github.com/microsoft/WSL)|[**en-US**](/completions/wsl/language/en-US.json)<br>[**zh-CN(100%)**](/completions/wsl/language/zh-CN.json)|WSL - 适用于 Linux 的 Windows 子系统。|
|[wt](https://github.com/microsoft/terminal)|[**en-US**](/completions/wt/language/en-US.json)<br>[**zh-CN(100%)**](/completions/wt/language/zh-CN.json)|Windows Terminal 命令行终端。<br> 你可以使用此命令启动一个终端。|
|[yarn](https://classic.yarnpkg.com/)|[**en-US**](/completions/yarn/language/en-US.json)<br>[**zh-CN(100%)**](/completions/yarn/language/zh-CN.json)|yarn - 软件包管理器。|
|...|...&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|...|
<!-- prettier-ignore-end -->
