<p align="center">
    <h1 align="center">✨<a href="https://pscompletions.pages.dev">PSCompletions(psc)</a>✨</h1>
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

- [`PowerShell`](https://github.com/PowerShell/PowerShell): 跨平台的 PowerShell。运行 `pwsh`/`pwsh.exe` 启动

- [`Windows PowerShell`](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell): Windows 系统内置的 PowerShell。运行 `powershell`/`powershell.exe` 启动

---

- 一个 `PowerShell` 补全管理模块，更好、更简单、更方便的使用和管理补全
  > `Windows PowerShell` 也可以使用此模块，但更推荐使用 `PowerShell`
- [集中管理补全](#补全列表 "点击查看可添加补全列表！")
- `en-US`,`zh-CN`,... 多语言切换
- 动态排序补全项(根据使用频次)
- [提供了一个更强大的补全菜单](#关于补全菜单 "点击查看相关详情")
- [与 argc-completions 结合使用](https://pscompletions.pages.dev/tips/pscompletions-and-argc-completions "点击查看如何实现")
  - [argc-completions 仓库](https://github.com/sigoden/argc-completions)

**如果 `PSCompletions` 对你有所帮助，请在此项目点个 Star ⭐**

## 新的变化

- 请查阅 [更新日志](./module/CHANGELOG-CN.md)

## 常见问题

- 请查阅 [常见问题](https://pscompletions.pages.dev/FAQ)

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
   - 如果不想每次启动 `PowerShell` 都需要导入 `PSCompletions` 模块，你可以将导入语句写入 `$PROFILE` 中
   ```powershell
   echo "Import-Module PSCompletions" >> $PROFILE
   ```

> [!warning]
>
> - 不能再使用 `Set-PSReadLineKeyHandler -Key <key> -Function MenuComplete` 了，它会导致 `PSCompletions` 菜单无法正常工作
> - 详细配置请参考 [关于补全触发按键](#关于补全触发按键)

## 卸载

1. 打开 `PowerShell`
2. 卸载模块:
   ```powershell
   Uninstall-Module PSCompletions
   ```

## 使用

### [可用补全列表](#补全列表 "当前可添加的所有补全，更多的补全正在添加中！")

> 如果补全列表里没有你想要的补全，你可以 [提交 issues](https://github.com/abgox/PSCompletions/issues "点击提交 issues")

- 以 `git` 补全为例

1. `psc add git`
2. 然后你就可以输入 `git`, 按下 `Space`(空格键) `Tab` 键来获得命令补全
3. 关于 `psc` 的更多命令用法，你只需要输入 `psc` 然后按下 `Space`(空格键) `Tab` 键触发补全，通过 [补全提示信息](#关于补全提示信息) 来了解

## Demo

![demo](https://pscompletions.pages.dev/demo-CN.gif)

## 贡献

- 请查阅 [CONTRIBUTING](./.github/contributing.md)

## Tips

### 关于补全触发按键

- 模块默认使用 `Tab` 键作为补全菜单触发按键
- 你可以使用 `psc menu config trigger_key <key>` 去设置它

> [!warning]
>
> - 不能再使用 `Set-PSReadLineKeyHandler -Key <key> -Function MenuComplete` 了，它会导致 `PSCompletions` 菜单无法正常工作
>
> ```diff
>
> + Import-Module PSCompletions
>
> - Set-PSReadLineKeyHandler -Key <key> -Function MenuComplete
> ```

### 关于补全更新

- 当打开 `PowerShell` 并导入 `PSCompletions` 模块后，`PSCompletions` 会开启一个后台作业去检查远程仓库中补全的状态
- 获取到更新后，会在下一次打开 `PowerShell` 并导入 `PSCompletions` 后显示补全更新提示

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

  1. 选用当前选中的补全项: `Enter`(回车键)
     - 当只有一个补全项时，也可以使用 `Tab` 或 `Space`(空格) 键
  2. 删除过滤字符: `Backspace`(退格键)
  3. 退出补全菜单: `ESC` / `Ctrl + c`
     - 当过滤区域没有字符时，也可以使用 `Backspace`(退格键) 退出补全菜单
  4. 选择补全项:

     |   选择上一项    | 选择下一项 |
     | :-------------: | :--------: |
     |      `Up`       |   `Down`   |
     |     `Left`      |  `Right`   |
     |  `Shift + Tab`  |   `Tab`    |
     | `Shift + Space` |  `Space`   |
     |   `Ctrl + u`    | `Ctrl + d` |
     |   `Ctrl + p`    | `Ctrl + n` |

- 补全菜单的所有配置, 你可以输入 `psc menu` 然后按下 `Space`(空格键) `Tab` 键触发补全，通过 [补全提示信息](#关于补全提示信息) 来了解
  - 对于配置的值，`1` 表示 `true`，`0` 表示 `false` (这适用于 `PSCompletions` 的所有配置)

#### 关于菜单增强 <img src="https://img.shields.io/badge/module%20version-v4.2.0+-4CAF50" alt="v4.2.0+ support" />

- 配置: `psc menu config enable_menu_enhance 1` 默认开启
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
         - [与 argc-completions 结合使用](https://pscompletions.pages.dev/tips/pscompletions-and-argc-completions)
         - 由 cli 或模块注册的补全
         - ...

### 关于特殊符号

> [!NOTE]
>
> - 由于未来的 Windows Terminal 的变化，将导致在补全菜单中无法正常显示 😄🤔😎，因此这三个默认特殊符号将改变。
> - 相关的 issue: https://github.com/microsoft/terminal/issues/18242
> - 变化如下:
>   - `😄` => `»`
>   - `🤔` => `?`
>   - `😎` => `!`

- 补全项后面的特殊符号用于在按下 `Tab` 键之前提前感知是否有可用的补全项

  - 这些符号目前只在通过 `psc add` 添加的补全中存在

  - 你可以将它们替换成空字符串来隐藏它们
    - `psc menu symbol SpaceTab ""`
    - `psc menu symbol OptionTab ""`
    - `psc menu symbol WriteSpaceTab ""`

- `»`,`?`,`!` : 如果出现多个, 表示符合多个条件, 可以选择其中一个效果

  - 定义:
    - `Normal Completion`: 子命令，例如在 `git` 中的 `add`/`pull`/`push`/`commit`/...
    - `Optional Completion`: 可选参数，例如在 `git add` 中的 `-g`/`-u`/...
    - `General Optional Completion`: 可以用在任何地方的通用可选参数，例如在 `git` 中的 `--help`/...
  - `»` : 表示选用当前选中的补全后, 可以按下 `Space`(空格键) 和 `Tab` 键继续获取 `Normal Completion` 或者 `Optional Completion`
    - 仅在有 `Normal Completion` 或 `Optional Completion` 时才会显示此符号
    - 可通过 `psc menu symbol SpaceTab <symbol>` 自定义此符号
  - `?` : 表示选用当前选中的补全(`Optional Completion`)后, 你可以按下 `Space`(空格键) 和 `Tab` 键继续获取其他的 `Optional Completion`
    - `General Optional Completion` 也使用此符号
    - 可通过 `psc menu symbol OptionTab <symbol>` 自定义此符号
  - `!` : 表示选用当前选中的补全(`Optional Completion` 或者 `General Optional Completion`)后, 你可以按下 `Space`(空格键), 再输入一个字符串, 然后按下 `Space`(空格键) 和 `Tab` 键继续获取其他的 `Optional Completion` 或者 `General Optional Completion`

    - 如果字符串有空格, 请使用 `"`(引号) 或 `'`(单引号) 包裹，如 `"test content"`
    - 如果同时还有 `»`, 表示有几个预设的字符串(`Normal Completion`)可以补全, 你可以不输入字符串, 直接按下 `Space`(空格键) 和 `Tab` 键继续获取它们
    - 可通过 `psc menu symbol WriteSpaceTab <symbol>` 自定义此符号

  - 所有补全都可以在输入部分字符后按下 `Tab` 键触发补全

### 关于补全提示信息

- 补全提示信息只是辅助, 你也可以使用 `psc menu config enable_tip 0` 来禁用补全提示信息

  - 启用补全提示信息: `psc menu config enable_tip 1`
  - 也可以禁用特定补全的提示信息，如 `psc`
    - `psc completion psc enable_tip 0`

- 补全提示信息一般由三部分组成: 用法(Usage) + 描述(Description) + 举例(Example)
  ```txt
  U: install|add [-g|-u] [options] <app>
  这里是命令的描述说明
  在 U: 和 E: 之间的内容都是命令描述
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

## 赞赏支持

![赞赏支持](https://abgox.pages.dev/support.png)

## 补全列表

- 说明
  - **`Completion`** ：可添加的补全。点击跳转命令官方网站，按照数字字母排序(0-9,a-z)。
    - 特殊情况: `abc(a)`，这表示你需要通过 `psc add abc` 去下载它，但默认使用 `a` 而不是 `abc` 去触发补全
  - **`Language`**: 支持的语言，以及翻译进度
    - 翻译进度是相较于 `en-US` 的
  - **`Description`**: 命令描述

<!-- prettier-ignore-start -->
|Completion|Language|Description|
|:-:|-|-|
|[7z](https://7-zip.org/)|**en-US**<br>**zh-CN(100%)**|7-Zip 的命令行 cli 程序|
|[arch](https://github.com/uutils/coreutils)|**en-US**<br>**zh-CN(100%)**|显示当前系统架构。<br> 补全基于 [uutils/coreutils](https://github.com/uutils/coreutils) 编写。|
|[b2sum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(15.38%)~~**|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[b3sum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(15.38%)~~**|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[base32](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[base64](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[basename](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Print NAME with any leading directory components removed.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[basenc](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(18.18%)~~**|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[bun](https://bun.sh)|**en-US**<br>**zh-CN(100%)**|Bun - JavaScript 运行时和工具包|
|[cargo](https://rustwiki.org/zh-CN/cargo/)|**en-US**<br>**zh-CN(100%)**|cargo - Rust 包管理器|
|[chfs](http://iscute.cn/chfs)|**en-US**<br>**zh-CN(100%)**|CuteHttpFileServer - 一个免费的、HTTP协议的文件共享服务器|
|[choco](https://chocolatey.org/)|**en-US**<br>**zh-CN(100%)**|choco(chocolatey) - 软件管理|
|[cksum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(17.14%)~~**|Print CRC and size for each file.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[comm](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(27.27%)~~**|Compare two sorted files line by line.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[conda](https://github.com/conda/conda)|**en-US**<br>**zh-CN(100%)**|conda - 二进制包和环境管理器|
|[csplit](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(19.35%)~~**|Split a file into sections determined by context lines.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[cut](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(16.22%)~~**|Print specified byte or field columns from each line of stdin or the input files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[date](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(14.29%)~~**|Print or set the system date and time.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[dd](https://github.com/uutils/coreutils)|**en-US**<br>**zh-CN(100%)**|复制并转换文件系统资源。<br> 补全基于 [uutils/coreutils](https://github.com/uutils/coreutils) 编写。|
|[deno](https://deno.com/)|**en-US**<br>**zh-CN(100%)**|Deno - 安全的 JavaScript 和 TypeScript 运行时|
|[df](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(6.67%)~~**|Show information about the file system on which each FILE resides, or all file systems by default.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[dircolors](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(31.58%)~~**|Output commands to set the LS_COLORS environment variable.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[dirname](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(54.55%)~~**|Strip last component from file name.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[docker](https://www.docker.com)|**en-US**<br>**zh-CN(100%)**|docker - 容器应用开发|
|[du](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(5.83%)~~**|Estimate file space usage.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[env](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(16.67%)~~**|Set each NAME to VALUE in the environment and run COMMAND.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[factor](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(60%)~~**|Print the prime factors of the given NUMBER(s).<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[fmt](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(14.63%)~~**|Reformat paragraphs from input files (or stdin) to stdout.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[fnm](https://github.com/Schniz/fnm)|**en-US**<br>**~~zh-CN(14.52%)~~**|快速、简单的 Node.js 版本管理器，使用 Rust 构建|
|[fold](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Writes each file (or standard input if no files are given) to standard output whilst breaking long lines.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[git](https://git-scm.com)|**en-US**<br>**zh-CN(100%)**|Git - 版本控制系统|
|[hashsum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(8.57%)~~**|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[head](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(24%)~~**|Print the first 10 lines of each 'FILE' to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[join](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(13.04%)~~**|For each pair of input lines with identical join fields, write a line to standard output.<br> The default join field is the first, delimited by blanks.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[kubectl](https://kubernetes.io/zh-cn/docs/reference/kubectl/)|**en-US**<br>**zh-CN(100%)**|Kubernetes 又称 K8s，是一个开源系统，用于自动化部署、扩展和管理容器化应用程序。<br> kubectl 是它的命令行工具|
|[link](https://github.com/uutils/coreutils)|**en-US**<br>**zh-CN(100%)**|调用 link 函数为现有的 FILE1 创建名为 FILE2 的链接。<br> 补全基于 [uutils/coreutils](https://github.com/uutils/coreutils) 编写。|
|[ln](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(14.63%)~~**|Make links between files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[md5sum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(17.14%)~~**|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[mktemp](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(24%)~~**|Create a temporary file or directory.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[ngrok](https://ngrok.com/)|**en-US**<br>**zh-CN(100%)**|ngrok - 面向开发人员的统一入口平台。<br> 将 localhost 连接到 Internet 以测试应用程序和 API。|
|[nl](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(6.58%)~~**|Number lines of files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[npm](https://www.npmjs.com/)|**en-US**<br>**zh-CN(100%)**|npm - 软件包管理器|
|[nproc](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(46.15%)~~**|Print the number of cores available to the current process.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[nrm](https://github.com/Pana/nrm)|**en-US**<br>**zh-CN(100%)**|nrm - npm 镜像源管理|
|[numfmt](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(8.57%)~~**|Convert numbers from/to human-readable strings.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[nvm](https://github.com/nvm-sh/nvm)|**en-US**<br>**zh-CN(100%)**|nvm - node 版本管理器|
|[od](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(7.41%)~~**|Dump files in octal and other formats.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[paste](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Write lines consisting of the sequentially corresponding lines from each 'FILE', separated by 'TAB's, to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[pdm](https://github.com/pdm-project/pdm)|**en-US**<br>**~~zh-CN(0.82%)~~**|A modern Python package and dependency manager supporting the latest PEP standards|
|[pip](https://github.com/pypa/pip)|**en-US**<br>**zh-CN(100%)**|pip - Python 包管理器|
|[pnpm](https://pnpm.io/zh/)|**en-US**<br>**zh-CN(100%)**|pnpm - 软件包管理器|
|[powershell](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh?view=powershell-5.1)|**en-US**<br>**zh-CN(100%)**|Windows PowerShell 命令行 CLI. (powershell.exe)|
|[psc](https://github.com/abgox/PSCompletions)|**en-US**<br>**zh-CN(100%)**|PSCompletions 模块的补全提示<br> 它只能更新，不能移除<br> 如果移除它，将会自动重新添加|
|[pwsh](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh)|**en-US**<br>**zh-CN(100%)**|PowerShell 命令行 CLI。(pwsh.exe)|
|[python](https://www.python.org)|**en-US**<br>**zh-CN(100%)**|python - 命令行|
|[scoop](https://scoop.sh)|**en-US**<br>**zh-CN(100%)**|Scoop - 软件管理|
|[sfsu](https://github.com/winpax/sfsu)|**en-US**<br>**~~zh-CN(10.77%)~~**|Scoop utilities that can replace the slowest parts of Scoop, and run anywhere from 30-100 times faster|
|[volta](https://volta.sh)|**en-US**<br>**zh-CN(100%)**|volta - 无障碍 JavaScript 工具管理器|
|[winget](https://github.com/microsoft/winget-cli)|**en-US**<br>**zh-CN(100%)**|WinGet - Windows 程序包管理器|
|[wsl](https://github.com/microsoft/WSL)|**en-US**<br>**zh-CN(100%)**|WSL - 适用于 Linux 的 Windows 子系统|
|[wt](https://github.com/microsoft/terminal)|**en-US**<br>**zh-CN(100%)**|Windows Terminal 命令行终端。<br> 你可以使用此命令启动一个终端。|
|[yarn](https://classic.yarnpkg.com/)|**en-US**<br>**zh-CN(100%)**|yarn - 软件包管理器|
|...|...&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|...|
<!-- prettier-ignore-end -->
