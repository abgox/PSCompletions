# ✨✨✨ PSCompletions(psc) ✨✨✨

[![license](https://img.shields.io/github/license/abgox/PSCompletions)](https://github.com/abgox/PSCompletions/blob/main/LICENSE)
[![code size](https://img.shields.io/github/languages/code-size/abgox/PSCompletions.svg)](https://img.shields.io/github/languages/code-size/abgox/PSCompletions.svg)

<p align="left">
<a href="README.md">English</a> |
<a href="README-CN.md">简体中文</a> |
<a href="https://github.com/abgox/PSCompletions">Github</a> |
<a href="https://gitee.com/abgox/PSCompletions">Gitee</a>
</p>

### How to install

1. `Install-Module PSCompletions`
2. `Import-Module PSCompletions`
    - `echo "Import-Module PSCompletions" >> $PROFILE`
    - So you don't have to import the module every time you open PowerShell.

### How to use(eg. git)

-   [completion list](./core/.list)

1. `psc add git`
2. Then you can type `git ` and press `Tab` to get command completion
3. For more commands on `psc`, you can learn by typing `psc` and then pressing `Tab`

### How to uninstall

-   `Uninstall-Module PSCompletions`

### Demo

![PSCompletions.gif](https://img1.imgtp.com/2023/08/21/OsAW6QcU.gif)
