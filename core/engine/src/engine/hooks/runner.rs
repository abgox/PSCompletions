//! Sandbox creation and hook execution (deadline, instruction-count hook, result assembly).
//! See `design/hooks.md`.

use mlua::{HookTriggers, Lua, LuaOptions, StdLib, Table, Value, VmState};
use std::time::{Duration, Instant};

use super::api::{items_to_table, resolve_localized, resolve_usage_example, table_to_items};
use super::bindings::build_psc_table;
use super::{HookContext, LazyEntry, LazyField, LuaItem};

/// The running hook's total deadline as `Instant` (None = none). A process global —
/// not a thread-local — so `psc.run_batch`'s worker threads see it too and cut their
/// subprocesses short once the hook's budget is spent. One hook runs at a time per
/// process, so a single slot is enough. Uses `Instant` to avoid `SystemTime` clock skew.
pub(crate) static HOOK_DEADLINE: std::sync::Mutex<Option<Instant>> = std::sync::Mutex::new(None);

/// The running hook's deadline, or `None` when no hook is running / the slot is contended.
/// Read it from a blocking `psc.*` call (one that executes no Lua instructions, so the
/// instruction-count hook cannot interrupt it) to cut that call short instead of hanging.
pub(crate) fn hook_deadline() -> Option<Instant> {
    HOOK_DEADLINE.try_lock().ok().and_then(|g| *g)
}

pub(crate) fn is_hook_expired() -> bool {
    hook_deadline().is_some_and(|dl| Instant::now() >= dl)
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

/// Per-field lazy evaluation budget: a single tip/usage/example callback must be a
/// fast local read (a manifest parse is milliseconds). This only guards hangs —
/// `psc.run` inside a callback observes the same deadline and is cut short too.
const LAZY_EVAL_TIMEOUT: Duration = Duration::from_secs(5);

/// A kept-alive hook VM plus its unevaluated lazy callbacks, owned by the menu
/// session on the main thread for the whole TUI lifetime. Selections resolve
/// callbacks on demand; everything else (peeks, cache, repeat filtering) only
/// ever sees plain strings.
pub struct HookSession {
    lua: Lua,
    lazy: Vec<LazyEntry>,
    language: String,
    log_dir: String,
    cmd: String,
}

impl HookSession {
    /// Whether any lazy callback is still unresolved.
    pub fn has_pending(&self) -> bool {
        !self.lazy.is_empty()
    }

    /// Drop lazy entries whose rows are gone from the final list (repeat /
    /// separator filtering dropped them after the hook ran). Keyed by text,
    /// orphans could never resolve — prune once, at handoff, instead.
    pub fn prune_to(&mut self, items: &[LuaItem]) {
        if self.lazy.is_empty() {
            return;
        }
        let live: std::collections::HashSet<String> =
            items.iter().map(|i| i.text.clone()).collect();
        self.lazy.retain(|e| live.contains(&e.key));
    }

    /// Drain pending lazy entries for the item text, evaluate each, and return
    /// (field, resolved text) pairs. Every entry resolves at most once — failures
    /// (error/timeout) cache as empty and are logged once to `error.log`.
    pub fn resolve_for(&mut self, key: &str) -> Vec<(LazyField, Option<String>)> {
        self.resolve_for_with_timeout(key, LAZY_EVAL_TIMEOUT)
    }

    /// Implementation of `resolve_for` with an explicit budget (so tests can use
    /// a short one).
    pub fn resolve_for_with_timeout(
        &mut self,
        key: &str,
        timeout: Duration,
    ) -> Vec<(LazyField, Option<String>)> {
        let mut pending = Vec::new();
        let mut kept = Vec::new();
        for e in self.lazy.drain(..) {
            if e.key == key {
                pending.push(e);
            } else {
                kept.push(e);
            }
        }
        self.lazy = kept;
        pending
            .into_iter()
            .map(|e| {
                let text = self.eval_one(&e, timeout);
                (e.field, text)
            })
            .collect()
    }

    fn eval_one(&mut self, entry: &LazyEntry, timeout: Duration) -> Option<String> {
        let _deadline_guard = arm_timeout(&self.lua, timeout).ok()?;
        let result: Value = match entry.func.call(()) {
            Ok(v) => v,
            Err(e) => {
                super::log_hook_error(&self.log_dir, &self.cmd, " (lazy tip)", &e);
                return None;
            }
        };
        // A callback returning another function is a hook bug, not a nested lazy level.
        if matches!(
            result,
            Value::Function(_) | Value::Thread(_) | Value::UserData(_) | Value::LightUserData(_)
        ) {
            return None;
        }
        let resolved = match entry.field {
            LazyField::Tip => resolve_localized(&self.lua, Some(result), &self.language),
            LazyField::Usage | LazyField::Example => resolve_usage_example(&self.lua, result),
        };
        match resolved {
            Ok(t) => t,
            Err(e) => {
                super::log_hook_error(&self.log_dir, &self.cmd, " (lazy tip)", &e);
                None
            }
        }
    }
}

/// Arm the VM instruction-count hook + the process-global deadline for `timeout`.
/// The returned guard clears the global slot on drop. Shared by full-hook runs
/// and single lazy evaluations.
fn arm_timeout(lua: &Lua, timeout: Duration) -> mlua::Result<HookDeadlineGuard> {
    let deadline = Instant::now() + timeout;
    if let Ok(mut guard) = HOOK_DEADLINE.lock() {
        *guard = Some(deadline);
    }
    lua.set_hook(
        HookTriggers::new().every_nth_instruction(HOOK_INSTRUCTION_INTERVAL),
        move |_lua, _dbg| -> mlua::Result<VmState> {
            if Instant::now() >= deadline {
                Err(mlua::Error::RuntimeError(format!(
                    "hook execution timed out after {}s",
                    timeout.as_secs_f64()
                )))
            } else {
                Ok(VmState::Continue)
            }
        },
    )?;
    Ok(HookDeadlineGuard)
}

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
    Ok(run_hook_keepalive_with_timeout(context, script, static_items, timeout)?.0)
}
/// Execute a `hooks.lua` script with the default timeout, keeping the VM and its
/// lazy callbacks alive for the menu session. Plain `run_hook` callers (tests,
/// peeks) use the dropping wrapper and see no behavior change.
pub(crate) fn run_hook_keepalive(
    context: &HookContext,
    script: &str,
    static_items: &[LuaItem],
) -> mlua::Result<(Vec<LuaItem>, HookSession)> {
    run_hook_keepalive_with_timeout(context, script, static_items, HOOK_TIMEOUT)
}

/// Implementation of `run_hook` with a kept-alive session: same as
/// `run_hook_with_timeout` but returns the VM and its lazy callbacks for the
/// menu session instead of dropping them. Plain `run_hook` callers (tests,
/// peeks) use the dropping wrapper and see no behavior change.
pub(crate) fn run_hook_keepalive_with_timeout(
    context: &HookContext,
    script: &str,
    static_items: &[LuaItem],
    timeout: Duration,
) -> mlua::Result<(Vec<LuaItem>, HookSession)> {
    let lua = new_sandbox_lua()?;
    let script = psc_common::strip_bom(script);
    let _deadline_guard = arm_timeout(&lua, timeout)?;
    let mut lazy: Vec<LazyEntry> = Vec::new();
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
            let all = table_to_items(&lua, &snapshot, &mut lazy)?;
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
        Value::Table(t) => table_to_items(&lua, &t, &mut lazy)?,
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
    let session = HookSession {
        lua,
        lazy,
        language: context.language.clone(),
        log_dir: context.log_dir.clone(),
        cmd: context.cmd.clone(),
    };
    Ok((items, session))
}
