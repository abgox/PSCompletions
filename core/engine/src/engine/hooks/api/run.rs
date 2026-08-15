//! `psc.run` family: process execution (single, parallel).

use mlua::{Lua, Table, Value, Variadic};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use super::parallel_map;
use super::HOOK_DEADLINE;
use super::{json_to_lua, table_to_strings};

/// `psc.run({cmd, arg, ...}, {timeout?, cwd?, format?, shell?})`.
/// Returns stdout lines; when `format` is `"json"`/`"toml"`/`"yaml"`, parses the output and
/// returns a table. `nil` on failure (spawn error / timeout / unparseable output) — strict
/// failure semantics, hooks guard with `or {}`.
/// `default_cwd` is the hook's working directory (the user's location): used when `cwd` is not
/// given, so commands run in the user's current directory rather than the engine process's
/// inherited one (which can lag after `cd` on some hosts).
pub(crate) fn api_run(
    lua: &Lua,
    args: Variadic<Value>,
    default_cwd: String,
) -> mlua::Result<Value> {
    let mut args = args.into_iter();
    let mut argv: Vec<String> = match args.next() {
        Some(Value::Table(t)) => table_to_strings(&t)?,
        _ => return Ok(Value::Nil),
    };
    let opts: Option<Table> = match args.next() {
        Some(Value::Table(t)) => Some(t),
        _ => None,
    };
    let timeout_ms = match &opts {
        Some(o) => o.get::<Option<u64>>("timeout")?.unwrap_or(5000),
        None => 5000,
    };
    let cwd_opt: Option<String> = match &opts {
        Some(o) => o.get("cwd")?,
        None => None,
    };
    let format: Option<String> = match &opts {
        Some(o) => o.get("format")?,
        None => None,
    };
    let shell = match &opts {
        Some(o) => o.get::<Option<bool>>("shell")?.unwrap_or(false),
        None => false,
    };
    if shell {
        argv = wrap_shell(&argv);
    }
    let cwd = cwd_opt.as_deref().unwrap_or(&default_cwd);
    let cwd_arg = if cwd.is_empty() { None } else { Some(cwd) };
    let Some(lines) = run_cmd_raw(&argv, timeout_ms, cwd_arg) else {
        return Ok(Value::Nil);
    };
    match format.as_deref() {
        Some(fmt) => {
            let text = lines.join("\n");
            let parsed = match fmt {
                "toml" => toml::from_str::<serde_json::Value>(&text).ok(),
                "yaml" => yaml_serde::from_str::<serde_json::Value>(&text).ok(),
                _ => serde_json::from_str::<serde_json::Value>(&text).ok(),
            };
            match parsed {
                Some(v) => json_to_lua(lua, &v),
                // Unparseable output → nil (strict failure semantics).
                None => Ok(Value::Nil),
            }
        }
        None => {
            let t = lua.create_table()?;
            for (i, l) in lines.iter().enumerate() {
                t.set(i + 1, l.clone())?;
            }
            Ok(Value::Table(t))
        }
    }
}

/// `psc.run_batch({ {cmd,...}, ... }, {timeout?, cwd?, format?})`.
/// Runs commands in parallel; returns their outputs in input order. With `format`,
/// each output is parsed with that format (parallel commands are of the same type).
/// A failed/unparseable command yields `nil` at its index (strict failure semantics).
pub(crate) fn api_run_batch(
    lua: &Lua,
    args: Variadic<Value>,
    default_cwd: String,
) -> mlua::Result<Table> {
    let mut args = args.into_iter();
    let cmds: Vec<Vec<String>> = match args.next() {
        Some(Value::Table(t)) => {
            let mut out = Vec::new();
            for i in 1..=t.raw_len() {
                let sub: Table = t.raw_get(i)?;
                out.push(table_to_strings(&sub)?);
            }
            out
        }
        _ => return lua.create_table(),
    };
    let opts: Option<Table> = match args.next() {
        Some(Value::Table(t)) => Some(t),
        _ => None,
    };
    let timeout_ms = match &opts {
        Some(o) => o.get::<Option<u64>>("timeout")?.unwrap_or(5000),
        None => 5000,
    };
    let cwd_opt: Option<String> = match &opts {
        Some(o) => o.get("cwd")?,
        None => None,
    };
    let format: Option<String> = match &opts {
        Some(o) => o.get("format")?,
        None => None,
    };
    let shell = match &opts {
        Some(o) => o.get::<Option<bool>>("shell")?.unwrap_or(false),
        None => false,
    };
    let cwd = cwd_opt.clone().unwrap_or_else(|| default_cwd.clone());
    let cwd_arg = if cwd.is_empty() {
        None
    } else {
        Some(cwd.as_str())
    };
    let outputs: Vec<Option<Vec<String>>> = parallel_map(&cmds, |cmd| {
        let argv = if shell { wrap_shell(cmd) } else { cmd.clone() };
        run_cmd_raw(&argv, timeout_ms, cwd_arg)
    });
    let t = lua.create_table()?;
    for (i, lines) in outputs.iter().enumerate() {
        match (lines, format.as_deref()) {
            (Some(lines), Some(fmt)) => {
                let text = lines.join("\n");
                let parsed = match fmt {
                    "toml" => toml::from_str::<serde_json::Value>(&text).ok(),
                    "yaml" => yaml_serde::from_str::<serde_json::Value>(&text).ok(),
                    _ => serde_json::from_str::<serde_json::Value>(&text).ok(),
                };
                match parsed {
                    Some(v) => t.set(i + 1, json_to_lua(lua, &v)?)?,
                    None => t.set(i + 1, Value::Nil)?,
                }
            }
            (Some(lines), None) => {
                let sub = lua.create_table()?;
                for (j, l) in lines.iter().enumerate() {
                    sub.set(j + 1, l.clone())?;
                }
                t.set(i + 1, sub)?;
            }
            (None, _) => t.set(i + 1, Value::Nil)?,
        }
    }
    Ok(t)
}

/// Wrap a command line in the platform shell so batch/PowerShell shims (e.g. `scoop`) can be
/// executed: `psc.run({ "scoop", "config" }, { shell = true })` → `cmd /c "scoop config"` on
/// Windows, `sh -c "scoop config"` elsewhere. Arguments containing whitespace or quotes are
/// quoted so the shell sees them as single words.
fn wrap_shell(argv: &[String]) -> Vec<String> {
    let joined: Vec<String> = argv.iter().map(|a| shell_quote(a)).collect();
    let line = joined.join(" ");
    if cfg!(windows) {
        vec!["cmd".into(), "/c".into(), line]
    } else {
        vec!["sh".into(), "-c".into(), line]
    }
}

/// Quote an argument for a POSIX-ish shell: wrap in double quotes when it contains whitespace
/// or quotes, escaping inner double quotes. Plain safe args pass through untouched.
fn shell_quote(arg: &str) -> String {
    let needs_quote = arg.is_empty() || arg.chars().any(|c| c.is_whitespace() || c == '"');
    if !needs_quote {
        return arg.to_string();
    }
    format!("\"{}\"", arg.replace('"', "\\\""))
}

/// Run a command, return its stdout lines. `None` on failure (empty argv / spawn error /
/// timeout); `Some(lines)` on success (possibly empty stdout).
/// Note: stdout is drained concurrently so a full pipe buffer (>64KB) cannot block the child.
pub(crate) fn run_cmd_raw(
    argv: &[String],
    timeout_ms: u64,
    cwd: Option<&str>,
) -> Option<Vec<String>> {
    if argv.is_empty() {
        return None;
    }
    let mut cmd = Command::new(&argv[0]);
    cmd.args(&argv[1..])
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    if let Some(c) = cwd {
        cmd.current_dir(c);
    }
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(_) => return None,
    };
    // Drain stdout on a helper thread and hand the text back over a channel. The channel
    // lets us give up without joining: a grandchild holding the pipe's write end keeps EOF
    // away forever, and `join()` on that thread would hang the whole hook.
    let (tx, rx) = std::sync::mpsc::channel();
    if let Some(s) = child.stdout.take() {
        std::thread::spawn(move || {
            use std::io::Read;
            let mut s = s;
            let mut buf = Vec::new();
            let _ = s.read_to_end(&mut buf);
            let _ = tx.send(String::from_utf8_lossy(&buf).to_string());
        });
    }
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    let timed_out = loop {
        match child.try_wait() {
            Ok(Some(_)) => break false,
            Ok(None) => {
                // Also stop when the hook's total budget is already spent, so a fresh
                // subprocess never runs its full timeout after the hook has timed out.
                let hook_expired =
                    HOOK_DEADLINE.with(|d| d.borrow().is_some_and(|dl| Instant::now() >= dl));
                if Instant::now() >= deadline || hook_expired {
                    break true;
                }
                std::thread::sleep(Duration::from_millis(5));
            }
            Err(_) => break true,
        }
    };
    if timed_out {
        let _ = child.kill();
        let _ = child.wait();
        return None;
    }
    // A non-zero exit code is a failure: strict semantics — hooks must not treat a failed
    // command's (possibly partial) stdout as valid candidates.
    let status = match child.wait() {
        Ok(s) => s,
        Err(_) => return None,
    };
    if !status.success() {
        return None;
    }
    // Wait briefly for the drained output; fall back to nothing when the pipe never
    // reaches EOF (grandchild still holding it) instead of blocking indefinitely.
    let stdout: String = rx
        .recv_timeout(Duration::from_millis(200))
        .unwrap_or_default();
    Some(stdout.lines().map(|s| s.to_string()).collect())
}
