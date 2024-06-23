<p align="center">
    <h1 align="center">✨PSCompletions(psc) ✨</h1>
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

-   `PowerShell`: 跨平台的 PowerShell。命令行中运行 `pwsh` 启动

-   `Windows PowerShell`: Windows 系统内置的 PowerShell。命令行中运行 `powershell` 启动

---

-   一个 `PowerShell` 补全管理模块，更好、更简单、更方便的使用和管理补全
    > `Windows PowerShell` 也可以使用此模块，但不建议
-   [集中管理补全](#补全列表 '点击查看可添加补全列表！')
-   `en-US`,`zh-CN`,... 多语言切换
-   动态排序补全候选(根据使用频次)

**如果 PSCompletions 对你有所帮助，请在右上角点个 Star ⭐**

## 安装

1. 打开 `PowerShell`
2. `Install-Module PSCompletions -Scope CurrentUser`
3. `Import-Module PSCompletions`
    - 如果不想每次启动 `PowerShell` 都导入一次，就执行 `echo "Import-Module PSCompletions" >> $PROFILE`

## 卸载

1. 打开 `PowerShell`
2. `Uninstall-Module PSCompletions`

## 使用(以 `git` 补全为例)

### [可用补全列表](#补全列表 '当前可添加的所有补全，更多的补全正在添加中！')

-   如果补全列表里没有你想要的补全，你可以[提交 issues](https://github.com/abgox/PSCompletions/issues '点击提交 issues'), 我会逐步添加

1. `psc add git`
2. 然后你就可以输入 `git`,按下 `Space`(空格键) `Tab` 键来获得命令补全
3. 关于 `psc` 的更多命令，你可以输入 `psc` 然后按下 `Space`(空格键) `Tab` 键触发补全，通过命令提示信息来了解

## Demo

![demo](https://abgop.netlify.app/pscompletions/demo.gif)

## Tips

### 关于补全触发按键

-   模块默认使用 `Tab` 键作为补全触发按键
-   你可以使用 `Set-PSReadLineKeyHandler <key> MenuComplete` 去设置它

### 关于补全更新

-   当打开 `PowerShell` 并导入 `PSCompletions` 后，`PSCompletions` 会开启一个后台作业去检查远程仓库中补全的状态
-   获取到更新后，会在下一次打开 `PowerShell` 并导入 `PSCompletions` 后显示补全更新提示

### 关于补全菜单

-   模块提供的补全菜单基于 [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion) 的实现思路，感谢 [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion) !
-   模块提供的补全菜单只能在 Windows 系统下使用 PowerShell(pwsh) 运行, 其他环境只能使用 PowerShell 自带的补全菜单
-   模块提供的补全菜单中的按键

    1. 应用选中的补全项: `Enter`(回车键)
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

-   补全菜单的所有配置, 你可以输入 `psc menu` 然后按下 `Space`(空格键) `Tab` 键触发补全，通过命令提示信息来了解

### 关于特殊符号

-   😄🤔😎 : 如果出现多个, 表示符合多个条件, 可以选择其中一个的效果

    -   😄 : 表示选用当前选中的补全后, 可以按下 `Space`(空格键) 和 `Tab` 键继续获取补全(普通补全或选项类补全)
        -   可通过 `psc menu symbol SpaceTab <symbol>` 自定义此符号
        -   如: `psc menu symbol SpaceTab ""` 设置为空字符串
    -   🤔 : 表示选用当前选中的选项类补全后, 你可以按下 `Space`(空格键) 和 `Tab` 键继续获取剩余选项类补全(如 --verbose)
        -   可通过 `psc menu symbol OptionTab <symbol>` 自定义此符号
    -   😎 : 表示选用当前选中的选项类补全后, 你可以按下 `Space`(空格键), 再输入一个字符串, 然后按下 `Space`(空格键) 和 `Tab` 键继续获取剩余选项类补全

        -   如果字符串有空格, 请使用 "" 或 '' 包裹，如 "test content"
        -   如果同时还有 😄, 表示有几个预设的字符串可以补全, 你可以不输入字符串, 直接按下 `Space`(空格键) 和 `Tab` 键继续获取补全
        -   可通过 `psc menu symbol WriteSpaceTab <symbol>` 自定义此符号

    -   如果存在通用选项类补全, 也可以触发通用选项的补全
    -   所有补全都可以在输入部分后按下 `Tab` 键触发补全
    -   如果你不需要也不想看到这些符号, 可以将它们替换成空字符串。如: `psc menu symbol SpaceTab ""`

-   使用 PowerShell 语言自带的补全菜单时, 如果 `...` 是最后一个补全, 则表示可显示区域过小, 无法显示所有候选项
-   使用模块提供的补全菜单时, 如果补全提示信息末尾出现 `...`, 则表示当前显示区域宽度不够, 提示信息显示不完整

### 关于语言

-   `Global language`: 默认为当前的系统语言
    -   `psc config language` 可以查看全局的语言配置
    -   `psc config language zh-CN` 可以更改全局的语言配置
-   `Completion language`: 为指定的补全设置的语言
    -   e.g. `psc completion git language en-US`
-   `Available language`: 每一个补全的 `config.json` 文件中有一个 `language` 属性，它的值是一个可用的语言列表

#### 确定语言

1. 确定指定的语言: 如果有 `Completion language`，优先使用它，没有则使用 `Global language`
2. 确定最终使用的语言:
    - 判断第一步确定的值是否存在于 `Available language` 中
    - 如果存在，则使用它
    - 如果不存在，直接使用 `Available language` 中的第一种语言(一般为 `en-US`)

### 关于路径补全

-   以 `git` 为例，当输入 `git add`，此时按下 `Space` 和 `Tab` 键，不会触发路径补全，只会触发模块提供的命令补全
-   如果你希望触发路径补全，你需要输入内容
-   只要输入的内容符合这个正则 `^\.*[\\/].*`，都会去获取路径补全，这是 PowerShell 的补全，与模块无关
-   比如:

    -   输入 `./` 或 `.\` 后按下 `Tab` 以获取 **子目录** 或 **文件** 的路径补全
    -   输入 `../` 或 `..\` 后按下 `Tab` 以获取 **父级目录** 或 **文件** 的路径补全
    -   输入 `/` 或 `\` 后按下 `Tab` 以获取 **同级目录** 的路径补全

-   因此，你应该输入 `git add ./` 这样的命令再按下 `Tab` 键来获取路径补全

## 补全列表

-   说明
    -   **`Completion`** ：可添加的补全。点击跳转命令官方网站，按照数字字母排序(0-9,a-z)。
        -   特殊情况: `abc(a)`，这表示你需要通过 `psc add abc` 去下载它，但默认使用 `a` 而不是 `abc` 去触发补全
    -   **`Language`**: 支持的语言，以及翻译进度
        -   翻译进度是相较于 `en-US` 的
            -   如果翻译进度大于 `100%`，则表示当前语言有一部分多余的补全项，应该被清理
    -   **`Description`**: 命令描述

|Completion|Language|Description|
|:-:|-|-|
|[7z](https://7-zip.org/)|**en-US**<br>**zh-CN(100%)**|7-Zip 的命令行 cli 程序|
|[arch](https://github.com/uutils/coreutils)|**en-US**<br>**zh-CN(100%)**|显示当前系统架构。<br> 来源于 [uutils/coreutils](https://github.com/uutils/coreutils)|
|[b2sum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(15.38%)~~**|Compute and check message digests.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[b3sum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(15.38%)~~**|Compute and check message digests.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[base32](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Encode/decode data and print to standard output.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[base64](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Encode/decode data and print to standard output.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[basename](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Print NAME with any leading directory components removed.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[basenc](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(18.18%)~~**|Encode/decode data and print to standard output.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[bun](https://bun.sh)|**en-US**<br>**zh-CN(100%)**|Bun - JavaScript 运行时和工具包|
|[cargo](https://rustwiki.org/zh-CN/cargo/)|**en-US**<br>**zh-CN(100%)**|cargo - Rust 包管理器|
|[chfs](http://iscute.cn/chfs)|**en-US**<br>**zh-CN(100%)**|CuteHttpFileServer - 一个免费的、HTTP协议的文件共享服务器|
|[choco](https://chocolatey.org/)|**en-US**<br>**zh-CN(100%)**|choco(chocolatey) - 软件管理|
|[cksum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(17.14%)~~**|Print CRC and size for each file.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[comm](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(27.27%)~~**|Compare two sorted files line by line.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[conda](https://github.com/conda/conda)|**en-US**<br>**zh-CN(100%)**|conda - 二进制包和环境管理器|
|[csplit](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(19.35%)~~**|Split a file into sections determined by context lines.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[cut](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(16.22%)~~**|Print specified byte or field columns from each line of stdin or the input files.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[date](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(14.29%)~~**|Print or set the system date and time.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[dd](https://github.com/uutils/coreutils)|**en-US**<br>**zh-CN(100%)**|复制并转换文件系统资源。<br> 来源于 [uutils/coreutils](https://github.com/uutils/coreutils)|
|[deno](https://deno.com/)|**en-US**<br>**zh-CN(100%)**|Deno - 安全的 JavaScript 和 TypeScript 运行时|
|[df](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(6.67%)~~**|Show information about the file system on which each FILE resides, or all file systems by default.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[dircolors](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(31.58%)~~**|Output commands to set the LS_COLORS environment variable.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[dirname](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(54.55%)~~**|Strip last component from file name.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[docker](https://www.docker.com)|**en-US**<br>**zh-CN(100%)**|docker - 容器应用开发|
|[du](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(6%)~~**|Estimate file space usage.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[env](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(16.67%)~~**|Set each NAME to VALUE in the environment and run COMMAND.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[factor](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(60%)~~**|Print the prime factors of the given NUMBER(s).<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[fmt](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(14.63%)~~**|Reformat paragraphs from input files (or stdin) to stdout.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[fnm](https://github.com/Schniz/fnm)|**en-US**<br>**~~zh-CN(14.52%)~~**|快速、简单的 Node.js 版本管理器，使用 Rust 构建|
|[fold](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Writes each file (or standard input if no files are given) to standard output whilst breaking long lines.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[git](https://git-scm.com)|**en-US**<br>**zh-CN(100%)**|Git - 版本控制系统|
|[hashsum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(8.57%)~~**|Compute and check message digests.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[head](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(24%)~~**|Print the first 10 lines of each 'FILE' to standard output.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[join](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(13.04%)~~**|For each pair of input lines with identical join fields, write a line to standard output.<br> The default join field is the first, delimited by blanks.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[kubectl](https://kubernetes.io/zh-cn/docs/reference/kubectl/)|**en-US**<br>**zh-CN(100%)**|Kubernetes 又称 K8s，是一个开源系统，用于自动化部署、扩展和管理容器化应用程序。<br> kubectl 是它的命令行工具|
|[link](https://github.com/uutils/coreutils)|**en-US**<br>**zh-CN(100%)**|调用 link 函数为现有的 FILE1 创建名为 FILE2 的链接。<br> 来源于 [uutils/coreutils](https://github.com/uutils/coreutils)|
|[ln](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(14.63%)~~**|Make links between files.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[md5sum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(17.14%)~~**|Compute and check message digests.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[mktemp](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(24%)~~**|Create a temporary file or directory.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[ngrok](https://ngrok.com/)|**en-US**<br>**zh-CN(100%)**|ngrok - 面向开发人员的统一入口平台。<br> 将 localhost 连接到 Internet 以测试应用程序和 API。|
|[nl](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(6.58%)~~**|Number lines of files.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[npm](https://www.npmjs.com/)|**en-US**<br>**zh-CN(100%)**|npm - 软件包管理器|
|[nproc](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(46.15%)~~**|Print the number of cores available to the current process.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[nrm](https://github.com/Pana/nrm)|**en-US**<br>**zh-CN(100%)**|nrm - npm 镜像源管理|
|[numfmt](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(8.57%)~~**|Convert numbers from/to human-readable strings.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[nvm](https://github.com/nvm-sh/nvm)|**en-US**<br>**zh-CN(100%)**|nvm - node 版本管理器|
|[od](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(7.41%)~~**|Dump files in octal and other formats.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[paste](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Write lines consisting of the sequentially corresponding lines from each 'FILE', separated by 'TAB's, to standard output.<br> Come from [uutils/coreutils](https://github.com/uutils/coreutils)|
|[pip](https://github.com/pypa/pip)|**en-US**<br>**zh-CN(100%)**|pip - Python 包管理器|
|[pnpm](https://pnpm.io/zh/)|**en-US**<br>**zh-CN(100%)**|pnpm - 软件包管理器|
|[psc](https://github.com/abgox/PSCompletions)|**en-US**<br>**zh-CN(100%)**|PSCompletions 模块的补全提示<br> 它只能更新，不能移除<br> 如果移除它，将会自动重新添加|
|[python](https://www.python.org)|**en-US**<br>**zh-CN(100%)**|python - 命令行|
|[scoop](https://scoop.sh)|**en-US**<br>**zh-CN(100%)**|Scoop - 软件管理|
|[volta](https://volta.sh)|**en-US**<br>**zh-CN(100%)**|volta - 无障碍 JavaScript 工具管理器|
|[winget](https://github.com/microsoft/winget-cli)|**en-US**<br>**zh-CN(100%)**|WinGet - Windows 程序包管理器|
|[wsl](https://github.com/microsoft/WSL)|**en-US**<br>**zh-CN(100%)**|WSL - 适用于 Linux 的 Windows 子系统|
|[wt](https://github.com/microsoft/terminal)|**en-US**<br>**zh-CN(100%)**|Windows Terminal 命令行终端。<br> 你可以使用此命令启动一个终端。|
|[yarn](https://classic.yarnpkg.com/)|**en-US**<br>**zh-CN(100%)**|yarn - 软件包管理器|
|...|...&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|...|
