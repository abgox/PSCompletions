-- PSCompletions `hooks.lua` type definitions for the Lua language server (sumneko.lua / the VSCode "Lua" extension).
--
-- Authoritative API reference: `design/hooks.md`.
-- Descriptions are bilingual, Chinese first then English.
---@diagnostic disable: missing-return



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
--- 其他语言代码（可扩展；引擎按 psc.config.language → en-US → 首项回退）。
---
--- Other language codes (extensible; the engine falls back psc.config.language → en-US → first entry).
---@field [string] string



--- 补全项。
---
--- A completion item.
---@class psc_item
--- 补全项名称。
---
--- Completion item name.
---@field name string
--- 提示文本：字符串或本地化表（键为语言代码，值对应该语言文本）。
---
--- Tip (Description) text: a plain string or a localized table (keys are language codes).
---@field tip? string|psc_localized
--- 用法文本。
---
--- Usage text.
---@field usage? string
--- 示例文本。
---
--- Example text.
---@field example? string
--- 可重复使用次数。
---
--- How many times it may be used.
---@field repeat_count? integer



--- 已完成的输入 token。
---
--- A completed input token.
---@class psc_token
--- 规范名。
--- - 它会对用户的输入进行规范化
--- - 它会将别名转换成清单中定义的 `name`
---
--- Canonical name.
--- - It normalizes user input
--- - It converts aliases to the `name` defined in the list
---@field name string
--- token 类型。
---
--- - `"command"`: 在清单中被定义为 `next` 的命令
--- - `"option"`: 在清单中被定义为 `option` 的选项
--- - `"value"`: 被作为选项的值消费
--- - `"unknown"`: 完全自由的值（清单中未定义的未知值，除非它被作为选项的值消费）
---
--- Token type.
---
--- - `"command"`: the command defined as `next` in the manifest
--- - `"option"`: the option defined as `option` in the manifest
--- - `"value"`: consumed as an option's value
--- - `"unknown"`: a truly free-form value (undefined values in the manifest, unless it is consumed as an option's value)
---@field type "command"|"option"|"value"|"unknown"
--- 用户原始输入。
---
--- The user's original input.
---@field input string



--- 路径条目（文件/目录）。
---
--- A path entry (file/directory).
---@class psc_path_entry
--- 条目名。
---
--- Entry name.
---@field name string
--- 条目的完整路径。
---
--- The entry's full path.
---@field path string
--- 是否为目录。
---
--- Whether it is a directory.
---@field is_dir boolean
--- 是否为符号链接。
---
--- Whether it is a symbolic link.
---@field is_link boolean



--- 实时的补全候选项列表。
---
--- - 初始内容：引擎基于静态清单生成
--- - 在 hooks 中进行修改：使用 `psc.add` 进行追加，普通 Lua 表操作
---
--- The live completion candidate list.
---
--- - Initial content: The engine is generated based on a static list
--- - Change it in the hooks: `psc.add` appends; plain Lua table operations
---@type psc_item[]
completions = {}

--- 引擎注入的全局对象，提供 hooks 所需的变量和方法。
---
--- Global objects injected by the engine, providing variables and methods required by hooks.
---@class psc
psc = {}

-- ===================== 上下文值 / Context values =====================

--- 已完成的输入 token 列表。
---
--- Completed input tokens.
---@type psc_token[]
psc.tokens = {}

--- 当前正在输入的 token。
---
--- The token currently being typed.
---@class psc_typing
--- token 类型。
---
--- - `"command"`: 在清单中被定义为 `next` 的命令
--- - `"option"`: 在清单中被定义为 `option` 的选项
--- - `"value"`: 被作为选项的值消费
--- - `"unknown"`: 完全自由的值（清单中未定义的未知值，除非它被作为选项的值消费）
---
--- Token type.
---
--- - `"command"`: the command defined as `next` in the manifest
--- - `"option"`: the option defined as `option` in the manifest
--- - `"value"`: consumed as an option's value
--- - `"unknown"`: a truly free-form value (undefined values in the manifest, unless it is consumed as an option's value)
---@field type? "command"|"option"|"value"|"unknown"
--- 用户原始输入。
---
--- The user's original input.
---@field input? string
--- 是否以 `-` 开头（启发式判断：像选项，非确定）。
---
--- Whether the input starts with `-` (heuristic: looks like an option, not definitive).
---@field option_like boolean
psc.typing = { option_like = false }

--- 最终补全配置：`psc config` → 清单中的 `config` → `psc completion`
---
--- The final completion config: `psc config` → Manifest `config` → `psc completion`
---@class psc_config
---@field enable_tip boolean
---@field enable_tip_usage boolean
---@field enable_tip_example boolean
---@field language string|"en-US"|"zh-CN"
---@field [string] any
psc.config = {}

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

---@class psc_manifest_meta
---@field url string
---@field description string[]

---@class psc_manifest_usage_example
---@field cmd string
---@field desc string

---@class psc_manifest_next
---@field name string
---@field alias string[]
---@field tip string[]
---@field usage (string|psc_manifest_usage_example)[]
---@field example (string|psc_manifest_usage_example)[]
---@field repeat number
---@field option psc_manifest_option
---@field next psc_manifest_next

---@class psc_manifest_option
---@field name string
---@field alias string[]
---@field tip string[]
---@field usage (string|psc_manifest_usage_example)[]
---@field example (string|psc_manifest_usage_example)[]
---@field repeat number
---@field next psc_manifest_next

---@class psc_manifest_config
---@field name string
---@field value string|number
---@field values (string|number)[]
---@field tip string[]

--- 解析后的补全清单。
---
--- The parsed completion manifest.
---@class psc_manifest
---@field meta psc_manifest_meta
---@field next? psc_manifest_next[]
---@field option? psc_manifest_option[]
---@field global_option? psc_manifest_option[]
---@field config? psc_manifest_config
---@field info? table
psc.manifest = { meta = { url = "", description = {} } }

-- ===================== 补全项 API / Completion-item API =====================

--- `psc.on` 的注册规格。
---
--- The registration spec of `psc.on`.
---@class psc_on_spec
--- 命令链
---
--- - 必须为清单中定义的规范名（`name`）
--- - 与 `option` 同时设置表示 AND（需同时匹配）
--- - `""` 表示通配任意一段
---
--- Command chain
---
--- - Must be the canonical name (`name` in manifest)
--- - Coexisting with `option` as AND (both must match)
--- - `""` is a wildcard matching any segment
---@field command? string|string[]
--- 选项链（后缀匹配）
---
--- - 必须为清单中定义的规范名（`name`）
--- - 与 `option` 同时设置表示 AND（需同时匹配）
--- - `""` 表示通配任意一段
---
--- Option chain (suffix match)
---
--- - Must be the canonical name (`name` in manifest)
--- - Coexisting with `option` as AND (both must match)
--- - `""` is a wildcard matching any segment
---@field option? string|string[]
--- 是否允许多次匹配
---
--- - 它表示在位置槽被填过一次后仍继续匹配
--- - 主要用于可以多次使用同类动态补全的情况，例如 `psc add <xxx> <yyy>`
---
--- Whether multiple matches are allowed
---
--- - It means matching can continue even after a position slot has been filled once
--- - Mainly used for scenarios where the same type of dynamic completion can be used multiple times, e.g. `psc add <xxx> <yyy>`
---@field multiple? true

--- 声明式条件触发。
---
--- - `spec`: 决定触发时机，也可以是规格数组（任一规格命中）
---   - `command` 与 `option` 同时设置表示 AND（需同时匹配）
---   - `{}` 表示根级，`""` 表示通配任意一段
---   - `multiple`：位置槽被填过一次后仍继续匹配（默认 `false`）
---
--- Declarative conditional triggering.
--- - `spec`: Determines the trigger timing; it can also be a specification array (any specification matches)
---   - When `command` and `option` are set simultaneously, it means AND (both must match)
---   - `{}` denotes the root level, and `""` is a wildcard matching any segment
---   - `multiple`: keep matching after the location's slot was filled once (default `false`)
---
---@param spec psc_on_spec|psc_on_spec[]
---@param handler fun()
function psc.on(spec, handler) end

--- 把数组中的每一项转换为补全项。
---
--- - `items`：要转换的元素数组
--- - `fn`：通过返回值自定义补全项，返回 `nil` 跳过该元素
---
--- Converts each element in the array to a completion item.
---
--- - `items`: the array of elements to convert
--- - `fn`: customize completion items through return values; return `nil` to skip the element
---@generic T
---@param items T[]
---@param fn? fun(item: T): psc_item|nil
---@return psc_item[]
function psc.items(items, fn) end

--- 把清单路径上指定数组的 **直接子项** 转换为补全项。
---
--- - `manifest_path`：从清单的根出发的路径，最后一段必须是 `"next"` 或 `"option"`
--- - 主要用于复用清单中已经定义好的 `next` 或 `option` 数组
---
--- Converts the **direct children** of the specified array at the manifest path to completion items.
---
--- - `manifest_path`: a path from the manifest root; the last segment must be `"next"` or `"option"`
--- - It is mainly used to reuse the `next` or `option` arrays already defined in the list.
---@param manifest_path_chain string[]
---@return psc_item[]
function psc.mount_items(manifest_path_chain) end

--- 追加补全项到 `completions` 中。
---
--- - `item_or_items`：单个补全项或补全项数组
--- - 返回已存储的条目表（单个时返回表，多条时返回数组）
---
--- Appends the completion items to `completions`.
---
--- - `item_or_items`: a single item table or an array of items
--- - Returns the stored entry table(s) (single → table, multiple → array)
---@param item_or_items psc_item|psc_item[]
---@return psc_item|psc_item[]|nil
function psc.add(item_or_items) end

--- 在 `psc.tokens` 中按条件查找首个匹配的 token。
---
--- - `spec` 省略或空表 → 首个 token（任意 `type`）
--- - `spec.name` → 按 `name` 匹配
--- - `spec.type` → 按 `type` 过滤
--- - `spec.case_sensitive` 为 `true` 时大小写敏感，默认不敏感
--- - 未找到返回 `nil`
---
--- Finds the first matching token in `psc.tokens`.
---
--- - `spec` omitted or empty → first token (any `type`)
--- - `spec.name` → filter by `name`
--- - `spec.type` → filter by `type`
--- - `spec.case_sensitive` true → case-sensitive, default insensitive
--- - `nil` if not found
---@param spec? {name?: string, type?: "command"|"option"|"value"|"unknown", case_sensitive?: true}
---@return psc_token?
function psc.token(spec) end

-- ===================== 数据获取 / Data fetching =====================

--- `psc.run` / `psc.run_batch` 的可选参数。
---
--- Optional options for `psc.run` / `psc.run_batch`.
---@class psc_run_opts
--- 解析命令输出（`"json"` / `"toml"` / `"yaml"`），返回解析后的 table；失败返回 `nil`。
---
--- Parses the command output (`"json"` / `"toml"` / `"yaml"`) and returns the parsed table; `nil` on failure.
---@field format? "json"|"toml"|"yaml"
--- 超时毫秒，默认 5000。
---
--- Timeout in ms, default 5000.
---@field timeout? integer|1000|3000|5000
--- 命令工作目录，默认用户当前工作目录。
---
--- Command working directory, default the user's current directory.
---@field cwd? string
--- 通过系统 shell 执行（Windows `cmd /c`、其他 `sh -c`），用于无法直接启动的 batch/PowerShell shim（如 `scoop`）。
---
--- Runs through the system shell (`cmd /c` on Windows, `sh -c` elsewhere) — for batch/PowerShell shims that cannot be spawned directly (e.g. `scoop`).
---@field shell? true
--- 注入子进程环境变量的键值对表，与继承的环境合并。
---
--- Key-value pairs injected into the child process environment, merged with the inherited env.
---@field env? table<string, string>
--- 捕获额外文件描述符（如 `8` 用于 Python argcomplete，补全结果写到 fd 8），通过 `8>&1` 重定向到 stdout 捕获。
---
--- Captures an extra file descriptor (e.g. `8` for Python argcomplete which writes completions to fd 8), redirected to stdout via `8>&1`.
---@field capture_fd? integer|3|4|5|6|7|8|9

--- 运行命令，返回 stdout 行数组。
---
--- - `argv`：命令及其参数，如 `{ "git", "branch" }`
--- - 失败/超时返回 `nil`
---
--- Runs a command; returns stdout lines.
---
--- - `argv`: the command and its arguments, e.g. `{ "git", "branch" }`
--- - `nil` on failure/timeout
---@param argv string[]
---@param opts? psc_run_opts
---@return table|nil
function psc.run(argv, opts) end

--- 并发运行多条命令
---
--- - `cmds`：命令列表，每个元素是 `{ cmd, arg... }`
--- - 按输入顺序返回各自的 stdout 行
--- - 某条命令失败/超时为 `nil`
---
--- Runs several commands in parallel.
---
--- - `cmds`: a list of commands, each an `{ cmd, arg... }` array
--- - Returns their stdout lines in input order
--- - `nil` at an index when that command failed/timed out
---@param cmds string[][]
---@param opts? psc_run_opts
---@return table<number, table|nil>
function psc.run_batch(cmds, opts) end

--- 以 UTF-8 读取文件，返回原始文本。
---
--- - 如果是相对路径，会拼接 `psc.cwd`
--- - 失败返回 `nil`
---
--- Reads a file as UTF-8 text.
---
--- - If it is a relative path, `psc.cwd` will be concatenated
--- - `nil` on failure
---@param path string
---@return string?
function psc.read(path) end

--- 并行读取多个文件。
---
--- - 如果是相对路径，会拼接 `psc.cwd`
--- - 返回 `{ [path] = content, ... }`
--- - 缺失/不可读的为 `nil`
---
--- Reads multiple files in parallel.
---
--- - If it is a relative path, `psc.cwd` will be concatenated
--- - Returns `{ [path] = content, ... }`
--- - `nil` for missing/unreadable files
---@param paths string[]
---@return table<string, string|nil>
function psc.read_batch(paths) end

--- 读取 + 解析 JSON 文件。
---
--- - 如果是相对路径，会拼接 `psc.cwd`
--- - 失败返回 `nil`
---
--- Reads + parses a JSON file.
---
--- - If it is a relative path, `psc.cwd` will be concatenated
--- - `nil` on failure
---@param path string
---@return table<string, any>?
function psc.json(path) end

--- 并行读取 + 解析多个 JSON 文件。
---
--- - 如果是相对路径，会拼接 `psc.cwd`
--- - 失败返回 `nil`
---
--- Reads + parses multiple JSON files in parallel.
---
--- - If it is a relative path, `psc.cwd` will be concatenated
--- - `nil` on failure
---@param paths string[]
---@return table<string, table<string, any>|nil>
function psc.json_batch(paths) end

--- 读取 + 解析 TOML 文件。
---
--- - 如果是相对路径，会拼接 `psc.cwd`
--- - 失败返回 `nil`
---
--- Reads + parses a TOML file.
---
--- - If it is a relative path, `psc.cwd` will be concatenated
--- - `nil` on failure
---@param path string
---@return table<string, any>?
function psc.toml(path) end

--- 并行读取 + 解析多个 TOML 文件。
---
--- - 如果是相对路径，会拼接 `psc.cwd`
--- - 失败返回 `nil`
---
--- Reads + parses multiple TOML files in parallel.
---
--- - If it is a relative path, `psc.cwd` will be concatenated
--- - `nil` on failure
---@param paths string[]
---@return table<string, table<string, any>|nil>
function psc.toml_batch(paths) end

--- 读取 + 解析 YAML 文件。
---
--- - 如果是相对路径，会拼接 `psc.cwd`
--- - 失败返回 `nil`
---
--- Reads + parses a YAML file.
---
--- - If it is a relative path, `psc.cwd` will be concatenated
--- - `nil` on failure
---@param path string
---@return table<string, any>?
function psc.yaml(path) end

--- 并行读取 + 解析多个 YAML 文件。
---
--- - 如果是相对路径，会拼接 `psc.cwd`
--- - 失败返回 `nil`
---
--- Reads + parses multiple YAML files in parallel.
---
--- - If it is a relative path, `psc.cwd` will be concatenated
--- - `nil` on failure
---@param paths string[]
---@return table<string, table<string, any>|nil>
function psc.yaml_batch(paths) end

--- 规范化 / 拼接路径片段为一条路径，使用平台原生的路径分隔符。
---
--- - 单个参数：规范化其分隔符（Windows 上 `/` → `\`；其他平台保持 `/`）
--- - 多个参数：用平台原生分隔符拼接，并去除重复的分隔符
--- - 绝对路径段（前导分隔符）与盘符根（如 `C:\`）会被保留
---
--- Normalize / join path segments into one path using the platform's native separator.
---
--- - A single argument normalizes its separators (on Windows `/` → `\`; elsewhere `/` is kept)
--- - Multiple arguments are joined with the native separator, collapsing duplicates
--- - A leading separator (absolute segment) and a drive root like `C:\` are preserved
---@vararg string
---@return string
function psc.path(...) end

--- 列出路径条目（文件/目录）。
---
--- - 如果是相对路径，会拼接 `psc.cwd`
--- - 目录不存在返回 `nil`
--- - 每项为 `{ name, path, is_dir, is_link }`
--- - `name`：条目名
--- - `path`：条目的完整路径
--- - `is_dir`：是否为目录（跟随符号链接判断）
--- - `is_link`：是否为符号链接
---
--- Lists path entries (files and directories)
---
--- - If it is a relative path, `psc.cwd` will be concatenated
--- - `nil` if the directory does not exist
--- - Each as `{ name, path, is_dir, is_link }`
--- - `name`: entry name
--- - `path`: the entry's full path
--- - `is_dir`: whether it is a directory (follows symlinks)
--- - `is_link`: whether it is a symbolic link
---@param path string
---@return psc_path_entry[]|nil
function psc.ls(path) end

--- 并发列出多个路径条目（文件/目录）。
---
--- - 按输入顺序返回各自的条目
--- - 如果是相对路径，会拼接 `psc.cwd`
--- - 目录不存在时该位为 `nil`
---
--- Lists several directories in parallel.
---
--- - Returns their entries in input order
--- - If it is a relative path, `psc.cwd` will be concatenated
--- - `nil` at an index for a missing dir
---@param dirs string[]
---@return table<number, psc_path_entry[]|nil>
function psc.ls_batch(dirs) end

--- glob 匹配。
---
--- - 支持 `*`、`?`、`**`、`{a,b}` 交替（`globset`）
--- - 路径相对 `psc.cwd` 解析（绝对路径 pattern 忽略 `psc.cwd`）
--- - 遍历尊重 `.gitignore`/`.ignore`/`.git/info/exclude`（如 ripgrep），被忽略的文件不返回
--- - 返回匹配的绝对路径
--- - 无效 pattern 返回 `nil`
---
--- Glob matching.
---
--- - supports `*`, `?`, `**`, and `{a,b}` alternation (`globset`)
--- - The pattern resolves against `psc.cwd` (an absolute pattern ignores it)
--- - The walk respects `.gitignore`/`.ignore`/`.git/info/exclude` (like ripgrep) — ignored files are not returned
--- - Returns matched absolute paths
--- - `nil` for an invalid pattern
---@param pattern string
---@return string[]|nil
function psc.glob(pattern) end

--- 路径是否存在。
---
--- - 如果是相对路径，会拼接 `psc.cwd`
---
--- Whether the path exists.
---
--- - If it is a relative path, `psc.cwd` will be concatenated
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

-- ===================== 数据操作 / Data operation =====================

--- 数组合并。
---
--- Merges arrays.
---@generic T
---@vararg T[]
---@return T[]
function psc.concat(...) end

--- 将字符串分割成数组。
--- - `text`：要拆分的字符串（`nil` 返回空数组）
--- - `separator`：分隔符，默认一个空格
---
--- Splits a string into an array.
--- - `text`: the string to split (`nil` yields empty array)
--- - `separator`: the separator, default a space
---@param text string|nil
---@param separator? string|"\\n"|","|";"
---@return string[]
function psc.split(text, separator) end

--- 合并为字符串。
--- - `value`：字符串（原样返回）或数组（元素 join 成字符串，非字符串元素用 tostring 转换，`nil` 返回空字符串）
--- - `separator`：分隔符，默认一个空格
---
--- Joins into a string.
--- - `value`: a string (returned as-is) or an array (elements joined; non-strings are tostring'd; `nil` yields empty string)
--- - `separator`: the separator, default a space
---@param value string|string[]|nil
---@param separator? string|"\\n"|","|";"
---@return string
function psc.join(value, separator) end

---@class psc_trim_opts
--- 剔除位置：`"start"`（开头）/ `"end"`（末尾）/ `"both"`（首尾，默认）。
---
--- Where to trim: `"start"` / `"end"` / `"both"` (default).
---@field mode? "start"|"end"|"both"
--- 要去除的字符串；默认去除空白。
---
--- The characters to trim; defaults to whitespace.
---@field chars? string

--- 去除指定字符。
---
--- - `text`：要处理的字符串（`nil` 返回空字符串）
--- - `opts`（可选）：
---   - `mode`：`"start"`（去开头）/ `"end"`（去末尾）/ `"both"`（首尾，默认）
---   - `chars`：要去除的字符串；默认去除空白
---
--- Trims characters.
---
--- - `text`: the string to process (`nil` yields empty string)
--- - `opts` (optional):
---   - `mode`: `"start"` / `"end"` / `"both"` (default)
---   - `chars`: the characters to trim; defaults to whitespace
---@param text string|nil
---@param opts? psc_trim_opts
---@return string
function psc.trim(text, opts) end

---@class psc_contains_opts
--- `needle` 按 Lua pattern 匹配。
---
--- `needle` is matched as a Lua pattern.
---@field pattern? true
--- 区分大小写。
---
--- Case-sensitive.
---@field case_sensitive? true

--- 匹配判断。
---
--- - `haystack`：要匹配的内容，字符串精确相等或数组成员
---   - 字符串：与 `needle` 精确相等即真
---   - 数组：任一元素匹配即真
--- - `needle`：要找的内容
--- - `opts`（可选）：
---   - 默认：忽略大小写 + 精确匹配
---   - `pattern = true`：`needle` 按 Lua pattern 匹配
---   - `case_sensitive = true`：区分大小写精确匹配
---
--- Match check.
---
--- - `haystack`: the content to match — string exact equality or array membership
---   - A string matches when it equals `needle` exactly
---   - An array matches when any element does
--- - `needle`: what to look for
--- - `opts` (optional):
---   - Default: case-insensitive exact match
---   - `pattern = true`: `needle` is matched as a Lua pattern
---   - `case_sensitive = true`: case-sensitive exact match
---@param haystack string|string[]
---@param needle string
---@param opts? psc_contains_opts
---@return boolean
function psc.contains(haystack, needle, opts) end

---@class psc_eq_opts
--- 区分大小写。
---
--- Case-sensitive.
---@field case_sensitive? true

--- 字符串相等判断。
---
--- - `s1`：要比较的字符串
--- - `s2`：要比较的字符串
--- - `opts`（可选）：
---   - 默认：忽略大小写
---   - `case_sensitive = true`：区分大小写
---
--- String equality check.
---
--- - `s1`: the first string
--- - `s2`: the second string
--- - `opts` (optional):
---   - Default: case-insensitive
---   - `case_sensitive = true`: case-sensitive
---@param s1 string
---@param s2 string
---@param opts? psc_eq_opts
---@return boolean
function psc.eq(s1, s2, opts) end

-- ===================== 调试工具 / Debugging =====================

--- 调试输出
---
--- - 接受任意参数，写入 `data/temp/log/debug.log`
---     ```powershell
---     Join-Path $PSCompletions.path.log 'debug.log'
---     Join-Path $PSCompletions.path.log 'error.log'
---     ```
--- - **注意**：
---   - hooks 默认有 10 秒的结果缓存，10 秒内仅运行一次
---   - 临时禁用缓存以实时调试: `psc config menu enable_cache 0`
---
--- Debug output.
---
--- - Accepts any number of arguments, and writes to `data/temp/log/debug.log`
---     ```powershell
---     Join-Path $PSCompletions.path.log 'debug.log'
---     Join-Path $PSCompletions.path.log 'error.log'
---     ```
--- - **Note**:
---   - Hooks have a default 10-second result cache and will run only once within 10 seconds
---   - For live debugging, temporarily disable the cache: `psc config menu enable_cache 0`
---@deprecated 仅调试阶段使用 | Debugging only
---@vararg any
function psc.log(...) end
