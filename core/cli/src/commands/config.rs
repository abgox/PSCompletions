//! `psc config` - grouped module config get/set/reset.

use std::process::ExitCode;

use serde_json::json;

use crate::data::config::{validate_value, CONFIG_GROUPS, CONFIG_KEYS};
use crate::data::{default_config, Settings};
use crate::messages::msg_cli;
use crate::net::is_official_source;
use crate::output::{fail, fail_details, key_line, ok, value_quoted, value_text, Out};

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
    if args.iter().any(|a| a == "--reset") {
        let defaults = default_config(&settings.language());
        let params: Vec<&String> = args.iter().filter(|a| *a != "--reset").collect();
        // A reset takes at most `<group> <key>`: more is a parameter-count error, not a silent
        // no-op (the chain below has no fallback branch).
        if params.len() > 2 {
            return crate::validate::too_many_params(out, lang, json);
        }
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
                    &msg_cli(lang, "invalid_subcommand"),
                    json,
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
                    &msg_cli(lang, "invalid_subcommand"),
                    json,
                    true,
                );
            };
            if def.key == "language" {
                return fail(
                    out,
                    "language_no_reset",
                    &msg_cli(lang, "language_no_reset"),
                    json,
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
                &msg_cli(lang, "invalid_subcommand"),
                json,
                true,
            );
        }
        if let Err(e) = settings.save(settings_path) {
            return fail(out, "io", &format!("error: {e}"), json, false);
        }
        if json {
            // A reset answers the same shape the read of that scope answers with — the resulting
            // state (design/json.md §8).
            if params.len() <= 1 {
                let entries = config_items(settings, params.first().map(|p| p.as_str()), None);
                let data = json!({ "config": entries });
                return ok(&data);
            }
            let key = params[1].as_str();
            let data = json!({ "key": key, "value": raw_value(settings, key) });
            return ok(&data);
        }
        out.line(&msg_cli(lang, "config_done"));
        return ExitCode::SUCCESS;
    }
    // No args: list everything (grouped by group)
    if args.is_empty() {
        if json {
            let entries = config_items(settings, None, None);
            let data = json!({ "config": entries });
            return ok(&data);
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
        let msg = msg_cli(lang, "invalid_subcommand_named")
            .replace("{{Token}}", group)
            .replace("{{Valid}}", &CONFIG_GROUPS.join(", "));
        // The same two parts also travel structured, so a machine caller reads them instead of
        // parsing a localized message (design/json.md §4).
        let details = json!({ "token": group, "valid": CONFIG_GROUPS });
        return fail_details(out, "invalid_subcommand", &msg, Some(details), json, true);
    }
    // `config <group>`: list that group
    if args.len() == 1 {
        if json {
            let entries = config_items(settings, Some(group), None);
            let data = json!({ "config": entries });
            return ok(&data);
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
            &msg_cli(lang, "invalid_subcommand"),
            json,
            true,
        );
    };
    // get
    if args.len() == 2 {
        if json {
            let data = json!({ "key": key, "value": raw_value(settings, key) });
            return ok(&data);
        } else {
            // The key was just typed, so the value alone (and unquoted) is the answer.
            let v = settings.config.get(key).map(value_text).unwrap_or_default();
            out.line(&v);
        }
        return ExitCode::SUCCESS;
    }
    // `config <group> <key> <value>` takes exactly three arguments: anything after the value is a
    // usage error, exactly as the reset form rejects it.
    if args.len() > 3 {
        return crate::validate::too_many_params(out, lang, json);
    }
    let Some(value) = validate_value(def, &args[2]) else {
        return fail(
            out,
            "config_value",
            &msg_cli(lang, "config_value"),
            json,
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
        return fail(out, "io", &format!("error: {e}"), json, false);
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
        return ok(&data);
    }
    out.line(&msg_cli(lang, "config_done"));
    if untrusted {
        out.line(&msg_cli(lang, "url_untrusted"));
    }
    ExitCode::SUCCESS
}
