//! Pure helper functions on the `psc.*` API. Contract and signatures: `design/hooks.md`.

use mlua::{Lua, Table, Value};

use super::Token;

/// Collect every form (canonical name + aliases) of the manifest nodes whose name or an
/// alias matches `target` (ASCII case-insensitive). Walks the whole tree — `next`, `option`
/// and root `global_option` arrays — so scoped option definitions are covered wherever they
/// live. `None` (unknown target) lets callers fail loudly instead of silently dying.
pub(crate) fn collect_node_names(json: &serde_json::Value, target: &str) -> Option<Vec<String>> {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use std::sync::{Mutex, OnceLock};
    #[allow(clippy::type_complexity)]
    static CACHE: OnceLock<
        Mutex<std::collections::HashMap<u64, std::collections::HashMap<String, Vec<String>>>>,
    > = OnceLock::new();
    let cache = CACHE.get_or_init(|| Mutex::new(Default::default()));
    // Hash manifest + target lowercased
    let mut hasher = DefaultHasher::new();
    json.to_string().hash(&mut hasher);
    target.to_lowercase().hash(&mut hasher);
    let hkey = hasher.finish();
    let tkey = target.to_lowercase();
    if let Ok(guard) = cache.lock() {
        if let Some(inner) = guard.get(&hkey) {
            if let Some(v) = inner.get(&tkey) {
                return Some(v.clone());
            }
        }
    }
    fn walk(node: &serde_json::Value, target: &str, out: &mut Vec<String>) {
        let Some(obj) = node.as_object() else { return };
        let name = obj.get("name").and_then(serde_json::Value::as_str);
        let aliases: Vec<&str> = obj
            .get("alias")
            .and_then(serde_json::Value::as_array)
            .map(|a| a.iter().filter_map(serde_json::Value::as_str).collect())
            .unwrap_or_default();
        let matched = name.is_some_and(|n| n.eq_ignore_ascii_case(target))
            || aliases.iter().any(|a| a.eq_ignore_ascii_case(target));
        if matched {
            if let Some(n) = name {
                if !out.iter().any(|x| x.eq_ignore_ascii_case(n)) {
                    out.push(n.to_string());
                }
            }
            for a in aliases {
                if !out.iter().any(|x| x.eq_ignore_ascii_case(a)) {
                    out.push(a.to_string());
                }
            }
        }
        for key in ["next", "option"] {
            if let Some(children) = obj.get(key).and_then(serde_json::Value::as_array) {
                for child in children {
                    walk(child, target, out);
                }
            }
        }
    }

    let root = json.as_object()?;
    let mut out = Vec::new();
    for key in ["next", "option", "global_option"] {
        if let Some(children) = root.get(key).and_then(serde_json::Value::as_array) {
            for child in children {
                walk(child, target, &mut out);
            }
        }
    }
    let result = out.clone();
    if let Ok(mut guard) = cache.lock() {
        guard.entry(hkey).or_default().insert(tkey, result.clone());
    }
    Some(result)
}

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

/// `psc.trim(s, opts?)` — trim characters; by default whitespace is trimmed, `opts.chars`
/// (a string whose characters form the trim set) overrides it, and `opts.mode` selects
/// "start"/"end"/"both" (default "both"). A nil `s` yields an empty string.
pub(crate) fn api_trim(lua: &Lua, (s, opts): (Value, Option<Table>)) -> mlua::Result<String> {
    let s = coerce_string(lua, s)?.unwrap_or_default();
    let mode: String = opts
        .as_ref()
        .and_then(|o| o.get::<Option<String>>("mode").ok().flatten())
        .unwrap_or_else(|| "both".to_string());
    let chars: Option<String> = opts
        .as_ref()
        .and_then(|o| o.get::<Option<String>>("chars").ok().flatten());
    fn trim_start<'a>(s: &'a str, chars: Option<&str>) -> &'a str {
        match chars {
            // Empty set = trim nothing (literal semantics).
            Some(set) => s.trim_start_matches(|c| set.contains(c)),
            None => s.trim_start_matches(char::is_whitespace),
        }
    }
    fn trim_end<'a>(s: &'a str, chars: Option<&str>) -> &'a str {
        match chars {
            Some(set) => s.trim_end_matches(|c| set.contains(c)),
            None => s.trim_end_matches(char::is_whitespace),
        }
    }
    let chars = chars.as_deref();
    Ok(match mode.as_str() {
        "start" => trim_start(&s, chars).to_string(),
        "end" => trim_end(&s, chars).to_string(),
        _ => trim_end(trim_start(&s, chars), chars).to_string(),
    })
}

/// `psc.token(spec?)` — index of the first completed token matching `spec`, `None` when
/// absent. `spec` is `{name?, type?, case_sensitive?}`; `type` filters `command`/`option`/
/// `value`/`unknown`; `case_sensitive` controls `name` matching (default insensitive).
/// Compares the **canonical** name when available, falling back to raw input.
pub(crate) fn api_token(
    tokens: &[Token],
    name: Option<String>,
    type_filter: Option<String>,
    case_sensitive: bool,
) -> Option<usize> {
    tokens.iter().position(|t| {
        if let Some(ref tf) = type_filter {
            if !t.kind.eq_ignore_ascii_case(tf) {
                return false;
            }
        }
        if let Some(ref n) = name {
            let key = t.canonical.as_deref().unwrap_or(&t.text);
            if case_sensitive {
                key == n
            } else {
                key.eq_ignore_ascii_case(n)
            }
        } else {
            true
        }
    })
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

/// `psc.mount_items(path)` → convert the **direct children** of a manifest `next`/`option`
/// array into completion items — a pure transform like `psc.items` (returns an array,
/// does NOT add to `completions`; injection is the caller's job via `psc.add`). No
/// recursion — deeper levels are reached by the engine's own `next` navigation, or by
/// calling `mount_items` again with a longer path from the hook.
pub(crate) fn api_mount_items(lua: &Lua, path: &[String]) -> mlua::Result<Table> {
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
