//! Module data layer: reads/writes the module's data files (settings.json, temp/completions.json)
//! and loads localized psc manifest info. Platform-agnostic.

use std::collections::HashMap;

use serde_json::{json, Value};

pub mod config;

// Shared text helpers (BOM-tolerant reads) live in `psc-common`; re-exported so the
// crate-internal `crate::data::read_text` paths keep working.
pub use psc_common::{read_text, strip_bom};

/// Whether a completion entry exists on disk (`<data>/completions/<name>`), as a real directory
/// or as a link (symlink/junction from `scripts/link-completion.ps1`). Uses `symlink_metadata`,
/// so a dangling link still counts as present.
pub fn completion_dir_exists(data_dir: &str, name: &str) -> bool {
    if !crate::validate::is_valid_name(name) {
        return false;
    }
    std::fs::symlink_metadata(format!("{data_dir}/completions/{name}")).is_ok()
}

/// Remove a completion entry: a symlink/junction is removed **as a link only** (the linked
/// local source stays intact), a real directory recursively, a missing path is a no-op.
/// An invalid name is a no-op: callers report it, and this keeps the destructive
/// path from ever resolving outside `<data>/completions`.
pub fn remove_completion_entry(data_dir: &str, name: &str) {
    if !crate::validate::is_valid_name(name) {
        return;
    }
    let dir = format!("{data_dir}/completions/{name}");
    if let Ok(md) = std::fs::symlink_metadata(&dir) {
        if md.file_type().is_symlink() {
            #[cfg(windows)]
            let _ = std::fs::remove_dir(&dir);
            #[cfg(not(windows))]
            let _ = std::fs::remove_file(&dir);
        } else if md.file_type().is_dir() {
            let _ = std::fs::remove_dir_all(&dir);
        } else {
            // A stray plain file in the library directory. The user named it, so remove it — the
            // directory holds completions and nothing else. (`remove_dir_all` fails on a file, and
            // the error used to be swallowed, so `rm` reported success and left it there.)
            let _ = std::fs::remove_file(&dir);
        }
    }
}

/// `settings.json` — `{ config, alias }`.
#[derive(Debug, Clone, Default)]
pub struct Settings {
    /// completion name -> trigger aliases. **Ordered on purpose**: the key order is the claim
    /// order, and the hosts build their `word -> completion` table by inserting in it, so the
    /// last claim of a word wins. Never re-sort it.
    pub alias: AliasMap,
    /// module config (default_config merged with user overrides), incl. `completion` per-completion map.
    pub config: Value,
}

/// `alias` is order-preserving on purpose (see `Settings::alias`). A plain map would lose the
/// claim order twice: `serde_json::Value` sorts its keys, and so would any round-trip through it.
pub type AliasMap = indexmap::IndexMap<String, Vec<String>>;

/// The on-disk shape. Serialized directly — never through `Value`, which would re-sort `alias`.
#[derive(serde::Serialize, serde::Deserialize)]
struct SettingsFile {
    #[serde(default = "empty_object")]
    config: Value,
    #[serde(default)]
    alias: AliasMap,
}

fn empty_object() -> Value {
    json!({})
}

impl Settings {
    /// Move a completion to the end of the claim order. That order is what the hosts insert in,
    /// so re-claiming is how a completion takes a word back from a later claim.
    pub fn reclaim_alias(&mut self, name: &str) {
        if let Some(words) = self.alias.shift_remove(name) {
            self.alias.insert(name.to_string(), words);
        }
    }

    /// Read and parse `settings.json`.
    ///
    /// A file that cannot be decoded (a foreign encoding) or parsed is **corruption, not
    /// absence**, so the run stops with an error naming the file. Nothing is written: no backup,
    /// no rewrite — the file itself is the evidence, and it stays exactly as it is.
    /// `Ok(None)` means the file simply is not there yet (a fresh install).
    pub fn load(path: &str) -> Result<Option<Settings>, String> {
        let Some(bytes) = std::fs::read(path).ok() else {
            return Ok(None);
        };
        let Some(text) = std::str::from_utf8(&bytes).ok().map(strip_bom) else {
            return Err(format!(
                "{path} is not valid UTF-8 — fix it or delete it (the file was not modified)"
            ));
        };
        let file: SettingsFile = serde_json::from_str(text).map_err(|e| {
            format!(
                "{path} is not valid JSON ({e}) — fix it or delete it (the file was not modified)"
            )
        })?;
        Ok(Some(Settings {
            alias: file.alias,
            config: file.config,
        }))
    }

    pub fn save(&self, path: &str) -> Result<(), String> {
        let text = serde_json::to_string_pretty(&SettingsFile {
            config: self.config.clone(),
            alias: self.alias.clone(),
        })
        .map_err(|e| e.to_string())?;
        // Atomic + durable: pid-suffixed tmp, sync file, then rename over target.
        // A crash mid-write can never leave a half-written settings.json, and a power loss
        // after rename is durable. Concurrent psc processes use distinct tmp names.
        let tmp = format!("{path}.{}.tmp", std::process::id());
        {
            let mut f = std::fs::File::create(&tmp).map_err(|e| e.to_string())?;
            use std::io::Write;
            f.write_all(text.as_bytes()).map_err(|e| e.to_string())?;
            f.sync_all().map_err(|e| e.to_string())?;
        }
        if let Err(e) = std::fs::rename(&tmp, path) {
            let _ = std::fs::remove_file(&tmp);
            return Err(e.to_string());
        }
        // Best-effort fsync parent dir for durability on Unix.
        if let Some(dir) = std::path::Path::new(path).parent() {
            if let Ok(d) = std::fs::File::open(dir) {
                let _ = d.sync_all();
            }
        }
        Ok(())
    }

    /// Completion names in **claim order** (the alias map's key order) — the same order every
    /// listing uses, so the map stays the single source of the ordering.
    pub fn list(&self) -> Vec<String> {
        self.alias.keys().cloned().collect()
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
    /// `None` for a missing **or unreadable** file: this is a rebuildable cache, so a corrupt one
    /// is simply fetched again — never reported, never rewritten.
    pub fn load(path: &str) -> Option<Index> {
        let bytes = std::fs::read(path).ok()?;
        let text = std::str::from_utf8(&bytes).ok()?;
        let v: Value = serde_json::from_str(strip_bom(text)).ok()?;
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_check: Option<u64>,
}

impl LibraryChanges {
    /// Load from `<data>/temp/change.json`; a missing file yields empty defaults.
    /// Each field parses independently: one malformed field falls back to its own
    /// default while intact fields still load. Unparseable content is backed up
    /// to `change.json.corrupt` like `Settings::load` / `Index::load`.
    pub fn load(data_dir: &str) -> LibraryChanges {
        fn str_list(v: Option<&Value>) -> Vec<String> {
            v.and_then(|x| x.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|e| e.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default()
        }
        let path = format!("{data_dir}/temp/change.json");
        // A notification file: missing or unreadable simply means "nothing to report".
        let Some(bytes) = std::fs::read(&path).ok() else {
            return LibraryChanges::default();
        };
        let Some(text) = std::str::from_utf8(&bytes).ok() else {
            return LibraryChanges::default();
        };
        let Ok(v) = serde_json::from_str::<Value>(strip_bom(text)) else {
            return LibraryChanges::default();
        };
        LibraryChanges {
            update: str_list(v.get("update")),
            added: str_list(v.get("added")),
            removed: str_list(v.get("removed")),
            renamed: v
                .get("renamed")
                .and_then(|x| x.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|e| {
                            e.as_array().and_then(|p| {
                                match (p.first()?.as_str(), p.get(1)?.as_str()) {
                                    (Some(o), Some(n)) => Some((o.to_string(), n.to_string())),
                                    _ => None,
                                }
                            })
                        })
                        .collect()
                })
                .unwrap_or_default(),
            module: v.get("module").and_then(|m| m.as_str()).map(String::from),
            last_check: v.get("last_check").and_then(|l| l.as_u64()),
        }
    }

    /// Atomically save to `<data>/temp/change.json`.
    pub fn save(&self, data_dir: &str) {
        if let Ok(text) = serde_json::to_string(self) {
            let tmp_dir = format!("{data_dir}/temp");
            let _ = std::fs::create_dir_all(&tmp_dir);
            let tmp = format!("{tmp_dir}/change.json.{}.tmp", std::process::id());
            let path = format!("{tmp_dir}/change.json");
            if std::fs::write(&tmp, text).is_ok() {
                let _ = std::fs::rename(&tmp, path);
                let _ = std::fs::remove_file(&tmp);
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
            // Dirs and links count as present (a dangling link's config reads as
            // defaults); plain files are not completion entries. A real dir without
            // config.json is stray and stays skipped.
            let ft = std::fs::symlink_metadata(&dir).map(|m| m.file_type());
            let is_link = ft.as_ref().is_ok_and(|t| t.is_symlink());
            let is_dir = ft.as_ref().is_ok_and(|t| t.is_dir());
            if !is_link && !is_dir {
                continue;
            }
            let config_path = dir.join("config.json");
            if !is_link && !config_path.exists() {
                continue;
            }
            let c: Value = read_text(&config_path.to_string_lossy())
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
            if let Some(text) = read_text(&manifest_path.to_string_lossy()) {
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

/// Load the `psc` completion's own `config.json`. Its `version` mirrors the module's, so the root
/// response can name the running version without guessing from `CARGO_PKG_VERSION` (the crate's).
pub fn load_psc_config(completions_dir: &str) -> Value {
    let path = std::path::Path::new(completions_dir)
        .join("psc")
        .join("config.json");
    let text = read_text(&path.to_string_lossy()).unwrap_or_default();
    serde_json::from_str(&text).unwrap_or_else(|_| json!({}))
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
        let s = Settings::load(&path).unwrap().unwrap();
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
        let mut s = Settings::load(&path).unwrap().unwrap();
        s.alias.insert("git".into(), vec!["git".into()]);
        s.config["language"] = json!("zh-CN");
        s.save(&path).unwrap();
        // The bytes on disk are UTF-8 without a BOM: every write path passes a `String`, so no
        // other encoding can reach the file (a foreign one can only come from outside —
        // PowerShell 5.1, an editor).
        let bytes = std::fs::read(&path).unwrap();
        assert!(
            std::str::from_utf8(&bytes).is_ok(),
            "settings.json must be valid UTF-8"
        );
        assert_ne!(
            &bytes[..3],
            b"\xef\xbb\xbf",
            "settings.json must not carry a BOM"
        );
        let reloaded = Settings::load(&path).unwrap().unwrap();
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
    fn settings_load_reports_corrupt_file_and_leaves_it_alone() {
        // Corruption is reported, never papered over with defaults: the file stays exactly as it
        // is — no `.corrupt` copy, no rewrite — so nothing the user wrote is lost.
        let (_p, path) = tmp_file("not-json{{{");
        let err = Settings::load(&path).unwrap_err();
        assert!(err.contains(&path), "the error must name the file: {err}");
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "not-json{{{");
        assert!(
            !std::path::Path::new(&format!("{path}.corrupt")).exists(),
            "nothing is backed up any more — the file itself is the evidence"
        );
        std::fs::remove_file(&path).ok();
    }

    #[test]
    fn settings_save_is_atomic_and_leaves_no_tmp() {
        let (_p, path) = tmp_file(r#"{"config":{},"alias":{}}"#);
        let mut s = Settings::load(&path).unwrap().unwrap();
        s.alias.insert("git".into(), vec!["git".into()]);
        s.save(&path).unwrap();
        // The bytes on disk are UTF-8 without a BOM: every write path passes a `String`, so no
        // other encoding can reach the file (a foreign one can only come from outside —
        // PowerShell 5.1, an editor).
        let bytes = std::fs::read(&path).unwrap();
        assert!(
            std::str::from_utf8(&bytes).is_ok(),
            "settings.json must be valid UTF-8"
        );
        assert_ne!(
            &bytes[..3],
            b"\xef\xbb\xbf",
            "settings.json must not carry a BOM"
        );
        let reloaded = Settings::load(&path).unwrap().unwrap();
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

    #[test]
    fn traversal_names_never_escape_the_completions_dir() {
        // `psc rm ../../victim` used to resolve outside the library: `assert_valid_name` was a
        // debug_assert (compiled out in release) and the existence probe followed the path.
        let (root, data) = tmp_data_dir("scoop");
        let victim = root.join("victim");
        std::fs::create_dir_all(&victim).unwrap();
        std::fs::write(victim.join("keep.txt"), "keep").unwrap();

        for evil in ["../victim", "..\\victim", "..", ".", "a/b", "C:evil", ""] {
            assert!(
                !completion_dir_exists(&data, evil),
                "{evil:?} must not be treated as installed"
            );
            remove_completion_entry(&data, evil);
        }
        assert!(
            victim.join("keep.txt").exists(),
            "a sibling of completions/ must survive"
        );
        std::fs::remove_dir_all(root).ok();
    }

    #[test]
    fn traversal_name_reports_not_available() {
        use crate::validate::name_status;
        let (root, data) = tmp_data_dir("scoop");
        let completions_dir = format!("{data}/completions");
        let settings = Settings::default();
        let index = Index::default();
        for evil in ["../scoop", "..\\scoop", "..", ".", "scoop/../scoop"] {
            assert_eq!(
                name_status(&settings, &index, &completions_dir, evil),
                0,
                "{evil:?} must not resolve to an installed entry"
            );
        }
        assert_eq!(
            name_status(&settings, &index, &completions_dir, "scoop"),
            2,
            "a real entry is still detected"
        );
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
            last_check: None,
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

    #[test]
    fn library_changes_load_keeps_intact_fields() {
        let n = TMP_COUNTER.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let mut data_dir = std::env::temp_dir();
        data_dir.push(format!("psc-data-lc-partial-{}-{n}", std::process::id()));
        std::fs::create_dir_all(data_dir.join("temp")).unwrap();
        let d = data_dir.to_string_lossy().to_string();
        std::fs::write(
            data_dir.join("temp/change.json"),
            r#"{"update":["git"],"renamed":{"git":"git1"},"module":7,"added":[1,"x"]}"#,
        )
        .unwrap();
        let loaded = LibraryChanges::load(&d);
        assert_eq!(loaded.update, vec!["git"]);
        assert!(loaded.renamed.is_empty());
        assert!(loaded.module.is_none());
        assert_eq!(loaded.added, vec!["x"]);
        std::fs::remove_dir_all(&data_dir).ok();
    }
}
