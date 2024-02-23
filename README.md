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

## Introduce

-   A completion manager in `PowerShell` for better and simpler use completions.
    > It can also be used in `Windows PowerShell`.
-   [Manage completions together.](#available-completions-list "Click it to view the completion list that can be added !")
-   Switch between languages(`zh-CN`,`en-US`) freely.
-   Sort completion tab dynamically by frequency of use.

> -   Completion information can be customized.(Not Recommend)
>     -   By modifying the `json` file.
>     -   Get the completion file path: `psc which <completion>`
>     -   It's recommended to modify only the completion prompt description to avoid accidental modification that causes some errors.
>     -   If there are problems, please run `psc update <completion>` to overwrite completion.

**If this project is helpful to you, please consider giving it a star ⭐.**

## How to install

1. Start `PowerShell`
    - If using `Windows PowerShell`, it's necessary to start in administrator privilege.
2. `Install-Module PSCompletions`
3. `Import-Module PSCompletions`
    - `echo "Import-Module PSCompletions" >> $PROFILE`
    - So you don't have to import the module every time you open PowerShell.

## How to uninstall

1. Start `PowerShell`
    - If using `Windows PowerShell`, it's necessary to start in administrator privilege.
2. `Uninstall-Module PSCompletions`

## How to use(e.g. `git`)

### [Available Completions](#available-completions-list "All completions that can be added at present. More completions are adding!")

-   If it doesn't include the completion you want, you can [submit an issue](https://github.com/abgox/PSCompletions/issues "Click to submit an issue") and I will consider adding it.

1. `psc add git`
2. Then you can type `git` and press `Space` `Tab` to get command completion.
3. For more commands on `psc`, you can learn by typing `psc` and then pressing `Space` `Tab`.

## Demo

![demo](https://abgop.netlify.app/pscompletions/demo.gif)

## Tips

### About completion update

-   When the module is imported after `PowerShell` is opened, `PSCompletions` will start a background job to check for the completion status of the remote repository.

-   After getting the update, `PSCompletions` will show the latest status of the completions in the next time.

### About completion menu UI

-   The module's completion menu UI is modified from [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion).
-   Starting with version 3.0.0, the completion menu UI offered by this module is used.
    -   If you like the language's built-in completion menu, please run `psc ui theme powershell`.
    -   > Due to the poor use of the UI in `Windows PowerShell`, the language's built-in completion menu will continue to be used.
-   you can run the commands under the `psc ui` to change the style and config.

### About special symbols in Completion Description

-   For 😄😎🤔: If there are multiple, you can choose the effect of one of them.

-   😄: It means that after you choose it, you can press `Space` and `Tab` key to continue to get command completions.

    -   This symbol can be customized by running `psc config symbol SpaceTab <symbol>`
    -   e.g. `psc config symbol SpaceTab 😄`

-   😎: It means that after you choose it, you can input a string without spaces, then press `Space` and `Tab` key to continue to get command completions.

    -   This symbol can be customized by running `psc config symbol WriteSpaceTab <symbol>`

-   🤔: It means that after you choose it, you can press `Space` and `Tab` key to continue to get option-type completions(e.g. --verbose).

    -   This symbol can be customized by running `psc config symbol OptionsTab <symbol>`

-   `...`: The description here will be filled in in the future.
    -   If `...` is the last one in the completion, it means that the display area is too small to display all completions.

### About path completion

-   Please type `./` or `.\` and press `Tab` to get path completion for the **subdirectory** or **file**.
-   Please type `/` or `\` and press `Tab` to get path completion for the **sibling directory**.

## Available Completions List

|                 Completions                 |                                            Source                                             |
| :-----------------------------------------: | :-------------------------------------------------------------------------------------------: |
| [PSCompletions](/completions/PSCompletions) | [PSCompletions - Module completion](https://www.powershellgallery.com/packages/PSCompletions) |
|         [cargo](/completions/cargo)         |                 [cargo - Rust package manager](https://rustwiki.org/en/cargo)                 |
|          [chfs](/completions/chfs)          |                       [chfs(CuteHttpFileServer)](http://iscute.cn/chfs)                       |
|         [choco](/completions/choco)         |                [choco(chocolatey) - Software Manager](https://chocolatey.org)                 |
|          [deno](/completions/deno)          |                   [deno - A secure runtime for JS and TS](https://deno.com)                   |
|        [docker](/completions/docker)        |             [docker - Container Application Development](https://www.docker.com)              |
|           [git](/completions/git)           |                      [Git - Version control system](https://git-scm.com)                      |
|       [kubectl](/completions/kubectl)       |                  [Kubernetes(k8s) command-line tool](https://kubernetes.io)                   |
|           [npm](/completions/npm)           |                        [npm - package manager](https://www.npmjs.com)                         |
|           [nrm](/completions/nrm)           |                   [nrm - npm registry manager](https://github.com/Pana/nrm)                   |
|           [nvm](/completions/nvm)           |                  [nvm - Node Version Manager](https://github.com/nvm-sh/nvm)                  |
|           [pip](/completions/pip)           |                  [pip - Python Package Manager](https://github.com/pypa/pip)                  |
|          [pnpm](/completions/pnpm)          |                         [pnpm - Package Manager](https://www.pnpm.cn)                         |
|        [python](/completions/python)        |                        [python - command-line](https://www.python.org)                        |
|         [scoop](/completions/scoop)         |                         [Scoop - Software Manager](https://scoop.sh)                          |
|         [volta](/completions/volta)         |                [volta - Accessible JavaScript Tool Manager](https://volta.sh)                 |
|        [winget](/completions/winget)        |          [WinGet - Windows package manager](https://github.com/microsoft/winget-cli)          |
|           [wsl](/completions/wsl)           |             [WSL - Windows Subsystem for Linux](https://github.com/microsoft/WSL)             |
|            [wt](/completions/wt)            |            [windows terminal command line](https://github.com/microsoft/terminal)             |
|          [yarn](/completions/yarn)          |                 [yarn - package manager](https://classic.yarnpkg.com/lang/en)                 |
|                     ...                     |                                              ...                                              |
