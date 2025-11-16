[English](./CHANGELOG.md) | [简体中文](./CHANGELOG.zh-CN.md)

## 5.11.0 (2025/11/16)

- 为 PSCompletions 的补全菜单添加按键绑定 ([#107](https://github.com/abgox/PSCompletions/issues/107))

  - 向上: `Ctrl + k`
  - 向下: `Ctrl + j`

## 5.10.1 (2025/11/05)

在模块提供的补全菜单中，允许在任意子命令之后获取补全 ([#102](https://github.com/abgox/PSCompletions/issues/102))

- 举个例子
  - 如果已经输入了 `git clone git@github.com:abgox/PSCompletions.git`
  - 此时，还想去补全 `--depth 1 `，
  - 那么，可以将光标移动到 `clone` 之后，然后就可以正常获取 `--depth`
- 需要注意:
  - 它只在模块提供的补全菜单中有效
  - 它的实现方式是通过将光标之前的内容作为输入，因此不会过滤光标之后的重复补全项

## 5.9.2 (2025/11/02)

- 修复了默认忽略大小写导致的补全排序错误

## 5.9.1 (2025/11/01)

- 修复了相同名称但大小写不同的参数重叠问题

## 5.9.0 (2025/10/18)

- 允许在过滤中使用通配符 `*` 和 `?`
  - 命令: `psc menu config enable_prefix_match_in_filter 0`
  - 代价: 无法匹配原始的 `*` 和 `?` 字符
- 优化了不同补全类型的处理逻辑
  - 这让 `completion_suffix` 配置项的生效范围更加精确

## 5.8.0 (2025/10/15)

- 添加配置项 `enable_hooks_tip` ([#96](https://github.com/abgox/PSCompletions/issues/96))
  - 对于全局设置: `psc menu config enable_hooks_tip 1`
  - 对于特定补全: `psc completion git enable_hooks_tip 1`
- 添加配置项 `completions_confirm_limit` ([#83](https://github.com/abgox/PSCompletions/issues/83))
  - 命令: `psc menu config completions_confirm_limit 1000`
- 添加了对于 `-?`，`-h`，`--help` 参数的支持
  - 命令: `psc` | `psc -?` | `psc -h` | `psc --help`
  - 以上四种命令的输出结果相同
- 移除了对内置命令的提示信息的特殊处理 ([#97](https://github.com/abgox/PSCompletions/issues/97))
- 其他的优化和修复

## 5.7.0 (2025/10/11)

- 添加配置项 `completion_suffix` ([#91](https://github.com/abgox/PSCompletions/issues/91))
- 命令: `psc menu config completion_suffix " "`

## 5.6.9 (2025/9/20)

- 在模块中禁用严格模式 ([#88](https://github.com/abgox/PSCompletions/issues/88))

## 5.6.8 (2025/9/16)

- 为 `Invoke-WebRequest` 添加 `-UseBasicParsing` 参数

## 5.6.7 (2025/9/16)

- 移除无意义的错误包装，让错误信息更清晰
- 在 Windows PowerShell 5.1 中禁止自定义补全菜单的边框线条样式
- 抑制仅输入空格就进行补全导致的错误
- 其他修复与优化

## 5.6.6 (2025/9/12)

- 优化了更新检查的网络请求频率
- 其他修复与优化

## 5.6.5 (2025/9/11)

- 修复了路径补全排序
- 其他修复与优化

## 5.6.4 (2025/8/11)

- 修复了补全菜单的过滤问题
- 其他修复与优化

## 5.6.3 (2025/7/21)

- 添加缺失的缓存逻辑

## 5.6.2 (2025/7/21)

- 修改了远程 url 地址的顺序

## 5.6.1 (2025/7/21)

- 移除了模块更新确认
  - 后续版本将需要手动更新 PSCompletions
  - 移除了一个无用的配置项 `module_update_confirm_duration`

## 5.6.0 (2025/7/21)

- 添加配置项 `enable_auto_alias_setup`
  - `psc config enable_auto_alias_setup`
- 将配置项 `disable_cache` 更改为 `enable_cache`
- 将默认的特殊符号 `»` 更改为 `~`
  - 现在默认的 3 个特殊符号是: `~?!`
  - 它们都是 ascii 字符，不可能再造成渲染的兼容性问题
- 修复了使用路径补全时，`Esc`/`Ctrl + C`/`Backspace` 会清除整个路径的问题
- 其他修复与优化

## 5.5.1 (2025/6/1)

- 修复了一个内部方法可能造成的错误。
- 添加补全时，显示可以触发补全的命令别名。
- 降低设置别名的限制。允许在存在 xxx 命令时，添加 xxx.exe 等类似别名。
- 其他修复与优化。

## 5.5.0 (2025/5/1)

- 添加一个配置项 `module_update_confirm_duration`
  - `psc config module_update_confirm_duration`
  - 当模块有版本更新时，模块更新确认的持续时间(毫秒)，默认值为 `15000`。
  - 当超过这个时间后，将自动取消，避免因为更新确认导致进程卡住。
- 其他修复与优化。

## 5.4.0 (2025/3/19)

- 为路径补全添加一个配置项 `enable_path_with_trailing_separator`
  - `psc menu config enable_path_with_trailing_separator`
  - 它控制路径补全是否需要带有末尾的分隔符，默认值为 `1`。
    - 带有: `C:\Users\abgox\`
    - 不带有: `C:\Users\abgox`
- 其他修复与优化。

## 5.3.3 (2025/2/28)

- 优化了在补全菜单中的一些按键。
  - 在补全菜单中，`Space`(空格) 等同于 `Enter`(回车键)
  - 移除了 `Shift + Space`
- 修复了当补全项出现空字符串时会触发的补全错误。
- 修复了模块更新中的一些问题。
- 其他修复与优化。

## 5.3.2 (2025/1/10)

- 优化了补全过滤。
- 在 `$PSCompletions` 中添加了部分属性供 `hooks` 使用，以提升解析速度。
- 修复了后台作业可能导致补全报错的问题。
- 其他修复与优化。

## 5.3.1 (2025/1/5)

- 修复了当选项补全已使用，在下次补全时没有被过滤掉的问题。
- 支持以 `=` 结尾的选项直接获取后续补全项。
  - 需要相关补全定义。

## 5.3.0 (2025/1/1)

- 优化了 json 补全文件的属性结构和解析。
  - 这对于补全文件有一个小的破坏性更新。
  - 因此，`PSCompletions` 模块更新完成后，请运行 `psc update * --force` 命令更新补全。
- 简化特殊符号(`»?!`)的显示规则。
- 添加了更多的内置边框主题。
- 其他修复与优化。

## 5.2.5 (2024/12/19)

- 修复了当配置项 `enable_tip` 设置为 0 时，过滤补全会导致报错的问题，减少了补全菜单闪烁的问题。

## 5.2.4 (2024/12/19)

- 优化模块版本迁移

## 5.2.3 (2024/12/18)

- 对于语言为 `zh-CN` 或设置为 `zh-CN` 的用户，之前默认会使用 Gitee 源 `https://gitee.com/abgox/PSCompletions/raw/main`
- 但是 Gitee 源经常将版本号文件(如 `5.2.2`) 或者 16 位的 Guid 当做违规内容，这会让 `PSCompletions` 的功能受限。
- 因此，现在使用 `https://abgox.github.io/PSCompletions` 作为模块和补全更新的默认首选源。
- 现在尝试的顺序是:
  1.  `https://abgox.github.io/PSCompletions`
  2.  `https://gitee.com/abgox/PSCompletions/raw/main`
  3.  `https://github.com/abgox/PSCompletions/raw/main`

## 5.2.2 (2024/12/18)

- 优化菜单的显示，让菜单项和命令帮助的显示更合理。
- 优化 PowerShell 内置命令的帮助提示显示效果。
- 修复模块更新后可能导致所有配置项被重置的问题。
- 其他修复与优化。

## 5.2.1 (2024/12/13)

- 修复了由于解析补全时的错误导致部分补全项缺失的问题。
- 其他的优化和修复。

## 5.2.0 (2024/12/12)

- 为命令 `psc update *` 添加一个选项 `--force`。
- 不再使用过滤模式获取补全，而是将命令补全解析为树形对象并缓存，大幅度提高补全性能。
- 扩展补全排序功能，现在，不是通过 `psc add` 添加的补全也会尝试通过历史命令记录自动排序。
- 为边框线条添加一种样式 `bold_line_rect_border`。通过命令 `psc menu line_theme bold_line_rect_border` 使用它。
- 修改了默认符号(`?!»`)，以避免特殊字符导致的渲染问题。
- 优化了补全菜单在各种宽高下的终端窗口的显示效果。
- 因为不再使用过滤模式获取补全，`hooks` 的生效节点延后，最后处理补全项，灵活性更强。
- 将 `disable_hooks` 配置项替换为 `enable_hooks`。
- 修复了 `CompletionPredictor` 模块引起的多次更新确认的问题。
- 修复了在 `Windows PowerShell` 中，补全菜单显示错位以及其他兼容性问题
- 修复了命令提示信息自适应换行没有充分利用终端宽度的问题。
- 对于 Scoop 应用清单，现在可以在安装逻辑中直接创建一个内容为 `{}` 的 data.json 文件。
- 其他的优化和修复。

## 5.1.4 (2024/11/30)

- 修复了在 `v5.1.3` 中，混合使用 `PowerShell` 和 `Windows PowerShell` 导致边框样式被意外更改的问题。

## 5.1.3 (2024/11/30)

- 修复拥有 `hooks.ps1` 的补全命令的动态补全不生效的问题。
- 当后续模块需要更新时，会尝试多种更新方式。
- 其他的优化和修复。

## 5.1.2 (2024/11/27)

- 由于未来的 Windows Terminal 的变化，将导致在补全菜单中无法正常显示 😄🤔😎，因此这三个默认特殊符号将改变。
  - 相关的 issue: https://github.com/microsoft/terminal/issues/18242
  - 目前 Windows Terminal 可用，Windows Terminal Preview 不可用。
  - PSCompletions 不会自动替换它们，你需要手动运行命令 `psc reset menu symbol` 来替换它们。
  - 变化如下:
    - `😄` => `→`
    - `🤔` => `?`
    - `😎` => `↓`
- 修复了配置修改后不生效的问题。
- 其他的优化和修复。

## 5.1.1 (2024/11/22)

- 修复了 `order.json` 解析压缩导致补全报错的问题。
- 其他的优化和修复。

## 5.1.0 (2024/11/21)

- 添加方法 `$PSCompletions.argc_completions()` 用于 [argc-completions](https://github.com/sigoden/argc-completions)。
  - 详情请查看: [PSCompletions and argc-completions](https://pscompletions.abgox.com//tips/pscompletions-and-argc-completions)
- 优化了模块目录结构，将不重要的临时文件统一放置到 `temp` 目录下。
- 减少不必要的重复解析，让第二次及之后的补全更快。
- 其他的优化和修复。

## 5.0.8 (2024/11/15)

- 修复了当切换语言后，帮助信息没有立即更换的问题。
- 修复了 `reset` 子命令的一些问题。
- 现在，当下载/更新补全时，所有 json 文件将被压缩。

## 5.0.7 (2024/11/9)

- 修复初始化错误。

## 5.0.6 (2024/10/26)

- 修复了目录路径补全没有尾部路径分隔符的问题
- 其他的优化和修复。

## 5.0.5 (2024/9/2)

- 在 `$PSCompletions` 中添加一个方法 `return_completion` 用于 `hooks.ps1`。
- 其他的优化和修复。

## 5.0.4 (2024/9/1)

- 修复 `psc rm *` 命令会重置所有配置项的问题。
- 其他的优化和修复。

## 5.0.3 (2024/8/31)

- 修复 `psc` 子命令运行时的报错。
- 其他的优化和修复。

## 5.0.2 (2024/8/31)

- 移除不必要的文件 I/O 操作。
- 其他的优化和修复。

## 5.0.1 (2024/8/31)

- 修复版本更新后 `psc` 没有正常添加的问题。

## 5.0.0 (2024/8/30)

- 减少文件 I/O 操作，优化初始化方法，提升首次加载速度。
  - 移除每个补全目录下的 **alias.txt** 文件，使用 **data.json** 文件存储数据。
- 将配置数据文件 **config.json** 合并到 **data.json** 中。
  - 注意: 如果使用了 scoop 去安装 `PSCompletions`，请检查应用清单(manifest)中的 persist 是否更新为 **data.json**。
- 修改了几乎所有配置项的名称。

  - 配置项名称的修改，不影响正常使用，在更新版本后，也会自动迁移旧的配置项到新的配置项。
  - 比如:
    - `update` => `enable_completions_update`
    - `module_update` => `enable_module_update`
    - `menu_show_tip` => `enable_tip`
    - ...

- 移除了两个配置项: `github` 和 `gitee`。
  - 如果需要自定义地址，请使用 `url` 配置项。
  - `psc config url <url>`
- 其他的优化和修复。

## 4.3.3 (2024/8/27)

- 当启用 `menu_is_prefix_match` 时，公共前缀提取后的输入可能会导致错误，现在已修复

## 4.3.2 (2024/8/18)

- 修复一个方法(`show_module_menu`)的参数类型转换错误

## 4.3.1 (2024/8/18)

- 添加一个配置项 `menu_is_loop`, 控制是否循环显示菜单，默认值为 `1`
  - 禁用它: `psc menu config menu_is_loop 0`
- 优化旧版本的迁移逻辑

## 4.3.0 (2024/8/15)

- 修复在 `Windows PowerShell` 中的模块更新问题
- 修复补全动态排序失效的问题
- 修复版本号对比的问题
  - 为了避免版本对比错误，此版本号由 `4.2.10` 更改为 `4.3.0`

## 4.2.9 (2024/8/15)

- 修复一些问题
- 优化部分逻辑,提升性能

## 4.2.8 (2024/8/12)

- 修复一个触发边界情况导致渲染错误的问题

## 4.2.7 (2024/8/12)

- `PSCompletions` 模块会占用两个全局命名，`$PSCompletions`(变量) 和 `PSCompletions`(函数)
  - 现在，它们都为只读，强行覆盖会报错，防止误操作导致模块失效
  - 但 `PSCompletions`(函数) 可以通过配置修改函数名
- 添加一个配置项 `function_name`, 默认值为 `PSCompletions`

  - 设置: `psc config function_name <name>`
  - 使用场景:
    - 当你或其他模块需要定义一个函数，名字刚好也必须为 `PSCompletions` 时
    - 你可以通过 `function_name` 将本模块的函数修改为一个不冲突的名字
  - 需要注意:
    - `PSCompletions`(函数) 可以通过配置修改，但 `$PSCompletions`(变量) 是无法修改的
    - 当你需要定义一个变量，名字刚好也必须为 `$PSCompletions`
    - 无法解决，要么你不使用 `PSCompletions` 模块，要么给你要定义的变量改个名字

- 对 PowerShell 内置命令的 ToolTip 提示信息简单处理，优化显示
- 当菜单显示后，输入字符进行过滤不再更改菜单的宽度
- 修复了可以设置一个已存在的命令为别名的bug
- 优化逻辑运算，移除一些多余的运算

## 4.2.6 (2024/8/10)

- 修复补全项列表为空的bug
- 如果使用 `Windows PowerShell`，且使用了命令行主题(如: oh-my-posh)，当补全菜单显示在上方时，可能会导致当前行附近的文字及图标错乱
  - 解决方案:
    1. 禁用命令行主题
    2. 尽量让补全菜单显示在下方(只要当前行在窗口中部以上即可)
    3. 不要使用 `Windows PowerShell`，直接使用 [`PowerShell`](https://github.com/PowerShell/PowerShell)
       - `Windows PowerShell` 真的很差，小问题总是很多

## 4.2.5 (2024/8/10)

- 如果菜单启用了前缀匹配(`menu_is_prefix_match`)，当有公共前缀时，只提取补全的值
- 优化补全更新的逻辑

## 4.2.4 (2024/8/10)

- 修复了因为一个代码文件使用了 LF 换行符导致 `Windows PowerShell` 模块加载错误的问题
  - 对于源代码文件，将 LF 换行符替换为 CRLF 换行符，UTF-8 编码替换为 UTF-8-BOM 编码
- 修复了非 Windows 环境的初始化导入缺失的问题
- 更改源代码文件目录结构

## 4.2.3 (2024/8/9)

- 修复特定补全的 `menu_show_tip` 配置无效的问题
- 修复在过滤补全时，菜单渲染错误的问题

## 4.2.2 (2024/8/9)

- 当使用 `psc update *` 更新补全后，不再立即检查更新

## 4.2.1 (2024/8/9)

- 修复新版本迁移时的一个小问题

## 4.2.0 (2024/8/9)

- 添加了三个 `menu` 配置

  1. `menu_trigger_key`: 默认值为 `Tab`, 用于设置补全菜单的触发按键
     - 设置: `psc menu config menu_trigger_key <key>`
  2. `menu_enhance`: 默认值为 `1`, 用于设置是否启用补全菜单增强功能

     - 禁用它: `psc menu config menu_enhance 0`
     - 开启后，`PSCompletions` 会拦截所有补全，并使用 `PSCompletions` 提供的补全菜单渲染补全
     - 比如，`PowerShell` 中的 `Get-*`,`Set-*` 等命令都会使用 `PSCompletions` 提供的补全菜单渲染补全
     - 需要注意，此配置项生效的前提是启用了 `menu_enable`
     - [关于菜单增强](../README.zh-CN.md#关于菜单增强)

  3. `menu_show_tip_when_enhance`: 默认值为 `1`, 设置不是通过 `psc add` 添加的补全，是否显示命令提示信息

     - 禁用它: `psc menu config menu_show_tip_when_enhance 0`
     - 和 `menu_enhance` 一起使用

- 解决了多字节文字可能导致菜单出现部分渲染错误的问题
  - 这配合 `menu_enhance` 很有用
  - 比如，输入 `cd` 命令按下 `Tab` 触发补全，即使路径补全中有中文等多字节文字，菜单也不会有渲染问题
- 补全提示信息支持根据可用宽度自动换行

  - 为了体验更好，`menu_tip_follow_cursor` 配置项的默认值从 `0` 修改为 `1`

- 重构代码，调整源代码文件目录结构，提取公共代码
- 使用多线程优化性能，移除一些多余的执行语句
- 修复一些其他问题
- 整理代码

## 4.1.0 (2024/8/7)

- 现在 `Windows PowerShell` 也可以使用模块提供的补全菜单了
  - 不过由于渲染问题，补全菜单的边框样式无法自定义
- 修复一些其他问题
- 调整源代码文件目录结构
- 整理代码

## 4.0.9 (2024/7/20)

- 添加两个命令: 添加/移除所有补全
  - `psc add *`
  - `psc rm *`
- 优化 `common_options` 的逻辑处理
- 修复模块更新的问题
- 调整源代码文件目录结构
- 整理代码

## 4.0.7 (2024/7/6)

- 将 `ForEach-Object` 替换为 `foreach`
  - `ForEach-Object` 在一些特殊情况下的结果不符合预期
- 整理代码

## 4.0.6 (2024/5/20)

- 一个默认颜色配置改错了，修复一下

## 4.0.5 (2024/5/20)

- 修复了关于补全特殊配置的一些问题
- 修复了因为存在缓存导致配置修改后无法立即生效的问题
- 给 `reset` 命令添加 `completion` 子命令，用于重置(移除)补全的特殊配置
- 修复了一些其他问题

## 4.0.4 (2024/5/20)

- 修复了当补全列表滚动时，补全提示信息、过滤区域、状态区域闪烁的问题
- 修复了一些其他的小问题

## 4.0.3 (2024/5/18)

- 修复了一个因为修改终端输出编码导致提示信息显示错误的问题
  - 必须先导入 `PSCompletions` 模块，然后再修改终端输出编码，否则还是会显示错误
- 将 `menu_tip_cover_buffer` 这个配置的默认值从 `0` 修改为 `1`
  - 表示默认情况下，菜单提示信息会覆盖缓冲区内容，主要是当提示信息显示在上方时，会覆盖掉上方所有内容，这会看起来背景更简洁
  - 当然，当补全菜单消失后，覆盖的内容会恢复
  - 你也可以禁用它(`psc menu config menu_tip_cover_buffer 0`)
- 修复了一些其他的小问题

## 4.0.2 (2024/5/15)

- 一个测试环境的配置没有及时删除，修复一下

## 4.0.1 (2024/5/15)

- 一个默认配置的颜色写错了，修复一下

## 4.0.0 (2024/5/15)

- 如果你当前使用的 `PSCompletions` 模块需要**管理员权限**，你应该删除 `PSCompletions` 模块，然后以**用户权限**安装最新版的模块。

  - 完整的模块安装命令: `Install-Module PSCompletions -Scope CurrentUser`

- 4.0.0 版本重构了整个模块，解决了许多不合理的地方，所以完全不兼容旧版本的配置和补全

  1.  性能优化:
      - 提升了模块加载速度
      - 提升了补全响应速度
  2.  补全菜单:
      - 补全菜单完全重写，菜单渲染的稳定性大幅提高，从根本上解决了许多渲染 bug
      - 补全菜单新增了许多的配置项，你可以自行通过触发补全以及提示信息查看
      - 比如: `menu_show_tip`, 它可以控制补全提示信息是否显示，如果你对命令足够熟悉，建议禁用补全提示信息
      - 此配置也可以单独给某一个补全设置，参考 `psc completion` 下的命令
  3.  补全别名:
      - 现在补全别名支持多个，你可以随意添加。理论上，你可以添加无数个别名
      - 比如，你可以添加 `.\scoop.ps1` 这样的别名，这在有些时候比较有用
  4.  补全文件和模块解耦
      - 现在可以只编写 json 文件去新增/更新/翻译一个补全，不需要涉及到代码(如果需要使用到 hooks 除外)
      - 同时使用了 json schema 控制 json 文件的类型，这让想要为仓库添加补全的贡献者创建 PR 的难度大幅降低
      - 比如你觉得某一个命令的描述不够完善，你也可以修改它的 json 文件后之后，提交一个 PR
  5.  语言:
      - 现在从模块层面，支持任何语言，模块会根据语言配置以及每一个补全的 `config.json` 文件来决定语言
      - 这意味着以后可以添加更多语言的支持，只需要编写对应的 json 文件即可
  6.  其他:
      - 新增了一些按键映射，你现在可以通过许多种按键方式在补全菜单中选择补全项，你可以选择一种适合自己的。
        |选择上一项|选择下一项|
        |:-:|:-:|
        |`Up`|`Down`|
        |`Left`|`Right`|
        |`Shift + Tab`|`Tab`|
        |`Shift + Space`|`Space`|
        |`Ctrl + u`|`Ctrl + d`|
        |`Ctrl + p`|`Ctrl + n`|
      - 现在符号被放在了补全项的后面，补全提示信息中不再出现符号
      - ...
