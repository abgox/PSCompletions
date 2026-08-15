//! PSCompletions completion engine + interactive menu (`psc-menu`).
//!
//! Domains:
//! - `engine`: completion tree/context resolution + Lua hook runtime.
//! - `menu`: interactive completion menu (ratatui TUI).

pub mod engine;
pub mod menu;

/// Strip a leading UTF-8 BOM if present (legacy PowerShell 5.1-written JSON files
/// carry one, which breaks serde_json parsing).
pub fn strip_bom(s: &str) -> &str {
    s.strip_prefix('\u{feff}').unwrap_or(s)
}
