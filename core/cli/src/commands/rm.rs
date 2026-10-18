//! `psc rm` - remove completions and drop their settings entries.

use std::process::ExitCode;

use crate::data::{remove_completion_entry, Index, LibraryChanges, Settings};
use crate::messages::msg_cli;
use crate::output::{fail, meta, ok, Out};
use crate::validate::{name_status, param_err};

#[allow(clippy::too_many_arguments)]
pub fn cmd_rm(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    index: &Index,
    data_dir: &str,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    if args.is_empty() {
        return param_err(out, lang, json, data_dir);
    }
    let all = args.iter().any(|a| a == "--all");
    let completions_dir = format!("{data_dir}/completions");
    let names: Vec<String> = if all {
        // Disk is the source of truth for `rm --all`: settings may be empty or stale
        // (a lost settings.json, manual copies). `psc` itself is kept - it is the
        // module's own completion and init re-adds it anyway, so there's no network
        // round-trip to re-fetch it here.
        let mut names = settings.list();
        if let Ok(entries) = std::fs::read_dir(&completions_dir) {
            for e in entries.flatten() {
                let n = e.file_name().to_string_lossy().to_string();
                if !names.contains(&n) {
                    names.push(n);
                }
            }
        }
        names.retain(|n| n != "psc");
        names
    } else {
        args.iter().filter(|a| *a != "--all").cloned().collect()
    };
    if names.is_empty() {
        if all {
            // `rm --all` with nothing to remove is a successful no-op, not an error.
            if json {
                return ok(
                    &serde_json::json!({ "completions": [] }),
                    &meta(Some(0), data_dir),
                );
            }
            return ExitCode::SUCCESS;
        }
        return param_err(out, lang, json, data_dir);
    }
    let mut results: Vec<serde_json::Value> = Vec::new();
    let mut removed_any = false;
    for name in &names {
        let status = name_status(settings, index, &completions_dir, name);
        let invalid = if status == 0 {
            Some(("not_available", msg_cli(lang, "not_available")))
        } else if status == 1 {
            Some(("not_installed", msg_cli(lang, "no_completion")))
        } else {
            None
        };
        if let Some((code, msg)) = invalid {
            if !json {
                out.line(&format!("{name}: {msg}"));
            }
            results.push(serde_json::json!({
                "name": name,
                "ok": false,
                "error": { "code": code, "message": msg }
            }));
            continue;
        }
        remove_completion_entry(data_dir, name);
        removed_any = true;
        settings.alias.shift_remove(name);
        if let Some(comp) = settings
            .config
            .get_mut("completion")
            .and_then(|c| c.as_object_mut())
        {
            comp.remove(name);
        }
        results.push(serde_json::json!({"name": name, "ok": true}));
    }
    // Drop removed completions from every persisted notification list: a name the
    // user just removed must not keep surfacing as new/removed/renamed/out-of-date.
    let mut changes = LibraryChanges::load(data_dir);
    changes.update.retain(|u| !names.iter().any(|n| n == u));
    changes.added.retain(|u| !names.iter().any(|n| n == u));
    changes.removed.retain(|u| !names.iter().any(|n| n == u));
    changes
        .renamed
        .retain(|(o, n)| !names.iter().any(|x| x == o || x == n));
    changes.save(data_dir);
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
    let had_error = results.iter().any(|v| v["ok"] != true);
    if json {
        let count = results.len();
        ok(
            &serde_json::json!({ "completions": results }),
            &meta(Some(count), data_dir),
        );
        // Any failed item fails the run (design/json.md §6).
        return if had_error {
            ExitCode::FAILURE
        } else {
            ExitCode::SUCCESS
        };
    }
    if removed_any {
        out.line(&msg_cli(lang, "rm_done"));
    }
    if had_error {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
