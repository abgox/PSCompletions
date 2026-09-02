//! `psc update` - real-time library check, named/--old/--all updates, rename migration.

use std::process::ExitCode;

use serde_json::{json, Value};

use crate::commands::run_parallel;
use crate::data::{read_text, Index, LibraryChanges, Settings};
use crate::messages::msg_cli;
use crate::net::{
    add_completion, download_list, local_completion_id, refresh_settings_after_add,
    rename_completion, resolve_urls,
};
use crate::output::{fail, Out};
use crate::postcheck::{fetch_module_version, record_post_check};
#[allow(clippy::too_many_arguments)]
pub fn cmd_update(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    index: &mut Index,
    data_dir: &str,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    let old_list: Vec<String> = read_text(&format!("{data_dir}/temp/completions.json"))
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .and_then(|v| {
            v.get("update")
                .and_then(|u| u.as_object())
                .map(|o| o.keys().cloned().collect())
        })
        .unwrap_or_default();
    let urls = resolve_urls(settings);
    let list = match download_list(data_dir, &urls) {
        Ok(v) => {
            *index = Index::from_value(v);
            index.remote_names()
        }
        Err(e) => {
            return fail(out, format!("error: {e}"), json);
        }
    };
    // Rename detection: a locally installed completion whose stable id now maps to a different remote name has been renamed upstream.
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
    let needs_update = |name: &String| -> bool {
        let dir = format!("{data_dir}/completions/{name}");
        if let Ok(meta) = std::fs::symlink_metadata(&dir) {
            if meta.file_type().is_symlink() {
                return false;
            }
        }
        let local = std::fs::read_to_string(format!("{dir}/.update")).unwrap_or_default();
        let remote = index.update.get(name).cloned().unwrap_or_default();
        local.trim() != remote
    };
    let need_update: Vec<String> = settings
        .list()
        .into_iter()
        .filter(|name| (list.contains(name) || rename_map.contains_key(name)) && needs_update(name))
        .collect();

    let is_check = args.is_empty();
    if is_check {
        let rename_keys: std::collections::HashSet<String> = rename_map.keys().cloned().collect();
        let update_no_rename: Vec<String> = need_update
            .iter()
            .filter(|n| !rename_keys.contains(*n))
            .cloned()
            .collect();
        let new_list: Vec<String> = index.update.keys().cloned().collect();
        let mut added: Vec<String> = new_list
            .iter()
            .filter(|n| !old_list.contains(n))
            .cloned()
            .collect();
        let mut removed: Vec<String> = old_list
            .iter()
            .filter(|n| !new_list.contains(n))
            .cloned()
            .collect();
        let rename_vals: std::collections::HashSet<String> = rename_map.values().cloned().collect();
        added.retain(|n| !rename_vals.contains(n));
        removed.retain(|n| !rename_keys.contains(n));
        added.sort();
        removed.sort();
        let mut renamed: Vec<(String, String)> = rename_map
            .iter()
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        renamed.sort_by(|a, b| a.0.cmp(&b.0));
        let mut changes = LibraryChanges::load(data_dir);
        changes.update = update_no_rename.clone();
        changes.added = added.clone();
        changes.removed = removed.clone();
        changes.renamed = renamed.clone();
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

        let mut any = false;
        let updatable_no_rename: Vec<&String> = need_update
            .iter()
            .filter(|n| !rename_keys.contains(*n))
            .collect();
        if !updatable_no_rename.is_empty() {
            any = true;
            if !json {
                out.line(&msg_cli(lang, "updatable"));
                for n in &updatable_no_rename {
                    out.line(&format!("  {n}"));
                }
            }
        }
        if !added.is_empty() {
            any = true;
            if !json {
                out.line(&msg_cli(lang, "lib_add"));
                for n in &added {
                    out.line(&format!("  {n}"));
                }
            }
        }
        if !removed.is_empty() {
            any = true;
            if !json {
                out.line(&msg_cli(lang, "lib_rm"));
                for n in &removed {
                    out.line(&format!("  {n}"));
                }
            }
        }
        if !renamed.is_empty() {
            any = true;
            if !json {
                out.line(&msg_cli(lang, "lib_rename"));
                for (old_n, new_n) in &renamed {
                    out.line(&format!("  {old_n} -> {new_n}"));
                }
            }
        }
        if !any && !json {
            out.line(&msg_cli(lang, "update_no"));
        }
        if json {
            println!(
                "{}",
                serde_json::to_string(&json!({
                    "update": update_no_rename,
                    "added": added,
                    "removed": removed,
                    "renamed": renamed.iter().map(|(a, b)| json!([a, b])).collect::<Vec<_>>(),
                }))
                .unwrap_or_default()
            );
        }
        return ExitCode::SUCCESS;
    }
    let all = args.iter().any(|a| a == "--all");
    let old = args.iter().any(|a| a == "--old");
    let named: Vec<String> = args
        .iter()
        .filter(|a| *a != "--all" && *a != "--old")
        .cloned()
        .collect();
    // `--all` force-updates every installed completion; `--old` updates only the out-of-date
    // ones; named targets are re-fetched unconditionally (naming a completion IS the intent to
    // reinstall it).
    let names: Vec<String> = if all {
        settings.list()
    } else if old {
        need_update.clone()
    } else {
        named
    };
    let installed: std::collections::HashSet<String> = settings.list().into_iter().collect();
    let settings_lock = std::sync::Mutex::new(&mut *settings);
    let had_error = std::sync::atomic::AtomicBool::new(false);
    let results: std::sync::Mutex<Vec<Value>> = std::sync::Mutex::new(Vec::new());
    let index_ref: &Index = index;
    run_parallel(&names, 8, |name| {
        let known = installed.contains(name)
            || std::path::Path::new(&format!("{data_dir}/completions/{name}")).exists()
            || list.contains(name);
        if !known {
            had_error.store(true, std::sync::atomic::Ordering::SeqCst);
            let err = msg_cli(lang, "not_available");
            results
                .lock()
                .unwrap()
                .push(json!({"completion": name, "ok": false, "error": err}));
            if !json {
                out.line(&format!("{name} {err}"));
            }
            return;
        }
        // Renamed upstream: migrate the old install (download new files, move settings, drop the old directory) instead of a plain update.
        // Must run before the `list.contains` check — a renamed old name no longer exists in the remote list.
        if let Some(new_name) = rename_map.get(name).cloned() {
            let version = index_ref.update.get(&new_name).cloned().unwrap_or_default();
            let mut sg = settings_lock.lock().unwrap();
            match rename_completion(&mut sg, data_dir, name, &new_name, &urls, &version) {
                Ok(()) => {
                    if json {
                        results.lock().unwrap().push(json!({
                            "completion": new_name, "ok": true, "renamed_from": name
                        }));
                    } else {
                        out.line(&format!(
                            "{name} {} {new_name}",
                            msg_cli(lang, "rename_done")
                        ));
                    }
                }
                Err(e) => {
                    had_error.store(true, std::sync::atomic::Ordering::SeqCst);
                    if json {
                        results
                            .lock()
                            .unwrap()
                            .push(json!({"completion": name, "ok": false, "error": e}));
                    } else {
                        out.line(&format!("{name}: error: {e}"));
                    }
                }
            }
            return;
        }
        if !list.contains(name) {
            return;
        }
        let version = index_ref.update.get(name).cloned().unwrap_or_default();
        match add_completion(data_dir, name, &urls, &version) {
            Ok(updated) => {
                if !updated {
                    let err = msg_cli(lang, "update_skip");
                    results
                        .lock()
                        .unwrap()
                        .push(json!({"completion": name, "ok": false, "error": err}));
                    if !json {
                        out.line(&format!("{name}: {err}"));
                    }
                    return;
                }
                let mut sg = settings_lock.lock().unwrap();
                if let Err(e) = refresh_settings_after_add(&mut sg, data_dir, name) {
                    had_error.store(true, std::sync::atomic::Ordering::SeqCst);
                    if json {
                        results
                            .lock()
                            .unwrap()
                            .push(json!({"completion": name, "ok": false, "error": e}));
                    } else {
                        out.line(&format!("error: {e}"));
                    }
                }
                if json {
                    results
                        .lock()
                        .unwrap()
                        .push(json!({"completion": name, "ok": true}));
                } else {
                    out.line(&format!("{name}: {}", msg_cli(lang, "update_done")));
                }
            }
            Err(e) => {
                had_error.store(true, std::sync::atomic::Ordering::SeqCst);
                if json {
                    results
                        .lock()
                        .unwrap()
                        .push(json!({"completion": name, "ok": false, "error": e}));
                } else {
                    out.line(&format!("{name}: error: {e}"));
                }
            }
        }
    });
    if json {
        let results = results.lock().unwrap();
        println!("{}", serde_json::to_string(&*results).unwrap_or_default());
    }
    // Persist the renames actually executed during this update so the module's pending
    // notifications can still show them even if the JSON results were not consumed.
    let executed_renames: Vec<(String, String)> = {
        let results = results.lock().unwrap();
        results
            .iter()
            .filter_map(|v| {
                let from = v.get("renamed_from").and_then(|x| x.as_str());
                let to = v.get("completion").and_then(|x| x.as_str());
                match (from, to) {
                    (Some(f), Some(t)) => Some((f.to_string(), t.to_string())),
                    _ => None,
                }
            })
            .collect()
    };
    // Refresh the persisted post-check state (added/removed/renamed/update/module) and check the module version.
    // Runs AFTER the operation, diffing the pre-operation snapshot against the fresh index.
    record_post_check(data_dir, settings, &old_list, index, &executed_renames);
    if let Err(e) = settings.save(settings_path) {
        if json {
            let mut results = results.lock().unwrap().clone();
            results.push(serde_json::json!({"ok": false, "error": e}));
            println!("{}", serde_json::to_string(&results).unwrap_or_default());
            return ExitCode::SUCCESS;
        }
        out.line(&format!("error: {e}"));
        return ExitCode::FAILURE;
    }
    if json {
        return ExitCode::SUCCESS;
    }
    if had_error.load(std::sync::atomic::Ordering::SeqCst) {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
