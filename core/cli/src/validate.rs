//! Shared validation helpers: completion-name status, uniform error emission, and
//! settings-map utilities used by several commands.

use std::process::ExitCode;

use serde_json::Value;

use crate::data::{read_text, Index, Settings};
use crate::messages::msg_cli;
use crate::output::{fail, Out};

/// Completion name status: 2=installed/local link (alias set or dir on disk), 1=remote-only, 0=unknown.
/// All subcommands that accept a completion name share this same determination.
pub fn name_status(settings: &Settings, index: &Index, completions_dir: &str, name: &str) -> u8 {
    // Reject before touching the filesystem: a name carrying separators would make the
    // `completions_dir/name` probe resolve outside the library directory.
    if !is_valid_name(name) {
        return 0;
    }
    if settings.alias.contains_key(name)
        || std::path::Path::new(&format!("{completions_dir}/{name}")).exists()
    {
        return 2;
    }
    if index.remote_names().iter().any(|n| n == name) {
        return 1;
    }
    0
}

pub fn is_valid_name(name: &str) -> bool {
    if name.is_empty() || name == "." || name == ".." {
        return false;
    }
    if name.contains('/') || name.contains('\\') || name.contains(':') {
        return false;
    }
    // Disallow control/space to keep trigger words unambiguous.
    if name.chars().any(|c| c.is_control() || c == ' ') {
        return false;
    }
    true
}

/// Validate a completion name uniformly and report errors. `need_installed`: whether the command
/// requires the completion to be installed (rm/update/completion/alias).
/// Returns the error message when the name is invalid.
pub fn name_error(lang: &str, name: &str, status: u8, need_installed: bool) -> Option<String> {
    if !is_valid_name(name) {
        return Some(format!("{name} {}", msg_cli(lang, "not_available")));
    }
    if status == 0 {
        return Some(format!("{name} {}", msg_cli(lang, "not_available")));
    }
    if need_installed && status == 1 {
        return Some(format!("{name}: {}", msg_cli(lang, "no_completion")));
    }
    None
}

/// Parameter-count validation error: routed through the output contract (`fail`).
pub fn param_err(out: &Out, lang: &str, json: bool) -> ExitCode {
    fail(out, msg_cli(lang, "param_min"), json)
}

/// `<data>` dir from the settings path (`<data>/settings.json`).
pub fn data_dir_of(settings_path: &str) -> String {
    std::path::Path::new(settings_path)
        .parent()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default()
}

/// Get (creating if needed) the per-completion config map in `settings.config.completion`.
pub fn ensure_completion_map(settings: &mut Settings) -> &mut serde_json::Map<String, Value> {
    if !settings.config.is_object() {
        settings.config = serde_json::json!({});
    }
    let obj = settings.config.as_object_mut().unwrap();
    let comp = obj
        .entry("completion")
        .or_insert_with(|| serde_json::json!({}));
    if !comp.is_object() {
        *comp = serde_json::json!({});
    }
    comp.as_object_mut().unwrap()
}

/// Split `desired` trigger aliases for `name` into `(kept, skipped)`.
/// A word already owned by another completion stays with its owner;
/// each skipped word pairs with its owner's name for the warning.
pub fn filter_owned_triggers(
    settings: &Settings,
    name: &str,
    desired: Vec<String>,
) -> (Vec<String>, Vec<(String, String)>) {
    let mut kept = Vec::new();
    let mut skipped = Vec::new();
    for a in desired {
        match settings
            .alias
            .iter()
            .find(|(k, v)| k.as_str() != name && v.iter().any(|x| x == &a))
            .map(|(k, _)| k.clone())
        {
            Some(owner) => skipped.push((a, owner)),
            None => kept.push(a),
        }
    }
    (kept, skipped)
}

/// Restore a completion's trigger aliases to its config.json alias (or the name itself).
/// Words already owned by another completion stay with their owner;
/// skipped words are returned for the warning.
pub fn reset_alias(settings: &mut Settings, data_dir: &str, name: &str) -> Vec<(String, String)> {
    let config_path = format!("{data_dir}/completions/{name}/config.json");
    let desired: Vec<String> = read_text(&config_path)
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .map(|config| {
            config
                .get("alias")
                .and_then(|a| a.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|x| x.as_str().map(String::from))
                        .collect::<Vec<_>>()
                })
                .filter(|a: &Vec<String>| !a.is_empty())
                .unwrap_or_else(|| vec![name.to_string()])
        })
        .unwrap_or_else(|| vec![name.to_string()]);
    let (kept, skipped) = filter_owned_triggers(settings, name, desired);
    settings.alias.insert(name.to_string(), kept);
    skipped
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filter_owned_triggers_keeps_earlier_owner() {
        let mut s = Settings::default();
        s.alias.insert(
            "helix".to_string(),
            vec!["helix".to_string(), "hx".to_string()],
        );
        let (kept, skipped) = filter_owned_triggers(
            &s,
            "helix-xxx",
            vec!["helix-xxx".to_string(), "hx".to_string()],
        );
        assert_eq!(kept, vec!["helix-xxx".to_string()]);
        assert_eq!(skipped, vec![("hx".to_string(), "helix".to_string())]);
        // A completion's own words are never filtered.
        let (kept, skipped) =
            filter_owned_triggers(&s, "helix", vec!["helix".to_string(), "hx".to_string()]);
        assert_eq!(kept.len(), 2);
        assert!(skipped.is_empty());
    }

    #[test]
    fn reset_alias_skips_words_owned_by_earlier_completion() {
        let base = std::env::temp_dir().join(format!("psc-validate-test-{}", std::process::id()));
        let dir = base.join("completions/new");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("config.json"),
            r#"{"language":["en-US"],"alias":["hx","new"]}"#,
        )
        .unwrap();
        let mut s = Settings::default();
        s.alias.insert(
            "helix".to_string(),
            vec!["helix".to_string(), "hx".to_string()],
        );
        let skipped = reset_alias(&mut s, base.to_str().unwrap(), "new");
        assert_eq!(skipped, vec![("hx".to_string(), "helix".to_string())]);
        assert_eq!(s.alias.get("new").unwrap(), &vec!["new".to_string()]);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn ensure_completion_map_handles_corrupt_config() {
        let mut s = Settings {
            config: serde_json::json!(123),
            ..Default::default()
        };
        {
            let map = ensure_completion_map(&mut s);
            assert!(map.is_empty());
        }
        assert!(s.config.is_object());
    }

    #[test]
    fn ensure_completion_map_handles_corrupt_completion_value() {
        let mut s = Settings {
            config: serde_json::json!({ "completion": "not-an-object" }),
            ..Default::default()
        };
        {
            let map = ensure_completion_map(&mut s);
            assert!(map.is_empty());
        }
        assert!(s.config["completion"].is_object());
    }
}
