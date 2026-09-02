use crate::menu::filter::filter_items;
use crate::menu::model::{Config, Item, TerminalInfo};
use std::collections::{HashMap, HashSet};

/// Result of applying a filter change.
pub enum FilterOutcome {
    /// No special action: the menu continues normally.
    None,
    /// Triggered by `enable_apply_when_no_match`: close the menu and insert the filter
    /// text into the command line.
    Input(String),
}

/// Where the description (tip) window is placed relative to the list window.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TipPlacement {
    /// No tip window.
    None,
    /// Below the list window.
    Below,
    /// Above the list window.
    Above,
}

/// No gap row between list and description (the border separates them).
pub const TIP_GAP: i32 = 0;
/// Description box heights: content lines + 2 borders (extreme/compact/tight/ample tiers).
pub const TIP_1_BOX: i32 = 3;
pub const TIP_2_BOX: i32 = 4;
pub const TIP_4_BOX: i32 = 6;
pub const TIP_5_BOX: i32 = 7;
/// Absolute minimum menu rows (filter row + count row + 1 item).
pub const MENU_MIN: i32 = 3;
/// Minimum menu rows when the description is shown (2 non-item rows + 3 items).
pub const MENU_MIN_WITH_TIP: i32 = 5;

/// Minimum space needed below the cursor; below it the alternate screen is used.
pub fn below_required(has_tip: bool) -> i32 {
    MENU_MIN_WITH_TIP + if has_tip { TIP_4_BOX } else { 0 }
}

/// How many rows the menu occupies for `count` candidates in `available` rows, with (or
/// without) a description box. The single source of truth for height allocation — the app layer
/// uses it to decide whether `auto` fits below before rendering, so the decision and the layout
/// can never disagree (no "try inline, retry alternate" loop).
pub fn layout_height(count: usize, available: i32, has_tip: bool) -> i32 {
    let count = count as i32;
    let list_limit: i32 = 12; // ui_height includes filter/count rows (+2), so at most 10 items are shown
    let base_height = (count + 2).min(list_limit).min(available);
    if !has_tip {
        return base_height;
    }
    let items_with_4 = available - 2 - TIP_4_BOX; // items fitting next to a 4-line description
                                                  // Floors: the 4/2-line tiers keep 3 items (never padding empty rows); the
                                                  // 1-line tier lets the list drop to 1 item to keep the description.
    let floor3 = (count + 2).min(MENU_MIN_WITH_TIP);
    let floor1 = (count + 2).min(MENU_MIN);
    if items_with_4 >= 8 {
        (count + 2)
            .min(list_limit)
            .min(available - TIP_5_BOX)
            .max(floor3)
    } else if available >= MENU_MIN_WITH_TIP + TIP_4_BOX {
        (count + 2)
            .min(list_limit)
            .min(available - TIP_4_BOX)
            .max(floor3)
    } else if available >= MENU_MIN_WITH_TIP + TIP_2_BOX {
        (count + 2)
            .min(list_limit)
            .min(available - TIP_2_BOX)
            .max(floor3)
    } else if available >= MENU_MIN + TIP_1_BOX {
        (count + 2)
            .min(list_limit)
            .min(available - TIP_1_BOX)
            .max(floor1)
    } else {
        base_height
    }
}

/// Cached description data for a single completion item (resolved on demand by the
/// PowerShell tip resolver). Assembled as `[Usage] / [Description] / [Example]` sections
/// when the menu is displayed.
#[derive(Debug, Clone, Default)]
pub struct CachedTip {
    pub tip: String,
    pub usage: String,
    pub example: String,
}

impl CachedTip {
    /// Assemble display lines `(is section header, text)`. Respects
    /// `enable_tip_usage` / `enable_tip_example`; `[Description]` is the tip body and is
    /// shown whenever `enable_tip` is on and there is content.
    pub fn display_lines(
        &self,
        enable_tip_usage: bool,
        enable_tip_example: bool,
    ) -> Vec<(bool, String)> {
        let mut lines: Vec<(bool, String)> = Vec::new();
        let mut push = |header: &str, content: &str, enabled: bool| {
            let content = content.trim();
            if enabled && !content.is_empty() {
                lines.push((true, header.to_string()));
                for l in content.lines() {
                    lines.push((false, l.to_string()));
                }
            }
        };
        push("[Usage]", &self.usage, enable_tip_usage);
        push("[Description]", &self.tip, true);
        push("[Example]", &self.example, enable_tip_example);
        lines
    }

    /// Whether anything is displayable under the current switches (decides whether to
    /// yield height to the description).
    pub fn has_display(&self, enable_tip_usage: bool, enable_tip_example: bool) -> bool {
        !self
            .display_lines(enable_tip_usage, enable_tip_example)
            .is_empty()
    }
}

/// Remove ANSI escape sequences (CSI: `ESC [ params final-byte`) so text renders cleanly.
fn strip_ansi(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '\u{1b}' {
            out.push(c);
            continue;
        }
        if chars.peek() == Some(&'[') {
            chars.next();
            for c2 in chars.by_ref() {
                if ('\u{40}'..='\u{7e}').contains(&c2) {
                    break;
                }
            }
        }
    }
    out
}

pub struct MenuState {
    pub items: Vec<Item>,
    pub filtered: Vec<usize>,
    pub filter: String,
    /// Cursor position within the filter text (**char index**, 0 = start); movable left/
    /// right while editing, with insert/delete in the middle.
    pub cursor: usize,
    pub is_prefix: bool,
    pub selected: usize,
    pub page_current: usize,
    pub offset: usize,

    pub ui_height: u16,
    pub pos: (u16, u16),
    pub is_show_above: bool,
    pub tip_placement: TipPlacement,
    pub page_max: usize,
    pub cursor_to_top: i32,
    pub cursor_to_bottom: i32,
    pub content_box: Vec<String>,
    pub min_area: bool,
    /// Whether filtering uses subsequence matching (from config; needed when rendering match highlights).
    pub use_subsequence: bool,
    /// Hint text shown after `>` when the filter is empty (from the psc completion's info, localized).
    pub filter_hint: String,
    pub enable_apply_when_no_match: bool,
    /// Whether the current filter is in a no-match state (the render layer shows the
    /// solid circle based on this; it is also the "previous state" the commit relies on).
    pub no_match: bool,
    /// Whether the selected row's peek is still in flight.
    pub peek_pending: bool,
    /// Rows whose peek result has already been computed and written back into
    /// `items[i].symbol`. Within one menu session a row's symbol is fixed (it depends
    /// only on the manifest and the row's own text), so re-selecting a row after
    /// moving up/down must not recompute it.
    pub peeked: Vec<bool>,
    /// Whether the last filter operation was a character insertion (insert, at any
    /// position including append at the end): with the solid-circle warning (no match),
    /// any character insertion triggers a commit; deletions (Backspace/Delete) and the
    /// `^` prefix toggle do not (used to recover / switch match mode).
    pub last_insert: bool,
    /// Cursor position before the current edit (insert/delete/prefix toggle): when a
    /// non-matching filter reverts to the last valid one, the cursor is restored to this
    /// pre-edit position (otherwise a failed insert looks like "the cursor moved right").
    pub prev_edit_cursor: usize,
    /// Lazily-resolved tooltips, keyed by item index into `items`.
    pub tip_cache: HashMap<usize, CachedTip>,
    /// Whether the description area shows `[Usage]` / `[Example]` sections (from config;
    /// used at render time).
    pub enable_tip_usage: bool,
    pub enable_tip_example: bool,
    /// Scroll offset inside the description container (0 = top). Reset when switching items.
    pub tip_scroll: usize,
    /// Maximum scroll offset when the description is scrollable (0 = not scrollable);
    /// updated by draw_tip.
    pub tip_scroll_max: usize,
    /// Previous frame's description container rect (x, y, w, h), used for mouse-wheel hit
    /// testing; None when there is no description.
    pub tip_box_rect: Option<(u16, u16, u16, u16)>,
    /// Row range covered this session (union across frames), for PowerShell's minimal restore.
    pub covered_top: u16,
    pub covered_bottom: u16,
    /// Whether the blinking cursor is currently in its "on" phase (flipped by the main
    /// loop over time; render reads it to decide whether to draw the bar).
    pub cursor_on: bool,

    /// Terminal cells already force-cleared this session (coordinates): clear_rect uses
    /// `AlwaysUpdate` to force-emit a blank and erase stale content only on the **first**
    /// cover of a cell, then falls back to the normal diff. This avoids the continuous
    /// output from force-resending every frame (VSCode re-detects links repeatedly → the
    /// hover underline flickers).
    pub cleaned: HashSet<(u16, u16)>,

    prev_filter: String,
    prev_filtered: Vec<usize>,
    prev_selected: usize,
}

impl MenuState {
    pub fn new(items: Vec<Item>, cfg: &Config, term: &TerminalInfo) -> MenuState {
        let count = items.len();
        let mut s = MenuState {
            filtered: (0..count).collect(),
            items,
            filter: String::new(),
            cursor: 0,
            is_prefix: false,
            selected: 0,
            page_current: 0,
            offset: 0,
            ui_height: 0,
            pos: (0, 0),
            is_show_above: false,
            tip_placement: TipPlacement::None,
            page_max: 0,
            cursor_to_top: 0,
            cursor_to_bottom: 0,
            content_box: Vec::new(),
            min_area: false,
            use_subsequence: cfg.flags.filter_mode == "subsequence",
            enable_tip_usage: cfg.flags.enable_tip_usage,
            enable_tip_example: cfg.flags.enable_tip_example,
            filter_hint: cfg.filter_hint.clone(),
            enable_apply_when_no_match: cfg.flags.enable_apply_when_no_match,
            no_match: false,
            peek_pending: false,
            peeked: vec![false; count],
            last_insert: false,
            prev_edit_cursor: 0,
            tip_cache: HashMap::new(),
            tip_scroll: 0,
            tip_scroll_max: 0,
            tip_box_rect: None,
            covered_top: u16::MAX,
            covered_bottom: 0,
            cursor_on: true,
            cleaned: HashSet::new(),
            prev_filter: String::new(),
            prev_filtered: Vec::new(),
            prev_selected: 0,
        };
        s.prev_filtered = s.filtered.clone();
        // Strip ANSI escapes from the list text here too, so all escape handling lives in the engine.
        for it in s.items.iter_mut() {
            it.list_item_text = strip_ansi(&it.list_item_text);
        }
        // Tips come with the items (resolved by the host shell). Cache only real content:
        // an empty/absent tip stays unresolved so the layout keeps its optimistic "a tip
        // may appear" assumption.
        for (i, it) in s.items.iter().enumerate() {
            let cached = CachedTip {
                tip: strip_ansi(it.tip.as_deref().unwrap_or_default()),
                usage: strip_ansi(it.usage.as_deref().unwrap_or_default()),
                example: strip_ansi(it.example.as_deref().unwrap_or_default()),
            };
            if cached.has_display(s.enable_tip_usage, s.enable_tip_example) {
                s.tip_cache.insert(i, cached);
            }
        }
        s.recompute_layout(cfg, term);
        s
    }

    /// Prefill the filter box (e.g. `^<pending>`) and filter the list, cursor at the end.
    pub fn with_initial_filter(&mut self, filter: &str, cfg: &Config, term: &TerminalInfo) {
        if filter.is_empty() {
            return;
        }
        self.filter = filter.to_string();
        let matched = filter_items(&self.items, &self.filter, filter.starts_with('^'), cfg);
        if matched.is_empty() {
            self.filtered = Vec::new();
            self.selected = 0;
            return;
        }
        self.last_insert = true;
        self.apply_filter(cfg, term);
        self.cursor = self.char_count();
        self.ensure_cursor_bounds();
    }

    pub fn selected_item_index(&self) -> Option<usize> {
        self.filtered.get(self.selected).copied()
    }

    pub fn selected_tip(&self) -> Option<&CachedTip> {
        let idx = self.selected_item_index()?;
        self.tip_cache.get(&idx)
    }

    /// Display lines `(is section header, text)` for the current selection; empty when not cached.
    pub fn selected_tip_lines(&self) -> Vec<(bool, String)> {
        match self.selected_item_index() {
            Some(idx) => self
                .tip_cache
                .get(&idx)
                .map(|t| t.display_lines(self.enable_tip_usage, self.enable_tip_example))
                .unwrap_or_default(),
            None => Vec::new(),
        }
    }

    pub fn tip_cached(&self, idx: usize) -> bool {
        self.tip_cache.contains_key(&idx)
    }

    /// Insert the prefix marker `^` at the start of the filter text (cursor lands right
    /// after it, ready for more prefix input). Only called by the key handler when there
    /// is no prefix yet and the cursor is at the start; a `^` anywhere else is inserted
    /// as an ordinary character.
    pub fn make_prefix(&mut self) {
        self.prev_edit_cursor = self.cursor;
        self.filter.insert(0, '^');
        self.cursor = 1;
        self.last_insert = false; // the `^` prefix is a mode switch, not a commit trigger (refilter after)
    }

    // ---------- Filter text cursor editing ----------

    /// Byte offset corresponding to the cursor (char index).
    pub fn filter_cursor_byte(&self) -> usize {
        self.filter
            .char_indices()
            .nth(self.cursor)
            .map(|(b, _)| b)
            .unwrap_or(self.filter.len())
    }

    fn char_count(&self) -> usize {
        self.filter.chars().count()
    }

    fn ensure_cursor_bounds(&mut self) {
        self.cursor = self.cursor.min(self.char_count());
    }

    /// Insert a character at the cursor (the boundary between characters).
    pub fn insert_at_cursor(&mut self, c: char) {
        self.prev_edit_cursor = self.cursor;
        let byte = self.filter_cursor_byte();
        // Any-position insert (append/middle/front) counts as an "insert": with the
        // solid-circle warning, the next insert commits.
        self.last_insert = true;
        self.filter.insert(byte, c);
        self.cursor += 1;
    }

    /// Delete the character before the cursor (Backspace).
    pub fn backspace_at_cursor(&mut self) {
        if self.cursor == 0 {
            return;
        }
        self.prev_edit_cursor = self.cursor;
        self.cursor -= 1;
        let byte = self.filter_cursor_byte();
        let ch = self.filter[byte..].chars().next().unwrap();
        self.filter.drain(byte..byte + ch.len_utf8());
        // A deletion is an edit (not an append): when nothing matches, the buffer is used
        // up directly (apply_filter handles this), so editing backwards does not keep
        // accumulating and accidentally trigger the forced apply.
        self.last_insert = false;
    }

    /// Delete the character after the cursor (Delete) — the cursor sits between characters,
    /// so this removes the first char to its right.
    pub fn delete_at_cursor(&mut self) {
        if self.cursor >= self.char_count() {
            return;
        }
        self.prev_edit_cursor = self.cursor;
        let byte = self.filter_cursor_byte();
        let ch = self.filter[byte..].chars().next().unwrap();
        self.filter.drain(byte..byte + ch.len_utf8());
        // Same as backspace_at_cursor: a deletion is an edit (not an append).
        self.last_insert = false;
    }

    pub fn move_cursor_left(&mut self) {
        if self.cursor > 0 {
            self.cursor -= 1;
        }
    }

    pub fn move_cursor_right(&mut self) {
        if self.cursor < self.char_count() {
            self.cursor += 1;
        }
    }

    pub fn move_cursor_home(&mut self) {
        self.cursor = 0;
    }

    pub fn move_cursor_end(&mut self) {
        self.cursor = self.char_count();
    }

    /// Apply the current `filter` against the full item list and update the
    /// selection/layout. Returns a special action when the user should be
    /// forced to accept the filter text.
    pub fn apply_filter(&mut self, cfg: &Config, term: &TerminalInfo) -> FilterOutcome {
        self.is_prefix = self.filter.starts_with('^');
        // If the revert lands back on the pre-filter list, keep the pre-filter selection
        // instead of prev_selected (which may be stale, e.g. still 0).
        let before_filtered = self.filtered.clone();
        let before_selected = self.selected;
        let matched = filter_items(&self.items, &self.filter, self.is_prefix, cfg);
        if matched.is_empty() {
            if cfg.flags.enable_apply_when_no_match {
                // Warning on first no-match; the next append commits. Edits (deletion /
                // middle insert) do not commit so they can recover to a match.
                if self.no_match && self.last_insert {
                    // Strip only the one mode-switch `^`; extra user-typed carets are literal.
                    let text = self
                        .filter
                        .strip_prefix('^')
                        .unwrap_or(&self.filter)
                        .to_string();
                    self.no_match = false;
                    self.filtered = self.prev_filtered.clone();
                    self.selected = if self.prev_filtered == before_filtered {
                        before_selected
                    } else {
                        self.prev_selected
                    }
                    .min(self.filtered.len().saturating_sub(1));
                    self.recompute_layout(cfg, term);
                    return FilterOutcome::Input(text);
                }
                self.no_match = true;
                self.filtered = self.prev_filtered.clone();
                self.selected = if self.prev_filtered == before_filtered {
                    before_selected
                } else {
                    self.prev_selected
                }
                .min(self.filtered.len().saturating_sub(1));
                self.recompute_layout(cfg, term);
                return FilterOutcome::None;
            }
            // Revert to the last valid filter and restore the pre-edit cursor position.
            self.filter = self.prev_filter.clone();
            self.is_prefix = self.filter.starts_with('^');
            self.no_match = false;
            self.filtered = self.prev_filtered.clone();
            self.selected = if self.prev_filtered == before_filtered {
                before_selected
            } else {
                self.prev_selected
            }
            .min(self.filtered.len().saturating_sub(1));
            self.cursor = self.prev_edit_cursor.min(self.char_count());
            self.recompute_layout(cfg, term);
            return FilterOutcome::None;
        }
        // prev_filtered must track prev_filter (this matched set), or a no-match revert
        // would pair the old filter text with the previous match set — a list jump with
        // no filter change. An unchanged match set keeps the selection position.
        self.no_match = false;
        let unchanged = matched == self.prev_filtered;
        self.prev_filter = self.filter.clone();
        self.prev_selected = before_selected;
        self.filtered = matched.clone();
        self.prev_filtered = matched;
        self.selected = if unchanged {
            before_selected.min(self.filtered.len().saturating_sub(1))
        } else {
            0
        };
        self.offset = 0;
        self.tip_scroll = 0;
        self.recompute_layout(cfg, term);
        FilterOutcome::None
    }

    /// Move the selection by one; scrolls the window when moving past the visible rows.
    pub fn move_selection(&mut self, is_down: bool, cfg: &Config) {
        let count = self.filtered.len();
        if count == 0 {
            return;
        }
        let dir: isize = if is_down { 1 } else { -1 };
        let new_selected = self.selected as isize + dir;
        self.selected = if cfg.flags.enable_list_loop {
            (((new_selected % count as isize) + count as isize) % count as isize) as usize
        } else {
            new_selected.clamp(0, count as isize - 1) as usize
        };
        self.tip_scroll = 0;
        self.update_window();
    }

    /// Jump to an absolute filtered index (mouse click). Clamps unless loop is enabled.
    pub fn jump(&mut self, index: usize, cfg: &Config) {
        let count = self.filtered.len();
        if count == 0 {
            return;
        }
        self.selected = if cfg.flags.enable_list_loop {
            index % count
        } else {
            index.min(count - 1)
        };
        self.tip_scroll = 0;
        self.update_window();
    }

    /// Record that a row range was drawn (menu/description/gap), unioned across frames for
    /// PowerShell's minimal restore.
    pub fn mark_covered(&mut self, top: u16, bottom: u16) {
        self.covered_top = self.covered_top.min(top);
        self.covered_bottom = self.covered_bottom.max(bottom);
    }

    /// Whether any covered range has been recorded (any frame drew the menu).
    pub fn has_covered(&self) -> bool {
        self.covered_top != u16::MAX
    }

    /// Scroll the description box by `delta` lines (used when the mouse wheel is over the
    /// description area).
    pub fn scroll_tip(&mut self, delta: i32) {
        let max = self.tip_scroll_max;
        self.tip_scroll = ((self.tip_scroll as i32 + delta).clamp(0, max as i32)) as usize;
    }

    /// Keep the selected row inside the visible window; scroll when needed.
    fn update_window(&mut self) {
        let count = self.filtered.len();
        if count <= self.page_max + 1 {
            self.page_current = self.selected;
            self.offset = 0;
            return;
        }
        if self.selected < self.offset {
            self.offset = self.selected;
            self.build_content_box();
        } else if self.selected > self.offset + self.page_max {
            self.offset = self.selected - self.page_max;
            self.build_content_box();
        }
        self.page_current = self.selected - self.offset;
    }

    /// Recompute geometry (ui_height, pos, tip_placement, page_max, content_box).
    fn recompute_layout(&mut self, cfg: &Config, term: &TerminalInfo) {
        let buffer_h = term.buffer.h as i32;
        let cursor_y = term.cursor.y as i32;
        let count = self.filtered.len() as i32;

        let cursor_to_top = (cursor_y - 1).max(0);
        let cursor_to_bottom = (buffer_h - cursor_y - 1).max(0);

        // Clip to the visible window (BufferSize spans the whole scrollback).
        let visible_above = match &term.window {
            Some(w) => (cursor_y - w.top).max(0),
            None => cursor_to_top,
        };
        let visible_below = match &term.window {
            Some(w) => (w.top + w.h - 1 - cursor_y).max(0),
            None => cursor_to_bottom,
        };
        let available_above = cursor_to_top.min(visible_above);
        let available_below = cursor_to_bottom.min(visible_below);

        // `altscreen-top` pins to the top (never flips); `altscreen-bottom` pins to the bottom
        // (always flips above, so the menu grows upward from the last row); `auto` in its inline
        // form also pins below (it only renders inline when there is room below, else the app
        // layer switched it to `altscreen-follow` on the alternate screen). `inline-follow` and
        // `altscreen-follow` balance above/below by available space.
        let show_mode = cfg.flags.show_mode.as_str();
        let force_below = matches!(show_mode, "auto" | "altscreen-top");
        let force_above = matches!(show_mode, "altscreen-bottom");
        let is_show_above = if force_below {
            false
        } else if force_above {
            true
        } else {
            available_above > available_below
        };

        let pos_x = 0;

        let has_tip = cfg.flags.enable_tip
            && match self.selected_item_index() {
                Some(idx) => match self.tip_cache.get(&idx) {
                    Some(t) => t.has_display(self.enable_tip_usage, self.enable_tip_example),
                    // Unresolved: optimistically assume a tip to avoid first-frame layout jumps.
                    None => true,
                },
                None => false,
            };
        let tip_placement = if has_tip {
            if is_show_above {
                TipPlacement::Above
            } else {
                TipPlacement::Below
            }
        } else {
            TipPlacement::None
        };

        // Height allocation: description tiers step down with available space (5 → 4 → 2
        // → 1 content line → none); the list keeps its minimum first, then grows. Surplus
        // height past the item cap goes to the (scrollable) description.
        let available = if is_show_above {
            available_above
        } else {
            available_below
        };

        let ui_height = layout_height(count as usize, available, has_tip);

        if ui_height < MENU_MIN {
            self.min_area = true;
            return;
        }
        self.min_area = false;

        let pos_y = if is_show_above {
            (cursor_y - ui_height).max(0)
        } else {
            cursor_y + 1
        };

        self.tip_placement = tip_placement;
        self.ui_height = ui_height as u16;
        self.pos = (pos_x.max(0) as u16, pos_y.max(0) as u16);
        self.is_show_above = is_show_above;
        self.cursor_to_top = cursor_to_top;
        self.cursor_to_bottom = cursor_to_bottom;
        self.page_max = (ui_height - 3).max(0) as usize;
        self.page_current = self.selected.min(self.page_max);
        self.offset = self.offset.min(self.filtered.len().saturating_sub(1));
        self.build_content_box();
    }

    /// Handle terminal resize: update dimensions and recompute layout.
    pub fn resize(&mut self, cfg: &Config, term: &mut TerminalInfo, new_w: u16, new_h: u16) {
        term.buffer.w = new_w;
        if let Some(ref mut w) = term.window {
            w.h = new_h as i32;
        }
        self.covered_top = 0;
        self.covered_bottom = 0;
        self.recompute_layout(cfg, term);
    }

    fn build_content_box(&mut self) {
        let rows = self.page_max + 1;
        let mut box_rows = Vec::with_capacity(rows);
        for r in 0..rows {
            let idx = self.offset + r;
            if idx < self.filtered.len() {
                box_rows.push(self.items[self.filtered[idx]].list_item_text.clone());
            } else {
                box_rows.push(String::new());
            }
        }
        self.content_box = box_rows;
    }
}

/// Byte ranges `[start, end)` of `text` matching the filter (for match highlighting).
/// Empty filter / no match → empty. Adjacent hits merge into one segment; a `^` prefix
/// requires the match to start at 0. Only literal parts are highlighted (`m*n` → `m`, `n`).
pub fn match_segments(
    text: &str,
    filter: &str,
    is_prefix: bool,
    use_subsequence: bool,
) -> Vec<(usize, usize)> {
    if filter.is_empty() {
        return Vec::new();
    }
    // Mode/pattern resolution mirrors filter_items (only one leading `^` is the marker).
    let actual = filter.strip_prefix('^').unwrap_or(filter);
    if actual.is_empty() {
        return Vec::new();
    }
    let (use_subseq, pattern) = if use_subsequence {
        (true, actual)
    } else if actual.starts_with("**") {
        (false, actual)
    } else if let Some(rest) = actual.strip_prefix('*') {
        (true, rest)
    } else {
        (false, actual)
    };
    if use_subseq {
        let pat: Vec<char> = pattern.chars().collect();
        let mut pi = 0;
        let mut positions: Vec<(usize, usize)> = Vec::new();
        for (idx, tc) in text.char_indices() {
            if pi < pat.len() && pat[pi].eq_ignore_ascii_case(&tc) {
                positions.push((idx, idx + tc.len_utf8()));
                pi += 1;
                if pi == pat.len() {
                    break;
                }
            }
        }
        if pi < pat.len() {
            return Vec::new();
        }
        if is_prefix {
            if let Some((s, _)) = positions.first() {
                if *s != 0 {
                    return Vec::new();
                }
            }
        }
        // Merge adjacent segments
        let mut merged: Vec<(usize, usize)> = Vec::new();
        for (s, e) in positions {
            if let Some(last) = merged.last_mut() {
                if last.1 == s {
                    last.1 = e;
                    continue;
                }
            }
            merged.push((s, e));
        }
        merged
    } else {
        crate::menu::filter::wildcard_segments(text, pattern, is_prefix).unwrap_or_default()
    }
}

#[cfg(test)]
mod tests;
