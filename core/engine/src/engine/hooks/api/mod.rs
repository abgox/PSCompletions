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
        _ => Ok(None),
    }
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
                results.lock().unwrap()[i] = Some(val);
            });
        }
    });
    results
        .into_inner()
        .unwrap()
        .into_iter()
        .map(|o| o.expect("worker completed its slot"))
        .collect()
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
        t.set(i + 1, it)?;
    }
    Ok(t)
}

/// Items returned by Lua → Rust completion items.
/// The external contract is `name`; `text` is an internal field and must not appear in Lua land.
pub(crate) fn table_to_items(t: &Table) -> mlua::Result<Vec<LuaItem>> {
    let mut out = Vec::new();
    for i in 1..=t.raw_len() {
        let item: Table = t.raw_get(i)?;
        let text: String = item.get("name")?;
        let tip: Option<String> = item.get("tip")?;
        let usage: Option<String> = item.get("usage")?;
        let example: Option<String> = item.get("example")?;
        let symbol: Option<String> = item.get("symbol")?;
        let repeat: i32 = item
            .get::<Option<i32>>("repeat_count")?
            .or(item.get::<Option<i32>>("repeat")?)
            .unwrap_or(0);
        out.push(LuaItem {
            text,
            tip,
            usage,
            example,
            symbol,
            repeat,
        });
    }
    Ok(out)
}

pub(crate) use formats::{
    api_json, api_json_batch, api_log, api_toml, api_toml_batch, api_yaml, api_yaml_batch,
    append_log, now_local,
};
#[cfg(test)]
pub(crate) use fs::normalize_glob_pattern;
pub(crate) use fs::{
    api_exist, api_glob, api_ls, api_ls_batch, api_path, api_read, api_read_batch, api_which,
    resolve, table_to_strings,
};
pub(crate) use items::{api_add, api_concat, api_contains, api_items, api_join, api_split};
pub(crate) use run::{api_run, api_run_batch};
