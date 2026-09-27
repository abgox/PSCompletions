//! `psc.*` file-system capabilities: read / exists / ls / glob, plus the batch `read_batch`.

use mlua::{Lua, Table, Value};
use std::time::{Duration, Instant};

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

/// `psc.glob(pattern)` → array of matching file paths (relative to `cwd`; absolute
/// patterns ignore `cwd`). The pattern may contain `*`/`?`/`**` and `{a,b}` alternation
/// (via `globset`, like `ripgrep`); nil for an invalid pattern (strict failure
/// semantics; a valid pattern with no match yields an empty array).
/// The walk respects `.gitignore`/`.ignore`/`.git/info/exclude` (via `ignore` crate,
/// like `ripgrep`): ignored files are never returned. `hidden` is `false` so dotfiles
/// like `.env.*` still match when the pattern asks for them.
/// Windows: glob treats `\` as an escape, so native backslash paths from hook authors fail;
/// normalize them to `/`. On non-Windows, `\` is a legal filename character (rare), so it stays literal.
pub(crate) fn normalize_glob_pattern(pattern: &str) -> String {
    if cfg!(windows) {
        pattern.replace('\\', "/")
    } else {
        pattern.to_string()
    }
}

/// Wall-clock budget for a single `glob` walk. Deliberately far below the hook's 10 s cap: a
/// completion menu that takes seconds to open is broken no matter what it finds, so a slow walk
/// returns the matches it already has instead of making the user wait. Measured on a 50k-file
/// tree (~0.6 s to walk), this leaves ample headroom for any legitimate listing while keeping the
/// worst case imperceptible.
pub(crate) const GLOB_BUDGET: Duration = Duration::from_millis(500);

/// How often the walk checks whether it is out of time. Every entry would put a clock read in
/// the per-file path; every 256 entries keeps that negligible while reacting in low milliseconds.
const GLOB_POLL_INTERVAL: usize = 256;

/// When a walk must stop: its own budget, or whatever is left of the hook's deadline, whichever
/// comes first. `hook_deadline` is a parameter (rather than read from the process-global slot) so
/// the composition is testable without shared state.
pub(crate) fn glob_stop_at(now: Instant, hook_deadline: Option<Instant>) -> Instant {
    match hook_deadline {
        Some(hook) => (now + GLOB_BUDGET).min(hook),
        None => now + GLOB_BUDGET,
    }
}

/// `psc.glob(pattern)` → array of matching file paths (see `normalize_glob_pattern` for the
/// pattern and ignore-file contract). The walk is time-bounded — see `glob_walk`.
pub(crate) fn api_glob(lua: &Lua, cwd: &str, pattern: String) -> mlua::Result<Option<Vec<String>>> {
    let _ = lua;
    let normalized = normalize_glob_pattern(&pattern);
    // Absolute patterns ignore `cwd` — `Path::join` discards the base when `normalized` is absolute.
    let abs_path = std::path::Path::new(cwd).join(&normalized);
    let abs_pat_str = abs_path.to_string_lossy().replace('\\', "/");

    // Validate pattern via globset; invalid → nil (strict failure).
    let glob = match globset::GlobBuilder::new(&abs_pat_str)
        .literal_separator(true)
        .case_insensitive(cfg!(windows))
        .backslash_escape(false)
        .build()
    {
        Ok(g) => g,
        Err(_) => return Ok(None),
    };
    let matcher = glob.compile_matcher();

    let has_meta = abs_pat_str.contains('*')
        || abs_pat_str.contains('?')
        || abs_pat_str.contains('[')
        || abs_pat_str.contains('{');
    if !has_meta {
        // No glob meta: direct existence check.
        if abs_path.exists() {
            return Ok(Some(vec![abs_path.to_string_lossy().replace('\\', "/")]));
        } else {
            return Ok(Some(Vec::new()));
        }
    }

    // Walk root = directory before the first meta char, to limit traversal.
    let meta_pos = abs_pat_str
        .find(|c| ['*', '?', '[', '{'].contains(&c))
        .unwrap();
    let prefix = &abs_pat_str[..meta_pos];
    let mut walk_root_str = match prefix.rfind('/') {
        Some(0) => "/".to_string(),
        Some(idx) => prefix[..idx].to_string(),
        None => cwd.to_string(),
    };
    if walk_root_str.is_empty() {
        walk_root_str = cwd.to_string();
    }
    let walk_root = std::path::Path::new(&walk_root_str);
    if !walk_root.exists() || !walk_root.is_dir() {
        return Ok(Some(Vec::new()));
    }

    // Depth hint: shallow patterns without `**` need not recurse deeply.
    let max_depth = if abs_pat_str.contains("**") {
        None
    } else {
        let remaining = abs_pat_str[walk_root_str.len()..].trim_start_matches('/');
        let depth = if remaining.is_empty() {
            0
        } else {
            remaining.matches('/').count() + 1
        };
        Some(depth)
    };

    let stop_at = glob_stop_at(
        Instant::now(),
        crate::engine::hooks::runner::hook_deadline(),
    );
    Ok(Some(glob_walk(walk_root, &matcher, max_depth, stop_at)))
}

/// Walk `walk_root` (respecting ignore files, like ripgrep) and collect the paths `matcher`
/// accepts, stopping at `stop_at`.
///
/// The walk is time-bounded, not count-bounded: the menu scrolls without a practical item limit,
/// so a result is never truncated for being large — only for taking too long to find. A partial
/// result degrades gracefully (the shallowest matches arrive first, and those are nearly always
/// the ones wanted), whereas a hang blocks the menu outright.
///
/// `stop_at` is an explicit parameter (not read from the process-global slot) so the bound is
/// testable without shared state.
pub(crate) fn glob_walk(
    walk_root: &std::path::Path,
    matcher: &globset::GlobMatcher,
    max_depth: Option<usize>,
    stop_at: Instant,
) -> Vec<String> {
    let mut builder = ignore::WalkBuilder::new(walk_root);
    builder
        .hidden(false)
        .git_ignore(true)
        .parents(true)
        .git_global(true)
        .git_exclude(true)
        .require_git(false)
        .follow_links(false);
    if let Some(d) = max_depth {
        builder.max_depth(Some(d));
    }
    let walker = builder.build();

    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    let mut visited: usize = 0;
    for entry in walker {
        // A recursive glob is a native walk: it burns wall-clock time without executing one
        // Lua instruction, so the VM instruction-count hook can never interrupt it. Checking
        // the clock here is what keeps a huge/deep tree from freezing the menu (the same
        // reason `psc.run` checks the deadline — see `api/run.rs`).
        visited += 1;
        if visited.is_multiple_of(GLOB_POLL_INTERVAL) && Instant::now() >= stop_at {
            break;
        }
        let Ok(entry) = entry else { continue };
        let s = entry.path().to_string_lossy().replace('\\', "/");
        if matcher.is_match(&s) && seen.insert(s.clone()) {
            out.push(s);
        }
    }
    out
}

/// `psc.path(...)` → normalize/join path segments into one path using the **native platform
/// separator** (`\` on Windows, `/` elsewhere): a single argument normalizes its separators
/// (on Windows `/` → `\`), multiple arguments are joined with that separator. Duplicate
/// separators collapse (`"a/" + "/b"` → `"a\b"` on Windows, `"a/b"` elsewhere). A leading
/// separator (absolute segment) and a drive root like `C:\` are preserved. The result is
/// valid as an input to every `psc.*` file API on its platform.
pub(crate) fn api_path(_lua: &Lua, parts: mlua::MultiValue) -> mlua::Result<String> {
    // Collect positional arguments; non-string values (nil, numbers, tables) are skipped,
    // mirroring the tolerant nil-handling of the other string-collecting APIs.
    let parts: Vec<String> = parts
        .into_iter()
        .filter_map(|v| match v {
            mlua::Value::String(s) => Some(s.to_string_lossy()),
            _ => None,
        })
        .collect();
    /// The platform's native path separator.
    fn sep() -> char {
        if cfg!(windows) {
            '\\'
        } else {
            '/'
        }
    }
    /// Collapse runs of the separator to a single one (keeping a leading/trailing one, so
    /// `/usr`, `C:\` etc. are preserved).
    fn collapse_seps(s: &str, sep: char) -> String {
        let mut out = String::new();
        let mut prev_sep = false;
        for ch in s.chars() {
            let is_sep = ch == sep;
            if is_sep {
                if !prev_sep {
                    out.push(ch);
                }
                prev_sep = true;
            } else {
                out.push(ch);
                prev_sep = false;
            }
        }
        out
    }

    let sep = sep();
    let mut out = String::new();
    for part in parts {
        // On Windows both `/` and `\` are path separators: unify to the native `\`.
        let part = if cfg!(windows) {
            part.replace('/', "\\")
        } else {
            part
        };
        let part = collapse_seps(&part, sep);
        if part.is_empty() {
            continue;
        }
        if !out.is_empty() {
            let out_ends_sep = out.ends_with(sep);
            let part_starts_sep = part.starts_with(sep);
            if out_ends_sep && part_starts_sep {
                out.pop();
            } else if !out_ends_sep && !part_starts_sep {
                out.push(sep);
            }
        }
        out.push_str(&part);
    }
    Ok(out)
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
