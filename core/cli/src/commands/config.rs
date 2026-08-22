//! `psc config` - grouped module config get/set/reset.

use std::process::ExitCode;

use serde_json::{json, Value};

use crate::data::config::{validate_value, CONFIG_GROUPS, CONFIG_KEYS};
use crate::data::{default_config, Settings};
use crate::messages::msg_cli;
use crate::output::Out;

pub(crate) fn value_str(v: &Value) -> String {
    match v {
        serde_json::Value::String(s) => {
            if s.trim().is_empty() || s.starts_with(' ') || s.ends_with(' ') {
                if s.contains('"') {
                    if s.contains('\'') {
                        s.clone()
                    } else {
                        format!("'{s}'")
                    }
                } else {
                    format!("\"{s}\"")
                }
            } else {
                s.clone()
            }
        }
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::Bool(b) => b.to_string(),
        other => other.to_string(),
    }
}

fn config_get(settings: &Settings, key: &str) -> String {
    settings.config.get(key).map(value_str).unwrap_or_default()
}

#[allow(clippy::too_many_arguments)]
pub fn cmd_config(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    if args.iter().any(|a| a == "--reset") {
        let defaults = default_config(&settings.language());
        let params: Vec<&String> = args.iter().filter(|a| *a != "--reset").collect();
        if params.is_empty() {
            if !settings.config.is_object() {
                settings.config = serde_json::json!({});
            }
            let obj = settings.config.as_object_mut().unwrap();
            let comp = obj.get("completion").cloned();
            let lang = obj.get("language").cloned();
            *obj = defaults.as_object().unwrap().clone();
            if let Some(c) = comp {
                obj.insert("completion".into(), c);
            }
            if let Some(l) = lang {
                obj.insert("language".into(), l);
            }
        } else if params.len() == 1 {
            // `config <group> --reset`: reset every config item in that group
            let group = params[0].as_str();
            if !CONFIG_GROUPS.contains(&group) {
                if json {
                    println!(
                        "{}",
                        serde_json::to_string(
                            &json!({"ok": false, "error": msg_cli(lang, "sub_cmd")})
                        )
                        .unwrap_or_default()
                    );
                    return ExitCode::SUCCESS;
                }
                out.line(&msg_cli(lang, "sub_cmd"));
                return ExitCode::FAILURE;
            }
            if !settings.config.is_object() {
                settings.config = serde_json::json!({});
            }
            let obj = settings.config.as_object_mut().unwrap();
            for d in CONFIG_KEYS.iter().filter(|d| d.group == group) {
                if d.key == "language" {
                    continue;
                }
                let value = defaults
                    .get(d.key)
                    .cloned()
                    .unwrap_or_else(|| serde_json::json!(""));
                obj.insert(d.key.to_string(), value);
            }
        } else if params.len() == 2 {
            let (group, key) = (params[0].as_str(), params[1].as_str());
            let Some(def) = CONFIG_KEYS
                .iter()
                .find(|d| d.group == group && d.key == key)
            else {
                if json {
                    println!(
                        "{}",
                        serde_json::to_string(
                            &json!({"ok": false, "error": msg_cli(lang, "sub_cmd")})
                        )
                        .unwrap_or_default()
                    );
                    return ExitCode::SUCCESS;
                }
                out.line(&msg_cli(lang, "sub_cmd"));
                return ExitCode::FAILURE;
            };
            if def.key == "language" {
                if json {
                    println!(
                        "{}",
                        serde_json::to_string(
                            &json!({"ok": false, "error": msg_cli(lang, "language_no_reset")})
                        )
                        .unwrap_or_default()
                    );
                    return ExitCode::SUCCESS;
                }
                out.line(&msg_cli(lang, "language_no_reset"));
                return ExitCode::FAILURE;
            }
            if !settings.config.is_object() {
                settings.config = serde_json::json!({});
            }
            let value = defaults
                .get(def.key)
                .cloned()
                .unwrap_or_else(|| serde_json::json!(""));
            settings
                .config
                .as_object_mut()
                .unwrap()
                .insert(def.key.to_string(), value);
        } else {
            if json {
                println!(
                    "{}",
                    serde_json::to_string(&json!({"ok": false, "error": msg_cli(lang, "sub_cmd")}))
                        .unwrap_or_default()
                );
                return ExitCode::SUCCESS;
            }
            out.line(&msg_cli(lang, "sub_cmd"));
            return ExitCode::FAILURE;
        }
        if let Err(e) = settings.save(settings_path) {
            if json {
                println!(
                    "{}",
                    serde_json::to_string(&json!({"ok": false, "error": e.to_string()}))
                        .unwrap_or_default()
                );
                return ExitCode::SUCCESS;
            }
            out.line(&format!("error: {e}"));
            return ExitCode::FAILURE;
        }
        if json {
            println!(
                "{}",
                serde_json::to_string(&json!({"ok": true})).unwrap_or_default()
            );
            return ExitCode::SUCCESS;
        }
        out.line(&msg_cli(lang, "config_done"));
        return ExitCode::SUCCESS;
    }
    // No args: list everything (grouped by group)
    if args.is_empty() {
        if json {
            let arr: Vec<serde_json::Value> = CONFIG_KEYS
                .iter()
                .map(|d| {
                    serde_json::json!({ "group": d.group, "key": d.key, "value": config_get(settings, d.key) })
                })
                .collect();
            println!("{}", serde_json::to_string(&arr).unwrap_or_default());
        } else {
            for group in CONFIG_GROUPS {
                out.line(&format!("[{group}]"));
                for d in CONFIG_KEYS.iter().filter(|d| d.group == group) {
                    out.line(&format!("  {}: {}", d.key, config_get(settings, d.key)));
                }
            }
        }
        return ExitCode::SUCCESS;
    }
    let group = args[0].as_str();
    if !CONFIG_GROUPS.contains(&group) {
        if json {
            println!(
                "{}",
                serde_json::to_string(&json!({"ok": false, "error": msg_cli(lang, "sub_cmd")}))
                    .unwrap_or_default()
            );
            return ExitCode::SUCCESS;
        }
        out.line(&msg_cli(lang, "sub_cmd"));
        return ExitCode::FAILURE;
    }
    // `config <group>`: list that group
    if args.len() == 1 {
        if json {
            let arr: Vec<serde_json::Value> = CONFIG_KEYS
                .iter()
                .filter(|d| d.group == group)
                .map(|d| {
                    serde_json::json!({ "group": d.group, "key": d.key, "value": config_get(settings, d.key) })
                })
                .collect();
            println!("{}", serde_json::to_string(&arr).unwrap_or_default());
        } else {
            out.line(&format!("[{group}]"));
            for d in CONFIG_KEYS.iter().filter(|d| d.group == group) {
                out.line(&format!("  {}: {}", d.key, config_get(settings, d.key)));
            }
        }
        return ExitCode::SUCCESS;
    }
    let key = args[1].as_str();
    let Some(def) = CONFIG_KEYS
        .iter()
        .find(|d| d.group == group && d.key == key)
    else {
        if json {
            println!(
                "{}",
                serde_json::to_string(&json!({"ok": false, "error": msg_cli(lang, "sub_cmd")}))
                    .unwrap_or_default()
            );
            return ExitCode::SUCCESS;
        }
        out.line(&msg_cli(lang, "sub_cmd"));
        return ExitCode::FAILURE;
    };
    // get
    if args.len() == 2 {
        if json {
            println!(
                "{}",
                serde_json::json!({ "key": key, "value": config_get(settings, key) })
            );
        } else {
            out.line(&format!("{key}: {}", config_get(settings, key)));
        }
        return ExitCode::SUCCESS;
    }
    let Some(value) = validate_value(def, &args[2]) else {
        if json {
            println!(
                "{}",
                serde_json::to_string(&json!({"ok": false, "error": msg_cli(lang, "config_val")}))
                    .unwrap_or_default()
            );
            return ExitCode::SUCCESS;
        }
        out.line(&msg_cli(lang, "config_val"));
        return ExitCode::FAILURE;
    };
    // A corrupt `config` (e.g. `{"config": 123}`) must not turn a set into a silent no-op.
    if !settings.config.is_object() {
        settings.config = serde_json::json!({});
    }
    settings
        .config
        .as_object_mut()
        .and_then(|o| o.get_mut(key))
        .map(|v| *v = value.clone())
        .or_else(|| {
            settings
                .config
                .as_object_mut()
                .map(|o| o.insert(key.to_string(), value.clone()));
            Some(())
        });
    if let Err(e) = settings.save(settings_path) {
        if json {
            println!(
                "{}",
                serde_json::to_string(&json!({"ok": false, "error": e.to_string()}))
                    .unwrap_or_default()
            );
            return ExitCode::SUCCESS;
        }
        out.line(&format!("error: {e}"));
        return ExitCode::FAILURE;
    }
    if json {
        println!(
            "{}",
            serde_json::to_string(&json!({"ok": true})).unwrap_or_default()
        );
        return ExitCode::SUCCESS;
    }
    out.line(&msg_cli(lang, "config_done"));
    ExitCode::SUCCESS
}
