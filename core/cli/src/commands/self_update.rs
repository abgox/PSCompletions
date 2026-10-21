//! `psc --self-update` — say how this copy was installed, and what updates it.
//!
//! The text is the `psc` completion's own `info.self_update.*` templates, rendered by the one `{{…}}` implementation (`tpl`), so the advice is localized like every other user-facing string.
//! The detection itself lives in `install`; this file only reports it — except for the one case the CLI can act on, a script install, where it fetches the installer fresh and runs it.

use std::process::{ExitCode, Stdio};

use serde_json::json;

use crate::data::{load_psc_info, LibraryChanges, Settings};
use crate::install::{self, Method};
use crate::messages::msg_fmt;
use crate::output::{ok, Out};

pub fn cmd_self_update(
    args: &[String],
    settings: &Settings,
    data_dir: &str,
    completions_dir: &str,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    // The flag takes nothing: a stray argument is a usage error, not a silently normal run.
    if !args.is_empty() {
        return crate::validate::too_many_params(out, lang, json);
    }
    let exe = std::env::current_exe().unwrap_or_default();
    let method = install::detect(&exe);
    let package = install::installed_dir(&exe, &method);
    let dir = package
        .as_ref()
        .map(|d| d.display().to_string())
        .unwrap_or_default();
    let current = package
        .as_deref()
        .and_then(install::installed_version)
        .unwrap_or_default();
    // The newest version is whatever the last library check recorded; only when that is missing (the file is written by add/update, not by init) ask the source itself.
    let latest = LibraryChanges::load(data_dir).module.unwrap_or_default();
    let latest = if latest.is_empty() {
        crate::postcheck::fetch_module_version(settings).unwrap_or_default()
    } else {
        latest
    };
    // The installer's one-liner for an unmanaged copy comes from the same source prefix the completions do, so a mirror the user configured is honoured here too.
    let installer_url = crate::net::resolve_urls(settings)
        .first()
        .map(|base| format!("curl -fsSL {}/install.sh | sh", base.trim_end_matches('/')))
        .unwrap_or_default();
    let commands = install::update_commands(&method, &installer_url);
    let kind = method.kind();

    // A script install is the one we own: fetch the installer itself, so a changed script takes effect on the next run (the installed copy never carries one), and run it.
    let mut ran = false;
    if matches!(method, Method::Script { .. }) {
        match run_installer(settings, data_dir, json) {
            Ok(code) if code.success() => ran = true,
            Ok(code) => {
                let exit = code.code().unwrap_or(1).to_string();
                let message = msg_fmt(lang, "installer_failed", &[("Code", &exit)]);
                return crate::output::fail(out, "installer_failed", &message, json, false);
            }
            Err(e) => {
                let message = msg_fmt(lang, "installer_fetch", &[("Cause", e.as_str())]);
                return crate::output::fail(out, "installer_fetch", &message, json, false);
            }
        }
    }

    if json {
        return ok(&json!({
            "method": kind,
            "path": dir,
            "current": current,
            "latest": latest,
            "commands": commands,
            "ran": ran,
        }));
    }

    // A script install speaks through the installer: it printed the version it found, what it did about it and the rc lines to add.
    // A line from the CLI would only say the same thing twice, so this method has no text of its own.
    if matches!(method, Method::Script { .. }) {
        return ExitCode::SUCCESS;
    }

    let info = load_psc_info(completions_dir, lang);
    let key = if !latest.is_empty() && latest == current {
        "up_to_date"
    } else {
        kind
    };
    let template = info
        .get("self_update")
        .and_then(|s| s.get(key))
        .cloned()
        .unwrap_or_else(|| json!(fallback(key, &commands)));
    let ctx = json!({
        "Path": dir,
        "Current": current,
        "Latest": latest,
        "Commands": commands.join("\n"),
    });
    let text = crate::tpl::render_with_root(&template, &ctx, "", Some(&info));
    // Color is the caller's decision, exactly as in `psc tpl`: the hosts render into a captured stdout, where a TTY test answers "no" and silently drops the color the templates carry.
    // The trailing reset closes the last tag, which no template line closes itself.
    print!("{}", Out { color: true }.render(&text));
    print!("\x1b[0m");
    ExitCode::SUCCESS
}

/// Download `<base>/install.sh` from the same source prefix the completions come from, and run it.
/// A file, not a pipe: the user can read what ran, and the exit code is the script's own.
/// `json`: the caller's stdout carries exactly one object, so the installer's own output is kept off it (its errors stay on stderr, which is not that channel).
fn run_installer(
    settings: &Settings,
    data_dir: &str,
    json: bool,
) -> Result<std::process::ExitStatus, String> {
    let text = install::fetch_installer(settings)?;
    let path = format!("{data_dir}/temp/install.sh.{}", std::process::id());
    if let Some(parent) = std::path::Path::new(&path).parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::write(&path, text).map_err(|e| e.to_string())?;
    let status = std::process::Command::new("sh")
        .arg(&path)
        .stdout(if json {
            Stdio::null()
        } else {
            Stdio::inherit()
        })
        .status();
    let _ = std::fs::remove_file(&path);
    status.map_err(|e| e.to_string())
}

/// Plain English for a data dir whose `psc` completion is missing (the CLI self-heals it later):
/// the command must still say something a user can act on, so the commands are appended here too.
fn fallback(key: &str, commands: &[String]) -> Vec<String> {
    let mut lines = match key {
        "up_to_date" => vec!["PSCompletions is up to date.\n".to_string()],
        "scoop" => vec!["Scoop installed PSCompletions. Run:\n".to_string()],
        "module" => vec!["The PowerShell module installed PSCompletions. Run:\n".to_string()],
        _ => vec![
            "This copy of PSCompletions was not installed by an installer. Install it with:\n"
                .to_string(),
        ],
    };
    for command in commands {
        lines.push(format!("{command}\n"));
    }
    lines
}
