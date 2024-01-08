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

-   一个 `PowerShell` 补全管理模块，更好、更简单、更方便的使用和管理补全
    > `Windows PowerShell` 也可以使用此模块，但更建议使用 `PowerShell`
-   [集中管理补全](#补全列表 "点击查看可添加补全列表！")
-   `zh-CN`，`en-US` 多语言切换
-   动态排序补全候选(根据使用频次)

> -   补全信息可自定义(但不太建议)
>     -   通过修改补全`json`文件实现
>     -   `psc which <completion>` 获取补全文件路径
>     -   建议只修改补全提示信息，避免出现不小心的修改导致整个补全失败
>     -   如果出现补全问题,请使用 `psc update <completion>` 更新覆盖

**如果 PSCompletions 对你有所帮助，请在右上角点个 Star ⭐**

## 安装

1. 打开 `PowerShell`
2. `Install-Module PSCompletions`
3. `Import-Module PSCompletions`
    - 如果不想每次启动 `PowerShell` 都导入一次，就执行 `echo "Import-Module PSCompletions" >> $PROFILE`

## 卸载

-   `Uninstall-Module PSCompletions`

## 使用(以 `git` 补全为例)

### [可用补全列表](#补全列表 "当前可添加的所有补全，更多的补全正在添加中！")

-   如果补全列表里没有你想要的补全，你可以[提交 issues](https://github.com/abgox/PSCompletions/issues "点击提交 issues"), 我会逐步添加

1. `psc add git`
2. 然后你就可以输入`git `,按下 `Space`(空格键) `Tab` 来获得命令补全
3. 关于`psc`的更多命令，你可以通过输入`psc`然后按下 `Space`(空格键) `Tab`来了解

## Demo

![demo](https://abgop.netlify.app/pscompletions/demo.gif)

## Tips

### 关于补全更新

-   当打开`PowerShell` 并导入 `PSCompletions` 后，`PSCompletions` 会开启一个后台作业去检查远程仓库中补全的状态
-   获取到更新后，会在下一次显示补全更新提示

### 关于补全菜单 UI

-   模块的补全菜单 UI 基于 [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion) 修改而来
-   模块自 3.0.0 版本起，默认使用本模块自带的补全菜单 UI
    > 由于 UI 在 Windows PowerShell 上不稳定，Windows PowerShell 将继续使用语言自带的补全菜单
    -   如果你喜欢语言自带的补全菜单，运行 `psc ui theme powershell` 即可
-   你可以通过 `psc ui` 下的命令来更改补全菜单 UI 的一些样式及配置

### 关于补全描述中的特殊符号

-   对于 😄😎🤔: 如果出现多个，可以选择其中一个的效果
-   😄：表示选用此补全后，可以按下 `Space`(空格键) 和 `Tab` 键继续获得补全候选

    -   可通过 `psc config symbol SpaceTab <symbol>` 自定义此符号

-   😎：表示选用此补全后，你可以输入一个不带空格的字符串，然后按下 `Space`(空格键) 和 `Tab` 键继续获得补全候选

    -   可通过 `psc config symbol WriteSpaceTab <symbol>` 自定义此符号

-   🤔：表示选用此补全后，你可以按下 `Space`(空格键) 和 `Tab` 键继续获取选项类补全候选(如 --verbose)

    -   可通过 `psc config symbol OptionsTab <symbol>` 自定义此符号

-   `...`：补全描述等待后续填充
    -   如果 `...` 是最后一个补全候选，则表示可显示区域过小，无法显示所有候选项

### 关于路径补全

-   输入 `./` 或 `.\` 后按下 `Tab` 以获取 **子目录** 或 **文件** 的路径补全
-   输入 `/` 或 `\` 后按下 `Tab` 以获取 **同级目录** 的路径补全

## 补全列表

|                  命令补全                   |                                      命令来源                                      |
| :-----------------------------------------: | :--------------------------------------------------------------------------------: |
| [PSCompletions](/completions/PSCompletions) | [PSCompletions 模块补全](https://www.powershellgallery.com/packages/PSCompletions) |
|          [chfs](/completions/chfs)          |         [CuteHttpFileServer - 跨平台文件共享服务器](http://iscute.cn/chfs)         |
|         [choco](/completions/choco)         |               [choco(chocolatey) - 软件管理](https://chocolatey.org)               |
|          [deno](/completions/deno)          |                 [deno - 安全的 JS 和 TS 运行时](https://deno.com)                  |
|        [docker](/completions/docker)        |                  [docker - 容器应用开发](https://www.docker.com)                   |
|           [git](/completions/git)           |                     [Git - 版本控制系统](https://git-scm.com)                      |
|       [kubectl](/completions/kubectl)       |             [Kubernetes(k8s) 命令行工具](https://kubernetes.io/zh-cn)              |
|           [npm](/completions/npm)           |                    [npm - 软件包管理器](https://www.npmjs.com)                     |
|           [nrm](/completions/nrm)           |                [nrm - npm 镜像源管理](https://github.com/Pana/nrm)                 |
|           [nvm](/completions/nvm)           |               [nvm - node 版本管理器](https://github.com/nvm-sh/nvm)               |
|           [pip](/completions/pip)           |                [pip - Python 包管理器](https://github.com/pypa/pip)                |
|          [pnpm](/completions/pnpm)          |                     [pnpm - 软件包管理器](https://www.pnpm.cn)                     |
|        [python](/completions/python)        |                     [python - 命令行](https://www.python.org)                      |
|         [scoop](/completions/scoop)         |                        [Scoop - 软件管理](https://scoop.sh)                        |
|         [volta](/completions/volta)         |              [volta - 无障碍 JavaScript 工具管理器](https://volta.sh)              |
|        [winget](/completions/winget)        |      [WinGet - Windows 程序包管理器](https://github.com/microsoft/winget-cli)      |
|           [wsl](/completions/wsl)           |      [WSL - 适用于 Linux 的 Windows 子系统](https://github.com/microsoft/WSL)      |
|            [wt](/completions/wt)            |        [windows terminal 命令行终端](https://github.com/microsoft/terminal)        |
|          [yarn](/completions/yarn)          |               [yarn - 软件包管理器](https://classic.yarnpkg.com/en)                |
|                     ...                     |                                        ...                                         |
