-- PSCompletions `hooks.lua` type definitions for the Lua language server
-- (sumneko.lua / the VSCode "Lua" extension).
--
-- Models the `psc` global (injected by the Rust engine) and the `completions`
-- global (static items) so the editor offers autocomplete and argument checks
-- inside `completions/*/hooks.lua`. The file is never executed.
--
-- Authoritative API reference: `design/hooks.md`.
-- Descriptions are bilingual, Chinese first then English.
---@diagnostic disable: missing-return



--- 补全项。
---
--- A completion item.
---@class psc_item
--- 规范名（比较/匹配用）。
---
--- Canonical name (used for comparison / matching).
---@field name string
--- 提示文本：字符串或本地化表（键为语言代码，值对应该语言文本）。
---
--- Tip text: a plain string or a localized table (keys are language codes).
---@field tip? string|psc_localized
--- 预测符号（config key）。
---
--- Predict symbol (config key).
---@field symbol? "switch"|"stay"
---@field usage? string
---@field example? string
--- 可重复使用次数；默认 0 = 首次使用后隐藏（字段名用 repeat_count，因 repeat 是 Lua 关键字）。
---
--- How many times it may be used; 0 (default) = hidden after first use (repeat is a Lua keyword).
---@field repeat_count? integer



--- 多语言文本表：键为语言代码，值为对应语言的文本。
---
--- Localized text table: keys are language codes, values are the text.
---@class psc_localized
--- 英文提示（回退目标：当前语言缺失时使用）。
---
--- English tip (fallback when the current language is missing).
---@field ["en-US"] string
--- 中文提示。
---
--- Chinese tip.
---@field ["zh-CN"]? string
--- 其他语言代码（可扩展；引擎按 psc.language → en-US → 首项回退）。
---
--- Other language codes (extensible; the engine falls back psc.language → en-US → first entry).
---@field [string] string



---@class psc_token
--- 规范名（命令/选项主名，别名已展开）。
---
--- Canonical name (main name of a command/option, aliases expanded).
---@field name string
--- token 类型。
---
--- Token type.
---@field type "command"|"option"|"value"|"unknown"
--- 用户原始输入（保留原文，可能为别名）。
---
--- The user's original input (kept as typed, possibly an alias).
---@field input string



---@class psc_current
--- 规范名（尽力匹配；未完成的词可能为空）。
---
--- Canonical name (best-effort; may be empty for an unfinished word).
---@field name? string
--- token 类型（未完成的词通常为 "unknown"）。
---
--- Token type (usually "unknown" for an unfinished word).
---@field type? "command"|"option"|"value"|"unknown"
--- 用户原始输入。
---
--- The user's original input.
---@field input? string
--- 是否以 `-` 开头（启发式判断：像选项，非确定）。
---
--- Whether the input starts with `-` (heuristic: looks like an option, not definitive).
---@field option_like boolean



--- 路径条目（可以是文件或目录）。
---
--- A path entry (may be a file or a directory).
---@class psc_path_entry
--- 条目名。
---
--- Entry name.
---@field name string
--- 条目的完整路径。
---
--- The entry's full path.
---@field path string
--- 是否为目录（跟随符号链接判断）。
---
--- Whether it is a directory (follows symlinks).
---@field is_dir boolean
--- 是否为符号链接。
---
--- Whether it is a symbolic link.
---@field is_link boolean



--- 来自 manifest 的静态项，由引擎提供。
---
--- Static items from the manifest, provided by the engine.
---@type psc_item[]
completions = {}

--- 引擎注入的全局对象：hooks 的运行环境。
---
--- The engine-injected global: the hooks runtime.
---@class psc
psc = {}

-- ===================== 上下文值（hooks 的输入侧） =====================

--- 已完成的子命令链，不包含根命令。
---
--- - `psc.tokens` 的过滤视图：取其中 `type == "command"` 的 `name`。
--- - 如 `git stash apply` → `psc.cmds = { "stash", "apply" }`
---
--- Completed subcommand chain excluding the root command.
---
--- - A filtered view of `psc.tokens`: the `name`s of its `type == "command"` entries.
--- - e.g. `git stash apply` → `psc.cmds = { "stash", "apply" }`
---@type string[]
psc.cmds = {}

--- 已完成的选项链。
---
--- - `psc.tokens` 的过滤视图：取其中 `type == "option"` 的 `name`。
--- - 如 `git branch -m -c` → `psc.opts = { "--move", "--copy" }`
---
--- Completed option chain (symmetrical to `cmds`).
---
--- - A filtered view of `psc.tokens`: the `name`s of its `type == "option"` entries.
--- - e.g. `git branch -m -c` → `psc.opts = { "--move", "--copy" }`
---@type string[]
psc.opts = {}

--- 已完成的输入 token 列表（含类型），不含当前正在输入的词。
---
--- Completed input tokens (with types), excluding the word currently being typed.
---@type psc_token[]
psc.tokens = {}

--- 当前正在输入的词（未完成）；与 `tokens` 对立。
---
--- The word currently being typed (unfinished); opposite of `tokens`.
---@type psc_current
psc.current = { option_like = false }

--- 当前命令的补全配置（用户为该命令单独设置的项，如 git 的 `max_commit`）。
---
--- The current command's completion config (user-configured keys for this command, e.g. git's `max_commit`).
---@type table<string, any>
psc.config = {}

--- 解析后的补全 manifest（数据文件）
---
--- The parsed completion manifest (data file)
---@type table<string, any>?
psc.manifest = {}

--- 模块当前语言（en-US / zh-CN）；用于选择多语言 tip 表的条目。
---
--- The module's current language (en-US / zh-CN); selects the entry of a localized tip table.
---@type string|"en-US"|"zh-CN"
psc.language = "en-US"

--- 当前的工作目录。
---
--- The current working directory.
---@type string
psc.cwd = ""

--- 当前的系统平台。
---
--- The current system platform.
---@type "windows"|"macos"|"linux"
psc.platform = "windows"

-- ===================== 补全项专属 =====================

--- 把数组每个元素转成补全项。
---
--- - `elements`：要转换的元素数组
--- - `fn`（可选）：转换函数
---   - 默认：元素即 `name`（元素必须是 string）
---   - 元素为其他类型必须显式传 fn
---   - 返回 `nil` 跳过该元素
---
--- Converts each array element into a completion item.
---
--- - `elements`: the array of elements to convert
--- - `fn` (optional): the converter
---   - Without it the element itself is the `name` (the element must be a string)
---   - Other types require fn
---   - Returning `nil` skips that element
---@param elements string[]
---@param fn? fun(elem: string): psc_item|nil
---@return psc_item[]
function psc.items(elements, fn) end

--- 把 manifest 路径上指定数组的**直接子项**挂载为补全项。
---
--- - `manifest_path`：从 manifest 根出发的路径，最后一段必须是 `"next"` 或 `"option"`——决定取哪个数组
--- - 只挂载该数组的直接子项（不递归展开）；更深层由引擎的 `next` 导航自动处理，或再次调用本方法用更长的路径
--- - 不计算预测符号；需要时用 `psc.set_symbol` 显式设置
--- - 想同时挂载 `next` 和 `option`，调用两次即可
---
--- Mounts the **direct children** of a manifest `next`/`option` array as completion items.
---
--- - `manifest_path`: a path from the manifest root; the last segment must be `"next"` or `"option"` — it selects which array
--- - Mounts only the direct children (no recursion); deeper levels are handled by the engine's `next` navigation, or by calling again with a longer path
--- - No predict symbol is set; use `psc.set_symbol` explicitly when needed
--- - To mount both `next` and `option`, call twice
---@param manifest_path string[]
---@return psc_item[]
function psc.mount_items(manifest_path) end

--- 追加补全项到 `cs`（单条或批量）。
---
--- - `cs`：hook 收集动态补全项的数组 `local cs = {}`
--- - `item_or_items`：单个补全项表或补全项数组
--- - 传空 name 或空数组时：静默跳过，不报错
--- - 返回实际添加数量
---
--- Appends completion items to `cs` (single or batch).
---
--- - `cs`: the hook's dynamic completion-item array `local cs = {}`
--- - `item_or_items`: a single item table or an array of items
--- - Empty name / empty array: silently skipped, no error
--- - Returns the number actually added.
---@param cs psc_item[]
---@param item_or_items psc_item|psc_item[]
---@return integer
function psc.add(cs, item_or_items) end

--- 合并补全项：与 `psc.concat(cs,completions)` 等效
---
--- Merge completion items: equivalent to `psc.concat(cs,completions)`
---@param cs psc_item[]
---@return psc_item[]
function psc.merge(cs) end

--- 覆盖当前上下文中某个项的预测符号。
---
--- - `name`：要匹配的项名（默认忽略大小写）
--- - `symbol`：只能是 `"switch"` 或 `"stay"`
--- - `opts`（可选）：`case_sensitive = true` 时区分大小写匹配
---
--- Overrides the predict symbol of an item in the current context.
---
--- - `name`: the item name to match (case-insensitive by default)
--- - `symbol`: must be `"switch"` or `"stay"`
--- - `opts` (optional): `case_sensitive = true` matches case-sensitively
---@param name string
---@param symbol "switch"|"stay"
---@param opts? { case_sensitive?: boolean }
function psc.set_symbol(name, symbol, opts) end

--- 覆盖或插入当前上下文中某个项的 tip。
---
--- - `name`：要匹配的项名（默认忽略大小写）
--- - `tip`：新的 tip，可以是字符串或**多语言表**
--- - `opts`（可选）：
---   - `mode`：`"set"`（替换，默认）/ `"prepend"`（前插）/ `"append"`（后插）
---   - `case_sensitive = true`：区分大小写匹配
---
--- Overrides or inserts the tip of an item in the current context.
---
--- - `name`: the item name to match (case-insensitive by default)
--- - `tip`: the new tip, a string or a **localized table**
--- - `opts` (optional):
---   - `mode`: `"set"` (replace, default) / `"prepend"` / `"append"`
---   - `case_sensitive = true`: matches case-sensitively
---@param name string
---@param tip string|psc_localized
---@param opts? { mode?: "set"|"prepend"|"append", case_sensitive?: boolean }
function psc.set_tip(name, tip, opts) end

--- 是否存在未知 token（说明已经输入了一个值）。
---
--- Whether any unknown token exists (a value has been typed).
---@return boolean
function psc.has_unknown() end

--- name（规范名）是否出现在已完成的 token 中；别名计入其主名（与引擎 repeat 过滤一致）。
---
--- Whether the canonical `name` appears among completed tokens; an alias counts as its main name (matching the engine's repeat filter).
---@param name string
---@return boolean
function psc.typed(name) end

--- name 是否出现在已完成的未知 token 中（仅值）。
---
--- Whether the name appears among completed unknown tokens (values only).
---@param name string
---@return boolean
function psc.typed_unknown(name) end

-- ===================== 数据获取 =====================

---@alias psc_run_format "json"|"toml"|"yaml" 命令输出解析格式（format to parse command output as）

--- 运行命令，返回 stdout 行数组。
---
--- - `argv`：命令及其参数，如 `{ "git", "branch" }`
--- - `opts`（可选）：
---   - `format`：解析命令输出，返回解析后的 table 或 `nil`
---   - `timeout`：超时毫秒，默认 5000
---   - `cwd`：命令工作目录，默认用户当前工作目录
---   - `shell`：通过系统 shell 执行（Windows `cmd /c`、其他 `sh -c`），用于无法直接启动的 batch/PowerShell shim（如 `scoop`）
--- - 失败/超时返回 `nil`
---
--- Runs a command; returns stdout lines.
---
--- - `argv`: the command and its arguments, e.g. `{ "git", "branch" }`
--- - `opts` (optional):
---   - `format`: parses the command output and returns the parsed table or `nil`
---   - `timeout`: timeout in ms, default 5000
---   - `cwd`: command working directory, default the user's current directory
---   - `shell`: runs through the system shell (`cmd /c` on Windows, `sh -c` elsewhere) — for batch/PowerShell shims that cannot be spawned directly (e.g. `scoop`)
--- - `nil` on failure/timeout.
---@param argv string[]
---@param opts? { format?: psc_run_format, timeout?: integer, cwd?: string, shell?: boolean }
---@return string[]|table|nil
function psc.run(argv, opts) end

--- 并发运行多条命令
---
--- - `cmds`：命令列表，每个元素是 `{ cmd, arg... }`
--- - `opts`（可选）：
---   - `format`：解析命令输出，返回解析后的 table 或 `nil`
---   - `timeout`：超时毫秒，默认 5000
---   - `cwd`：命令工作目录，默认用户当前工作目录
---   - `shell`：每条命令都通过系统 shell 执行
--- - 按输入顺序返回各自的 stdout 行
--- - 某条命令失败/超时为 `nil`
---
--- Runs several commands in parallel.
---
--- - `cmds`: a list of commands, each an `{ cmd, arg... }` array
--- - `opts` (optional):
---   - `format`: parses the command output and returns the parsed table or `nil`
---   - `timeout`: timeout in ms, default 5000
---   - `cwd`: command working directory, default the user's current directory
---   - `shell`: each command runs through the system shell
--- - Returns their stdout lines in input order.
--- - `nil` at an index when that command failed/timed out.
---@param cmds string[][]
---@param opts? { format?: psc_run_format, timeout?: integer, cwd?: string, shell?: boolean }
---@return table<number, string[]|table|nil>
function psc.run_batch(cmds, opts) end

--- 以 UTF-8 读取文件，返回原始文本
---
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
--- - 失败返回 `nil`。
---
--- Reads a file as UTF-8 text.
---
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is
--- - `nil` on failure.
---@param path string
---@return string?
function psc.read(path) end

--- 并行读取多个文件。
---
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
--- - 返回 `{ [path] = content, ... }`
--- - 缺失/不可读的为 `nil`
---
--- Reads multiple files in parallel.
---
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is
--- - Returns `{ [path] = content, ... }`
--- - `nil` for missing/unreadable files.
---@param paths string[]
---@return table<string, string|nil>
function psc.read_batch(paths) end

--- 读取并解析 JSON 文件为 table
---
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
--- - 失败返回 `nil`
---
--- Reads and parses a JSON file into a table.
---
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is
--- - `nil` on failure.
---@param path string
---@return table<string, any>?
function psc.json(path) end

--- 并行读取 + 解析多个 JSON 文件。
---
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
--- - 缺失/不可解析的为 `nil`
---
--- Reads + parses multiple JSON files in parallel.
---
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is
--- - `nil` for missing/unparseable files.
---@param paths string[]
---@return table<string, table<string, any>|nil>
function psc.json_batch(paths) end

--- 读取并解析 TOML 文件为 table
---
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
--- - 失败返回 `nil`
---
--- Reads and parses a TOML file into a table.
---
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is
--- - `nil` on failure.
---@param path string
---@return table<string, any>?
function psc.toml(path) end

--- 并行读取 + 解析多个 TOML 文件。
---
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
--- - 缺失/不可解析的为 `nil`
---
--- Reads + parses multiple TOML files in parallel.
---
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is
--- - `nil` for missing/unparseable files.
---@param paths string[]
---@return table<string, table<string, any>|nil>
function psc.toml_batch(paths) end

--- 读取并解析 YAML 文件为 table
---
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
--- - 失败返回 `nil`
---
--- Reads and parses a YAML file into a table.
---
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is
--- - `nil` on failure.
---@param path string
---@return table<string, any>?
function psc.yaml(path) end

--- 并行读取 + 解析多个 YAML 文件。
---
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
--- - 缺失/不可解析的为 `nil`
---
--- Reads + parses multiple YAML files in parallel.
---
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is
--- - `nil` for missing/unparseable files.
---@param paths string[]
---@return table<string, table<string, any>|nil>
function psc.yaml_batch(paths) end

--- 列出路径条目（文件与目录）
---
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
--- - 目录不存在返回 `nil`
--- - 每项为 `{ name, path, is_dir, is_link }`
--- - `name`：条目名
--- - `path`：条目的完整路径
--- - `is_dir`：是否为目录（跟随符号链接判断）
--- - `is_link`：是否为符号链接
---
--- Lists path entries (files and directories)
---
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is.
--- - `nil` if the directory does not exist.
--- - Each as `{ name, path, is_dir, is_link }`
--- - `name`: entry name
--- - `path`: the entry's full path
--- - `is_dir`: whether it is a directory (follows symlinks)
--- - `is_link`: whether it is a symbolic link
---@param path string
---@return psc_path_entry[]|nil
function psc.ls(path) end

--- 并发列出多个目录
---
--- - 按输入顺序返回各自的条目
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
--- - 目录不存在时该位为 `nil`
---
--- Lists several directories in parallel.
---
--- - Returns their entries in input order.
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is.
--- - `nil` at an index for a missing dir.
---@param dirs string[]
---@return table<number, psc_path_entry[]|nil>
function psc.ls_batch(dirs) end

--- glob 匹配（支持 *、?、**）
---
--- - 路径相对 `psc.cwd` 解析
--- - 返回匹配的绝对路径
--- - 无效 pattern 返回 `nil`
---
--- Glob matching (supports *, ?, **)
---
--- - The pattern resolves against `psc.cwd`.
--- - Returns matched absolute paths.
--- - `nil` for an invalid pattern.
---@param pattern string
---@return string[]|nil
function psc.glob(pattern) end

--- 路径是否存在（跟随符号链接）。
---
--- - 路径相对 `psc.cwd` 解析；绝对路径直接用
---
--- Whether the path exists (follows symlinks).
---
--- - Paths resolve relative to `psc.cwd`; absolute paths are used as-is
---@param path string
---@return boolean
function psc.exist(path) end

--- 读取环境变量；未设置返回 `nil`。
---
--- Reads an environment variable; `nil` if unset.
---@param name string|"HOME"|"USERPROFILE"|"APPDATA"|"LOCALAPPDATA"|"TEMP"|"TMP"|"TMPDIR"|"PATH"|"PATHEXT"|"SHELL"|"COMSPEC"|"XDG_CONFIG_HOME"|"XDG_DATA_HOME"|"XDG_CACHE_HOME"|"XDG_STATE_HOME"|"MSYSTEM"|"MSYS"|"MINGW_PREFIX"|"OS"|"SYSTEMROOT"|"WINDIR"
---@return string?
function psc.env(name) end

--- 在 PATH 中查找可执行文件，返回完整路径；找不到返回 `nil`。
---
--- Full path of the first executable found in PATH; `nil` when not found.
---@param name string
---@return string|nil
function psc.which(name) end

-- ===================== 数据操作 =====================

--- 数组映射：对每个元素应用 fn，返回等长新数组；fn 必填。
---
--- Array map: applies fn to each element, returns a new array of the same length; fn is required.
---@generic T, U
---@param list T[]
---@param fn fun(elem: T): U
---@return U[]
function psc.map(list, fn) end

--- 通用数组过滤：保留 `fn` 返回真值的元素（结果被压缩，是 `psc.map` 的互补）。
--- - `list`：任意数组
--- - `fn`：判定函数，返回 truthy 保留该元素（仅 nil 和 false 为假）
--- - 按补全项 name 过滤用 `fn` 检查 `it.name`，如 `psc.filter(items, function(it) return psc.eq(it.name, "x") end)`
---
--- Generic array filter: keeps the elements for which `fn` is truthy (compacted; the
--- complementary operation to `psc.map`).
--- - `list`: any array
--- - `fn`: predicate; truthy keeps the element (only nil and false are falsy)
--- - Filtering completion items by name: `psc.filter(items, function(it) return psc.eq(it.name, "x") end)`
---@generic T
---@param list T[]
---@param fn fun(elem: T): any
---@return T[]
function psc.filter(list, fn) end

--- 数组合并（可变参数，接受任意多个数组）。
---
--- Merges arrays (variadic, accepts any number).
---@vararg any[]
---@return any[]
function psc.concat(...) end

--- 将字符串分割成数组
--- - `text`：要拆分的字符串
--- - `separator`（可选）：分隔符，默认一个空格；传空串 `""` 时返回 `{ text }`（不拆分）
---
--- Splits a string into an array.
--- - `text`: the string to split
--- - `separator` (optional): the separator, default a space; `""` returns `{ text }` (no split)
---@param text string
---@param separator? string|"\\n"|","|";"
---@return string[]
function psc.split(text, separator) end

--- 合并为字符串
--- - `value`：字符串（原样返回）或数组（元素 join 成字符串，非字符串元素用 tostring 转换）
--- - `separator`（可选）：分隔符，默认一个空格
---
--- Joins into a string.
--- - `value`: a string (returned as-is) or an array (elements joined; non-strings are tostring'd)
--- - `separator` (optional): the separator, default a space
---@param value string|string[]
---@param separator? string|"\\n"|","|";"
---@return string
function psc.join(value, separator) end

--- 匹配判断。
---
--- - `haystack`：要匹配的内容，字符串或数组均可
---   - 字符串直接匹配
---   - 数组任一元素匹配即真
--- - `needle`：要找的内容（精确值或 Lua pattern）
--- - `opts`（可选）：
---   - 默认：忽略大小写 + 精确匹配
---   - `pattern = true`：`needle` 按 Lua pattern 匹配
---   - `case_sensitive = true`：区分大小写精确匹配
---
--- Match check.
---
--- - `haystack`: the content to match — a string or an array
---   - A string is matched directly
---   - An array matches when any element does
--- - `needle`: what to look for (an exact value or a Lua pattern)
--- - `opts` (optional):
---   - Default: case-insensitive exact match
---   - `pattern = true`: `needle` is matched as a Lua pattern
---   - `case_sensitive = true`: case-sensitive exact match
---@param haystack string|string[]
---@param needle string
---@param opts? { pattern?: boolean, case_sensitive?: boolean }
---@return boolean
function psc.contains(haystack, needle, opts) end

--- 字符串相等判断。
---
--- - `a`：要比较的字符串
--- - `b`：要比较的字符串
--- - `opts`（可选）：
---   - 默认：忽略大小写
---   - `case_sensitive = true`：区分大小写
---
--- String equality check.
---
--- - `a`: the first string
--- - `b`: the second string
--- - `opts` (optional):
---   - Default: case-insensitive
---   - `case_sensitive = true`: case-sensitive
---@param a string
---@param b string
---@param opts? { case_sensitive?: boolean }
---@return boolean
function psc.eq(a, b, opts) end

--- 去除空白。
---
--- - `text`：要处理的字符串
--- - `opts`（可选）：`mode` 为 `"start"`（去开头）/ `"end"`（去末尾）/ `"both"`（首尾，默认）
---
--- Trims whitespace.
---
--- - `text`: the string to process
--- - `opts` (optional): `mode` is `"start"` / `"end"` / `"both"` (default)
---@param text string
---@param opts? { mode?: "start"|"end"|"both" }
---@return string
function psc.trim(text, opts) end

-- ===================== 调试工具 =====================

--- 调试输出
---
--- - 接受任意多个参数，写入 `data/temp/log/debug.log`
--- - **注意**：
---   - hooks 默认有 10s 的结果缓存，10s 内仅运行一次
---   - 临时禁用缓存以实时调试: `psc config menu enable_cache 0`
---
--- Debug output.
---
--- - Accepts any number of arguments, and writes to `data/temp/log/debug.log`.
--- - **Note**:
---   - Hooks have a default 10-second result cache and will run only once within 10 seconds.
---   - For live debugging, temporarily disable the cache: `psc config menu enable_cache 0`
---@deprecated 仅调试阶段使用（debugging only）
---@vararg any
function psc.log(...) end
