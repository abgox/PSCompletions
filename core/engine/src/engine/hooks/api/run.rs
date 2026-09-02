//! `psc.run` family: process execution (single, parallel).

use mlua::{Lua, Table, Value, Variadic};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use super::parallel_map;
use super::{json_to_lua, table_to_strings};

/// `psc.run({cmd, arg, ...}, {timeout?, cwd?, format?, shell?, env?, capture_fd?})`.
/// Returns stdout lines; when `format` is `"json"`/`"toml"`/`"yaml"`, parses the output and
/// returns a table. `nil` on failure (spawn error / timeout / unparseable output) — strict
/// failure semantics, hooks guard with `or {}`.
/// `default_cwd` is the hook's working directory (the user's location): used when `cwd` is not
/// given, so commands run in the user's current directory rather than the engine process's
/// inherited one (which can lag after `cd` on some hosts).
/// `env` is a table of key-value pairs injected into the child process environment.
/// `capture_fd` is an extra file descriptor to capture (e.g. `8` for Python argcomplete which
/// writes completions to fd 8). When set, the command is run through the shell with `8>&1`
/// redirection so the fd's output is merged into stdout and captured.
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
    let capture_fd: Option<i32> = match &opts {
        Some(o) => o.get("capture_fd")?,
        None => None,
    };
    let env_map = parse_env(&opts)?;
    // capture_fd needs shell to interpret `8>&1` redirection; force shell when requested.
    let effective_shell = shell || capture_fd.is_some();
    if effective_shell {
        argv = wrap_shell_with_capture(&argv, capture_fd);
    }
    let cwd = cwd_opt.as_deref().unwrap_or(&default_cwd);
    let cwd_arg = if cwd.is_empty() { None } else { Some(cwd) };
    let Some(lines) = run_cmd_raw(&argv, timeout_ms, cwd_arg, env_map.as_deref()) else {
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

/// `psc.run_batch({ {cmd,...}, ... }, {timeout?, cwd?, format?, shell?, env?, capture_fd?})`.
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
    let capture_fd: Option<i32> = match &opts {
        Some(o) => o.get("capture_fd")?,
        None => None,
    };
    let env_map = parse_env(&opts)?;
    let effective_shell = shell || capture_fd.is_some();
    let cwd = cwd_opt.clone().unwrap_or_else(|| default_cwd.clone());
    let cwd_arg = if cwd.is_empty() {
        None
    } else {
        Some(cwd.as_str())
    };
    let outputs: Vec<Option<Vec<String>>> = parallel_map(&cmds, |cmd| {
        let argv = if effective_shell {
            wrap_shell_with_capture(cmd, capture_fd)
        } else {
            cmd.clone()
        };
        run_cmd_raw(&argv, timeout_ms, cwd_arg, env_map.as_deref())
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
#[allow(dead_code)]
fn wrap_shell(argv: &[String]) -> Vec<String> {
    wrap_shell_with_capture(argv, None)
}

/// Like `wrap_shell` but optionally captures an extra file descriptor (e.g. `8` for Python
/// argcomplete which writes completions to fd 8). The fd is redirected to stdout (`8>&1`) so
/// `run_cmd_raw`'s piped stdout captures it. The redirection is appended after the quoted args,
/// outside any per-arg quotes, so the shell parses it as redirection syntax, not as an argument.
fn wrap_shell_with_capture(argv: &[String], capture_fd: Option<i32>) -> Vec<String> {
    let joined: Vec<String> = argv.iter().map(|a| shell_quote(a)).collect();
    let mut line = joined.join(" ");
    if let Some(fd) = capture_fd {
        line = format!("{} {}>&1", line, fd);
    }
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

/// Parse the optional `env` field from a Lua opts table.
/// Accepts a Lua table of `{ [string] = string }` key-value pairs.
/// Returns `None` when the field is absent or nil; `Some(Vec<(String, String)>)` otherwise.
fn parse_env(opts: &Option<Table>) -> mlua::Result<Option<Vec<(String, String)>>> {
    let Some(o) = opts else {
        return Ok(None);
    };
    let Some(env_tbl) = o.get::<Option<Table>>("env")? else {
        return Ok(None);
    };
    let mut pairs = Vec::new();
    for pair in env_tbl.pairs::<String, String>() {
        let (k, v) = pair?;
        pairs.push((k, v));
    }
    Ok(Some(pairs))
}

/// Run a command, return its stdout lines. `None` on failure (empty argv / spawn error /
/// timeout); `Some(lines)` on success (possibly empty stdout).
/// `env` — optional key-value pairs injected into the child process environment (replacing
/// the inherited env when present).
/// Note: stdout is drained concurrently so a full pipe buffer (>64KB) cannot block the child.
pub(crate) fn run_cmd_raw(
    argv: &[String],
    timeout_ms: u64,
    cwd: Option<&str>,
    env: Option<&[(String, String)]>,
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
    if let Some(pairs) = env {
        cmd.envs(pairs.iter().cloned());
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
                let hook_expired = crate::engine::hooks::runner::is_hook_expired();
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
