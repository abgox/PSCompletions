//! Post-operation library diff + psc self-heal: after add/update/init, diff the pre-operation
//! index snapshot against the fresh one and persist `temp/change.json`.

use crate::data::{Index, LibraryChanges, Settings};
use crate::net::{
    add_completion, download_list, fetch_text, local_completion_id, refresh_settings_after_add,
    resolve_urls,
};

/// Whether the psc completion's key files exist on disk (its own manifest + config).
pub fn psc_completion_present(completions_dir: &str) -> bool {
    std::path::Path::new(completions_dir)
        .join("psc")
        .join("config.json")
        .exists()
        && std::path::Path::new(completions_dir)
            .join("psc")
            .join("language")
            .join("en-US.json")
            .exists()
}

/// Re-fetch the psc completion (remote index + files) when its files are missing, restoring
/// the module's `info` templates and management completions. Best-effort: an offline failure
/// is tolerated because every later `psc init` (each session / menu start) retries it.
pub fn restore_psc_completion(settings_path: &str, settings: &mut Settings, data_dir: &str) {
    let urls = resolve_urls(settings);
    let Ok(v) = download_list(data_dir, &urls) else {
        return;
    };
    let version = v
        .get("update")
        .and_then(|u| u.as_object())
        .and_then(|o| o.get("psc"))
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string();
    if add_completion(data_dir, "psc", &urls, &version).unwrap_or(false) {
        if let Ok(()) = refresh_settings_after_add(settings, data_dir, "psc") {
            let _ = settings.save(settings_path);
        }
    }
}

/// Fetch the newest remote module version (first URL that returns a parseable `module/version.json`).
/// The CLI does not compare versions — it records whatever it fetched; the module compares the
/// value against its installed version at render time (replaces the background job / env var).
pub fn fetch_module_version(settings: &Settings) -> Option<String> {
    let urls = resolve_urls(settings);
    for u in urls {
        if let Ok(text) = fetch_text(&[u], "module/version.json") {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) {
                let newv = v
                    .get("version")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .trim_start_matches('v')
                    .to_string();
                if !newv.is_empty() && newv.chars().all(|c| c.is_ascii_digit() || c == '.') {
                    return Some(newv);
                }
            }
            // Successful fetch but unparseable: try the next mirror.
            continue;
        }
    }
    None
}

/// Pure post-operation diff: compute `added`/`removed`/`renamed`/`update` from the fresh index
/// and the installed settings, folding in the renames already executed during this command
/// (they no longer appear in the post-state diff — the old name is gone from settings — so
/// without them a rename would be misreported as added+removed).
pub fn compute_post_changes(
    data_dir: &str,
    settings: &Settings,
    old_list: &[String],
    index: &Index,
    executed_renames: &[(String, String)],
) -> LibraryChanges {
    let mut rename_map: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    for installed in settings.list() {
        let Some(id) = local_completion_id(data_dir, &installed) else {
            continue;
        };
        if let Some((new_name, _)) = index.ids.iter().find(|(_, v)| **v == id) {
            if new_name != &installed {
                rename_map.insert(installed.clone(), new_name.clone());
            }
        }
    }
    for (old, new) in executed_renames {
        rename_map.insert(old.clone(), new.clone());
    }
    let rename_keys: std::collections::HashSet<String> = rename_map.keys().cloned().collect();
    let rename_vals: std::collections::HashSet<String> = rename_map.values().cloned().collect();
    let new_list: Vec<String> = index.update.keys().cloned().collect();
    let mut changes = LibraryChanges::load(data_dir);
    let mut added: Vec<String> = new_list
        .iter()
        .filter(|n| !old_list.contains(n))
        .filter(|n| !rename_vals.contains(*n))
        .cloned()
        .collect();
    added.sort();
    changes.added = std::mem::take(&mut added);
    let mut removed: Vec<String> = old_list
        .iter()
        .filter(|n| !new_list.contains(n))
        .filter(|n| !rename_keys.contains(*n))
        .cloned()
        .collect();
    changes.removed = std::mem::take(&mut removed);
    let mut renamed: Vec<(String, String)> = rename_map.into_iter().collect();
    renamed.sort_by(|a, b| a.0.cmp(&b.0));
    changes.renamed = renamed;
    let mut need_update: Vec<String> = settings
        .list()
        .into_iter()
        .filter(|name| !rename_keys.contains(name))
        .filter(|name| index.update.contains_key(name))
        .filter(|name| {
            let dir = format!("{data_dir}/completions/{name}");
            if let Ok(meta) = std::fs::symlink_metadata(&dir) {
                if meta.file_type().is_symlink() {
                    return false;
                }
            }
            let local = std::fs::read_to_string(format!("{dir}/.update")).unwrap_or_default();
            let remote = index.update.get(name).cloned().unwrap_or_default();
            local.trim() != remote
        })
        .collect();
    need_update.sort();
    changes.update = need_update;
    changes
}

/// After an add/update completes, refresh temp/change.json (update/added/removed/renamed/module)
/// by diffing the pre-operation index snapshot against the fresh one, and record the remote module
/// version. Runs synchronously AFTER the operation so a completion this command just touched is
/// not reported as needing an update; `old_list` is captured before `download_list` overwrites the
/// cache. On a fetch failure the existing `module` value is preserved (don't drop a pending notice
/// just because one check hit the network and another didn't).
pub fn record_post_check(
    data_dir: &str,
    settings: &Settings,
    old_list: &[String],
    index: &Index,
    executed_renames: &[(String, String)],
) {
    let mut changes = compute_post_changes(data_dir, settings, old_list, index, executed_renames);
    if let Some(v) = fetch_module_version(settings) {
        changes.module = Some(v);
    }
    changes.last_check = Some(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
    );
    changes.save(data_dir);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::data::Settings;

    // Each test gets a unique dir: Rust runs tests in parallel, so sharing one path
    // would let one test's cleanup clobber another's fixtures.
    fn test_base() -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        std::env::temp_dir().join(format!(
            "psc-postcheck-test-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ))
    }

    #[test]
    fn psc_completion_present_checks_key_files() {
        let base = test_base();
        let completions = base.join("completions");
        std::fs::create_dir_all(completions.join("psc/language")).unwrap();
        let s = completions.to_str().unwrap();
        assert!(!psc_completion_present(s));
        std::fs::write(completions.join("psc/config.json"), "{}").unwrap();
        assert!(!psc_completion_present(s), "manifest is also required");
        std::fs::write(completions.join("psc/language/en-US.json"), "{}").unwrap();
        assert!(psc_completion_present(s));
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn compute_post_changes_merges_executed_renames() {
        let base = test_base();
        let data_dir = base.to_str().unwrap();
        std::fs::create_dir_all(format!("{data_dir}/completions/bar")).unwrap();
        std::fs::write(
            format!("{data_dir}/completions/bar/config.json"),
            r#"{"id":"abc"}"#,
        )
        .unwrap();
        std::fs::write(format!("{data_dir}/completions/bar/.update"), "v1").unwrap();
        let settings = Settings {
            alias: [("bar".to_string(), Vec::new())].into_iter().collect(),
            config: serde_json::json!({}),
        };
        let mut index = Index::default();
        index.ids.insert("bar".to_string(), "abc".to_string());
        index.update.insert("bar".to_string(), "v1".to_string());
        let old_list = vec!["foo".to_string()];

        // Without the executed_renames parameter the post-state diff would report
        // added=["bar"] + removed=["foo"]; the merge must turn it into a single rename.
        let changes = compute_post_changes(
            data_dir,
            &settings,
            &old_list,
            &index,
            &[("foo".into(), "bar".into())],
        );
        assert_eq!(
            changes.renamed,
            vec![("foo".to_string(), "bar".to_string())]
        );
        assert!(
            changes.added.is_empty(),
            "renamed completion must not be added"
        );
        assert!(
            changes.removed.is_empty(),
            "renamed completion must not be removed"
        );
        assert!(
            changes.update.is_empty(),
            "up-to-date completion must not need update"
        );
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn compute_post_changes_reports_plain_add_and_remove() {
        let base = test_base();
        let data_dir = base.to_str().unwrap();
        std::fs::create_dir_all(format!("{data_dir}/completions/foo")).unwrap();
        std::fs::write(
            format!("{data_dir}/completions/foo/config.json"),
            r#"{"id":"abc"}"#,
        )
        .unwrap();
        std::fs::write(format!("{data_dir}/completions/foo/.update"), "v1").unwrap();
        let settings = Settings {
            alias: [("foo".to_string(), Vec::new())].into_iter().collect(),
            config: serde_json::json!({}),
        };
        let mut index = Index::default();
        index.ids.insert("foo".to_string(), "abc".to_string());
        index.update.insert("foo".to_string(), "v1".to_string());
        let old_list = Vec::<String>::new();

        let changes = compute_post_changes(data_dir, &settings, &old_list, &index, &[]);
        assert_eq!(changes.added, vec!["foo".to_string()]);
        assert!(changes.removed.is_empty());
        assert!(changes.renamed.is_empty());
        assert!(changes.update.is_empty());
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn record_post_check_writes_last_check_even_offline() {
        // last_check drives the menu's stale-update hint: it must land in change.json on
        // every post-check, including when the module-version fetch fails (offline).
        let base = test_base();
        let data_dir = base.to_str().unwrap();
        std::fs::create_dir_all(format!("{data_dir}/completions/foo")).unwrap();
        std::fs::write(
            format!("{data_dir}/completions/foo/config.json"),
            r#"{"id":"abc"}"#,
        )
        .unwrap();
        std::fs::write(format!("{data_dir}/completions/foo/.update"), "v1").unwrap();
        let settings = Settings {
            alias: [("foo".to_string(), Vec::new())].into_iter().collect(),
            config: serde_json::json!({}),
        };
        let mut index = Index::default();
        index.ids.insert("foo".to_string(), "abc".to_string());
        index.update.insert("foo".to_string(), "v1".to_string());

        record_post_check(data_dir, &settings, &[], &index, &[]);

        let loaded = LibraryChanges::load(data_dir);
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        match loaded.last_check {
            Some(t) => assert!(
                now.saturating_sub(t) < 60,
                "last_check must be a fresh timestamp, got {t} vs now {now}"
            ),
            None => panic!("last_check must be written"),
        }
        std::fs::remove_dir_all(&base).ok();
    }
}
