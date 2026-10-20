//! `psc info` - completion metadata (no-arg lists all installed).

use std::process::ExitCode;

use serde_json::json;

use crate::data::{Index, Settings};
use crate::messages::msg_cli;
use crate::output::{display_path, ok, Out};
use crate::validate::{name_error, name_status};
/// A Unix timestamp as the human view shows it.
/// The engine carries no timezone database, so this is UTC and says so; the JSON keeps the raw seconds (design/json.md §3).
fn utc_stamp(secs: u64) -> String {
    let days = (secs / 86_400) as i64;
    let rem = secs % 86_400;
    // Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let mut y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    if m <= 2 {
        y += 1;
    }
    format!(
        "{y:04}-{m:02}-{d:02} {:02}:{:02}:{:02} UTC",
        rem / 3_600,
        (rem % 3_600) / 60,
        rem % 60
    )
}

pub fn cmd_info(
    args: &[String],
    settings: &Settings,
    index: &Index,
    completions_dir: &str,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    let lang = lang.to_string();
    let owned;
    let args: &[String] = if args.is_empty() {
        // Claim order, the same order every listing uses (design/psc-cli.md §6.2).
        owned = settings.alias.keys().cloned().collect::<Vec<String>>();
        &owned
    } else {
        args
    };
    if json {
        let mut entries = Vec::new();
        for name in args {
            let status = name_status(settings, index, completions_dir, name);
            if name_error(&lang, name, status, false).is_some() {
                // The message stays name-free: the host renders `name: message` itself.
                entries.push(json!({
                    "name": name,
                    "ok": false,
                    "error": { "code": "not_available", "message": msg_cli(&lang, "not_available") },
                }));
                continue;
            }
            // One fixed key set, `null` where a field is absent (design/json.md §3): a caller never has to test whether a key is there.
            let mut alias = serde_json::Value::Null;
            if let Some(a) = settings.alias.get(name) {
                if !a.is_empty() {
                    alias = json!(a);
                }
            }
            let mut url = serde_json::Value::Null;
            let mut description = serde_json::Value::Null;
            if let Some(meta) = index.meta.get(name) {
                if let Some(c) = meta.get(&lang).or_else(|| meta.get("en-US")) {
                    if let Some(u) = c.get("url").and_then(|u| u.as_str()) {
                        url = json!(u);
                    }
                    // The value is reported as a string — the index's own form; a completion's `meta.description` is an array, joined the same way (with `\n`).
                    if let Some(desc) = c.get("description") {
                        let d = match desc {
                            serde_json::Value::String(s) => s.clone(),
                            serde_json::Value::Array(a) => a
                                .iter()
                                .filter_map(|x| x.as_str())
                                .collect::<Vec<_>>()
                                .join("\n"),
                            _ => String::new(),
                        };
                        if !d.is_empty() {
                            description = json!(d);
                        }
                    }
                }
            }
            let path = display_path(&format!("{completions_dir}/{name}"), cfg!(windows));
            let mut path_v = serde_json::Value::Null;
            let mut update = serde_json::Value::Null;
            let mut updated = serde_json::Value::Null;
            if std::path::Path::new(&path).exists() {
                path_v = json!(path);
                if let Ok(t) = std::fs::read_to_string(format!("{path}/.update")) {
                    let t = t.trim();
                    if !t.is_empty() {
                        update = json!(t);
                    }
                }
                if let Ok(m) = std::fs::metadata(format!("{path}/.update")) {
                    if let Ok(mt) = m.modified() {
                        if let Ok(d) = mt.duration_since(std::time::UNIX_EPOCH) {
                            updated = json!(d.as_secs());
                        }
                    }
                }
            }
            entries.push(json!({
                "name": name,
                "ok": true,
                "alias": alias,
                "url": url,
                "description": description,
                "path": path_v,
                "update": update,
                "updated": updated,
            }));
        }
        let had_error = entries.iter().any(|e| e["ok"] != true);
        let data = json!({ "completions": entries });
        ok(&data);
        // A failed entry fails this invocation (design/json.md §6): the exit code is the signal a script sees without parsing the payload.
        return if had_error {
            ExitCode::FAILURE
        } else {
            ExitCode::SUCCESS
        };
    }
    // A completion is a group, exactly like `config`'s groups: `[name]` then `key: value` rows.
    // The key names *are* the labels — semantic, identical to the JSON's, and the same in every language (design/json.md §2) — so there is no label table to keep in step.
    // Naming it on the command line drops the header, and the `name` row is gone either way: the caller or the header already said it.
    let mut had_error = false;
    let single = args.len() == 1;
    // One level is enough: a `[name]` heading already delimits, and the rows never indent (the same rule as an ini section, where a value sits at column 0).
    let field = |label: String, value: &str| out.line(&format!("{label}{value}"));
    for name in args {
        let status = name_status(settings, index, completions_dir, name);
        // A failure is an error line, not a block entry: it names itself, so it takes no `[name]` heading — the shape single-name mode already uses.
        if let Some((_code, e)) = name_error(&lang, name, status, false) {
            out.line(&e);
            had_error = true;
            continue;
        }
        if !single {
            out.line(&format!("[{name}]"));
        }
        if let Some(aliases) = settings.alias.get(name) {
            if !aliases.is_empty() {
                field("alias: ".to_string(), &aliases.join(", "));
            }
        }
        // The description is the one value authored as lines, so it is emitted last
        let mut description: Option<String> = None;
        if let Some(meta) = index.meta.get(name) {
            let c = meta.get(&lang).or_else(|| meta.get("en-US"));
            if let Some(c) = c {
                if let Some(url) = c.get("url").and_then(|u| u.as_str()) {
                    field("url: ".to_string(), url);
                }
                if let Some(desc) = c.get("description") {
                    let d = match desc {
                        serde_json::Value::String(s) => s.clone(),
                        serde_json::Value::Array(a) => a
                            .iter()
                            .filter_map(|x| x.as_str())
                            .collect::<Vec<_>>()
                            .join("\n"),
                        _ => String::new(),
                    };
                    if !d.is_empty() {
                        description = Some(d);
                    }
                }
            }
        }
        let path = display_path(&format!("{completions_dir}/{name}"), cfg!(windows));
        if std::path::Path::new(&path).exists() {
            field("path: ".to_string(), &path);
            if let Ok(t) = std::fs::read_to_string(format!("{path}/.update")) {
                let t = t.trim();
                if !t.is_empty() {
                    field("update: ".to_string(), t);
                }
            }
            if let Ok(meta) = std::fs::metadata(format!("{path}/.update")) {
                if let Ok(mt) = meta.modified() {
                    if let Ok(d) = mt.duration_since(std::time::UNIX_EPOCH) {
                        field("updated: ".to_string(), &utc_stamp(d.as_secs()));
                    }
                }
            }
        }
        if let Some(d) = description {
            // The label stands alone and the value starts on the next line — one rule for one line and for several.
            out.line("description:");
            out.line(&d);
        }
    }
    if had_error {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn utc_stamp_renders_known_instants() {
        assert_eq!(super::utc_stamp(0), "1970-01-01 00:00:00 UTC");
        assert_eq!(super::utc_stamp(1_000_000_000), "2001-09-09 01:46:40 UTC");
    }
}
