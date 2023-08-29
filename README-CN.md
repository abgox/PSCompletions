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
</p>

---

## 介绍

-   一个补全管理模块，更好、更简单、更方便的使用和管理补全
-   [集中管理补全](#补全列表 "点击查看可添加补全列表！")
-   `zh-CN`,`en-US` 多语言随意切换
-   补全动态排序
    -   根据使用频次对补全候选菜单进行合理排序
-   补全内容可自定义
    -   通过修改补全`json`文件来实现
    -   `psc which <completion>` 获取补全文件路径
    -   如果你已修改，请不要使用`psc update`，避免你的自定义被覆盖

## 安装

1. `Install-Module PSCompletions`
2. `Import-Module PSCompletions`
    - 如果不想每次启动终端都导入一次，就执行 `echo "Import-Module PSCompletions" >> $PROFILE`

## 使用(以 `git` 补全为例)

### [可用补全列表](#补全列表 "当前可添加的所有补全，更多的补全正在添加中！")

1. `psc add git`
2. 然后你就可以输入`git ` 按下`Tab` 来获得命令补全
3. 关于`psc`的更多命令，你可以通过输入`psc`然后按下`Tab`来了解

## 卸载

-   `Uninstall-Module PSCompletions`

## Demo

[![PSCompletions-demo.gif](https://img1.imgtp.com/2023/08/23/tthYsMaR.gif)](https://img1.imgtp.com/2023/08/23/tthYsMaR.gif)

## 关于补全描述

-   ✨：还可以按下 `Tab` 获得补全候选(特殊情况除外)
-   `...`：补全描述等待后续填充
    -   如果 `...` 是最后一个补全候选，则表示可显示区域过小，无法显示所有候选项

## 补全列表

|                  命令补全                   |                                 命令来源                                  |
| :-----------------------------------------: | :-----------------------------------------------------------------------: |
| [PSCompletions](/completions/PSCompletions) | [PSCompletions](https://www.powershellgallery.com/packages/PSCompletions) |
|           [git](/completions/git)           |                      [Git](https://git-scm.com/docs)                      |
|         [scoop](/completions/scoop)         |             [Scoop](https://github.com/ScoopInstaller/Scoop)              |
|         [volta](/completions/volta)         |                        [volta](https://volta.sh/)                         |
|          [pnpm](/completions/pnpm)          |                         [pnpm](https://pnpm.io/)                          |
|           [nvm](/completions/nvm)           |             [nvm](https://github.com/coreybutler/nvm-windows)             |
|           [npm](/completions/npm)           |                       [npm](https://www.npmjs.com/)                       |
|        [python](/completions/python)        |                     [python](https://www.python.org/)                     |
|          [chfs](/completions/chfs)          |             [chfs(CuteHttpFileServer)](http://iscute.cn/chfs)             |
|         [choco](/completions/choco)         |               [choco(chocolatey)](https://chocolatey.org/)                |
|        [docker](/completions/docker)        |                     [docker](https://www.docker.com/)                     |
|          [yarn](/completions/yarn)          |                     [yarn](https://yarnpkg.com/cli/)                      |
|                     ...                     |                                    ...                                    |
