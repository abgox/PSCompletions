//! Sandbox creation and hook execution (deadline, instruction-count hook, result assembly).
//! See `design/hooks.md`.

use mlua::{HookTriggers, Lua, LuaOptions, StdLib, Table, Value, VmState};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use super::api::{items_to_table, table_to_items};
use super::bindings::build_psc_table;
use super::{HookContext, LuaItem};

/// The running hook's total deadline as unix milliseconds (0 = none). A process global —
/// not a thread-local — so `psc.run_batch`'s worker threads see it too and cut their
/// subprocesses short once the hook's budget is spent. One hook runs at a time per
/// process, so a single slot is enough.
pub(crate) static HOOK_DEADLINE_MS: AtomicU64 = AtomicU64::new(0);

/// Current unix time in milliseconds (0 fallback on clock error).
pub(crate) fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

struct HookDeadlineGuard;
impl Drop for HookDeadlineGuard {
    fn drop(&mut self) {
        HOOK_DEADLINE_MS.store(0, Ordering::SeqCst);
    }
}

/// Create the restricted Lua VM (sandbox, see `design/hooks.md`).
pub(crate) fn new_sandbox_lua() -> mlua::Result<Lua> {
    let lua = Lua::new_with(
        StdLib::TABLE
            | StdLib::STRING
            | StdLib::MATH
            | StdLib::UTF8
            | StdLib::COROUTINE
            | StdLib::OS,
        LuaOptions::default(),
    )?;
    let globals = lua.globals();
    for name in [
        "io", "package", "require", "dofile", "loadfile", "load", "debug",
    ] {
        globals.raw_set(name, Value::Nil)?;
    }
    let os: Table = globals.raw_get("os")?;
    for name in ["execute", "exit", "remove", "rename", "tmpname", "getenv"] {
        os.raw_set(name, Value::Nil)?;
    }
    Ok(lua)
}

/// Total hook-script execution cap (10s, per `design/hooks.md`).
const HOOK_TIMEOUT: Duration = Duration::from_secs(10);

/// Instruction-counting interval: the timeout is polled every this many VM instructions.
const HOOK_INSTRUCTION_INTERVAL: u32 = 1_000_000;

/// Execute a `hooks.lua` script with the default timeout.
pub fn run_hook(
    context: &HookContext,
    script: &str,
    static_items: &[LuaItem],
) -> mlua::Result<Vec<LuaItem>> {
    run_hook_with_timeout(context, script, static_items, HOOK_TIMEOUT)
}

/// Implementation of `run_hook`; the caller supplies the timeout (so tests can use a short one).
pub(crate) fn run_hook_with_timeout(
    context: &HookContext,
    script: &str,
    static_items: &[LuaItem],
    timeout: Duration,
) -> mlua::Result<Vec<LuaItem>> {
    let lua = new_sandbox_lua()?;
    let deadline = Instant::now() + timeout;
    HOOK_DEADLINE_MS.store(now_ms() + timeout.as_millis() as u64, Ordering::SeqCst);
    let _deadline_guard = HookDeadlineGuard;
    lua.set_hook(
        HookTriggers::new().every_nth_instruction(HOOK_INSTRUCTION_INTERVAL),
        {
            move |_lua, _dbg| -> mlua::Result<VmState> {
                if Instant::now() >= deadline {
                    Err(mlua::Error::RuntimeError(format!(
                        "hook execution timed out after {}s",
                        timeout.as_secs_f64()
                    )))
                } else {
                    Ok(VmState::Continue)
                }
            }
        },
    )?;
    let symbols = std::rc::Rc::new(std::cell::RefCell::new(std::collections::HashMap::<
        String,
        (String, bool),
    >::new()));
    let tips = std::rc::Rc::new(std::cell::RefCell::new(std::collections::HashMap::<
        String,
        ((String, String), bool),
    >::new()));
    let psc = build_psc_table(&lua, context, symbols.clone(), tips.clone())?;
    lua.globals().set("psc", psc)?;
    lua.globals()
        .set("completions", items_to_table(&lua, static_items)?)?;
    let result: Value = lua.load(script).call(())?;
    let mut items = match result {
        Value::Nil => static_items.to_vec(),
        Value::Table(t) => table_to_items(&t)?,
        // A stray return value (e.g. `return "x"`) is almost always a hook bug; fail loudly
        // instead of silently dropping every dynamic item.
        other => {
            return Err(mlua::Error::RuntimeError(format!(
                "hook must return an array of items or nothing, got {other:?}"
            )))
        }
    };
    // Repeat-filter only hook-added items; static ones were already filtered on the resolve side
    let static_texts: std::collections::HashSet<String> =
        static_items.iter().map(|i| i.text.to_lowercase()).collect();
    let mut used: std::collections::HashMap<String, i32> = std::collections::HashMap::new();
    for t in &context.tokens {
        let key = t
            .canonical
            .as_deref()
            .map(|c| c.to_lowercase())
            .unwrap_or_else(|| t.text.to_lowercase());
        *used.entry(key).or_insert(0) += 1;
    }
    if !used.is_empty() {
        items.retain(|item| {
            if static_texts.contains(&item.text.to_lowercase()) {
                return true;
            }
            let used_count = used.get(&item.text.to_lowercase()).copied().unwrap_or(0);
            !(item.repeat == 0 && used_count > 0 || item.repeat > 0 && used_count >= item.repeat)
        });
    }
    let overrides = symbols.borrow();
    if !overrides.is_empty() {
        for item in &mut items {
            for (key, (sym, case_sensitive)) in overrides.iter() {
                let matches = if *case_sensitive {
                    key == &item.text
                } else {
                    key.eq_ignore_ascii_case(&item.text)
                };
                if matches {
                    item.symbol = Some(sym.clone());
                    break;
                }
            }
        }
    }
    let tip_overrides = tips.borrow();
    if !tip_overrides.is_empty() {
        for item in &mut items {
            for (key, ((tip, mode), case_sensitive)) in tip_overrides.iter() {
                let matches = if *case_sensitive {
                    key == &item.text
                } else {
                    key.eq_ignore_ascii_case(&item.text)
                };
                if matches {
                    match mode.as_str() {
                        "prepend" => {
                            item.tip =
                                Some(format!("{tip}\n{}", item.tip.clone().unwrap_or_default()))
                        }
                        "append" => {
                            item.tip =
                                Some(format!("{}\n{tip}", item.tip.clone().unwrap_or_default()))
                        }
                        _ => item.tip = Some(tip.clone()),
                    }
                    break;
                }
            }
        }
    }
    Ok(items)
}
