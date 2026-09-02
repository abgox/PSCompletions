//! Builds the `psc` global table: context values + API bindings.

use mlua::{Lua, Table, Value};
use std::sync::Arc;

use super::api::{
    api_add, api_concat, api_contains, api_env, api_exist, api_glob, api_items, api_join, api_json,
    api_json_batch, api_log, api_ls, api_ls_batch, api_path, api_read, api_read_batch, api_run,
    api_run_batch, api_split, api_toml, api_toml_batch, api_which, api_yaml, api_yaml_batch,
    coerce_string_opt, json_to_lua,
};
use super::helpers;
use super::{HookContext, Token};

/// The current accumulation target for `psc.add` (the live candidate list).
pub(crate) type AddTarget = std::rc::Rc<std::cell::RefCell<Table>>;
/// Recursion guard shared by all `psc.on` registrations of one hook run.
pub(crate) type OnDepth = std::rc::Rc<std::cell::Cell<u32>>;
/// Set when an `on` injection ran during this build (drives the mixing warning
/// when a script explicitly returns a replacing array).
pub(crate) type InjectedFlag = std::rc::Rc<std::cell::Cell<bool>>;

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
#[allow(clippy::too_many_arguments)]
pub(crate) fn build_psc_table(
    lua: &Lua,
    ctx: &HookContext,
    add_target: AddTarget,
    on_depth: OnDepth,
    injected: std::rc::Rc<std::cell::Cell<bool>>,
) -> mlua::Result<Table> {
    let psc = lua.create_table()?;

    let cur = lua.create_table()?;
    cur.set("name", ctx.typing.canonical.clone())?;
    cur.set("type", ctx.typing.kind.clone())?;
    cur.set("input", ctx.typing.text.clone())?;
    cur.set("option_like", ctx.typing.option_like)?;
    psc.set("typing", cur)?;

    let tokens = lua.create_table()?;
    let tokens_lua = tokens.clone();
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
    // The host passes the fully-resolved config (per-completion → global → default
    // → manifest defaults, merged in build_candidate_items).  Surface an empty table
    // instead of nil so hooks that index psc.config don't crash on a nil index.
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
    let lang_for_add = ctx.language.clone();
    let add_target_for_closure = add_target.clone();
    psc.set(
        "add",
        lua.create_function(move |lua, x: Value| {
            let t = add_target_for_closure.borrow().clone();
            api_add(lua, &t, x, &lang_for_add)
        })?,
    )?;
    let lang = ctx.language.clone();
    psc.set(
        "items",
        lua.create_function(move |lua, args| api_items(lua, args, &lang))?,
    )?;
    psc.set("concat", lua.create_function(api_concat)?)?;
    psc.set("split", lua.create_function(api_split)?)?;
    psc.set("join", lua.create_function(api_join)?)?;
    psc.set("path", lua.create_function(api_path)?)?;
    psc.set("contains", lua.create_function(api_contains)?)?;

    // ---- psc.on(spec, handler): declarative dynamic-completion registration ----
    let provide_path = {
        let joined = ctx.path.join(" ");
        if joined.is_empty() {
            String::new()
        } else {
            format!(" {joined}")
        }
    };
    let provide_env = ProvideEnv {
        layers: ctx.layers.clone(),
        tokens: ctx.tokens.clone(),
        manifest: ctx.manifest.clone(),
        // Derived from tokens (kind == "option", canonical name) — the same source
        // the old `last_option` used; identical to `ctx.opts` in production.
        opts: ctx
            .tokens
            .iter()
            .filter(|t| t.kind == "option")
            .filter_map(|t| t.canonical.clone())
            .collect(),
        depth: on_depth.clone(),
        injected,
        log_dir: ctx.log_dir.clone(),
        cmd: ctx.cmd.clone(),
        path: provide_path,
    };
    psc.set(
        "on",
        lua.create_function(move |lua, (spec, handler): (Value, Value)| {
            Ok(api_on(lua, &provide_env, spec, handler))
        })?,
    )?;
    // ---- Helper functions ----
    let helper_tokens = Arc::new(ctx.tokens.clone());
    psc.set("eq", lua.create_function(helpers::api_eq)?)?;
    psc.set("trim", lua.create_function(helpers::api_trim)?)?;
    let t2 = helper_tokens.clone();
    let token_tokens = tokens_lua.clone();
    psc.set(
        "token",
        lua.create_function(move |lua, spec: Option<Value>| {
            let (name, type_filter, case_sensitive) = match spec {
                None | Some(Value::Nil) => (None, None, false),
                Some(Value::String(s)) => {
                    let n = s.to_str()?.to_string();
                    if n.trim().is_empty() {
                        (None, None, false)
                    } else {
                        (Some(n), None, false)
                    }
                }
                Some(Value::Table(t)) => {
                    let name: Option<String> = t
                        .get::<Option<Value>>("name")?
                        .and_then(|v| lua.coerce_string(v).ok().flatten())
                        .map(|s| s.to_string_lossy());
                    let name = name.filter(|n| !n.trim().is_empty());
                    let type_filter: Option<String> = t.get::<Option<String>>("type")?;
                    let case_sensitive: bool =
                        t.get::<Option<bool>>("case_sensitive")?.unwrap_or(false);
                    // Validate type filter
                    let type_filter = type_filter.filter(|s| {
                        matches!(s.as_str(), "command" | "option" | "value" | "unknown")
                    });
                    (name, type_filter, case_sensitive)
                }
                _ => (None, None, false),
            };
            match helpers::api_token(t2.as_slice(), name, type_filter, case_sensitive) {
                // Return the same table reference as `psc.tokens[i]` (identity preserved).
                Some(i) => token_tokens.raw_get(i + 1),
                None => Ok(Value::Nil),
            }
        })?,
    )?;
    psc.set(
        "mount_items",
        lua.create_function(move |lua, path: Value| {
            let Some(path) = table_of_strings(lua, path)? else {
                return lua.create_table();
            };
            helpers::api_mount_items(lua, &path)
        })?,
    )?;
    Ok(psc)
}

/// Per-run environment shared by every `psc.on` registration.
struct ProvideEnv {
    layers: Vec<(String, String)>,
    /// All completed tokens (kind `command`/`option`/`value`/`unknown`), for slot gating.
    tokens: Vec<Token>,
    manifest: serde_json::Value,
    /// Canonical names of all completed option tokens, in input order (from `ctx.opts`).
    opts: Vec<String>,
    injected: InjectedFlag,
    depth: OnDepth,
    log_dir: String,
    cmd: String,
    path: String,
}

/// `psc.on(spec, handler)` - declarative hooks: run `handler` when the current
/// position matches `spec`. The handler directly manipulates the live candidate
/// list (the `completions` global) via `psc.add` / plain Lua table operations.
///
/// `spec` is a single spec table or an **array of spec tables** (OR: any element
/// matching injects). Each element follows the single-spec rules: `command` and
/// `option` coexist as AND; a spec array mixed with named keys raises.
///
/// NEVER raises into Lua: any failure (bad spec, unknown target, recursion,
/// handler error) is logged to `error.log`; whatever the successful parts
/// already changed stays changed. Raising from a Lua C callback in release
/// builds interacts fatally with `lua_error`'s longjmp unwinding and aborts
/// the whole menu process - so it must not happen.
fn api_on(lua: &Lua, env: &ProvideEnv, spec: Value, handler: Value) -> Value {
    match api_on_outer(lua, env, spec, handler) {
        Ok(_) => {}
        Err(e) => {
            eprintln!("psc.on: {e}");
            super::log_hook_error(&env.log_dir, &env.cmd, &env.path, &e);
        }
    }
    Value::Nil
}

/// Spec dispatch: a plain table is a single spec; an array of tables is a set of
/// specs with OR semantics (each element independently validated and injected).
fn api_on_outer(lua: &Lua, env: &ProvideEnv, spec: Value, handler: Value) -> mlua::Result<Value> {
    const PRE: &str = "psc.on:";
    if let Value::Table(t) = &spec {
        // An array of spec tables (every element 1..len is a table) → OR them.
        let len = t.raw_len();
        let is_array =
            len > 0 && (1..=len).all(|i| matches!(t.raw_get::<Value>(i), Ok(Value::Table(_))));
        if is_array {
            // Mixing named keys with array elements is ambiguous → fail loudly
            // (a table like { command = "x", { ... } } would otherwise silently
            // ignore the named keys).
            for pair in t.pairs::<Value, Value>() {
                let (k, _) = pair?;
                let is_named = !matches!(k, Value::Integer(_));
                if is_named {
                    return Err(mlua::Error::RuntimeError(format!(
                        "{PRE} cannot mix named keys with spec-array elements"
                    )));
                }
            }
            for i in 1..=len {
                let elem: Value = t.raw_get(i)?;
                api_on_inner(lua, env, elem, handler.clone(), i)?;
            }
            return Ok(Value::Nil);
        }
        if len > 0 {
            return Err(mlua::Error::RuntimeError(format!(
                "{PRE} spec array elements must all be tables"
            )));
        }
    }
    api_on_inner(lua, env, spec, handler, 0)
}

/// A command-chain segment: wildcard (`""`) or an exact canonical name.
enum Seg {
    Any,
    Name(String),
}

/// Whether the completed option sequence (`opts`, canonical names in input order)
/// ENDS WITH the spec's option chain. A single-string spec is a length-1 chain, so
/// this is a superset of the old `last_option` behavior. Case-insensitive; values
/// never enter `opts`, so `--move val --copy` still matches `{ "--move", "--copy" }`.
fn match_option_suffix(segs: &[Seg], opts: &[String]) -> bool {
    if segs.is_empty() {
        return false;
    }
    if segs.len() > opts.len() {
        return false;
    }
    opts[opts.len() - segs.len()..]
        .iter()
        .zip(segs.iter())
        .all(|(o, sg)| match sg {
            Seg::Any => true,
            Seg::Name(n) => n.eq_ignore_ascii_case(o),
        })
}

/// The location declared by a registration. `command` and `option` may coexist as AND
/// (both must match); a single key is a simple match, neither targets root.
/// `command` is anchored at the root (full chain); `option` matches as a **suffix**
/// of the completed option sequence (options have no root).
struct SpecLoc {
    command: Option<Vec<Seg>>,
    option: Option<Vec<Seg>>,
    multiple: bool,
}
impl SpecLoc {
    fn is_root(&self) -> bool {
        self.command.is_none() && self.option.is_none()
    }
}

/// Whether an unknown token appears AFTER the last completed command token — i.e. in the
/// positional slot area of the matched command chain.
fn unknown_after_command_chain(tokens: &[Token]) -> bool {
    let Some(last_cmd) = tokens.iter().rposition(|t| t.kind == "command") else {
        return tokens.iter().any(|t| t.kind == "unknown");
    };
    tokens[last_cmd + 1..].iter().any(|t| t.kind == "unknown")
}

/// Whether an option spec's value slot is still unfilled: the last completed token is the
/// chain's last option (any option for a wildcard). A value/unknown token at the frontier
/// means the value has already been typed — the slot is filled.
fn option_slot_unfilled(tokens: &[Token], last_seg: &Seg) -> bool {
    match tokens.last() {
        Some(t) if t.kind == "option" => match (last_seg, t.canonical.as_deref()) {
            (Seg::Any, _) => true,
            (Seg::Name(n), Some(c)) => n.eq_ignore_ascii_case(c),
            _ => false,
        },
        _ => false,
    }
}

/// Whether the frontier is inside an option's value/sub-option domain that this spec does
/// NOT pin itself. Even `multiple` must not inject there: the spec's slot is not the next
/// thing to fill (e.g. `git rebase --onto <Tab>` is `--onto`'s value position, not
/// rebase's positional slot).
fn in_unpinned_option_domain(layers: &[(String, String)], spec_option_last: Option<&Seg>) -> bool {
    let Some((kind, name)) = layers.last() else {
        return false;
    };
    if kind != "option" {
        return false;
    }
    match spec_option_last {
        None => true,
        Some(Seg::Any) => false,
        Some(Seg::Name(n)) => !n.eq_ignore_ascii_case(name),
    }
}

fn api_on_inner(
    lua: &Lua,
    env: &ProvideEnv,
    spec: Value,
    handler: Value,
    spec_index: usize,
) -> mlua::Result<Value> {
    const PRE: &str = "psc.on:";
    // Element index prefix for spec-array error messages ("#2" etc.); empty for a single spec.
    let idx = if spec_index == 0 {
        String::new()
    } else {
        format!("#{spec_index} ")
    };
    let func = match handler {
        Value::Function(f) => f,
        _ => {
            return Err(mlua::Error::RuntimeError(format!(
                "{PRE} handler must be a function"
            )))
        }
    };

    // --- Strict spec parsing: unknown keys raise so typos never become silently-
    // --- dead registrations. Failures are caught by api_on and logged instead.
    // `command` and `option` coexist as AND; Root is when both are absent.
    let mut command: Option<Vec<Seg>> = None;
    let mut option: Option<Vec<Seg>> = None;
    let mut multiple = false;
    let mut multiple_seen = false;
    match &spec {
        Value::Nil => {}
        Value::Table(t) => {
            for pair in t.pairs::<String, Value>() {
                let (key, value) = pair?;
                match key.as_str() {
                    "command" => {
                        if command.is_some() {
                            return Err(mlua::Error::RuntimeError(format!(
                                "{PRE} duplicate spec key \"command\""
                            )));
                        }
                        let segs: Vec<Seg> = match &value {
                            Value::Nil => Vec::new(),
                            Value::String(_) => {
                                let Some(s) = coerce_string_opt(lua, value.clone())? else {
                                    return Err(mlua::Error::RuntimeError(format!(
                                        "{PRE} command segments must be strings"
                                    )));
                                };
                                vec![if s.is_empty() { Seg::Any } else { Seg::Name(s) }]
                            }
                            Value::Table(t2) => {
                                let len = t2.raw_len();
                                if len == 0 {
                                    return Err(mlua::Error::RuntimeError(format!(
                                        "{PRE} command must not be an empty array"
                                    )));
                                }
                                let mut segs = Vec::with_capacity(len);
                                for i in 1..=len {
                                    let v: Value = t2.raw_get(i)?;
                                    let Some(s) = coerce_string_opt(lua, v)? else {
                                        return Err(mlua::Error::RuntimeError(format!(
                                            "{PRE} command segments must be strings"
                                        )));
                                    };
                                    if s.starts_with('-') {
                                        return Err(mlua::Error::RuntimeError(format!(
                                            "{PRE} command segments must be commands, got option-like {s:?}"
                                        )));
                                    }
                                    segs.push(if s.is_empty() { Seg::Any } else { Seg::Name(s) });
                                }
                                segs
                            }
                            _ => {
                                return Err(mlua::Error::RuntimeError(format!(
                                    "{PRE} command must be a string or array of strings"
                                )))
                            }
                        };
                        command = Some(segs);
                    }
                    "option" => {
                        if option.is_some() {
                            return Err(mlua::Error::RuntimeError(format!(
                                "{PRE} duplicate spec key \"option\""
                            )));
                        }
                        // String = single-option chain; array = an option chain matched as a
                        // SUFFIX of the completed option sequence (options have no root, so
                        // unlike command chains the prefix is open). `""` is a wildcard segment.
                        let segs: Vec<Seg> = match &value {
                            Value::Nil => Vec::new(),
                            Value::String(_) => {
                                let Some(s) = coerce_string_opt(lua, value.clone())? else {
                                    return Err(mlua::Error::RuntimeError(format!(
                                        "{PRE} option segments must be strings"
                                    )));
                                };
                                if !s.starts_with('-') && !s.is_empty() {
                                    return Err(mlua::Error::RuntimeError(format!(
                                        "{PRE} option segments must be options, got {s:?}"
                                    )));
                                }
                                vec![if s.is_empty() { Seg::Any } else { Seg::Name(s) }]
                            }
                            Value::Table(t2) => {
                                let len = t2.raw_len();
                                if len == 0 {
                                    return Err(mlua::Error::RuntimeError(format!(
                                        "{PRE} option must not be an empty array"
                                    )));
                                }
                                let mut segs = Vec::with_capacity(len);
                                for i in 1..=len {
                                    let v: Value = t2.raw_get(i)?;
                                    let Some(s) = coerce_string_opt(lua, v)? else {
                                        return Err(mlua::Error::RuntimeError(format!(
                                            "{PRE} option segments must be strings"
                                        )));
                                    };
                                    if !s.starts_with('-') && !s.is_empty() {
                                        return Err(mlua::Error::RuntimeError(format!(
                                            "{PRE} option segments must be options, got {s:?}"
                                        )));
                                    }
                                    segs.push(if s.is_empty() { Seg::Any } else { Seg::Name(s) });
                                }
                                segs
                            }
                            _ => {
                                return Err(mlua::Error::RuntimeError(format!(
                                    "{PRE} option must be a string or array of strings"
                                )))
                            }
                        };
                        option = Some(segs);
                    }
                    "multiple" => {
                        if multiple_seen {
                            return Err(mlua::Error::RuntimeError(format!(
                                "{PRE} duplicate spec key \"multiple\""
                            )));
                        }
                        multiple_seen = true;
                        multiple = match value {
                            Value::Boolean(b) => b,
                            _ => {
                                return Err(mlua::Error::RuntimeError(format!(
                                    "{PRE} multiple must be a boolean"
                                )))
                            }
                        };
                    }
                    other => {
                        return Err(mlua::Error::RuntimeError(format!(
                            "{PRE} unknown spec key {other:?} (expected command / option / multiple)"
                        )));
                    }
                }
            }
        }
        _ => {
            return Err(mlua::Error::RuntimeError(format!(
                "{PRE} spec must be a table"
            )))
        }
    }

    let loc = SpecLoc {
        command,
        option,
        multiple,
    };

    // Validate target names up front: unknown names fail loudly so
    // typos never become silently-dead. For AND specs both sides must be known;
    // otherwise the registration is inert (logged).
    let is_and = loc.command.is_some() && loc.option.is_some();
    let mut command_valid = true;
    let mut option_valid = true;
    if let Some(segs) = &loc.command {
        if let Some(Seg::Name(n)) = segs.last() {
            if helpers::collect_node_names(&env.manifest, n).is_none_or(|v| v.is_empty()) {
                if is_and {
                    let e = mlua::Error::RuntimeError(format!(
                        "{PRE}{idx} unknown command target {n:?} in AND spec, whole spec inert"
                    ));
                    eprintln!("psc.on: {e}");
                    super::log_hook_error(&env.log_dir, &env.cmd, &env.path, &e);
                    command_valid = false;
                    option_valid = false;
                } else {
                    return Err(mlua::Error::RuntimeError(format!(
                        "{PRE}{idx} unknown target {n:?} in this manifest"
                    )));
                }
            }
        }
    }
    if let Some(segs) = &loc.option {
        // Validate the LAST named segment (the innermost context), mirroring how the
        // command chain validates only its final segment.
        if let Some(Seg::Name(n)) = segs.last() {
            if helpers::collect_node_names(&env.manifest, n).is_none_or(|v| v.is_empty()) {
                if is_and {
                    let e = mlua::Error::RuntimeError(format!(
                        "{PRE}{idx} unknown option target {n:?} in AND spec, whole spec inert"
                    ));
                    eprintln!("psc.on: {e}");
                    super::log_hook_error(&env.log_dir, &env.cmd, &env.path, &e);
                    command_valid = false;
                    option_valid = false;
                } else {
                    return Err(mlua::Error::RuntimeError(format!(
                        "{PRE}{idx} unknown target {n:?} in this manifest"
                    )));
                }
            }
        }
    }

    // --- Dispatch: inject, driven purely by position ---
    // AND semantics when both keys present: both sides must match; otherwise OR.
    //
    // Slot model: a spec pins a slot — a command spec pins the first positional argument
    // after its chain; an option spec pins the value slot of its chain's last option. By
    // default injection happens only while that slot is still the next thing to fill.
    // `multiple` keeps matching after the slot has been filled one or more times
    // (positional args, repeated option values) — but never inside an unrelated option's
    // value position.
    let multiple = loc.multiple;
    let tokens = &env.tokens;
    // Command-only projection of the layer chain (option layers ignored); the prefix form
    // is what `multiple` matches against.
    let cmd_layers: Vec<&String> = env
        .layers
        .iter()
        .filter_map(|(k, v)| (k == "command").then_some(v))
        .collect();
    let command_match = |segs: &[Seg], cmds: &[&String], prefix: bool| -> bool {
        let len_ok = if prefix {
            cmds.len() >= segs.len()
        } else {
            cmds.len() == segs.len()
        };
        len_ok
            && cmds.iter().zip(segs.iter()).all(|(ln, sg)| match sg {
                Seg::Any => true,
                Seg::Name(n) => n.eq_ignore_ascii_case(ln),
            })
    };
    // Default gate: an unknown token after the chain fills the positional slot.
    let unknown_gate = unknown_after_command_chain(tokens);
    // `multiple` must not leak into an unrelated option's value position.
    let unpinned_option =
        in_unpinned_option_domain(&env.layers, loc.option.as_ref().and_then(|s| s.last()));

    let inject = if loc.is_root() {
        env.layers.is_empty() && (multiple || !unknown_gate)
    } else if is_and {
        let command_ok = command_valid
            && loc.command.as_ref().is_some_and(|segs| {
                command_match(segs, &cmd_layers, multiple) && (multiple || !unknown_gate)
            });
        let option_ok = option_valid
            && loc.option.as_ref().is_some_and(|segs| {
                match_option_suffix(segs, &env.opts)
                    && (multiple
                        || segs
                            .last()
                            .is_some_and(|last| option_slot_unfilled(tokens, last)))
            });
        command_ok && option_ok
    } else if loc.command.is_some() {
        command_valid
            && loc.command.as_ref().is_some_and(|segs| {
                if multiple {
                    command_match(segs, &cmd_layers, true) && !unpinned_option
                } else {
                    // Exact: the whole layer chain must be the command chain (an option at
                    // the frontier breaks it) and no unknown may sit after the chain.
                    env.layers.len() == segs.len()
                        && env
                            .layers
                            .iter()
                            .zip(segs.iter())
                            .all(|((lk, ln), sg)| match sg {
                                Seg::Any => lk == "command",
                                Seg::Name(n) => lk == "command" && n.eq_ignore_ascii_case(ln),
                            })
                        && !unknown_gate
                }
            })
    } else {
        option_valid
            && loc.option.as_ref().is_some_and(|segs| {
                match_option_suffix(segs, &env.opts)
                    && (multiple
                        || segs
                            .last()
                            .is_some_and(|last| option_slot_unfilled(tokens, last)))
            })
    };
    if inject {
        // No pending gating: injected rows would be prefix-filtered anyway when the
        // user browses option names; the cost trade-off belongs to the handler.
        if env.depth.get() != 0 {
            return Err(mlua::Error::RuntimeError(format!(
                "{PRE} recursive call inside a handler"
            )));
        }
        env.depth.set(1);
        let r = func.call::<Value>(());
        env.depth.set(0);
        if let Err(e) = r {
            eprintln!("psc.on: handler error: {e}");
            super::log_hook_error(&env.log_dir, &env.cmd, &env.path, &e);
            // Partial mutations persist by design (direct manipulation).
        } else {
            env.injected.set(true);
        }
    }

    Ok(Value::Nil)
}
