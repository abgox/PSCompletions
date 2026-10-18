//! Shared helpers, the independent `psc.env`, and module-level re-exports of the `psc.*`
//! capability groups (run / fs / formats / items). Contract: `design/hooks.md` §5.

mod formats;
mod fs;
mod items;
mod run;

use mlua::{Lua, Table, Value};

/// Coerce a Lua value to a string using `tostring` semantics (numbers/bools included).
/// Returns `None` for `nil` or un-coercible values — a nil argument to a `psc.*` API must
/// never crash the hook, it just yields "no result" (see `design/hooks.md` §nil-safety).
pub(crate) fn coerce_string_opt(lua: &Lua, v: Value) -> mlua::Result<Option<String>> {
    Ok(lua.coerce_string(v)?.map(|s| s.to_string_lossy()))
}

pub(crate) use super::LuaItem;
use super::{LazyEntry, LazyField};
/// Resolve a tip value to text: a plain string is used as-is; a **localized table**
/// `{ ["en-US"] = "...", ["zh-CN"] = "..." }` picks the entry matching `language`
/// (fallback `"en-US"`, then the first entry). Nil/other → None.
pub(crate) fn resolve_localized(
    lua: &Lua,
    tip: Option<Value>,
    language: &str,
) -> mlua::Result<Option<String>> {
    let Some(v) = tip else {
        return Ok(None);
    };
    match v {
        Value::String(s) => Ok(Some(s.to_str()?.to_string())),
        Value::Table(t) => {
            if let Ok(Some(s)) = t.get::<Option<String>>(language) {
                return Ok(Some(s));
            }
            if let Ok(Some(s)) = t.get::<Option<String>>("en-US") {
                return Ok(Some(s));
            }
            if let Some((_, val)) = t.pairs::<String, String>().flatten().next() {
                return Ok(Some(val));
            }
            let _ = lua;
            Ok(None)
        }
        Value::Boolean(b) => Ok(Some(b.to_string())),
        _ => Ok(coerce_string_opt(lua, v)?),
    }
}

/// Resolve a usage/example value: a plain string is used as-is; a `{ cmd, desc }`
/// object renders as `cmd  # desc` (just `cmd` without desc, dropped without cmd) —
/// mirroring the static manifest's object entries. Nil/other → None.
pub(crate) fn resolve_usage_example(lua: &Lua, v: Value) -> mlua::Result<Option<String>> {
    match v {
        Value::Nil => Ok(None),
        Value::String(s) => Ok(Some(s.to_str()?.to_string())),
        Value::Table(t) => {
            let cmd = t
                .get::<Option<String>>("cmd")?
                .map(|c| c.trim().to_string())
                .filter(|c| !c.is_empty());
            let Some(cmd) = cmd else {
                return Ok(None);
            };
            let desc = t
                .get::<Option<String>>("desc")?
                .map(|d| d.trim().to_string())
                .filter(|d| !d.is_empty());
            Ok(Some(match desc {
                Some(d) => format!("{cmd}  # {d}"),
                None => cmd,
            }))
        }
        _ => Ok(coerce_string_opt(lua, v)?),
    }
}
/// Take a lock, recovering from poisoning: a worker that panicked while holding it poisons the
/// mutex, and `lock().unwrap()` would then panic every later access — one worker's death turning
/// into a cascade. The panic still propagates at scope exit (see `parallel_map`); the slots fill.
fn lock_recover<T>(m: &std::sync::Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// Bounded worker-pool parallelism: call `f` on each input, results in input order (std threads, no deps).
/// A panic in `f` propagates at scope exit (the worker threads are joined there), aborting the
/// call — callers pass non-panicking closures (IO reads returning `Result`/`Option`), so this is
/// acceptable; every slot is always written by its worker before the scope returns.
fn parallel_map<T: Sync, R: Send, F: Fn(&T) -> R + Sync>(inputs: &[T], f: F) -> Vec<R> {
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Mutex;
    if inputs.is_empty() {
        return Vec::new();
    }
    let workers = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(4)
        .clamp(1, 32);
    let next = AtomicUsize::new(0);
    let results: Mutex<Vec<Option<R>>> = Mutex::new((0..inputs.len()).map(|_| None).collect());
    std::thread::scope(|s| {
        for _ in 0..workers.min(inputs.len()) {
            s.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::SeqCst);
                if i >= inputs.len() {
                    break;
                }
                let val = f(&inputs[i]);
                lock_recover(&results)[i] = Some(val);
            });
        }
    });
    results
        .into_inner()
        .unwrap_or_else(|e| e.into_inner())
        .into_iter()
        .map(|o| o.expect("worker completed its slot"))
        .collect()
}

#[cfg(test)]
mod tests_lock_recover {
    use super::lock_recover;

    #[test]
    fn a_poisoned_lock_is_recovered_not_panicked_on() {
        // A worker that panics while holding the mutex poisons it; `lock().unwrap()` then panicked
        // on every later access, so one worker's death cascaded through the rest.
        let m = std::sync::Mutex::new(0);
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _held = m.lock().unwrap();
            panic!("a worker died holding the lock");
        }));
        assert!(
            m.is_poisoned(),
            "the lock must be poisoned for this test to mean anything"
        );
        *lock_recover(&m) = 1;
        assert_eq!(*lock_recover(&m), 1);
    }
}

/// `psc.env(name)` → environment variable (nil when unset).
pub(crate) fn api_env(lua: &Lua, name: String) -> mlua::Result<Option<String>> {
    let _ = lua;
    Ok(std::env::var(name).ok())
}

/// serde_json::Value → Lua Value.
pub(crate) fn json_to_lua(lua: &Lua, v: &serde_json::Value) -> mlua::Result<Value> {
    match v {
        serde_json::Value::Null => Ok(Value::Nil),
        serde_json::Value::Bool(b) => Ok(Value::Boolean(*b)),
        serde_json::Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                Ok(Value::Integer(i))
            } else if let Some(f) = n.as_f64() {
                Ok(Value::Number(f))
            } else {
                Ok(Value::Nil)
            }
        }
        serde_json::Value::String(s) => Ok(Value::String(lua.create_string(s)?)),
        serde_json::Value::Array(arr) => {
            let t = lua.create_table()?;
            for (i, item) in arr.iter().enumerate() {
                t.set(i + 1, json_to_lua(lua, item)?)?;
            }
            Ok(Value::Table(t))
        }
        serde_json::Value::Object(map) => {
            let t = lua.create_table()?;
            for (k, v) in map {
                t.set(k.as_str(), json_to_lua(lua, v)?)?;
            }
            Ok(Value::Table(t))
        }
    }
}

/// Rust completion items → Lua array table.
pub(crate) fn items_to_table(lua: &Lua, items: &[LuaItem]) -> mlua::Result<Table> {
    let t = lua.create_table()?;
    for (i, item) in items.iter().enumerate() {
        let it = lua.create_table()?;
        it.set("name", item.text.clone())?;
        if let Some(tip) = &item.tip {
            it.set("tip", tip.clone())?;
        }
        if let Some(u) = &item.usage {
            it.set("usage", u.clone())?;
        }
        if let Some(e) = &item.example {
            it.set("example", e.clone())?;
        }
        if let Some(s) = &item.symbol {
            it.set("symbol", s.clone())?;
        }
        if item.repeat > 0 {
            // `repeat_count` is the external field (repeat is a Lua keyword).
            it.set("repeat_count", item.repeat)?;
        }
        if item.nospace {
            it.set("nospace", true)?;
        }
        if let Some(is_option) = item.is_option {
            it.set("is_option", is_option)?;
        }
        t.set(i + 1, it)?;
    }
    Ok(t)
}

/// Items returned by Lua → Rust completion items.
/// The external contract is `name`; `text` is an internal field and must not appear in Lua land.
/// `usage`/`example` accept the same `{ cmd, desc }` objects as the manifest (see
/// `resolve_usage_example`), since direct `completions` table ops bypass `psc.add`.
/// A `tip`/`usage`/`example` holding a function is NOT resolved here — it is collected
/// into `lazy` (keyed by item text; positions shift under order-sort) for on-selection
/// evaluation by the menu session, and reads back as empty.
pub(crate) fn table_to_items(
    lua: &Lua,
    t: &Table,
    lazy: &mut Vec<LazyEntry>,
    language: &str,
) -> mlua::Result<Vec<LuaItem>> {
    let mut out = Vec::new();
    for i in 1..=t.raw_len() {
        // Malformed rows are skipped like the `psc.add` path, never aborting the hook.
        let Ok(item) = t.raw_get::<Table>(i) else {
            continue;
        };
        let Ok(name) = item.get::<Option<String>>("name") else {
            continue;
        };
        let Some(text) = name.filter(|n| !n.trim().is_empty()) else {
            continue;
        };
        let tip = take_lazy_or_string(lua, &item, "tip", LazyField::Tip, &text, lazy, language)?;
        let usage =
            take_lazy_or_string(lua, &item, "usage", LazyField::Usage, &text, lazy, language)?;
        let example = take_lazy_or_string(
            lua,
            &item,
            "example",
            LazyField::Example,
            &text,
            lazy,
            language,
        )?;
        // A wrong-typed `symbol` / `repeat_count` marks the row malformed, not the hook (§3, §7.0):
        // skipped like a missing `name`, so one typo cannot take the static candidates with it.
        // (`nospace` needs no guard — Lua truthiness makes `bool` total.)
        let Ok(symbol) = item.get::<Option<String>>("symbol") else {
            continue;
        };
        let repeat = match item.get::<Option<i32>>("repeat_count") {
            Ok(Some(v)) => Some(v),
            Err(_) => continue,
            Ok(None) => match item.get::<Option<i32>>("repeat") {
                Ok(v) => v,
                Err(_) => continue,
            },
        };
        let nospace: bool = item.get::<Option<bool>>("nospace")?.unwrap_or(false);
        // Engine-internal, like `nospace`: `None` means the row came from a hook, not a node.
        let is_option: Option<bool> = item.get::<Option<bool>>("is_option")?;
        out.push(LuaItem {
            text,
            tip,
            usage,
            example,
            symbol,
            repeat: repeat.unwrap_or(0),
            nospace,
            is_option,
        });
    }
    Ok(out)
}

/// Read one description field: a function value registers a lazy entry (reads back
/// as empty); anything else follows the existing conversion (strings as-is,
/// `{ cmd, desc }` objects for usage/example, error otherwise).
fn take_lazy_or_string(
    lua: &Lua,
    item: &Table,
    key: &str,
    field: LazyField,
    text: &str,
    lazy: &mut Vec<LazyEntry>,
    language: &str,
) -> mlua::Result<Option<String>> {
    if let Value::Function(f) = item.get::<Value>(key)? {
        lazy.push(LazyEntry {
            key: text.to_string(),
            field,
            func: f,
        });
        return Ok(None);
    }
    match key {
        "tip" => resolve_localized(lua, Some(item.get(key)?), language),
        _ => resolve_usage_example(lua, item.get(key)?),
    }
}

pub(crate) use formats::{
    api_json, api_json_batch, api_log, api_toml, api_toml_batch, api_yaml, api_yaml_batch,
    append_log, now_local,
};
pub(crate) use fs::{
    api_exist, api_glob, api_ls, api_ls_batch, api_path, api_read, api_read_batch, api_which,
    resolve, table_to_strings,
};
#[cfg(test)]
pub(crate) use fs::{glob_stop_at, glob_walk, normalize_glob_pattern, GLOB_BUDGET};
pub(crate) use items::{api_add, api_concat, api_contains, api_items, api_join, api_split};
pub(crate) use run::{api_run, api_run_batch};
