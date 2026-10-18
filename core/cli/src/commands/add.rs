//! `psc add` - install completions from the remote index (parallel downloads).

use std::process::ExitCode;

use serde_json::{json, Value};

use crate::commands::run_parallel;
use crate::data::{read_text, Index, Settings};
use crate::messages::msg_cli;
use crate::net::{
    add_completion, download_list, refresh_settings_after_add, resolve_index_urls, resolve_urls,
};
use crate::output::{fail, meta, ok, Out};
use crate::postcheck::record_post_check;
use crate::validate::param_err;

#[allow(clippy::too_many_arguments)]
pub fn cmd_add(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    index: &mut Index,
    data_dir: &str,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    if args.is_empty() {
        return param_err(out, lang, json, data_dir);
    }
    // Snapshot the pre-operation update keys so the post-check can diff added/removed/renamed.
    let old_list: Vec<String> = read_text(&format!("{data_dir}/temp/completions.json"))
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .and_then(|v| {
            v.get("update")
                .and_then(|u| u.as_object())
                .map(|o| o.keys().cloned().collect())
        })
        .unwrap_or_default();
    let urls = resolve_urls(settings);
    // The index is fetched from the index branch first; content files stay on main.
    let list = match download_list(data_dir, &resolve_index_urls(settings)) {
        Ok(v) => {
            *index = Index::from_value(v);
            index.remote_names()
        }
        Err(e) => {
            return fail(
                out,
                "network",
                &format!("error: {e}"),
                json,
                &meta(None, data_dir),
                false,
            );
        }
    };
    let names: Vec<String> = args.to_vec();
    // Download multiple completions concurrently (shared client + bounded worker pool).
    let settings_lock = std::sync::Mutex::new(&mut *settings);
    let results: std::sync::Mutex<Vec<serde_json::Value>> = std::sync::Mutex::new(Vec::new());
    let index_ref: &Index = index;
    run_parallel(&names, 8, |name| {
        let entry = if !list.contains(name) {
            // Not in the remote library: report + mark failure
            if !json {
                out.line(&format!("{name} {}", msg_cli(lang, "not_available")));
            }
            serde_json::json!({
                "name": name,
                "ok": false,
                "error": { "code": "not_available", "message": msg_cli(lang, "not_available") }
            })
        } else {
            let version = index_ref.update.get(name).cloned().unwrap_or_default();
            match add_completion(data_dir, name, &urls, &version) {
                Ok(updated) => {
                    if !updated {
                        // Linked completions keep their link; settings still refresh.
                        let mut sg = settings_lock.lock().unwrap();
                        match refresh_settings_after_add(&mut sg, data_dir, name, true) {
                            Err(e) => {
                                if !json {
                                    out.line(&format!("error: {e}"));
                                }
                                serde_json::json!({"name": name, "ok": false, "error": {"code": "io", "message": e}})
                            }
                            Ok(_) => {
                                if !json {
                                    out.line(&format!("{name}: {}", msg_cli(lang, "add_done")));
                                }
                                serde_json::json!({"name": name, "ok": true})
                            }
                        }
                    } else {
                        let mut sg = settings_lock.lock().unwrap();
                        // `add` reinstalls: remote alias defaults fully overwrite.
                        match refresh_settings_after_add(&mut sg, data_dir, name, true) {
                            Err(e) => {
                                if !json {
                                    out.line(&format!("error: {e}"));
                                }
                                serde_json::json!({"name": name, "ok": false, "error": {"code": "io", "message": e}})
                            }
                            Ok(_) => {
                                if !json {
                                    out.line(&format!("{name}: {}", msg_cli(lang, "add_done")));
                                }
                                serde_json::json!({"name": name, "ok": true})
                            }
                        }
                    }
                }
                Err(e) => {
                    if !json {
                        out.line(&format!("{name}: error: {e}"));
                    }
                    serde_json::json!({"name": name, "ok": false, "error": {"code": "network", "message": e}})
                }
            }
        };
        results.lock().unwrap().push(entry);
    });
    if let Err(e) = settings.save(settings_path) {
        // Nothing was persisted: that is the whole command's failure, not one item's.
        return fail(
            out,
            "io",
            &format!("error: {e}"),
            json,
            &meta(None, data_dir),
            false,
        );
    }
    record_post_check(data_dir, settings, &old_list, index, &[], &names);
    let results = results.lock().unwrap().clone();
    let had_error = results.iter().any(|v| v["ok"] != true);
    if json {
        let count = results.len();
        ok(
            &json!({ "completions": results }),
            &meta(Some(count), data_dir),
        );
        // Any failed item fails the run (design/json.md §6).
        return if had_error {
            ExitCode::FAILURE
        } else {
            ExitCode::SUCCESS
        };
    }
    if had_error {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
