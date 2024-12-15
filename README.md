<p align="center">
    <h1 align="center">✨<a href="https://pscompletions.pages.dev">PSCompletions(psc)</a>✨</h1>
</p>

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

- [`PowerShell`](https://github.com/PowerShell/PowerShell): A cross-platform PowerShell. Start it by running `pwsh`/`pwsh.exe`.

- [`Windows PowerShell`](https://learn.microsoft.com/powershell/scripting/what-is-windows-powershell): A PowerShell which is built-in on Windows system. Start it by running `powershell`/`powershell.exe`.

---

- A completion manager in `PowerShell` for better and simpler use completions.
  > It can also be used in `Windows PowerShell`, but it's a better choice to use `PowerShell`.
- [Manage completions together.](#available-completions-list "Click it to view the completion list that can be added.")
- Switch between languages(`en-US`,`zh-CN`,...) freely.
- Sort completion items dynamically by frequency of use.
- [Provide a more powerful completion menu.](#about-completion-menu "Click it to learn more about it.")
- [Combined with argc-completions.](https://pscompletions.pages.dev/tips/pscompletions-and-argc-completions "Click to see what you need to do.")
  - [sigoden/argc-completions](https://github.com/sigoden/argc-completions)

**If `PSCompletions` is helpful to you, please consider giving it a star ⭐.**

## What's new

- See the [CHANGELOG](./module/CHANGELOG.md) for details.

## FAQ

- See the [FAQ](https://pscompletions.pages.dev/FAQ).

## How to install

1. Start `PowerShell`.
2. Install module:

   - Don't omit `-Scope CurrentUser` unless you're sure you'll always start `PowerShell` with administrator permissions.
     ```powershell
     Install-Module PSCompletions -Scope CurrentUser
     ```
   - Install silently:
     ```powershell
     Install-Module PSCompletions -Scope CurrentUser -Repository PSGallery -Force
     ```

3. Import module:
   ```powershell
   Import-Module PSCompletions
   ```
   - If you don't want to import the `PSCompletions` module every time when you start `PowerShell`, you can write it to `$PROFILE`.
     ```powershell
     echo "Import-Module PSCompletions" >> $PROFILE
     ```

> [!warning]
>
> - The `Set-PSReadLineKeyHandler -Key <key> -Function MenuComplete` can no longer be used.
> - It will cause the `PSCompletions` menu to not work correctly.
> - For detail, see [About the completion trigger key](#about-the-completion-trigger-key).

## How to uninstall

1. Start `PowerShell`.
2. Uninstall module:
   ```powershell
   Uninstall-Module PSCompletions
   ```

## How to use

### [Available Completions](#available-completions-list "All completions that can be added at present. More completions are adding!")

> If it doesn't include the completion you want, you can [submit an issue](https://github.com/abgox/PSCompletions/issues "Click to submit an issue.").

- Take `git` as an example.

1. `psc add git`
2. Then you can enter `git`, press `Space` and `Tab` key to get command completion.
3. For more usages on `psc`, you just need to enter `psc`, press `Space` and `Tab` key, and you will get all usages of `psc` by reading [the completion tip](#about-completion-tip).

## Demo

![demo](https://pscompletions.pages.dev/demo.gif)

## Contribution

- See the [CONTRIBUTING](./.github/contributing.md) for details.

## Tips

### About the completion trigger key

- `PSCompletions` uses the `Tab` key by default.
- You can set it by running `psc menu config trigger_key <key>`.

> [!warning]
>
> - The `Set-PSReadLineKeyHandler -Key <key> -Function MenuComplete` can no longer be used.
> - It will cause the `PSCompletions` menu to not work correctly.
>
> ```diff
>
> + Import-Module PSCompletions
>
> - Set-PSReadLineKeyHandler -Key <key> -Function MenuComplete
> ```

### About completion update

- When `PSCompletions` module is imported after starting `PowerShell`, it will start a background job to check for the completion status of the remote repository.
- After getting the update, `PSCompletions` will show the latest status of the completions in the next time.

### About option completion

- `Optional Completion`: some command completions that like `-*`, such as `--global` in `git config --global`.
- You should use option completion first.
- Taking `git` as an example, if you want to enter `git config user.name --global xxx`, you should use `--global` completion first, and then use `user.name`, and then enter the name `xxx` .

### About completion menu

- In addition to the built-in completion menu of `PowerShell`, `PSCompletions` module also provides a more powerful completion menu.

  - Setting: `psc menu config enable_menu 1` (Default: `1`)

- The module's completion menu is based on [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion) realization idea, thanks!

- Available Windows environment:
  - `PowerShell` <img src="https://img.shields.io/badge/module%20version-v4.0.0+-4CAF50" alt="v4.0.0+ support" />
  - `Windows PowerShell` <img src="https://img.shields.io/badge/module%20version-v4.1.0+-4CAF50" alt="v4.1.0+ support" />
    - Due to rendering problems of `Windows PowerShell`, the border style of the completion menu cannot be customized.
      - If you need to customize it, use `PowerShell`.
- Some keys in the module's completion menu.

  1. Apply the selected completion item: `Enter`
     - You can also use `Tab` or `Space` when there's only one completion.
  2. Delete filter characters: `Backspace`
  3. Exit the completion menu: `Esc` / `Ctrl + c`
     - You can also use `Backspace` when there're no characters in the filter area.
  4. Select completion item:

     | Select previous item | Select next item |
     | :------------------: | :--------------: |
     |         `Up`         |      `Down`      |
     |        `Left`        |     `Right`      |
     |    `Shift + Tab`     |      `Tab`       |
     |   `Shift + Space`    |     `Space`      |
     |      `Ctrl + u`      |    `Ctrl + d`    |
     |      `Ctrl + p`      |    `Ctrl + n`    |

- All configurations of it, you can trigger completion by running `psc menu`, then learn about them by [the completion tip](#about-completion-tip).
  - For configured values, `1` means `true` and `0` means `false`. (It applies to all configurations of `PSCompletions`)

#### About menu enhance <img src="https://img.shields.io/badge/module%20version-v4.2.0+-4CAF50" alt="v4.2.0+ support" />

- Setting: `psc menu config enable_menu_enhance 1` (Default: `1`)
- Now, `PSCompletions` has two completion implementations.

  1. [`Register-ArgumentCompleter`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter)
     - <img src="https://img.shields.io/badge/module%20version-v4.1.0-4CAF50" alt="v4.1.0 support" /> : It's used.
     - <img src="https://img.shields.io/badge/module%20version-v4.2.0+-4CAF50" alt="v4.2.0+ support" />: It's optional.
       - You can use it by running `psc menu config enable_menu_enhance 0`.
       - It's not recommended. It only works for completions added by `psc add`.
  2. [`Set-PSReadLineKeyHandler`](https://learn.microsoft.com/powershell/module/psreadline/set-psreadlinekeyhandler)
     - <img src="https://img.shields.io/badge/module%20version-v4.2.0+-4CAF50" alt="v4.2.0+ support" />: It's used by default.
       - Requires: `enable_menu` and `enable_menu_enhance` both set to `1`.
     - It no longer needs to loop through registering `Register-ArgumentCompleter` for all completions, which theoretically makes loading faster.
     - It use [`TabExpansion2`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/tabexpansion2) to manage completions globally, not limited to those added by `psc add`.
       - For example:
         - Path completion such as `cd`/`.\`/`..\`/`~\`/... in `PowerShell`.
         - Build-in commands such as `Get-*`/`Set-*`/`New-*`/... in `PowerShell`.
         - Completion registered by [`Register-ArgumentCompleter`](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/register-argumentcompleter)
         - [Combined with argc-completions.](https://pscompletions.pages.dev/tips/pscompletions-and-argc-completions)
         - Completion registered by cli or module.
         - ...

### About special symbols

> [!NOTE]
>
> - Due to future changes in Windows Terminal, 😄🤔😎 will not be displayed properly in the completion menu, so these three default special symbols will change.
> - Related issue: https://github.com/microsoft/terminal/issues/18242
> - The changes are as follows:
>   - `😄` => `»`
>   - `🤔` => `?`
>   - `😎` => `!`

- Special symbols after the completion item are used to let you know in advance if completions are available before you press the `Tab` key.

  - They only exist in completions added via `psc add`.
  - You can hide them by replacing them with the empty string.
    - `psc menu symbol SpaceTab ""`
    - `psc menu symbol OptionTab ""`
    - `psc menu symbol WriteSpaceTab ""`

- `»`,`?`,`!` : If there are multiple, you can choose the effect of one of them.
  - Define them:
    - `Normal Completion`: Sub-commands. Such as `add`/`pull`/`push`/`commit`/... in `git`.
    - `Optional Completion`: Optional parameters. Such as `-g`/`-u`/... in `git add`.
    - `General Optional Completion`: General optional parameters that can be used with any command. Such as `--help`/... in `git`.
  - `»` : It means that after you apply it, you can press `Space` and `Tab` key to continue to get `Normal Completion` or `Optional Completion`.
    - It will appear only when there's `Normal Completion` or `Optional Completion`.
    - It can be customized by running `psc menu symbol SpaceTab <symbol>`
  - `?` : It means that after you apply it (`Optional Completion`), you can press `Space` and `Tab` key to continue to get other `Optional Completion`.
    - `General Optional Completion` use also this symbol.
    - It can be customized by running `psc menu symbol OptionTab <symbol>`
  - `!` : It means that after you apply it (`Optional Completion` or `General Optional Completion`), you can press `Space` and enter a string, then press `Space` and `Tab` key to continue to get other `Optional Completion` or `General Optional Completion`.
    - If the string has Spaces, Please use `"`(quote) or `'`(single quote) to wrap it. e.g. `"test content"`
    - If there's also `»`, it means that there's `Normal Completion`, you can press `Space` and `Tab` key to continue to get them without entering a string.
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

## Support

![Support](https://abgox.pages.dev/support.png)

## Available Completions List

- Guide
  - **`Completion`** ：Click to view to the official website of the command. Sort by first letter(0-9,a-z).
    - Special case: `abc(a)`, it means that you need to download it by `psc add abc`, but by default `a` is used instead of `abc` to trigger the completion.
  - **`Language`**: Supported Languages, and Translation Progress.
    - The translation progress is compared to `en-US`.
  - **`Description`**: Command Description.

<!-- prettier-ignore-start -->
|Completion|Language|Description|
|:-:|-|-|
|[7z](https://7-zip.org/)|**en-US**<br>**zh-CN(100%)**|The command line cli of 7-Zip|
|[arch](https://github.com/uutils/coreutils)|**en-US**<br>**zh-CN(100%)**|Display machine architecture.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[b2sum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(15.38%)~~**|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[b3sum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(15.38%)~~**|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[base32](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[base64](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[basename](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Print NAME with any leading directory components removed.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[basenc](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(18.18%)~~**|Encode/decode data and print to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[bun](https://bun.sh)|**en-US**<br>**zh-CN(100%)**|Bun - JavaScript all-in-one toolkit|
|[cargo](https://rustwiki.org/en/cargo)|**en-US**<br>**zh-CN(100%)**|cargo - Rust package manager|
|[chfs](http://iscute.cn/chfs)|**en-US**<br>**zh-CN(100%)**|CuteHttpFileServer - A free, HTTP protocol file sharing server cross-platform file sharing server|
|[choco](https://chocolatey.org/)|**en-US**<br>**zh-CN(100%)**|choco(chocolatey) - Software Manager|
|[cksum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(17.14%)~~**|Print CRC and size for each file.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[comm](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(27.27%)~~**|Compare two sorted files line by line.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[conda](https://github.com/conda/conda)|**en-US**<br>**zh-CN(100%)**|conda - binary package and environment manager|
|[csplit](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(19.35%)~~**|Split a file into sections determined by context lines.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[cut](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(16.22%)~~**|Print specified byte or field columns from each line of stdin or the input files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[date](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(14.29%)~~**|Print or set the system date and time.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[dd](https://github.com/uutils/coreutils)|**en-US**<br>**zh-CN(100%)**|Copy, and optionally convert, a file system resource.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[deno](https://deno.com/)|**en-US**<br>**zh-CN(100%)**|Deno - A secure runtime for JavaScript and TypeScript.|
|[df](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(6.67%)~~**|Show information about the file system on which each FILE resides, or all file systems by default.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[dircolors](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(31.58%)~~**|Output commands to set the LS_COLORS environment variable.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[dirname](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(54.55%)~~**|Strip last component from file name.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[docker](https://www.docker.com)|**en-US**<br>**zh-CN(100%)**|docker - Container Application Development|
|[du](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(5.83%)~~**|Estimate file space usage.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[env](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(16.67%)~~**|Set each NAME to VALUE in the environment and run COMMAND.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[factor](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(60%)~~**|Print the prime factors of the given NUMBER(s).<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[fmt](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(14.63%)~~**|Reformat paragraphs from input files (or stdin) to stdout.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[fnm](https://github.com/Schniz/fnm)|**en-US**<br>**~~zh-CN(14.52%)~~**|Fast and simple Node.js version manager, built in Rust.|
|[fold](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Writes each file (or standard input if no files are given) to standard output whilst breaking long lines.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[git](https://git-scm.com)|**en-US**<br>**zh-CN(100%)**|Git - Version control system|
|[hashsum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(8.57%)~~**|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[head](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(24%)~~**|Print the first 10 lines of each 'FILE' to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[join](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(13.04%)~~**|For each pair of input lines with identical join fields, write a line to standard output.<br> The default join field is the first, delimited by blanks.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[kubectl](https://kubernetes.io/docs/reference/kubectl/)|**en-US**<br>**zh-CN(100%)**|Kubernetes, also known as K8s, is an open source system for automating deployment, scaling, and management of containerized applications.<br> kubectl is its command-line tool.|
|[link](https://github.com/uutils/coreutils)|**en-US**<br>**zh-CN(100%)**|Call the link function to create a link named FILE2 to an existing FILE1.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[ln](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(14.63%)~~**|Make links between files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[md5sum](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(17.14%)~~**|Compute and check message digests.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[mktemp](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(24%)~~**|Create a temporary file or directory.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[ngrok](https://ngrok.com/)|**en-US**<br>**zh-CN(100%)**|ngrok - Unified Ingress Platform for developers.<br> Connect localhost to the internet for testing applications and APIs.|
|[nl](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(6.58%)~~**|Number lines of files.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[npm](https://www.npmjs.com/)|**en-US**<br>**zh-CN(100%)**|npm - package manager|
|[nproc](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(46.15%)~~**|Print the number of cores available to the current process.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[nrm](https://github.com/Pana/nrm)|**en-US**<br>**zh-CN(100%)**|nrm - npm registry manager|
|[numfmt](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(8.57%)~~**|Convert numbers from/to human-readable strings.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[nvm](https://github.com/nvm-sh/nvm)|**en-US**<br>**zh-CN(100%)**|nvm - Node Version Manager|
|[od](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(7.41%)~~**|Dump files in octal and other formats.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[paste](https://github.com/uutils/coreutils)|**en-US**<br>**~~zh-CN(33.33%)~~**|Write lines consisting of the sequentially corresponding lines from each 'FILE', separated by 'TAB's, to standard output.<br> Completion was written based on [uutils/coreutils](https://github.com/uutils/coreutils)|
|[pdm](https://github.com/pdm-project/pdm)|**en-US**<br>**~~zh-CN(0.82%)~~**|A modern Python package and dependency manager supporting the latest PEP standards|
|[pip](https://github.com/pypa/pip)|**en-US**<br>**zh-CN(100%)**|pip - Python Package Manager|
|[pnpm](https://pnpm.io/)|**en-US**<br>**zh-CN(100%)**|pnpm - Package Manager|
|[powershell](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh?view=powershell-5.1)|**en-US**<br>**zh-CN(100%)**|Windows PowerShell CLI. (powershell.exe)|
|[psc](https://github.com/abgox/PSCompletions)|**en-US**<br>**zh-CN(100%)**|PSCompletions module's completion tips.<br> It can only be updated, not removed.<br> If removed, it will be automatically added again.|
|[pwsh](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh)|**en-US**<br>**zh-CN(100%)**|PowerShell CLI. (pwsh.exe)|
|[python](https://www.python.org)|**en-US**<br>**zh-CN(100%)**|python - command-line|
|[scoop](https://scoop.sh)|**en-US**<br>**zh-CN(100%)**|Scoop - Software Manager|
|[sfsu](https://github.com/winpax/sfsu)|**en-US**<br>**~~zh-CN(10.77%)~~**|Scoop utilities that can replace the slowest parts of Scoop, and run anywhere from 30-100 times faster|
|[volta](https://volta.sh)|**en-US**<br>**zh-CN(100%)**|volta - Accessible JavaScript Tool Manager|
|[winget](https://github.com/microsoft/winget-cli)|**en-US**<br>**zh-CN(100%)**|WinGet - Windows package manager|
|[wsl](https://github.com/microsoft/WSL)|**en-US**<br>**zh-CN(100%)**|WSL - Windows Subsystem for Linux|
|[wt](https://github.com/microsoft/terminal)|**en-US**<br>**zh-CN(100%)**|Windows Terminal command line.<br> You can use it to start a terminal.|
|[yarn](https://classic.yarnpkg.com/)|**en-US**<br>**zh-CN(100%)**|yarn - package manager|
|...|...&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|...|
<!-- prettier-ignore-end -->
