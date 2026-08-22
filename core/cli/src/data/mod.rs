//! Module data layer: reads/writes the module's data files (settings.json, temp/completions.json)
//! and loads localized psc manifest info. Platform-agnostic.

use std::collections::HashMap;

use serde_json::{json, Value};

pub mod config;

/// Strip a leading UTF-8 BOM if present (legacy PowerShell 5.1 `Out-File -Encoding utf8`
/// writes one, which breaks serde_json parsing).
pub fn strip_bom(s: &str) -> &str {
    s.strip_prefix('\u{feff}').unwrap_or(s)
}

/// Read a UTF-8 text file, stripping a leading BOM.
pub fn read_text(path: &str) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    Some(strip_bom(&text).to_string())
}

/// Whether a completion entry exists on disk (`<data>/completions/<name>`), as a real directory
/// or as a link (symlink/junction from `scripts/link-completion.ps1`). Uses `symlink_metadata`,
/// so a dangling link still counts as present.
pub fn completion_dir_exists(data_dir: &str, name: &str) -> bool {
    std::fs::symlink_metadata(format!("{data_dir}/completions/{name}")).is_ok()
}

/// Remove a completion entry: a symlink/junction is removed **as a link only** (the linked
/// local source stays intact), a real directory recursively, a missing path is a no-op.
pub fn remove_completion_entry(data_dir: &str, name: &str) {
    let dir = format!("{data_dir}/completions/{name}");
    if let Ok(md) = std::fs::symlink_metadata(&dir) {
        if md.file_type().is_symlink() {
            #[cfg(windows)]
            let _ = std::fs::remove_dir(&dir);
            #[cfg(not(windows))]
            let _ = std::fs::remove_file(&dir);
        } else {
            let _ = std::fs::remove_dir_all(&dir);
        }
    }
}

/// `settings.json` — `{ config, alias }`.
#[derive(Debug, Clone, Default)]
pub struct Settings {
    /// completion name -> trigger aliases.
    pub alias: HashMap<String, Vec<String>>,
    /// module config (default_config merged with user overrides), incl. `completion` per-completion map.
    pub config: Value,
}

impl Settings {
    pub fn load(path: &str) -> Option<Settings> {
        let text = read_text(path)?;
        let v: Value = match serde_json::from_str(&text) {
            Ok(v) => v,
            Err(_) => {
                // Corrupt settings.json: back it up (never silently drop the damaged content)
                // and fall back to defaults; the next save won't overwrite it without a trace.
                let _ = std::fs::rename(path, format!("{path}.corrupt"));
                return None;
            }
        };
        let alias = v
            .get("alias")
            .and_then(|a| a.as_object())
            .map(|o| {
                o.iter()
                    .map(|(k, val)| {
                        let arr = val
                            .as_array()
                            .map(|a| {
                                a.iter()
                                    .filter_map(|x| x.as_str().map(String::from))
                                    .collect()
                            })
                            .unwrap_or_default();
                        (k.clone(), arr)
                    })
                    .collect()
            })
            .unwrap_or_default();
        Some(Settings {
            alias,
            config: v.get("config").cloned().unwrap_or_else(|| json!({})),
        })
    }

    pub fn save(&self, path: &str) -> Result<(), String> {
        let data = json!({ "config": self.config, "alias": self.alias });
        let text = serde_json::to_string_pretty(&data).map_err(|e| e.to_string())?;
        // Atomic replace: write a sibling temp file (pid-suffixed so concurrent psc processes
        // don't collide), then rename over the target. A crash mid-write can never leave a
        // half-written settings.json (which the next load would treat as corrupt).
        let tmp = format!("{path}.{}.tmp", std::process::id());
        std::fs::write(&tmp, text).map_err(|e| e.to_string())?;
        std::fs::rename(&tmp, path).map_err(|e| e.to_string())
    }

    /// Sorted completion names (alias map keys).
    pub fn list(&self) -> Vec<String> {
        let mut v: Vec<String> = self.alias.keys().cloned().collect();
        v.sort();
        v
    }

    /// Module language from config, defaulting to "en-US".
    pub fn language(&self) -> String {
        self.config
            .get("language")
            .and_then(|l| l.as_str())
            .map(String::from)
            .unwrap_or_else(|| "en-US".into())
    }
}

/// `temp/completions.json` — `{ update: {name: version}, meta: {name: {id, lang: {url, description}}} }`.
#[derive(Debug, Clone, Default)]
pub struct Index {
    pub update: HashMap<String, String>,
    pub meta: Value,
    /// completion name -> stable id (from meta.<name>.id).
    pub ids: HashMap<String, String>,
}

impl Index {
    pub fn load(path: &str) -> Option<Index> {
        let text = read_text(path)?;
        let v: Value = serde_json::from_str(&text).ok()?;
        Some(Index::from_value(v))
    }

    /// Build an index from a parsed `{ update, meta }` value.
    pub fn from_value(v: Value) -> Index {
        let update = v
            .get("update")
            .and_then(|u| u.as_object())
            .map(|o| {
                o.iter()
                    .filter_map(|(k, val)| val.as_str().map(|s| (k.clone(), s.to_string())))
                    .collect()
            })
            .unwrap_or_default();
        let meta = v.get("meta").cloned().unwrap_or_else(|| json!({}));
        let ids = meta
            .as_object()
            .map(|m| {
                m.iter()
                    .filter_map(|(name, info)| {
                        info.get("id")
                            .and_then(|i| i.as_str())
                            .map(|i| (name.clone(), i.to_string()))
                    })
                    .collect()
            })
            .unwrap_or_default();
        Index { update, meta, ids }
    }

    /// Sorted remote completion names (update keys).
    pub fn remote_names(&self) -> Vec<String> {
        let mut v: Vec<String> = self.update.keys().cloned().collect();
        v.sort();
        v
    }
}

/// `temp/change.json` — a single JSON recording the pending notifications surfaced to the module:
/// which completions need an update, which were added or removed in the library, which were
/// renamed (`[old, new]` pairs), and the newest remote module version (written whenever it was
/// fetched; the module compares it against its own installed version).
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct LibraryChanges {
    #[serde(default)]
    pub update: Vec<String>,
    #[serde(default)]
    pub added: Vec<String>,
    #[serde(default)]
    pub removed: Vec<String>,
    #[serde(default)]
    pub renamed: Vec<(String, String)>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub module: Option<String>,
}

impl LibraryChanges {
    /// Load from `<data>/temp/change.json`; a missing or corrupt file yields empty defaults.
    pub fn load(data_dir: &str) -> LibraryChanges {
        let path = format!("{data_dir}/temp/change.json");
        read_text(&path)
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or_default()
    }

    /// Atomically save to `<data>/temp/change.json`.
    pub fn save(&self, data_dir: &str) {
        if let Ok(text) = serde_json::to_string(self) {
            let tmp = format!("{data_dir}/temp/change.json.{}.tmp", std::process::id());
            let path = format!("{data_dir}/temp/change.json");
            if std::fs::write(&tmp, text).is_ok() {
                let _ = std::fs::rename(&tmp, path);
            }
        }
    }
}

/// Default module config (mirrors the module's `default_config`), used when bootstrapping
/// a fresh `settings.json`.
pub fn default_config(language: &str) -> Value {
    json!({
        "url": "",
        "language": language,
        "enable_auto_alias_setup": 1,
        "switch": "~",
        "stay": "?",
        "trigger_key": "Tab",
        "show_mode": "auto",
        "enable_native_completion": 1,
        "enable_apply_when_single": 0,
        "enable_list_loop": 1,
        "enable_apply_when_no_match": 0,
        "enable_tip": 1,
        "enable_tip_usage": 1,
        "enable_tip_example": 1,
        "filter_mode": "wildcard",
        "enable_sort_by_history": 1,
        "enable_cache": 1,
        "enable_path_trailing_separator": 1,
        "enable_append_space": 1,
        "color_focus": "red",
        "color_match": "cyan"
    })
}

/// Bootstrap `settings.json` from the installed completions (mirrors the module's `new_data`):
/// alias per completion (from config.json) + per-completion config defaults (from the manifest
/// `config` array). Returns `{ alias, config }`.
pub fn build_default_data(completions_dir: &str, language: &str) -> Value {
    let mut alias = serde_json::Map::new();
    let mut config = default_config(language);
    config["completion"] = json!({});
    let comp = config["completion"].as_object_mut().unwrap();

    let lang_file = if language.starts_with("zh") {
        "zh-CN"
    } else {
        "en-US"
    };
    if let Ok(entries) = std::fs::read_dir(completions_dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            let dir = entry.path();
            if !dir.is_dir() {
                continue;
            }
            let config_path = dir.join("config.json");
            if !config_path.exists() {
                continue;
            }
            let c: Value = std::fs::read_to_string(&config_path)
                .ok()
                .and_then(|t| serde_json::from_str(&t).ok())
                .unwrap_or_else(|| json!({}));
            let aliases: Vec<Value> = c
                .get("alias")
                .and_then(|a| a.as_array())
                .filter(|a| !a.is_empty())
                .map(|a| a.to_vec())
                .unwrap_or_else(|| vec![Value::String(name.clone())]);
            alias.insert(name.clone(), Value::Array(aliases));

            let manifest_path = dir.join("language").join(format!("{lang_file}.json"));
            let mut comp_defaults = serde_json::Map::new();
            if let Ok(text) = std::fs::read_to_string(&manifest_path) {
                if let Ok(manifest) = serde_json::from_str::<Value>(&text) {
                    if let Some(items) = manifest.get("config").and_then(|x| x.as_array()) {
                        for item in items {
                            if let (Some(k), Some(v)) =
                                (item.get("name").and_then(|x| x.as_str()), item.get("value"))
                            {
                                comp_defaults.insert(k.to_string(), v.clone());
                            }
                        }
                    }
                }
            }
            if !comp_defaults.is_empty() {
                comp.insert(name.clone(), Value::Object(comp_defaults));
            }
        }
    }
    json!({ "alias": Value::Object(alias), "config": config })
}

/// Load the psc completion's localized `info` object from `completions/psc/language/<lang>.json`.
pub fn load_psc_info(completions_dir: &str, lang: &str) -> Value {
    let mut path = std::path::Path::new(completions_dir)
        .join("psc")
        .join("language")
        .join(format!("{lang}.json"));
    if !path.exists() {
        path = std::path::Path::new(completions_dir)
            .join("psc")
            .join("language")
            .join("en-US.json");
    }
    let text = read_text(&path.to_string_lossy()).unwrap_or_default();
    let v: Value = serde_json::from_str(&text).unwrap_or_else(|_| json!({}));
    v.get("info").cloned().unwrap_or_else(|| json!({}))
}

/// Resolve a dotted path (e.g. `add.err.no`) in the psc info object.
pub fn info_path(info: &Value, path: &[&str]) -> Option<Value> {
    let mut node = info;
    for seg in path {
        node = node.get(*seg)?;
    }
    Some(node.clone())
}

/// Join an info value (string or array of lines) into one line-joined string.
pub fn info_text(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Array(arr) => arr
            .iter()
            .filter_map(|v| v.as_str())
            .collect::<Vec<_>>()
            .join("\n"),
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    static TMP_COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

    fn tmp_file(content: &str) -> (std::path::PathBuf, String) {
        let n = TMP_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let mut p = std::env::temp_dir();
        p.push(format!("psc-data-test-{}-{n}.json", std::process::id()));
        std::fs::write(&p, content).unwrap();
        let s = p.to_string_lossy().to_string();
        (p, s)
    }

    #[test]
    fn settings_load_parse_alias_and_config() {
        let (_p, path) = tmp_file(
            r#"{"config":{"language":"en-US","completion":{"git":{"max_commit":30}}},"alias":{"git":["git","g"],"scoop":["scoop"]}}"#,
        );
        let s = Settings::load(&path).unwrap();
        assert_eq!(s.list(), vec!["git", "scoop"]);
        assert_eq!(
            s.alias.get("git").unwrap(),
            &vec!["git".to_string(), "g".to_string()]
        );
        assert_eq!(s.language(), "en-US");
        assert_eq!(s.config["completion"]["git"]["max_commit"], 30);
        std::fs::remove_file(_p).ok();
    }

    #[test]
    fn settings_save_roundtrip() {
        let (_p, path) = tmp_file(r#"{"config":{},"alias":{}}"#);
        let mut s = Settings::load(&path).unwrap();
        s.alias.insert("git".into(), vec!["git".into()]);
        s.config["language"] = json!("zh-CN");
        s.save(&path).unwrap();
        let reloaded = Settings::load(&path).unwrap();
        assert!(reloaded.alias.contains_key("git"));
        assert_eq!(reloaded.language(), "zh-CN");
        std::fs::remove_file(_p).ok();
    }

    #[test]
    fn index_load_update_and_meta() {
        let (_p, path) = tmp_file(
            r#"{"update":{"git":"2024-01-01","scoop":"2024-02-01"},"meta":{"git":{"id":"11111111-2222-3333-4444-555555555555","en-US":{"url":"https://git-scm.com","description":["VCS"]}}}}"#,
        );
        let idx = Index::load(&path).unwrap();
        assert_eq!(
            idx.update.get("git").map(|s| s.as_str()),
            Some("2024-01-01")
        );
        assert_eq!(idx.meta["git"]["en-US"]["url"], "https://git-scm.com");
        assert_eq!(
            idx.ids.get("git").map(|s| s.as_str()),
            Some("11111111-2222-3333-4444-555555555555")
        );
        std::fs::remove_file(_p).ok();
    }

    #[test]
    fn index_ids_missing_meta_id_defaults_empty() {
        let (_p, path) = tmp_file(
            r#"{"update":{"git":"2024-01-01"},"meta":{"git":{"en-US":{"url":"u","description":["d"]}}}}"#,
        );
        let idx = Index::load(&path).unwrap();
        assert!(idx.ids.is_empty());
        std::fs::remove_file(_p).ok();
    }

    #[test]
    fn info_text_joins_arrays() {
        let v = json!(["a", "b"]);
        assert_eq!(info_text(&v), "a\nb");
        assert_eq!(info_text(&json!("x")), "x");
    }

    #[test]
    fn settings_load_backs_up_corrupt_file() {
        let (_p, path) = tmp_file("not-json{{{");
        assert!(
            Settings::load(&path).is_none(),
            "corrupt settings must load as None"
        );
        assert!(
            std::path::Path::new(&format!("{path}.corrupt")).exists(),
            "corrupt file must be backed up, not silently dropped"
        );
        assert!(
            !std::path::Path::new(&path).exists(),
            "original must be moved away before defaults take over"
        );
        std::fs::remove_file(format!("{path}.corrupt")).ok();
    }

    #[test]
    fn settings_save_is_atomic_and_leaves_no_tmp() {
        let (_p, path) = tmp_file(r#"{"config":{},"alias":{}}"#);
        let mut s = Settings::load(&path).unwrap();
        s.alias.insert("git".into(), vec!["git".into()]);
        s.save(&path).unwrap();
        let reloaded = Settings::load(&path).unwrap();
        assert!(reloaded.alias.contains_key("git"));
        let tmp = format!("{path}.{}.tmp", std::process::id());
        assert!(
            !std::path::Path::new(&tmp).exists(),
            "temp file must be renamed away after save"
        );
        std::fs::remove_file(_p).ok();
    }

    /// Build a temp data dir with `completions/<name>` laid out. Returns (root, path string).
    fn tmp_data_dir(name: &str) -> (std::path::PathBuf, String) {
        let n = TMP_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let mut root = std::env::temp_dir();
        root.push(format!("psc-data-rm-{}-{n}", std::process::id()));
        std::fs::create_dir_all(root.join("completions").join(name)).unwrap();
        let s = root.to_string_lossy().to_string();
        (root, s)
    }

    #[test]
    fn completion_dir_exists_detects_dir_and_missing() {
        let (root, data) = tmp_data_dir("scoop");
        assert!(completion_dir_exists(&data, "scoop"));
        assert!(!completion_dir_exists(&data, "nope"));
        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn remove_real_dir_deletes_contents() {
        let (root, data) = tmp_data_dir("scoop");
        std::fs::write(root.join("completions/scoop/manifest.json"), "{}").unwrap();
        remove_completion_entry(&data, "scoop");
        assert!(!root.join("completions/scoop").exists());
        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn remove_missing_is_noop() {
        let (root, data) = tmp_data_dir("scoop");
        remove_completion_entry(&data, "nope");
        assert!(!root.join("completions/nope").exists());
        std::fs::remove_dir_all(root).ok();
    }

    #[cfg(windows)]
    #[test]
    fn remove_junction_removes_link_but_keeps_target() {
        use std::os::windows::fs as wfs;
        let n = TMP_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let mut root = std::env::temp_dir();
        root.push(format!("psc-data-junction-{}-{n}", std::process::id()));
        let src = root.join("src");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(src.join("keep.txt"), "keep").unwrap();
        // link under the data dir's completions layout
        let data_dir = root.join("data");
        std::fs::create_dir_all(data_dir.join("completions")).unwrap();
        let link = data_dir.join("completions/scoop");
        wfs::symlink_dir(&src, &link).unwrap();
        let data = data_dir.to_string_lossy().to_string();

        assert!(completion_dir_exists(&data, "scoop"));
        assert!(std::fs::symlink_metadata(&link)
            .unwrap()
            .file_type()
            .is_symlink());

        remove_completion_entry(&data, "scoop");

        assert!(!link.exists(), "link must be removed");
        assert!(
            src.join("keep.txt").exists(),
            "linked source must be untouched"
        );
        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn library_changes_roundtrip() {
        let n = TMP_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let mut data_dir = std::env::temp_dir();
        data_dir.push(format!("psc-data-lc-{}-{n}", std::process::id()));
        std::fs::create_dir_all(data_dir.join("temp")).unwrap();
        let d = data_dir.to_string_lossy().to_string();

        let c = LibraryChanges {
            update: vec!["7z".into(), "docker".into()],
            added: vec!["new-tool".into()],
            removed: vec!["old-tool".into()],
            renamed: vec![("git".into(), "git1".into())],
            module: Some("7.2.0".into()),
        };
        c.save(&d);

        let loaded = LibraryChanges::load(&d);
        assert_eq!(loaded.update, vec!["7z", "docker"]);
        assert_eq!(loaded.added, vec!["new-tool"]);
        assert_eq!(loaded.removed, vec!["old-tool"]);
        assert_eq!(loaded.renamed, vec![("git".into(), "git1".into())]);
        assert_eq!(loaded.module.as_deref(), Some("7.2.0"));

        // Missing file yields empty defaults.
        std::fs::remove_file(data_dir.join("temp/change.json")).ok();
        let empty = LibraryChanges::load(&d);
        assert!(empty.update.is_empty() && empty.renamed.is_empty() && empty.module.is_none());
        std::fs::remove_dir_all(&data_dir).ok();
    }
}
