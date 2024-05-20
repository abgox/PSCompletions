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
-   `zh-CN`，`en-US`，... 多语言切换
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
    -   😎 : 表示选用当前选中的选项类补全后, 你可以输入一个字符串, 然后按下 `Space`(空格键) 和 `Tab` 键继续获取剩余选项类补全

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

|            命令补全             |                                       命令来源                                       |
| :-----------------------------: | :----------------------------------------------------------------------------------: |
|     [psc](/completions/psc)     | [psc - PSCompletions 模块](https://www.powershellgallery.com/packages/PSCompletions) |
|     [bun](/completions/bun)     |                  [Bun - JavaScript 运行时和工具包](https://bun.sh)                   |
|   [cargo](/completions/cargo)   |              [cargo - Rust 包管理器](https://rustwiki.org/zh-CN/cargo)               |
|    [chfs](/completions/chfs)    |          [CuteHttpFileServer - 跨平台文件共享服务器](http://iscute.cn/chfs)          |
|   [choco](/completions/choco)   |                [choco(chocolatey) - 软件管理](https://chocolatey.org)                |
|   [conda](/completions/conda)   |            [conda - 二进制包和环境管理器](https://github.com/conda/conda)            |
|    [deno](/completions/deno)    |                  [deno - 安全的 JS 和 TS 运行时](https://deno.com)                   |
|  [docker](/completions/docker)  |                   [docker - 容器应用开发](https://www.docker.com)                    |
|     [git](/completions/git)     |                      [Git - 版本控制系统](https://git-scm.com)                       |
| [kubectl](/completions/kubectl) |              [Kubernetes(k8s) 命令行工具](https://kubernetes.io/zh-cn)               |
|     [npm](/completions/npm)     |                     [npm - 软件包管理器](https://www.npmjs.com)                      |
|     [nrm](/completions/nrm)     |                 [nrm - npm 镜像源管理](https://github.com/Pana/nrm)                  |
|     [nvm](/completions/nvm)     |                [nvm - node 版本管理器](https://github.com/nvm-sh/nvm)                |
|     [pip](/completions/pip)     |                 [pip - Python 包管理器](https://github.com/pypa/pip)                 |
|    [pnpm](/completions/pnpm)    |                      [pnpm - 软件包管理器](https://www.pnpm.cn)                      |
|  [python](/completions/python)  |                      [python - 命令行](https://www.python.org)                       |
|   [scoop](/completions/scoop)   |                         [Scoop - 软件管理](https://scoop.sh)                         |
|   [volta](/completions/volta)   |               [volta - 无障碍 JavaScript 工具管理器](https://volta.sh)               |
|  [winget](/completions/winget)  |       [WinGet - Windows 程序包管理器](https://github.com/microsoft/winget-cli)       |
|     [wsl](/completions/wsl)     |       [WSL - 适用于 Linux 的 Windows 子系统](https://github.com/microsoft/WSL)       |
|      [wt](/completions/wt)      |         [windows terminal 命令行终端](https://github.com/microsoft/terminal)         |
|    [yarn](/completions/yarn)    |                [yarn - 软件包管理器](https://classic.yarnpkg.com/en)                 |
|               ...               |                                         ...                                          |
