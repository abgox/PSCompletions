# Changelog

[English](./CHANGELOG.md) | 简体中文

## 8.0.4

- cli: 限制 `--self-update` 更新检查的时长，并打印出当前正在等待的事项
- cli: 默认改用 raw CDN 地址，下载不再多付一次重定向
- cli: 信息页与自更新报告末尾加入赞助商区块，指向赞助页面
- cli: 修复了模块在 CLI 之外升级后 `--self-update` 报出虚假降级的问题，并改为不再只信陈旧缓存、会重新向源确认

## 8.0.3

- hooks: hook 运行时不再克隆已解析的清单并改从字节解析，大型补全打开更快
- hooks: 不再为每个 `psc.on` 目标做全清单遍历，大型补全打开时不再有之前的卡顿
- cli: `rm psc` 会被拒绝，它只能用 `add`/`update` 刷新/更新
- cli: 修复了未受管理的副本上 `psc --self-update` 已安装版本为空的问题
- bridge: 修复了所有补全都已最新时 `psc update` 没有任何输出的问题
- cli: 修复了 `psc --self-update` 对 scoop 安装的识别，无论走 `modules\PSCompletions` 链接还是 `apps\<name>` 目录
- bridge: `psc --self-update` 之后不再重复提示模块更新

## 8.0.2

- bridge: 修复了 git bash 下因 python 输出 CRLF 换行导致选择失败的问题
- bridge: 读取单个补全配置值不再显示为绿色
- bridge: 已是最新版本时不再错误提示有模块更新
- bridge: `psc update` 不再重复列出可更新补全
- cli: `psc --json` 现在报告已安装版本，不再是补全库基线
- cli: 修复了 Windows 上 `psc --json` 与 `psc info` 输出路径混用分隔符的问题

## 8.0.1

- cli: `psc --self-update` 不再重复显示安装脚本已经打印的内容
- cli: 自更新失败的消息现在按模块语言显示
- bridge: 修复了因发布包带 Windows 换行符而无法加载的问题

## 8.0.0

> PSCompletions(psc) 正式转变为通用的补全管理器 —— 单个引擎，多个 Shell

### 单个引擎，多个 Shell

- **支持 bash、zsh、fish**：相同的引擎和交互式菜单，同时服务 bash、zsh、fish 以及 Windows PowerShell 5.1 与 PowerShell 7
- **不装 PowerShell 也能安装**：`install.sh`
- **各平台体验一致**：触发键、菜单、过滤、历史排序、提示信息等
- **原生补全步调一致**：当宿主提供自己的候选项时，引擎负责推导过滤条件并以索引作答
- **各平台输出一致**：`psc list` / `info` / `alias` / `config` / `completion` 在所有 Shell 中都输出引擎的文本

### 其他变化

- cli: 新增 `--json` 选项 —— 每条命令都能输出一个机器可读的对象
- cli: 新增 `--self-update`，用于自更新
- cli: 首次使用非官方补全源会给出警告
- cli: `psc add` 移除 `--all` 选项 —— 请按需安装，避免补全变体相互覆盖
- cli: 触发别名的归属改由声明顺序决定 —— 被多个补全声明的别名归后声明的那个
- menu: 前置的 `sudo` 在补全与历史排序中都会被跳过，历史排序现在区分大小写
- menu: 分隔符（`|`、`;`、`&`、`&&`、`||`）之后视为一条新命令 —— `git status | grep <Tab>` 补全的是 `grep`；引号内的分隔符仍是普通文本
- hooks: `psc.mount_items` 的路径链条与清单结构精确对应并包含别名
- hooks: `tip` / `usage` / `example` 支持延迟求值的函数与 `{ cmd, desc }` 形式
- completion: `config.json` 新增 `version` 字段 —— 该补全撰写与校验时对标的命令版本
- chore: 其他的优化和修复

## [历史版本](./archive/CHANGELOG.zh-CN.md)
