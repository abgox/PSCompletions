<p align="center">
    <h1 align="center">✨PSCompletions(psc) ✨</h1>
</p>

</p>
<p align="center">
    <a href="README.md">English</a> |
    <a href="README-CN.md">简体中文</a> |
    <a href="https://github.com/abgox/PSCompletions">Github</a> |
    <a href="https://gitee.com/abgox/PSCompletions">Gitee</a>
</p>

---

<p align="left">
    <a href="https://github.com/abgox/PSCompletions/blob/main/LICENSE">
        <img src="https://img.shields.io/github/license/abgox/PSCompletions" alt="license" />
    </a>
    <a href="https://img.shields.io/github/languages/code-size/abgox/PSCompletions.svg">
        <img src="https://img.shields.io/github/languages/code-size/abgox/PSCompletions.svg" alt="code size" />
    </a>
</p>

## Introduce

-   A completion manager for better and simpler use and Manage completions.
-   [Manage the completion together.](./core/.list "Click it to view the completion list that can be added !")
-   Switch between languages(`zh-CN`,`en-US`) freely.
-   Complete content can be customized.
    -   By modifying the `json` file to achieve.
        -   if you do it, Please do not use `psc update` to avoid overwriting your customizations.
    -   Get the completion file path. `psc which <completion>`

## How to install

1. `Install-Module PSCompletions`
2. `Import-Module PSCompletions`
    - `echo "Import-Module PSCompletions" >> $PROFILE`
    - So you don't have to import the module every time you open PowerShell.

## How to use(eg. `git`)

### [Completion List](./core/.list "All completions that can be added at present. More completions are adding!")

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
    -   If `...` is the last completion, it means that the display area is too small to display all completions.
