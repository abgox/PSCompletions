//! `psc info` - completion metadata (no-arg lists all installed).

use std::process::ExitCode;

use serde_json::json;

use crate::data::{Index, Settings};
use crate::messages::msg_cli;
use crate::output::{meta, ok, Out};
use crate::validate::{name_error, name_status};
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
        let mut v: Vec<String> = settings.alias.keys().cloned().collect();
        v.sort();
        owned = v;
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
            // One fixed key set, `null` where a field is absent (design/json.md §3): a caller never
            // has to test whether a key is there.
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
            let path = format!("{completions_dir}/{name}");
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
        let count = entries.len();
        let data = json!({ "completions": entries });
        ok(
            &data,
            &meta(
                Some(count),
                completions_dir.trim_end_matches("/completions"),
            ),
        );
        // A failed entry fails this invocation (design/json.md §6): the exit code is the signal a
        // script sees without parsing the payload.
        return if had_error {
            ExitCode::FAILURE
        } else {
            ExitCode::SUCCESS
        };
    }
    // A completion is a group, exactly like `config`'s groups: `[name]` then `key: value` rows.
    // The key names *are* the labels — semantic, identical to the JSON's, and the same in every
    // language (design/json.md §2) — so there is no label table to keep in step. Naming it on the
    // command line drops the header, and the `name` row is gone either way: the caller or the
    // header already said it.
    let mut had_error = false;
    let single = args.len() == 1;
    // One level is enough: a `[name]` heading already delimits, and the rows never indent (the
    // same rule as an ini section, where a value sits at column 0).
    let field = |label: String, value: &str| out.line(&format!("{label}{value}"));
    for name in args {
        if !single {
            out.line(&format!("[{name}]"));
        }
        let status = name_status(settings, index, completions_dir, name);
        if let Some((_code, e)) = name_error(&lang, name, status, false) {
            out.line(&e);
            had_error = true;
            continue;
        }
        if let Some(aliases) = settings.alias.get(name) {
            if !aliases.is_empty() {
                field("alias: ".to_string(), &aliases.join(", "));
            }
        }
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
                        field("description: ".to_string(), &d);
                    }
                }
            }
        }
        let path = format!("{completions_dir}/{name}");
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
                        field("updated: ".to_string(), &d.as_secs().to_string());
                    }
                }
            }
        }
    }
    if had_error {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
