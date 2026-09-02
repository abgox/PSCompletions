//! Sandbox creation and hook execution (deadline, instruction-count hook, result assembly).
//! See `design/hooks.md`.

use mlua::{HookTriggers, Lua, LuaOptions, StdLib, Table, Value, VmState};
use std::time::{Duration, Instant};

use super::api::{items_to_table, table_to_items};
use super::bindings::build_psc_table;
use super::{HookContext, LuaItem};

/// The running hook's total deadline as `Instant` (None = none). A process global —
/// not a thread-local — so `psc.run_batch`'s worker threads see it too and cut their
/// subprocesses short once the hook's budget is spent. One hook runs at a time per
/// process, so a single slot is enough. Uses `Instant` to avoid `SystemTime` clock skew.
pub(crate) static HOOK_DEADLINE: std::sync::Mutex<Option<Instant>> = std::sync::Mutex::new(None);

pub(crate) fn is_hook_expired() -> bool {
    if let Ok(guard) = HOOK_DEADLINE.try_lock() {
        if let Some(dl) = *guard {
            return Instant::now() >= dl;
        }
    }
    false
}

struct HookDeadlineGuard;
impl Drop for HookDeadlineGuard {
    fn drop(&mut self) {
        if let Ok(mut guard) = HOOK_DEADLINE.lock() {
            *guard = None;
        }
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
    let script = psc_common::strip_bom(script);
    let deadline = Instant::now() + timeout;
    if let Ok(mut guard) = HOOK_DEADLINE.lock() {
        *guard = Some(deadline);
    }
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
    // The ONE live candidate list: seeded with static expansion, mutated by handlers
    // (via the implicit `psc.add` target) and read back when the hook returns nothing.
    let live = items_to_table(&lua, static_items)?;
    let add_target: super::bindings::AddTarget =
        std::rc::Rc::new(std::cell::RefCell::new(live.clone()));
    let on_depth: super::bindings::OnDepth = std::rc::Rc::new(std::cell::Cell::new(0));
    let injected: std::rc::Rc<std::cell::Cell<bool>> =
        std::rc::Rc::new(std::cell::Cell::new(false));
    let psc = build_psc_table(
        &lua,
        context,
        add_target.clone(),
        on_depth,
        injected.clone(),
    )?;
    lua.globals().set("psc", psc)?;
    lua.globals().set("completions", live.clone())?;
    let result: Value = lua.load(script).call(())?;
    let explicit_return = matches!(result, Value::Table(_));
    // For reordering: dynamic items should appear before static so users quickly see
    // the contextual completions; history-based ordering in the menu layer will then
    // apply within that merged sequence.
    let static_texts: std::collections::HashSet<String> =
        static_items.iter().map(|i| i.text.to_lowercase()).collect();
    let mut items = match result {
        // Nothing returned → the live candidate list (static seed + every registered
        // contribution) is the result. Reorder to put dynamic first.
        Value::Nil => {
            let snapshot = add_target.borrow().clone();
            let all = table_to_items(&snapshot)?;
            let mut dynamic = Vec::new();
            let mut stat = Vec::new();
            for item in all {
                if static_texts.contains(&item.text.to_lowercase()) {
                    stat.push(item);
                } else {
                    dynamic.push(item);
                }
            }
            dynamic.extend(stat);
            dynamic
        }
        Value::Table(t) => table_to_items(&t)?,
        // A stray return value (e.g. `return "x"`) is almost always a hook bug; fail loudly
        // instead of silently dropping every dynamic item.
        other => {
            return Err(mlua::Error::RuntimeError(format!(
                "hook must return an array of items or nothing, got {other:?}"
            )))
        }
    };
    // Mixing warning: an explicit return REPLACES the candidate list, discarding any
    // psc.on contributions made during this build. Surface it instead of hiding it.
    if injected.get() && explicit_return {
        let msg = format!(
            "[{}{}] warning: explicit return discarded psc.on contributions\n",
            context.cmd,
            if context.path.is_empty() {
                String::new()
            } else {
                format!(" {}", context.path.join(" "))
            },
        );
        super::api::append_log(&context.log_dir, "error", &msg);
    }
    // Repeat-filter only hook-added items; static ones were already filtered on the resolve side
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
    Ok(items)
}
