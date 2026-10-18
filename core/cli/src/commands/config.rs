//! `psc config` - grouped module config get/set/reset.

use std::process::ExitCode;

use serde_json::json;

use crate::data::config::{validate_value, CONFIG_GROUPS, CONFIG_KEYS};
use crate::data::{default_config, Settings};
use crate::messages::msg_cli;
use crate::net::is_official_source;
use crate::output::{fail, key_line, meta, ok, value_quoted, value_text, Out};

fn config_get(settings: &Settings, key: &str) -> String {
    settings
        .config
        .get(key)
        .map(value_quoted)
        .unwrap_or_default()
}

/// The items a `config` listing answers with, optionally narrowed to one group or one key. A
/// reset reports the same items, so this is the one place the shape is built.
fn config_items(
    settings: &Settings,
    group: Option<&str>,
    key: Option<&str>,
) -> Vec<serde_json::Value> {
    CONFIG_KEYS
        .iter()
        .filter(|d| group.is_none_or(|g| d.group == g) && key.is_none_or(|k| d.key == k))
        .map(|d| {
            json!({
                "group": d.group,
                "key": d.key,
                "value": raw_value(settings, d.key),
            })
        })
        .collect()
}

/// The raw stored value: numbers stay numbers and an absent key is `null` — the display form
/// (`value_str`'s quoting) belongs to the text mode only.
fn raw_value(settings: &Settings, key: &str) -> serde_json::Value {
    settings
        .config
        .get(key)
        .cloned()
        .unwrap_or(serde_json::Value::Null)
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
    let data_dir = crate::validate::data_dir_of(settings_path);
    let m = || meta(None, &data_dir);
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
                return fail(
                    out,
                    "invalid_subcommand",
                    &msg_cli(lang, "sub_cmd"),
                    json,
                    &m(),
                    true,
                );
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
                return fail(
                    out,
                    "invalid_subcommand",
                    &msg_cli(lang, "sub_cmd"),
                    json,
                    &m(),
                    true,
                );
            };
            if def.key == "language" {
                return fail(
                    out,
                    "language_no_reset",
                    &msg_cli(lang, "language_no_reset"),
                    json,
                    &m(),
                    true,
                );
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
            return fail(
                out,
                "invalid_subcommand",
                &msg_cli(lang, "sub_cmd"),
                json,
                &m(),
                true,
            );
        }
        if let Err(e) = settings.save(settings_path) {
            return fail(out, "io", &format!("error: {e}"), json, &m(), false);
        }
        if json {
            // A reset answers the same shape the read of that scope answers with — the resulting
            // state (design/json.md §8).
            if params.len() <= 1 {
                let entries = config_items(settings, params.first().map(|p| p.as_str()), None);
                let count = entries.len();
                let data = json!({ "config": entries });
                return ok(&data, &meta(Some(count), &data_dir));
            }
            let key = params[1].as_str();
            let data = json!({ "key": key, "value": raw_value(settings, key) });
            return ok(&data, &meta(None, &data_dir));
        }
        out.line(&msg_cli(lang, "config_done"));
        return ExitCode::SUCCESS;
    }
    // No args: list everything (grouped by group)
    if args.is_empty() {
        if json {
            let entries = config_items(settings, None, None);
            let count = entries.len();
            let data = json!({ "config": entries });
            return ok(&data, &meta(Some(count), &data_dir));
        } else {
            for group in CONFIG_GROUPS {
                out.line(&format!("[{group}]"));
                for d in CONFIG_KEYS.iter().filter(|d| d.group == group) {
                    out.line(&key_line(d.key, &config_get(settings, d.key)));
                }
            }
        }
        return ExitCode::SUCCESS;
    }
    let group = args[0].as_str();
    if !CONFIG_GROUPS.contains(&group) {
        // Name the offending token and the valid set: a bare "invalid subcommand" leaves the
        // reader guessing, and this text is the interface in the shells.
        let msg = msg_cli(lang, "sub_cmd_named")
            .replace("{{Token}}", group)
            .replace("{{Valid}}", &CONFIG_GROUPS.join(", "));
        return fail(out, "invalid_subcommand", &msg, json, &m(), true);
    }
    // `config <group>`: list that group
    if args.len() == 1 {
        if json {
            let entries = config_items(settings, Some(group), None);
            let count = entries.len();
            let data = json!({ "config": entries });
            return ok(&data, &meta(Some(count), &data_dir));
        } else {
            // The caller named the group, so repeating `[group]` is noise; keys sit at column 0.
            for d in CONFIG_KEYS.iter().filter(|d| d.group == group) {
                out.line(&key_line(d.key, &config_get(settings, d.key)));
            }
        }
        return ExitCode::SUCCESS;
    }
    let key = args[1].as_str();
    let Some(def) = CONFIG_KEYS
        .iter()
        .find(|d| d.group == group && d.key == key)
    else {
        return fail(
            out,
            "invalid_subcommand",
            &msg_cli(lang, "sub_cmd"),
            json,
            &m(),
            true,
        );
    };
    // get
    if args.len() == 2 {
        if json {
            let data = json!({ "key": key, "value": raw_value(settings, key) });
            return ok(&data, &meta(None, &data_dir));
        } else {
            // The key was just typed, so the value alone (and unquoted) is the answer.
            let v = settings.config.get(key).map(value_text).unwrap_or_default();
            out.line(&v);
        }
        return ExitCode::SUCCESS;
    }
    let Some(value) = validate_value(def, &args[2]) else {
        return fail(
            out,
            "config_value",
            &msg_cli(lang, "config_val"),
            json,
            &m(),
            true,
        );
    };
    // What this write answers with: the item a read of that key returns, plus what the value was
    // before — `null` when the key had none (design/json.md §8).
    let old = raw_value(settings, key);
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
        return fail(out, "io", &format!("error: {e}"), json, &m(), false);
    }
    // A custom source is unreviewed: warn once it takes effect.
    let untrusted = group == "core"
        && key == "url"
        && value.as_str().is_some_and(|u| {
            !is_official_source(
                &crate::validate::data_dir_of(settings_path),
                &settings.language(),
                u,
            )
        });
    if json {
        // The item a read of that key answers with, plus what it was before. An unreviewed
        // source's notice rides alongside it, so a caller can surface it without parsing prose.
        let mut data = json!({ "key": key, "value": value, "old": old });
        if untrusted {
            data["warning"] = json!(msg_cli(lang, "url_untrusted"));
        }
        return ok(&data, &meta(None, &data_dir));
    }
    out.line(&msg_cli(lang, "config_done"));
    if untrusted {
        out.line(&msg_cli(lang, "url_untrusted"));
    }
    ExitCode::SUCCESS
}
