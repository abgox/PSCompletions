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

-   A completion manager in `PowerShell` for better and simpler use and manage completions.
    > It can also be used in `Windows PowerShell`
-   [Manage the completion together.](#available-completions-list "Click it to view the completion list that can be added !")
-   Switch between languages(`zh-CN`,`en-US`) freely.
-   Sort completion tab dynamically by frequency of use.
-   Completion information can be customized.
    -   By modifying the `json` file to achieve.
        > -   It's recommended to modify only the completion prompt description to avoid accidental modification that causes some errors.
        > -   If there are problems, please use `psc update <completion>` to overwrite completion
    -   Get the completion file path. `psc which <completion>`

**If you find this project helpful, please consider giving it a star ⭐.**

## How to install

1. Start `PowerShell`
2. `Install-Module PSCompletions`
3. `Import-Module PSCompletions`
    - `echo "Import-Module PSCompletions" >> $PROFILE`
    - So you don't have to import the module every time you open PowerShell.

## How to uninstall

-   `Uninstall-Module PSCompletions`

## How to use(e.g. `git`)

### [Available Completions](#available-completions-list "All completions that can be added at present. More completions are adding!")

-   If it doesn't include the completion you want, you can [submit an issue](https://github.com/abgox/PSCompletions/issues "Click to submit an issue") and I will consider adding it.

1. `psc add git`
2. Then you can type `git`,`Space` and press `Tab` to get command completion.
3. For more commands on `psc`, you can learn by typing `psc` and then pressing `Tab`.

## Demo

![demo](https://abgop.netlify.app/pscompletions/demo.gif)

## Tips

### About completion update

-   When the module is imported after `PowerShell` is opened,`PSCompletions` will start a background job to check for the completion status of the remote repository.

-   After getting the update, `PSCompletions` will show the latest status of the completions in the next time.

### About completion menu UI

-   The module's completion menu UI is modified from [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion).
-   Starting with version 3.0.0, the completion menu UI offered by this module is used.
    -   If you like the language's built-in completion menu, please run `psc ui theme powershell`.
    -   > Due to the poor use of the UI in `Windows PowerShell`, the language's built-in completion menu will continue to be used.
-   you can use the commands under the `psc ui` to change the style and config.

### About special symbols in Completion Description

> Since ✨ was destructive to the UI, it was replaced with 😄

-   😄: After selecting and applying, Press `Space` and `Tab` to continue to get command completion.
-   😄😄：After selecting and applying, type a string without spaces, press `Space` and `Tab` to continue to get command completion.
-   `...`: The description here will be filled in in the future.
    -   If `...` is the last one in the completion, it means that the display area is too small to display all completions.

### About path completion

-   Please type `./` or `.\` and press `Tab` to get path completion for the **subdirectory** or **file**.
-   Please type `/` or `\` and press `Tab` to get path completion for the **sibling directory**.

## Available Completions

|                 Completions                 |                   Source                   |
| :-----------------------------------------: | :----------------------------------------: |
| [PSCompletions](/completions/PSCompletions) |     PSCompletions - Module completion      |
|          [chfs](/completions/chfs)          |          chfs(CuteHttpFileServer)          |
|         [choco](/completions/choco)         |    choco(chocolatey) - Software Manager    |
|          [deno](/completions/deno)          |   deno - A secure runtime for JS and TS    |
|        [docker](/completions/docker)        | docker - Container Application Development |
|           [git](/completions/git)           |        Git - Version control system        |
|       [kubectl](/completions/kubectl)       |     Kubernetes(k8s) command-line tool      |
|           [npm](/completions/npm)           |           npm - package manager            |
|           [nrm](/completions/nrm)           |         nrm - npm registry manager         |
|           [nvm](/completions/nvm)           |         nvm - Node Version Manager         |
|          [pnpm](/completions/pnpm)          |           pnpm - Package Manager           |
|        [python](/completions/python)        |      python - A programming language       |
|         [scoop](/completions/scoop)         |          Scoop - Software Manager          |
|         [volta](/completions/volta)         | volta - Accessible JavaScript Tool Manager |
|           [wsl](/completions/wsl)           |     WSL - Windows Subsystem for Linux      |
|            [wt](/completions/wt)            |       windows terminal command line        |
|          [yarn](/completions/yarn)          |           yarn - package manager           |
|                     ...                     |                    ...                     |
