//! Pure helper functions on the `psc.*` API. Contract and signatures: `design/hooks.md`.

use mlua::{Lua, Table, Value};

use super::Token;

/// Lua `tostring` semantics to a Rust String (None when the value coerces to nothing).
fn coerce_string(lua: &Lua, v: Value) -> mlua::Result<Option<String>> {
    Ok(lua.coerce_string(v)?.map(|s| s.to_string_lossy()))
}

/// `psc.eq(a, b, opts?)` — string equality; case-insensitive by default,
/// `opts.case_sensitive` true makes it exact. `nil` arguments never match (return false),
pub(crate) fn api_eq(lua: &Lua, (a, b, opts): (Value, Value, Option<Table>)) -> mlua::Result<bool> {
    let (Some(a), Some(b)) = (coerce_string(lua, a)?, coerce_string(lua, b)?) else {
        return Ok(false);
    };
    let case_sensitive = opts
        .as_ref()
        .and_then(|o| o.get::<Option<bool>>("case_sensitive").ok().flatten())
        .unwrap_or(false);
    if case_sensitive {
        Ok(a == b)
    } else {
        Ok(a.eq_ignore_ascii_case(&b))
    }
}

/// `psc.trim(s, opts?)` — trim whitespace; `opts.mode` is "start"/"end"/"both" (default "both").
/// A nil `s` yields an empty string.
pub(crate) fn api_trim(lua: &Lua, (s, opts): (Value, Option<Table>)) -> mlua::Result<String> {
    let s = coerce_string(lua, s)?.unwrap_or_default();
    let mode: String = opts
        .as_ref()
        .and_then(|o| o.get::<Option<String>>("mode").ok().flatten())
        .unwrap_or_else(|| "both".to_string());
    Ok(match mode.as_str() {
        "start" => s.trim_start_matches(char::is_whitespace).to_string(),
        "end" => s.trim_end_matches(char::is_whitespace).to_string(),
        _ => s.trim_matches(char::is_whitespace).to_string(),
    })
}

/// `psc.has_unknown()` — any completed unknown token exists (a value has been typed).
pub(crate) fn api_has_unknown(tokens: &[Token]) -> bool {
    tokens.iter().any(|t| t.kind == "unknown")
}

/// `psc.typed(name)` — the name appears among all completed tokens (case-insensitive).
/// Compares the **canonical** name when available (aliases count as their main name, matching
/// the engine's repeat-filter), falling back to the raw input for unknown/value tokens.
pub(crate) fn api_typed(tokens: &[Token], name: &str) -> bool {
    tokens.iter().any(|t| {
        let key = t
            .canonical
            .as_deref()
            .unwrap_or(&t.text)
            .to_ascii_lowercase();
        key == name.to_ascii_lowercase()
    })
}

/// `psc.typed_unknown(name)` — the name appears among completed unknown tokens only.
pub(crate) fn api_typed_unknown(tokens: &[Token], name: &str) -> bool {
    tokens
        .iter()
        .any(|t| t.kind == "unknown" && t.text.eq_ignore_ascii_case(name))
}

/// Resolve a tip/usage/example field (string or array) to a single string.
fn text_of(lua: &Lua, v: Value) -> mlua::Result<Option<String>> {
    match v {
        Value::Nil => Ok(None),
        Value::String(s) => Ok(Some(s.to_str()?.to_string())),
        Value::Table(t) => {
            let mut parts = Vec::new();
            for i in 1..=t.raw_len() {
                if let Some(s) = coerce_string(lua, t.raw_get::<Value>(i)?)? {
                    parts.push(s);
                }
            }
            Ok(Some(parts.join("\n")))
        }
        other => Ok(coerce_string(lua, other)?),
    }
}

/// `psc.mount_items(path, opts?)` → mount the **direct children** of a manifest `next`/`option`
/// array as completion items (returns an array, does not add; no recursion — deeper levels are
/// reached by the engine's own `next` navigation, or by calling `mount_items` again with a
/// longer path from the hook). `opts` is accepted for signature stability but unused.
pub(crate) fn api_mount_items(
    lua: &Lua,
    (path, _opts): (Vec<String>, Option<Table>),
) -> mlua::Result<Table> {
    let out = lua.create_table()?;
    let last = path.last().map(|s| s.as_str()).unwrap_or("");
    if last != "next" && last != "option" {
        return Ok(out);
    }
    let source = last;
    let psc: Table = lua.globals().get("psc")?;
    let manifest: Option<Table> = psc.get("manifest")?;
    let Some(manifest) = manifest else {
        return Ok(out);
    };
    let first = path.first().map(|s| s.as_str()).unwrap_or("");
    let container = manifest
        .raw_get::<Option<Value>>(first)?
        .and_then(|v| match v {
            Value::Table(t) => Some(t),
            _ => None,
        });
    let mut container: Option<Table> = container;

    let mut node: Option<Table> = None;
    let nav_end = path.len().saturating_sub(1);
    for seg in path.iter().take(nav_end).skip(1) {
        let Some(container_t) = &container else {
            return Ok(out);
        };
        let Some(found) = find_named(container_t, seg)? else {
            return Ok(out);
        };
        node = Some(found.clone());
        container = found.raw_get::<Option<Table>>("next")?;
    }
    let Some(node) = node else { return Ok(out) };

    let from_option = source == "option";
    let children = if from_option {
        node.raw_get::<Option<Table>>("option")?
    } else {
        node.raw_get::<Option<Table>>("next")?
    };
    if let Some(children) = children {
        mount_children(lua, &children, &out)?;
    }
    Ok(out)
}

fn find_named(container: &Table, name: &str) -> mlua::Result<Option<Table>> {
    for i in 1..=container.raw_len() {
        if let Value::Table(t) = container.raw_get::<Value>(i)? {
            if t.raw_get::<Option<String>>("name")?.as_deref() == Some(name) {
                return Ok(Some(t));
            }
        }
    }
    for pair in container.pairs::<Value, Value>() {
        let (k, v) = pair?;
        if let Value::String(s) = k {
            if s.to_str()? == name {
                if let Value::Table(t) = v {
                    return Ok(Some(t));
                }
            }
        }
    }
    Ok(None)
}

/// Mount one level: copy each child's name/tip/usage/example.
/// No symbol is computed here — a mounted item's symbol depends on the *current* context (what
/// happens when it is selected there), not on its original manifest position. Set symbols
/// explicitly with `psc.set_symbol` when needed.
fn mount_children(lua: &Lua, children: &Table, out: &Table) -> mlua::Result<()> {
    for i in 1..=children.raw_len() {
        let Value::Table(k) = children.raw_get::<Value>(i)? else {
            continue;
        };
        let Some(name) = k.raw_get::<Option<String>>("name")? else {
            continue;
        };
        let tip = text_of(lua, k.raw_get::<Value>("tip")?)?;
        let usage = text_of(lua, k.raw_get::<Value>("usage")?)?;
        let example = text_of(lua, k.raw_get::<Value>("example")?)?;
        let item = lua.create_table()?;
        item.set("name", name)?;
        if let Some(t) = tip {
            item.set("tip", t)?;
        }
        if let Some(u) = usage {
            item.set("usage", u)?;
        }
        if let Some(e) = example {
            item.set("example", e)?;
        }
        let n = out.raw_len();
        out.raw_set(n + 1, item)?;
    }
    Ok(())
}
