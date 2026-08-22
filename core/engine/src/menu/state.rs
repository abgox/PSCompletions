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
        term.buffer.h = new_h;
        if let Some(ref mut w) = term.window {
            w.h = (new_h as i32 - w.top).max(0);
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
mod tests {
    use super::*;
    use crate::menu::model::{Flags, Pos, Size};
    use ratatui::style::{Color, Modifier};

    fn cfg(loop_enabled: bool) -> Config {
        Config {
            filter_hint: String::new(),
            filter_hint_stale: String::new(),
            flags: Flags {
                enable_list_loop: loop_enabled,
                filter_mode: "wildcard".into(),
                enable_tip: false,
                enable_tip_usage: true,
                enable_tip_example: true,
                enable_apply_when_single: false,
                enable_apply_when_no_match: false,
                show_mode: "auto".into(),
                color_focus: "red".into(),
                color_match: "cyan".into(),
            },
            context_switch: "~".into(),
            context_stay: "?".into(),
            raw_config: None,
        }
    }

    fn items(n: usize) -> Vec<Item> {
        (0..n)
            .map(|i| Item {
                completion_text: format!("cmd{i}"),
                list_item_text: format!("cmd{i}"),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect()
    }

    #[test]
    fn strip_ansi_removes_csi_sequences() {
        assert_eq!(strip_ansi("\u{1b}[31mred\u{1b}[0m"), "red");
        assert_eq!(strip_ansi("plain text"), "plain text");
        assert_eq!(strip_ansi("\u{1b}[2Jclear"), "clear");
        assert_eq!(strip_ansi(""), "");
    }

    #[test]
    fn description_box_coverage_stays_always_update() {
        use crate::menu::model::Window;
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        c.flags.show_mode = "inline".into();
        let term = TerminalInfo {
            cursor: Pos { x: 0, y: 5 },
            buffer: Size { w: 120, h: 30 },
            window: Some(Window { top: 0, h: 30 }),
            platform: "windows".into(),
        };
        let mut s = MenuState::new(items(3), &c, &term);
        s.tip_cache.insert(
            0,
            CachedTip {
                tip: "A description long enough to draw the box".into(),
                usage: String::new(),
                example: String::new(),
            },
        );
        let backend = ratatui::backend::TestBackend::new(120, 30);
        let mut terminal = ratatui::Terminal::new(backend).unwrap();
        terminal
            .draw(|f| crate::menu::ui::render(f, &mut s, &term, &c))
            .unwrap();
        let buf = terminal.backend().buffer();
        // The description-box region must stay force-updated on the first frame; a cell.reset()
        // in draw_tip's clear would drop AlwaysUpdate and the history list would bleed through.
        let mut covered = false;
        for y in (s.pos.1 + s.ui_height)..29u16 {
            for x in 0..20u16 {
                let cell = &buf[(x, y)];
                if cell.symbol() == " "
                    && cell.diff_option == ratatui::buffer::CellDiffOption::AlwaysUpdate
                {
                    covered = true;
                    break;
                }
            }
            if covered {
                break;
            }
        }
        assert!(covered, "description-box coverage must stay AlwaysUpdate");
    }

    fn term() -> TerminalInfo {
        TerminalInfo {
            cursor: Pos { x: 0, y: 5 },
            buffer: Size { w: 120, h: 30 },
            window: None,
            platform: "windows".into(),
        }
    }

    #[test]
    fn desc_gets_four_content_lines_in_16_row_window() {
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        // Window height 16: top row 1 (0) + input row (1) → 14 rows (2..15) left for the
        // TUI. A 6-item menu at 8 rows + a 6-row description box (4 content lines) fills
        // exactly those 14 rows — the 4-line description baseline.
        let term = TerminalInfo {
            cursor: Pos { x: 0, y: 1 },
            buffer: Size { w: 120, h: 16 },
            window: Some(crate::menu::model::Window { top: 0, h: 16 }),
            platform: "windows".into(),
        };
        let s = MenuState::new(items(7), &c, &term);
        assert_eq!(s.ui_height, 8); // 6 items = 8 rows
        assert_eq!(s.pos.1, 2); // menu top sits below the input row
                                // desc content 4 lines: the box should appear right below the menu (no gap),
                                // height 6 (4 content lines + 2 borders)
        let mut s2 = MenuState::new(items(7), &c, &term);
        s2.tip_cache.insert(
            0,
            CachedTip {
                tip: "line1\nline2\nline3\nline4".into(),
                ..Default::default()
            },
        );
        let mut out: Vec<u8> = Vec::new();
        {
            let backend =
                ratatui::backend::CrosstermBackend::new(std::io::BufWriter::new(&mut out));
            let mut terminal = ratatui::Terminal::new(backend).unwrap();
            terminal
                .draw(|f| crate::menu::ui::render(f, &mut s2, &term, &c))
                .unwrap();
        }
        let box_rect = s2.tip_box_rect.unwrap();
        assert_eq!(box_rect.1, 10); // sits below the menu (2+8), no gap row
        assert_eq!(box_rect.3, 6); // 4 content lines + top/bottom borders; bottom reaches window bottom 15
    }

    #[test]
    fn jump_moves_selection_and_window() {
        let cfg = cfg(true);
        let mut s = MenuState::new(items(20), &cfg, &term());
        // 20 items, visible page = page_max+1
        let visible = s.page_max + 1;
        assert!(visible < 20);

        // jump to last -> window scrolled to the end
        s.jump(19, &cfg);
        assert_eq!(s.selected, 19);
        assert_eq!(s.page_current, s.page_max);
        assert!(s.offset > 0);

        // Home
        s.jump(0, &cfg);
        assert_eq!(s.selected, 0);
        assert_eq!(s.offset, 0);
        assert_eq!(s.page_current, 0);
    }

    #[test]
    fn move_selection_clamps_without_loop() {
        let cfg = cfg(false);
        let mut s = MenuState::new(items(5), &cfg, &term());
        s.jump(100, &cfg);
        assert_eq!(s.selected, 4);
        s.jump(0, &cfg);
        s.move_selection(true, &cfg);
        assert_eq!(s.selected, 1);
        s.move_selection(false, &cfg);
        assert_eq!(s.selected, 0);
        s.move_selection(false, &cfg);
        assert_eq!(s.selected, 0);
    }

    #[test]
    fn match_segments_substring_and_case() {
        assert_eq!(match_segments("add ~", "ad", false, false), vec![(0, 2)]);
        assert_eq!(match_segments("Add ~", "add", false, false), vec![(0, 3)]);
        assert_eq!(match_segments("commit ~", "mm", false, false), vec![(2, 4)]);
        assert_eq!(
            match_segments("add ~", "xx", false, false),
            Vec::<(usize, usize)>::new()
        );
    }

    #[test]
    fn match_segments_wildcards_highlight_literals() {
        // m*n: highlights m and n (the part consumed by the star wildcard is not highlighted)
        assert_eq!(
            match_segments("many", "m*n", false, false),
            vec![(0, 1), (2, 3)]
        );
        // Prefix mode with a wildcard: ^a*b → highlights a and b (adjacent, merged into one)
        assert_eq!(match_segments("ab", "^a*b", true, false), vec![(0, 2)]);
        // The star spans multiple characters
        assert_eq!(
            match_segments("m--n", "m*n", false, false),
            vec![(0, 1), (3, 4)]
        );
        // The literal star escaped by ** is also highlighted
        assert_eq!(match_segments("a*b", "a**b", false, false), vec![(0, 3)]);
        // Wildcard has no match → empty
        assert_eq!(
            match_segments("xyz", "m*n", false, false),
            Vec::<(usize, usize)>::new()
        );
        // Without a wildcard it still takes the first case-insensitive substring (regression)
        assert_eq!(match_segments("commit ~", "mm", false, false), vec![(2, 4)]);
    }

    #[test]
    fn match_segments_resolves_force_subsequence() {
        // Wildcard config + a leading `*` forces subsequence: highlights the chars hit in
        // subsequence order.
        assert_eq!(
            match_segments("xaybc", "*abc", false, false),
            vec![(1, 2), (3, 5)]
        );
        // Subsequence config + `^*abc`: `*` is literal and anchored by the prefix; the
        // whole "*abc" is highlighted.
        assert_eq!(match_segments("*abc", "^*abc", true, true), vec![(0, 4)]);
    }

    #[test]
    fn match_segments_subsequence_and_prefix() {
        // subsequence: b(0) then a(2) in "branch"
        assert_eq!(
            match_segments("branch ~", "ba", false, true),
            vec![(0, 1), (2, 3)]
        );
        // prefix subsequence: must start at 0
        assert_eq!(match_segments("branch ~", "^b", true, true), vec![(0, 1)]);
        assert_eq!(
            match_segments("branch ~", "^a", true, true),
            Vec::<(usize, usize)>::new()
        );
        // prefix substring
        assert_eq!(match_segments("add ~", "^a", true, false), vec![(0, 1)]);
    }

    #[test]
    fn height_allocation_adapts_to_terminal_size() {
        // Small terminal (6 rows, cursor on bottom row 5): 4 rows available above, not
        // enough for the description → the menu takes it all.
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        c.flags.show_mode = "inline".into(); // only inline allows flipping above
        let small = TerminalInfo {
            cursor: Pos { x: 0, y: 5 },
            buffer: Size { w: 120, h: 6 },
            window: None,
            platform: "windows".into(),
        };
        let s = MenuState::new(items(20), &c, &small);
        assert!(!s.min_area);
        assert!(s.is_show_above);
        // 4 rows available → items win: the menu fills all 4 rows (2 items), no description;
        // tip_placement stays optimistically Above, but draw_tip skips it for lack of space.
        assert_eq!(s.ui_height, 4);
        assert_eq!(s.tip_placement, TipPlacement::Above);

        // Medium terminal (10 rows, cursor on bottom row 9): 8 rows available → description
        // gets its extreme 1-line baseline, menu 5 rows (3 items).
        let med = TerminalInfo {
            cursor: Pos { x: 0, y: 9 },
            buffer: Size { w: 120, h: 10 },
            window: None,
            platform: "windows".into(),
        };
        let s2 = MenuState::new(items(20), &c, &med);
        assert!(!s2.min_area);
        assert_eq!(s2.ui_height, 5);
        assert_eq!(s2.tip_placement, TipPlacement::Above);

        // Taller terminal (11 rows, cursor on bottom row 10): 9 rows available → description
        // gets its compact 2-line baseline, menu 5 rows (3 items).
        let tall = TerminalInfo {
            cursor: Pos { x: 0, y: 10 },
            buffer: Size { w: 120, h: 11 },
            window: None,
            platform: "windows".into(),
        };
        let s4 = MenuState::new(items(20), &c, &tall);
        assert!(!s4.min_area);
        assert_eq!(s4.ui_height, 5);
        assert_eq!(s4.tip_placement, TipPlacement::Above);

        // Ample terminal (13 rows, cursor on bottom row 12): 11 rows available → description
        // gets its 4-line baseline, menu 5 rows (3 items).
        let ample = TerminalInfo {
            cursor: Pos { x: 0, y: 12 },
            buffer: Size { w: 120, h: 13 },
            window: None,
            platform: "windows".into(),
        };
        let s5 = MenuState::new(items(20), &c, &ample);
        assert!(!s5.min_area);
        assert_eq!(s5.ui_height, 5);
        assert_eq!(s5.tip_placement, TipPlacement::Above);

        // Description off: on the same terminal the menu takes all available space
        // (8 rows), showing more items.
        let mut c2 = cfg(false);
        c2.flags.enable_tip = false;
        c2.flags.show_mode = "inline".into();
        let s3 = MenuState::new(items(20), &c2, &med);
        assert!(!s3.min_area);
        assert_eq!(s3.ui_height, 8);
        assert_eq!(s3.tip_placement, TipPlacement::None);

        // Scarce terminal (7 rows available): description keeps its extreme 1 line, the
        // list drops to 2 items (the description is no longer cut).
        let scarce7 = TerminalInfo {
            cursor: Pos { x: 0, y: 8 },
            buffer: Size { w: 120, h: 9 },
            window: None,
            platform: "windows".into(),
        };
        let s6 = MenuState::new(items(20), &c, &scarce7);
        assert!(!s6.min_area);
        assert_eq!(s6.ui_height, 4); // 2 items + 1 description line
        assert_eq!(s6.tip_placement, TipPlacement::Above);

        // Scarce terminal (6 rows available): description keeps its extreme 1 line, the
        // list drops to 1 item.
        let scarce6 = TerminalInfo {
            cursor: Pos { x: 0, y: 7 },
            buffer: Size { w: 120, h: 8 },
            window: None,
            platform: "windows".into(),
        };
        let s7 = MenuState::new(items(20), &c, &scarce6);
        assert!(!s7.min_area);
        assert_eq!(s7.ui_height, 3); // 1 item + 1 description line
        assert_eq!(s7.tip_placement, TipPlacement::Above);
    }

    #[test]
    fn filter_no_match_keeps_selection_when_list_unchanged() {
        // User scenario: after selecting a later item, typing a non-matching char (X) →
        // the menu reverts to the full list (unchanged); the selection should stay at its
        // pre-filter position, not jump to the first item.
        let c = cfg(false);
        let mut s = MenuState::new(items(10), &c, &term());
        for _ in 0..4 {
            s.move_selection(true, &c);
        }
        assert_eq!(s.selected, 4);
        // cmd0..cmd9 contain no X → no match
        s.filter.push('X');
        s.apply_filter(&c, &term());
        assert_eq!(s.filtered.len(), 10);
        assert_eq!(s.selected, 4);
    }

    #[test]
    fn filter_keeps_selection_when_list_unchanged() {
        // The post-filter match set equals the previous one (the menu did not change) →
        // the selection is kept, not reset to the first item.
        let c = cfg(false);
        let mut s = MenuState::new(items(10), &c, &term());
        for _ in 0..4 {
            s.move_selection(true, &c);
        }
        assert_eq!(s.selected, 4);
        // Type filter "cmd" (matches all 10 items, same as the initial full list)
        s.filter.push_str("cmd");
        s.apply_filter(&c, &term());
        assert_eq!(s.filtered.len(), 10);
        assert_eq!(s.selected, 4); // list unchanged → selection kept
                                   // Switch to a filter that changes the list → jumps back to the first item
        s.filter.clear();
        s.filter.push_str("cmd5");
        s.apply_filter(&c, &term());
        assert_eq!(s.filtered.len(), 1);
        assert_eq!(s.selected, 0);
    }

    #[test]
    fn single_match_does_not_inflate_menu() {
        // Filter leaves exactly 1 item (and the selected item has a tip that triggers the
        // description branch): the menu height should be count+2 (3 rows = filter row +
        // count row + 1 item), not inflated to the 3-item floor with empty item rows.
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        c.flags.show_mode = "inline".into();
        let list: Vec<Item> = (0..20)
            .map(|i| Item {
                completion_text: format!("cmd{i}"),
                list_item_text: format!("cmd{i}"),
                tip: Some(format!("tip {i}")),
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect();
        let mut s = MenuState::new(list, &c, &term());
        s.filter.push_str("cmd3");
        s.apply_filter(&c, &term());
        assert_eq!(s.filtered.len(), 1);
        assert_eq!(s.ui_height, 3); // filter row + count row + 1 item
        assert!(s.content_box.iter().all(|l| !l.is_empty())); // no empty item rows
    }

    #[test]
    fn window_caps_available_space_for_huge_buffer() {
        // Huge buffer (3000 rows) but only a 30-row visible window: allocation must follow
        // the visible window, not sprawl across the whole buffer.
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        c.flags.show_mode = "inline".into();
        let term = TerminalInfo {
            cursor: Pos { x: 0, y: 2999 },
            buffer: Size { w: 100, h: 3000 },
            window: Some(crate::menu::model::Window { top: 2970, h: 30 }),
            platform: "windows".into(),
        };
        let s = MenuState::new(items(20), &c, &term);
        assert!(!s.min_area);
        assert!(s.is_show_above);
        // 29 visible rows → ample (a 4-line description fits ≥8 items) → description gets
        // its 5-line baseline (7-row box) → menu = min(20+2, 12, 29-7=22) = 12 (capped at 10 items)
        assert_eq!(s.ui_height, 12);
    }

    #[test]
    fn covered_tracks_rendered_rows() {
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        let term = term(); // cursor on row 5, 24 rows available below → the menu goes below
        let mut s = MenuState::new(items(10), &c, &term);
        assert!(!s.is_show_above);
        let backend = ratatui::backend::TestBackend::new(term.buffer.w, term.buffer.h);
        let mut terminal = ratatui::Terminal::new(backend).unwrap();
        terminal
            .draw(|f| crate::menu::ui::render(f, &mut s, &term, &c))
            .unwrap();
        // covered should span the menu rows [pos_y .. pos_y+ui_height-1] and not reach above cursor row 5.
        assert!(s.has_covered());
        assert!(s.covered_top <= s.pos.1);
        assert!(s.covered_bottom >= s.pos.1 + s.ui_height - 1);
        // Menu below: covered starts at >= cursor row + 1
        assert!(s.covered_top >= 6);
    }

    #[test]
    fn filter_cursor_editing() {
        let c = cfg(false);
        let term = term();
        let mut s = MenuState::new(items(10), &c, &term);
        // Append input: ab
        s.insert_at_cursor('a');
        s.insert_at_cursor('b');
        assert_eq!(s.filter, "ab");
        assert_eq!(s.cursor, 2);
        // Move to the start, insert c → cab
        s.move_cursor_home();
        s.insert_at_cursor('c');
        assert_eq!(s.filter, "cab");
        assert_eq!(s.cursor, 1);
        // Cursor between a and b? cab: cursor=1 is before 'a', move right to 2 (after a), insert d → cadb
        s.move_cursor_right();
        assert_eq!(s.cursor, 2);
        s.insert_at_cursor('d');
        assert_eq!(s.filter, "cadb");
        assert_eq!(s.cursor, 3);
        // Move left to 1 (after c), backspace deletes c → adb, cursor back to 0
        s.move_cursor_left();
        s.move_cursor_left();
        assert_eq!(s.cursor, 1);
        s.backspace_at_cursor();
        assert_eq!(s.filter, "adb");
        assert_eq!(s.cursor, 0);
        // Move right one (after a), Delete removes the 'd' right of the cursor → ab
        s.move_cursor_right();
        assert_eq!(s.cursor, 1);
        s.delete_at_cursor();
        assert_eq!(s.filter, "ab");
        assert_eq!(s.cursor, 1);
        // Out-of-range clamping
        s.move_cursor_home();
        for _ in 0..5 {
            s.move_cursor_left();
        }
        assert_eq!(s.cursor, 0);
        s.move_cursor_end();
        for _ in 0..5 {
            s.move_cursor_right();
        }
        assert_eq!(s.cursor, 2);
        s.delete_at_cursor();
        assert_eq!(s.filter, "ab"); // cursor already at the end; Delete has no effect
                                    // Backspace at the start has no effect (no cancel)
        s.move_cursor_home();
        s.backspace_at_cursor();
        assert_eq!(s.filter, "ab");
    }

    #[test]
    fn filter_cursor_handles_cjk() {
        let c = cfg(false);
        let term = term();
        let mut s = MenuState::new(items(10), &c, &term);
        s.insert_at_cursor('你');
        s.insert_at_cursor('好');
        assert_eq!(s.filter, "你好");
        assert_eq!(s.cursor, 2);
        // Cursor moves to 1 (before 好), insert 世 → 你世好
        s.move_cursor_home();
        s.move_cursor_right();
        s.insert_at_cursor('世');
        assert_eq!(s.filter, "你世好");
        assert_eq!(s.cursor, 2);
        // Backspace removes 世 → 你好
        s.backspace_at_cursor();
        assert_eq!(s.filter, "你好");
        assert_eq!(s.cursor, 1);
    }

    #[test]
    fn prefix_derived_from_filter_no_toggle() {
        let c = cfg(false);
        let term = term();
        let mut s = MenuState::new(items(10), &c, &term);
        // Typing ^ at the start → prefix, cursor lands right after it.
        s.make_prefix();
        s.apply_filter(&c, &term);
        assert_eq!(s.filter, "^");
        assert_eq!(s.cursor, 1);
        assert!(s.is_prefix);
        // With a prefix already, inserting ^ in the middle → prefix state is derived from
        // the filter, it will not flip back to normal mode.
        s.insert_at_cursor('^'); // filter="^^"
        s.apply_filter(&c, &term);
        // "^^" has no match (cmd* does not start with ^) → reverts to "^", still in prefix state.
        assert_eq!(s.filter, "^");
        assert!(s.is_prefix);
        // Deleting the leading ^ → prefix cleared (no "toggle" semantics anymore; deleting removes it).
        s.move_cursor_home();
        s.delete_at_cursor();
        s.apply_filter(&c, &term);
        assert_eq!(s.filter, "");
        assert!(!s.is_prefix);
    }

    #[test]
    fn with_initial_filter_no_match_closes_menu() {
        let c = cfg(false);
        let mut s = MenuState::new(items(10), &c, &term());
        s.with_initial_filter("^X", &c, &term());
        assert!(s.filtered.is_empty());
    }

    #[test]
    fn with_initial_filter_prefills_and_prefix_matches() {
        let c = cfg(false);
        let term = term();
        // The prefix `abyss/Microsoft.Power*` matches 3 items.
        let its = vec![
            Item {
                completion_text: "abyss/Microsoft.Edit".into(),
                list_item_text: "abyss/Microsoft.Edit".into(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            },
            Item {
                completion_text: "abyss/Microsoft.PowerShell".into(),
                list_item_text: "abyss/Microsoft.PowerShell".into(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            },
            Item {
                completion_text: "abyss/Microsoft.PowerShell.Preview".into(),
                list_item_text: "abyss/Microsoft.PowerShell.Preview".into(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            },
            Item {
                completion_text: "abyss/Microsoft.PowerToys".into(),
                list_item_text: "abyss/Microsoft.PowerToys".into(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            },
        ];
        let mut s = MenuState::new(its, &c, &term);
        s.with_initial_filter("^abyss/Microsoft.Power", &c, &term);
        // Prefix filtering keeps only the three abyss/Microsoft.Power* items (Edit is excluded).
        assert_eq!(s.filter, "^abyss/Microsoft.Power");
        assert!(s.is_prefix);
        assert_eq!(s.filtered.len(), 3);
        assert_eq!(
            s.items[s.filtered[0]].completion_text,
            "abyss/Microsoft.PowerShell"
        );
        assert_eq!(
            s.items[s.filtered[1]].completion_text,
            "abyss/Microsoft.PowerShell.Preview"
        );
        assert_eq!(
            s.items[s.filtered[2]].completion_text,
            "abyss/Microsoft.PowerToys"
        );
        // Cursor lands at the end, ready for more input.
        assert_eq!(s.cursor, s.filter.chars().count());
    }

    #[test]
    fn with_initial_filter_empty_keeps_full_list() {
        let c = cfg(false);
        let term = term();
        let mut s = MenuState::new(items(5), &c, &term);
        s.with_initial_filter("", &c, &term);
        assert_eq!(s.filtered.len(), 5);
        assert!(s.filter.is_empty());
    }

    #[test]
    fn below_required_threshold() {
        assert_eq!(crate::menu::state::below_required(true), 11); // 3 items + a 4-line description
        assert_eq!(crate::menu::state::below_required(false), 5); // 3 items
    }

    #[test]
    fn auto_inline_threshold_actually_fits_layout() {
        // `below_required` is the `auto` inline floor: at that space the menu must fit inline.
        // Guarantees the app-layer decision (inline vs alternate) and recompute_layout never
        // disagree, so `auto` never does an above-inline flip or a retry.
        for count in 1..=20 {
            let space = crate::menu::state::below_required(true);
            let h = crate::menu::state::layout_height(count as usize, space, true);
            assert!(
                h <= space,
                "count {count}: layout_height({h}) exceeds below_required({space})"
            );
        }
        for count in 1..=20 {
            let space = crate::menu::state::below_required(false);
            let h = crate::menu::state::layout_height(count as usize, space, false);
            assert!(
                h <= space,
                "count {count}: no-tip layout_height({h}) exceeds below_required({space})"
            );
        }
    }

    #[test]
    fn cached_tip_sections_respect_switches() {
        let t = CachedTip {
            usage: " -f, --force ".into(),
            tip: "Force action\nCan be repeated.".into(),
            example: "pkg i -f # install".into(),
        };
        // All on: Usage → Description → Example, headers first.
        let lines = t.display_lines(true, true);
        let headers: Vec<&str> = lines
            .iter()
            .filter(|(h, _)| *h)
            .map(|(_, l)| l.as_str())
            .collect();
        assert_eq!(headers, vec!["[Usage]", "[Description]", "[Example]"]);
        assert_eq!(lines.len(), 7); // 2 (usage) + 3 (description) + 2 (example)
                                    // usage off: the whole Usage section disappears; Description always shows
        let lines2 = t.display_lines(false, true);
        let headers2: Vec<&str> = lines2
            .iter()
            .filter(|(h, _)| *h)
            .map(|(_, l)| l.as_str())
            .collect();
        assert_eq!(headers2, vec!["[Description]", "[Example]"]);
        // All off (example too): only Description remains.
        let lines3 = t.display_lines(false, false);
        let headers3: Vec<&str> = lines3
            .iter()
            .filter(|(h, _)| *h)
            .map(|(_, l)| l.as_str())
            .collect();
        assert_eq!(headers3, vec!["[Description]"]);
        // has_display is true when only the description is present.
        assert!(t.has_display(false, false));
        // No description but the other sections switched off: nothing to show → has_display false.
        let empty = CachedTip {
            tip: String::new(),
            usage: "  ".into(),
            example: String::new(),
        };
        assert!(!empty.has_display(false, true));
        // Usage leading/trailing whitespace is trimmed: the content line = "-f".
        let padded = CachedTip {
            tip: String::new(),
            usage: "  -f  ".into(),
            example: String::new(),
        };
        let plines = padded.display_lines(true, false);
        assert_eq!(plines[0], (true, "[Usage]".to_string()));
        assert_eq!(plines[1], (false, "-f".to_string()));
    }

    #[test]
    fn sections_render_with_colored_desc_split() {
        // Real rendering: usage/example drawn into the description container, with the
        // `  # explanation` part in the secondary color (color layering, not alignment).
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        c.flags.enable_tip_usage = true;
        c.flags.enable_tip_example = true;
        c.flags.show_mode = "inline".into();
        let term = TerminalInfo {
            cursor: Pos { x: 0, y: 5 },
            buffer: Size { w: 120, h: 30 },
            window: None,
            platform: "windows".into(),
        };
        let mut s = MenuState::new(items(3), &c, &term);
        s.tip_cache.insert(
            0,
            CachedTip {
                tip: "Show info".into(),
                usage: "-f, --force".into(),
                example: "x demo.7z  # extract here".into(),
            },
        );
        let backend = ratatui::backend::TestBackend::new(term.buffer.w, term.buffer.h);
        let mut terminal = ratatui::Terminal::new(backend).unwrap();
        terminal
            .draw(|f| crate::menu::ui::render(f, &mut s, &term, &c))
            .unwrap();
        let buf = terminal.backend().buffer();
        let rows: Vec<String> = (0..term.buffer.h)
            .map(|y| {
                (0..term.buffer.w)
                    .map(|x| buf[(x, y)].symbol().to_string())
                    .collect()
            })
            .collect();
        let joined = rows.join("\n");
        assert!(joined.contains("[Usage]"), "missing [Usage]");
        assert!(joined.contains("[Description]"), "missing [Description]");
        assert!(joined.contains("[Example]"), "missing [Example]");
        // example row: cmd in the default color; the `# explanation` (code-comment style)
        // in the secondary color (STRUCT_C structural gray, not bold).
        let row_idx = rows
            .iter()
            .position(|r| r.contains("extract here"))
            .expect("example row");
        let row = &rows[row_idx];
        let hash_col = row.chars().position(|ch| ch == '#').expect("hash column");
        let hash_style = buf[(hash_col as u16, row_idx as u16)].style();
        assert_eq!(
            hash_style.fg,
            Some(Color::DarkGray),
            "# should be secondary color"
        );
        assert!(
            !hash_style.add_modifier.contains(Modifier::BOLD),
            "# should not be bold"
        );
        let cmd_col = row.chars().position(|ch| ch == 'x').expect("cmd column");
        assert_eq!(buf[(cmd_col as u16, row_idx as u16)].symbol(), "x");
        assert_ne!(
            buf[(cmd_col as u16, row_idx as u16)].style().fg,
            Some(Color::DarkGray),
            "cmd should not be secondary color"
        );
    }

    #[test]
    fn desc_split_keeps_color_on_wrapped_continuation() {
        // After a long desc wraps, the continuation rows keep the secondary color (the # explanation part).
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        c.flags.enable_tip_example = true;
        c.flags.show_mode = "inline".into();
        let term = TerminalInfo {
            cursor: Pos { x: 0, y: 5 },
            buffer: Size { w: 40, h: 30 }, // narrow terminal → forces wrapping
            window: None,
            platform: "windows".into(),
        };
        let mut s = MenuState::new(items(3), &c, &term);
        s.tip_cache.insert(
            0,
            CachedTip {
                tip: String::new(),
                usage: String::new(),
                example: "x demo.7z  # a very long description that will wrap onto the next line"
                    .into(),
            },
        );
        let backend = ratatui::backend::TestBackend::new(term.buffer.w, term.buffer.h);
        let mut terminal = ratatui::Terminal::new(backend).unwrap();
        terminal
            .draw(|f| crate::menu::ui::render(f, &mut s, &term, &c))
            .unwrap();
        let buf = terminal.backend().buffer();
        // Desc characters on the continuation row should be secondary (DarkGray).
        let mut wrapped = false;
        for y in 0..term.buffer.h {
            let line: String = (0..term.buffer.w)
                .map(|x| buf[(x, y)].symbol().to_string())
                .collect();
            if let Some(x) = line.find("will wrap") {
                assert_eq!(
                    buf[(x as u16, y)].style().fg,
                    Some(Color::DarkGray),
                    "wrapped desc continuation should stay dim"
                );
                wrapped = true;
            }
        }
        assert!(
            wrapped,
            "the long desc should have wrapped onto a continuation row"
        );
    }

    #[test]
    fn desc_split_ignores_bare_hash_in_command() {
        // A bare # in command text (no surrounding spaces) does not trigger splitting; only
        // ` # ` (a space on both sides) is a separator.
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        c.flags.enable_tip_example = true;
        c.flags.show_mode = "inline".into();
        let term = TerminalInfo {
            cursor: Pos { x: 0, y: 5 },
            buffer: Size { w: 120, h: 30 },
            window: None,
            platform: "windows".into(),
        };
        let mut s = MenuState::new(items(3), &c, &term);
        s.tip_cache.insert(
            0,
            CachedTip {
                tip: String::new(),
                usage: String::new(),
                example: "grep 'a#b' file  # show matches".into(),
            },
        );
        let backend = ratatui::backend::TestBackend::new(term.buffer.w, term.buffer.h);
        let mut terminal = ratatui::Terminal::new(backend).unwrap();
        terminal
            .draw(|f| crate::menu::ui::render(f, &mut s, &term, &c))
            .unwrap();
        let buf = terminal.backend().buffer();
        let rows: Vec<String> = (0..term.buffer.h)
            .map(|y| {
                (0..term.buffer.w)
                    .map(|x| buf[(x, y)].symbol().to_string())
                    .collect()
            })
            .collect();
        let row_idx = rows
            .iter()
            .position(|r| r.contains("show matches"))
            .expect("example row");
        let row = &rows[row_idx];
        // Bare # (inside 'a#b', no surrounding spaces) → default color (not secondary).
        let bare = row.chars().position(|ch| ch == '#').expect("bare hash");
        assert_ne!(
            buf[(bare as u16, row_idx as u16)].style().fg,
            Some(Color::DarkGray),
            "bare hash in command should be default"
        );
        // Separator ` # ` (surrounded by spaces) → secondary color.
        let sep = row.find(" # ").expect("separator") + 1;
        assert_eq!(
            buf[(sep as u16, row_idx as u16)].style().fg,
            Some(Color::DarkGray),
            "separator hash should be secondary"
        );
    }

    #[test]
    fn scroll_highlights_all_items_not_just_first_page() {
        let mut c = cfg(false);
        c.flags.filter_mode = "wildcard".into();
        c.flags.show_mode = "inline".into(); // only inline allows flipping above
                                             // Small window: h=6, cursor on bottom row 5 → 4 rows above → menu 4 rows, 2 items/page
        let term = TerminalInfo {
            cursor: Pos { x: 0, y: 5 },
            buffer: Size { w: 120, h: 6 },
            window: None,
            platform: "windows".into(),
        };
        // 20 items, each containing "abc", so every item can be verified to hit the highlight.
        let list: Vec<Item> = (0..20)
            .map(|i| Item {
                completion_text: format!("prefix-abc-{i}"),
                list_item_text: format!("prefix-abc-{i}"),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect();
        let mut s = MenuState::new(list, &c, &term);
        s.filter.push('a');
        s.filter.push('b');
        s.filter.push('c');
        s.apply_filter(&c, &term);
        assert_eq!(s.page_max + 1, 2); // 2 items per page, guaranteeing scrolling
        let highlight = |state: &MenuState| {
            state.content_box.iter().all(|l| {
                !match_segments(l, &state.filter, state.is_prefix, state.use_subsequence).is_empty()
            })
        };
        // Items visible on the first page are all highlighted.
        assert!(highlight(&s), "first page items should be highlighted");
        // Scroll to the last page.
        while s.offset + (s.page_max + 1) < s.filtered.len() {
            s.move_selection(true, &c);
        }
        // Items newly visible after scrolling are also highlighted.
        assert!(highlight(&s), "scrolled items should also be highlighted");
    }

    #[test]
    fn psc_real_items_revert_consistently() {
        // A few letters hit a subset → typing more leads to no match → reverts to the
        // previous menu state; the reverted list must agree with the reverted filter text
        // (must not jump back to a larger match set).
        let path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../completions/psc/language/en-US.json"
        );
        let text = std::fs::read_to_string(path).unwrap();
        let json: serde_json::Value = serde_json::from_str(&text).unwrap();
        let names: Vec<String> = json["next"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|n| n["name"].as_str().map(String::from))
            .collect();
        assert!(names.len() >= 8, "psc has many subcommands");
        let list: Vec<Item> = names
            .iter()
            .map(|n| Item {
                completion_text: n.clone(),
                list_item_text: n.clone(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect();

        let mut c = cfg(false);
        c.flags.filter_mode = "subsequence".into();
        c.flags.show_mode = "auto".into();
        let mut s = MenuState::new(list, &c, &term());
        // "a" → add / alias / update (subsequence hits the 3 items containing a).
        s.insert_at_cursor('a');
        s.apply_filter(&c, &term());
        assert_eq!(s.filtered.len(), 3);
        // "ad" → only add.
        s.insert_at_cursor('d');
        s.apply_filter(&c, &term());
        assert_eq!(s.filtered.len(), 1);
        assert_eq!(s.items[s.filtered[0]].completion_text, "add");
        // "add" → still matches add (the word itself has two d's).
        s.insert_at_cursor('d');
        s.apply_filter(&c, &term());
        assert_eq!(s.filtered.len(), 1);
        // "addd" → no match → reverts to "add", the list stays ["add"] (must not jump back
        // to a larger match set).
        s.insert_at_cursor('d');
        s.apply_filter(&c, &term());
        assert_eq!(s.filter, "add", "filter reverts to last valid");
        assert_eq!(
            s.filtered.len(),
            1,
            "list must stay consistent with reverted filter"
        );
        assert_eq!(s.items[s.filtered[0]].completion_text, "add");
        // Typing more non-matching letters stays stable.
        s.insert_at_cursor('z');
        s.apply_filter(&c, &term());
        assert_eq!(s.filter, "add");
        assert_eq!(s.filtered.len(), 1);
    }

    #[test]
    fn no_match_auto_apply_on_next_append() {
        // Auto-apply on no match (no buffering): a non-matching filter shows the warning;
        // the next **append** input commits.
        // add matches → addx does not (warning, no commit) → addxy appends → commits.
        let mut c = cfg(false);
        c.flags.filter_mode = "subsequence".into();
        c.flags.show_mode = "auto".into();
        c.flags.enable_apply_when_no_match = true;
        let list: Vec<Item> = ["add", "rm", "which"]
            .iter()
            .map(|n| Item {
                completion_text: n.to_string(),
                list_item_text: n.to_string(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect();
        let mut s = MenuState::new(list, &c, &term());
        // "add" matches.
        for ch in ['a', 'd', 'd'] {
            s.insert_at_cursor(ch);
            let out = s.apply_filter(&c, &term());
            assert!(matches!(out, FilterOutcome::None));
        }
        assert_eq!(s.filtered.len(), 1);
        assert!(!s.no_match, "matching has no warning");
        // "addx" does not match (append) → warning, no commit.
        s.insert_at_cursor('x');
        let out = s.apply_filter(&c, &term());
        assert!(
            matches!(out, FilterOutcome::None),
            "first no-match must not commit"
        );
        assert!(s.no_match, "no-match shows warning");
        // "addxy" appends → commits.
        s.insert_at_cursor('y');
        let out = s.apply_filter(&c, &term());
        match out {
            FilterOutcome::Input(text) => assert_eq!(text, "addxy"),
            _ => panic!("next append after no-match must commit"),
        }
    }

    #[test]
    fn no_match_warning_circle_renders_only_when_no_match() {
        // Rendering: enabled and no match → a single solid circle ● on the count row.
        let mut c = cfg(false);
        c.flags.filter_mode = "subsequence".into();
        c.flags.show_mode = "auto".into();
        c.flags.enable_tip = false;
        c.flags.enable_apply_when_no_match = true;
        let list: Vec<Item> = ["add", "rm", "which"]
            .iter()
            .map(|n| Item {
                completion_text: n.to_string(),
                list_item_text: n.to_string(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect();
        let render = |state: &mut MenuState| -> String {
            let backend = ratatui::backend::TestBackend::new(term().buffer.w, term().buffer.h);
            let mut terminal = ratatui::Terminal::new(backend).unwrap();
            terminal
                .draw(|f| crate::menu::ui::render(f, state, &term(), &c))
                .unwrap();
            let buf = terminal.backend().buffer();
            (0..term().buffer.h)
                .map(|y| {
                    (0..term().buffer.w)
                        .map(|x| buf[(x, y)].symbol().to_string())
                        .collect()
                })
                .collect::<Vec<String>>()
                .join("\n")
        };
        let mut s = MenuState::new(list.clone(), &c, &term());
        for ch in ['a', 'd', 'd'] {
            s.insert_at_cursor(ch);
            s.apply_filter(&c, &term());
        }
        assert!(!render(&mut s).contains('●'), "matching shows no circle");
        s.insert_at_cursor('x');
        s.apply_filter(&c, &term());
        assert!(
            render(&mut s).contains('●'),
            "no-match shows single solid circle"
        );
        // Disabled: no solid circle (a non-matching filter reverts to the last valid state).
        let mut c0 = cfg(false);
        c0.flags.filter_mode = "subsequence".into();
        c0.flags.show_mode = "auto".into();
        c0.flags.enable_tip = false;
        c0.flags.enable_apply_when_no_match = false;
        let mut s0 = MenuState::new(list, &c0, &term());
        for ch in ['a', 'd', 'd', 'x'] {
            s0.insert_at_cursor(ch);
            s0.apply_filter(&c0, &term());
        }
        assert_eq!(s0.filter, "add", "disabled reverts no-match filter");
        assert!(!render(&mut s0).contains('●'), "disabled shows no circle");
    }

    #[test]
    fn edit_recovers_from_no_match() {
        // After a no-match, editing (backspace) recovers a match → the warning clears;
        // re-entering no-match requires two fresh appends to commit again.
        let mut c = cfg(false);
        c.flags.filter_mode = "subsequence".into();
        c.flags.show_mode = "auto".into();
        c.flags.enable_apply_when_no_match = true;
        let list: Vec<Item> = ["add", "rm", "which"]
            .iter()
            .map(|n| Item {
                completion_text: n.to_string(),
                list_item_text: n.to_string(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect();
        let mut s = MenuState::new(list, &c, &term());
        for ch in ['a', 'd', 'd', 'x'] {
            s.insert_at_cursor(ch);
            s.apply_filter(&c, &term());
        }
        assert!(s.no_match, "addx is no-match");
        // Backspace → "add" matches → the warning clears.
        s.backspace_at_cursor();
        s.apply_filter(&c, &term());
        assert!(!s.no_match, "recovering to match clears the warning");
        assert_eq!(s.filter, "add");
        // Re-enter no-match: addx → warning; addxy → commit.
        s.insert_at_cursor('x');
        s.apply_filter(&c, &term());
        assert!(s.no_match, "re-entering no-match warns again");
        s.insert_at_cursor('y');
        let out = s.apply_filter(&c, &term());
        assert!(
            matches!(out, FilterOutcome::Input(_)),
            "fresh no-match commits on next append"
        );
    }

    #[test]
    fn disabled_reverts_no_match_filter() {
        // Disabled: a non-matching filter reverts to the last valid one (not kept, no warning).
        let mut c = cfg(false);
        c.flags.filter_mode = "subsequence".into();
        c.flags.show_mode = "auto".into();
        c.flags.enable_apply_when_no_match = false;
        let list: Vec<Item> = ["add", "rm", "which"]
            .iter()
            .map(|n| Item {
                completion_text: n.to_string(),
                list_item_text: n.to_string(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect();
        let mut s = MenuState::new(list, &c, &term());
        for ch in ['a', 'd', 'd', 'x'] {
            s.insert_at_cursor(ch);
            s.apply_filter(&c, &term());
        }
        assert_eq!(s.filter, "add", "no-match filter reverts when disabled");
        assert_eq!(s.filtered.len(), 1);
        assert!(!s.no_match);
    }

    #[test]
    fn insert_anywhere_commits_when_no_match_warning_shown() {
        // With the solid-circle warning (no match), any character insertion at any
        // position commits — not just appending at the end; middle/front inserts also
        // count as "the next input". Deletion recovers; the `^` prefix toggle does not commit.
        let mut c = cfg(false);
        c.flags.filter_mode = "subsequence".into();
        c.flags.show_mode = "auto".into();
        c.flags.enable_apply_when_no_match = true;
        let list: Vec<Item> = ["add", "rm", "which"]
            .iter()
            .map(|n| Item {
                completion_text: n.to_string(),
                list_item_text: n.to_string(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect();
        let mut s = MenuState::new(list, &c, &term());
        // "add" matches → appending x does not (solid circle).
        for ch in ['a', 'd', 'd', 'x'] {
            s.insert_at_cursor(ch);
            s.apply_filter(&c, &term());
        }
        assert!(s.no_match);
        // Middle insert of y (cursor moved between d and x) → commits.
        s.move_cursor_left();
        s.insert_at_cursor('y');
        let out = s.apply_filter(&c, &term());
        match out {
            FilterOutcome::Input(text) => assert_eq!(text, "addyx"),
            _ => panic!("middle insert while warning must commit"),
        }
    }

    #[test]
    fn prefix_toggle_does_not_commit_but_insert_after_does() {
        // The `^` prefix is a mode switch and does not commit; if it still does not match
        // after the toggle, the next insert commits.
        let mut c = cfg(false);
        c.flags.filter_mode = "subsequence".into();
        c.flags.show_mode = "auto".into();
        c.flags.enable_apply_when_no_match = true;
        let list: Vec<Item> = ["add", "rm", "which"]
            .iter()
            .map(|n| Item {
                completion_text: n.to_string(),
                list_item_text: n.to_string(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect();
        let mut s = MenuState::new(list, &c, &term());
        // "addx" (no match, solid circle).
        for ch in ['a', 'd', 'd', 'x'] {
            s.insert_at_cursor(ch);
            s.apply_filter(&c, &term());
        }
        assert!(s.no_match);
        // Add the prefix ^ → no commit (mode switch), the solid circle stays (^addx still does not match).
        s.make_prefix();
        let out = s.apply_filter(&c, &term());
        assert!(
            matches!(out, FilterOutcome::None),
            "prefix toggle must not commit"
        );
        assert!(s.no_match);
        assert_eq!(s.filter, "^addx");
        // Move past the prefix to the end and insert a character → commits (the text
        // contains ^; by convention the ^ is stripped).
        s.move_cursor_end();
        s.insert_at_cursor('z');
        let out = s.apply_filter(&c, &term());
        match out {
            FilterOutcome::Input(text) => assert_eq!(text, "addxz"),
            _ => panic!("insert after prefix must commit"),
        }
    }

    #[test]
    fn commit_strips_only_one_prefix_caret() {
        // Regression: the committed text strips only **one** prefix caret ^; a ^ the user
        // typed extra is an ordinary character and is kept. Filtering ^^x (prefix ^ +
        // ordinary ^x) writes ^x, not trimming everything into x.
        let mut c = cfg(false);
        c.flags.filter_mode = "subsequence".into();
        c.flags.show_mode = "auto".into();
        c.flags.enable_apply_when_no_match = true;
        let list: Vec<Item> = ["add", "rm", "which"]
            .iter()
            .map(|n| Item {
                completion_text: n.to_string(),
                list_item_text: n.to_string(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect();
        let mut s = MenuState::new(list, &c, &term());
        // Type x (no match, solid circle).
        s.insert_at_cursor('x');
        s.apply_filter(&c, &term());
        assert!(s.no_match);
        // Add the prefix ^ → ^x (still no match, solid circle stays).
        s.make_prefix();
        s.apply_filter(&c, &term());
        assert!(s.no_match);
        assert_eq!(s.filter, "^x");
        // Insert an ordinary ^ between ^ and x → ^^x → commits, writing ^x (only the one
        // prefix ^ is stripped).
        s.insert_at_cursor('^');
        let out = s.apply_filter(&c, &term());
        match out {
            FilterOutcome::Input(text) => {
                assert_eq!(text, "^x", "must strip one ^, keep the typed ^")
            }
            _ => panic!("inserting a caret while warning must commit"),
        }
    }

    #[test]
    fn always_below_reserves_tip_space() {
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        c.flags.show_mode = "altscreen-top".into();
        // 12 rows below (cursor on row 17 of 30): altscreen-top forces below, description gets
        // its 4-line baseline (6-row box), the menu takes 6 (4 items).
        let term = TerminalInfo {
            cursor: Pos { x: 0, y: 17 },
            buffer: Size { w: 120, h: 30 },
            window: None,
            platform: "windows".into(),
        };
        let s = MenuState::new(items(20), &c, &term);
        assert!(!s.min_area);
        assert!(!s.is_show_above);
        assert_eq!(s.ui_height, 6); // min(22, 12, 12-6=6) = 6
        assert_eq!(s.tip_placement, TipPlacement::Below);
    }

    #[test]
    fn auto_alternate_flips_above_when_below_is_tight() {
        // `auto` switches to the alternate screen when the space below the input line is less
        // than `below_required`. There the app layer delegates it to `altscreen-follow`, so the
        // menu must flip above when below is provably too small. Window height 30, so the
        // below_required(11) threshold means a cursor below row 18 (rel_y 19+) flips above.
        for rel_y in [20u16, 25] {
            let mut c = cfg(false);
            c.flags.enable_tip = true;
            c.flags.show_mode = "altscreen-follow".into();
            let term = TerminalInfo {
                cursor: Pos { x: 0, y: rel_y },
                buffer: Size { w: 120, h: 30 },
                window: Some(crate::menu::model::Window { top: 0, h: 30 }),
                platform: "windows".into(),
            };
            let s = MenuState::new(items(20), &c, &term);
            assert!(!s.min_area, "rel_y {rel_y}: must not be min_area");
            // Below is 30-1-rel_y < below_required here → the menu must sit above the cursor.
            assert!(
                s.is_show_above,
                "rel_y {rel_y}: below too small, expected flip above, pos.y={}",
                s.pos.1
            );
        }
        // A cursor high enough that below fits stays below (no flip).
        let mut c = cfg(false);
        c.flags.enable_tip = true;
        c.flags.show_mode = "altscreen-follow".into();
        let term = TerminalInfo {
            cursor: Pos { x: 0, y: 10 },
            buffer: Size { w: 120, h: 30 },
            window: Some(crate::menu::model::Window { top: 0, h: 30 }),
            platform: "windows".into(),
        };
        let s = MenuState::new(items(20), &c, &term);
        assert!(
            !s.is_show_above,
            "rel_y 10: below fits, should not flip above"
        );
    }

    #[test]
    fn altscreen_bottom_pins_to_the_bottom() {
        // `altscreen-bottom` always renders above (menu grows upward from the last row). The
        // app layer sets the alternate-screen cursor to the bottom row (window_h-1), so the
        // menu's bottom hugs the row before the last, symmetric with altscreen-top's empty top
        // row.
        for _rel in [5u16, 15, 25] {
            let mut c = cfg(false);
            c.flags.enable_tip = true;
            c.flags.show_mode = "altscreen-bottom".into();
            let term = TerminalInfo {
                cursor: Pos { x: 0, y: 29 }, // app layer: window_h-1
                buffer: Size { w: 120, h: 30 },
                window: Some(crate::menu::model::Window { top: 0, h: 30 }),
                platform: "windows".into(),
            };
            let s = MenuState::new(items(20), &c, &term);
            assert!(!s.min_area, "must not be min_area");
            assert!(s.is_show_above, "altscreen-bottom must render above");
            // The menu ends one row above the last: pos.y + ui_height == window_h - 1.
            assert_eq!(
                s.pos.1 as i32 + s.ui_height as i32,
                29,
                "menu must end one row above the bottom (pos.y={}, ui_height={})",
                s.pos.1,
                s.ui_height
            );
        }
    }
}
