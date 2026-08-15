//! Builds the `psc` global table: context values + API bindings.

use mlua::{Lua, Table, Value};
use std::sync::Arc;

use super::api::{
    api_add, api_concat, api_contains, api_env, api_exist, api_filter, api_glob, api_items,
    api_join, api_json, api_json_batch, api_log, api_ls, api_ls_batch, api_map, api_merge,
    api_read, api_read_batch, api_run, api_run_batch, api_split, api_toml, api_toml_batch,
    api_which, api_yaml, api_yaml_batch, coerce_string_opt, json_to_lua, resolve_localized,
};
use super::helpers;
use super::HookContext;

/// Symbol overrides collected by `psc.set_symbol`: name → (symbol, case_sensitive).
type SymbolMap = std::rc::Rc<std::cell::RefCell<std::collections::HashMap<String, (String, bool)>>>;
/// Tip overrides collected by `psc.set_tip`: name → ((tip, mode), case_sensitive).
type TipMap =
    std::rc::Rc<std::cell::RefCell<std::collections::HashMap<String, ((String, String), bool)>>>;

/// Extract a Lua array into `Vec<String>`, skipping nil/non-string elements (a `nil` in a
/// batch list must not crash the hook). Returns None when the argument isn't a table at all.
fn table_of_strings(lua: &Lua, v: Value) -> mlua::Result<Option<Vec<String>>> {
    let Value::Table(t) = v else {
        return Ok(None);
    };
    let mut out = Vec::new();
    for i in 1..=t.raw_len() {
        if let Some(s) = coerce_string_opt(lua, t.raw_get(i)?)? {
            out.push(s);
        }
    }
    Ok(Some(out))
}
/// Build the `psc` global table: context values + API functions.
pub(crate) fn build_psc_table(
    lua: &Lua,
    ctx: &HookContext,
    symbols: SymbolMap,
    tips: TipMap,
) -> mlua::Result<Table> {
    let psc = lua.create_table()?;
    psc.set("language", ctx.language.clone())?;
    psc.set("cmds", lua.create_sequence_from(ctx.path.iter().cloned())?)?;

    let cur = lua.create_table()?;
    cur.set("name", ctx.pending.canonical.clone())?;
    cur.set("type", ctx.pending.kind.clone())?;
    cur.set("input", ctx.pending.text.clone())?;
    cur.set("option_like", ctx.pending.option_like)?;
    psc.set("current", cur)?;

    psc.set("opts", lua.create_sequence_from(ctx.opts.iter().cloned())?)?;
    let tokens = lua.create_table()?;
    for (i, t) in ctx.tokens.iter().enumerate() {
        let tok = lua.create_table()?;
        tok.set(
            "name",
            t.canonical.clone().unwrap_or_else(|| t.text.clone()),
        )?;
        tok.set("type", t.kind.clone())?;
        tok.set("input", t.text.clone())?;
        tokens.set(i + 1, tok)?;
    }
    psc.set("tokens", tokens)?;
    // The host passes config.completion[<cmd>], which is JSON null when the completion was
    // never configured. Surface an empty table instead of nil so hooks that index
    // psc.config (e.g. git's psc.config.max_commit) don't crash on a nil index.
    let empty_config = serde_json::json!({});
    let config_ref = if ctx.config.is_object() {
        &ctx.config
    } else {
        &empty_config
    };
    psc.set("config", json_to_lua(lua, config_ref)?)?;
    psc.set("manifest", json_to_lua(lua, &ctx.manifest)?)?;
    psc.set("_data", json_to_lua(lua, &ctx.data)?)?;

    let cwd = Arc::new(ctx.cwd.clone());
    // User's current working directory, captured once with the pre-parsed context.
    psc.set("cwd", cwd.as_str().to_string())?;
    // Platform the engine was built for; hooks branch on it (e.g. `where` vs `which`).
    // Three values like Node process.platform / Go GOOS: `~= "windows"` covers the unix case.
    let platform = if cfg!(windows) {
        "windows"
    } else if cfg!(target_os = "macos") {
        "macos"
    } else {
        "linux"
    };
    psc.set("platform", platform)?;

    let log_dir = ctx.log_dir.clone();
    psc.set(
        "log",
        lua.create_function(move |lua, args: mlua::Variadic<Value>| api_log(lua, args, &log_dir))?,
    )?;

    let cwd_read = cwd.clone();
    psc.set(
        "read",
        lua.create_function(move |lua, path: Value| {
            let Some(path) = coerce_string_opt(lua, path)? else {
                return Ok(Value::Nil);
            };
            Ok(match api_read(lua, &cwd_read, path)? {
                Some(s) => Value::String(lua.create_string(&s)?),
                None => Value::Nil,
            })
        })?,
    )?;
    let cwd_exists = cwd.clone();
    psc.set(
        "exist",
        lua.create_function(move |lua, path: Value| {
            let Some(path) = coerce_string_opt(lua, path)? else {
                return Ok(false);
            };
            api_exist(lua, &cwd_exists, path)
        })?,
    )?;
    let cwd_ls = cwd.clone();
    psc.set(
        "ls",
        lua.create_function(move |lua, path: Value| {
            let Some(path) = coerce_string_opt(lua, path)? else {
                return Ok(Value::Nil);
            };
            Ok(api_ls(lua, &cwd_ls, path)?
                .map(Value::Table)
                .unwrap_or(Value::Nil))
        })?,
    )?;
    let cwd_glob = cwd.clone();
    psc.set(
        "glob",
        lua.create_function(move |lua, pattern: Value| {
            let Some(pattern) = coerce_string_opt(lua, pattern)? else {
                return Ok(Value::Nil);
            };
            let v = match api_glob(lua, &cwd_glob, pattern)? {
                Some(paths) => Value::Table(lua.create_sequence_from(paths)?),
                None => Value::Nil,
            };
            Ok(v)
        })?,
    )?;
    let cwd_json = cwd.clone();
    psc.set(
        "json",
        lua.create_function(move |lua, path: Value| {
            let Some(path) = coerce_string_opt(lua, path)? else {
                return Ok(Value::Nil);
            };
            api_json(lua, &cwd_json, path)
        })?,
    )?;
    let cwd_json_batch = cwd.clone();
    psc.set(
        "json_batch",
        lua.create_function(move |lua, paths: Value| {
            let Some(paths) = table_of_strings(lua, paths)? else {
                return lua.create_table();
            };
            api_json_batch(lua, &cwd_json_batch, paths)
        })?,
    )?;
    let cwd_toml = cwd.clone();
    psc.set(
        "toml",
        lua.create_function(move |lua, path: Value| {
            let Some(path) = coerce_string_opt(lua, path)? else {
                return Ok(Value::Nil);
            };
            api_toml(lua, &cwd_toml, path)
        })?,
    )?;
    let cwd_toml_batch = cwd.clone();
    psc.set(
        "toml_batch",
        lua.create_function(move |lua, paths: Value| {
            let Some(paths) = table_of_strings(lua, paths)? else {
                return lua.create_table();
            };
            api_toml_batch(lua, &cwd_toml_batch, paths)
        })?,
    )?;
    let cwd_yaml = cwd.clone();
    psc.set(
        "yaml",
        lua.create_function(move |lua, path: Value| {
            let Some(path) = coerce_string_opt(lua, path)? else {
                return Ok(Value::Nil);
            };
            api_yaml(lua, &cwd_yaml, path)
        })?,
    )?;
    let cwd_yaml_batch = cwd.clone();
    psc.set(
        "yaml_batch",
        lua.create_function(move |lua, paths: Value| {
            let Some(paths) = table_of_strings(lua, paths)? else {
                return lua.create_table();
            };
            api_yaml_batch(lua, &cwd_yaml_batch, paths)
        })?,
    )?;
    psc.set(
        "which",
        lua.create_function(move |lua, name: Value| {
            let Some(name) = coerce_string_opt(lua, name)? else {
                return Ok(Value::Nil);
            };
            Ok(match api_which(lua, name)? {
                Some(s) => Value::String(lua.create_string(&s)?),
                None => Value::Nil,
            })
        })?,
    )?;
    let cwd_read_batch = cwd.clone();
    psc.set(
        "read_batch",
        lua.create_function(move |lua, paths: Value| {
            let Some(paths) = table_of_strings(lua, paths)? else {
                return lua.create_table();
            };
            api_read_batch(lua, &cwd_read_batch, paths)
        })?,
    )?;
    let cwd_ls_batch = cwd.clone();
    psc.set(
        "ls_batch",
        lua.create_function(move |lua, dirs: Value| {
            let Some(dirs) = table_of_strings(lua, dirs)? else {
                return lua.create_table();
            };
            api_ls_batch(lua, &cwd_ls_batch, dirs)
        })?,
    )?;
    let cwd_run = cwd.clone();
    psc.set(
        "run",
        lua.create_function(move |lua, args| api_run(lua, args, cwd_run.to_string()))?,
    )?;
    let cwd_run_batch = cwd.clone();
    psc.set(
        "run_batch",
        lua.create_function(move |lua, args| api_run_batch(lua, args, cwd_run_batch.to_string()))?,
    )?;
    psc.set(
        "env",
        lua.create_function(move |lua, name: Value| {
            let Some(name) = coerce_string_opt(lua, name)? else {
                return Ok(Value::Nil);
            };
            Ok(match api_env(lua, name)? {
                Some(s) => Value::String(lua.create_string(&s)?),
                None => Value::Nil,
            })
        })?,
    )?;
    let lang = ctx.language.clone();
    psc.set(
        "add",
        lua.create_function(move |lua, args| api_add(lua, args, &lang))?,
    )?;
    let lang = ctx.language.clone();
    psc.set(
        "items",
        lua.create_function(move |lua, args| api_items(lua, args, &lang))?,
    )?;
    psc.set("map", lua.create_function(api_map)?)?;
    psc.set("concat", lua.create_function(api_concat)?)?;
    psc.set("split", lua.create_function(api_split)?)?;
    psc.set("join", lua.create_function(api_join)?)?;
    psc.set("filter", lua.create_function(api_filter)?)?;
    psc.set("contains", lua.create_function(api_contains)?)?;
    psc.set("merge", lua.create_function(api_merge)?)?;
    let sym_map = symbols;
    psc.set(
        "set_symbol",
        lua.create_function(
            move |lua, (name, symbol, opts): (Value, String, Option<Table>)| {
                let Some(name) = coerce_string_opt(lua, name)? else {
                    // nil name → no-op (never crash the hook).
                    return Ok(());
                };
                let s = symbol.as_str();
                if s != "switch" && s != "stay" {
                    return Err(mlua::Error::RuntimeError(format!(
                        "psc.set_symbol: invalid symbol {symbol:?} (expected \"switch\" | \"stay\")"
                    )));
                }
                let case_sensitive = opts
                    .as_ref()
                    .and_then(|o| o.get::<Option<bool>>("case_sensitive").ok().flatten())
                    .unwrap_or(false);
                sym_map.borrow_mut().insert(name, (symbol, case_sensitive));
                Ok(())
            },
        )?,
    )?;
    let tip_map = tips;
    let lang = ctx.language.clone();
    psc.set(
        "set_tip",
        lua.create_function(
            move |lua, (name, tip, opts): (Value, Option<Value>, Option<Table>)| {
                let Some(name) = coerce_string_opt(lua, name)? else {
                    // nil name → no-op (never crash the hook).
                    return Ok(());
                };
                let mode: String = opts
                    .as_ref()
                    .and_then(|o| o.get::<Option<String>>("mode").ok().flatten())
                    .unwrap_or_else(|| "set".into());
                if !matches!(mode.as_str(), "set" | "prepend" | "append") {
                    return Err(mlua::Error::RuntimeError(format!(
                        "psc.set_tip: invalid mode {mode:?} (expected \"set\" | \"prepend\" | \"append\")"
                    )));
                }
                let case_sensitive = opts
                    .as_ref()
                    .and_then(|o| o.get::<Option<bool>>("case_sensitive").ok().flatten())
                    .unwrap_or(false);
                let Some(tip) = resolve_localized(lua, tip, &lang)? else {
                    // Passing nil removes any previously-set tip.
                    tip_map.borrow_mut().remove(&name);
                    return Ok(());
                };
                tip_map
                    .borrow_mut()
                    .insert(name, ((tip, mode), case_sensitive));
                Ok(())
            },
        )?,
    )?;
    // ---- Helper functions ----
    let helper_tokens = Arc::new(ctx.tokens.clone());
    psc.set("eq", lua.create_function(helpers::api_eq)?)?;
    psc.set("trim", lua.create_function(helpers::api_trim)?)?;
    let t1 = helper_tokens.clone();
    psc.set(
        "has_unknown",
        lua.create_function(move |_lua, ()| Ok(helpers::api_has_unknown(t1.as_slice())))?,
    )?;
    let t2 = helper_tokens.clone();
    psc.set(
        "typed",
        lua.create_function(move |lua, name: Value| {
            let Some(name) = coerce_string_opt(lua, name)? else {
                return Ok(false);
            };
            Ok(helpers::api_typed(t2.as_slice(), &name))
        })?,
    )?;
    let t3 = helper_tokens.clone();
    psc.set(
        "typed_unknown",
        lua.create_function(move |lua, name: Value| {
            let Some(name) = coerce_string_opt(lua, name)? else {
                return Ok(false);
            };
            Ok(helpers::api_typed_unknown(t3.as_slice(), &name))
        })?,
    )?;
    psc.set(
        "mount_items",
        lua.create_function(move |lua, path: Value| {
            let Some(path) = table_of_strings(lua, path)? else {
                return lua.create_table();
            };
            helpers::api_mount_items(lua, (path, None))
        })?,
    )?;
    Ok(psc)
}
