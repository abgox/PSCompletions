use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Input {
    #[serde(default)]
    pub items: Vec<Item>,
    pub config: Config,
    pub terminal: TerminalInfo,
    #[serde(default)]
    pub order: Option<OrderInfo>,
    /// Order-cache directory (module temp dir) — the engine prunes stale order files on menu open.
    #[serde(default)]
    pub order_dir: String,
    /// Menu temp directory — the engine prunes stale input/output files (left by crashed sessions) on menu open.
    #[serde(default)]
    pub menu_dir: String,
    /// Prefilled filter (`^<token>` from an unfinished token; the menu opens already filtered).
    #[serde(default)]
    pub initial_filter: Option<String>,
    /// Manifest build context (`CompleteInput`), present when the host wants the engine to
    /// build the candidate items itself instead of passing them; used so the engine builds
    /// the candidates and renders the menu in a single process call.
    #[serde(default)]
    pub build: Option<serde_json::Value>,
}

/// Input for the background ordering computation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrderInfo {
    /// PSReadLine history file path.
    pub history: String,
    /// The current command name.
    pub cmd: String,
    /// The command's aliases (including the name itself), used to recognize the command in
    /// history lines.
    #[serde(default)]
    pub aliases: Vec<String>,
    /// Output path of the ordering result JSON.
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Item {
    /// Kept for the PowerShell-side contract; not read by the menu itself.
    #[serde(default)]
    #[allow(dead_code)]
    pub completion_text: String,
    #[serde(default)]
    pub list_item_text: String,
    /// Display char of the predict symbol (`~` / `?` / empty), pre-mapped by the PowerShell side.
    #[serde(default)]
    pub symbol: String,
    /// Description text resolved by the host shell, shown in the description box.
    #[serde(default)]
    pub tip: Option<String>,
    #[serde(default)]
    pub usage: Option<String>,
    #[serde(default)]
    pub example: Option<String>,
    /// Kept for the PowerShell-side contract; not read by the menu itself.
    #[serde(default)]
    #[allow(dead_code)]
    pub result_type: Option<i32>,
}

/// Menu config. Width/palette are gone; most fields are kept only as contract.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Config {
    /// Hint text shown after `>` when the filter is empty (from the psc completion's info, localized).
    #[serde(default)]
    pub filter_hint: String,
    /// Stale hint appended to filter_hint when last_check is stale (from the psc completion's info, localized).
    #[serde(default)]
    pub filter_hint_stale: String,
    #[serde(default)]
    pub flags: Flags,
    /// Predict-symbol characters for "switch" / "stay" items (from the module's context config).
    #[serde(default = "default_switch_symbol")]
    pub context_switch: String,
    #[serde(default = "default_stay_symbol")]
    pub context_stay: String,
    /// Raw config layers used to resolve the three tip toggles (`enable_tip` /
    /// `enable_tip_usage` / `enable_tip_example`) per-completion → global → default.
    /// `{ "completion": {...}, "global": {...}, "default": {...} }`; consumed once by
    /// `Config::resolve_tip_flags`.
    #[serde(default)]
    pub raw_config: Option<serde_json::Value>,
}

impl Config {
    pub fn resolve_tip_flags(&mut self) {
        let Some(raw) = self.raw_config.take() else {
            return;
        };
        // Config values are stored as `0`/`1` (numbers) by the CLI, so accept both numbers
        // and JSON booleans. A key absent from all three layers keeps the current flag value
        // (the serde default), matching the documented defaults.
        let pick = |key: &str| -> Option<bool> {
            for layer in ["completion", "global", "default"] {
                let v = raw.get(layer).and_then(|l| l.get(key));
                if let Some(b) = v.and_then(|v| v.as_bool()) {
                    return Some(b);
                }
                if let Some(n) = v.and_then(|v| v.as_i64()) {
                    return Some(n != 0);
                }
            }
            None
        };
        if let Some(v) = pick("enable_tip") {
            self.flags.enable_tip = v;
        }
        if let Some(v) = pick("enable_tip_usage") {
            self.flags.enable_tip_usage = v;
        }
        if let Some(v) = pick("enable_tip_example") {
            self.flags.enable_tip_example = v;
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Flags {
    #[serde(default = "default_true")]
    pub enable_list_loop: bool,
    /// `"subsequence"` / `"wildcard"` (see `design/filter-matching.md`).
    #[serde(default = "default_filter_mode")]
    pub filter_mode: String,
    #[serde(default = "default_true")]
    pub enable_tip: bool,
    #[serde(default = "default_true")]
    pub enable_tip_usage: bool,
    #[serde(default = "default_true")]
    pub enable_tip_example: bool,
    #[serde(default)]
    pub enable_apply_when_single: bool,
    #[serde(default)]
    pub enable_apply_when_no_match: bool,
    #[serde(default = "default_show_mode")]
    pub show_mode: String,
    #[serde(default = "default_color_focus")]
    pub color_focus: String,
    #[serde(default = "default_color_match")]
    pub color_match: String,
}

fn default_true() -> bool {
    true
}

fn default_show_mode() -> String {
    "auto".into()
}

fn default_filter_mode() -> String {
    "wildcard".into()
}

fn default_color_focus() -> String {
    "red".into()
}

fn default_color_match() -> String {
    "cyan".into()
}

fn default_switch_symbol() -> String {
    "~".into()
}

fn default_stay_symbol() -> String {
    "?".into()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalInfo {
    pub cursor: Pos,
    pub buffer: Size,
    /// Visible window (top/h); layout is clipped to it (BufferSize spans the whole scrollback).
    #[serde(default)]
    pub window: Option<Window>,
    #[serde(default)]
    pub platform: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Window {
    pub top: i32,
    pub h: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pos {
    #[allow(dead_code)]
    pub x: u16,
    pub y: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Size {
    pub w: u16,
    pub h: u16,
}

/// Response to a `REQ\t<index>` tip request: the resolved tip/usage/example text.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TipResponse {
    #[serde(default)]
    pub tip: String,
    #[serde(default)]
    pub usage: String,
    #[serde(default)]
    pub example: String,
}

#[derive(Debug, Serialize)]
pub struct Output {
    pub status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub index: Option<usize>,
    /// Selected item's completion text (build mode: the host has no item list to index into).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completion_text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result_type: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub is_show_above: Option<bool>,
    /// Exact covered row range, for PowerShell's minimal restore.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub covered_top: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub covered_bottom: Option<u16>,
    /// Whether the alternate screen was used (PowerShell then skips buffer save/restore).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub alternate: Option<bool>,
}

impl Output {
    pub fn selected(index: usize) -> Self {
        Output {
            status: "selected",
            index: Some(index),
            text: None,
            message: None,
            is_show_above: None,
            covered_top: None,
            covered_bottom: None,
            alternate: None,
            completion_text: None,
            result_type: None,
        }
    }

    pub fn cancel() -> Self {
        Output {
            status: "cancel",
            index: None,
            text: None,
            message: None,
            is_show_above: None,
            covered_top: None,
            covered_bottom: None,
            alternate: None,
            completion_text: None,
            result_type: None,
        }
    }

    pub fn input(text: String) -> Self {
        Output {
            status: "input",
            index: None,
            text: Some(text),
            message: None,
            is_show_above: None,
            covered_top: None,
            covered_bottom: None,
            alternate: None,
            completion_text: None,
            result_type: None,
        }
    }

    pub fn min_area() -> Self {
        Output {
            status: "min_area",
            index: None,
            text: None,
            message: None,
            is_show_above: None,
            covered_top: None,
            covered_bottom: None,
            alternate: None,
            completion_text: None,
            result_type: None,
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Output {
            status: "error",
            index: None,
            text: None,
            message: Some(message.into()),
            is_show_above: None,
            covered_top: None,
            covered_bottom: None,
            alternate: None,
            completion_text: None,
            result_type: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_tip_flags_layers() {
        let mut cfg = Config {
            raw_config: Some(serde_json::json!({
                "completion": { "enable_tip": false },
                "global": { "enable_tip_usage": false },
                "default": { "enable_tip": true, "enable_tip_usage": true, "enable_tip_example": true }
            })),
            ..Default::default()
        };
        cfg.resolve_tip_flags();
        // Per-completion overrides global.
        assert!(!cfg.flags.enable_tip);
        // Global overrides default.
        assert!(!cfg.flags.enable_tip_usage);
        // Only present in default → picked up.
        assert!(cfg.flags.enable_tip_example);
        // Raw layers are consumed.
        assert!(cfg.raw_config.is_none());
    }

    #[test]
    fn resolve_tip_flags_accepts_01_numbers() {
        // The CLI stores config booleans as 0/1 numbers, not JSON booleans.
        let mut cfg = Config {
            raw_config: Some(serde_json::json!({
                "default": { "enable_tip": 1, "enable_tip_usage": 1, "enable_tip_example": 0 }
            })),
            ..Default::default()
        };
        cfg.resolve_tip_flags();
        assert!(cfg.flags.enable_tip);
        assert!(cfg.flags.enable_tip_usage);
        assert!(!cfg.flags.enable_tip_example);
    }

    #[test]
    fn accepts_unknown_config_fields() {
        // Unknown config keys are ignored (forward/backward compatibility with the module).
        let json = r##"{
            "items": [{"completion_text":"a","list_item_text":"a","tip":"","result_type":16}],
            "config": {
                "flags": {
                    "enable_list_loop": true,
                    "filter_mode": "wildcard",
                    "enable_tip": true,
                    "enable_apply_when_single": false
                }
            },
            "terminal":{"cursor":{"x":0,"y":5},"buffer":{"w":120,"h":30},"platform":"windows"}
        }"##;
        let input: Input = serde_json::from_str(json).expect("parse with unknown fields");
        // Missing fields (old protocol) → flags default off.
        assert!(!input.config.flags.enable_apply_when_no_match);
    }

    #[test]
    fn tip_response_parses_usage_and_example() {
        let json = r##"{"tip":"desc","usage":"-f, --force","example":"cmd -f  # do it"}"##;
        let r: TipResponse = serde_json::from_str(json).unwrap();
        assert_eq!(r.tip, "desc");
        assert_eq!(r.usage, "-f, --force");
        assert_eq!(r.example, "cmd -f  # do it");
        // Missing fields (old protocol) also parse, defaulting to empty strings.
        let old: TipResponse = serde_json::from_str(r##"{"tip":"only"}"##).unwrap();
        assert_eq!(old.usage, "");
        assert_eq!(old.example, "");
    }

    #[test]
    fn flags_default_tip_sections_enabled() {
        let json = r##"{
            "items": [{"completion_text":"a","list_item_text":"a","tip":"","result_type":16}],
            "config": {
                "flags":{"enable_list_loop":true,"filter_mode":"wildcard","enable_tip":true,"enable_apply_when_single":false,"show_mode":"auto"}
            },
            "terminal":{"cursor":{"x":0,"y":5},"buffer":{"w":120,"h":30},"platform":"windows"}
        }"##;
        let input: Input = serde_json::from_str(json).unwrap();
        assert!(input.config.flags.enable_tip_usage);
        assert!(input.config.flags.enable_tip_example);
    }

    #[test]
    fn output_serializes_is_show_above() {
        let json_absent = serde_json::to_string(&Output::cancel()).unwrap();
        assert!(!json_absent.contains("is_show_above"));
        let mut o = Output::cancel();
        o.is_show_above = Some(true);
        let json_true = serde_json::to_string(&o).unwrap();
        assert!(json_true.contains("\"is_show_above\":true"));
        let mut o2 = Output::cancel();
        o2.is_show_above = Some(false);
        let json_false = serde_json::to_string(&o2).unwrap();
        assert!(json_false.contains("\"is_show_above\":false"));
    }
}
