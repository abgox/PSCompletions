//! PSCompletions completion engine + interactive menu (`psc-menu`).
//!
//! Domains:
//! - `engine`: completion tree/context resolution + Lua hook runtime.
//! - `menu`: interactive completion menu (ratatui TUI).

pub mod engine;
pub mod menu;

// Shared text helpers (BOM-tolerant reads) live in `psc-common`; re-exported so the
// established `psc_engine::strip_bom` / `crate::strip_bom` paths keep working.
pub use psc_common::strip_bom;
