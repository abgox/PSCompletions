//! Embedded bilingual CLI messages (`key -> (zh-CN, en-US)`).

/// CLI messages: `key -> (zh-CN, en-US)`.
/// Plain text only (the manifest `info` templates are PowerShell-bound).
/// Adding a message = add a row.
const MESSAGES: &[(&str, &str, &str)] = &[
    ("too_few_params", "参数不足。", "Too few parameters."),
    ("too_many_params", "参数过多。", "Too many parameters."),
    ("invalid_subcommand", "子命令错误。", "Invalid subcommand."),
    (
        "invalid_subcommand_named",
        "无效的子命令: {{Token}}。可用: {{Valid}}",
        "Invalid subcommand: {{Token}}. Valid: {{Valid}}",
    ),
    (
        "needs_confirmation",
        "该操作具有破坏性，需要确认：请加 --yes 以授权。",
        "This operation is destructive and needs confirmation: pass --yes to authorise it.",
    ),
    ("not_installed", "尚未添加该补全。", "Completion not added."),
    (
        "not_available",
        "不是一个可用的补全。",
        "is not an available completion.",
    ),
    (
        "not_in_library",
        "不在补全库中。",
        "is not in the completion library.",
    ),
    ("config_done", "配置修改成功。", "Config updated."),
    (
        "completion_done",
        "补全配置修改成功。",
        "Completion config updated.",
    ),
    (
        "alias_done",
        "触发器别名修改成功。",
        "Trigger aliases updated.",
    ),
    (
        "one_or_zero",
        "该配置只接受 0 或 1。",
        "This option only accepts 0 or 1.",
    ),
    ("config_value", "配置值无效。", "Invalid config value."),
    (
        "language_no_reset",
        "language 不是一个恒定的配置值，无法重置。",
        "language is not a constant config value and cannot be reset.",
    ),
    (
        "no_hooks",
        "该补全没有动态 hooks。",
        "This completion has no dynamic hooks.",
    ),
    (
        "url_untrusted",
        "警告：正在使用非官方补全源，其 hooks.lua 将以你的权限执行，请确认你信任该来源。",
        "Warning: using a non-official completion source; its hooks.lua will run with your privileges. Proceed only if you trust it.",
    ),
    (
        "psc_hooks_locked",
        "psc 自身的 hooks 不能禁用。",
        "psc hooks cannot be disabled.",
    ),
    ("add_done", "已添加。", "Added."),
    ("update_done", "已更新。", "Updated."),
    ("rm_done", "已移除。", "Removed."),
    (
        "rm_psc",
        "它是内置补全，不能被移除，只能更新 (psc update psc) 或重新添加 (psc add psc)",
        "it is the built-in completion and cannot be removed; only update (psc update psc) or re-add (psc add psc)",
    ),
    ("updatable", "可更新的补全：", "Updatable completions:"),
    (
        "lib_add",
        "补全库中新增：",
        "Newly available in the library:",
    ),
    ("lib_rm", "从补全库中移除：", "Removed from the library:"),
    ("lib_rename", "补全库中重命名：", "Renamed in the library:"),
    ("rename_done", "已重命名为", "renamed to"),
    (
        "update_no",
        "所有补全都是最新的。",
        "All completions are up to date.",
    ),
    (
        "update_skip",
        "补全正在使用本地链接，已跳过。",
        "Completion is using a local link, skipped.",
    ),
    (
        "has_wildcard",
        "不能包含通配符。",
        "Cannot contain wildcards.",
    ),
    (
        "cmd_exist",
        "为保留名称，不可用。",
        "Reserved name, unavailable.",
    ),
    (
        "alias_not_found",
        "指定的触发器别名不存在。",
        "The specified trigger alias does not exist.",
    ),
    (
        "installer_failed",
        "安装脚本执行失败（退出码 {Code}）。",
        "The install script failed (exit code {Code}).",
    ),
    (
        "installer_fetch",
        "无法下载安装脚本（{Cause}）。",
        "Could not download the install script ({Cause}).",
    ),
    (
        "installer_downloading",
        "正在获取安装脚本……",
        "Fetching the installer...",
    ),
    (
        "checking_updates",
        "正在检查最新版本……",
        "Checking for the latest version...",
    ),
];

/// Look up a bilingual CLI message (zh if the language starts with `zh`, else en).
pub fn msg_cli(lang: &str, key: &str) -> String {
    msg_fmt(lang, key, &[])
}

/// Look up a message and substitute `{name}` placeholders with the given values.
/// An unknown key yields the key itself, never an empty error string.
pub fn msg_fmt(lang: &str, key: &str, vars: &[(&str, &str)]) -> String {
    let zh = lang.starts_with("zh");
    let mut text = MESSAGES
        .iter()
        .find(|(k, _, _)| *k == key)
        .map(|(_, z, e)| if zh { z.to_string() } else { e.to_string() })
        .unwrap_or_else(|| key.to_string());
    for (k, v) in vars {
        text = text.replace(&format!("{{{k}}}"), v);
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn msg_cli_selects_language_by_prefix() {
        assert_eq!(msg_cli("zh-CN", "too_few_params"), "参数不足。");
        assert_eq!(msg_cli("zh-TW", "too_few_params"), "参数不足。");
        assert_eq!(msg_cli("en-US", "too_few_params"), "Too few parameters.");
        // Any non-zh language falls back to the English column.
        assert_eq!(msg_cli("de-DE", "too_few_params"), "Too few parameters.");
    }

    #[test]
    fn msg_cli_unknown_key_yields_key() {
        assert_eq!(msg_cli("en-US", "no_such_key"), "no_such_key");
        assert_eq!(msg_cli("zh-CN", "no_such_key"), "no_such_key");
    }
}
