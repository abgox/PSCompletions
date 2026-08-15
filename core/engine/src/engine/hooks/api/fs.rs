//! `psc.*` file-system capabilities: read / exists / ls / glob, plus the batch `read_batch`.

use mlua::{Lua, Table, Value};

use super::parallel_map;

/// A directory entry as listed by `ls_entries`: `(name, full path, is_dir, is_link)`.
pub(crate) type LsEntry = (String, String, bool, bool);

/// Read a Lua array table (1..raw_len) into a Vec<String>;
/// nil/non-string elements are skipped (a `nil` in a `psc.run` argv or batch list must not crash the hook).
pub(crate) fn table_to_strings(t: &Table) -> mlua::Result<Vec<String>> {
    let mut out = Vec::new();
    for i in 1..=t.raw_len() {
        if let Value::String(s) = t.raw_get::<Value>(i)? {
            out.push(s.to_str()?.to_string());
        }
    }
    Ok(out)
}

/// Resolve relative paths against `cwd`; absolute paths are used as-is.
pub(crate) fn resolve(cwd: &str, path: &str) -> std::path::PathBuf {
    let p = std::path::Path::new(path);
    if p.is_absolute() {
        p.to_path_buf()
    } else {
        std::path::Path::new(cwd).join(p)
    }
}

/// `psc.read(path)` → file contents (read-only); nil if missing or unreadable.
pub(crate) fn api_read(lua: &Lua, cwd: &str, path: String) -> mlua::Result<Option<String>> {
    let _ = lua;
    Ok(std::fs::read_to_string(resolve(cwd, &path)).ok())
}

/// `psc.exist(path)` → whether the path exists (file or directory).
pub(crate) fn api_exist(lua: &Lua, cwd: &str, path: String) -> mlua::Result<bool> {
    let _ = lua;
    Ok(resolve(cwd, &path).exists())
}

/// `psc.ls(path)` → `{ {name, path, is_dir, is_link}, ... }`; nil if the directory does not exist
/// (strict failure semantics; an empty dir yields an empty array).
pub(crate) fn api_ls(lua: &Lua, cwd: &str, path: String) -> mlua::Result<Option<Table>> {
    let Ok(entries) = ls_entries(cwd, &path) else {
        return Ok(None);
    };
    let t = lua.create_table()?;
    for (i, (name, full, is_dir, is_link)) in entries.iter().enumerate() {
        let row = lua.create_table()?;
        row.set("name", name.clone())?;
        row.set("path", full.clone())?;
        row.set("is_dir", *is_dir)?;
        row.set("is_link", *is_link)?;
        t.set(i + 1, row)?;
    }
    Ok(Some(t))
}

/// Raw directory entries `(name, path, is_dir, is_link)`; shared by `ls` and `ls_batch`.
/// `path` is the resolved full path of the entry.
fn ls_entries(cwd: &str, path: &str) -> std::io::Result<Vec<LsEntry>> {
    let mut out = Vec::new();
    for e in std::fs::read_dir(resolve(cwd, path))? {
        let e = e?;
        let name = e.file_name().to_string_lossy().to_string();
        let full = e.path().to_string_lossy().to_string();
        let is_link = e.file_type().map(|ft| ft.is_symlink()).unwrap_or(false);
        let is_dir = std::fs::metadata(e.path())
            .map(|m| m.is_dir())
            .unwrap_or(false);
        out.push((name, full, is_dir, is_link));
    }
    Ok(out)
}

/// `psc.ls_batch({dir,...})` → list several directories in parallel; `{ [index] = entries | nil }`
/// (nil for a missing/unreadable dir — strict failure semantics).
pub(crate) fn api_ls_batch(lua: &Lua, cwd: &str, dirs: Vec<String>) -> mlua::Result<Table> {
    let resolved: Vec<(String, String)> = dirs
        .iter()
        .map(|d| (d.clone(), resolve(cwd, d).to_string_lossy().to_string()))
        .collect();
    let results: Vec<Option<Vec<LsEntry>>> =
        super::parallel_map(&resolved, |(_, p)| ls_entries(cwd, p).ok());
    let t = lua.create_table()?;
    for (i, r) in results.iter().enumerate() {
        match r {
            Some(entries) => {
                let sub = lua.create_table()?;
                for (j, (name, full, is_dir, is_link)) in entries.iter().enumerate() {
                    let row = lua.create_table()?;
                    row.set("name", name.clone())?;
                    row.set("path", full.clone())?;
                    row.set("is_dir", *is_dir)?;
                    row.set("is_link", *is_link)?;
                    sub.set(j + 1, row)?;
                }
                t.set(i + 1, sub)?;
            }
            None => t.set(i + 1, Value::Nil)?,
        }
    }
    Ok(t)
}

/// `psc.glob(pattern)` → array of matching file paths (relative to `cwd`; pattern may contain
/// `*`/`?`/`**`); nil for an invalid pattern (strict failure semantics; a valid pattern with no
/// match yields an empty array).
/// Windows: glob treats `\` as an escape, so native backslash paths from hook authors fail;
/// normalize them to `/`. On non-Windows, `\` is a legal filename character (rare), so it stays literal.
pub(crate) fn normalize_glob_pattern(pattern: &str) -> String {
    if cfg!(windows) {
        pattern.replace('\\', "/")
    } else {
        pattern.to_string()
    }
}

pub(crate) fn api_glob(lua: &Lua, cwd: &str, pattern: String) -> mlua::Result<Option<Vec<String>>> {
    let _ = lua;
    let base = std::path::Path::new(cwd).join(normalize_glob_pattern(&pattern));
    let Ok(entries) = glob::glob(&base.to_string_lossy()) else {
        return Ok(None);
    };
    let mut out = Vec::new();
    for p in entries.flatten() {
        out.push(p.to_string_lossy().to_string());
    }
    Ok(Some(out))
}

/// `psc.read_batch({path,...})` → read files in parallel; returns `{ [original path] = content | nil }`
/// (nil for a missing/unreadable file — strict failure semantics).
pub(crate) fn api_read_batch(lua: &Lua, cwd: &str, paths: Vec<String>) -> mlua::Result<Table> {
    let resolved: Vec<(String, String)> = paths
        .iter()
        .map(|p| (p.clone(), resolve(cwd, p).to_string_lossy().to_string()))
        .collect();
    let contents: Vec<(String, Option<String>)> = parallel_map(&resolved, |(orig, p)| {
        (orig.clone(), std::fs::read_to_string(p).ok())
    });
    let t = lua.create_table()?;
    for (path, c) in contents {
        match c {
            Some(txt) => t.set(path, txt)?,
            None => t.set(path, Value::Nil)?,
        }
    }
    Ok(t)
}

/// `psc.which(name)` — full path of the first executable found in PATH; nil when not found.
pub(crate) fn api_which(_lua: &Lua, name: String) -> mlua::Result<Option<String>> {
    let path_var = match std::env::var("PATH") {
        Ok(p) => p,
        Err(_) => return Ok(None),
    };
    let sep = if cfg!(windows) { ';' } else { ':' };
    for dir in path_var.split(sep) {
        if dir.is_empty() {
            continue;
        }
        let base = std::path::Path::new(dir).join(&name);
        #[cfg(windows)]
        {
            let pathext =
                std::env::var("PATHEXT").unwrap_or_else(|_| ".EXE;.BAT;.CMD;.COM".to_string());
            let mut candidates = vec![base.clone()];
            for e in pathext.split(';') {
                if !e.is_empty() {
                    candidates.push(std::path::PathBuf::from(format!("{}{}", base.display(), e)));
                }
            }
            for c in candidates {
                if c.is_file() {
                    return Ok(Some(c.to_string_lossy().to_string()));
                }
            }
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if base.is_file() {
                if base
                    .metadata()
                    .map(|m| m.permissions().mode() & 0o111 != 0)
                    .unwrap_or(false)
                {
                    return Ok(Some(base.to_string_lossy().to_string()));
                }
            }
        }
    }
    Ok(None)
}
