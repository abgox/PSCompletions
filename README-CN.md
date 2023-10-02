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
        <img src="https://img.shields.io/github/repo-size/abgox/PSCompletions.svg" alt="code size" />
    </a>
    <a href="https://github.com/abgox/PSCompletions">
        <img src="https://img.shields.io/badge/created-2023--8--15-blue" alt="created" />
    </a>
</p>

---

## 介绍

-   一个 `PowerShell` 补全管理模块，更好、更简单、更方便的使用和管理补全
    >  `WindowsPowerShell` 也可以使用此模块
-   [集中管理补全](#补全列表 "点击查看可添加补全列表！")
-   `zh-CN`，`en-US` 多语言切换
-   动态排序补全候选(根据使用频次)
-   补全内容可自定义
    -   通过修改补全`json`文件实现
    >-   建议只修改补全提示信息，避免出现不小心的修改导致整个补全失败
    >-   如果你已修改，请不要使用`psc update`，避免有更新时，你的自定义被覆盖
    >-   如果出现问题,请使用 `psc update <completion>` 更新覆盖
    -   `psc which <completion>` 获取补全文件路径

**如果 PSCompletions 对你有所帮助，请在右上角点个 Star ⭐ 支持一下**

## 安装

1. 打开 `PowerShell`
2. `Install-Module PSCompletions`
3. `Import-Module PSCompletions`
    - 如果不想每次启动终端都导入一次，就执行 `echo "Import-Module PSCompletions" >> $PROFILE`

## 使用(以 `git` 补全为例)

### [可用补全列表](#补全列表 "当前可添加的所有补全，更多的补全正在添加中！")

-   如果补全列表里没有你想要的补全，你可以[提交 issues](https://github.com/abgox/PSCompletions/issues "点击提交 issues"), 我会逐步添加

1. `psc add git`
2. 然后你就可以输入`git ` 按下`Tab` 来获得命令补全
3. 关于`psc`的更多命令，你可以通过输入`psc`然后按下`Tab`来了解

## 卸载

-   `Uninstall-Module PSCompletions`

## Demo

![PSCompletions-demo.gif](demo.gif)

### 关于补全描述中的特殊符号

-   ✨：当此补全被选中后，可以按下 `空格键` 和 `Tab` 键继续获得补全候选(特殊情况除外)
-   ✨✨：你需要输入一个不带空格的内容后按下 `空格键` 和 `Tab` 键继续获得补全候选
-   `...`：补全描述等待后续填充
    -   如果 `...` 是最后一个补全候选，则表示可显示区域过小，无法显示所有候选项

## 补全列表

|                  命令补全                   |                                         命令来源                                         |
| :-----------------------------------------: | :--------------------------------------------------------------------------------------: |
| [PSCompletions](/completions/PSCompletions) | [PSCompletions 本模块自用补全](https://www.powershellgallery.com/packages/PSCompletions) |
|           [git](/completions/git)           |                      [Git - 版本控制系统](https://git-scm.com/docs)                      |
|           [wsl](/completions/wsl)           |  [WSL - 适用于 Linux 的 Windows 子系统](https://learn.microsoft.com/zh-cn/windows/wsl/)  |
|        [docker](/completions/docker)        |                     [docker - 容器应用开发](https://www.docker.com/)                     |
|         [scoop](/completions/scoop)         |               [Scoop - 软件管理](https://github.com/ScoopInstaller/Scoop)                |
|         [choco](/completions/choco)         |                 [choco(chocolatey) - 软件管理](https://chocolatey.org/)                  |
|         [volta](/completions/volta)         |                [volta - 无障碍 JavaScript 工具管理器](https://volta.sh/)                 |
|           [nvm](/completions/nvm)           |           [nvm - node 版本管理器](https://github.com/coreybutler/nvm-windows)            |
|          [pnpm](/completions/pnpm)          |                         [pnpm - 软件包管理器](https://pnpm.io/)                          |
|           [npm](/completions/npm)           |                       [npm - 软件包管理器](https://www.npmjs.com/)                       |
|          [yarn](/completions/yarn)          |                     [yarn - 软件包管理器](https://yarnpkg.com/cli/)                      |
|          [chfs](/completions/chfs)          |        [chfs(CuteHttpFileServer) - 跨平台的文件共享服务器](http://iscute.cn/chfs)        |
|        [python](/completions/python)        |                       [python - 编程语言](https://www.python.org/)                       |
|                     ...                     |                                           ...                                            |
