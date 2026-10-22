//! `psc --self-update` — say how this copy was installed, and what updates it.
//!
//! The text is the `psc` completion's own `info.self_update.*` templates, rendered by the one `{{…}}` implementation (`tpl`), so the advice is localized like every other user-facing string.
//! The detection itself lives in `install`; this file only reports it — except for the one case the CLI can act on, a script install, where it fetches the installer fresh and runs it.

use std::process::{ExitCode, Stdio};

use serde_json::json;

use crate::data::{load_psc_info, LibraryChanges, Settings};
use crate::install::{self, Method};
use crate::messages::{msg_cli, msg_fmt};
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
    let script = matches!(method, Method::Script { .. });
    let progress = |key: &str| {
        if json {
            return;
        }
        let line = Out { color: true }.render(&format!("<@Cyan>{}<@>", msg_cli(lang, key)));
        eprintln!("{line}");
    };
    // A script install reports through the installer, which probes the Gallery itself — asking here first would only add a second silent round trip in front of the one that prints.
    // The payload still needs the value, so `--json` keeps asking.
    let cached = LibraryChanges::load(data_dir).module.unwrap_or_default();
    let latest = if script && !json {
        String::new()
    } else if install::version_newer(&cached, &current) == Some(true) {
        // A cached value answers the question only while it still proves "something newer exists".
        cached
    } else {
        // The probe can spend up to its per-request timeout on each mirror before it answers;
        // saying so turns a frozen-looking command into a wait with a reason.
        progress("checking_updates");
        crate::postcheck::fetch_module_version(settings).unwrap_or(cached)
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
    if script {
        // The fetch is a network round trip with nothing to show for it, and on a slow or blackholed link it is the longest silent stretch of the command — one line, on stderr so it is not queued behind the installer's own stdout.
        progress("installer_downloading");
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
    if script {
        return ExitCode::SUCCESS;
    }

    let info = load_psc_info(completions_dir, lang);
    let key = report_key(kind, &current, &latest);
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
    let block_src = info
        .get("sponsor_block")
        .cloned()
        .unwrap_or_else(|| json!([]));
    let block = crate::tpl::render_with_root(&block_src, &ctx, "", Some(&info));
    let mut rendered = Out { color: true }.render(&text);
    if !block.trim().is_empty() {
        rendered.push('\n');
        rendered.push_str(&Out { color: true }.render(&block));
    }
    // Color is the caller's decision, exactly as in `psc tpl`: the hosts render into a captured stdout, where a TTY test answers "no" and silently drops the color the templates carry.
    // The trailing reset closes the last tag, which no template line closes itself.
    print!("{rendered}\x1b[0m");
    ExitCode::SUCCESS
}

/// Which `info.self_update` template the report uses.
/// Only a genuinely newer published version is an update: an equal value, a cache written before the package was upgraded, and a source that lags behind the package all read as "nothing to install", never as `current > latest`.
/// A value that cannot be compared keeps the reporting branch, so both numbers and the commands still reach the user.
fn report_key<'a>(kind: &'a str, current: &str, latest: &str) -> &'a str {
    match install::version_newer(latest, current) {
        Some(true) => kind,
        Some(false) => "up_to_date",
        None => kind,
    }
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

#[cfg(test)]
mod tests {
    use super::report_key;

    #[test]
    fn only_a_newer_published_version_reads_as_an_update() {
        // The scoop case that went wrong: the package was upgraded to 8.0.3 while `change.json` still recorded 8.0.2, and the report rendered `8.0.3 > 8.0.2` — a downgrade that never existed.
        assert_eq!(report_key("scoop", "8.0.3", "8.0.2"), "up_to_date");
        // Equal is up to date, as before.
        assert_eq!(report_key("module", "8.0.3", "8.0.3"), "up_to_date");
        // A genuinely newer remote keeps the reporting branch (its own template, with both numbers and the commands).
        assert_eq!(report_key("module", "8.0.2", "8.0.3"), "module");
        // Segments compare numerically, so 8.0.10 beats 8.0.9 rather than losing a string compare.
        assert_eq!(report_key("scoop", "8.0.9", "8.0.10"), "scoop");
        // Nothing to compare with: report both numbers instead of claiming a status.
        assert_eq!(report_key("unknown", "", "8.0.3"), "unknown");
        assert_eq!(report_key("unknown", "8.0.3", ""), "unknown");
        assert_eq!(report_key("unknown", "8.0.3", "not-a-version"), "unknown");
    }
}
