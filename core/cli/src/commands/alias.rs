//! `psc alias` - manage trigger aliases (list / add / rm / --reset).

use std::process::ExitCode;

use serde_json::json;

use crate::data::{Index, Settings};
use crate::messages::msg_cli;
use crate::output::{fail, key_line, ok, Out};
use crate::validate::{data_dir_of, name_error, name_status, reset_alias, too_few_params};

/// The entry every listing and every write answers with (design/json.md): the completion's name
/// and its trigger words — singular inside the item, exactly as `config.json` spells it.
fn alias_entry(name: &str, settings: &Settings) -> serde_json::Value {
    json!({
        "name": name,
        "alias": settings.alias.get(name).cloned().unwrap_or_default(),
    })
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
        if let Some((code, e)) = name_error(lang, &name, status, true) {
            return fail(out, code, &e, json, false);
        }
        reset_alias(settings, &data_dir, &name);
        if let Err(e) = settings.save(settings_path) {
            return fail(out, "io", &format!("error: {e}"), json, false);
        }
        if json {
            return ok(&alias_entry(&name, settings));
        }
        out.line(&msg_cli(lang, "alias_done"));
        return ExitCode::SUCCESS;
    }
    if args.iter().any(|a| a == "--reset") {
        // Only `alias --reset` is legal; any other arg is a subcommand error.
        let params: Vec<&String> = args.iter().filter(|a| *a != "--reset").collect();
        if !params.is_empty() {
            return fail(
                out,
                "invalid_subcommand",
                &msg_cli(lang, "invalid_subcommand"),
                json,
                true,
            );
        }
        let targets: Vec<String> = settings.list();
        let mut entries: Vec<serde_json::Value> = Vec::new();
        for n in &targets {
            reset_alias(settings, &data_dir, n);
            entries.push(alias_entry(n, settings));
        }
        if let Err(e) = settings.save(settings_path) {
            return fail(out, "io", &format!("error: {e}"), json, false);
        }
        if json {
            let data = json!({ "aliases": entries });
            return ok(&data);
        }
        out.line(&msg_cli(lang, "alias_done"));
        return ExitCode::SUCCESS;
    }
    match args.first().map(|s| s.as_str()) {
        None => {
            let entries: Vec<serde_json::Value> = settings
                .list()
                .iter()
                .map(|n| alias_entry(n, settings))
                .collect();
            if json {
                let data = json!({ "aliases": entries });
                return ok(&data);
            }
            for e in &entries {
                let name = e["name"].as_str().unwrap_or_default();
                let words: Vec<&str> = e["alias"]
                    .as_array()
                    .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                    .unwrap_or_default();
                out.line(&key_line(name, &words.join(", ")));
            }
            ExitCode::SUCCESS
        }
        Some("add") => {
            if args.len() < 3 {
                return too_few_params(out, lang, json);
            }
            let name = args[1].clone();
            let status = name_status(settings, index, &format!("{data_dir}/completions"), &name);
            if let Some((code, e)) = name_error(lang, &name, status, true) {
                return fail(out, code, &e, json, false);
            }
            let mut added: Vec<String> = Vec::new();
            // Every declined alias is recorded with its stable code, so a caller can tell a
            // wildcard from a word another completion already owns.
            let mut rejected: Vec<serde_json::Value> = Vec::new();
            let reject = |rejected: &mut Vec<serde_json::Value>,
                          a: &String,
                          code: &str,
                          msg: String,
                          json: bool| {
                if !json {
                    out.line(&format!("{a}: {msg}"));
                }
                rejected.push(json!({ "alias": a, "error": { "code": code, "message": msg } }));
            };
            for a in &args[2..] {
                if a.contains('*') || a.contains('?') {
                    reject(
                        &mut rejected,
                        a,
                        "alias_wildcard",
                        msg_cli(lang, "has_wildcard"),
                        json,
                    );
                    continue;
                }
                if a == "PSCompletions" {
                    reject(
                        &mut rejected,
                        a,
                        "alias_reserved",
                        msg_cli(lang, "cmd_exist"),
                        json,
                    );
                    continue;
                }
                // A word the completion already has is not rejected: re-declaring it changes
                // nothing in the list, but it still moves the completion to the end — that is
                // the explicit way to take a word back from a later claim. A word another
                // completion also claims is not rejected either: nothing is filtered anywhere.
                if !settings
                    .alias
                    .get(&name)
                    .is_some_and(|v| v.iter().any(|x| x == a))
                {
                    settings
                        .alias
                        .entry(name.clone())
                        .or_default()
                        .push(a.clone());
                }
                // Re-declaring moves the completion to the end of the claim order: that is how
                // it takes a word back from a later claim.
                settings.reclaim_alias(&name);
                added.push(a.clone());
            }
            if !added.is_empty() {
                if let Err(e) = settings.save(settings_path) {
                    return fail(out, "io", &format!("error: {e}"), json, false);
                }
                if !json {
                    out.line(&msg_cli(lang, "alias_done"));
                }
            }
            if json {
                let mut data = alias_entry(&name, settings);
                data["rejected"] = json!(rejected);
                ok(&data);
                // A declined alias fails this invocation, not the whole command.
                return if rejected.is_empty() {
                    ExitCode::SUCCESS
                } else {
                    ExitCode::FAILURE
                };
            }
            if rejected.is_empty() {
                ExitCode::SUCCESS
            } else {
                ExitCode::FAILURE
            }
        }
        Some("rm") => {
            if args.len() < 3 {
                return too_few_params(out, lang, json);
            }
            let name = args[1].clone();
            let status = name_status(settings, index, &format!("{data_dir}/completions"), &name);
            if let Some((code, e)) = name_error(lang, &name, status, true) {
                return fail(out, code, &e, json, false);
            }
            let Some(entry) = settings.alias.get_mut(&name) else {
                return fail(
                    out,
                    "not_installed",
                    &format!("{name}: {}", msg_cli(lang, "not_installed")),
                    json,
                    false,
                );
            };
            let remove_count = entry
                .iter()
                .filter(|a| args[2..].iter().any(|x| x == *a))
                .count();
            if remove_count == 0 {
                return fail(
                    out,
                    "alias_not_found",
                    &format!("{name}: {}", msg_cli(lang, "alias_not_found")),
                    json,
                    false,
                );
            }
            entry.retain(|a| !args[2..].iter().any(|x| x == a));
            if let Err(e) = settings.save(settings_path) {
                return fail(out, "io", &format!("error: {e}"), json, false);
            }
            if json {
                // The resulting state, the same shape `add` answers with.
                return ok(&alias_entry(&name, settings));
            }
            out.line(&msg_cli(lang, "alias_done"));
            ExitCode::SUCCESS
        }
        Some(_) => fail(
            out,
            "invalid_subcommand",
            &msg_cli(lang, "invalid_subcommand"),
            json,
            true,
        ),
    }
}
