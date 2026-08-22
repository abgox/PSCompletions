//! `psc info` - completion metadata (no-arg lists all installed).

use std::process::ExitCode;

use serde_json::json;

use crate::data::{Index, Settings};
use crate::messages::msg_cli;
use crate::output::Out;
use crate::validate::{name_error, name_status};
pub fn cmd_info(
    args: &[String],
    settings: &Settings,
    index: &Index,
    completions_dir: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    let lang = settings.language();
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
        let mut arr = Vec::new();
        for name in args {
            let status = name_status(settings, index, completions_dir, name);
            if name_error(&lang, name, status, false).is_some() {
                // Error text stays name-free: the module (and any consumer) renders
                // `name: error` itself, mirroring the add/rm/update entry shape.
                arr.push(
                    json!({"name": name, "ok": false, "error": msg_cli(&lang, "not_available")}),
                );
                continue;
            }
            let mut o = serde_json::Map::new();
            o.insert("name".into(), serde_json::json!(name));
            if let Some(aliases) = settings.alias.get(name) {
                if !aliases.is_empty() {
                    o.insert("alias".into(), serde_json::json!(aliases.join(" ")));
                }
            }
            if let Some(meta) = index.meta.get(name) {
                let c = meta.get(&lang).or_else(|| meta.get("en-US"));
                if let Some(c) = c {
                    if let Some(url) = c.get("url").and_then(|u| u.as_str()) {
                        o.insert("url".into(), serde_json::json!(url));
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
                            o.insert("description".into(), serde_json::json!(d));
                        }
                    }
                }
            }
            let path = format!("{completions_dir}/{name}");
            if std::path::Path::new(&path).exists() {
                o.insert("path".into(), serde_json::json!(path));
                if let Ok(t) = std::fs::read_to_string(format!("{path}/.update")) {
                    let t = t.trim();
                    if !t.is_empty() {
                        o.insert("update".into(), serde_json::json!(t));
                    }
                }
                if let Ok(meta) = std::fs::metadata(format!("{path}/.update")) {
                    if let Ok(mt) = meta.modified() {
                        if let Ok(d) = mt.duration_since(std::time::UNIX_EPOCH) {
                            o.insert("updated".into(), serde_json::json!(d.as_secs()));
                        }
                    }
                }
            }
            arr.push(serde_json::Value::Object(o));
        }
        // Still output valid entries on error (partial success); skip an all-failed empty array
        if !arr.is_empty() {
            println!("{}", serde_json::to_string(&arr).unwrap_or_default());
        }
        return ExitCode::SUCCESS;
    }
    let mut had_error = false;
    for name in args {
        let status = name_status(settings, index, completions_dir, name);
        if let Some(e) = name_error(&lang, name, status, false) {
            out.line(&e);
            had_error = true;
            continue;
        }
        out.line(&format!("Name: {name}"));
        if let Some(aliases) = settings.alias.get(name) {
            if !aliases.is_empty() {
                out.line(&format!("Alias: {}", aliases.join(" ")));
            }
        }
        if let Some(meta) = index.meta.get(name) {
            let c = meta.get(&lang).or_else(|| meta.get("en-US"));
            if let Some(c) = c {
                if let Some(url) = c.get("url").and_then(|u| u.as_str()) {
                    out.line(&format!("Url: {url}"));
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
                        out.line(&format!("Description: {d}"));
                    }
                }
            }
        }
        let path = format!("{completions_dir}/{name}");
        if std::path::Path::new(&path).exists() {
            out.line(&format!("Path: {path}"));
            if let Ok(t) = std::fs::read_to_string(format!("{path}/.update")) {
                let t = t.trim();
                if !t.is_empty() {
                    out.line(&format!("Update: {t}"));
                }
            }
            if let Ok(meta) = std::fs::metadata(format!("{path}/.update")) {
                if let Ok(mt) = meta.modified() {
                    if let Ok(d) = mt.duration_since(std::time::UNIX_EPOCH) {
                        out.line(&format!("Updated: {}", d.as_secs()));
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
