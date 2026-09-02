//! Embedded bilingual CLI messages (`key -> (zh-CN, en-US)`).

/// CLI messages: `key -> (zh-CN, en-US)`. Plain text only (the manifest `info` templates are
/// PowerShell-bound). Adding a message = add a row.
const MESSAGES: &[(&str, &str, &str)] = &[
    ("param_min", "参数不足。", "Too few parameters."),
    ("sub_cmd", "子命令错误。", "Invalid subcommand."),
    ("no_completion", "尚未添加该补全。", "Completion not added."),
    (
        "not_available",
        "不是一个可用的补全。",
        "is not an available completion.",
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
    ("config_val", "配置值无效。", "Invalid config value."),
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
    ("add_done", "已添加。", "Added."),
    ("update_done", "已更新。", "Updated."),
    ("rm_done", "已移除。", "Removed."),
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
        "链接补全，已跳过更新。",
        "Linked completion, update skipped.",
    ),
    (
        "has_wildcard",
        "不能包含通配符。",
        "Cannot contain wildcards.",
    ),
    (
        "cmd_exist",
        "与已有命令或别名冲突。",
        "Conflicts with an existing command or alias.",
    ),
    ("alias_exist", "该别名已存在。", "The alias already exists."),
    (
        "alias_unique",
        "不能移除最后一个触发器别名。",
        "Cannot remove the last trigger alias.",
    ),
    (
        "alias_not_found",
        "指定的触发器别名不存在。",
        "The specified trigger alias does not exist.",
    ),
];

/// Look up a bilingual CLI message (zh if the language starts with `zh`, else en).
pub fn msg_cli(lang: &str, key: &str) -> String {
    let zh = lang.starts_with("zh");
    MESSAGES
        .iter()
        .find(|(k, _, _)| *k == key)
        .map(|(_, z, e)| if zh { z.to_string() } else { e.to_string() })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn msg_cli_selects_language_by_prefix() {
        assert_eq!(msg_cli("zh-CN", "param_min"), "参数不足。");
        assert_eq!(msg_cli("zh-TW", "param_min"), "参数不足。");
        assert_eq!(msg_cli("en-US", "param_min"), "Too few parameters.");
        // Any non-zh language falls back to the English column.
        assert_eq!(msg_cli("de-DE", "param_min"), "Too few parameters.");
    }

    #[test]
    fn msg_cli_unknown_key_yields_empty_string() {
        assert_eq!(msg_cli("en-US", "no_such_key"), "");
        assert_eq!(msg_cli("zh-CN", "no_such_key"), "");
    }
}
