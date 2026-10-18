//! Shared validation helpers: completion-name status, uniform error emission, and
//! settings-map utilities used by several commands.

use std::process::ExitCode;

use serde_json::Value;

use crate::data::{read_text, Index, Settings};
use crate::messages::msg_cli;
use crate::output::{err, meta, Out};

/// Completion name status: 2=installed/local link (alias set or dir on disk), 1=remote-only, 0=unknown.
/// All subcommands that accept a completion name share this same determination.
pub fn name_status(settings: &Settings, index: &Index, completions_dir: &str, name: &str) -> u8 {
    // Reject before touching the filesystem: a name carrying separators would make the
    // `completions_dir/name` probe resolve outside the library directory.
    if !is_valid_name(name) {
        return 0;
    }
    if settings.alias.contains_key(name)
        || std::fs::symlink_metadata(format!("{completions_dir}/{name}")).is_ok()
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
///
/// Returns the stable `code` a machine branches on together with the message a human reads
/// (design/json.md): `not_available` for a name that is not usable, `not_installed` for one that
/// exists remotely but is not installed here.
pub fn name_error(
    lang: &str,
    name: &str,
    status: u8,
    need_installed: bool,
) -> Option<(&'static str, String)> {
    if !is_valid_name(name) || status == 0 {
        return Some((
            "not_available",
            format!("{name} {}", msg_cli(lang, "not_available")),
        ));
    }
    if need_installed && status == 1 {
        return Some((
            "not_installed",
            format!("{name}: {}", msg_cli(lang, "no_completion")),
        ));
    }
    None
}

/// Parameter-count validation error: the envelope's `too_few_params`, a usage error (exit 2).
pub fn param_err(out: &Out, lang: &str, json: bool, data_dir: &str) -> ExitCode {
    let msg = msg_cli(lang, "param_min");
    if json {
        return err("too_few_params", &msg, None, &meta(None, data_dir), true);
    }
    out.line(&msg);
    ExitCode::from(2)
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

/// Get (creating if needed) one completion's config map, repairing a non-object entry.
/// `settings.config` and `config.completion` may hold anything a hand-edited file put there; a
/// non-object is replaced rather than unwrapped.
pub fn ensure_completion_entry<'a>(
    settings: &'a mut Settings,
    name: &str,
) -> &'a mut serde_json::Map<String, Value> {
    let comp = ensure_completion_map(settings);
    let entry = comp
        .entry(name.to_string())
        .or_insert_with(|| serde_json::json!({}));
    if !entry.is_object() {
        *entry = serde_json::json!({});
    }
    entry.as_object_mut().unwrap()
}

/// Restore a completion's trigger aliases to its config.json alias (or the name itself).
///
/// The alias map's order **is** the claim order, and the hosts build their `word -> completion`
/// table by inserting in it, so declaring the words here — moving the completion to the end —
/// is what makes a later declaration win. Conflicts are deliberately not resolved: the last
/// claim simply wins, and `psc alias` shows the current ownership.
pub fn reset_alias(settings: &mut Settings, data_dir: &str, name: &str) {
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
    settings.alias.shift_remove(name);
    settings.alias.insert(name.to_string(), desired);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reset_alias_declares_the_config_words_in_order() {
        // No filtering: the config's words are declared as-is, and the completion moves to the
        // end of the map — that order is what makes a later declaration win for the hosts.
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
        s.alias.insert("new".to_string(), vec!["old".to_string()]);
        reset_alias(&mut s, base.to_str().unwrap(), "new");
        assert_eq!(
            s.alias.get("new").unwrap(),
            &vec!["hx".to_string(), "new".to_string()]
        );
        // Declared last, so it is last in the map.
        assert_eq!(s.alias.keys().last().unwrap(), "new");
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn reset_alias_falls_back_to_the_name_without_a_config_alias() {
        let base = std::env::temp_dir().join(format!("psc-validate-name-{}", std::process::id()));
        let dir = base.join("completions/solo");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("config.json"), r#"{"language":["en-US"]}"#).unwrap();
        let mut s = Settings::default();
        reset_alias(&mut s, base.to_str().unwrap(), "solo");
        assert_eq!(s.alias.get("solo").unwrap(), &vec!["solo".to_string()]);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn name_status_counts_dangling_link_as_present() {
        #[cfg(unix)]
        {
            use std::sync::atomic::{AtomicU64, Ordering};
            static COUNTER: AtomicU64 = AtomicU64::new(0);
            let n = COUNTER.fetch_add(1, Ordering::Relaxed);
            let base = std::env::temp_dir()
                .join(format!("psc-validate-dangle-{}-{n}", std::process::id()));
            let dir = base.join("completions");
            std::fs::create_dir_all(&dir).unwrap();
            std::os::unix::fs::symlink(base.join("gone"), dir.join("dangle")).unwrap();
            let s = Settings::default();
            let index = Index::default();
            assert_eq!(
                name_status(
                    &s,
                    &index,
                    base.join("completions").to_str().unwrap(),
                    "dangle"
                ),
                2
            );
            std::fs::remove_dir_all(&base).ok();
        }
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
