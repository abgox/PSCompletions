//! Network layer for the `psc` CLI (P2): download completions.json / completion files via reqwest.

use std::sync::OnceLock;
use std::time::Duration;

use serde_json::Value;

use crate::data::{remove_completion_entry, Settings};
use crate::validate::is_valid_name;

/// Default completion source URLs (order follows the module's language preference).
const GITEE: &str = "https://gitee.com/abgox/PSCompletions/raw/main";
const GITHUB: &str = "https://github.com/abgox/PSCompletions/raw/main";
const GH_PAGES: &str = "https://abgox.github.io/PSCompletions";

/// Derive the index-branch variant of a content base: only raw-style bases
/// ending in the branch segment `main` qualify (`.../raw/main` ->
/// `.../raw/index`). Anything else (Pages roots, custom path prefixes,
/// bare hosts) has no known index layout and is tried as-is: guessing
/// `.../index` there wastes a request at best (GH_PAGES: a 404 before the
/// fallback heals it) and mangles the URL at worst.
fn index_branch_url(base: &str) -> Option<String> {
    let b = base.trim_end_matches('/');
    let (head, last) = b.rsplit_once('/')?;
    if !head.contains("://") {
        return None;
    }
    match last {
        "main" => Some(format!("{head}/index")),
        // Already on the index layout: resolves to itself (deduped downstream).
        "index" => Some(b.to_string()),
        _ => None,
    }
}

/// Index download bases: the index-branch layout first, then today's layout.
/// New servers answer the first; legacy/custom mirrors serving the old layout
/// answer the second. Deduped, so a base already on the index layout is tried once.
pub fn resolve_index_urls(settings: &Settings) -> Vec<String> {
    let bases = resolve_urls(settings);
    let mut out = Vec::new();
    for b in &bases {
        if let Some(d) = index_branch_url(b) {
            if !out.contains(&d) {
                out.push(d);
            }
        }
    }
    for b in &bases {
        if !out.contains(b) {
            out.push(b.clone());
        }
    }
    out
}

/// Official `config.url` candidates from the installed psc manifest
/// (`config core url` value list): the manifest is the user-facing source of truth.
/// Falls back to the static default bases when the manifest is unreadable.
/// Names are stored quoted in the manifest; comparison strips one quote pair.
pub fn official_sources(data_dir: &str, language: &str) -> Vec<String> {
    fn child<'a>(node: &'a Value, name: &str) -> Option<&'a Value> {
        node.get("next")?
            .as_array()?
            .iter()
            .find(|n| n.get("name").and_then(|x| x.as_str()) == Some(name))
    }
    let mut out = vec![GITEE.to_string(), GITHUB.to_string(), GH_PAGES.to_string()];
    let lang_file = if language.starts_with("zh") {
        "zh-CN"
    } else {
        "en-US"
    };
    let path = format!("{data_dir}/completions/psc/language/{lang_file}.json");
    if let Some(text) = crate::data::read_text(&path) {
        if let Ok(manifest) = serde_json::from_str::<Value>(&text) {
            let root = Value::Object({
                let mut m = serde_json::Map::new();
                m.insert(
                    "next".into(),
                    manifest.get("next").cloned().unwrap_or(Value::Null),
                );
                m
            });
            if let Some(urls) = child(&root, "config")
                .and_then(|n| child(n, "core"))
                .and_then(|n| child(n, "url"))
                .and_then(|n| n.get("next"))
                .and_then(|n| n.as_array())
            {
                for v in urls {
                    if let Some(name) = v.get("name").and_then(|n| n.as_str()) {
                        let u = name.trim().trim_matches('"').trim_end_matches('/');
                        if !u.is_empty() && !out.iter().any(|o| o == u) {
                            out.push(u.to_string());
                        }
                    }
                }
            }
        }
    }
    out
}

/// Whether a `config.url` value is an official source: empty (auto) or listed in
/// the psc manifest candidates / static default bases. Anything else is unreviewed.
pub fn is_official_source(data_dir: &str, language: &str, url: &str) -> bool {
    let u = url.trim();
    u.is_empty()
        || official_sources(data_dir, language)
            .iter()
            .any(|o| o == u.trim_end_matches('/'))
}

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

/// Crash residue from staged downloads: pid-suffixed temp files/dirs
/// (`temp/<name>.<pid>.tmp`, incl. `completions.json.<pid>.tmp`) and aside-renamed
/// dirs (`completions/<name>.<pid>.old`). A killed process never cleans its own.
/// Entries older than a day are dead by definition (an active staging lives
/// minutes); anything younger — including a concurrent `psc` mid-download, whose
/// names differ by pid anyway — is left alone.
pub fn cleanup_stale_staging(data_dir: &str) {
    cleanup_stale_staging_with_age(data_dir, Duration::from_secs(24 * 60 * 60));
}

fn cleanup_stale_staging_with_age(data_dir: &str, max_age: Duration) {
    let old_enough = |path: &std::path::Path| {
        std::fs::metadata(path)
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| std::time::SystemTime::now().duration_since(t).ok())
            .is_some_and(|d| d >= max_age)
    };
    // `<base>.<pid><ext>` with a numeric pid — nothing legitimate in these
    // directories looks like that.
    let pid_suffixed = |name: &str, ext: &str| {
        name.strip_suffix(ext)
            .and_then(|base| base.rsplit('.').next())
            .is_some_and(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
    };
    let sweep = |dir: &str, ext: &str| {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if !pid_suffixed(&name, ext) || !old_enough(&path) {
                continue;
            }
            if path.is_dir() {
                let _ = std::fs::remove_dir_all(&path);
            } else {
                let _ = std::fs::remove_file(&path);
            }
        }
    };
    sweep(&format!("{data_dir}/temp"), ".tmp");
    sweep(&format!("{data_dir}/completions"), ".old");
}

/// Shape check for a downloaded `completions.json`: the remote must have served an actual
/// index (`{ update, meta }`), not a redirect page or error body that happens to parse as JSON.
/// Without this, `psc add <name>` would report a misleading "not an available completion".
pub fn validate_index_shape(v: &Value) -> Result<(), String> {
    let update = v
        .get("update")
        .and_then(|u| u.as_object())
        .ok_or("bad completions.json: missing `update` object")?;
    if v.get("meta").and_then(|m| m.as_object()).is_none() {
        return Err("bad completions.json: missing `meta` object".into());
    }
    // Version markers drive update detection by string comparison; a non-string
    // value would be silently dropped downstream, disabling updates for that entry.
    if update.values().any(|val| val.as_str().is_none()) {
        return Err("bad completions.json: non-string `update` value".into());
    }
    Ok(())
}

/// Download `completions.json`, write it to `<data>/temp/completions.json`, return the parsed value.
/// Tries each candidate base in order; the first *valid* index wins. Validity
/// (fetch + parse + shape) decides, not mere HTTP success — an error page that
/// happens to parse as JSON must not shadow the real index on the next candidate.
pub fn download_list(data_dir: &str, urls: &[String]) -> Result<Value, String> {
    let mut last_err = String::from("no index sources");
    for base in urls {
        let attempt = match fetch_text(std::slice::from_ref(base), "completions.json") {
            Ok(t) => t,
            Err(e) => {
                last_err = format!("{base}: {e}");
                continue;
            }
        };
        let v: Value = match serde_json::from_str(&attempt) {
            Ok(v) => v,
            Err(e) => {
                last_err = format!("{base}: bad completions.json: {e}");
                continue;
            }
        };
        if let Err(e) = validate_index_shape(&v) {
            last_err = format!("{base}: {e}");
            continue;
        }
        let tmp = format!("{data_dir}/temp");
        std::fs::create_dir_all(&tmp).map_err(|e| e.to_string())?;
        // Atomic replace (same scheme as settings.json): never leave a half-written index file.
        let path = format!("{tmp}/completions.json");
        let tmp_path = format!("{path}.{}.tmp", std::process::id());
        std::fs::write(&tmp_path, attempt).map_err(|e| e.to_string())?;
        if let Err(e) = std::fs::rename(&tmp_path, path) {
            let _ = std::fs::remove_file(&tmp_path);
            return Err(e.to_string());
        }
        return Ok(v);
    }
    Err(last_err)
}

/// A downloaded config.json must carry a usable stable `id` (non-empty string):
/// without it the completion cannot participate in rename detection or settings
/// sync, so the download is refused before any further files are fetched.
fn validate_config_id(config: &Value) -> Result<(), String> {
    let ok = config
        .get("id")
        .and_then(|i| i.as_str())
        .is_some_and(|s| !s.trim().is_empty());
    if ok {
        Ok(())
    } else {
        Err("bad config.json (missing stable `id`)".to_string())
    }
}

/// Download a completion's files (config.json first, then language/*.json + hooks.lua in
/// parallel) and write `.update`. Files are staged in `<data>/temp/<name>.<pid>.tmp` and moved
/// into place only on full success, so a failed download never removes an already-installed
/// version. The pid suffix keeps two concurrent processes operating on the same completion
/// from interleaving writes into one shared staging dir.
pub fn add_completion(
    data_dir: &str,
    name: &str,
    urls: &[String],
    version: &str,
) -> Result<bool, String> {
    // The single place a completion lands on disk: reject a name carrying separators before
    // anything is created or removed, so no caller can escape the library directory
    // (design/psc-cli.md §6.7 — validated before any filesystem access).
    if !is_valid_name(name) {
        return Err(format!("invalid completion name: {name}"));
    }
    let dir = format!("{data_dir}/completions/{name}");
    // Skip linked (symlink) completions: Ok(false) = "skipped, not updated".
    if let Ok(meta) = std::fs::symlink_metadata(&dir) {
        if meta.file_type().is_symlink() {
            return Ok(false);
        }
    }
    // The completions root may not exist (a wiped data dir): create it so the staged
    // commit can rename into place — otherwise add/init's restore would fail here.
    let _ = std::fs::create_dir_all(format!("{data_dir}/completions"));
    // Stage under `<data>/temp` (same volume as `completions/`, so rename is atomic).
    let tmp_dir = format!("{data_dir}/temp/{name}.{}.tmp", std::process::id());
    let old_dir = format!("{dir}.{}.old", std::process::id());
    let _ = std::fs::remove_dir_all(&tmp_dir);
    let _ = std::fs::remove_dir_all(&old_dir);
    // Legacy fixed-name residue from pre-pid-suffix versions is cleaned opportunistically;
    // a crashed run's pid-suffixed dirs stay behind (same policy as settings.json's tmp).
    let _ = std::fs::remove_dir_all(format!("{data_dir}/temp/{name}.tmp"));
    let _ = std::fs::remove_dir_all(format!("{dir}.old"));
    let result = (|| -> Result<bool, String> {
        let language_dir = format!("{tmp_dir}/language");
        std::fs::create_dir_all(&language_dir).map_err(|e| e.to_string())?;
        let config_text = fetch_text(urls, &format!("completions/{name}/config.json"))?;
        let config: Value =
            serde_json::from_str(&config_text).map_err(|e| format!("bad config.json: {e}"))?;
        validate_config_id(&config)?;
        std::fs::write(format!("{tmp_dir}/config.json"), &config_text)
            .map_err(|e| e.to_string())?;

        // (url_path, local_path, is_hooks)
        let mut jobs: Vec<(String, String, bool)> = Vec::new();
        if let Some(langs) = config.get("language").and_then(|l| l.as_array()) {
            for lang in langs {
                if let Some(l) = lang.as_str() {
                    // The tag names both a URL segment and a local file: reject one carrying
                    // separators, so nothing lands outside the staging dir.
                    if !is_valid_name(l) {
                        return Err(format!("invalid language tag in config.json: {l}"));
                    }
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

        // Fetched one after another: a completion ships a handful of files, and the parallelism
        // that matters is across completions (`add`'s run_parallel). A thread per file would let
        // a hostile config.json decide how many threads to spawn.
        for (url_path, local_path, is_hooks) in &jobs {
            match fetch_text(urls, url_path) {
                Ok(text) => std::fs::write(local_path, text).map_err(|e| e.to_string())?,
                Err(e) => {
                    // hooks.lua may be missing remotely (not yet synced): degrade to static
                    // completions; the next update fills it in.
                    if !*is_hooks {
                        return Err(e);
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
        // Restore the previous version and drop the staged files. A failed restore leaves
        // `old_dir` behind (pid-suffixed; cleaned by the same pid's next add, or manually).
        let _ = std::fs::rename(old_dir, dir);
        let _ = std::fs::remove_dir_all(tmp_dir);
        return Err(format!("{e}"));
    }
    let _ = std::fs::remove_dir_all(old_dir);
    Ok(())
}

/// Manifest-derived per-completion config defaults (the manifest `config` items).
/// Manifest `config` defaults for a completion. Reads the manifest in the
/// requested language first (same selection as `build_default_data`), falling
/// back to the manifest's first declared language.
pub fn completion_defaults(data_dir: &str, name: &str, language: &str) -> Value {
    let mut map = serde_json::Map::new();
    let config_path = format!("{data_dir}/completions/{name}/config.json");
    if let Some(text) = crate::data::read_text(&config_path) {
        if let Ok(config) = serde_json::from_str::<Value>(&text) {
            let declared = config
                .get("language")
                .and_then(|l| l.as_array())
                .and_then(|a| a.first())
                .and_then(|v| v.as_str())
                .unwrap_or("en-US");
            let requested = if language.starts_with("zh") {
                "zh-CN"
            } else {
                "en-US"
            };
            let langs = if requested == declared {
                vec![requested]
            } else {
                vec![requested, declared]
            };
            for lang in langs {
                let manifest_path = format!("{data_dir}/completions/{name}/language/{lang}.json");
                let Some(text) = crate::data::read_text(&manifest_path) else {
                    continue;
                };
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
                    break;
                }
            }
        }
    }
    Value::Object(map)
}

/// After adding/updating a completion, refresh its alias + config defaults.
/// `reinstall` selects the discipline: `add` reinstalls — the whole per-completion
/// entry (trigger aliases + `config.completion`) is dropped and rebuilt from remote
/// defaults (like `rm` + `add`); `update` patches — a missing/empty trigger entry is
/// filled, per-completion config only gains missing keys, customizations survive.
/// Words already owned by another completion stay with their owner in both modes;
/// skipped words are returned for the warning.
pub fn refresh_settings_after_add(
    settings: &mut Settings,
    data_dir: &str,
    name: &str,
    reinstall: bool,
) -> Result<Vec<(String, String)>, String> {
    let config_path = format!("{data_dir}/completions/{name}/config.json");
    let text =
        crate::data::read_text(&config_path).ok_or_else(|| "missing config.json".to_string())?;
    let config: Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    if reinstall {
        // Reinstall feel: drop the whole per-completion config entry so the manifest
        // defaults below rebuild it from scratch (removed upstream keys vanish too).
        if let Some(comp) = settings
            .config
            .get_mut("completion")
            .and_then(|c| c.as_object_mut())
        {
            comp.remove(name);
        }
    }
    // Whether this completion already had per-completion settings before the manifest
    // defaults below may create it (first install vs update).
    let first_install = settings
        .config
        .get("completion")
        .and_then(|c| c.get(name))
        .is_none();
    let hooks_disabled = config.get("hooks").and_then(|h| h.as_bool()) == Some(false);

    let desired: Vec<String> = config
        .get("alias")
        .and_then(|a| a.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|x| x.as_str().map(String::from))
                .collect()
        })
        .filter(|a: &Vec<String>| !a.is_empty())
        .unwrap_or_else(|| vec![name.to_string()]);
    let skipped = if reinstall
        || settings
            .alias
            .get(name)
            .map(|v| v.is_empty())
            .unwrap_or(true)
    {
        let (kept, skipped) = crate::validate::filter_owned_triggers(settings, name, desired);
        settings.alias.insert(name.to_string(), kept);
        skipped
    } else {
        Vec::new()
    };

    // Per-completion config defaults from the manifest's `config` field.
    let lang = settings.language();
    if let Value::Object(map) = completion_defaults(data_dir, name, &lang) {
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
            .insert("enable_hooks".to_string(), serde_json::json!(0));
    }
    Ok(skipped)
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
    // Remove the old entry — a linked (junction) old completion is removed as a link only,
    // so the linked local source is never followed or deleted.
    remove_completion_entry(data_dir, old);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_config_id_requires_usable_id() {
        assert!(
            validate_config_id(&serde_json::json!({"id": "7b8d1eb7", "language": ["en-US"]}))
                .is_ok()
        );
        assert!(validate_config_id(&serde_json::json!({"language": ["en-US"]})).is_err());
        assert!(validate_config_id(&serde_json::json!({"id": ""})).is_err());
        assert!(validate_config_id(&serde_json::json!({"id": "  "})).is_err());
        assert!(validate_config_id(&serde_json::json!({"id": 123})).is_err());
    }

    #[test]
    fn cleanup_stale_staging_removes_only_pid_suffixed_residue() {
        // Directory mtimes are not portable to fake (Windows cannot set them
        // without backup semantics), so the threshold itself is the parameter:
        // ZERO sweeps every residue shape (covering dir removal), a huge age
        // keeps everything live.
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let mk = |tag: &str| {
            let n = SEQ.fetch_add(1, Ordering::SeqCst);
            let dir =
                std::env::temp_dir().join(format!("psc-staging-{tag}{}{}", std::process::id(), n));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(dir.join("temp")).unwrap();
            std::fs::create_dir_all(dir.join("completions")).unwrap();
            std::fs::create_dir_all(dir.join("temp/old.99999.tmp")).unwrap();
            std::fs::write(dir.join("temp/completions.json.99999.tmp"), "{}").unwrap();
            std::fs::create_dir_all(dir.join("completions/old.99999.old")).unwrap();
            std::fs::create_dir_all(dir.join("temp/live.12345.tmp")).unwrap();
            std::fs::write(dir.join("temp/completions.json"), "{}").unwrap();
            std::fs::create_dir_all(dir.join("completions/live")).unwrap();
            dir
        };
        let dir = mk("sweep");
        cleanup_stale_staging_with_age(dir.to_str().unwrap(), std::time::Duration::ZERO);
        assert!(!dir.join("temp/old.99999.tmp").exists());
        assert!(!dir.join("temp/completions.json.99999.tmp").exists());
        assert!(!dir.join("completions/old.99999.old").exists());
        // Non-matching names survive regardless of age.
        assert!(dir.join("temp/completions.json").exists());
        assert!(dir.join("completions/live").exists());
        let dir2 = mk("keep");
        cleanup_stale_staging_with_age(
            dir2.to_str().unwrap(),
            std::time::Duration::from_secs(365 * 24 * 60 * 60),
        );
        assert!(dir2.join("temp/old.99999.tmp").exists());
        assert!(dir2.join("temp/live.12345.tmp").exists());
        assert!(dir2.join("completions/old.99999.old").exists());
        let _ = std::fs::remove_dir_all(&dir);
        let _ = std::fs::remove_dir_all(&dir2);
    }

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
        assert!(
            validate_index_shape(&serde_json::json!({ "update": { "git": 42 }, "meta": {} }))
                .is_err()
        );
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

    #[test]
    fn index_branch_url_swaps_last_segment() {
        assert_eq!(
            index_branch_url("https://github.com/abgox/PSCompletions/raw/main"),
            Some("https://github.com/abgox/PSCompletions/raw/index".into())
        );
        // Non-branch path segments have no known index layout: tried as-is.
        assert_eq!(index_branch_url("https://mirror.example.com/psc/"), None);
        assert_eq!(
            index_branch_url("https://abgox.github.io/PSCompletions"),
            None
        );
        // A base already on the index layout resolves to itself (deduped downstream).
        assert_eq!(
            index_branch_url("https://github.com/abgox/PSCompletions/raw/index"),
            Some("https://github.com/abgox/PSCompletions/raw/index".into())
        );
        // Bare hosts have no swappable segment.
        assert_eq!(index_branch_url("https://example.com"), None);
        assert_eq!(index_branch_url("https://example.com/"), None);
    }

    #[test]
    fn official_sources_reads_psc_manifest_candidates() {
        let base = test_base();
        let dir = base.join("completions/psc/language");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("en-US.json"),
            r#"{"next":[{"name":"config","next":[{"name":"core","next":[{"name":"url","next":[{"name":"\"https://mirror.example/x\""},{"name":"\"\""}]}]}]}]}"#,
        )
        .unwrap();
        let src = official_sources(base.to_str().unwrap(), "en-US");
        assert!(src.contains(&"https://mirror.example/x".to_string()));
        assert!(is_official_source(
            base.to_str().unwrap(),
            "en-US",
            "https://mirror.example/x"
        ));
        assert!(!is_official_source(
            base.to_str().unwrap(),
            "en-US",
            "https://evil.example/y"
        ));
        // Empty (auto) never warns; static bases survive without a manifest.
        assert!(is_official_source(base.to_str().unwrap(), "en-US", ""));
        std::fs::remove_dir_all(&base).ok();
        let bare = test_base();
        let src = official_sources(bare.to_str().unwrap(), "en-US");
        assert_eq!(src.len(), 3);
        std::fs::remove_dir_all(&bare).ok();
    }

    #[test]
    fn resolve_index_urls_prefers_index_layout() {
        let mut s = Settings::default();
        s.config["url"] = serde_json::json!("https://example.com/raw/main");
        let urls = resolve_index_urls(&s);
        assert_eq!(
            urls,
            vec![
                "https://example.com/raw/index",
                "https://example.com/raw/main"
            ]
        );
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
    fn add_completion_rejects_a_name_that_escapes_the_library() {
        let base = test_base();
        std::fs::create_dir_all(base.join("completions")).unwrap();
        // `../evil` makes the staging dir resolve to `<base>/evil.<pid>.tmp` — outside temp/,
        // where the cleanup `remove_dir_all` calls would then delete outside the library too.
        let stray = base.join(format!("evil.{}.tmp", std::process::id()));
        let err = add_completion(base.to_str().unwrap(), "../evil", &[], "").unwrap_err();
        assert!(!stray.exists(), "staging dir escaped temp/: {stray:?}");
        assert!(err.contains("invalid completion name"), "{err}");
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
        // First install: `hooks: false` seeds enable_hooks=0 (disabled by default).
        let skipped =
            refresh_settings_after_add(&mut s, base.to_str().unwrap(), "x", true).unwrap();
        assert!(skipped.is_empty());
        assert_eq!(s.config["completion"]["x"]["enable_hooks"], 0);
        // Update (patch): an existing entry is never rewritten (the user's opt-in survives).
        s.config["completion"]["x"]["enable_hooks"] = serde_json::json!(1);
        let skipped =
            refresh_settings_after_add(&mut s, base.to_str().unwrap(), "x", false).unwrap();
        assert!(skipped.is_empty());
        assert_eq!(s.config["completion"]["x"]["enable_hooks"], 1);
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
        let skipped =
            refresh_settings_after_add(&mut s, base.to_str().unwrap(), "x", true).unwrap();
        // `hooks: true` writes no enable_hooks entry (absence means enabled).
        assert!(skipped.is_empty());
        assert!(s.config["completion"]["x"].get("enable_hooks").is_none());
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn refresh_settings_after_add_keeps_earlier_owner() {
        let base = test_base();
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
        // `hx` stays with the earlier owner; only `new` is installed.
        let skipped =
            refresh_settings_after_add(&mut s, base.to_str().unwrap(), "new", true).unwrap();
        assert_eq!(skipped, vec![("hx".to_string(), "helix".to_string())]);
        assert_eq!(s.alias.get("new").unwrap(), &vec!["new".to_string()]);
        assert_eq!(
            s.alias.get("helix").unwrap(),
            &vec!["helix".to_string(), "hx".to_string()]
        );
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn refresh_patch_keeps_custom_aliases_but_fills_missing() {
        let base = test_base();
        let dir = base.join("completions/x");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("config.json"),
            r#"{"language":["en-US"],"alias":["x","ex"]}"#,
        )
        .unwrap();
        // Customized entry survives patch mode untouched.
        let mut s = Settings::default();
        s.alias
            .insert("x".to_string(), vec!["x".to_string(), "mine".to_string()]);
        let skipped =
            refresh_settings_after_add(&mut s, base.to_str().unwrap(), "x", false).unwrap();
        assert!(skipped.is_empty());
        assert_eq!(
            s.alias.get("x").unwrap(),
            &vec!["x".to_string(), "mine".to_string()]
        );
        // Missing entry is filled from remote defaults.
        let mut s = Settings::default();
        let skipped =
            refresh_settings_after_add(&mut s, base.to_str().unwrap(), "x", false).unwrap();
        assert!(skipped.is_empty());
        assert_eq!(
            s.alias.get("x").unwrap(),
            &vec!["x".to_string(), "ex".to_string()]
        );
        // Empty entry counts as missing.
        let mut s = Settings::default();
        s.alias.insert("x".to_string(), Vec::new());
        let skipped =
            refresh_settings_after_add(&mut s, base.to_str().unwrap(), "x", false).unwrap();
        assert!(skipped.is_empty());
        assert_eq!(
            s.alias.get("x").unwrap(),
            &vec!["x".to_string(), "ex".to_string()]
        );
        // Overwrite mode resets customs (add = reinstall feel).
        let mut s = Settings::default();
        s.alias
            .insert("x".to_string(), vec!["x".to_string(), "mine".to_string()]);
        s.config = serde_json::json!({"completion": {"x": {"enable_tip": 0, "custom": 1}}});
        let skipped =
            refresh_settings_after_add(&mut s, base.to_str().unwrap(), "x", true).unwrap();
        assert!(skipped.is_empty());
        assert_eq!(
            s.alias.get("x").unwrap(),
            &vec!["x".to_string(), "ex".to_string()]
        );
        // The whole per-completion config entry is rebuilt (this manifest has no
        // `config` array, so customs simply vanish).
        assert!(s.config["completion"].get("x").is_none());
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
