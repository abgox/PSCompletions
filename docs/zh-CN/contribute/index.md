---
title: 关于 PR (Pull Request)
prev:
    text: 关于补全的 json 文件结构
    link: '../completion/index.md'
---

# 关于 PR (Pull Request)

1. 前提: 你应该先阅读 [关于补全的 json 文件结构](../completion/index.md)
2. 你应该 fork [PSCompletions 仓库](https://github.com/abgox/PSCompletions)，克隆到本地进行修改
3. 只要到补全文件进行了修改，都需要更新其目录下的 `guid.txt` 文件
    - 你可以手动运行 `New-Guid` 生成，将值填入此文件中
    - 也可以直接运行 `.\script\updateGuid.ps1`，在弹出的 PowerShell 列表框中，选择此补全，并应用修改即可
4. 修改完成后，提交并创建 `PR`

## 1. 更新 json 文件内容

-   完善补全的一些提示信息(`tip` 属性)
-   添加补全的一些缺失的命令

## 2. 添加语言

1. 在项目的 `completions` 目录中找到你想要添加语言的补全
2. 在其目录下的 `config.json` 文件中的 `language` 属性里添加像 `zh-CN` 这样的语言标识符
3. 在 `language` 目录下添加与语言标识符同名的 json 文件
    - 你可以将原有的一个 json 文件直接复制，改名即可
4. 翻译其中的 `tip` 属性的内容即可

## 3. 添加一个全新的命令补全

1. 在项目根目录下运行 `.\script\create.ps1`
2. 根据提示进行操作
3. 修改新创建的补全
4. 最后还需要在项目根目录的 `completions.json` 中的 `list` 属性值中添加此补全
