//! `psc alias` - manage trigger aliases (list / add / rm / --reset).

use std::process::ExitCode;

use serde_json::json;

use crate::data::{Index, Settings};
use crate::messages::{msg_cli, msg_fmt};
use crate::output::{fail, Out};
use crate::validate::{data_dir_of, name_error, name_status, param_err, reset_alias};

fn skipped_json(skipped: &[(String, String)]) -> serde_json::Value {
    json!(skipped
        .iter()
        .map(|(alias, owner)| json!({ "alias": alias, "owner": owner }))
        .collect::<Vec<_>>())
}

pub fn cmd_alias(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    index: &Index,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    let data_dir = data_dir_of(settings_path);
    // `alias add <name> --reset` / `alias rm <name> --reset` : reset aliases for that completion.
    if args.len() == 3 && (args[0] == "add" || args[0] == "rm") && args[2] == "--reset" {
        let name = args[1].clone();
        let status = name_status(settings, index, &format!("{data_dir}/completions"), &name);
        if let Some(e) = name_error(lang, &name, status, true) {
            return fail(out, e, json);
        }
        let skipped = reset_alias(settings, &data_dir, &name);
        if let Err(e) = settings.save(settings_path) {
            return fail(out, format!("error: {e}"), json);
        }
        if json {
            let mut payload = json!({
                "name": name,
                "ok": true,
                "reset": settings.alias.get(&name).cloned().unwrap_or_default(),
            });
            if !skipped.is_empty() {
                payload["skipped"] = skipped_json(&skipped);
            }
            println!("{}", serde_json::to_string(&payload).unwrap_or_default());
            return ExitCode::SUCCESS;
        }
        for (a, owner) in &skipped {
            out.line(&format!(
                "{a}: {}",
                msg_fmt(lang, "alias_owned", &[("owner", owner)])
            ));
        }
        out.line(&msg_cli(lang, "alias_done"));
        return ExitCode::SUCCESS;
    }
    if args.iter().any(|a| a == "--reset") {
        // Only `alias --reset` is legal; any other arg is a subcommand error.
        let params: Vec<&String> = args.iter().filter(|a| *a != "--reset").collect();
        if !params.is_empty() {
            return fail(out, msg_cli(lang, "sub_cmd"), json);
        }
        let targets: Vec<String> = settings.list();
        let mut reset_entries: Vec<serde_json::Value> = Vec::new();
        let mut skipped_all: Vec<(String, String)> = Vec::new();
        for n in &targets {
            skipped_all.extend(reset_alias(settings, &data_dir, n));
            reset_entries.push(json!({
                "name": n,
                "aliases": settings.alias.get(n).cloned().unwrap_or_default(),
            }));
        }
        if let Err(e) = settings.save(settings_path) {
            return fail(out, format!("error: {e}"), json);
        }
        if json {
            let mut payload = json!({ "ok": true, "reset": reset_entries });
            if !skipped_all.is_empty() {
                payload["skipped"] = skipped_json(&skipped_all);
            }
            println!("{}", serde_json::to_string(&payload).unwrap_or_default());
            return ExitCode::SUCCESS;
        }
        for (a, owner) in &skipped_all {
            out.line(&format!(
                "{a}: {}",
                msg_fmt(lang, "alias_owned", &[("owner", owner)])
            ));
        }
        out.line(&msg_cli(lang, "alias_done"));
        return ExitCode::SUCCESS;
    }
    match args.first().map(|s| s.as_str()) {
        None => {
            if json {
                let arr: Vec<serde_json::Value> = settings
                    .list()
                    .iter()
                    .map(|name| {
                        let aliases = settings.alias.get(name).cloned().unwrap_or_default();
                        serde_json::json!({ "completion": name, "aliases": aliases })
                    })
                    .collect();
                println!("{}", serde_json::to_string(&arr).unwrap_or_default());
            } else {
                for name in settings.list() {
                    let aliases = settings.alias.get(&name).cloned().unwrap_or_default();
                    out.line(&format!("{name}: {}", aliases.join(" ")));
                }
            }
            ExitCode::SUCCESS
        }
        Some("add") => {
            if args.len() < 3 {
                return param_err(out, lang, json);
            }
            let name = args[1].clone();
            let status = name_status(settings, index, &format!("{data_dir}/completions"), &name);
            if let Some(e) = name_error(lang, &name, status, true) {
                return fail(out, e, json);
            }
            let mut added: Vec<String> = Vec::new();
            let mut rejected: Vec<serde_json::Value> = Vec::new();
            // `rejected` records every declined alias in BOTH modes: json mode serializes the
            // array, text mode only reads its length for the exit code while printing inline.
            let reject =
                |rejected: &mut Vec<serde_json::Value>, a: &String, msg: String, json: bool| {
                    if !json {
                        out.line(&format!("{a}: {msg}"));
                    }
                    rejected.push(json!({"alias": a, "ok": false, "error": msg}));
                };
            for a in &args[2..] {
                if a.contains('*') || a.contains('?') {
                    reject(&mut rejected, a, msg_cli(lang, "has_wildcard"), json);
                    continue;
                }
                if a == "PSCompletions" {
                    reject(&mut rejected, a, msg_cli(lang, "cmd_exist"), json);
                    continue;
                }
                if settings
                    .alias
                    .get(&name)
                    .map(|v| v.iter().any(|x| x == a))
                    .unwrap_or(false)
                {
                    reject(&mut rejected, a, msg_cli(lang, "alias_exist"), json);
                    continue;
                }
                let conflict = settings
                    .alias
                    .iter()
                    .find(|(k, v)| k.as_str() != name && v.iter().any(|x| x == a))
                    .map(|(k, _)| k.clone());
                if let Some(owner) = conflict {
                    // Already owned: the earlier owner keeps the word.
                    reject(
                        &mut rejected,
                        a,
                        msg_fmt(lang, "alias_owned", &[("owner", &owner)]),
                        json,
                    );
                    continue;
                }
                settings
                    .alias
                    .entry(name.clone())
                    .or_default()
                    .push(a.clone());
                added.push(a.clone());
            }
            if !added.is_empty() {
                if let Err(e) = settings.save(settings_path) {
                    return fail(out, format!("error: {e}"), json);
                }
                if !json {
                    out.line(&msg_cli(lang, "alias_done"));
                }
            }
            if json {
                if !added.is_empty() {
                    rejected.push(json!({"name": name, "ok": true, "added": added}));
                }
                println!("{}", serde_json::to_string(&rejected).unwrap_or_default());
                return ExitCode::SUCCESS;
            }
            if rejected.is_empty() {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
        Some("rm") => {
            if args.len() < 3 {
                return param_err(out, lang, json);
            }
            let name = args[1].clone();
            let status = name_status(settings, index, &format!("{data_dir}/completions"), &name);
            if let Some(e) = name_error(lang, &name, status, true) {
                return fail(out, e, json);
            }
            let Some(entry) = settings.alias.get_mut(&name) else {
                return fail(
                    out,
                    format!("{name}: {}", msg_cli(lang, "no_completion")),
                    json,
                );
            };
            let remove_count = entry
                .iter()
                .filter(|a| args[2..].iter().any(|x| x == *a))
                .count();
            if remove_count == 0 {
                return fail(
                    out,
                    format!("{name}: {}", msg_cli(lang, "alias_not_found")),
                    json,
                );
            }
            if entry.len() <= remove_count {
                return fail(out, msg_cli(lang, "alias_unique"), json);
            }
            let removed: Vec<String> = args[2..]
                .iter()
                .filter(|a| entry.iter().any(|x| x == *a))
                .cloned()
                .collect();
            entry.retain(|a| !args[2..].iter().any(|x| x == a));
            if let Err(e) = settings.save(settings_path) {
                return fail(out, format!("error: {e}"), json);
            }
            if !json {
                out.line(&msg_cli(lang, "alias_done"));
            }
            if json {
                println!(
                    "{}",
                    serde_json::to_string(&json!({"name": name, "ok": true, "removed": removed}))
                        .unwrap_or_default()
                );
            }
            ExitCode::SUCCESS
        }
        Some(_) => fail(out, msg_cli(lang, "sub_cmd"), json),
    }
}
