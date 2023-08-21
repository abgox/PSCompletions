# ✨✨✨ PSCompletions(psc) ✨✨✨

[![license](https://img.shields.io/github/license/abgox/PSCompletions)](https://github.com/abgox/PSCompletions/blob/main/LICENSE)
[![code size](https://img.shields.io/github/languages/code-size/abgox/PSCompletions.svg)](https://img.shields.io/github/languages/code-size/abgox/PSCompletions.svg)

<p align="left">
<a href="README.md">English</a> |
<a href="README-CN.md">简体中文</a> |
<a href="https://github.com/abgox/PSCompletions">Github</a> |
<a href="https://gitee.com/abgox/PSCompletions">Gitee</a>
</p>

### 安装

1. `Install-Module PSCompletions`
2. `Import-Module PSCompletions`
    - 如果不想每次启动终端都导入一次，就执行 `echo "Import-Module PSCompletions" >> $PROFILE`

### 使用(以 git 补全为例)

-   [补全列表](./core/.list)

1. `psc add git`
2. 然后你就可以输入`git ` 按下`Tab` 来获得命令补全
3. 关于`psc`的更多命令，你可以通过输入`psc`然后按下`Tab`来了解

### 卸载

-   `Uninstall-Module PSCompletions`

### Demo

![PSCompletions.gif](https://img1.imgtp.com/2023/08/21/OsAW6QcU.gif)
