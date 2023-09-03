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

## Introduce

-   A completion manager for better and simpler use and Manage completions.
-   [Manage the completion together.](#available-completions-list "Click it to view the completion list that can be added !")
-   Switch between languages(`zh-CN`,`en-US`) freely.
-   Completion of dynamic sorting.
    -   Sort by frequency of use.
-   Complete content can be customized.
    -   By modifying the `json` file to achieve.
        -   It's recommended to modify only the completion prompt description to avoid accidental modification that causes some errors.
        -   If you do it, don't use `psc update` to avoid overwriting your customizations.
        -   If there are problems, please use `psc update<completion>` to Overwrite completion
    -   Get the completion file path. `psc which <completion>`

**If you find this project helpful, please consider giving it a star ⭐.**

## How to install

1. `Install-Module PSCompletions`
2. `Import-Module PSCompletions`
    - `echo "Import-Module PSCompletions" >> $PROFILE`
    - So you don't have to import the module every time you open PowerShell.

## How to use(eg. `git`)

### [Available Completions](#available-completions-list "All completions that can be added at present. More completions are adding!")

-   If it doesn't include the completion you want, you can [submit an issue](https://github.com/abgox/PSCompletions/issues "Click to submit an issue") and I will consider adding it.

1. `psc add git`
2. Then you can type `git ` and press `Tab` to get command completion.
3. For more commands on `psc`, you can learn by typing `psc` and then pressing `Tab`.

## How to uninstall

-   `Uninstall-Module PSCompletions`

## Demo

[![PSCompletions-demo.gif](https://img1.imgtp.com/2023/08/23/tthYsMaR.gif)](https://img1.imgtp.com/2023/08/23/tthYsMaR.gif)

## About Completion Description

-   ✨: You can continue to press `Tab` to get command completion. (except for special cases)
-   `...`: The description here will be filled in in the future.
    -   If `...` is the last one in the completion, it means that the display area is too small to display all completions.

## Available Completions List

|                 Completions                 |                                            Source                                             |
| :-----------------------------------------: | :-------------------------------------------------------------------------------------------: |
| [PSCompletions](/completions/PSCompletions) | [PSCompletions - Module completion](https://www.powershellgallery.com/packages/PSCompletions) |
|           [wsl](/completions/wsl)           |      [WSL - Windows Subsystem for Linux](https://learn.microsoft.com/zh-cn/windows/wsl/)      |
|           [git](/completions/git)           |                   [Git - Version control system](https://git-scm.com/docs)                    |
|        [docker](/completions/docker)        |             [docker - Container Application Development](https://www.docker.com/)             |
|         [scoop](/completions/scoop)         |              [Scoop - Software Manager](https://github.com/ScoopInstaller/Scoop)              |
|         [choco](/completions/choco)         |                [choco(chocolatey) - Software Manager](https://chocolatey.org/)                |
|         [volta](/completions/volta)         |                [volta - Accessible JavaScript Tool Manager](https://volta.sh/)                |
|           [nvm](/completions/nvm)           |           [nvm - Node Version Manager](https://github.com/coreybutler/nvm-windows)            |
|          [pnpm](/completions/pnpm)          |                          [pnpm - Package Manager](https://pnpm.io/)                           |
|           [npm](/completions/npm)           |                        [npm - package manager](https://www.npmjs.com/)                        |
|          [yarn](/completions/yarn)          |                      [yarn - package manager](https://yarnpkg.com/cli/)                       |
|          [chfs](/completions/chfs)          |                       [chfs(CuteHttpFileServer)](http://iscute.cn/chfs)                       |
|        [python](/completions/python)        |                  [python - A programming language](https://www.python.org/)                   |
|                     ...                     |                                              ...                                              |
