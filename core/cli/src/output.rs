//! Output rendering: the `Out` sink, `<@Tag>` color markup, and the JSON-contract
//! failure exit (`fail`).

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

/// Emit a whole-command failure per the output contract and return the matching exit code:
/// JSON mode → in-band `{"ok": false, "error": ...}` + exit 0; text mode → plain line +
/// exit FAILURE. Every early-return validation/runtime error must go through this so a
/// `--json` consumer always gets parseable output.
pub fn fail(out: &Out, msg: String, json: bool) -> ExitCode {
    if json {
        println!(
            "{}",
            serde_json::to_string(&serde_json::json!({ "ok": false, "error": msg }))
                .unwrap_or_default()
        );
        ExitCode::SUCCESS
    } else {
        out.line(&msg);
        ExitCode::FAILURE
    }
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
    fn render_follows_the_color_flag() {
        let plain = Out { color: false };
        assert_eq!(plain.render("<@Cyan>cyan"), "cyan");
    }

    #[test]
    fn fail_uses_exit_codes_per_mode() {
        let out = Out::new();
        // JSON mode: in-band error, exit SUCCESS (contract: --json always exits 0).
        assert_eq!(fail(&out, "boom".into(), true), ExitCode::SUCCESS);
        // Text mode: plain line + FAILURE. (Output goes to captured stdout.)
        assert_eq!(fail(&out, "boom".into(), false), ExitCode::FAILURE);
    }
}
