//! Pure helper functions on the `psc.*` API.
//! Contract and signatures: `design/hooks.md`.

use mlua::{Lua, Table, Value};

use super::Token;

/// Which manifest position a `psc.on` target must be declared in.
/// The manifest fixes a node's type by the array it sits in — a `next` entry of the root or of a command is a command; an `option` / `global_option` entry is an option — so a spec's key has to agree with that declaration.
/// A name written into the other position used to register and then never fire.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum TargetKind {
    Command,
    Option,
}

impl TargetKind {
    /// The article-bearing form, for messages: "a command" / "an option".
    pub(crate) fn noun(self) -> &'static str {
        match self {
            TargetKind::Command => "a command",
            TargetKind::Option => "an option",
        }
    }
}

/// The declared position of a manifest node while walking.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Pos {
    /// A `next` entry of the root or of a command: a subcommand.
    Command,
    /// An entry of an `option` / `global_option` array.
    Option,
    /// A `next` entry of an option: a candidate **value**, never a target.
    Value,
}

impl Pos {
    fn matches(self, kind: TargetKind) -> bool {
        matches!(
            (self, kind),
            (Pos::Command, TargetKind::Command) | (Pos::Option, TargetKind::Option)
        )
    }
}

/// Per-hook-run validation index: one walk collects every declared spelling (canonical name + aliases, lowercased) per kind, so `psc.on` target validation is a set lookup instead of a full-tree walk per spec element.
pub(crate) struct TargetIndex {
    commands: std::collections::HashSet<String>,
    options: std::collections::HashSet<String>,
}

impl TargetIndex {
    pub(crate) fn build(json: &serde_json::Value) -> Self {
        fn walk(
            node: &serde_json::Value,
            pos: Pos,
            commands: &mut std::collections::HashSet<String>,
            options: &mut std::collections::HashSet<String>,
        ) {
            let Some(obj) = node.as_object() else { return };
            let set = if pos.matches(TargetKind::Command) {
                Some(&mut *commands)
            } else if pos.matches(TargetKind::Option) {
                Some(&mut *options)
            } else {
                None
            };
            if let Some(set) = set {
                if let Some(n) = obj.get("name").and_then(serde_json::Value::as_str) {
                    set.insert(n.to_lowercase());
                }
                if let Some(a) = obj.get("alias").and_then(serde_json::Value::as_array) {
                    for alias in a.iter().filter_map(serde_json::Value::as_str) {
                        set.insert(alias.to_lowercase());
                    }
                }
            }
            for key in ["next", "option", "global_option"] {
                let child = match key {
                    "next" => match pos {
                        Pos::Command => Pos::Command,
                        _ => Pos::Value,
                    },
                    _ => Pos::Option,
                };
                if let Some(children) = obj.get(key).and_then(serde_json::Value::as_array) {
                    for c in children {
                        walk(c, child, commands, options);
                    }
                }
            }
        }

        let mut index = TargetIndex {
            commands: std::collections::HashSet::new(),
            options: std::collections::HashSet::new(),
        };
        if let Some(root) = json.as_object() {
            for key in ["next", "option", "global_option"] {
                let pos = if key == "next" {
                    Pos::Command
                } else {
                    Pos::Option
                };
                if let Some(children) = root.get(key).and_then(serde_json::Value::as_array) {
                    for child in children {
                        walk(child, pos, &mut index.commands, &mut index.options);
                    }
                }
            }
        }
        index
    }

    fn contains(&self, name: &str, kind: TargetKind) -> bool {
        let key = name.to_lowercase();
        match kind {
            TargetKind::Command => self.commands.contains(&key),
            TargetKind::Option => self.options.contains(&key),
        }
    }

    /// Why a `psc.on` target cannot fire, or `None` when it is declared in the position its spec key asks for.
    /// The manifest already fixes a node's type by the array it sits in, so a name declared as the other kind is a **position** mistake, not a typo.
    pub(crate) fn reject(&self, name: &str, kind: TargetKind) -> Option<String> {
        if self.contains(name, kind) {
            return None;
        }
        let other = match kind {
            TargetKind::Command => TargetKind::Option,
            TargetKind::Option => TargetKind::Command,
        };
        Some(if !self.contains(name, other) {
            format!("unknown target {name:?} in this manifest")
        } else {
            format!(
                "{name:?} is {}, not {} — the manifest fixes a node's type by the array it sits in",
                other.noun(),
                kind.noun()
            )
        })
    }
}

/// Lua `tostring` semantics to a Rust String (None when the value coerces to nothing).
fn coerce_string(lua: &Lua, v: Value) -> mlua::Result<Option<String>> {
    Ok(lua.coerce_string(v)?.map(|s| s.to_string_lossy()))
}

/// `psc.eq(a, b, opts?)` — string equality; case-insensitive by default, `opts.case_sensitive` true makes it exact.
/// `nil` arguments never match (return false),
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

/// `psc.trim(s, opts?)` — trim characters; by default whitespace is trimmed, `opts.chars` (a string whose characters form the trim set) overrides it, and `opts.mode` selects "start"/"end"/"both" (default "both").
/// A nil `s` yields an empty string.
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

/// `psc.token(spec?)` — index of the first completed token matching `spec`, `None` when absent.
/// `spec` is `{name?, type?, case_sensitive?}`; `type` filters `command`/`option`/ `value`/`unknown`; `case_sensitive` controls `name` matching (default insensitive).
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
/// Array elements (and the value itself) may be `{ cmd, desc }` objects, rendered like the static manifest's entries (see `super::api::resolve_usage_example`).
fn text_of(lua: &Lua, v: Value) -> mlua::Result<Option<String>> {
    match v {
        Value::Nil => Ok(None),
        Value::String(s) => Ok(Some(s.to_str()?.to_string())),
        Value::Table(t) => {
            if t.raw_get::<Option<String>>("cmd")?.is_some() {
                return super::api::resolve_usage_example(lua, Value::Table(t));
            }
            let mut parts = Vec::new();
            for i in 1..=t.raw_len() {
                if let Some(s) = super::api::resolve_usage_example(lua, t.raw_get::<Value>(i)?)? {
                    parts.push(s);
                }
            }
            Ok(Some(parts.join("\n")))
        }
        other => Ok(coerce_string(lua, other)?),
    }
}

/// `psc.mount_items(path)` → resolve `path` from the manifest root and convert the **direct children** of the array it lands on into completion items — a pure transform like `psc.items` (returns an array, does NOT add to `completions`; injection is the caller's job via `psc.add`).
/// No recursion — deeper levels are reached by the engine's own `next` navigation, or by calling `mount_items` again with a longer path.
///
/// The chain mirrors the manifest structure exactly: at an object the segment is a plain key lookup (any existing key), at an array it must be an item's `name` (exact, case-sensitive).
/// The path must land on an array (mounts its children) or on an item object with a `name` (mounts that single item); anything else mounts nothing.
pub(crate) fn api_mount_items(lua: &Lua, path: &[String]) -> mlua::Result<Table> {
    let out = lua.create_table()?;
    let psc: Table = lua.globals().get("psc")?;
    let Some(manifest) = psc.get::<Option<Table>>("manifest")? else {
        return Ok(out);
    };
    let mut cur = Value::Table(manifest);
    for seg in path {
        let Value::Table(t) = &cur else {
            return Ok(out);
        };
        cur = match resolve_segment(t, seg)? {
            Some(next) => next,
            None => return Ok(out),
        };
    }
    if let Value::Table(t) = cur {
        if t.raw_get::<Option<String>>("name")?.is_some() {
            mount_one(lua, &t, &out)?;
        } else {
            mount_children(lua, &t, &out)?;
        }
    }
    Ok(out)
}

/// One path step: an object's exact key, or an array item's `name`.
/// Nothing else.
fn resolve_segment(node: &Table, seg: &str) -> mlua::Result<Option<Value>> {
    if let Some(child) = node.raw_get::<Option<Value>>(seg)? {
        return Ok(Some(child));
    }
    Ok(find_named(node, seg)?.map(Value::Table))
}

fn find_named(container: &Table, name: &str) -> mlua::Result<Option<Table>> {
    for i in 1..=container.raw_len() {
        if let Value::Table(t) = container.raw_get::<Value>(i)? {
            if t.raw_get::<Option<String>>("name")?.as_deref() == Some(name) {
                return Ok(Some(t));
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
        mount_one(lua, &k, out)?;
    }
    Ok(())
}

/// Mount one item: copy its name/tip/usage/example.
/// Skipped without a `name`.
/// Aliases expand into separate items sharing the same tip, like the static menu.
fn mount_one(lua: &Lua, k: &Table, out: &Table) -> mlua::Result<()> {
    let Some(name) = k.raw_get::<Option<String>>("name")? else {
        return Ok(());
    };
    let tip = text_of(lua, k.raw_get::<Value>("tip")?)?;
    let usage = text_of(lua, k.raw_get::<Value>("usage")?)?;
    let example = text_of(lua, k.raw_get::<Value>("example")?)?;
    let mut names = vec![name];
    if let Some(alias) = k.raw_get::<Option<Table>>("alias")? {
        for i in 1..=alias.raw_len() {
            if let Some(a) = alias.raw_get::<Option<String>>(i)? {
                if !a.trim().is_empty() && !names.iter().any(|n| n == &a) {
                    names.push(a);
                }
            }
        }
    }
    for name in names {
        let item = lua.create_table()?;
        item.set("name", name)?;
        if let Some(t) = tip.clone() {
            item.set("tip", t)?;
        }
        if let Some(u) = usage.clone() {
            item.set("usage", u)?;
        }
        if let Some(e) = example.clone() {
            item.set("example", e)?;
        }
        let n = out.raw_len();
        out.raw_set(n + 1, item)?;
    }
    Ok(())
}
