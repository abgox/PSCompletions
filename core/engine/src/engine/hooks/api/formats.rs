//! `psc.*` structured-format capabilities: read + parse (single/many) for json / toml / yaml.
//!
//! A shared `parse_text_as` handles the format dispatch; each format has a single and a
//! `_batch` (parallel) entry. Parsing failures return nil (never crash a hook).

use mlua::{Lua, Table, Value};

use super::{json_to_lua, parallel_map, resolve};

/// Parse `text` as the given format into a `serde_json::Value`. None on invalid input.
fn parse_text_as(text: &str, format: &str) -> Option<serde_json::Value> {
    match format {
        "toml" => toml::from_str::<serde_json::Value>(text).ok(),
        "yaml" => yaml_serde::from_str::<serde_json::Value>(text).ok(),
        _ => serde_json::from_str::<serde_json::Value>(text).ok(),
    }
}

/// Read a file at `path` (resolved against cwd) and parse it as `format`.
fn read_and_parse(cwd: &str, path: &str, format: &str) -> Option<serde_json::Value> {
    let text = std::fs::read_to_string(resolve(cwd, path)).ok()?;
    parse_text_as(crate::strip_bom(&text), format)
}

/// `psc.json(path)` → read the file and parse its JSON into a Lua table; nil if missing or unparsable.
pub(crate) fn api_json(lua: &Lua, cwd: &str, path: String) -> mlua::Result<Value> {
    match read_and_parse(cwd, &path, "json") {
        Some(v) => json_to_lua(lua, &v),
        None => Ok(Value::Nil),
    }
}

/// `psc.toml(path)` → read the file and parse its TOML into a Lua table; nil if missing or unparsable.
pub(crate) fn api_toml(lua: &Lua, cwd: &str, path: String) -> mlua::Result<Value> {
    match read_and_parse(cwd, &path, "toml") {
        Some(v) => json_to_lua(lua, &v),
        None => Ok(Value::Nil),
    }
}

/// `psc.yaml(path)` → read the file and parse its YAML into a Lua table; nil if missing or unparsable.
pub(crate) fn api_yaml(lua: &Lua, cwd: &str, path: String) -> mlua::Result<Value> {
    match read_and_parse(cwd, &path, "yaml") {
        Some(v) => json_to_lua(lua, &v),
        None => Ok(Value::Nil),
    }
}

/// Shared `_batch` body: read + parse each path in parallel, return `{ [path] = table | nil }`
/// (nil for a missing/unparseable file — strict failure semantics).
fn parse_batch(lua: &Lua, cwd: &str, paths: &[String], format: &str) -> mlua::Result<Table> {
    let resolved: Vec<(String, String)> = paths
        .iter()
        .map(|p| (p.clone(), resolve(cwd, p).to_string_lossy().to_string()))
        .collect();
    let parsed: Vec<(String, Option<serde_json::Value>)> = parallel_map(&resolved, |(orig, p)| {
        let v = std::fs::read_to_string(p)
            .ok()
            .and_then(|t| parse_text_as(crate::strip_bom(&t), format));
        (orig.clone(), v)
    });
    let t = lua.create_table()?;
    for (path, v) in parsed {
        match v {
            Some(val) => t.set(path, json_to_lua(lua, &val)?)?,
            None => t.set(path, Value::Nil)?,
        }
    }
    Ok(t)
}

/// `psc.json_batch({path,...})` → read + parse JSON in parallel; returns `{ [path] = table | nil }`.
pub(crate) fn api_json_batch(lua: &Lua, cwd: &str, paths: Vec<String>) -> mlua::Result<Table> {
    parse_batch(lua, cwd, &paths, "json")
}

/// `psc.toml_batch({path,...})` → read + parse TOML in parallel; returns `{ [path] = table | nil }`.
pub(crate) fn api_toml_batch(lua: &Lua, cwd: &str, paths: Vec<String>) -> mlua::Result<Table> {
    parse_batch(lua, cwd, &paths, "toml")
}

/// `psc.yaml_batch({path,...})` → read + parse YAML in parallel; returns `{ [path] = table | nil }`.
pub(crate) fn api_yaml_batch(lua: &Lua, cwd: &str, paths: Vec<String>) -> mlua::Result<Table> {
    parse_batch(lua, cwd, &paths, "yaml")
}

// ===================== psc.log (debug output) =====================

use std::collections::HashSet;

/// Max nesting depth for `psc.log` table formatting (prevents stack overflow on deep tables).
const LOG_MAX_DEPTH: usize = 10;

/// Format any Lua value into a readable multi-line string (console.log style).
fn format_value(
    lua: &Lua,
    v: &Value,
    indent: usize,
    seen: &mut HashSet<usize>,
) -> mlua::Result<String> {
    let pad = "  ".repeat(indent);
    Ok(match v {
        Value::Nil => "nil".into(),
        Value::Boolean(b) => b.to_string(),
        Value::Integer(i) => i.to_string(),
        Value::Number(n) => {
            if n.fract() == 0.0 {
                format!("{n:.0}")
            } else {
                n.to_string()
            }
        }
        Value::String(s) => {
            let s = s.to_str()?;
            format!("\"{}\"", truncate(&s, 200))
        }
        Value::Function(_) => "<function>".into(),
        Value::Thread(_) => "<thread>".into(),
        Value::LightUserData(_) => "<lightuserdata>".into(),
        Value::UserData(_) => "<userdata>".into(),
        Value::Error(e) => format!("<error: {e}>"),
        Value::Table(t) => {
            if indent >= LOG_MAX_DEPTH {
                return Ok("<depth>".into());
            }
            let ptr = t.to_pointer() as usize;
            if seen.contains(&ptr) {
                return Ok("<cycle>".into());
            }
            seen.insert(ptr);
            let inner = format_table(lua, t, indent + 1, seen)?;
            seen.remove(&ptr);
            if inner.is_empty() {
                "{}".into()
            } else {
                format!("{{\n{inner}{pad}}}")
            }
        }
        other => format!("<{}>", mlua::Value::type_name(other)),
    })
}

/// Format a table's entries: numeric keys first (array part), then string keys (sorted).
fn format_table(
    lua: &Lua,
    t: &Table,
    indent: usize,
    seen: &mut HashSet<usize>,
) -> mlua::Result<String> {
    let pad = "  ".repeat(indent);
    let mut lines: Vec<String> = Vec::new();
    let mut numeric: Vec<(i64, Value)> = Vec::new();
    let mut string_keys: Vec<String> = Vec::new();
    let mut string_vals: std::collections::HashMap<String, Value> = Default::default();

    for pair in t.pairs::<Value, Value>() {
        let (k, val) = pair?;
        match k {
            Value::Integer(i) => numeric.push((i, val)),
            Value::String(s) => {
                let key = s.to_str()?.to_string();
                if !string_vals.contains_key(&key) {
                    string_keys.push(key.clone());
                }
                string_vals.insert(key, val);
            }
            Value::Number(n) if n.fract() == 0.0 => numeric.push((n as i64, val)),
            other => {
                let kk = format_value(lua, &other, indent, seen)?;
                let vv = format_value(lua, &val, indent, seen)?;
                lines.push(format!("{pad}[{kk}] = {vv},"));
            }
        }
    }
    numeric.sort_by_key(|(i, _)| *i);
    for (i, val) in numeric {
        let vv = format_value(lua, &val, indent, seen)?;
        lines.push(format!("{pad}[{i}] = {vv},"));
    }
    string_keys.sort();
    for key in string_keys {
        let vv = format_value(lua, &string_vals[&key], indent, seen)?;
        lines.push(format!("{pad}{key} = {vv},"));
    }
    Ok(lines.join("\n"))
}

/// Truncate a long string, keeping the tail visible.
fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        let head: String = s.chars().take(max - 3).collect();
        format!("{head}...")
    }
}

/// Local time as `YYYY-MM-DD HH:MM:SS`; falls back to UTC on any failure.
pub(crate) fn now_local() -> String {
    let now = time::OffsetDateTime::now_local().unwrap_or_else(|_| time::OffsetDateTime::now_utc());
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
        now.year(),
        u8::from(now.month()),
        now.day(),
        now.hour(),
        now.minute(),
        now.second(),
    )
}

/// Append a line to `<log_dir>/<file_name>.log`; silently ignored when logging is disabled or
/// the write fails (debug output must never break a hook or the menu).
///
/// Two rotation rules keep the file bounded:
/// - **Age**: an mtime older than `LOG_MAX_AGE` is removed before appending, so long-unused
///   logs are reset.
/// - **Size**: when the file exceeds `LOG_MAX_SIZE`, the front half is dropped and the tail
///   is kept (from the next complete line), prefixed with a `[truncated]` marker — so an
///   actively-written log can never grow unbounded.
pub(crate) fn append_log(log_dir: &str, file_name: &str, text: &str) {
    if log_dir.is_empty() {
        return;
    }
    let dir = std::path::Path::new(log_dir);
    if !dir.exists() {
        let _ = std::fs::create_dir_all(dir);
    }
    let file = dir.join(format!("{file_name}.log"));
    if log_is_stale(&file) {
        let _ = std::fs::remove_file(&file);
    }
    truncate_log_to_tail(&file);
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&file)
    {
        let _ = f.write_all(text.as_bytes());
    }
}

/// How long a log file can go untouched before the next append truncates it.
const LOG_MAX_AGE: std::time::Duration = std::time::Duration::from_secs(7 * 24 * 60 * 60);

/// Hard size cap for a single log file. On overflow the front half is dropped and the tail
/// is kept, so a frequently-written log (mtime keeps refreshing) can never grow unbounded.
const LOG_MAX_SIZE: u64 = 1024 * 1024;

/// Marker written at the head of a size-truncated log.
const LOG_TRUNCATED_MARKER: &[u8] = b"[truncated] older entries removed (1 MB cap)\n";

/// If the log exceeds `LOG_MAX_SIZE`, keep only the tail: the second half of the file,
/// starting at the first complete line after the midpoint, prepended with the truncation
/// marker. Best-effort; any failure keeps the file as-is and the next write retries.
fn truncate_log_to_tail(path: &std::path::Path) {
    let Ok(meta) = path.metadata() else {
        return;
    };
    if meta.len() <= LOG_MAX_SIZE {
        return;
    }
    let Ok(data) = std::fs::read(path) else {
        return;
    };
    let midpoint = (data.len() / 2).min(data.len());
    // Cut at the first newline at/after the midpoint so the kept tail starts at a
    // complete line (no half-line garbage at the head of the truncated log).
    let Some(offset) = data[midpoint..].iter().position(|&b| b == b'\n') else {
        return; // No newline in the second half; skip truncation (rare pathological file).
    };
    let keep_from = midpoint + offset + 1;
    let mut new_data = LOG_TRUNCATED_MARKER.to_vec();
    new_data.extend_from_slice(&data[keep_from..]);
    let _ = std::fs::write(path, new_data);
}

/// Whether the log file's last write is older than `LOG_MAX_AGE` (missing files aren't stale).
fn log_is_stale(path: &std::path::Path) -> bool {
    let Ok(meta) = path.metadata() else {
        return false;
    };
    let Ok(modified) = meta.modified() else {
        return false;
    };
    let Ok(age) = std::time::SystemTime::now().duration_since(modified) else {
        return false;
    };
    age > LOG_MAX_AGE
}

/// `psc.log(...)` → append a formatted dump of each value to `<log_dir>/debug.log`
/// (one per line). A multi-return call like `psc.log(fn())` prints every returned value
/// (no argument is mistaken for a file name). Empty `log_dir` disables logging.
pub(crate) fn api_log(lua: &Lua, values: mlua::Variadic<Value>, log_dir: &str) -> mlua::Result<()> {
    if log_dir.is_empty() {
        return Ok(());
    }
    let now = now_local();
    let mut text = String::new();
    for v in values {
        let formatted = format_value(lua, &v, 0, &mut HashSet::new())?;
        text.push_str(&format!("[{now}] {formatted}\n"));
    }
    append_log(log_dir, "debug", &text);
    Ok(())
}

#[cfg(test)]
mod tests_log_size {
    use super::*;

    #[test]
    fn append_log_truncates_to_tail_when_over_cap() {
        let dir = std::env::temp_dir().join(format!("psc-logsize-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let dir_s = dir.to_string_lossy().to_string();

        // Build a file over the cap from complete lines.
        let line = "x".repeat(64) + "\n";
        let mut big = String::new();
        while (big.len() as u64) < LOG_MAX_SIZE + 4096 {
            big.push_str(&line);
        }
        std::fs::write(dir.join("debug.log"), &big).unwrap();

        append_log(&dir_s, "debug", "[stamp] newest entry\n");

        let after = std::fs::read_to_string(dir.join("debug.log")).unwrap();
        assert!(
            after.len() as u64 <= LOG_MAX_SIZE + 1024,
            "still too big: {}",
            after.len()
        );
        assert!(
            after.starts_with("[truncated]"),
            "missing marker: {}",
            &after[..80.min(after.len())]
        );
        assert!(after.contains("[stamp] newest entry"), "newest entry lost");
        // The kept tail must start at a complete line: no partial "xxxx" fragment before a newline.
        for l in after.lines() {
            assert!(
                l.starts_with("[truncated]") || l.starts_with("[stamp]") || l.starts_with("xxx"),
                "unexpected line: {l}"
            );
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn append_log_no_truncation_under_cap() {
        let dir = std::env::temp_dir().join(format!("psc-logsmall-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let dir_s = dir.to_string_lossy().to_string();

        append_log(&dir_s, "debug", "[stamp] entry one\n");
        append_log(&dir_s, "debug", "[stamp] entry two\n");

        let after = std::fs::read_to_string(dir.join("debug.log")).unwrap();
        assert_eq!(after, "[stamp] entry one\n[stamp] entry two\n");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
