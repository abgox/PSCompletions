//! Output rendering: the `Out` sink, `<@Tag>` color markup, and the JSON-contract failure exit (`err` / `fail`).

use std::io::IsTerminal;
use std::process::ExitCode;

pub struct Out {
    pub color: bool,
}

impl Out {
    pub fn new() -> Self {
        Out {
            color: std::io::stdout().is_terminal(),
        }
    }
    pub fn line(&self, s: &str) {
        println!("{}", self.render(s));
    }
    pub fn render(&self, s: &str) -> String {
        if self.color {
            colorize(s)
        } else {
            strip_colors(s)
        }
    }
}

impl Default for Out {
    fn default() -> Self {
        Self::new()
    }
}

fn color_code(tag: &str) -> &'static str {
    match tag {
        "Green" => "\x1b[32m",
        "Red" => "\x1b[31m",
        "Cyan" => "\x1b[36m",
        "Magenta" => "\x1b[35m",
        "Blue" => "\x1b[34m",
        "Yellow" => "\x1b[33m",
        _ => "\x1b[0m",
    }
}

fn colorize(s: &str) -> String {
    let mut out = String::new();
    let mut rest = s;
    while let Some(start) = rest.find("<@") {
        out.push_str(&rest[..start]);
        rest = &rest[start + 2..];
        if let Some(end) = rest.find('>') {
            out.push_str(color_code(&rest[..end]));
            rest = &rest[end + 1..];
        } else {
            out.push_str("<@");
            break;
        }
    }
    out.push_str(rest);
    out
}

fn strip_colors(s: &str) -> String {
    let mut out = String::new();
    let mut rest = s;
    while let Some(start) = rest.find("<@") {
        out.push_str(&rest[..start]);
        rest = &rest[start + 2..];
        if let Some(end) = rest.find('>') {
            rest = &rest[end + 1..];
        } else {
            out.push_str("<@");
            break;
        }
    }
    out.push_str(rest);
    out
}

/// A value as the text mode shows it, before any display convention: a string as itself, a number or boolean in its own form, an absent value as nothing, anything else in compact JSON.
/// The template renderer and the commands' listings both start from this.
pub fn value_text(v: &serde_json::Value) -> String {
    match v {
        serde_json::Value::String(s) => s.clone(),
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::Null => String::new(),
        serde_json::Value::Bool(b) => b.to_string(),
        other => other.to_string(),
    }
}

/// The text mode's one display convention: quote a value whose surrounding whitespace would otherwise disappear — an all-space or padded value would read as a different one.
/// An empty value stays blank, because blank already says "nothing" whereas `""` reads as two characters (design/json.md §3).
pub fn value_quoted(v: &serde_json::Value) -> String {
    let s = value_text(v);
    if s.trim() != s {
        // Single quotes only when they cannot clash; otherwise double quotes.
        // Never give up the quotes: that would swallow the very whitespace they exist to show.
        if s.contains('"') && !s.contains('\'') {
            format!("'{s}'")
        } else {
            format!("\"{s}\"")
        }
    } else {
        s
    }
}

/// A `key: value` listing line.
/// An empty value ends at the colon: the separator is only there to set the value apart, and a trailing space is an invisible byte in captured output.
pub fn key_line(key: &str, value: &str) -> String {
    if value.is_empty() {
        format!("{key}:")
    } else {
        format!("{key}: {value}")
    }
}

/// A whole-command failure in both modes: the text mode prints the message, the JSON mode the envelope with a stable `code` beside it.
/// `usage` selects the exit code — a usage error is `2`, anything else `1` — so a caller can tell "you asked wrong" from "it did not work".
pub fn fail(out: &Out, code: &str, msg: &str, json: bool, usage: bool) -> ExitCode {
    fail_details(out, code, msg, None, json, usage)
}

/// `fail` plus the structured parts of a failure (`design/json.md` §4): a machine caller reads `details` instead of parsing a localized `message`.
/// Only a site that actually has parts passes them; every other site keeps calling `fail`.
pub fn fail_details(
    out: &Out,
    code: &str,
    msg: &str,
    details: Option<serde_json::Value>,
    json: bool,
    usage: bool,
) -> ExitCode {
    if json {
        return err(code, msg, details, usage);
    }
    out.line(msg);
    if usage {
        ExitCode::from(2)
    } else {
        ExitCode::FAILURE
    }
}

/// The `--json` envelope: every command answers with one object — `ok`, the payload in `data`, and `meta` about this run — so a caller never has to guess the shape (design/json.md).
pub fn ok(data: &serde_json::Value) -> ExitCode {
    println!(
        "{}",
        serde_json::to_string(&serde_json::json!({ "ok": true, "data": data })).unwrap_or_default()
    );
    ExitCode::SUCCESS
}

/// A failure, in the envelope's `error` object: a stable `code` a machine branches on, a `message` a human reads (localized), and optional `details` for the parts.
/// `usage` selects the exit code: a usage error is `2`, anything else `1`.
pub fn err(code: &str, message: &str, details: Option<serde_json::Value>, usage: bool) -> ExitCode {
    let mut error = serde_json::json!({ "code": code, "message": message });
    if let Some(d) = details {
        error["details"] = d;
    }
    println!(
        "{}",
        serde_json::to_string(&serde_json::json!({ "ok": false, "error": error }))
            .unwrap_or_default()
    );
    if usage {
        ExitCode::from(2)
    } else {
        ExitCode::FAILURE
    }
}

/// `meta`: the payload's item count (when it has one) plus where this run reads from — the directories and files, in the same vocabulary the host and the module use.
/// The two log files are derived here: the engine writes them, so the module does not carry them.
pub fn run_paths(data_dir: &str) -> serde_json::Value {
    paths(data_dir, cfg!(windows))
}

/// A path as this platform writes it.
/// The module builds its own paths with `/` (the Linux side needs that shape) and hands a data dir of either form back, so a Windows reply would otherwise mix separators — `D:\data/temp/cache` is a string no Windows tool would print.
pub fn display_path(path: &str, windows: bool) -> String {
    if windows {
        path.replace('/', "\\")
    } else {
        path.to_string()
    }
}

/// The same block for a named platform, so a test can pin the Windows shape on any host.
fn paths(data_dir: &str, windows: bool) -> serde_json::Value {
    let sep = if windows { "\\" } else { "/" };
    let data = display_path(data_dir, windows);
    let temp = format!("{data}{sep}temp");
    serde_json::json!({
        "dir": {
            "data": data.clone(),
            "completions": format!("{data}{sep}completions"),
            "temp": temp.clone(),
            "menu": format!("{temp}{sep}menu"),
            "cache": format!("{temp}{sep}cache"),
            "log": format!("{temp}{sep}log"),
            "order": format!("{temp}{sep}order"),
        },
        "file": {
            "settings": format!("{data}{sep}settings.json"),
            "completions": format!("{temp}{sep}completions.json"),
            "change": format!("{temp}{sep}change.json"),
            "debug": format!("{temp}{sep}log{sep}debug.log"),
            "error": format!("{temp}{sep}log{sep}error.log"),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn colorize_maps_known_tags_and_keeps_unknown_text() {
        assert_eq!(colorize("<@Green>ok"), "\x1b[32mok");
        assert_eq!(colorize("a<@Red>b<@>c"), "a\x1b[31mb\x1b[0mc");
        // Unknown tag falls back to reset.
        assert_eq!(colorize("<@Nope>x"), "\x1b[0mx");
    }

    #[test]
    fn strip_colors_removes_tags_but_keeps_content() {
        assert_eq!(strip_colors("<@Green>ok"), "ok");
        assert_eq!(strip_colors("a<@Red>b<@>c"), "abc");
        // An unterminated tag is kept verbatim.
        assert_eq!(strip_colors("x<@Red"), "x<@Red");
    }

    #[test]
    fn run_paths_names_the_paths_the_way_the_module_does() {
        // The POSIX shape, named explicitly: `run_paths` follows the host, and a test must not.
        let m = paths("/d", false);
        assert_eq!(m["dir"]["data"], serde_json::json!("/d"));
        assert_eq!(m["dir"]["completions"], serde_json::json!("/d/completions"));
        assert_eq!(m["dir"]["log"], serde_json::json!("/d/temp/log"));
        assert_eq!(
            m["file"]["completions"],
            serde_json::json!("/d/temp/completions.json")
        );
        assert_eq!(
            m["file"]["debug"],
            serde_json::json!("/d/temp/log/debug.log")
        );
        assert_eq!(
            m["file"]["error"],
            serde_json::json!("/d/temp/log/error.log")
        );
        // The item count is gone: a caller counts the array it was given.
        assert!(m.get("count").is_none());
    }

    #[test]
    fn run_paths_keeps_one_separator_on_windows() {
        // The module hands over a native data dir and everything is derived from it, so every derived path must use the same separator: `D:\data\temp\cache` is one path, and a stray `/` in it is a string no Windows tool prints.
        let m = paths(r"D:\abgox\data", true);
        assert_eq!(m["dir"]["data"], serde_json::json!(r"D:\abgox\data"));
        assert_eq!(
            m["dir"]["cache"],
            serde_json::json!(r"D:\abgox\data\temp\cache")
        );
        assert_eq!(
            m["file"]["debug"],
            serde_json::json!(r"D:\abgox\data\temp\log\debug.log")
        );
        // A data dir that already carries the other slash is normalised, not echoed back mixed.
        let m = paths("D:/abgox/data", true);
        assert_eq!(
            m["dir"]["log"],
            serde_json::json!(r"D:\abgox\data\temp\log")
        );
    }

    #[test]
    fn value_quoted_only_quotes_when_whitespace_would_be_lost() {
        // An empty value needs no marker: blank already says "nothing".
        assert_eq!(value_quoted(&serde_json::json!("")), "");
        // Surrounding whitespace would disappear in the rendering, so it keeps its quotes.
        assert_eq!(value_quoted(&serde_json::json!("  ")), "\"  \"");
        assert_eq!(value_quoted(&serde_json::json!(" a ")), "\" a \"");
        // A value carrying both quote kinds is still quoted, so its padding stays visible.
        assert_eq!(value_quoted(&serde_json::json!(" a\"b'c ")), "\" a\"b'c \"");
        assert_eq!(value_quoted(&serde_json::json!("plain")), "plain");
        assert_eq!(value_quoted(&serde_json::json!(1)), "1");
        assert_eq!(value_quoted(&serde_json::json!(null)), "");
    }

    #[test]
    fn key_line_leaves_no_trailing_space_for_an_empty_value() {
        assert_eq!(key_line("url", ""), "url:");
        assert_eq!(key_line("language", "zh-CN"), "language: zh-CN");
    }

    #[test]
    fn err_uses_the_usage_exit_code() {
        assert_eq!(err("bad_flag", "nope", None, true), ExitCode::from(2));
        assert_eq!(err("io", "nope", None, false), ExitCode::FAILURE);
    }

    #[test]
    fn render_follows_the_color_flag() {
        let plain = Out { color: false };
        assert_eq!(plain.render("<@Cyan>cyan"), "cyan");
    }
}
