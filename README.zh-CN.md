<h1 align="center">✨<a href="https://pscompletions.abgox.com">PSCompletions(psc)</a>✨</h1>

<p align="center">
    <a href="README.md">English</a> |
    <span>简体中文</span> |
    <a href="https://www.powershellgallery.com/packages/PSCompletions">PowerShell Gallery</a> |
    <a href="https://github.com/abgox/PSCompletions">GitHub</a> |
    <a href="https://atomgit.com/abgox/PSCompletions">AtomGit</a> |
    <a href="https://gitee.com/abgox/PSCompletions">Gitee</a>
</p>

<p align="center">
    <a href="https://github.com/abgox/PSCompletions/blob/main/LICENSE">
        <img src="https://img.shields.io/github/license/abgox/PSCompletions" alt="license" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/v/PSCompletions?label=version" alt="module version" />
    </a>
    <a href="../index/completions.zh-CN.md">
        <img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fabgox%2FPSCompletions%2Frefs%2Fheads%2Findex%2Fcompletions.json&query=%24.count&label=completions" alt="completions" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/dt/PSCompletions" alt="PowerShell Gallery" />
    </a>
    <a href="https://github.com/abgox/PSCompletions">
        <img src="https://img.shields.io/github/created-at/abgox/PSCompletions" alt="created" />
    </a>
</p>

## 介绍

**Powerful Shell Completions** —— 适用于 [PowerShell 和其他 Shell](https://pscompletions.abgox.com/docs/shells) 的强大的命令补全器，由 Rust 与 Lua 驱动。

- [一个引擎，多个 Shell](https://pscompletions.abgox.com/docs/shells)
- [内置的补全库](../index/completions.zh-CN.md)
- [更强大的补全菜单](https://pscompletions.abgox.com/docs/completion-menu)
- [多语言支持: en-US、zh-CN 等](https://pscompletions.abgox.com/docs/language)
- [基于命令历史的补全项动态排序](https://pscompletions.abgox.com/docs/sort-completion-items)

## 演示

![demo](https://pscompletions.abgox.com/demo.zh-CN.gif)

## 使用

1. 安装它
   - [Install-Module](https://learn.microsoft.com/powershell/module/powershellget/install-module)

     ```powershell
     Install-Module PSCompletions
     ```

   - [Install-PSResource](https://learn.microsoft.com/powershell/module/microsoft.powershell.psresourceget/install-psresource)

     ```powershell
     Install-PSResource PSCompletions
     ```

   - [Scoop](https://scoop.sh)
     - 使用 [main](https://github.com/ScoopInstaller/Main) bucket

       ```shell
       scoop install pscompletions
       ```

     - 使用 [abyss](https://abyss.abgox.com) bucket

       ```shell
       scoop install abyss/abgox.PSCompletions
       ```

2. 加载它
   - PowerShell —— [直接导入模块](https://pscompletions.abgox.com/docs/direct-import-module)：

     ```powershell
     Import-Module PSCompletions
     ```

   - 其他 Shell —— 引入模块内置的桥接脚本（见 [Shell 支持](https://pscompletions.abgox.com/docs/shells)）：

     ```sh
     # Linux / macOS；Windows 的模块目录不同
     module="$(ls -dt "$HOME"/.local/share/powershell/Modules/PSCompletions/*/ | head -1)"

     # bash —— 在 ~/.bashrc 里加一行，放在文件末尾
     source "${module}PSCompletions.bash"
     # zsh —— 在 ~/.zshrc 里加一行，放在文件末尾
     source "${module}PSCompletions.zsh"
     # fish —— 用 conf.d 软链，或从 config.fish 里 source 它
     ln -s "${module}PSCompletions.fish" ~/.config/fish/conf.d/PSCompletions.fish
     ```

3. 使用它
   - [内置补全库](../index/completions.zh-CN.md)：用 `psc add git` 添加补全
   - [原生补全](https://pscompletions.abgox.com/docs/native-completion)：各 Shell 有各自的机制 —— PowerShell 参数补全器、bash/zsh/fish 原生补全，等等

## 新的变化

请查看 [更新日志](./module/CHANGELOG.zh-CN.md)

## 贡献

请查看 [贡献指南](./.github/contributing.md)

## 支持

如果你喜欢这个项目，欢迎给它 Star ⭐️ 或 [赞赏 💰](https://me.abgox.com/donate)

## 致谢

- [PSReadLine](https://github.com/PowerShell/PSReadLine) — PowerShell 的编辑与补全基础
- [fzf](https://github.com/junegunn/fzf)/[PSFzf](https://github.com/kelleyma49/PSFzf) — [补全菜单](https://pscompletions.abgox.com/docs/completion-menu) 的 UI 参考

## License

[MIT](./LICENSE) © [abgox](https://me.abgox.com)
