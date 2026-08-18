//! Config registry, migration and sanitization. Every config key is defined here (one row
//! per key, so new keys/groups are added by appending a row); migration and sanitization
//! live alongside.

use serde_json::{Map, Value};

pub const CONFIG_GROUPS: [&str; 3] = ["core", "menu", "context"];

#[derive(Debug, Clone, Copy)]
pub enum CfgType {
    Bool,
    Str,
    Url,
    NonEmptyStr,
    IntRange(i64, i64),
    /// Positive integer kept as-is (no upper bound; the consumer caps it when using it).
    PositiveInt,
    Enum(&'static [&'static str]),
}

pub struct CfgDef {
    pub group: &'static str,
    pub key: &'static str,
    pub ty: CfgType,
}

pub const CONFIG_KEYS: &[CfgDef] = &[
    CfgDef {
        group: "core",
        key: "url",
        ty: CfgType::Url,
    },
    CfgDef {
        group: "core",
        key: "language",
        ty: CfgType::NonEmptyStr,
    },
    CfgDef {
        group: "core",
        key: "enable_auto_alias_setup",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "show_mode",
        ty: CfgType::Enum(&[
            "auto",
            "inline-follow",
            "altscreen-follow",
            "altscreen-top",
            "altscreen-bottom",
        ]),
    },
    CfgDef {
        group: "menu",
        key: "enable_tip",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "enable_tip_usage",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "enable_tip_example",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "trigger_key",
        ty: CfgType::Str,
    },
    CfgDef {
        group: "menu",
        key: "filter_mode",
        ty: CfgType::Enum(&["subsequence", "wildcard"]),
    },
    CfgDef {
        group: "menu",
        key: "enable_apply_when_single",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "enable_apply_when_no_match",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "enable_list_loop",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "enable_native_completion",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "enable_sort_by_history",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "enable_cache",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "enable_append_space",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "enable_path_trailing_separator",
        ty: CfgType::Bool,
    },
    CfgDef {
        group: "menu",
        key: "color_focus",
        ty: CfgType::Str,
    },
    CfgDef {
        group: "menu",
        key: "color_match",
        ty: CfgType::Str,
    },
    CfgDef {
        group: "context",
        key: "switch",
        ty: CfgType::Str,
    },
    CfgDef {
        group: "context",
        key: "stay",
        ty: CfgType::Str,
    },
];

/// Validate and parse a config value for a key; returns the JSON value to store.
pub fn validate_value(def: &CfgDef, value: &str) -> Option<Value> {
    match def.ty {
        CfgType::Bool => match value {
            // Only `0`/`1` are accepted; stored as JSON numbers.
            "0" => Some(Value::Number(0.into())),
            "1" => Some(Value::Number(1.into())),
            _ => None,
        },
        CfgType::Str => Some(Value::String(value.to_string())),
        CfgType::NonEmptyStr => {
            if value.is_empty() {
                None
            } else {
                Some(Value::String(value.to_string()))
            }
        }
        CfgType::Url => {
            if value.is_empty() || value.starts_with("http://") || value.starts_with("https://") {
                Some(Value::String(value.to_string()))
            } else {
                None
            }
        }
        CfgType::IntRange(min, max) => match value.parse::<i64>() {
            Ok(n) if n >= min && n <= max => Some(Value::Number(n.into())),
            _ => None,
        },
        CfgType::PositiveInt => match value.parse::<i64>() {
            // Positive integer, stored verbatim (bounded by i32 since the engine consumes it).
            Ok(n) if n >= 1 && n <= i32::MAX as i64 => Some(Value::Number(n.into())),
            _ => None,
        },
        CfgType::Enum(vals) => {
            if vals.contains(&value) {
                Some(Value::String(value.to_string()))
            } else {
                None
            }
        }
    }
}

/// Parse a value as an integer (accepts number or numeric string).
pub fn as_int(v: &Value) -> Option<i64> {
    v.as_i64()
        .or_else(|| v.as_str().and_then(|s| s.trim().parse::<i64>().ok()))
}

/// Convert a legacy `true`/`false` boolean (or numeric string) in place to a `1`/`0` number.
/// Returns whether the value changed.
fn normalize_bool_value(v: &mut Value) -> bool {
    let converted = match v {
        Value::Bool(b) => Some(if *b { 1 } else { 0 }),
        Value::Number(n) => match n.as_i64() {
            Some(0) | Some(1) => None, // already a 0/1 number
            _ => None,
        },
        Value::String(s) => match s.as_str() {
            "0" | "false" => Some(0),
            "1" | "true" => Some(1),
            _ => None,
        },
        _ => None,
    };
    if let Some(n) = converted {
        *v = Value::Number(n.into());
        true
    } else {
        false
    }
}

/// Migrate config keys (centralized here): old settings names → current; returns whether anything changed.
pub fn migrate_config(config: &mut Map<String, Value>) -> bool {
    let mut changed = false;
    if config.get("comp_config").is_some() && config.get("completion").is_none() {
        if let Some(v) = config.remove("comp_config") {
            config.insert("completion".into(), v);
            changed = true;
        }
    }
    // Symbol migration: old symbol keys -> current symbol keys.
    // - First-generation keys like SpaceTab map directly to the current names (switch/stay)
    // - continue (the symbol was once called continue, now switch) -> switch
    // - WriteSpaceTab / input have been removed (input is expressed via the usage placeholder) -> drop
    if config.remove("WriteSpaceTab").is_some() {
        changed = true;
    }
    if config.remove("input").is_some() {
        changed = true;
    }
    let mut map = |old: &str, new: &str| {
        if let Some(v) = config.remove(old) {
            config.insert(new.to_string(), v);
            changed = true;
        }
    };
    map("SpaceTab", "switch");
    map("OptionTab", "stay");
    map("continue", "switch");
    map("menu_mode", "show_mode");
    map("enable_enter_when_single", "enable_apply_when_single");
    map("enable_enter_when_no_match", "enable_apply_when_no_match");
    map("enable_completions_sort", "enable_sort_by_history");
    map(
        "enable_path_with_trailing_separator",
        "enable_path_trailing_separator",
    );
    // gap_above/gap_below
    if config
        .remove("height_from_menu_bottom_to_cursor_when_above")
        .is_some()
    {
        changed = true;
    }
    if config
        .remove("height_from_menu_top_to_cursor_when_below")
        .is_some()
    {
        changed = true;
    }
    if config.remove("enable_menu_show_below").is_some() {
        config.insert("show_mode".into(), Value::String("auto".into()));
        changed = true;
    }
    if let Some(old) = config.remove("enter_when_no_match_after") {
        let on = as_int(&old).map(|n| n > 0).unwrap_or(false);
        config.insert(
            "enable_apply_when_no_match".into(),
            Value::from(if on { 1 } else { 0 }),
        );
        changed = true;
    }
    if let Some(old) = config.remove("completion_suffix") {
        let on = old.as_str().map(|s| !s.is_empty()).unwrap_or(false);
        config.insert(
            "enable_append_space".into(),
            Value::from(if on { 1 } else { 0 }),
        );
        changed = true;
    }
    // Filter mode: boolean enable_filter_subsequence_match -> enum filter_mode
    if let Some(old) = config.remove("enable_filter_subsequence_match") {
        let subseq = as_int(&old).map(|n| n != 0).unwrap_or(false);
        config.insert(
            "filter_mode".into(),
            Value::String(if subseq { "subsequence" } else { "wildcard" }.into()),
        );
        changed = true;
    }
    if config.remove("between_item_and_symbol").is_some() {
        changed = true;
    }
    let bool_keys: Vec<&'static str> = CONFIG_KEYS
        .iter()
        .filter(|d| matches!(d.ty, CfgType::Bool))
        .map(|d| d.key)
        .collect();
    for key in &bool_keys {
        if let Some(v) = config.get_mut(*key) {
            if normalize_bool_value(v) {
                changed = true;
            }
        }
    }
    if let Some(comp) = config.get_mut("completion").and_then(|c| c.as_object_mut()) {
        for (_, v) in comp.iter_mut() {
            if let Some(o) = v.as_object_mut() {
                for key in bool_keys.iter().chain(std::iter::once(&"enable_hooks")) {
                    if let Some(bv) = o.get_mut(*key) {
                        if normalize_bool_value(bv) {
                            changed = true;
                        }
                    }
                }
            }
        }
    }
    changed
}

/// Revert invalid config values to defaults so corrupt/manually edited config cannot silently
/// change behavior. Returns whether anything changed (migration, whitelist cleanup, default
/// backfill, value correction) — the caller persists the corrected config based on this.
pub fn sanitize_config(config: &mut Map<String, Value>, defaults: &Value) -> bool {
    let mut changed = migrate_config(config);
    // Whitelist: drop obsolete keys, keeping only the current CONFIG_KEYS plus `completion`.
    let allowed: Vec<&str> = CONFIG_KEYS
        .iter()
        .map(|d| d.key)
        .chain(std::iter::once("completion"))
        .collect();
    let before = config.len();
    config.retain(|k, _| allowed.contains(&k.as_str()));
    if config.len() != before {
        changed = true;
    }
    if let Some(def) = defaults.as_object() {
        for (k, v) in def {
            if !config.contains_key(k) {
                config.insert(k.clone(), v.clone());
                changed = true;
            }
        }
    }
    // Revert invalid values to the default (same rules as validate_value).
    for def in CONFIG_KEYS {
        let Some(v) = config.get_mut(def.key) else {
            continue;
        };
        let ok = match def.ty {
            CfgType::Bool => as_int(v).map(|n| n == 0 || n == 1).unwrap_or(false),
            CfgType::Str => v.is_string(),
            CfgType::NonEmptyStr => v.as_str().map(|s| !s.is_empty()).unwrap_or(false),
            CfgType::Url => v
                .as_str()
                .map(|s| s.is_empty() || s.starts_with("http://") || s.starts_with("https://"))
                .unwrap_or(false),
            CfgType::IntRange(min, max) => as_int(v).map(|n| n >= min && n <= max).unwrap_or(false),
            CfgType::PositiveInt => as_int(v)
                .map(|n| n >= 1 && n <= i32::MAX as i64)
                .unwrap_or(false),
            CfgType::Enum(vals) => v.as_str().map(|s| vals.contains(&s)).unwrap_or(false),
        };
        if !ok {
            if let Some(d) = defaults.get(def.key) {
                *v = d.clone();
                changed = true;
            }
        }
    }
    // enable_hooks uses override semantics (absent = enabled)
    if let Some(comp) = config.get_mut("completion").and_then(|c| c.as_object_mut()) {
        let mut emptied: Vec<String> = Vec::new();
        for (name, v) in comp.iter_mut() {
            if let Some(o) = v.as_object_mut() {
                let redundant = as_int(&o.get("enable_hooks").cloned().unwrap_or(Value::Null))
                    .map(|n| n == 1)
                    .unwrap_or(false);
                if redundant {
                    o.remove("enable_hooks");
                    changed = true;
                }
                if o.is_empty() {
                    emptied.push(name.clone());
                }
            }
        }
        for name in emptied {
            comp.remove(name.as_str());
            changed = true;
        }
    }
    changed
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::default_config;

    #[test]
    fn migrate_first_generation_keys() {
        let mut c = serde_json::Map::new();
        c.insert("SpaceTab".into(), Value::String("~".into()));
        c.insert("OptionTab".into(), Value::String("?".into()));
        c.insert("WriteSpaceTab".into(), Value::String("!".into()));
        c.insert("continue".into(), Value::String("~".into()));
        c.insert(
            "comp_config".into(),
            serde_json::json!({ "git": { "enable_tip": 0 } }),
        );
        assert!(migrate_config(&mut c));
        assert_eq!(c.get("switch").unwrap(), "~");
        assert_eq!(c.get("stay").unwrap(), "?");
        assert!(c.get("SpaceTab").is_none());
        assert!(c.get("OptionTab").is_none());
        assert!(c.get("WriteSpaceTab").is_none());
        assert!(c.get("continue").is_none());
        assert!(c.get("input").is_none());
        assert_eq!(c.get("completion").unwrap()["git"]["enable_tip"], 0);
        assert!(c.get("comp_config").is_none());
    }

    #[test]
    fn migrate_second_generation_menu_keys() {
        let mut c = serde_json::Map::new();
        c.insert("menu_mode".into(), Value::String("inline".into()));
        c.insert("enable_enter_when_single".into(), Value::from(1));
        c.insert("enable_completions_sort".into(), Value::from(0));
        c.insert("completion_suffix".into(), Value::String(" ".into()));
        c.insert(
            "height_from_menu_bottom_to_cursor_when_above".into(),
            Value::from(2),
        );
        c.insert("between_item_and_symbol".into(), Value::String(" ".into()));
        assert!(migrate_config(&mut c));
        assert_eq!(c.get("show_mode").unwrap(), "inline");
        assert_eq!(c.get("enable_apply_when_single").unwrap(), 1);
        assert_eq!(c.get("enable_sort_by_history").unwrap(), 0);
        assert_eq!(c.get("enable_append_space").unwrap(), 1);
        assert!(c
            .get("height_from_menu_bottom_to_cursor_when_above")
            .is_none());
        assert!(c.get("between_item_and_symbol").is_none());
    }

    #[test]
    fn migrate_menu_show_below_to_auto() {
        let mut c = serde_json::Map::new();
        c.insert("enable_menu_show_below".into(), Value::from(1));
        assert!(migrate_config(&mut c));
        assert_eq!(c.get("show_mode").unwrap(), "auto");
    }

    #[test]
    fn migrate_filter_mode_bool_to_enum() {
        let mut c = serde_json::Map::new();
        c.insert("enable_filter_subsequence_match".into(), Value::from(1));
        assert!(migrate_config(&mut c));
        assert_eq!(c.get("filter_mode").unwrap(), "subsequence");
        assert!(c.get("enable_filter_subsequence_match").is_none());

        let mut c0 = serde_json::Map::new();
        c0.insert("enable_filter_subsequence_match".into(), Value::from(0));
        assert!(migrate_config(&mut c0));
        assert_eq!(c0.get("filter_mode").unwrap(), "wildcard");
    }

    #[test]
    fn migrate_completion_suffix_empty_is_off() {
        let mut c = serde_json::Map::new();
        c.insert("completion_suffix".into(), Value::String(String::new()));
        assert!(migrate_config(&mut c));
        assert_eq!(c.get("enable_append_space").unwrap(), 0);
    }

    #[test]
    fn sanitize_removes_obsolete_and_fills_defaults() {
        let mut c = serde_json::Map::new();
        c.insert("border_color".into(), Value::String("DarkGray".into()));
        c.insert("enable_menu".into(), Value::from(1));
        c.insert("enable_tip".into(), Value::from(0));
        let defaults = default_config("en-US");
        assert!(sanitize_config(&mut c, &defaults));
        assert!(c.get("border_color").is_none());
        assert!(c.get("enable_menu").is_none());
        // Backfill missing default keys
        for k in CONFIG_KEYS.iter().map(|d| d.key) {
            assert!(c.contains_key(k), "missing default key {k}");
        }
        assert_eq!(c.get("enable_tip").unwrap(), 0);
    }

    #[test]
    fn sanitize_reverts_invalid_values_to_defaults() {
        let defaults = default_config("en-US");
        let mut c = serde_json::json!({
            "show_mode": "bogus",
            "enable_tip": 7,
            "trigger_key": 123,
            "language": "zh-CN",
            "enable_append_space": "yes",
            "url": "not-a-url",
        })
        .as_object()
        .unwrap()
        .clone();
        assert!(sanitize_config(&mut c, &defaults));
        assert_eq!(c.get("show_mode").unwrap(), "auto");
        assert_eq!(c.get("enable_tip").unwrap(), 1);
        assert_eq!(c.get("trigger_key").unwrap(), "Tab");
        assert_eq!(c.get("language").unwrap(), "zh-CN");
        assert_eq!(c.get("enable_append_space").unwrap(), 1);
        assert_eq!(c.get("url").unwrap(), "");
    }

    #[test]
    fn sanitize_drops_redundant_enable_hooks_1_keeps_0() {
        let defaults = default_config("en-US");
        let mut c = serde_json::json!({
            "completion": {
                "scoop": { "enable_hooks": 1 },
                "git": { "enable_hooks": 0 },
                "plain": { "enable_tip": 0 }
            }
        })
        .as_object()
        .unwrap()
        .clone();
        assert!(sanitize_config(&mut c, &defaults));
        // enable_hooks:1 is redundant (absent = enabled) -> removed; the empty entry is dropped too
        assert!(c.get("completion").unwrap().get("scoop").is_none());
        // enable_hooks:0 is an explicit disable -> kept
        assert_eq!(c.get("completion").unwrap()["git"]["enable_hooks"], 0);
        // Other keys are unaffected
        assert_eq!(c.get("completion").unwrap()["plain"]["enable_tip"], 0);
        // Second run: already clean, no change reported
        assert!(!sanitize_config(&mut c, &defaults));
    }

    #[test]
    fn sanitize_idempotent_when_already_valid() {
        let defaults = default_config("zh-CN");
        let mut c = defaults.as_object().unwrap().clone();
        // Already a canonical config: must not report any change.
        assert!(!sanitize_config(&mut c, &defaults));
    }

    #[test]
    fn validate_value_accepts_each_type() {
        let show = CONFIG_KEYS.iter().find(|d| d.key == "show_mode").unwrap();
        assert_eq!(
            validate_value(show, "auto"),
            Some(Value::String("auto".into()))
        );
        assert_eq!(validate_value(show, "bogus"), None);
        let tip = CONFIG_KEYS.iter().find(|d| d.key == "enable_tip").unwrap();
        assert_eq!(validate_value(tip, "1"), Some(Value::Number(1.into())));
        assert_eq!(validate_value(tip, "0"), Some(Value::Number(0.into())));
        assert_eq!(validate_value(tip, "true"), None);
        assert_eq!(validate_value(tip, "false"), None);
        assert_eq!(validate_value(tip, "2"), None);
        let url = CONFIG_KEYS.iter().find(|d| d.key == "url").unwrap();
        assert_eq!(
            validate_value(url, "https://x"),
            Some(Value::String("https://x".into()))
        );
        assert_eq!(validate_value(url, "ftp://x"), None);
        let lang = CONFIG_KEYS.iter().find(|d| d.key == "language").unwrap();
        assert_eq!(validate_value(lang, ""), None);
    }
}
