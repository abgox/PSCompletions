use crate::engine::completion;
use crate::menu::model::{Config, Output, TerminalInfo};
use crate::menu::protocol::CompleteInput;
use crate::menu::state::{FilterOutcome, MenuState};
use crate::menu::ui;
use crossterm::event::{
    read, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEvent, KeyEventKind,
    KeyModifiers, MouseButton, MouseEvent, MouseEventKind,
};
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use ratatui::layout::Rect;
use ratatui::{Terminal, TerminalOptions, Viewport};
use std::io::Write;
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// Check if change.json's last_check is stale (>7 days or missing).
pub(crate) fn is_stale(data_dir: &str, order_dir: &str, menu_dir: &str) -> bool {
    let data_dir = if !data_dir.is_empty() {
        data_dir.to_string()
    } else {
        // Legacy fallback: derive data_dir from order_dir/menu_dir parent chain.
        match () {
            _ if !order_dir.is_empty() => std::path::Path::new(order_dir)
                .parent()
                .and_then(|p| p.parent())
                .map(|p| p.to_string_lossy().to_string()),
            _ if !menu_dir.is_empty() => std::path::Path::new(menu_dir)
                .parent()
                .and_then(|p| p.parent())
                .map(|p| p.to_string_lossy().to_string()),
            _ => None,
        }
        .unwrap_or_default()
    };
    if data_dir.is_empty() {
        return true;
    }
    let path = std::path::Path::new(&data_dir)
        .join("temp")
        .join("change.json");
    // Read errors, an empty file, and parse failures all mean "no usable last_check" → stale.
    let Some(text) = psc_common::read_text(&path.to_string_lossy()) else {
        return true;
    };
    if text.trim().is_empty() {
        return true;
    }
    let v: serde_json::Value = match serde_json::from_str(&text) {
        Ok(v) => v,
        Err(_) => return true,
    };
    let last = v.get("last_check").and_then(|x| x.as_u64());
    let now = match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
        Ok(d) => d.as_secs(),
        Err(_) => return true,
    };
    match last {
        None => true,
        Some(t) => now.saturating_sub(t) > 604800,
    }
}

pub enum Action {
    Select,
    Cancel,
    Input(String),
}

/// Selected output with the item's text/type attached, so the host can apply the selection
/// even when it passed a build context instead of an item list.
fn selected_output(state: &MenuState, idx: usize) -> Output {
    let mut out = Output::selected(idx);
    if let Some(it) = state.items.get(idx) {
        out.completion_text = Some(it.completion_text.clone());
        out.result_type = it.result_type;
    }
    out
}

/// Delete stale menu temp files (`psc-menu-*-input.json`, `psc-menu-*-output.json`,
/// `psc-menu-*-sort-in.json`, `psc-menu-*-sort-out.json`) older than 30 minutes. Normal menu
/// invocations clean up immediately, but files left behind by a crashed or force-killed
/// session accumulate forever without this sweep. Runs once per menu open in a background
/// thread, using filesystem mtime (no JSON parsing needed).
fn cleanup_stale_menu_files(menu_dir: &str) {
    let dir = menu_dir.trim_end_matches(['/', '\\']);
    if dir.is_empty() {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let cutoff = now_secs.saturating_sub(30 * 60);
    for entry in entries.flatten() {
        let path = entry.path();
        let is_menu_file = path
            .file_name()
            .and_then(|n| n.to_str())
            .is_some_and(|n| n.starts_with("psc-menu-") && n.ends_with(".json"));
        if !is_menu_file {
            continue;
        }
        let expired = std::fs::metadata(&path)
            .ok()
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() < cutoff)
            .unwrap_or(false);
        if expired {
            let _ = std::fs::remove_file(&path);
        }
    }
}

pub fn run(input_path: &str) -> Output {
    let input = match load_input(input_path) {
        Ok(i) => i,
        Err(e) => return Output::error(format!("failed to read input: {e}")),
    };

    if let Some(ord) = input.order.clone() {
        std::thread::spawn(move || crate::menu::order::compute_and_write_order(&ord));
    }
    if !input.order_dir.is_empty() {
        let dir = input.order_dir.clone();
        std::thread::spawn(move || crate::menu::order::cleanup_stale_order_files(&dir));
    }
    if !input.menu_dir.is_empty() {
        let dir = input.menu_dir.clone();
        std::thread::spawn(move || cleanup_stale_menu_files(&dir));
    }

    if input.items.is_empty() {
        return Output::cancel();
    }
    if input.terminal.buffer.h < 5 {
        return Output::min_area();
    }

    let mut cfg = input.config;
    cfg.resolve_tip_flags();
    if is_stale(&input.data_dir, &input.order_dir, &input.menu_dir) {
        let stale = cfg.filter_hint_stale.trim();
        if !stale.is_empty() {
            if cfg.filter_hint.is_empty() {
                cfg.filter_hint = stale.to_string();
            } else {
                cfg.filter_hint = format!("{} {}", cfg.filter_hint, stale);
            }
        }
    }
    let mut term = input.terminal;
    // Input-line cursor position, kept for restoring the system cursor on exit (before
    // `use_alt` rewrites `term.cursor.y` to 0).
    let origin_cursor = (term.cursor.x, term.cursor.y);

    let space_below = match &term.window {
        Some(w) => (w.top + w.h - 1 - term.cursor.y as i32).clamp(0, w.h),
        None => (term.buffer.h as i32 - term.cursor.y as i32 - 1).max(0),
    };
    let has_tip = cfg.flags.enable_tip && !input.items.is_empty();
    // `auto` renders inline below whenever the below space fits the normal menu spec (3 items +
    // a 4-line description); below that it switches to the alternate screen. Inline is pinned
    // below — `auto` never does an above-inline flip.
    let auto_alt = space_below < crate::menu::state::below_required(has_tip);
    // Unix always renders via the alternate screen (`Viewport::Fullscreen`), so it always counts
    // as "alternate" here. Windows follows `show_mode`'s rendering intent: `auto` uses the
    // alternate screen only when the space below the cursor cannot fit the menu; `inline-follow`
    // never does; `altscreen-follow` / `altscreen-top` / `altscreen-bottom` always do.
    let use_alt = term.platform != "windows"
        || match cfg.flags.show_mode.as_str() {
            "auto" => auto_alt,
            "inline-follow" => false,
            _ => true, // altscreen-follow / altscreen-top / altscreen-bottom
        };
    // Alternate-screen menu position, per `show_mode`:
    // - `auto` (alternate) / `inline-follow` / `altscreen-follow`: follow the input line; the
    //   layout flips above when the space above is larger than below.
    // - `altscreen-top`: always start at the top.
    // - `altscreen-bottom`: always start at the bottom (recompute_layout forces above).
    // `auto`'s inline form (below) never flips — see `force_below` in recompute_layout; on the
    // alternate screen it is delegated to `altscreen-follow` below.
    // The alternate screen is the visible window, so coordinates are relative to it
    // (`window.top` offset), not the whole scrollback buffer.
    let alt_cursor_y: u16 = if use_alt {
        let window_top = term.window.as_ref().map(|w| w.top).unwrap_or(0);
        let window_h = term
            .window
            .as_ref()
            .map(|w| w.h)
            .unwrap_or(term.buffer.h as i32);
        let rel_y = (term.cursor.y as i32 - window_top).max(0);
        match cfg.flags.show_mode.as_str() {
            "altscreen-top" => 0,
            // Cursor one row past the last rendered row: `pos_y = cursor_y - h`, so the menu
            // ends one row above the bottom (an empty last row, symmetric with altscreen-top's
            // empty top row).
            "altscreen-bottom" => window_h.saturating_sub(1) as u16,
            _ => rel_y as u16, // auto / inline-follow / altscreen-follow follow the input line
        }
    } else {
        term.cursor.y
    };
    if use_alt {
        // The alternate screen has the visible-window height; rebase the layout to it so the
        // menu renders from the mode-dependent start position within the screen.
        // `auto` on the alternate screen behaves like `altscreen-follow` (balance above/below
        // by space); its inline form (below) pins below via `force_below` in recompute_layout.
        if cfg.flags.show_mode.as_str() == "auto" {
            cfg.flags.show_mode = "altscreen-follow".into();
        }
        term.cursor.y = alt_cursor_y;
        if let Some(w) = term.window.as_mut() {
            term.buffer.h = w.h as u16;
            w.top = 0;
        }
    }

    let mut state = MenuState::new(input.items, &cfg, &term);
    if let Some(f) = input.initial_filter.as_deref() {
        state.with_initial_filter(f, &cfg, &term);
    }
    if state.filtered.is_empty() {
        return Output::cancel();
    }
    // Async switch symbol: menu draws immediately with static symbols.
    // A background peek computes whether the selected row has a next context beyond globals.
    let peek_input: Option<CompleteInput> = input
        .build
        .as_ref()
        .and_then(|v| serde_json::from_value::<CompleteInput>(v.clone()).ok());
    let switch_sym = cfg.context_switch.clone();
    let stay_sym = cfg.context_stay.clone();
    let (peek_req_tx, peek_req_rx) = mpsc::channel::<(u64, usize, String)>();
    let (peek_resp_tx, peek_resp_rx) = mpsc::channel::<(u64, usize, String)>();
    if let Some(pi) = peek_input.clone() {
        // Skip the entire peek computation when both symbols are empty —
        // there's nothing to display regardless of the result.
        if switch_sym.is_empty() && stay_sym.is_empty() {
            // fall through: channels stay alive, schedule_peek sends to
            // an unbounded mpsc whose consumer was never started, which is
            // harmless (a few tiny allocations per menu frame).
        } else {
            let sw = switch_sym.clone();
            let stay = stay_sym.clone();
            std::thread::spawn(move || {
                // Pre-parse the manifest tree once: every peek call reuses the same tree
                // for the fast-path static-candidate check and global-option extraction,
                // avoiding O(N) redundant manifest I/O across multiple peek requests.
                let static_tree = std::fs::read_to_string(&pi.manifest)
                    .ok()
                    .and_then(|text| {
                        serde_json::from_str::<serde_json::Value>(crate::strip_bom(&text)).ok()
                    })
                    .map(|json| completion::build_tree(&json));

                // Pre-compute parent items once (silent: no psc.log).
                let mut parent_input = pi.clone();
                parent_input.order = None;
                parent_input.log_dir = String::new();
                let parent_items: Vec<crate::engine::hooks::LuaItem> =
                    match crate::menu::protocol::build_candidate_items(&parent_input) {
                        Ok((items, _)) => items,
                        Err(_) => Vec::new(),
                    };

                while let Ok((gen, idx, cand)) = peek_req_rx.recv() {
                    // Drain all pending requests: when the user rapidly switches
                    // through candidates, only the latest request matters — skip
                    // the stale ones instead of processing them sequentially.
                    let mut latest = (gen, idx, cand);
                    while let Ok(next) = peek_req_rx.try_recv() {
                        latest = next;
                    }
                    let (gen, idx, cand) = latest;
                    let raw = match static_tree.as_ref() {
                        Some(tree) => crate::menu::protocol::peek_predict_symbol_with_tree_cached(
                            &pi,
                            &cand,
                            tree,
                            &parent_items,
                        ),
                        None => crate::menu::protocol::peek_predict_symbol(&pi, &cand),
                    };
                    let sym = match raw {
                        Some(s) if s == "switch" => sw.clone(),
                        Some(s) if s == "stay" => stay.clone(),
                        _ => String::new(),
                    };
                    let _ = peek_resp_tx.send((gen, idx, sym));
                }
            });
        }
    }
    let mut peek_gen: u64 = 0;
    let mut prev_sel = state.selected;
    let mut prev_len = state.filtered.len();
    let schedule_peek =
        |st: &mut MenuState, tx: &mpsc::Sender<(u64, usize, String)>, gen: &mut u64| {
            // No peek when there is no build context or when both symbols are disabled
            // (the peek thread is never spawned in that case, so nothing would clear the
            // pending flag — the static symbol must be shown as-is).
            if peek_input.is_none() || (switch_sym.is_empty() && stay_sym.is_empty()) {
                st.peek_pending = false;
                return;
            }
            let Some(idx) = st.selected_item_index() else {
                return;
            };
            if let Some(it) = st.items.get(idx) {
                if it.symbol == switch_sym {
                    st.peek_pending = false;
                    return;
                }
                // Already computed for this row in this menu session: its symbol is
                // fixed (depends only on the manifest + row text), so re-selecting it
                // while moving up/down must not recompute the peek.
                if st.peeked.get(idx).copied().unwrap_or(false) {
                    st.peek_pending = false;
                    return;
                }
                *gen += 1;
                st.peek_pending = true;
                let _ = tx.send((*gen, idx, it.completion_text.clone()));
            }
        };
    schedule_peek(&mut state, &peek_req_tx, &mut peek_gen);
    if state.min_area {
        if use_alt {
            // The alternate screen is fullscreen, so min_area should not happen; defensive fallback.
        } else {
            return Output::min_area();
        }
    }
    if cfg.flags.enable_apply_when_single && state.filtered.len() == 1 {
        return selected_output(&state, state.filtered[0]);
    }

    let unix_fullscreen = term.platform != "windows" || use_alt;
    // Restore the system cursor to the input line on exit only in inline (non-alternate)
    // mode. Alternate screen (`LeaveAlternateScreen`) restores the main-screen cursor
    // position itself, so a manual MoveTo there would use the wrong coordinate space.
    let restore_cursor = if unix_fullscreen {
        None
    } else {
        Some(origin_cursor)
    };
    // Alternate screen: start drawing at the menu position (input line or top).
    let alt_start_y = if use_alt { alt_cursor_y } else { 0 };
    let guard = TermGuard::install(unix_fullscreen, alt_start_y, restore_cursor);
    let backend = ratatui::backend::CrosstermBackend::new(std::io::stdout());
    let viewport = if unix_fullscreen {
        Viewport::Fullscreen
    } else {
        Viewport::Fixed(Rect::new(0, 0, term.buffer.w, term.buffer.h))
    };
    let mut terminal = match Terminal::with_options(backend, TerminalOptions { viewport }) {
        Ok(t) => t,
        Err(e) => {
            drop(guard);
            return Output::error(format!("terminal init failed: {e}"));
        }
    };

    let mut last_click: Option<(Instant, usize)> = None;
    // Blinking-cursor phase: flipped by time (independent of the loop rate; accurate even
    // while idle-polling at 50ms).
    let mut last_blink = Instant::now();
    let mut last_heartbeat = Instant::now();
    let result = loop {
        // Drain completed peeks: a row's symbol does not depend on the current
        // selection, so every response is applied and remembered (avoiding a
        // recompute when the row is selected again). Only the response matching the
        // current request clears the pending flag — stale responses must not unhide
        // the selected row's symbol while its own peek is still in flight.
        while let Ok((gen, idx, sym)) = peek_resp_rx.try_recv() {
            if let Some(it) = state.items.get_mut(idx) {
                it.symbol = sym;
            }
            if let Some(p) = state.peeked.get_mut(idx) {
                *p = true;
            }
            if gen == peek_gen {
                state.peek_pending = false;
            }
        }
        if last_blink.elapsed() >= Duration::from_millis(500) {
            state.cursor_on = !state.cursor_on;
            last_blink = Instant::now();
        }
        if last_heartbeat.elapsed() >= Duration::from_secs(15) {
            let _ = writeln!(std::io::stderr(), "HBT");
            last_heartbeat = Instant::now();
        }
        if let Err(e) = terminal.draw(|f| ui::render(f, &mut state, &term, &cfg)) {
            break Err(format!("draw failed: {e}"));
        }
        let has_input = match crossterm::event::poll(Duration::from_millis(50)) {
            Ok(h) => h,
            Err(e) => break Err(format!("input poll failed: {e}")),
        };
        if !has_input {
            continue;
        }
        let event = match read() {
            Ok(ev) => ev,
            Err(e) => break Err(format!("input failed: {e}")),
        };
        let action = match event {
            Event::Key(k) => handle_key(&mut state, &cfg, &term, k),
            Event::Mouse(m) => handle_mouse(&mut state, &cfg, m, &mut last_click),
            Event::Resize(new_w, new_h) => {
                state.resize(&cfg, &mut term, new_w, new_h);
                let _ = terminal.resize(Rect::new(0, 0, new_w, new_h));
                None
            }
            _ => None,
        };
        match action {
            Some(Action::Select) => {
                if let Some(i) = state.selected_item_index() {
                    break Ok(selected_output(&state, i));
                }
            }
            Some(Action::Cancel) => break Ok(Output::cancel()),
            Some(Action::Input(text)) => break Ok(Output::input(text)),
            None => {}
        }
        // Schedule async switch peek when selection or filter changed.
        if state.selected != prev_sel || state.filtered.len() != prev_len {
            prev_sel = state.selected;
            prev_len = state.filtered.len();
            schedule_peek(&mut state, &peek_req_tx, &mut peek_gen);
        }
    };

    drop(terminal);
    drop(guard);
    match result {
        Ok(mut out) => {
            out.is_show_above = Some(state.is_show_above);
            if state.has_covered() {
                out.covered_top = Some(state.covered_top);
                out.covered_bottom = Some(state.covered_bottom);
            }
            if use_alt {
                out.alternate = Some(true);
            }
            out
        }
        Err(e) => Output::error(e),
    }
}

fn handle_key(
    state: &mut MenuState,
    cfg: &Config,
    term: &TerminalInfo,
    key: KeyEvent,
) -> Option<Action> {
    // Ignore the Release half of Windows' Press+Release event pair.
    if key.kind == KeyEventKind::Release {
        return None;
    }
    let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
    let shift = key.modifiers.contains(KeyModifiers::SHIFT);
    match key.code {
        KeyCode::Esc => return Some(Action::Cancel),
        KeyCode::Enter | KeyCode::Char(' ') if !state.filtered.is_empty() => {
            return Some(Action::Select);
        }
        KeyCode::Backspace => {
            if state.filter.is_empty() {
                return Some(Action::Cancel);
            }
            state.backspace_at_cursor();
            if let Some(act) = apply_filter(state, cfg, term) {
                return Some(act);
            }
        }
        KeyCode::Delete => {
            if state.filter.is_empty() {
                return Some(Action::Cancel);
            }
            state.delete_at_cursor();
            if let Some(act) = apply_filter(state, cfg, term) {
                return Some(act);
            }
        }
        KeyCode::Left => state.move_cursor_left(),
        KeyCode::Right => state.move_cursor_right(),
        KeyCode::Home => state.move_cursor_home(),
        KeyCode::End => state.move_cursor_end(),
        KeyCode::BackTab => state.move_selection(false, cfg),
        KeyCode::Tab => {
            if shift {
                state.move_selection(false, cfg);
            } else if state.filtered.len() == 1 {
                return Some(Action::Select);
            } else {
                state.move_selection(true, cfg);
            }
        }
        KeyCode::Up => state.move_selection(false, cfg),
        KeyCode::Down => state.move_selection(true, cfg),
        KeyCode::Char(c) => {
            if ctrl {
                match c {
                    'c' => return Some(Action::Cancel),
                    'u' | 'p' | 'k' => state.move_selection(false, cfg),
                    'd' | 'n' | 'j' => state.move_selection(true, cfg),
                    _ => {}
                }
            } else if c == '^' && state.cursor == 0 && !state.filter.starts_with('^') {
                state.make_prefix();
                if let Some(act) = apply_filter(state, cfg, term) {
                    return Some(act);
                }
            } else {
                state.insert_at_cursor(c);
                if let Some(act) = apply_filter(state, cfg, term) {
                    return Some(act);
                }
            }
        }
        _ => {}
    }
    None
}

fn apply_filter(state: &mut MenuState, cfg: &Config, term: &TerminalInfo) -> Option<Action> {
    match state.apply_filter(cfg, term) {
        FilterOutcome::Input(text) => Some(Action::Input(text)),
        FilterOutcome::None => None,
    }
}

/// Mouse: left-click selects; double-click within 400ms confirms; wheel scrolls list or description.
fn handle_mouse(
    state: &mut MenuState,
    cfg: &Config,
    m: MouseEvent,
    last_click: &mut Option<(Instant, usize)>,
) -> Option<Action> {
    let item_top = if state.is_show_above { 0 } else { 2 } as u16;
    let list_top = state.pos.1;
    let hit = if m.row >= list_top + item_top
        && m.row < list_top + item_top + (state.page_max as u16 + 1)
    {
        let rel = m.row - (list_top + item_top);
        Some(state.offset + rel as usize)
    } else {
        None
    };
    match m.kind {
        MouseEventKind::ScrollDown => {
            if tip_wheel_target(state, m) {
                state.scroll_tip(1);
            } else {
                state.move_selection(true, cfg);
            }
            None
        }
        MouseEventKind::ScrollUp => {
            if tip_wheel_target(state, m) {
                state.scroll_tip(-1);
            } else {
                state.move_selection(false, cfg);
            }
            None
        }
        MouseEventKind::Down(MouseButton::Left) => {
            let idx = hit?;
            let now = Instant::now();
            let is_double = matches!(last_click, Some((t, i)) if *i == idx && now.duration_since(*t) < Duration::from_millis(400));
            *last_click = Some((now, idx));
            state.jump(idx, cfg);
            if is_double {
                Some(Action::Select)
            } else {
                None
            }
        }
        _ => None,
    }
}

/// Whether the wheel should act on the description container (the cursor is inside the
/// description box and it is scrollable).
fn tip_wheel_target(state: &MenuState, m: MouseEvent) -> bool {
    if state.tip_scroll_max == 0 {
        return false;
    }
    match state.tip_box_rect {
        Some((x, y, w, h)) => m.row >= y && m.row < y + h && m.column >= x && m.column < x + w,
        None => false,
    }
}

fn load_input(path: &str) -> Result<crate::menu::model::Input, String> {
    let data = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    serde_json::from_str(&data).map_err(|e| e.to_string())
}

/// Restores the terminal when dropped, even during unwinding.
struct TermGuard {
    unix_fullscreen: bool,
    /// Where to move the system cursor before showing it again (the input-line position the
    /// menu was opened from). Moving it back first prevents it flashing at the last drawn
    /// spot (e.g. under the description container after cycling items).
    restore_cursor: Option<(u16, u16)>,
}

impl TermGuard {
    fn install(
        unix_fullscreen: bool,
        alt_start_y: u16,
        restore_cursor: Option<(u16, u16)>,
    ) -> Self {
        let _ = enable_raw_mode();
        // Hide the system cursor on ALL platforms: the menu draws its own blinking bar on the
        // filter row, so a visible system cursor (which stays near the first item in inline
        // mode) would appear as a second cursor and flicker on open.
        let _ = crossterm::execute!(std::io::stdout(), crossterm::cursor::Hide);
        if unix_fullscreen {
            // Enter the alternate screen first (the terminal saves the input-line cursor
            // position so it can restore it on leave), THEN move to the menu start so the
            // fullscreen menu draws from there (input line, or the top when it doesn't fit).
            let _ = crossterm::execute!(std::io::stdout(), EnterAlternateScreen);
            let _ =
                crossterm::execute!(std::io::stdout(), crossterm::cursor::MoveTo(0, alt_start_y));
        }
        let _ = crossterm::execute!(std::io::stdout(), EnableMouseCapture);
        TermGuard {
            unix_fullscreen,
            restore_cursor,
        }
    }
}

impl Drop for TermGuard {
    fn drop(&mut self) {
        let _ = crossterm::execute!(std::io::stdout(), DisableMouseCapture);
        if let Some((x, y)) = self.restore_cursor {
            // Move back to the input line before showing, so the cursor never flashes at a
            // menu-drawn position on exit.
            let _ = crossterm::execute!(std::io::stdout(), crossterm::cursor::MoveTo(x, y));
        }
        if self.unix_fullscreen {
            let _ = crossterm::execute!(std::io::stdout(), LeaveAlternateScreen);
        }
        let _ = crossterm::execute!(std::io::stdout(), crossterm::cursor::Show);
        let _ = disable_raw_mode();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::menu::model::{Config, Flags, Item, Pos, Size, TerminalInfo};

    // --- is_stale: six-branch fs matrix guarding the stale-hint feature ---

    fn stale_dir(tag: &str) -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let base = std::env::temp_dir().join(format!(
            "psc-stale-{}-{}-{}",
            tag,
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir_all(base.join("temp")).unwrap();
        base
    }

    fn write_change(dir: &std::path::Path, content: &str) {
        std::fs::write(dir.join("temp/change.json"), content).unwrap();
    }

    #[test]
    fn stale_missing_file() {
        let d = stale_dir("missing");
        let data = d.to_str().unwrap();
        assert!(is_stale(data, data, ""));
        std::fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn stale_fresh_timestamp_not_stale() {
        let d = stale_dir("fresh");
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        write_change(&d, &format!(r#"{{"last_check":{now}}}"#));
        let data = d.to_str().unwrap();
        assert!(!is_stale(data, data, ""));
        std::fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn stale_older_than_seven_days() {
        let d = stale_dir("old");
        let old = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs()
            - 604_801;
        write_change(&d, &format!(r#"{{"last_check":{old}}}"#));
        let data = d.to_str().unwrap();
        assert!(is_stale(data, data, ""));
        std::fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn stale_future_clock_skew_treated_as_fresh() {
        let d = stale_dir("future");
        let future = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs()
            + 100_000;
        write_change(&d, &format!(r#"{{"last_check":{future}}}"#));
        let data = d.to_str().unwrap();
        assert!(!is_stale(data, data, ""));
        std::fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn stale_corrupt_json_is_stale() {
        let d = stale_dir("corrupt");
        write_change(&d, "garbage{{{");
        let data = d.to_str().unwrap();
        assert!(is_stale(data, data, ""));
        std::fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn stale_bom_prefixed_json_still_parses() {
        let d = stale_dir("bom");
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        write_change(&d, &format!("\u{feff}{{\"last_check\":{now}}}"));
        let data = d.to_str().unwrap();
        assert!(!is_stale(data, data, ""));
        std::fs::remove_dir_all(&d).ok();
    }

    #[test]
    fn stale_legacy_derivation_fallback() {
        // When data_dir is empty and order_dir is present, the legacy parent-chain
        // derivation should still work.
        let d = stale_dir("legacy");
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        write_change(&d, &format!(r#"{{"last_check":{now}}}"#));
        let order = d.join("temp/order").to_str().unwrap().to_string();
        assert!(!is_stale("", &order, ""));
        std::fs::remove_dir_all(&d).ok();
    }

    fn cfg() -> Config {
        Config {
            filter_hint: String::new(),
            filter_hint_stale: String::new(),
            flags: Flags {
                enable_list_loop: true,
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

    fn term() -> TerminalInfo {
        TerminalInfo {
            cursor: Pos { x: 0, y: 10 },
            buffer: Size { w: 80, h: 24 },
            window: None,
            platform: "test".into(),
        }
    }

    fn items() -> Vec<Item> {
        ["config", "completion", "update"]
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
            .collect()
    }

    fn char_key(c: char) -> KeyEvent {
        KeyEvent::new(KeyCode::Char(c), KeyModifiers::empty())
    }

    #[test]
    fn no_match_reverts_filter_and_restores_cursor() {
        let c = cfg();
        let mut s = MenuState::new(items(), &c, &term());
        // Type "on", cursor at the end.
        handle_key(&mut s, &c, &term(), char_key('o'));
        handle_key(&mut s, &c, &term(), char_key('n'));
        assert_eq!(s.filter, "on");
        // Insert "A" in the middle ("oAn" does not match) → reverts to "on", cursor back between o and n.
        handle_key(
            &mut s,
            &c,
            &term(),
            KeyEvent::new(KeyCode::Home, KeyModifiers::empty()),
        );
        handle_key(
            &mut s,
            &c,
            &term(),
            KeyEvent::new(KeyCode::Right, KeyModifiers::empty()),
        );
        assert_eq!(s.cursor, 1);
        handle_key(&mut s, &c, &term(), char_key('A'));
        assert_eq!(s.filter, "on", "non-matching insert reverts the filter");
        assert_eq!(s.cursor, 1, "cursor must return to its pre-edit position");
        // Insert "^" at the start ("^on" prefix does not match) → also reverts to "on",
        // the cursor returns to the start (no longer drifting right).
        handle_key(
            &mut s,
            &c,
            &term(),
            KeyEvent::new(KeyCode::Home, KeyModifiers::empty()),
        );
        assert_eq!(s.cursor, 0);
        handle_key(&mut s, &c, &term(), char_key('^'));
        assert_eq!(s.filter, "on", "non-matching prefix also reverts");
        assert_eq!(
            s.cursor, 0,
            "cursor must not drift right after a reverted caret"
        );
        assert!(!s.is_prefix);
    }

    #[test]
    fn matching_prefix_is_kept() {
        let c = cfg();
        let mut s = MenuState::new(items(), &c, &term());
        // Empty filter + "^" → prefix mode, the empty pattern matches everything.
        handle_key(&mut s, &c, &term(), char_key('^'));
        assert_eq!(s.filter, "^");
        assert!(s.is_prefix);
        // Type "c" → "^c" prefix-matches config / completion.
        handle_key(&mut s, &c, &term(), char_key('c'));
        assert_eq!(s.filter, "^c");
        assert!(s.is_prefix);
        assert!(!s.filtered.is_empty());
    }
}
