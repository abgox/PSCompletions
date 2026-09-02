//! Lua dynamic-completion runtime: runs `hooks.lua` in the Rust core process, implementing
//! the `psc.*` API. Contract: `design/hooks.md`.

mod api;
mod bindings;
mod helpers;
mod runner;
#[cfg(test)]
mod tests;

pub use runner::run_hook;

/// Append a timestamped hook error to `<log_dir>/error.log` (best-effort, never fails).
///
/// `context` identifies the failing completion/command path; `err` is the Lua error message.
/// The log rotates by age — see `append_log`.
pub fn log_hook_error(log_dir: &str, cmd: &str, path: &str, err: &mlua::Error) {
    use api::append_log;
    let now = crate::engine::hooks::api::now_local();
    let text = format!("[{now}] [{cmd}{path}] hook error: {err}\n");
    append_log(log_dir, "error", &text);
}

#[cfg(test)]
mod tests_log {
    use super::*;

    #[test]
    fn hook_error_log_roundtrip() {
        use std::io::Read;
        let dir = std::env::temp_dir().join(format!("psc-log-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let dir_s = dir.to_string_lossy().to_string();
        let err = mlua::Error::runtime("boom");
        log_hook_error(&dir_s, "npm", "/install", &err);
        let file = dir.join("error.log");
        let mut s = String::new();
        std::fs::File::open(&file)
            .unwrap()
            .read_to_string(&mut s)
            .unwrap();
        assert!(s.contains("hook error"), "log content: {s}");
        assert!(s.contains("boom"), "log content: {s}");
        assert!(s.contains("[npm/install]"), "log content: {s}");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
/// A parsed command token.
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(default)]
pub struct Token {
    pub text: String,
    /// command | option | value | unknown
    pub kind: String,
    /// Canonical name of a known command/option (None for unknown/value); repeat counting keys on it.
    pub canonical: Option<String>,
}

/// The token being typed (may be empty: after a space, a new argument starts).
#[derive(Debug, Clone, Default, serde::Deserialize)]
#[serde(default)]
pub struct Typing {
    /// Raw input text (kept as typed, possibly an alias).
    pub text: Option<String>,
    /// command | option | value | unknown
    pub kind: Option<String>,
    /// Canonical name (best-effort; an unfinished word usually has none).
    pub canonical: Option<String>,
    /// Whether the input starts with `-` (heuristic: looks like an option).
    pub option_like: bool,
}

/// Pre-parsed context passed to the Lua hook.
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(default)]
pub struct HookContext {
    /// Root command name.
    pub cmd: String,
    /// Subcommand path (without options/values): `git stash pop` → `["stash","pop"]`.
    pub path: Vec<String>,
    /// Typed layer chain: `(kind, canonical)` per context switch — commands always, options
    /// when they have a `next` array (even empty) or a non-empty `option` array. Drives
    /// `psc.on` location matching.
    pub layers: Vec<(String, String)>,
    pub typing: Typing,
    /// All completed options' **canonical** names, in order.
    pub opts: Vec<String>,
    /// Raw token list (kept for unusual cases).
    pub tokens: Vec<Token>,
    /// The current command's fully-resolved config: per-completion overrides, global config
    /// values, built-in defaults, and manifest `config` array defaults, merged in
    /// `build_candidate_items`.  Hooks receive the final value directly.
    pub config: serde_json::Value,
    /// Raw manifest text (parsed as JSON), so hooks can read static data (e.g. git config keys).
    #[serde(default)]
    pub manifest: serde_json::Value,
    /// Module-level data (psc completion only): local lists/aliases, remote list/meta, live config, colors.
    #[serde(default)]
    pub data: serde_json::Value,
    /// The module's current language (`en-US`/`zh-CN`); selects the entry of a localized tip table.
    #[serde(default)]
    pub language: String,
    /// Current working directory.
    pub cwd: String,
    /// Directory for `psc.log` debug output (module-managed temp dir); empty = disabled.
    #[serde(default)]
    pub log_dir: String,
}

impl Default for HookContext {
    fn default() -> Self {
        HookContext {
            cmd: String::new(),
            path: Vec::new(),
            layers: Vec::new(),
            typing: Typing::default(),
            opts: Vec::new(),
            tokens: Vec::new(),
            config: serde_json::Value::Null,
            manifest: serde_json::Value::Null,
            data: serde_json::Value::Null,
            language: String::new(),
            cwd: String::new(),
            log_dir: String::new(),
        }
    }
}

/// Completion item (the exchange format between Lua and Rust).
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(default)]
#[derive(Default)]
pub struct LuaItem {
    pub text: String,
    pub tip: Option<String>,
    pub usage: Option<String>,
    pub example: Option<String>,
    pub symbol: Option<String>,
    pub repeat: i32,
}

impl From<&crate::engine::completion::CompletionItem> for LuaItem {
    fn from(it: &crate::engine::completion::CompletionItem) -> Self {
        LuaItem {
            text: it.text.clone(),
            tip: it.tip.clone(),
            usage: it.usage.clone(),
            example: it.example.clone(),
            symbol: it.symbol.clone(),
            repeat: it.repeat,
        }
    }
}
