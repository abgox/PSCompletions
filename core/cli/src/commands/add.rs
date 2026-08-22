//! `psc add` - install completions from the remote index (parallel downloads).

use std::process::ExitCode;

use serde_json::Value;

use crate::commands::run_parallel;
use crate::data::{read_text, Index, Settings};
use crate::messages::msg_cli;
use crate::net::{add_completion, download_list, refresh_settings_after_add, resolve_urls};
use crate::output::{fail, Out};
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
        return param_err(out, lang, json);
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
    let list = match download_list(data_dir, &urls) {
        Ok(v) => {
            *index = Index::from_value(v);
            index.remote_names()
        }
        Err(e) => {
            return fail(out, format!("error: {e}"), json);
        }
    };
    let all = args.iter().any(|a| a == "--all");
    let names: Vec<String> = if all {
        list.clone()
    } else {
        args.iter()
            .filter(|a| a.as_str() != "--all")
            .cloned()
            .collect()
    };
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
                "completion": name,
                "ok": false,
                "error": msg_cli(lang, "not_available")
            })
        } else {
            let version = index_ref.update.get(name).cloned().unwrap_or_default();
            match add_completion(data_dir, name, &urls, &version) {
                Ok(_updated) => {
                    let mut sg = settings_lock.lock().unwrap();
                    if let Err(e) = refresh_settings_after_add(&mut sg, data_dir, name) {
                        if !json {
                            out.line(&format!("error: {e}"));
                        }
                        serde_json::json!({"completion": name, "ok": false, "error": e})
                    } else {
                        if !json {
                            out.line(&format!("{name}: {}", msg_cli(lang, "add_done")));
                        }
                        serde_json::json!({"completion": name, "ok": true})
                    }
                }
                Err(e) => {
                    if !json {
                        out.line(&format!("{name}: error: {e}"));
                    }
                    serde_json::json!({"completion": name, "ok": false, "error": e})
                }
            }
        };
        results.lock().unwrap().push(entry);
    });
    if let Err(e) = settings.save(settings_path) {
        if json {
            let arr = results.lock().unwrap().clone();
            println!("{}", serde_json::to_string(&arr).unwrap_or_default());
            return ExitCode::SUCCESS;
        }
        out.line(&format!("error: {e}"));
        return ExitCode::FAILURE;
    }
    record_post_check(data_dir, settings, &old_list, index, &[]);
    if json {
        let arr = results.lock().unwrap().clone();
        println!("{}", serde_json::to_string(&arr).unwrap_or_default());
        return ExitCode::SUCCESS;
    }
    let had_error = results.lock().unwrap().iter().any(|v| v["ok"] != true);
    if had_error {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
