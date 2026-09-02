use crate::menu::model::{Config, TerminalInfo};
use crate::menu::state::{match_segments, MenuState, TipPlacement, TIP_GAP};
use ratatui::buffer::{Buffer, CellDiffOption};
use ratatui::style::{Color, Modifier, Style};
use ratatui::Frame;
use std::collections::HashSet;
use unicode_width::UnicodeWidthChar;

/// Default theme colors; overridden by `color_focus` / `color_match` config values.
const DEFAULT_FOCUS_C: Color = Color::Red;
const DEFAULT_MATCH_C: Color = Color::Cyan;
const WARN_C: Color = Color::Yellow;
const STRUCT_C: Color = Color::DarkGray;

/// Left track: marks focus together with the selection marker (the selected row turns red).
const TRACK: char = '\u{258D}'; // ▍
/// Arrow left of the selected item (double focus marker; no right `>` — it would
/// collide with predict symbols like `~`).
const SELECT_L: char = '>';
/// Divider line between the count and the list.
const DIVIDER: char = '\u{2500}'; // ─
/// Blinking bar cursor on the filter row (terminal default foreground, ASCII `|`).
const CURSOR_BAR: char = '|';
/// Right-side proportional scrollbar thumb.
const SCROLL: char = '\u{2502}'; // |
/// Description border container characters (rounded).
const TIP_BOX_TL: char = '\u{256D}'; // ╭
const TIP_BOX_TR: char = '\u{256E}'; // ╮
const TIP_BOX_BL: char = '\u{2570}'; // ╰
const TIP_BOX_BR: char = '\u{256F}'; // ╯
const TIP_BOX_V: char = '\u{2502}'; // │

/// Parse a color string into a `ratatui::style::Color`.
///
/// Supports named colors (`red`, `cyan`, …), 256-color index (`0`–`255`), and
/// 24-bit RGB (`#rrggbb`).  Falls back to the given default on unrecognized input.
fn parse_color(s: &str, fallback: Color) -> Color {
    match s.to_lowercase().as_str() {
        "red" => Color::Red,
        "green" => Color::Green,
        "yellow" => Color::Yellow,
        "blue" => Color::Blue,
        "magenta" => Color::Magenta,
        "cyan" => Color::Cyan,
        "white" => Color::White,
        "gray" => Color::Gray,
        "black" => Color::Black,
        _ => {
            if let Ok(idx) = s.parse::<u8>() {
                return Color::Indexed(idx);
            }
            if s.len() == 7 && s.starts_with('#') {
                if let (Ok(r), Ok(g), Ok(b)) = (
                    u8::from_str_radix(&s[1..3], 16),
                    u8::from_str_radix(&s[3..5], 16),
                    u8::from_str_radix(&s[5..7], 16),
                ) {
                    return Color::Rgb(r, g, b);
                }
            }
            fallback
        }
    }
}

pub fn render(frame: &mut Frame, state: &mut MenuState, term: &TerminalInfo, cfg: &Config) {
    let focus_c = parse_color(&cfg.flags.color_focus, DEFAULT_FOCUS_C);
    let match_c = parse_color(&cfg.flags.color_match, DEFAULT_MATCH_C);

    let buf = frame.buffer_mut();
    let bg = Color::Reset;

    let bx = state.pos.0;
    let y = state.pos.1;
    let h = state.ui_height;
    let content_x = bx + 2;
    let max_content = (term.buffer.w as usize).saturating_sub(content_x as usize);

    let below = !state.is_show_above;
    // Below the cursor, blank the whole viewport underneath so PSReadLine's command-history
    // prediction list (rendered below the menu) never shows through.
    let viewport_bottom = match &term.window {
        Some(w) => (w.top + w.h) as u16,
        None => term.buffer.h,
    };
    let cover_h = if below {
        viewport_bottom.saturating_sub(y)
    } else {
        h
    };
    clear_rect(buf, (0, y, term.buffer.w, cover_h), bg, &mut state.cleaned);
    state.mark_covered(y, y.saturating_add(cover_h.saturating_sub(1)));

    let text_style = Style::default().bg(bg);
    let track_c = STRUCT_C;
    let divider_c = STRUCT_C;

    let item_top: u16 = if below { 2 } else { 0 };
    let prompt_row: u16 = if below { 0 } else { h.saturating_sub(1) };
    let count_row: u16 = if below { 1 } else { h.saturating_sub(2) };

    let empty_hint = state.filter.is_empty() && !state.filter_hint.is_empty();
    put_char(
        buf,
        bx,
        y + prompt_row,
        '>',
        Style::default().fg(focus_c).bg(bg),
    );

    // The bar owns one cell: split the filter at the cursor and shift the right half over.
    let cursor_byte = state.filter_cursor_byte();
    let left = &state.filter[..cursor_byte];
    let right = &state.filter[cursor_byte..];
    let left_w = display_width(left).min(max_content);
    let cursor_x = bx + 2 + left_w as u16;

    if state.cursor_on {
        put_char(
            buf,
            cursor_x,
            y + prompt_row,
            CURSOR_BAR,
            Style::default().bg(bg),
        );
    }

    if empty_hint {
        // Start one column after the bar so it never covers the hint's first character.
        put_str(
            buf,
            bx + 3,
            y + prompt_row,
            &state.filter_hint,
            Style::default().fg(STRUCT_C).bg(bg),
            max_content.saturating_sub(1),
        );
    } else {
        put_str(buf, bx + 2, y + prompt_row, left, text_style, max_content);
        if !right.is_empty() {
            put_str(
                buf,
                cursor_x + 1,
                y + prompt_row,
                right,
                text_style,
                max_content.saturating_sub(left_w + 1),
            );
        }
    }

    let total = state.filtered.len();
    let cur = state.selected + 1;
    let width = total.to_string().len();
    let cur_text = format!("{:0>width$}", cur, width = width);
    put_str(
        buf,
        content_x,
        y + count_row,
        &cur_text,
        Style::default().fg(focus_c).bg(bg),
        max_content,
    );
    let tail_text = format!("/{}", total);
    put_str(
        buf,
        content_x + cur_text.chars().count() as u16,
        y + count_row,
        &tail_text,
        text_style,
        max_content,
    );
    let count_text = format!("{}{}", cur_text, tail_text);
    // While the selected row's peek is in flight, withhold the static symbol: the peek
    // (which runs the hook) may correct it, and showing a value that is about to change
    // would make the symbol visibly flip. Once the peek result lands, it is shown.
    let sel_symbol = if state.peek_pending {
        ""
    } else {
        state
            .filtered
            .get(state.selected)
            .and_then(|&i| state.items.get(i))
            .map(|it| it.symbol.as_str())
            .unwrap_or("")
    };
    let sym_w = sel_symbol.chars().count() as u16;
    let sym_x = content_x + count_text.chars().count() as u16 + 1;
    if sym_w > 0 {
        put_str(
            buf,
            sym_x,
            y + count_row,
            sel_symbol,
            text_style,
            max_content,
        );
    }
    // No-match warning: a single solid circle ● hints that the next input commits.
    let warn_pip: Option<String> = if state.enable_apply_when_no_match && state.no_match {
        Some("\u{25CF}".to_string())
    } else {
        None
    };
    let pip_width = warn_pip.as_ref().map(|p| p.chars().count()).unwrap_or(0);
    let mut div_x = if sym_w > 0 { sym_x + sym_w + 1 } else { sym_x };
    if let Some(p) = &warn_pip {
        put_str(
            buf,
            div_x,
            y + count_row,
            p,
            Style::default().fg(WARN_C).bg(bg),
            max_content,
        );
        div_x = div_x + pip_width as u16 + 1;
    }
    // Stop one column before the rightmost scrollbar column so they never overlap.
    let div_w = (term.buffer.w.saturating_sub(div_x)).saturating_sub(1);
    if div_w > 0 {
        let div = DIVIDER.to_string().repeat(div_w as usize);
        put_str(
            buf,
            div_x,
            y + count_row,
            &div,
            Style::default().fg(divider_c).bg(bg),
            div_w as usize,
        );
    }

    let match_style = Style::default().fg(match_c).bg(bg);
    let track_style = Style::default().fg(track_c).bg(bg);
    let selected_style = Style::default().fg(focus_c).bg(bg);
    for (i, line) in state.content_box.iter().enumerate() {
        let cy = y + item_top + i as u16;
        if cy >= y + h {
            break;
        }
        put_char(
            buf,
            bx,
            cy,
            TRACK,
            if i == state.page_current {
                selected_style
            } else {
                track_style
            },
        );
        let segments = match_segments(line, &state.filter, state.is_prefix, state.use_subsequence);
        if i == state.page_current {
            put_char(buf, bx + 1, cy, SELECT_L, selected_style);
            let item_max = max_content.saturating_sub(1);
            put_item_line(
                buf,
                content_x + 1,
                cy,
                line,
                item_max,
                &segments,
                (text_style, match_style),
            );
        } else {
            put_item_line(
                buf,
                content_x,
                cy,
                line,
                max_content,
                &segments,
                (text_style, match_style),
            );
        }
    }

    let total = state.filtered.len();
    let visible = state.page_max + 1;
    let area_top = y + item_top;
    let area_bottom = area_top + visible as u16 - 1;
    if total > visible {
        let area_h = visible as f32;
        let thumb_h = (area_h * visible as f32 / total as f32).round().max(1.0) as u16;
        let scroll_range = (total - visible) as f32;
        let slide_range = (visible as f32 - thumb_h as f32).max(0.0);
        let pos = state.offset as f32 / scroll_range.max(1.0);
        let thumb_top = area_top + (slide_range * pos).round() as u16;
        let scroll_style = Style::default().fg(track_c).bg(bg);
        for row in thumb_top..thumb_top + thumb_h {
            if row <= area_bottom && row >= area_top {
                put_char(buf, term.buffer.w - 1, row, SCROLL, scroll_style);
            }
        }
    }

    // Description info: no border, above or below.
    if state.tip_placement != TipPlacement::None {
        draw_tip(buf, state, term);
    }

    // Wrap-up: reset the diff option on cells with real content so the AlwaysUpdate left
    // by clear_rect does not force-resend text (incl. URL links) every frame → the terminal
    // redraws repeatedly and VSCode's link underline flickers. Blank cells keep
    // AlwaysUpdate (force-cleared every frame, erasing stale terminal content under the menu).
    for cell in buf.content.iter_mut() {
        if cell.symbol() != " " {
            cell.set_diff_option(CellDiffOption::None);
        }
    }
}

/// Draw the description box: dynamic width, scrollable, on the end away from the input row.
fn draw_tip(buf: &mut Buffer, state: &mut MenuState, term: &TerminalInfo) {
    let tip_lines = state.selected_tip_lines();
    if tip_lines.is_empty() {
        state.tip_box_rect = None;
        state.tip_scroll_max = 0;
        return;
    }

    let buffer_w = term.buffer.w as i32;
    let buffer_h = term.buffer.h as i32;
    let list_y = state.pos.1 as i32;
    let list_h = state.ui_height as i32;

    let natural_max = tip_lines
        .iter()
        .map(|(_, l)| display_width(l.trim_end_matches('\r')))
        .max()
        .unwrap_or(0);
    // Side margins (2) + border (2) + inner padding (2)
    let text_avail = (buffer_w - 2 - 2 - 2).max(4) as usize;
    let wrap_w = natural_max.min(text_avail).max(1);

    let window_top = match &term.window {
        Some(w) => w.top,
        None => 0,
    };
    let window_bottom = match &term.window {
        Some(w) => w.top + w.h - 1,
        None => buffer_h - 1,
    };

    // Below expands downward from the list, above expands upward from it.
    // max_lines = available range - 1 (content rows + 2 borders; tail aligns to the edge).
    let (box_top_anchor, max_lines) = match state.tip_placement {
        TipPlacement::Below => {
            let top = list_y + list_h + TIP_GAP;
            let avail = window_bottom - top;
            if avail < 2 {
                state.tip_box_rect = None;
                state.tip_scroll_max = 0;
                return;
            }
            (top, (avail - 1).max(0) as usize)
        }
        TipPlacement::Above => {
            let bottom = list_y - TIP_GAP - 1;
            if bottom < 0 {
                state.tip_box_rect = None;
                state.tip_scroll_max = 0;
                return;
            }
            let avail = bottom - window_top;
            if avail < 2 {
                state.tip_box_rect = None;
                state.tip_scroll_max = 0;
                return;
            }
            (bottom - 1, (avail - 1).max(0) as usize)
        }
        TipPlacement::None => {
            state.tip_box_rect = None;
            state.tip_scroll_max = 0;
            return;
        }
    };
    // The description box uses all available space (clipped by the layout tiers); overflow scrolls.
    let wrapped = wrap_tip(&tip_lines, wrap_w);
    if wrapped.is_empty() {
        state.tip_box_rect = None;
        state.tip_scroll_max = 0;
        return;
    }

    let total = wrapped.len();
    let scrollable = total > max_lines;
    let visible = if scrollable { max_lines } else { total };
    if visible == 0 {
        state.tip_box_rect = None;
        state.tip_scroll_max = 0;
        return;
    }
    if scrollable {
        if state.tip_scroll > total - visible {
            state.tip_scroll = total - visible;
        }
        state.tip_scroll_max = total - visible;
    } else {
        state.tip_scroll = 0;
        state.tip_scroll_max = 0;
    }

    let content_w = wrapped
        .iter()
        .map(|row| match row {
            TipRow::Split(c, d) => display_width(c) + display_width(d),
            TipRow::Section(l) | TipRow::Body(l) | TipRow::Desc(l) => display_width(l),
        })
        .max()
        .unwrap_or(wrap_w)
        .max(10);
    let box_w = (content_w + 4).min(buffer_w as usize).max(4);
    let box_x = 0u16; // same column as the menu, pinned to the far left
    let box_top = if state.tip_placement == TipPlacement::Above {
        let bottom = box_top_anchor + 1;
        (bottom - visible as i32 - 1).max(0)
    } else {
        box_top_anchor
    } as u16;
    let box_h = visible + 2;
    let box_rect = (box_x, box_top, box_w as u16, box_h as u16);

    // Clear the box + the gap rows to the menu with whole blank rows (stale content must
    // not peek through beside a narrow box).
    let (clear_y, clear_h) = if state.tip_placement == TipPlacement::Above {
        (box_top as i32, box_h as i32 + TIP_GAP)
    } else {
        (list_y + list_h, TIP_GAP + box_h as i32)
    };
    clear_rect(
        buf,
        (
            0,
            clear_y.max(0) as u16,
            term.buffer.w,
            clear_h.max(0) as u16,
        ),
        Color::Reset,
        &mut state.cleaned,
    );
    let clear_top = clear_y.max(0) as u16;
    let clear_bottom = (clear_y + clear_h).max(0) as u16;
    state.mark_covered(clear_top, clear_bottom.saturating_sub(1));

    let border_style = Style::default().fg(STRUCT_C).bg(Color::Reset);
    let left = box_rect.0;
    let right = box_rect.0 + box_rect.2 - 1;
    let top_row = box_rect.1;
    let bottom_row = box_rect.1 + box_rect.3 - 1;
    put_char(buf, left, top_row, TIP_BOX_TL, border_style);
    put_char(buf, left, bottom_row, TIP_BOX_BL, border_style);
    put_char(buf, right, top_row, TIP_BOX_TR, border_style);
    put_char(buf, right, bottom_row, TIP_BOX_BR, border_style);
    let hline = DIVIDER.to_string().repeat(box_w - 2);
    put_str(buf, left + 1, top_row, &hline, border_style, box_w - 2);
    put_str(buf, left + 1, bottom_row, &hline, border_style, box_w - 2);
    for i in 1..box_h as u16 - 1 {
        put_char(buf, left, top_row + i, TIP_BOX_V, border_style);
        put_char(buf, right, top_row + i, TIP_BOX_V, border_style);
    }

    // Rows were classified by the separator before wrapping, so colors survive a wrap.
    let text_x = left + 2;
    let tstyle = Style::default().bg(Color::Reset);
    let hstyle = Style::default()
        .fg(STRUCT_C)
        .add_modifier(Modifier::BOLD)
        .bg(Color::Reset);
    // The `# explanation` part: structural color, not bold (color layering, no alignment).
    let dstyle = Style::default().fg(STRUCT_C).bg(Color::Reset);
    for i in 0..visible as u16 {
        let y = top_row + 1 + i;
        match &wrapped[state.tip_scroll + i as usize] {
            TipRow::Section(line) => {
                put_str(buf, text_x, y, line, hstyle, content_w);
            }
            TipRow::Body(line) => {
                put_str(buf, text_x, y, line, tstyle, content_w);
            }
            TipRow::Desc(line) => {
                put_str(buf, text_x, y, line, dstyle, content_w);
            }
            TipRow::Split(cmd, desc) => {
                put_str(buf, text_x, y, cmd, tstyle, content_w);
                let off = display_width(cmd);
                put_str(
                    buf,
                    text_x + off as u16,
                    y,
                    desc,
                    dstyle,
                    content_w.saturating_sub(off),
                );
            }
        }
    }

    if scrollable {
        let scroll_x = right - 1;
        let track_h = box_h as u16 - 2;
        let thumb_h = ((track_h as f32) * (visible as f32) / (total as f32))
            .round()
            .max(1.0) as u16;
        let slide = (track_h as f32 - thumb_h as f32).max(0.0);
        let range = (total - visible) as f32;
        let thumb_top =
            top_row + 1 + (slide * (state.tip_scroll as f32 / range.max(1.0))).round() as u16;
        let thumb_end = (thumb_top + thumb_h).min(top_row + box_h as u16 - 1);
        for row in thumb_top..thumb_end {
            put_char(
                buf,
                scroll_x,
                row,
                SCROLL,
                Style::default().fg(STRUCT_C).bg(Color::Reset),
            );
        }
    }

    state.tip_box_rect = Some(box_rect);
}

/// Fill a rect with spaces + the given background (background coverage, see `design/menu.md`).
///
/// Spaces are marked `AlwaysUpdate`: ratatui's first-frame diff skips default cells, so plain
/// spaces would never erase the stale terminal content underneath. Only the **first** cover of
/// a cell marks `AlwaysUpdate`; afterwards the normal diff applies (no per-frame resend, which
/// made VSCode re-detect links and flicker the hover underline).
fn clear_rect(
    buf: &mut Buffer,
    rect: (u16, u16, u16, u16),
    bg: Color,
    cleaned: &mut HashSet<(u16, u16)>,
) {
    let (x, y, w, h) = rect;
    if w == 0 || h == 0 {
        return;
    }
    let style = Style::default().bg(bg);
    for yy in y..y.saturating_add(h) {
        if yy >= buf.area.height {
            break;
        }
        for xx in x..x.saturating_add(w) {
            if xx >= buf.area.width {
                break;
            }
            let cell = &mut buf[(xx, yy)];
            cell.set_symbol(" ");
            cell.set_style(style);
            if cleaned.insert((xx, yy)) {
                cell.set_diff_option(CellDiffOption::AlwaysUpdate);
            }
        }
    }
}

fn put_char(buf: &mut Buffer, x: u16, y: u16, ch: char, style: Style) {
    if x >= buf.area.width || y >= buf.area.height {
        return;
    }
    let cell = &mut buf[(x, y)];
    cell.set_char(ch);
    cell.set_style(style);
}

fn put_str(buf: &mut Buffer, x: u16, y: u16, s: &str, style: Style, max_width: usize) {
    if y >= buf.area.height {
        return;
    }
    if x >= buf.area.width {
        return;
    }
    let max_w = max_width.min((buf.area.width - x) as usize);
    buf.set_stringn(x, y, s, max_w, style);
}

/// Draw a line char by char, accenting matched chars; truncates by display width (CJK-aware).
fn put_item_line(
    buf: &mut Buffer,
    x: u16,
    y: u16,
    text: &str,
    max_width: usize,
    segments: &[(usize, usize)],
    styles: (Style, Style),
) {
    if y >= buf.area.height || x >= buf.area.width {
        return;
    }
    let mut col = 0u16;
    let mut width = 0usize;
    for (byte_idx, ch) in text.char_indices() {
        let cw = UnicodeWidthChar::width(ch).unwrap_or(0);
        if width + cw > max_width {
            break;
        }
        let in_match = segments.iter().any(|&(s, e)| byte_idx >= s && byte_idx < e);
        put_char(
            buf,
            x + col,
            y,
            ch,
            if in_match { styles.1 } else { styles.0 },
        );
        width += cw;
        col += cw as u16;
    }
}

/// A row in the description container: split at the `# explanation` separator before
/// wrapping, so continuation lines keep their corresponding color.
#[derive(Debug, Clone)]
enum TipRow {
    /// Section header (`[Usage]` / `[Description]` / `[Example]`, bold structural color).
    Section(String),
    /// Body content (default foreground).
    Body(String),
    /// The explanation part of `# explanation` (secondary color).
    Desc(String),
    /// A single row split into cmd (default color) + `# explanation` (secondary color).
    Split(String, String),
}

/// Wrap a line into `(start byte, text)` rows at `width`, so each row can be classified
/// as cmd or desc by its separator position.
fn wrap_rows(line: &str, width: usize) -> Vec<(usize, String)> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut cur_w = 0usize;
    let mut start = 0usize;
    for (bi, ch) in line.char_indices() {
        let cw = UnicodeWidthChar::width(ch).unwrap_or(0);
        if cur_w + cw > width && !cur.is_empty() {
            out.push((start, std::mem::take(&mut cur)));
            cur_w = 0;
            start = bi;
        }
        cur.push(ch);
        cur_w += cw;
    }
    if !cur.is_empty() {
        out.push((start, cur));
    }
    out
}

fn wrap_tip(lines: &[(bool, String)], width: usize) -> Vec<TipRow> {
    let mut out = Vec::new();
    if width == 0 {
        return out;
    }
    for (is_header, line) in lines {
        for seg in line.split('\n') {
            let seg = seg.trim_end_matches('\r');
            if seg.is_empty() {
                continue;
            }
            if *is_header {
                for (_, row) in wrap_rows(seg, width) {
                    out.push(TipRow::Section(row));
                }
            } else if let Some(sep) = find_desc_separator(seg) {
                // Classify each wrapped row relative to the separator: before → default,
                // after → secondary, crossing → an in-row split.
                for (start, row) in wrap_rows(seg, width) {
                    let end = start + row.len();
                    if end <= sep {
                        out.push(TipRow::Body(row));
                    } else if start >= sep {
                        out.push(TipRow::Desc(row));
                    } else {
                        let local = sep - start;
                        let (cmd, desc) = row.split_at(local);
                        out.push(TipRow::Split(cmd.to_string(), desc.to_string()));
                    }
                }
            } else {
                for (_, row) in wrap_rows(seg, width) {
                    out.push(TipRow::Body(row));
                }
            }
        }
    }
    out
}

/// Find the `# explanation` separator position in a usage/example row (returns the byte
/// index of the `#` itself). Rule: at least 2 spaces before the `#` and 1 space after
/// (the engine joins `{cmd, desc}` as `cmd  # desc`), so a `#` that is bare or wrapped by
/// a single space inside command text is not misjudged as a separator.
fn find_desc_separator(line: &str) -> Option<usize> {
    let bytes = line.as_bytes();
    for i in 0..bytes.len() {
        if bytes[i] == b'#' {
            let spaces_before = bytes[..i].iter().rev().take_while(|&&b| b == b' ').count();
            let space_after = i + 1 < bytes.len() && bytes[i + 1] == b' ';
            if spaces_before >= 2 && space_after {
                return Some(i);
            }
        }
    }
    None
}

/// Display width of a string (CJK-aware, same as the item rows).
fn display_width(s: &str) -> usize {
    s.chars()
        .map(|c| UnicodeWidthChar::width(c).unwrap_or(0))
        .sum()
}

#[cfg(test)]
mod tests {
    use super::find_desc_separator;

    #[test]
    fn desc_separator_requires_two_spaces_before() {
        // The engine joins `cmd  # desc`: 2 spaces + # + space → hit.
        assert_eq!(find_desc_separator("x demo.7z  # extract"), Some(11));
        // Multiple spaces also work.
        assert_eq!(find_desc_separator("x demo.7z   # extract"), Some(12));
        // Single space + # → no hit (not enough space before).
        assert_eq!(find_desc_separator("x demo.7z # extract"), None);
        // Bare # (no preceding space) → no hit; the trailing separator # hits.
        assert_eq!(find_desc_separator("grep 'a#b' file  # show"), Some(17));
        assert_eq!(find_desc_separator("grep 'a#b'"), None);
        // No space after → no hit.
        assert_eq!(find_desc_separator("cmd  #desc"), None);
    }
}
