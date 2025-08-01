<h1 align="center">✨<a href="https://pscompletions.abgox.com">PSCompletions(psc)</a>✨</h1>

<p align="center">
    <a href="README-CN.md">简体中文</a> |
    <a href="README.md">English</a> |
    <a href="https://github.com/abgox/PSCompletions">Github</a> |
    <a href="https://gitee.com/abgox/PSCompletions">Gitee</a>
</p>

<p align="center">
    <a href="https://github.com/abgox/PSCompletions/blob/main/LICENSE">
        <img src="https://img.shields.io/github/license/abgox/PSCompletions" alt="license" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/v/PSCompletions?label=version" alt="module version" />
    </a>
    <a href="https://www.powershellgallery.com/packages/PSCompletions">
        <img src="https://img.shields.io/powershellgallery/dt/PSCompletions?color=%23008FC7" alt="PowerShell Gallery" />
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

> [!Tip]
>
> - [`PowerShell(pwsh)`](https://learn.microsoft.com/powershell/scripting/overview): A cross-platform PowerShell. Start it by running `pwsh`/`pwsh.exe`.
> - [`Windows PowerShell`](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell): A PowerShell which is built-in on Windows system. Start it by running `powershell`/`powershell.exe`.
> - They can both use `PSCompletions`, but [`PowerShell(pwsh)`](https://learn.microsoft.com/powershell/scripting/overview) is more recommended.

- A completion manager in `PowerShell` for better and simpler use completions.
- [Manage completions together.](#available-completions "Click it to view the completion list that can be added.")
- Switch between languages(`en-US`,`zh-CN`,...) freely.
- Sort completion items dynamically by frequency of use.
- [More powerful completion menu.](#about-completion-menu "Click it to learn more about it.")
- [Combined with argc-completions.](https://pscompletions.abgox.com/tips/pscompletions-and-argc-completions "Click to see what you need to do.")
  - [sigoden/argc-completions](https://github.com/sigoden/argc-completions)

[**If `PSCompletions` is helpful to you, please consider giving it a star.**](#stars)

## What's new

- See the [CHANGELOG](./module/CHANGELOG.md) for details.

## FAQ

- See the [FAQ](https://pscompletions.abgox.com/FAQ).

## How to install

> [!Warning]
>
> - [`PowerShell(pwsh)`](https://learn.microsoft.com/powershell/scripting/overview): Don't add `-Scope AllUsers` unless you're sure you'll always use administrator permissions.
> - [`Windows PowerShell`](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell): Don't omit `-Scope CurrentUser` unless you're sure you'll always use administrator permissions.

1. Start `PowerShell`.
2. Install module:

   - Normal:

     ```powershell
     Install-Module PSCompletions
     ```

   - Install silently:
     ```powershell
     Install-Module PSCompletions -Repository PSGallery -Force
     ```
   - Use [Scoop](https://scoop.sh/):

     ```shell
     scoop bucket add abyss https://github.com/abgox/abyss.git
     ```

     ```shell
     scoop install abyss/abgox.PSCompletions
     ```

3. Import module:
   ```powershell
   Import-Module PSCompletions
   ```
   - Add it to your `$PROFILE` to make it permanent by running the following command.
     ```powershell
     echo "Import-Module PSCompletions" >> $PROFILE
     ```
   - Note: Recommend add `Import-Module PSCompletions` early in `$PROFILE` to void [the encoding issue](https://pscompletions.abgox.com/en-US/FAQ/#about-the-output-encoding).
   - [About the completion trigger key](#about-the-completion-trigger-key).

## How to uninstall

1. Start `PowerShell`.
2. Uninstall module:
   ```powershell
   Uninstall-Module PSCompletions
   ```

## How to use

> [!Tip]
>
> - [Available Completions.](#available-completions "All completions that can be added at present. More completions are adding!")
> - If it doesn't include the completion you want, you can [submit an issue](https://github.com/abgox/PSCompletions/issues "Click to submit an issue.").
> - You can also [combined with argc-completions.](https://pscompletions.abgox.com/tips/pscompletions-and-argc-completions "Click to see what you need to do.")

- Take `git` as an example.

1. `psc add git`
2. Then you can enter `git`, press `Space` and `Tab` key to get command completion.
3. For more usages on `psc`, you just need to enter `psc`, press `Space` and `Tab` key, and you will get all usages of `psc` by reading [the completion tip](#about-completion-tip).

## Demo

![demo](https://pscompletions.abgox.com/demo.gif)

## Contribution

- See the [CONTRIBUTING](./.github/contributing.md) for details.

## Tips

### About the completion trigger key

- `PSCompletions` uses the `Tab` key by default.
- You can set it by running `psc menu config trigger_key <key>`.

> [!Warning]
>
> - If you need to set `Set-PSReadLineKeyHandler -Key <key> -Function <MenuComplete|Complete>`
> - Please add it before `Import-Module PSCompletions`
> - Example:
>
>   ```powershell
>   Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
>
>   Import-Module PSCompletions
>   ```

### About completion update

- When `PSCompletions` module is imported after starting `PowerShell`, it will start a background job to check for the completion status of the remote repository.
- After getting the update, `PSCompletions` will show the latest status of the completions in the next time.

### About option completion

- `Optional Completions`: some command completions that like `-*`, such as `--global` in `git config --global`.
- You should use option completion first.
- Taking `git` as an example, if you want to enter `git config user.name --global xxx`, you should use `--global` completion first, and then use `user.name`, and then enter the name `xxx` .
- For options ending with `=`, if there's completion definition, you can directly press the `Tab` key to get the completions.

### About completion menu

- In addition to the built-in completion menu of `PowerShell`, `PSCompletions` module also provides a more powerful completion menu.

  - Setting: `psc menu config enable_menu 1` (Default: `1`)

- The module's completion menu is based on [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion) realization idea, thanks!

- Available Windows environment:
  - `PowerShell`
  - `Windows PowerShell`
    - Due to rendering problems of `Windows PowerShell`, the border style of the completion menu cannot be customized.
      - If you need to customize it, use `PowerShell`.
- Some keys in the module's completion menu.

  1. Apply the selected completion item: `Enter` / `Space`
     - You can also use `Tab` when there's only one completion.
  2. Delete filter characters: `Backspace`
  3. Exit the completion menu: `Esc` / `Ctrl + c`
     - You can also use `Backspace` when there're no characters in the filter area.
  4. Select completion item:

     | Select previous item | Select next item |
     | :------------------: | :--------------: |
     |         `Up`         |      `Down`      |
     |        `Left`        |     `Right`      |
     |    `Shift + Tab`     |      `Tab`       |
     |      `Ctrl + u`      |    `Ctrl + d`    |
     |      `Ctrl + p`      |    `Ctrl + n`    |

- All configurations of it, you can trigger completion by running `psc menu`, then learn about them by [the completion tip](#about-completion-tip).
  - For configured values, `1` means `true` and `0` means `false`. (It applies to all configurations of `PSCompletions`)

#### About menu enhance

- Setting: `psc menu config enable_menu_enhance 1` (Default: `1`)
- Now, `PSCompletions` has two completion implementations.

  - [`Set-PSReadLineKeyHandler`](https://learn.microsoft.com/powershell/module/psreadline/set-psreadlinekeyhandler)
    - It's used by default.
      - Requires: `enable_menu` and `enable_menu_enhance` both set to `1`.
    - It no longer needs to loop through registering `Register-ArgumentCompleter` for all completions, which theoretically makes loading faster.
    - It use [`TabExpansion2`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/tabexpansion2) to manage completions globally, not limited to those added by `psc add`.
      - For example:
        - Path completion such as `cd`/`.\`/`..\`/`~\`/... in `PowerShell`.
        - Build-in commands such as `Get-*`/`Set-*`/`New-*`/... in `PowerShell`.
        - Completion registered by [`Register-ArgumentCompleter`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter)
        - [Combined with argc-completions.](https://pscompletions.abgox.com/tips/pscompletions-and-argc-completions)
        - Completion registered by cli or module.
        - ...
  - [`Register-ArgumentCompleter`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter)
    - You can use it by running `psc menu config enable_menu_enhance 0`.
    - It only works for completions added by `psc add`.
    - Other completions are controlled by `Set-PSReadLineKeyHandler -Key <key> -Function <MenuComplete|Complete>`.

### About special symbols

> [!Tip]
>
> - Due to future changes in Windows Terminal, 😄🤔😎 will not be displayed properly in the completion menu, so these three default special symbols will change.
> - Related issue: https://github.com/microsoft/terminal/issues/18242
> - The changes are as follows:
>   - `😄` => `~`
>   - `🤔` => `?`
>   - `😎` => `!`

- Special symbols after the completion item are used to let you know in advance if completions are available before you press the `Tab` key.

  - They only exist in completions added by `psc add`.
  - You can hide them by replacing them with the empty string.
    - `psc menu symbol SpaceTab ""`
    - `psc menu symbol OptionTab ""`
    - `psc menu symbol WriteSpaceTab ""`

- `~`,`?`,`!` : If there are multiple, you can choose the effect of one of them.
  - Define them:
    - `Normal Completions`: Sub-commands. Such as `add`/`pull`/`push`/`commit`/... in `git`.
    - `Optional Completions`: Optional parameters. Such as `-g`/`-u`/... in `git add`.
    - `General Optional Completions`: General optional parameters that can be used with any command. Such as `--help`/... in `git`.
    - `Current Completions`: Current completion items in completion menu.
  - `~` : It means that after you apply it, you can press `Space` and `Tab` key to continue to get completions.
    - It can be customized by running `psc menu symbol SpaceTab <symbol>`
  - `?` : It means that after you apply it (`Optional Completions` or `General Optional Completions`), you can press `Space` and `Tab` key to continue to get `Current Completions`.
    - It can be customized by running `psc menu symbol OptionTab <symbol>`
  - `!` : It means that after you apply it (`Optional Completions` or `General Optional Completions`), you can press `Space` and enter a string, then press `Space` and `Tab` key to continue to get completions.
    - If the string has Spaces, Please use `"`(quote) or `'`(single quote) to wrap it. e.g. `"test content"`
    - If there's also `~`, it means that there's some preset completions, you can press `Space` and `Tab` key to continue to get them without entering a string.
    - It can be customized by running `psc menu symbol WriteSpaceTab <symbol>`
  - All completions can be triggered by pressing the `Tab` key after entering a part.

### About completion tip

- The completion tip is only a helper, you can also disable the tip by running `psc menu config enable_tip 0`

  - To enable the completion tip, run `psc menu config enable_tip 1`.
  - You can also disable the tip for a specific completion, such as `psc`.
    - `psc completion psc enable_tip 0`

- General structure of the completion tip: `Usage` + `Description` + `Example`

  ```txt
  U: install|add [-g|-u] [options] <app>
  This is a description of the command.
  E: install xxx
     add -g xxx
  ```

- Example Analysis:
  1. Usage: Begin with `U:`
     - command name: `install`
     - command alias: `add`
     - required parameters: `<app>`
       - `app` is a simple summary of the parameters.
     - optional parameters: `-g` `-u`
       - `[options]`: Some options.
  2. Description: The description of the command.
  3. Example: Begin with `E:`

### About language

- `Global language`: Default to the language of current system.
  - You can show it by running `psc config language`.
  - You can change it by running `psc config language zh-CN`.
- `Completion language`: The language set for the specified completion.
  - e.g. `psc completion git language en-US`.
- `Available language`: In the completion `config.json` file, there is a `language` attribute whose value is a list of available languages.

#### Determine language

1. Get the specified language:
   - If there is `Completion language`,use it.
   - If not, use `Global language`.
2. Determine the final language:
   - Determine whether the value of the first step exists in `Available language`.
   - If it exists, use it.
   - If not, use the first of the `Available language`. (It's usually `en-US`)

### About path completion

- Take `git` for example, when entering `git add`, pressing the `Space` and `Tab` keys, path completion will not be triggered, only completion provided by the module will be triggered.
- If you want to trigger path completion, you need to enter a content which matches `^(?:\.\.?|~)?(?:[/\\]).*`.
- e.g.
  - Please enter `./` or `.\` and press `Tab` key to get path completion for the **subdirectory** or **file**.
  - Please enter `../` or `..\` and press `Tab` key to get path completion for the **parent directory** or **file**.
  - Please enter `/` or `\` and press `Tab` key to get path completion for the **sibling directory**.
  - More examples: `~/` / `../../` ...
- So you can enter `git add ./` and then press `Tab` key to get the path completion.

## Stars

**If `PSCompletions` is helpful to you, please consider giving it a star.**

<a href="https://github.com/abgox/PSCompletions">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="http://reporoster.com/stars/abgox/PSCompletions"> <!-- light theme -->
    <img alt="stargazer-widget" src="http://reporoster.com/stars/dark/abgox/PSCompletions"> <!-- dark theme -->
  </picture>
</a>

## Support

<a href='https://ko-fi.com/W7W817R6Z3' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://me.abgox.com/buy-me-a-coffee.png' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

![Support](https://me.abgox.com/support.png)

## Available Completions

- Guide
  - **`Completion`** ：Click to view to the official website of the command. Sort by first letter(0-9,a-z).
  - **`Language`**: Supported Languages, and Progress.
    - This progress is compared to the first language defined in `config.json` (usually `en-US`).
  - **`Description`**: Command Description.

<!-- prettier-ignore-start -->
|Completion|Language|Description|
|:-:|-|-|
|[7z](https://7-zip.org/)|[**en-US**](/completions/7z/language/en-US.json)<br>[**zh-CN(100%)**](/completions/7z/language/zh-CN.json)|The command line cli of 7-Zip|
|[arch](https://github.com/uutils/coreutils)|[**en-US**](/completions/arch/language/en-US.json)<br>[**zh-CN(100%)**](/completions/arch/language/zh-CN.json)|Display machine architecture.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[b2sum](https://github.com/uutils/coreutils)|[**en-US**](/completions/b2sum/language/en-US.json)<br>[**zh-CN(13.33%)**](/completions/b2sum/language/zh-CN.json)|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[b3sum](https://github.com/uutils/coreutils)|[**en-US**](/completions/b3sum/language/en-US.json)<br>[**zh-CN(13.33%)**](/completions/b3sum/language/zh-CN.json)|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[base32](https://github.com/uutils/coreutils)|[**en-US**](/completions/base32/language/en-US.json)<br>[**zh-CN(28.57%)**](/completions/base32/language/zh-CN.json)|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[base64](https://github.com/uutils/coreutils)|[**en-US**](/completions/base64/language/en-US.json)<br>[**zh-CN(28.57%)**](/completions/base64/language/zh-CN.json)|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[basename](https://github.com/uutils/coreutils)|[**en-US**](/completions/basename/language/en-US.json)<br>[**zh-CN(28.57%)**](/completions/basename/language/zh-CN.json)|Print NAME with any leading directory components removed.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[basenc](https://github.com/uutils/coreutils)|[**en-US**](/completions/basenc/language/en-US.json)<br>[**zh-CN(13.33%)**](/completions/basenc/language/zh-CN.json)|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[bun](https://bun.sh)|[**en-US**](/completions/bun/language/en-US.json)<br>[**zh-CN(100%)**](/completions/bun/language/zh-CN.json)|Bun - JavaScript all-in-one toolkit.|
|[cargo](https://rustwiki.org/en/cargo)|[**en-US**](/completions/cargo/language/en-US.json)<br>[**zh-CN(100%)**](/completions/cargo/language/zh-CN.json)|cargo - Rust package manager.|
|[chfs](http://iscute.cn/chfs)|[**en-US**](/completions/chfs/language/en-US.json)<br>[**zh-CN(100%)**](/completions/chfs/language/zh-CN.json)|CuteHttpFileServer - A free, HTTP protocol file sharing server cross-platform file sharing server.|
|[choco](https://chocolatey.org/)|[**en-US**](/completions/choco/language/en-US.json)<br>[**zh-CN(100%)**](/completions/choco/language/zh-CN.json)|choco(chocolatey) - Software Manager.|
|[cksum](https://github.com/uutils/coreutils)|[**en-US**](/completions/cksum/language/en-US.json)<br>[**zh-CN(20%)**](/completions/cksum/language/zh-CN.json)|Print CRC and size for each file.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[comm](https://github.com/uutils/coreutils)|[**en-US**](/completions/comm/language/en-US.json)<br>[**zh-CN(20%)**](/completions/comm/language/zh-CN.json)|Compare two sorted files line by line.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[conda](https://github.com/conda/conda)|[**en-US**](/completions/conda/language/en-US.json)<br>[**zh-CN(100%)**](/completions/conda/language/zh-CN.json)|conda - binary package and environment manager.|
|[csplit](https://github.com/uutils/coreutils)|[**en-US**](/completions/csplit/language/en-US.json)<br>[**zh-CN(18.18%)**](/completions/csplit/language/zh-CN.json)|Split a file into sections determined by context lines.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[cut](https://github.com/uutils/coreutils)|[**en-US**](/completions/cut/language/en-US.json)<br>[**zh-CN(15.38%)**](/completions/cut/language/zh-CN.json)|Print specified byte or field columns from each line of stdin or the input files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[date](https://github.com/uutils/coreutils)|[**en-US**](/completions/date/language/en-US.json)<br>[**zh-CN(14.29%)**](/completions/date/language/zh-CN.json)|Print or set the system date and time.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[dd](https://github.com/uutils/coreutils)|[**en-US**](/completions/dd/language/en-US.json)<br>[**zh-CN(100%)**](/completions/dd/language/zh-CN.json)|Copy, and optionally convert, a file system resource.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[deno](https://deno.com/)|[**en-US**](/completions/deno/language/en-US.json)<br>[**zh-CN(100%)**](/completions/deno/language/zh-CN.json)|Deno - A secure runtime for JavaScript and TypeScript.|
|[df](https://github.com/uutils/coreutils)|[**en-US**](/completions/df/language/en-US.json)<br>[**zh-CN(5.71%)**](/completions/df/language/zh-CN.json)|Show information about the file system on which each FILE resides, or all file systems by default.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[dircolors](https://github.com/uutils/coreutils)|[**en-US**](/completions/dircolors/language/en-US.json)<br>[**zh-CN(25%)**](/completions/dircolors/language/zh-CN.json)|Output commands to set the LS_COLORS environment variable.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[dirname](https://github.com/uutils/coreutils)|[**en-US**](/completions/dirname/language/en-US.json)<br>[**zh-CN(40%)**](/completions/dirname/language/zh-CN.json)|Strip last component from file name.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[docker](https://www.docker.com)|[**en-US**](/completions/docker/language/en-US.json)<br>[**zh-CN(100%)**](/completions/docker/language/zh-CN.json)|docker - Container Application Development.|
|[du](https://github.com/uutils/coreutils)|[**en-US**](/completions/du/language/en-US.json)<br>[**zh-CN(2.17%)**](/completions/du/language/zh-CN.json)|Estimate file space usage.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[env](https://github.com/uutils/coreutils)|[**en-US**](/completions/env/language/en-US.json)<br>[**zh-CN(16.67%)**](/completions/env/language/zh-CN.json)|Set each NAME to VALUE in the environment and run COMMAND.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[factor](https://github.com/uutils/coreutils)|[**en-US**](/completions/factor/language/en-US.json)<br>[**zh-CN(20%)**](/completions/factor/language/zh-CN.json)|Print the prime factors of the given NUMBER(s).<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[fmt](https://github.com/uutils/coreutils)|[**en-US**](/completions/fmt/language/en-US.json)<br>[**zh-CN(11.76%)**](/completions/fmt/language/zh-CN.json)|Reformat paragraphs from input files (or stdin) to stdout.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[fnm](https://github.com/Schniz/fnm)|[**en-US**](/completions/fnm/language/en-US.json)<br>[**zh-CN(8.33%)**](/completions/fnm/language/zh-CN.json)|Fast and simple Node.js version manager, built in Rust.|
|[fold](https://github.com/uutils/coreutils)|[**en-US**](/completions/fold/language/en-US.json)<br>[**zh-CN(28.57%)**](/completions/fold/language/zh-CN.json)|Writes each file (or standard input if no files are given) to standard output whilst breaking long lines.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[git](https://git-scm.com)|[**en-US**](/completions/git/language/en-US.json)<br>[**zh-CN(94.93%)**](/completions/git/language/zh-CN.json)|Git - Version control system.|
|[hashsum](https://github.com/uutils/coreutils)|[**en-US**](/completions/hashsum/language/en-US.json)<br>[**zh-CN(6.45%)**](/completions/hashsum/language/zh-CN.json)|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[head](https://github.com/uutils/coreutils)|[**en-US**](/completions/head/language/en-US.json)<br>[**zh-CN(22.22%)**](/completions/head/language/zh-CN.json)|Print the first 10 lines of each 'FILE' to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[join](https://github.com/uutils/coreutils)|[**en-US**](/completions/join/language/en-US.json)<br>[**zh-CN(11.11%)**](/completions/join/language/zh-CN.json)|For each pair of input lines with identical join fields, write a line to standard output.<br> The default join field is the first, delimited by blanks.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[kubectl](https://kubernetes.io/docs/reference/kubectl/)|[**en-US**](/completions/kubectl/language/en-US.json)<br>[**zh-CN(100%)**](/completions/kubectl/language/zh-CN.json)|Kubernetes, also known as K8s, is an open source system for automating deployment, scaling, and management of containerized applications.<br> kubectl is its command-line tool.|
|[link](https://github.com/uutils/coreutils)|[**en-US**](/completions/link/language/en-US.json)<br>[**zh-CN(100%)**](/completions/link/language/zh-CN.json)|Call the link function to create a link named FILE2 to an existing FILE1.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[ln](https://github.com/uutils/coreutils)|[**en-US**](/completions/ln/language/en-US.json)<br>[**zh-CN(11.76%)**](/completions/ln/language/zh-CN.json)|Make links between files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[md5sum](https://github.com/uutils/coreutils)|[**en-US**](/completions/md5sum/language/en-US.json)<br>[**zh-CN(14.29%)**](/completions/md5sum/language/zh-CN.json)|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[mise](https://github.com/jdx/mise)|[**en-US**](/completions/mise/language/en-US.json)<br>[**zh-CN(3.39%)**](/completions/mise/language/zh-CN.json)|mise is a task runner and dev tools manager for any language.|
|[mktemp](https://github.com/uutils/coreutils)|[**en-US**](/completions/mktemp/language/en-US.json)<br>[**zh-CN(20%)**](/completions/mktemp/language/zh-CN.json)|Create a temporary file or directory.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[ngrok](https://ngrok.com/)|[**en-US**](/completions/ngrok/language/en-US.json)<br>[**zh-CN(100%)**](/completions/ngrok/language/zh-CN.json)|ngrok - Unified Ingress Platform for developers.<br> Connect localhost to the internet for testing applications and APIs.|
|[nl](https://github.com/uutils/coreutils)|[**en-US**](/completions/nl/language/en-US.json)<br>[**zh-CN(6.67%)**](/completions/nl/language/zh-CN.json)|Number lines of files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[npm](https://www.npmjs.com/)|[**en-US**](/completions/npm/language/en-US.json)<br>[**zh-CN(100%)**](/completions/npm/language/zh-CN.json)|npm - package manager.|
|[nproc](https://github.com/uutils/coreutils)|[**en-US**](/completions/nproc/language/en-US.json)<br>[**zh-CN(33.33%)**](/completions/nproc/language/zh-CN.json)|Print the number of cores available to the current process.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[nrm](https://github.com/Pana/nrm)|[**en-US**](/completions/nrm/language/en-US.json)<br>[**zh-CN(100%)**](/completions/nrm/language/zh-CN.json)|nrm - npm registry manager.|
|[numfmt](https://github.com/uutils/coreutils)|[**en-US**](/completions/numfmt/language/en-US.json)<br>[**zh-CN(7.69%)**](/completions/numfmt/language/zh-CN.json)|Convert numbers from/to human-readable strings.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[nvm](https://github.com/nvm-sh/nvm)|[**en-US**](/completions/nvm/language/en-US.json)<br>[**zh-CN(100%)**](/completions/nvm/language/zh-CN.json)|nvm - Node Version Manager.|
|[od](https://github.com/uutils/coreutils)|[**en-US**](/completions/od/language/en-US.json)<br>[**zh-CN(4.65%)**](/completions/od/language/zh-CN.json)|Dump files in octal and other formats.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[oh-my-posh](https://ohmyposh.dev)|[**en-US**](/completions/oh-my-posh/language/en-US.json)<br>[**zh-CN(7.41%)**](/completions/oh-my-posh/language/zh-CN.json)|oh-my-posh is a cross platform tool to render your prompt.|
|[paste](https://github.com/uutils/coreutils)|[**en-US**](/completions/paste/language/en-US.json)<br>[**zh-CN(28.57%)**](/completions/paste/language/zh-CN.json)|Write lines consisting of the sequentially corresponding lines from each 'FILE', separated by 'TAB's, to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils).|
|[pdm](https://github.com/pdm-project/pdm)|[**en-US**](/completions/pdm/language/en-US.json)<br>[**zh-CN(0.31%)**](/completions/pdm/language/zh-CN.json)|A modern Python package and dependency manager supporting the latest PEP standards.|
|[pip](https://github.com/pypa/pip)|[**en-US**](/completions/pip/language/en-US.json)<br>[**zh-CN(99.42%)**](/completions/pip/language/zh-CN.json)|pip - Python Package Manager.|
|[pnpm](https://pnpm.io/)|[**en-US**](/completions/pnpm/language/en-US.json)<br>[**zh-CN(100%)**](/completions/pnpm/language/zh-CN.json)|pnpm - Package Manager.|
|[powershell](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh?view=powershell-5.1)|[**en-US**](/completions/powershell/language/en-US.json)<br>[**zh-CN(100%)**](/completions/powershell/language/zh-CN.json)|Windows PowerShell CLI. (powershell.exe)|
|[psc](https://github.com/abgox/PSCompletions)|[**en-US**](/completions/psc/language/en-US.json)<br>[**zh-CN(97.63%)**](/completions/psc/language/zh-CN.json)|PSCompletions module's completion tips.<br> It can only be updated, not removed.<br> If removed, it will be automatically added again.|
|[pwsh](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh)|[**en-US**](/completions/pwsh/language/en-US.json)<br>[**zh-CN(100%)**](/completions/pwsh/language/zh-CN.json)|PowerShell CLI. (pwsh.exe)|
|[python](https://www.python.org)|[**en-US**](/completions/python/language/en-US.json)<br>[**zh-CN(100%)**](/completions/python/language/zh-CN.json)|python - command-line.|
|[scoop](https://scoop.sh)|[**en-US**](/completions/scoop/language/en-US.json)<br>[**zh-CN(100%)**](/completions/scoop/language/zh-CN.json)|Scoop - Software Manager.|
|[scoop-install](https://github.com/abgox/scoop-tools)|[**en-US**](/completions/scoop-install/language/en-US.json)<br>[**zh-CN(100%)**](/completions/scoop-install/language/zh-CN.json)|A PowerShell script that allows you to add Scoop configurations to use a replaced url instead of the original url when installing the app in Scoop.|
|[scoop-update](https://github.com/abgox/scoop-tools)|[**en-US**](/completions/scoop-update/language/en-US.json)<br>[**zh-CN(100%)**](/completions/scoop-update/language/zh-CN.json)|A PowerShell script that allows you to add Scoop configurations to use a replaced url instead of the original url when updating the app in Scoop.|
|[sfsu](https://github.com/winpax/sfsu)|[**en-US**](/completions/sfsu/language/en-US.json)<br>[**zh-CN(6.67%)**](/completions/sfsu/language/zh-CN.json)|Scoop utilities that can replace the slowest parts of Scoop, and run anywhere from 30-100 times faster.|
|[uv](https://docs.astral.sh/uv/)|[**en-US**](/completions/uv/language/en-US.json)<br>[**zh-CN(10%)**](/completions/uv/language/zh-CN.json)|An extremely fast Python package and project manager, written in Rust.|
|[volta](https://volta.sh)|[**en-US**](/completions/volta/language/en-US.json)<br>[**zh-CN(100%)**](/completions/volta/language/zh-CN.json)|volta - Accessible JavaScript Tool Manager.|
|[winget](https://github.com/microsoft/winget-cli)|[**en-US**](/completions/winget/language/en-US.json)<br>[**zh-CN(100%)**](/completions/winget/language/zh-CN.json)|WinGet - Windows package manager.|
|[wsh](https://github.com/wavetermdev/waveterm)|[**en-US**](/completions/wsh/language/en-US.json)<br>[**zh-CN(3.45%)**](/completions/wsh/language/zh-CN.json)|wsh is a small utility that lets you do cool things with Wave Terminal, right from the command line.|
|[wsl](https://github.com/microsoft/WSL)|[**en-US**](/completions/wsl/language/en-US.json)<br>[**zh-CN(100%)**](/completions/wsl/language/zh-CN.json)|WSL - Windows Subsystem for Linux.|
|[wt](https://github.com/microsoft/terminal)|[**en-US**](/completions/wt/language/en-US.json)<br>[**zh-CN(100%)**](/completions/wt/language/zh-CN.json)|Windows Terminal command line.<br> You can use it to start a terminal.|
|[yarn](https://classic.yarnpkg.com/)|[**en-US**](/completions/yarn/language/en-US.json)<br>[**zh-CN(100%)**](/completions/yarn/language/zh-CN.json)|yarn - package manager.|
|...|...&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|...|
<!-- prettier-ignore-end -->
