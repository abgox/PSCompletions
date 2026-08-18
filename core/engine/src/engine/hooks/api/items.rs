//! `psc.*` item-building and manipulation: add / items / filter / remove / contains /
//! map / concat / split / merge.
//!
//! The external contract uses `name` on items everywhere hooks can see them (static
//! `completions`, `cs` after `add`, `items` output). The internal `text` shape is only
//! applied at the read-back boundary (`table_to_items` in `api/mod.rs`).

use mlua::{Lua, Table, Value};

use super::{coerce_string_opt, resolve_localized};

/// Normalize an item table: keep the external `name` key and resolve localized fields.
/// The internal `text` shape stays a Rust-side detail, only applied at the read-back
/// boundary (`table_to_items`).
fn item_to_internal(lua: &Lua, item: &Table, language: &str) -> mlua::Result<Table> {
    let name: String = item.get("name")?;
    let t = lua.create_table()?;
    t.set("name", name)?;
    if let Some(tip) = resolve_localized(lua, item.get::<Option<Value>>("tip")?, language)? {
        t.set("tip", tip)?;
    }
    if let Some(s) = item.get::<Option<String>>("symbol")? {
        t.set("symbol", s)?;
    }
    if let Some(u) = item.get::<Option<String>>("usage")? {
        t.set("usage", u)?;
    }
    if let Some(e) = item.get::<Option<String>>("example")? {
        t.set("example", e)?;
    }
    if let Some(r) = item.get::<Option<i32>>("repeat_count")? {
        if r > 0 {
            t.set("repeat", r)?;
        }
    }
    Ok(t)
}

/// `psc.add(cs, x)` → append a completion item (single table) or a batch (array of tables).
/// Empty names are skipped; tip defaults to the name. Returns the number actually added.
pub(crate) fn api_add(lua: &Lua, (tbl, x): (Value, Value), language: &str) -> mlua::Result<i32> {
    let Value::Table(tbl) = tbl else {
        return Ok(0);
    };
    let mut added = 0;
    if let Value::Table(t) = x {
        // Discriminate single item vs array: an item has a `name` key at the top level.
        if t.raw_get::<Option<String>>("name")?.is_some() {
            if let Some(n) = append_one(lua, &tbl, &t, language)? {
                added += n;
            }
        } else {
            for i in 1..=t.raw_len() {
                let Value::Table(sub) = t.raw_get::<Value>(i)? else {
                    continue;
                };
                if let Some(n) = append_one(lua, &tbl, &sub, language)? {
                    added += n;
                }
            }
        }
    }
    Ok(added)
}

/// Append one item; returns Some(count) when added, None when skipped (empty name).
fn append_one(lua: &Lua, tbl: &Table, item: &Table, language: &str) -> mlua::Result<Option<i32>> {
    // Missing or blank `name` → skip (no hard error); a table without `name` (e.g. a stray
    // `{ text = "x" }`) is treated as not-a-completion and dropped.
    let Some(name) = item.get::<Option<String>>("name")? else {
        return Ok(None);
    };
    if name.trim().is_empty() {
        return Ok(None);
    }
    // tip defaults to the name when absent (on the copy, not the caller's table).
    let it = item_to_internal(lua, item, language)?;
    if it.get::<Option<Value>>("tip")?.is_none() {
        it.set("tip", Value::String(lua.create_string(&name)?))?;
    }
    let n = tbl.raw_len();
    tbl.set(n + 1, it)?;
    Ok(Some(1))
}

/// `psc.items(list, symbol_or_fn?)` → convert each element into a completion item.
///
/// - Without second arg: the element itself is the name (element must be a string).
/// - With a **string** (`"stay"` or `"switch"`): each element becomes `{ name = elem, symbol = ... }`.
/// - With a **function**: `fn(elem)` returns the item table; returning nil skips that element.
pub(crate) fn api_items(
    lua: &Lua,
    (list, fnv): (Table, Option<Value>),
    _language: &str,
) -> mlua::Result<Table> {
    let t = lua.create_table()?;
    let mut n = 1;

    // Determine the mode: string symbol, function converter, or plain.
    let mode = match &fnv {
        Some(Value::String(_)) => 0,   // symbol string
        Some(Value::Function(_)) => 1, // converter function
        _ => 2,                        // plain (element = name)
    };

    for i in 1..=list.raw_len() {
        let elem = list.raw_get::<Value>(i)?;
        let item: Option<Value> = match mode {
            0 => {
                // String symbol — set symbol on every item.
                let symbol = fnv.as_ref().unwrap().as_string().unwrap().to_str()?;
                let name: String = match &elem {
                    Value::String(s) => s.to_str()?.to_string(),
                    _ => continue,
                };
                if name.trim().is_empty() {
                    continue;
                }
                let tb = lua.create_table()?;
                tb.set("name", name)?;
                tb.set("symbol", symbol)?;
                Some(Value::Table(tb))
            }
            1 => {
                // Function converter — original behavior.
                let func = fnv.as_ref().unwrap().as_function().unwrap();
                let res: Value = func.call(elem.clone())?;
                match res {
                    Value::Nil => None,
                    Value::Table(tb) => Some(Value::Table(tb)),
                    _ => None,
                }
            }
            _ => {
                // Plain — element is the name.
                let name: String = match &elem {
                    Value::String(s) => s.to_str()?.to_string(),
                    _ => continue,
                };
                // An empty string carries no usable name; skip it.
                if name.trim().is_empty() {
                    continue;
                }
                let tb = lua.create_table()?;
                tb.set("name", name)?;
                Some(Value::Table(tb))
            }
        };
        if let Some(it) = item {
            t.raw_set(n, it)?;
            n += 1;
        }
    }
    Ok(t)
}

/// `psc.map(list, fn)` → standard array map (fn required): apply fn to each element and keep
/// every result at its original index (the array keeps its length). A nil list yields an empty table.
pub(crate) fn api_map(lua: &Lua, (list, fnv): (Value, Value)) -> mlua::Result<Table> {
    let Value::Table(list) = list else {
        return lua.create_table();
    };
    let func = fnv
        .as_function()
        .ok_or_else(|| mlua::Error::RuntimeError("psc.map: fn must be a function".into()))?;
    let t = lua.create_table()?;
    for i in 1..=list.raw_len() {
        let elem = list.raw_get::<Value>(i)?;
        let res: Value = func.call(elem)?;
        t.set(i, res)?;
    }
    Ok(t)
}

/// `psc.concat(...)` → merge any number of arrays.
pub(crate) fn api_concat(lua: &Lua, args: mlua::Variadic<Value>) -> mlua::Result<Table> {
    let t = lua.create_table()?;
    let mut n = 1;
    for arg in args {
        if let Value::Table(arr) = arg {
            for i in 1..=arr.raw_len() {
                t.set(n, arr.raw_get::<Value>(i)?)?;
                n += 1;
            }
        }
    }
    Ok(t)
}

/// `psc.split(s, sep?)` → split a string into an array. A nil `s` yields an empty table.
pub(crate) fn api_split(lua: &Lua, (s, sep): (Value, Option<String>)) -> mlua::Result<Table> {
    let t = lua.create_table()?;
    let Some(s) = coerce_string_opt(lua, s)? else {
        return Ok(t);
    };
    let sep = sep.unwrap_or_else(|| " ".to_string());
    if sep.is_empty() {
        t.set(1, s)?;
        return Ok(t);
    }
    for (i, part) in s.split(&sep).enumerate() {
        t.set(i + 1, part.to_string())?;
    }
    Ok(t)
}

/// `psc.join(v, sep?)` → join into a string (the complement of `psc.split`); default separator
/// is a space, matching `split`. Accepts a **string** (returned as-is) or an **array**
/// (elements joined; non-string elements are coerced via `tostring`). A nil value yields an
/// empty string.
pub(crate) fn api_join(lua: &Lua, (v, sep): (Value, Option<String>)) -> mlua::Result<String> {
    let Value::Table(t) = v else {
        // A string is returned as-is; nil/other → empty string.
        return Ok(coerce_string_opt(lua, v)?.unwrap_or_default());
    };
    let sep = sep.unwrap_or_else(|| " ".to_string());
    let mut parts: Vec<String> = Vec::new();
    for i in 1..=t.raw_len() {
        let val = t.raw_get::<Value>(i)?;
        if let Some(s) = coerce_string_opt(lua, val)? {
            parts.push(s);
        }
    }
    Ok(parts.join(&sep))
}

/// `psc.filter(list, fn)` → keep the elements for which `fn` returns truthy (compacted;
/// the complementary operation to `psc.map`). A nil list yields an empty table.
pub(crate) fn api_filter(lua: &Lua, (list, fnv): (Value, Value)) -> mlua::Result<Table> {
    let Value::Table(list) = list else {
        return lua.create_table();
    };
    let func = fnv
        .as_function()
        .ok_or_else(|| mlua::Error::RuntimeError("psc.filter: fn must be a function".into()))?;
    let t = lua.create_table()?;
    let mut n = 1;
    for i in 1..=list.raw_len() {
        let elem = list.raw_get::<Value>(i)?;
        let keep: Value = func.call(elem.clone())?;
        // Lua truthy: everything except nil and false.
        if !matches!(keep, Value::Nil | Value::Boolean(false)) {
            t.set(n, elem)?;
            n += 1;
        }
    }
    Ok(t)
}

/// `psc.contains(v, target, opts?)` → membership / pattern check.
///
/// - Default (exact): `v` is an array, `target` is matched exactly (case-insensitive unless
///   `opts.case_sensitive`). A `nil`/non-string `target` never matches — a common hook pattern
///   is `psc.contains(list, cmd0)` where `cmd0` is nil at the root level.
/// - With `opts.pattern` true: `v` may be a **string or an array** — a string is matched against
///   `target` as a Lua pattern (`string.find`), an array matches when any element does. This
///   handles manifest fields that may be a string OR an array.
pub(crate) fn api_contains(
    lua: &Lua,
    (v, target, opts): (Value, Option<String>, Option<Table>),
) -> mlua::Result<bool> {
    let Some(target) = target else {
        return Ok(false);
    };
    let is_pattern = opts
        .as_ref()
        .and_then(|o| o.get::<Option<bool>>("pattern").ok().flatten())
        .unwrap_or(false);
    let case_sensitive = opts
        .as_ref()
        .and_then(|o| o.get::<Option<bool>>("case_sensitive").ok().flatten())
        .unwrap_or(false);

    // Pattern mode: string or array, match any element via `string.find`.
    if is_pattern {
        let needle = target;
        let haystacks: Vec<Value> = match &v {
            Value::String(_) => vec![v.clone()],
            Value::Table(t) => {
                let mut out = Vec::new();
                for i in 1..=t.raw_len() {
                    out.push(t.raw_get(i)?);
                }
                out
            }
            _ => return Ok(false),
        };
        let string: Table = lua.globals().get("string")?;
        let find_value: Value = string.get("find")?;
        let find = find_value.as_function().ok_or_else(|| {
            mlua::Error::RuntimeError("psc.contains: string.find unavailable".into())
        })?;
        for h in haystacks {
            if let Value::String(s) = h {
                let text = s.to_str()?.to_string();
                let r: Value = find.call((text, needle.clone()))?;
                if !matches!(r, Value::Nil) {
                    return Ok(true);
                }
            }
        }
        return Ok(false);
    }

    // Exact mode: array membership, case-insensitive by default.
    let Value::Table(list) = &v else {
        return Ok(false);
    };
    let needle = if case_sensitive {
        target
    } else {
        target.to_lowercase()
    };
    for i in 1..=list.raw_len() {
        let e: Value = list.raw_get(i)?;
        let s = match e {
            Value::String(s) => s.to_str()?.to_string(),
            _ => continue,
        };
        let hay = if case_sensitive { s } else { s.to_lowercase() };
        if hay == needle {
            return Ok(true);
        }
    }
    Ok(false)
}

/// `psc.merge(cs)` → return `cs` merged with the static `completions` (end-of-hook convenience).
/// A nil `cs` yields just the static completions.
pub(crate) fn api_merge(lua: &Lua, dyn_tbl: Value) -> mlua::Result<Table> {
    let globals = lua.globals();
    let completions: Value = globals.get("completions")?;
    let t = lua.create_table()?;
    let mut n = 1;
    if let Value::Table(dyn_tbl) = dyn_tbl {
        for i in 1..=dyn_tbl.raw_len() {
            t.set(n, dyn_tbl.raw_get::<Value>(i)?)?;
            n += 1;
        }
    }
    if let Value::Table(c) = completions {
        for i in 1..=c.raw_len() {
            t.set(n, c.raw_get::<Value>(i)?)?;
            n += 1;
        }
    }
    Ok(t)
}
