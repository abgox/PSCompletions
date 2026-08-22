//! Network layer for the `psc` CLI (P2): download completions.json / completion files via reqwest.

use std::sync::OnceLock;
use std::time::Duration;

use serde_json::Value;

use crate::data::Settings;

/// Default completion source URLs (order follows the module's language preference).
const GITEE: &str = "https://gitee.com/abgox/PSCompletions/raw/main";
const GITHUB: &str = "https://github.com/abgox/PSCompletions/raw/main";
const GH_PAGES: &str = "https://abgox.github.io/PSCompletions";

/// Source URLs: `config.url` if set, else defaults (zh prefers gitee first).
pub fn resolve_urls(settings: &Settings) -> Vec<String> {
    if let Some(u) = settings.config.get("url").and_then(|v| v.as_str()) {
        let u = u.trim();
        if !u.is_empty() {
            return vec![u.to_string()];
        }
    }
    if settings.language().starts_with("zh") {
        vec![GITEE.into(), GITHUB.into(), GH_PAGES.into()]
    } else {
        vec![GITHUB.into(), GITEE.into(), GH_PAGES.into()]
    }
}

/// Shared blocking HTTP client: built once, reused across requests and threads
/// (reqwest's blocking Client is Send + Sync and keeps a connection pool).
fn http_client() -> &'static reqwest::blocking::Client {
    static CLIENT: OnceLock<reqwest::blocking::Client> = OnceLock::new();
    CLIENT.get_or_init(|| {
        reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("build http client")
    })
}

/// Fetch `path` under the first URL that succeeds (reuses the shared client).
pub fn fetch_text(urls: &[String], path: &str) -> Result<String, String> {
    let client = http_client();
    let mut last_err = String::new();
    for u in urls {
        let url = format!("{}/{}", u.trim_end_matches('/'), path);
        // Retry once on transient connect/timeout failures (a single-threaded local server
        // can drop a burst of connections under concurrency); other errors are final.
        for attempt in 0..2 {
            match client
                .get(&url)
                .send()
                .and_then(|r| r.error_for_status())
                .and_then(|r| r.text())
            {
                Ok(t) => return Ok(t),
                Err(e) => {
                    let transient = e.is_connect()
                        || e.is_timeout()
                        || e.status()
                            .is_some_and(|s| s.as_u16() == 429 || s.is_server_error());
                    last_err = e.to_string();
                    if !transient || attempt == 1 {
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(200));
                }
            }
        }
    }
    Err(last_err)
}

/// Shape check for a downloaded `completions.json`: the remote must have served an actual
/// index (`{ update, meta }`), not a redirect page or error body that happens to parse as JSON.
/// Without this, `psc add <name>` would report a misleading "not an available completion".
pub fn validate_index_shape(v: &Value) -> Result<(), String> {
    if v.get("update").and_then(|u| u.as_object()).is_none() {
        return Err("bad completions.json: missing `update` object".into());
    }
    if v.get("meta").and_then(|m| m.as_object()).is_none() {
        return Err("bad completions.json: missing `meta` object".into());
    }
    Ok(())
}

/// Download `completions.json`, write it to `<data>/temp/completions.json`, return the parsed value.
pub fn download_list(data_dir: &str, urls: &[String]) -> Result<Value, String> {
    let text = fetch_text(urls, "completions.json")?;
    let v: Value = serde_json::from_str(&text).map_err(|e| format!("bad completions.json: {e}"))?;
    validate_index_shape(&v)?;
    let tmp = format!("{data_dir}/temp");
    std::fs::create_dir_all(&tmp).map_err(|e| e.to_string())?;
    // Atomic replace (same scheme as settings.json): never leave a half-written index file.
    let path = format!("{tmp}/completions.json");
    let tmp_path = format!("{path}.{}.tmp", std::process::id());
    std::fs::write(&tmp_path, text).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp_path, path).map_err(|e| e.to_string())?;
    Ok(v)
}

/// Download a completion's files (config.json first, then language/*.json + hooks.lua in
/// parallel) and write `.update`. Files are staged in `<data>/temp/<name>.tmp` and moved
/// into place only on full success, so a failed download never removes an already-installed
/// version (`.tmp`/`.old` residue from an interrupted run is cleaned on the next call).
pub fn add_completion(
    data_dir: &str,
    name: &str,
    urls: &[String],
    version: &str,
) -> Result<bool, String> {
    let dir = format!("{data_dir}/completions/{name}");
    // Skip linked (symlink) completions: Ok(false) = "skipped, not updated".
    if let Ok(meta) = std::fs::symlink_metadata(&dir) {
        if meta.file_type().is_symlink() {
            return Ok(false);
        }
    }
    // Stage under `<data>/temp` (same volume as `completions/`, so rename is atomic);
    // a stale staging/backup dir from an interrupted run is dropped first.
    let tmp_dir = format!("{data_dir}/temp/{name}.tmp");
    let _ = std::fs::remove_dir_all(&tmp_dir);
    let old_dir = format!("{dir}.old");
    let _ = std::fs::remove_dir_all(&old_dir);
    let result = (|| -> Result<bool, String> {
        let language_dir = format!("{tmp_dir}/language");
        std::fs::create_dir_all(&language_dir).map_err(|e| e.to_string())?;
        let config_text = fetch_text(urls, &format!("completions/{name}/config.json"))?;
        let config: Value =
            serde_json::from_str(&config_text).map_err(|e| format!("bad config.json: {e}"))?;
        std::fs::write(format!("{tmp_dir}/config.json"), &config_text)
            .map_err(|e| e.to_string())?;

        // (url_path, local_path, is_hooks)
        let mut jobs: Vec<(String, String, bool)> = Vec::new();
        if let Some(langs) = config.get("language").and_then(|l| l.as_array()) {
            for lang in langs {
                if let Some(l) = lang.as_str() {
                    jobs.push((
                        format!("completions/{name}/language/{l}.json"),
                        format!("{language_dir}/{l}.json"),
                        false,
                    ));
                }
            }
        }
        if config.get("hooks").is_some() {
            jobs.push((
                format!("completions/{name}/hooks.lua"),
                format!("{tmp_dir}/hooks.lua"),
                true,
            ));
        }

        let results: Vec<Result<String, String>> = std::thread::scope(|s| {
            let urls = &urls;
            let jobs = &jobs;
            let mut out: Vec<Option<Result<String, String>>> = vec![None; jobs.len()];
            let handles: Vec<_> = jobs
                .iter()
                .enumerate()
                .map(|(i, (url_path, _, _))| s.spawn(move || (i, fetch_text(urls, url_path))))
                .collect();
            for h in handles {
                if let Ok((i, r)) = h.join() {
                    out[i] = Some(r);
                }
                // Err: slot stays None → Err below
            }
            out.into_iter()
                .map(|o| {
                    o.unwrap_or(Err(
                        "thread panic while fetching completion file".to_string()
                    ))
                })
                .collect()
        });

        for (i, r) in results.iter().enumerate() {
            match r {
                Ok(text) => std::fs::write(&jobs[i].1, text).map_err(|e| e.to_string())?,
                Err(e) => {
                    // hooks.lua may be missing remotely (not yet synced): degrade to static
                    // completions; the next update fills it in.
                    if !jobs[i].2 {
                        return Err(e.to_string());
                    }
                }
            }
        }

        std::fs::write(format!("{tmp_dir}/.update"), version).map_err(|e| e.to_string())?;
        commit_staged(&dir, &tmp_dir, &old_dir)?;
        Ok(true)
    })();
    // Never touch the installed `dir` on failure: `add` leaves nothing behind (the staging
    // dir is removed), `update` keeps the previous version intact.
    if result.is_err() {
        let _ = std::fs::remove_dir_all(&tmp_dir);
    }
    result
}

/// Move a fully-downloaded staging dir into place. An existing `dir` is renamed aside
/// first and restored if the final rename fails, so a failure mid-commit never leaves
/// the completion missing.
fn commit_staged(dir: &str, tmp_dir: &str, old_dir: &str) -> Result<(), String> {
    if std::fs::symlink_metadata(dir).is_err() {
        return std::fs::rename(tmp_dir, dir).map_err(|e| e.to_string());
    }
    std::fs::rename(dir, old_dir).map_err(|e| e.to_string())?;
    if let Err(e) = std::fs::rename(tmp_dir, dir) {
        // Restore the previous version; a failed restore leaves `old_dir` for manual recovery.
        let _ = std::fs::rename(old_dir, dir);
        return Err(format!("{e}"));
    }
    let _ = std::fs::remove_dir_all(old_dir);
    Ok(())
}

/// Manifest-derived per-completion config defaults (the manifest `config` items).
pub fn completion_defaults(data_dir: &str, name: &str) -> Value {
    let mut map = serde_json::Map::new();
    let config_path = format!("{data_dir}/completions/{name}/config.json");
    if let Some(text) = crate::data::read_text(&config_path) {
        if let Ok(config) = serde_json::from_str::<Value>(&text) {
            let lang = config
                .get("language")
                .and_then(|l| l.as_array())
                .and_then(|a| a.first())
                .and_then(|v| v.as_str())
                .unwrap_or("en-US");
            let manifest_path = format!("{data_dir}/completions/{name}/language/{lang}.json");
            if let Some(text) = crate::data::read_text(&manifest_path) {
                if let Ok(manifest) = serde_json::from_str::<Value>(&text) {
                    if let Some(items) = manifest.get("config").and_then(|x| x.as_array()) {
                        for item in items {
                            if let (Some(k), Some(v)) =
                                (item.get("name").and_then(|x| x.as_str()), item.get("value"))
                            {
                                map.insert(k.to_string(), v.clone());
                            }
                        }
                    }
                }
            }
        }
    }
    Value::Object(map)
}

/// After adding/updating a completion, refresh its alias + config defaults, preserving user overrides.
pub fn refresh_settings_after_add(
    settings: &mut Settings,
    data_dir: &str,
    name: &str,
) -> Result<(), String> {
    let config_path = format!("{data_dir}/completions/{name}/config.json");
    let text =
        crate::data::read_text(&config_path).ok_or_else(|| "missing config.json".to_string())?;
    let config: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    // Whether this completion already had per-completion settings before the manifest
    // defaults below may create it (first install vs update).
    let first_install = settings
        .config
        .get("completion")
        .and_then(|c| c.get(name))
        .is_none();
    let hooks_disabled = config.get("hooks").and_then(|h| h.as_bool()) == Some(false);

    let aliases: Vec<String> = config
        .get("alias")
        .and_then(|a| a.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|x| x.as_str().map(String::from))
                .collect()
        })
        .filter(|a: &Vec<String>| !a.is_empty())
        .unwrap_or_else(|| vec![name.to_string()]);
    settings.alias.insert(name.to_string(), aliases);

    // Per-completion config defaults from the first language manifest's `config` field.
    let lang = config
        .get("language")
        .and_then(|l| l.as_array())
        .and_then(|a| a.first())
        .and_then(|v| v.as_str())
        .unwrap_or("en-US");
    let manifest_path = format!("{data_dir}/completions/{name}/language/{lang}.json");
    if let Some(text) = crate::data::read_text(&manifest_path) {
        if let Ok(manifest) = serde_json::from_str::<Value>(&text) {
            let defaults = manifest
                .get("config")
                .cloned()
                .unwrap_or_else(|| serde_json::json!([]));
            if let Some(items) = defaults.as_array() {
                let mut map = serde_json::Map::new();
                for item in items {
                    if let Some(k) = item.get("name").and_then(|v| v.as_str()) {
                        if let Some(v) = item.get("value") {
                            map.insert(k.to_string(), v.clone());
                        }
                    }
                }
                if !map.is_empty() {
                    if !settings.config.is_object() {
                        settings.config = serde_json::json!({});
                    }
                    let obj = settings.config.as_object_mut().unwrap();
                    let comp = obj
                        .entry("completion")
                        .or_insert_with(|| serde_json::json!({}));
                    let c = comp.as_object_mut().unwrap();
                    let n = c
                        .entry(name.to_string())
                        .or_insert_with(|| serde_json::json!({}));
                    let existing = n.as_object_mut().unwrap();
                    for (k, v) in map {
                        if !existing.contains_key(&k) {
                            existing.insert(k, v);
                        }
                    }
                }
            }
        }
    }
    // `hooks: false` in config.json declares "dynamic hooks exist but are disabled by
    // default": seed enable_hooks=0 on first install so they don't run until the user
    // opts in (`psc completion <name> enable_hooks 1`). Updates never touch an entry.
    if first_install && hooks_disabled {
        if !settings.config.is_object() {
            settings.config = serde_json::json!({});
        }
        let obj = settings.config.as_object_mut().unwrap();
        let comp = obj
            .entry("completion")
            .or_insert_with(|| serde_json::json!({}));
        let c = comp.as_object_mut().unwrap();
        let n = c
            .entry(name.to_string())
            .or_insert_with(|| serde_json::json!({}));
        n.as_object_mut()
            .unwrap()
            .insert("enable_hooks".to_string(), serde_json::json!(false));
    }
    Ok(())
}

/// Read a locally installed completion's stable id from its config.json.
pub fn local_completion_id(data_dir: &str, name: &str) -> Option<String> {
    let config_path = format!("{data_dir}/completions/{name}/config.json");
    let text = crate::data::read_text(&config_path)?;
    let v: Value = serde_json::from_str(&text).ok()?;
    v.get("id").and_then(|i| i.as_str()).map(String::from)
}

/// Migrate an installed completion `old` to its renamed remote name `new`
pub fn rename_completion(
    settings: &mut Settings,
    data_dir: &str,
    old: &str,
    new: &str,
    urls: &[String],
    version: &str,
) -> Result<(), String> {
    // Download the new completion first (aborts on failure, old stays intact).
    add_completion(data_dir, new, urls, version)?;
    // Move per-completion settings: alias + config.completion entry
    // (including enable_hooks). Do NOT call refresh_settings_after_add here —
    // it would overwrite the migrated user aliases with the new manifest's defaults.
    if let Some(aliases) = settings.alias.remove(old) {
        settings.alias.insert(new.to_string(), aliases);
    }
    if let Some(comp) = settings
        .config
        .get_mut("completion")
        .and_then(|c| c.as_object_mut())
    {
        if let Some(v) = comp.remove(old) {
            comp.insert(new.to_string(), v);
        }
    }
    // Remove the old directory.
    let old_dir = format!("{data_dir}/completions/{old}");
    let _ = std::fs::remove_dir_all(&old_dir);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_index_shape_accepts_real_index() {
        let v = serde_json::json!({
            "update": { "git": "abc123" },
            "meta": { "git": { "en-US": { "url": "https://git-scm.com", "description": "VCS" } } }
        });
        assert!(validate_index_shape(&v).is_ok());
    }

    #[test]
    fn validate_index_shape_rejects_non_index_json() {
        // A GitHub 404 body / redirect page that parses as JSON must be rejected, not
        // silently turned into an empty `update` map (misleading "not available" errors).
        assert!(validate_index_shape(&serde_json::json!({ "message": "Not Found" })).is_err());
        assert!(validate_index_shape(&serde_json::json!([])).is_err());
        assert!(validate_index_shape(&serde_json::json!({ "update": [], "meta": {} })).is_err());
        assert!(validate_index_shape(&serde_json::json!({ "update": {}, "meta": [] })).is_err());
    }

    #[test]
    fn resolve_urls_uses_config_url() {
        let mut s = Settings::default();
        s.config["url"] = serde_json::json!("https://example.com/raw");
        let urls = resolve_urls(&s);
        assert_eq!(urls, vec!["https://example.com/raw"]);
    }

    #[test]
    fn resolve_urls_prefers_language_order() {
        let s = Settings::default();
        let urls = resolve_urls(&s);
        assert_eq!(urls.len(), 3);
        assert!(urls[0].contains("github.com") || urls[0].contains("gitee.com"));
    }

    // Each test gets a unique dir: Rust runs tests in parallel, so sharing one path
    // would let one test's cleanup clobber another's fixtures.
    fn test_base() -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        std::env::temp_dir().join(format!(
            "psc-net-test-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ))
    }

    #[test]
    fn commit_staged_installs_when_dir_absent() {
        let base = test_base();
        let dir = base.join("completions/x");
        let tmp = base.join("temp/x.tmp");
        let old = base.join("completions/x.old");
        std::fs::create_dir_all(&tmp).unwrap();
        std::fs::create_dir_all(base.join("completions")).unwrap(); // rename target parent
        std::fs::write(tmp.join("config.json"), "{}").unwrap();
        commit_staged(
            dir.to_str().unwrap(),
            tmp.to_str().unwrap(),
            old.to_str().unwrap(),
        )
        .unwrap();
        assert!(dir.join("config.json").exists());
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn commit_staged_replaces_existing_dir() {
        let base = test_base();
        let dir = base.join("completions/x");
        let tmp = base.join("temp/x.tmp");
        let old = base.join("completions/x.old");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("old.txt"), "old").unwrap();
        std::fs::create_dir_all(&tmp).unwrap();
        std::fs::write(tmp.join("new.txt"), "new").unwrap();
        commit_staged(
            dir.to_str().unwrap(),
            tmp.to_str().unwrap(),
            old.to_str().unwrap(),
        )
        .unwrap();
        assert!(dir.join("new.txt").exists());
        assert!(!dir.join("old.txt").exists());
        assert!(!old.exists());
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn refresh_settings_after_add_seeds_enable_hooks_for_hooks_false() {
        let base = test_base();
        let dir = base.join("completions/x");
        std::fs::create_dir_all(dir.join("language")).unwrap();
        std::fs::write(
            dir.join("config.json"),
            r#"{"language":["en-US"],"hooks":false}"#,
        )
        .unwrap();
        std::fs::write(
            dir.join("language/en-US.json"),
            r#"{"meta":{"url":"","description":["x"]}}"#,
        )
        .unwrap();
        let mut s = Settings::default();
        // First install: `hooks: false` seeds enable_hooks=false (disabled by default).
        refresh_settings_after_add(&mut s, base.to_str().unwrap(), "x").unwrap();
        assert_eq!(s.config["completion"]["x"]["enable_hooks"], false);
        // Update: an existing entry is never rewritten (the user's opt-in survives).
        s.config["completion"]["x"]["enable_hooks"] = serde_json::json!(true);
        refresh_settings_after_add(&mut s, base.to_str().unwrap(), "x").unwrap();
        assert_eq!(s.config["completion"]["x"]["enable_hooks"], true);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn refresh_settings_after_add_skips_seed_for_hooks_true() {
        let base = test_base();
        let dir = base.join("completions/x");
        std::fs::create_dir_all(dir.join("language")).unwrap();
        std::fs::write(
            dir.join("config.json"),
            r#"{"language":["en-US"],"hooks":true}"#,
        )
        .unwrap();
        std::fs::write(
            dir.join("language/en-US.json"),
            r#"{"meta":{"url":"","description":["x"]}}"#,
        )
        .unwrap();
        let mut s = Settings::default();
        refresh_settings_after_add(&mut s, base.to_str().unwrap(), "x").unwrap();
        // `hooks: true` writes no enable_hooks entry (absence means enabled).
        assert!(s.config["completion"]["x"].get("enable_hooks").is_none());
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn commit_staged_rolls_back_when_final_rename_fails() {
        let base = test_base();
        let dir = base.join("completions/x");
        let tmp = base.join("temp/x.tmp"); // never created -> final rename fails
        let old = base.join("completions/x.old");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("old.txt"), "old").unwrap();
        let err = commit_staged(
            dir.to_str().unwrap(),
            tmp.to_str().unwrap(),
            old.to_str().unwrap(),
        );
        assert!(err.is_err());
        // The previous version survives and is restored in place.
        assert!(dir.join("old.txt").exists());
        assert!(!old.exists());
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn local_completion_id_reads_config_id() {
        let base = test_base();
        let dir = base.join("completions/x");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("config.json"),
            r#"{"language":["en-US"],"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"}"#,
        )
        .unwrap();
        let id = local_completion_id(base.to_str().unwrap(), "x");
        assert_eq!(id.as_deref(), Some("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"));
        // Missing id -> None.
        std::fs::write(dir.join("config.json"), r#"{"language":["en-US"]}"#).unwrap();
        assert!(local_completion_id(base.to_str().unwrap(), "x").is_none());
        // Missing config.json -> None.
        std::fs::remove_file(dir.join("config.json")).ok();
        assert!(local_completion_id(base.to_str().unwrap(), "x").is_none());
        std::fs::remove_dir_all(&base).ok();
    }
}
