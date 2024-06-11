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

-   `PowerShell`: A Cross-platform PowerShell. Start it in command line by running `pwsh`.

-   `Windows PowerShell`: A PowerShell which is built-in on Windows systems. Start it in command line by running `powershell`.

---

-   A completion manager in `PowerShell` for better and simpler use completions.
    > It can also be used in `Windows PowerShell`.(Not Recommend)
-   [Manage completions together.](#available-completions-list 'Click it to view the completion list that can be added !')
-   Switch between languages(`en-US`,`zh-CN`,...) freely.
-   Sort completion tab dynamically by frequency of use.

**If this project is helpful to you, please consider giving it a star ⭐.**

## How to install

1. Start `PowerShell`
2. `Install-Module PSCompletions -Scope CurrentUser`
3. `Import-Module PSCompletions`
    - `echo "Import-Module PSCompletions" >> $PROFILE`
    - So you don't have to import the module every time you open PowerShell.

## How to uninstall

1. Start `PowerShell`
2. `Uninstall-Module PSCompletions`

## How to use(e.g. `git`)

### [Available Completions](#available-completions-list 'All completions that can be added at present. More completions are adding!')

-   If it doesn't include the completion you want, you can [submit an issue](https://github.com/abgox/PSCompletions/issues 'Click to submit an issue') and I will consider adding it.

1. `psc add git`
2. Then you can enter `git` and press `Space` `Tab` to get command completion.
3. For more commands on `psc`, you can learn by entering `psc` and then pressing `Space` `Tab`.

## Demo

![demo](https://abgop.netlify.app/pscompletions/demo.gif)

## Tips

### About the completion trigger key

-   The module uses the `Tab` key by default.
-   You can set it by running `Set-PSReadLineKeyHandler <key> MenuComplete`.

### About completion update

-   When the module is imported after opening `PowerShell`, `PSCompletions` will start a background job to check for the completion status of the remote repository.
-   After getting the update, `PSCompletions` will show the latest status of the completions in the next time.

### About completion menu

-   The module's completion menu provided by the module is based on [PS-GuiCompletion](https://github.com/nightroman/PS-GuiCompletion) realization idea, thanks!
-   It can only be used in PowerShell(pwsh) under Windows.
-   Some keys in the completion menu provided by the module.

    1. Apply the selected completion item: `Enter`
    2. Delete filter characters: `Backspace`
    3. Exit the completion menu: `ESC` / `Ctrl + c`
        - When there are no characters in the filter area, you can also use `Backspace` key to exit the completion menu.
    4. Select completion item:

        | Select previous item | Select next item |
        | :------------------: | :--------------: |
        |         `Up`         |      `Down`      |
        |        `Left`        |     `Right`      |
        |    `Shift + Tab`     |      `Tab`       |
        |   `Shift + Space`    |     `Space`      |
        |      `Ctrl + u`      |    `Ctrl + d`    |
        |      `Ctrl + p`      |    `Ctrl + n`    |

-   All configurations of it, you can trigger completion by running `psc menu`, then learn about them by completion tip.

### About special symbols

-   😄🤔😎 : If there are multiple, you can choose the effect of one of them.
    -   😄 : It means that after you apply it, you can press `Space` and `Tab` key to continue to get command completions.(Normal or optional completions)
        -   It can be customized by running `psc menu symbol SpaceTab <symbol>`
    -   🤔 : It means that after you apply it (option completion), you can press `Space` and `Tab` key to continue to get option completions. (e.g. `--verbose`)
        -   It can be customized by running `psc menu symbol OptionTab <symbol>`
    -   😎 : It means that after you apply it (option completion), you can press `Space` and enter a string, then press `Space` and `Tab` key to continue to get the rest of option completions.
        -   If the string has Spaces, Please use "" or '' to wrap it. e.g. 'test content'
        -   If there is also 😄, it means that there are some strings to complete, you can press `Space` and `Tab` key to continue to get command completions without entering a string.
        -   It can be customized by running `psc menu symbol WriteSpaceTab <symbol>`
    -   Completion of generic options can also be triggered if there is one or more generic option completion.
    -   All complements can be triggered by pressing the `Tab` key after entering a part.
    -   If you don't need or want to see these symbols, you can hide them by replacing them with the empty string.
        -   e.g. `psc menu symbol SpaceTab ""`

### About language

-   `Global language`: Default to the language of current system.
    -   You can show it by running `psc config language`
    -   You can change it by running `psc config language zh-CN`
-   `Completion language`: The language set for the specified completion.
    -   e.g. `psc completion git language en-US`.
-   `Available language`: In the completion `config.json` file, there is a `language` attribute whose value is a list of available languages.

#### Determine language

1. Get the specified language:
    - If there is `Completion language`,use it.
    - If not, use `Global language`.
2. Determine the final language:
    - Determine whether the value of the first step exists in `Available language`.
    - If it exists, use it.
    - If not, use the first of the `Available language`. (It's usually `en-US`)

### About path completion

-   Take `git` for example, when entering `git add`, pressing the `Space` and `Tab` keys, path completion will not be triggered, only completion provided by the module will be triggered.
-   If you want to trigger path completion, you need to enter a content.
-   If the content matches this regex rule `^\.*[\\/].*`, it will get the path completion, which is PowerShell completion.
-   e.g.
    -   Please enter `./` or `.\` and press `Tab` key to get path completion for the **subdirectory** or **file**.
    -   Please enter `../` or `..\` and press `Tab` key to get path completion for the **parent directory** or **file**.
    -   Please enter `/` or `\` and press `Tab` key to get path completion for the **sibling directory**.
-   So you can enter `git add ./` and then press `Tab` key to get the path completion.

## Available Completions List

-   Guide
    -   **`Completion`** ：Click to view to the official website of the command. Sort by first letter(0-9,a-z).
        -   Special case: `abc(a)`, it means that you need to download it by `psc add abc`, but by default `a` is used instead of `abc` to trigger the completion.
    -   **`Language`**: Supported Languages, and Translation Progress.
        -   The translation progress is compared to `en-US`
        -   If it is greater than `100%`, it means that the current language has some redundant completion items and should be cleaned.
    -   **`Description`**: Command Description.

|Completion|Language|Description|
|:-:|-|-|
|[7z](https://7-zip.org/)|`en-US`<br>`zh-CN(100%)`|The command line cli of 7-Zip|
|[bun](https://bun.sh)|`en-US`<br>`zh-CN(100%)`|Bun - JavaScript all-in-one toolkit|
|[cargo](https://rustwiki.org/en/cargo)|`en-US`<br>`zh-CN(100%)`|cargo - Rust package manager|
|[chfs](http://iscute.cn/chfs)|`en-US`<br>`zh-CN(100%)`|CuteHttpFileServer - A free, HTTP protocol file sharing server cross-platform file sharing server|
|[choco](https://chocolatey.org/)|`en-US`<br>`zh-CN(100%)`|choco(chocolatey) - Software Manager|
|[conda](https://github.com/conda/conda)|`en-US`<br>`zh-CN(100%)`|conda - binary package and environment manager|
|[deno](https://deno.com/)|`en-US`<br>`zh-CN(100%)`|Deno - A secure runtime for JavaScript and TypeScript.|
|[docker](https://www.docker.com)|`en-US`<br>`zh-CN(100%)`|docker - Container Application Development|
|[git](https://git-scm.com)|`en-US`<br>`zh-CN(100%)`|Git - Version control system|
|[kubectl](https://kubernetes.io/docs/reference/kubectl/)|`en-US`<br>`zh-CN(100%)`|Kubernetes, also known as K8s, is an open source system for automating deployment, scaling, and management of containerized applications.<br> kubectl is its command-line tool.|
|[ngrok](https://ngrok.com/)|`en-US`|ngrok - Unified Ingress Platform  for developers<br> Connect localhost to the internet for testing applications and APIs|
|[npm](https://www.npmjs.com/)|`en-US`<br>`zh-CN(100%)`|npm - package manager|
|[nrm](https://github.com/Pana/nrm)|`en-US`<br>`zh-CN(100%)`|nrm - npm registry manager|
|[nvm](https://github.com/nvm-sh/nvm)|`en-US`<br>`zh-CN(100%)`|nvm - Node Version Manager|
|[pip](https://github.com/pypa/pip)|`en-US`<br>`zh-CN(100%)`|pip - Python Package Manager|
|[pnpm](https://pnpm.io/)|`en-US`<br>`zh-CN(100%)`|pnpm - Package Manager|
|[psc](https://github.com/abgox/PSCompletions)|`en-US`<br>`zh-CN(100%)`|PSCompletions module's completion tips.<br> It can only be updated, not removed.<br> If removed, it will be automatically added again.|
|[python](https://www.python.org)|`en-US`<br>`zh-CN(100%)`|python - command-line|
|[scoop](https://scoop.sh)|`en-US`<br>`zh-CN(100%)`|Scoop - Software Manager|
|[volta](https://volta.sh)|`en-US`<br>`zh-CN(100%)`|volta - Accessible JavaScript Tool Manager|
|[winget](https://github.com/microsoft/winget-cli)|`en-US`<br>`zh-CN(100%)`|WinGet - Windows package manager|
|[wsl](https://github.com/microsoft/WSL)|`en-US`<br>`zh-CN(100%)`|WSL - Windows Subsystem for Linux|
|[wt](https://github.com/microsoft/terminal)|`en-US`<br>`zh-CN(100%)`|Windows terminal command line|
|[yarn](https://classic.yarnpkg.com/)|`en-US`<br>`zh-CN(100%)`|yarn - package manager|
|...|...&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;|...|
