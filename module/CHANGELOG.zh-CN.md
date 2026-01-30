[English](./CHANGELOG.md) | [简体中文](./CHANGELOG.zh-CN.md)

## 6.4.0

- 添加了 `enable_menu_show_below` 配置项
  - 启用它: `psc menu config enable_menu_show_below 1`
  - 当模块补全菜单需要在光标上方显示时，滚动内容缓冲区，让光标回到顶部，然后在光标下方显示菜单
  - 只要你能接受旧的缓冲区内容需要向上滚动查看，它就是一个彻底解决 [缓冲区重绘问题](https://github.com/abgox/PSCompletions/issues/93) 的完美方案
- 移除了 `Left` 和 `Right` 方向键的绑定
  - 它们也被用来选择上一个和下一个补全项，这并不常见
  - 现在保留这两个按键，未来可能会给它们绑定其他功能
- 修复了根命令包含路径分隔符时，无法触发补全的问题
  - 以 `scoop-checkver` 补全为例，它使用 `.\bin\checkver.ps1` 作为根命令
  - 现在，它就可以正常触发补全了
- 优化了模块的输出，格式更加清晰易读
- 其他的优化和修复

## 6.3.3

- 暴露了模块补全菜单以允许外部调用
  - 可以直接使用 `Set-PSReadLineKeyHandler -Key <Key> -ScriptBlock $PSCompletions.menu.module_completion_menu_script` 绑定模块补全菜单
  - 它会假定 `enable_menu` 和 `enable_menu_enhance` 为 `1`，忽略真实的配置值
  - 不建议这样使用它，除非特殊需求且这两个配置实际生效的值都为 `1`
- 修复了由于 PowerShell 中逻辑比较运算符的特殊行为导致的一些特殊配置无效的问题
- 其他的优化和修复

## 6.3.2

- 修复了 ToolTip 的显示问题
- 改进了补全采用时，对补全项的处理方式
- 其他的优化和修复

## 6.3.1

- 使用硬编码的 'PSCompletions' 作为导出函数名称 ([#129](https://github.com/abgox/PSCompletions/issues/129))
- 移除了可能存在的 ANSI 颜色代码以正常显示 (仅模块提供的补全菜单)

## 6.3.0

- 现在，运行 `psc` 将重新加载模块的按键绑定和数据，然后打印帮助信息
  - 在旧版本中，使用 `. $Profile` 会导致模块的按键绑定失效
  - 现在，只需要运行一次 `psc` 即可恢复模块的正常使用
- 渲染补全菜单时使用正确的区域编码 ([#127](https://github.com/abgox/PSCompletions/issues/127))

## 6.2.6

- 清空 change.txt 时静默处理错误

## 6.2.5

- 在获取 buffer 之前设置编码，以确保重绘的一致性

## 6.2.4

- 优化了获取原始输出编码的方式
  - 以前必须先导入 `PSCompletions` 模块，才能修改编码，否则可能导致编码问题
  - 由于新的获取方式，不再有先后顺序限制
- 其他的优化和修复

## 6.2.3

- 重新使用 `Add-Member` 以避免缓冲区访问错误 ([#122](https://github.com/abgox/PSCompletions/issues/122), [#124](https://github.com/abgox/PSCompletions/issues/124))
  - [CompletionPredictor](https://www.powershellgallery.com/packages/completionpredictor) 模块会阻止 `PSCompletions` 访问缓冲区，包括公共的相关变量和方法
  - 使用 `Add-Member` 可以避免这个问题，但是具体原因还不清楚
- 修复了 [CompletionPredictor](https://www.powershellgallery.com/packages/completionpredictor) 模块会导致核心脚本重复加载多次的问题
- 修复了命令中包含通配符会导致补全错误的问题
  - 现在 `[xxx]` 这样的输入，如 `[env]` 也可以获取到相关的补全项了
- 其他的优化和修复

## 6.2.2

- 改进了当 `enable_list_full_width` 为 `0` 时的宽度校验，避免一些异常情况
  - 推荐将 `enable_list_full_width` 设置为 `1`, 它是目前的最优体验
  - 设置: `psc menu config enable_list_full_width 1`
- 其他的优化和修复

## 6.2.1

- 为 `$PSCompletions.argc_completions()` 添加了别名支持
  - 参考: [结合 argc-completions 使用](https://pscompletions.abgox.com/faq/pscompletions-and-argc-completions)
  - 感谢来自 [@CallMeLaNN](https://github.com/CallMeLaNN) 的 [实现参考](https://github.com/sigoden/argc-completions/issues/65#issuecomment-3642388096)
- 移除了补全项中可能存在的 ANSI 转义码
  - 参考: [#121](https://github.com/abgox/PSCompletions/issues/121)
  - [PSCompletions 可以正常和 Carapace 结合使用](https://pscompletions.abgox.com/faq/pscompletions-and-carapace)
- 优化了命令及别名检查
- 其他的优化和修复

## 6.2.0

- 添加 `enable_list_full_width` 配置项，用于控制补全菜单是否铺满窗口宽度
  - 参考: [#117](https://github.com/abgox/PSCompletions/issues/117)
  - 它是默认启用的
  - 它能够让补全菜单的相关计算复杂度从 `O(n)` 降低到 `O(1)`，媲美原生补全菜单的响应性能
  - 如果你不喜欢它的效果，请运行 `psc menu config enable_list_full_width 0`
- 为补全菜单添加 `height_from_menu_top_to_cursor_when_below` 配置项
- 简化了补全菜单的颜色主题
  - 移除了一些冗余的颜色配置项
  - 变更了一些颜色配置项的名称，如果你有自定义，可能需要重新设置
- 使用 `single_line_round_border` 作为补全菜单的默认线条主题
- 移除所有补全文件的 `tip` 字段中的换行符，由补全加载时自动添加
- 当光标后有空格时，禁用补全后缀
- 限制 `completion_suffix` 的值，它只能是一个或多个空格
- 修复当 `enable_tip` 为 `0` 时，模块提供的特殊符号(`~?!`)缺失的问题
- 修复了 `WriteSpaceTab` 类型补全失效的问题
- 其他性能优化和修复

## 6.1.0

- 补全库存在部分破坏性变更，请在更新模块后及时更新所有补全
  - 更新命令：`psc update * --force`
- 过滤时，忽略补全项中由模块提供的特殊符号(`~?!`)
- 修复了包含 `[` 字符时触发补全错误的问題
- 修复了根命令的补全触发时机
- 多项性能优化

## 6.0.3

- 处理菜单渲染中的空提示

## 6.0.2

- 减少不必要的字符串匹配和解析
- 检查管理员权限
  - 如果安装模块时指定了 `-Scope AllUsers`，模块会安装到系统级目录中
  - 此时，模块只能在管理员权限下运行

## 6.0.1

- 减少 buffer 的重绘范围

## 6.0.0

- 重构了补全菜单，补全响应速度大幅提升
- 移除了 `enable_prefix_match_in_filter`
  - 现在过滤使用模糊匹配，支持三个匹配符: `^?*`
  - 使用 `^` 替代以前的前缀匹配
- 移除了一些不常用的配置
  - `enable_list_cover_buffer`
  - `enable_tip_cover_buffer`
  - `enable_selection_with_margin`
  - `width_from_menu_left_to_item`
  - `width_from_menu_right_to_item`
- 其他的优化和修复

## [历史版本](./changelog/archive.zh-CN.md)
