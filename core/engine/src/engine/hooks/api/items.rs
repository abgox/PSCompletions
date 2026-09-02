//! `psc.*` item-building and manipulation: add / items / contains / concat / split / join.
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

/// `psc.add(x)` — append a completion item (single table) or a batch (array of tables)
/// to the **current accumulation target** (implicit; routed by the engine).
///
/// Returns the stored entry (single form) or the stored entries (array form), **by
/// reference**: mutating them before the build finalizes applies to the menu.
/// Empty names are skipped.
pub(crate) fn api_add(lua: &Lua, tbl: &Table, x: Value, language: &str) -> mlua::Result<Value> {
    let mut added: Vec<Table> = Vec::new();
    if let Value::Table(t) = &x {
        // Discriminate single item vs array: an item has a `name` key at the top level.
        if t.raw_get::<Option<String>>("name")?.is_some() {
            if let Some(it) = append_one(lua, tbl, t, language)? {
                added.push(it);
            }
        } else {
            for i in 1..=t.raw_len() {
                let Value::Table(sub) = t.raw_get::<Value>(i)? else {
                    continue;
                };
                if let Some(it) = append_one(lua, tbl, &sub, language)? {
                    added.push(it);
                }
            }
        }
    }
    match added.len() {
        1 => Ok(Value::Table(added.remove(0))),
        n if n > 1 => {
            let arr = lua.create_table()?;
            for (i, it) in added.into_iter().enumerate() {
                arr.raw_set((i + 1) as u64, it)?;
            }
            Ok(Value::Table(arr))
        }
        _ => Ok(Value::Nil),
    }
}

/// Append one item; returns the stored normalized entry table (by reference),
/// None when skipped (empty name).
fn append_one(lua: &Lua, tbl: &Table, item: &Table, language: &str) -> mlua::Result<Option<Table>> {
    // Missing or blank `name` → skip (no hard error); a table without `name` (e.g. a stray
    // `{ text = "x" }`) is treated as not-a-completion and dropped.
    let Some(name) = item.get::<Option<String>>("name")? else {
        return Ok(None);
    };
    if name.trim().is_empty() {
        return Ok(None);
    }
    let it = item_to_internal(lua, item, language)?;
    let n = tbl.raw_len();
    tbl.set(n + 1, it.clone())?;
    Ok(Some(it))
}

/// `psc.items(list, fn?)` → convert each element into a completion item.
///
/// - Without fn: the element itself is the name (element must be a string).
/// - With a **function**: `fn(elem)` returns the item table; returning nil skips that element.
pub(crate) fn api_items(
    lua: &Lua,
    (list, fnv): (Table, Option<Value>),
    _language: &str,
) -> mlua::Result<Table> {
    let t = lua.create_table()?;
    let mut n = 1;

    for i in 1..=list.raw_len() {
        let elem = list.raw_get::<Value>(i)?;
        let item: Option<Value> = match &fnv {
            Some(Value::Function(func)) => {
                // Function converter — fn(elem) returns the item table; nil skips.
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
                let (text_check, needle_check) = if case_sensitive {
                    (text, needle.clone())
                } else {
                    (text.to_lowercase(), needle.to_lowercase())
                };
                let r: Value = find.call((text_check, needle_check))?;
                if !matches!(r, Value::Nil) {
                    return Ok(true);
                }
            }
        }
        return Ok(false);
    }

    // Exact mode: string equality or array membership, case-insensitive by default.
    // String haystack is exact equality (not substring); use pattern=true for substring/pattern.
    if let Value::String(s) = &v {
        let hay = s.to_str()?.to_string();
        let (hay_check, needle_check) = if case_sensitive {
            (hay, target)
        } else {
            (hay.to_lowercase(), target.to_lowercase())
        };
        return Ok(hay_check == needle_check);
    }
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
