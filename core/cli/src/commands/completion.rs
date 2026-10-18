//! `psc completion` - per-completion special config (enable_tip etc.).

use std::process::ExitCode;

use serde_json::{json, Value};

use crate::commands::config::value_str;
use crate::data::{read_text, Index, Settings};
use crate::messages::msg_cli;
use crate::net::completion_defaults;
use crate::output::{fail, meta, ok, Out};
use crate::validate::{data_dir_of, ensure_completion_map, name_error, name_status};

const COMPLETION_KEYS: &[&str] = &[
    "language",
    "enable_tip",
    "enable_tip_usage",
    "enable_tip_example",
    "enable_hooks",
];

pub fn hooks_declared_disabled(data_dir: &str, name: &str) -> bool {
    let path = format!("{data_dir}/completions/{name}/config.json");
    read_text(&path)
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .map(|v| v.get("hooks").and_then(|h| h.as_bool()) == Some(false))
        .unwrap_or(false)
}

/// Every completion whose stored special config is not empty — the set the listing reports and a
/// reset answers with (an emptied entry is dropped, so "default" means absent).
fn completion_configs(settings: &Settings) -> Vec<(String, serde_json::Map<String, Value>)> {
    settings
        .config
        .get("completion")
        .and_then(|c| c.as_object())
        .map(|o| {
            o.iter()
                .filter(|(_, cfg)| cfg.as_object().map(|c| !c.is_empty()).unwrap_or(false))
                .filter_map(|(n, cfg)| cfg.as_object().map(|c| (n.clone(), c.clone())))
                .collect()
        })
        .unwrap_or_default()
}

#[allow(clippy::too_many_arguments)]
pub fn cmd_completion(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    index: &Index,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    let data_dir = data_dir_of(settings_path);
    let check_installed = |name: &String| -> Option<(&'static str, String)> {
        let data_dir = data_dir_of(settings_path);
        let status = name_status(settings, index, &format!("{data_dir}/completions"), name);
        // The code rides into the JSON envelope; the text mode only shows the message.
        name_error(lang, name, status, true)
    };
    if args.iter().any(|a| a == "--reset") {
        let data_dir = data_dir_of(settings_path);
        let params: Vec<&String> = args.iter().filter(|a| *a != "--reset").collect();
        let names: Vec<String> = if params.is_empty() {
            settings.list()
        } else {
            if let Some((code, e)) = check_installed(params[0]) {
                return fail(out, code, &e, json, &meta(None, &data_dir), false);
            }
            vec![params[0].clone()]
        };
        if params.len() <= 1 {
            let mut comp = std::mem::take(ensure_completion_map(settings));
            for n in &names {
                // Reset back to the manifest's config defaults; empty defaults are not persisted.
                let defaults = completion_defaults(&data_dir, n, &settings.language());
                if defaults.as_object().map(|o| o.is_empty()).unwrap_or(true) {
                    comp.remove(n.as_str());
                } else {
                    comp.insert(n.clone(), defaults);
                }
                // Re-apply the manifest's `hooks` declaration: a `hooks: false` completion
                // stays disabled after a reset (its author-declared default).
                if hooks_declared_disabled(&data_dir, n) {
                    let entry = comp
                        .entry(n.clone())
                        .or_insert_with(|| serde_json::json!({}));
                    if let Some(o) = entry.as_object_mut() {
                        o.insert("enable_hooks".to_string(), serde_json::json!(0));
                    }
                }
            }
            if let Some(obj) = settings
                .config
                .get_mut("completion")
                .and_then(|c| c.as_object_mut())
            {
                *obj = comp;
            }
        } else {
            // Exactly one key per reset; surplus args are rejected like an unknown key.
            if params.len() > 2 {
                return fail(
                    out,
                    "invalid_subcommand",
                    &msg_cli(lang, "sub_cmd"),
                    json,
                    &meta(None, &data_dir),
                    true,
                );
            }
            let name = params[0].clone();
            let key = params[1].clone();
            // Validate the key like the set path: a known key, or one already stored.
            let valid = COMPLETION_KEYS.contains(&key.as_str())
                || settings
                    .config
                    .get("completion")
                    .and_then(|c| c.get(name.as_str()))
                    .and_then(|c| c.get(&key))
                    .is_some();
            if !valid {
                return fail(
                    out,
                    "invalid_subcommand",
                    &msg_cli(lang, "sub_cmd"),
                    json,
                    &meta(None, &data_dir),
                    true,
                );
            }
            let defaults = completion_defaults(&data_dir, &name, &settings.language());
            if let Some(n) = settings
                .config
                .get_mut("completion")
                .and_then(|c| c.get_mut(&name))
                .and_then(|n| n.as_object_mut())
            {
                match defaults.get(&key) {
                    Some(v) => {
                        n.insert(key.clone(), v.clone());
                    }
                    None => {
                        // `enable_hooks` has no manifest default; resetting it re-applies
                        // the config.json declaration (a `hooks: false` completion stays off).
                        if key == "enable_hooks" && hooks_declared_disabled(&data_dir, &name) {
                            n.insert("enable_hooks".to_string(), serde_json::json!(0));
                        } else {
                            n.remove(&key);
                        }
                    }
                }
            }
            // Drop the entry once emptied (back to "default" = no special config).
            if let Some(comp) = settings
                .config
                .get_mut("completion")
                .and_then(|c| c.as_object_mut())
            {
                if comp
                    .get(&name)
                    .map(|v| v.as_object().map(|o| o.is_empty()).unwrap_or(false))
                    .unwrap_or(false)
                {
                    comp.remove(name.as_str());
                }
            }
        }
        if let Err(e) = settings.save(settings_path) {
            return fail(
                out,
                "io",
                &format!("error: {e}"),
                json,
                &meta(None, &data_dir),
                false,
            );
        }
        if json {
            // A reset answers the same shape the read of that scope answers with (design/json.md §8).
            if params.is_empty() {
                let items: Vec<serde_json::Value> = completion_configs(settings)
                    .iter()
                    .map(|(n, cfg)| json!({ "name": n, "config": cfg }))
                    .collect();
                let count = items.len();
                let data = json!({ "completions": items });
                return ok(&data, &meta(Some(count), &data_dir));
            }
            if params.len() == 1 {
                let n = params[0].clone();
                let cfg = settings
                    .config
                    .get("completion")
                    .and_then(|c| c.get(n.as_str()))
                    .and_then(|c| c.as_object())
                    .cloned()
                    .unwrap_or_default();
                let data = json!({ "name": n, "config": cfg });
                return ok(&data, &meta(None, &data_dir));
            }
            let (n, k) = (params[0].clone(), params[1].clone());
            let value = settings
                .config
                .get("completion")
                .and_then(|c| c.get(n.as_str()))
                .and_then(|c| c.get(k.as_str()))
                .cloned()
                .unwrap_or(serde_json::Value::Null);
            let data = json!({ "name": n, "key": k, "value": value });
            return ok(&data, &meta(None, &data_dir));
        }
        out.line(&msg_cli(lang, "completion_done"));
        return ExitCode::SUCCESS;
    }
    // No args: list every completion with non-default special config (with its config)
    if args.is_empty() {
        let entries = completion_configs(settings);
        if json {
            let items: Vec<serde_json::Value> = entries
                .iter()
                .map(|(n, cfg)| serde_json::json!({ "name": n, "config": cfg }))
                .collect();
            let count = items.len();
            let data = json!({ "completions": items });
            return ok(&data, &meta(Some(count), &data_dir));
        } else {
            // Each completion is a group, exactly like `config`: `[name]` then `  key: value`.
            // The named forms below drop the header (`completion <name>`) or the key
            // (`completion <name> <key>`) — the caller already said which one it wants.
            for (n, cfg) in entries {
                out.line(&format!("[{n}]"));
                for (k, v) in cfg {
                    out.line(&format!("{k}: {}", value_str(&v)));
                }
            }
        }
        return ExitCode::SUCCESS;
    }
    // Single arg <name>: list all special config for that completion
    if args.len() == 1 {
        let name = &args[0];
        if let Some((code, e)) = check_installed(name) {
            return fail(out, code, &e, json, &meta(None, &data_dir), false);
        }
        let cfg: serde_json::Map<String, Value> = settings
            .config
            .get("completion")
            .and_then(|c| c.get(name.as_str()))
            .and_then(|c| c.as_object())
            .cloned()
            .unwrap_or_default();
        if json {
            let data = json!({ "name": name, "config": cfg });
            return ok(&data, &meta(None, &data_dir));
        } else {
            for (k, v) in cfg {
                out.line(&format!("{k}: {}", value_str(&v)));
            }
        }
        return ExitCode::SUCCESS;
    }
    let name = args[0].clone();
    if let Some((code, e)) = check_installed(&name) {
        return fail(out, code, &e, json, &meta(None, &data_dir), false);
    }
    let key = args[1].clone();
    // enable_hooks is only valid when the completion's config.json declares hooks.
    if key == "enable_hooks" {
        let config_path = format!(
            "{}/completions/{name}/config.json",
            data_dir_of(settings_path)
        );
        let has_hooks = read_text(&config_path)
            .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
            .map(|c| c.get("hooks").is_some())
            .unwrap_or(false);
        if !has_hooks {
            return fail(
                out,
                "no_hooks",
                &msg_cli(lang, "no_hooks"),
                json,
                &meta(None, &data_dir),
                true,
            );
        }
    }
    let valid = COMPLETION_KEYS.contains(&key.as_str())
        || settings
            .config
            .get("completion")
            .and_then(|c| c.get(name.as_str()))
            .and_then(|c| c.get(&key))
            .is_some();
    if !valid {
        return fail(
            out,
            "invalid_subcommand",
            &msg_cli(lang, "sub_cmd"),
            json,
            &meta(None, &data_dir),
            true,
        );
    }
    let get = |key: &str| -> String {
        settings
            .config
            .get("completion")
            .and_then(|c| c.get(name.as_str()))
            .and_then(|c| c.get(key))
            .map(|v| match v {
                serde_json::Value::String(s) => s.clone(),
                serde_json::Value::Number(n) => n.to_string(),
                serde_json::Value::Bool(b) => b.to_string(),
                other => other.to_string(),
            })
            .unwrap_or_default()
    };
    if args.len() == 2 {
        if json {
            let raw = settings
                .config
                .get("completion")
                .and_then(|c| c.get(name.as_str()))
                .and_then(|c| c.get(&key))
                .cloned()
                .unwrap_or(serde_json::Value::Null);
            let data = json!({ "name": name.clone(), "key": key, "value": raw });
            return ok(&data, &meta(None, &data_dir));
        } else {
            // Same rule as `config <group> <key>`: the key was just typed, answer with the value.
            out.line(&get(&key));
        }
        return ExitCode::SUCCESS;
    }
    let value: serde_json::Value = match args[2].parse::<i64>() {
        Ok(n) => serde_json::Value::Number(n.into()),
        Err(_) => serde_json::Value::String(args[2].clone()),
    };
    if key.starts_with("enable_") || key.starts_with("disable_") {
        let v = match &value {
            serde_json::Value::Number(n) => n.as_i64() == Some(0) || n.as_i64() == Some(1),
            _ => false,
        };
        if !v {
            return fail(
                out,
                "one_or_zero",
                &msg_cli(lang, "one_or_zero"),
                json,
                &meta(None, &data_dir),
                true,
            );
        }
    }
    // The module's management completions run on psc's own hooks.
    if name == "psc" && key == "enable_hooks" && value.as_i64() == Some(0) {
        return fail(
            out,
            "psc_hooks_locked",
            &msg_cli(lang, "psc_hooks_locked"),
            json,
            &meta(None, &data_dir),
            true,
        );
    }
    // What this write answers with: the item a read of that key returns, plus what the value was
    // before — `null` when the key had none (design/json.md §8).
    let old = settings
        .config
        .get("completion")
        .and_then(|c| c.get(name.as_str()))
        .and_then(|c| c.get(key.as_str()))
        .cloned()
        .unwrap_or(serde_json::Value::Null);
    {
        // Recover a corrupt settings.json (reset config/completion/name entries that aren't objects)
        // to avoid an unwrap panic
        let comp = ensure_completion_map(settings);
        let n = comp
            .entry(name.clone())
            .or_insert_with(|| serde_json::json!({}));
        if !n.is_object() {
            *n = serde_json::json!({});
        }
        n.as_object_mut()
            .unwrap()
            .insert(key.clone(), value.clone());
    }
    if let Err(e) = settings.save(settings_path) {
        return fail(
            out,
            "io",
            &format!("error: {e}"),
            json,
            &meta(None, &data_dir),
            false,
        );
    }
    if json {
        // The item a read of that key answers with, plus what it was before.
        let data = json!({ "name": name, "key": key, "value": value, "old": old });
        return ok(&data, &meta(None, &data_dir));
    }
    out.line(&msg_cli(lang, "completion_done"));
    ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    // Each test gets a unique dir: Rust runs tests in parallel, so sharing one path
    // would let one test's cleanup clobber another's fixtures.
    fn test_base() -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        std::env::temp_dir().join(format!(
            "psc-completion-test-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ))
    }

    #[test]
    fn hooks_declared_disabled_reads_config_json() {
        let base = test_base();
        let dir = base.join("completions/x");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("config.json"),
            r#"{"language":["en-US"],"hooks":false}"#,
        )
        .unwrap();
        assert!(hooks_declared_disabled(base.to_str().unwrap(), "x"));
        std::fs::write(
            dir.join("config.json"),
            r#"{"language":["en-US"],"hooks":true}"#,
        )
        .unwrap();
        assert!(!hooks_declared_disabled(base.to_str().unwrap(), "x"));
        std::fs::write(dir.join("config.json"), r#"{"language":["en-US"]}"#).unwrap();
        assert!(!hooks_declared_disabled(base.to_str().unwrap(), "x"));
        std::fs::remove_dir_all(&base).ok();
    }
}
