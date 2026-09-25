//! Wire protocol types and menu-mode helpers shared by the `psc-menu` entry point:
//! input/output JSON shapes (`design/protocol.md`), history-order ranking, hook
//! signature/cache plumbing, and candidate assembly.

use std::collections::HashMap;

use crate::engine::{completion, hooks};
use crate::menu::model;
pub fn lua_to_model_item(it: &hooks::LuaItem, switch_sym: &str, stay_sym: &str) -> model::Item {
    let symbol = match it.symbol.as_deref() {
        Some("switch") => switch_sym.to_string(),
        Some("stay") => stay_sym.to_string(),
        other => other.unwrap_or("").to_string(),
    };
    model::Item {
        completion_text: it.text.clone(),
        list_item_text: it.text.clone(),
        symbol,
        tip: it.tip.clone(),
        usage: it.usage.clone(),
        example: it.example.clone(),
        result_type: None,
        nospace: it.nospace,
    }
}

/// `=`-attached value (`--format=j<TAB>`) or separator-list value
/// (`--exclude a,b<TAB>`): the menu lists bare values, but the host replaces
/// the whole word — prefix the rebuild head back onto the inserted text only
/// (display text stays bare). The head is the `=` head plus any completed
/// list segments (`--format=`, `a,`, `--format=a,`); empty for plain values.
pub fn apply_value_prefix(items: &mut [model::Item], ctx: &completion::ResolvedContext) {
    let Some(p) = ctx.pending.as_ref() else {
        return;
    };
    if p.value_prefix.is_none() && p.list_sep.is_none() {
        return;
    }
    let mut head = p.value_prefix.clone().unwrap_or_default();
    if !p.list_used.is_empty() {
        let sep = p.list_sep.as_deref().unwrap_or(",");
        head.push_str(&p.list_used.join(sep));
        head.push_str(sep);
    }
    for it in items.iter_mut() {
        it.completion_text = format!("{head}{}", it.completion_text);
    }
}

pub fn get_flag(args: &[String], flag: &str) -> Option<String> {
    args.iter()
        .position(|a| a == flag)
        .and_then(|i| args.get(i + 1).cloned())
        .or_else(|| {
            args.iter().find_map(|a| {
                a.strip_prefix(flag)
                    .map(|s| s.trim_start_matches('=').to_string())
            })
        })
}

/// Input for the menu's build mode (also the former `--complete` mode).
#[derive(serde::Deserialize, Clone)]
pub struct CompleteInput {
    pub cmd: String,
    pub arg_tokens: Vec<String>,
    #[serde(default)]
    pub treat_last_as_complete: bool,
    /// Manifest file path (e.g. completions/git/language/en-US.json).
    pub manifest: String,
    #[serde(default)]
    pub hooks: bool,
    #[serde(default)]
    pub cwd: String,
    #[serde(default)]
    pub config: serde_json::Value,
    /// Full global config (module `menu` group etc.), for build-stage switches like
    /// `enable_cache`.
    #[serde(default)]
    pub global_config: serde_json::Value,
    /// Module-level data (psc completion only): settings/completions_json paths + live config + menu colors.
    #[serde(default)]
    pub data: serde_json::Value,
    /// Order-file paths, present when history sorting is enabled.
    #[serde(default)]
    pub order: Option<CompleteOrder>,
    /// Result cache directory (module-managed temp dir); empty = caching disabled.
    #[serde(default)]
    pub cache_dir: String,
    /// Directory for `psc.log` debug output (module-managed temp dir); empty = logging disabled.
    #[serde(default)]
    pub log_dir: String,
}

/// Paths to the order files used to rank the candidate items.
#[derive(serde::Deserialize, Clone)]
pub struct CompleteOrder {
    /// Per-command order file (already URL-encoded filename).
    #[serde(default)]
    pub cmd_order: String,
    /// Global path-leaf history (_shared/_paths.json).
    #[serde(default)]
    pub paths_order: String,
    /// Global command-use frequency (_shared/_commands.json).
    #[serde(default)]
    pub commands_order: String,
}

/// Assemble the `psc.data` value for the psc completion (settings + completions.json + config).
pub fn build_psc_data(input: &CompleteInput) -> serde_json::Value {
    let mut data = serde_json::json!({
        "list": [],
        "alias": {},
        "remote": [],
        "meta": {},
    });
    if !input.data.is_object() {
        return data;
    }
    let d = input.data.as_object().unwrap();
    if let Some(p) = d.get("settings").and_then(|s| s.as_str()) {
        if let Ok(t) = std::fs::read_to_string(p) {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(crate::strip_bom(&t)) {
                if let Some(alias) = v.get("alias") {
                    data["alias"] = alias.clone();
                    let names: Vec<&str> = alias
                        .as_object()
                        .map(|o| o.keys().map(|k| k.as_str()).collect())
                        .unwrap_or_default();
                    data["list"] = serde_json::json!(names);
                }
            }
        }
    }
    if let Some(p) = d.get("completions_json").and_then(|s| s.as_str()) {
        if let Ok(t) = std::fs::read_to_string(p) {
            if let Ok(v) = serde_json::from_str::<serde_json::Value>(crate::strip_bom(&t)) {
                let remote: Vec<&str> = v
                    .get("update")
                    .and_then(|u| u.as_object())
                    .map(|o| o.keys().map(|k| k.as_str()).collect())
                    .unwrap_or_default();
                data["remote"] = serde_json::json!(remote);
                if let Some(meta) = v.get("meta") {
                    data["meta"] = meta.clone();
                }
            }
        }
    }
    for key in ["config", "menu_colors", "completions"] {
        if let Some(v) = d.get(key) {
            data[key] = v.clone();
        }
    }
    data
}

/// Input for `--sort` mode: host-provided candidate items + order-file paths.
#[derive(serde::Deserialize)]
pub struct SortInput {
    pub items: Vec<hooks::LuaItem>,
    #[serde(default)]
    pub order: Option<CompleteOrder>,
    /// The input line's tokens (including the first one), as the host tokenized them.
    #[serde(default)]
    pub tokens: Vec<String>,
    /// Whether the last token is complete (a space followed it on the input line).
    #[serde(default)]
    pub treat_last_as_complete: bool,
}

/// Whether the completion targets the first token of the input line (root-command name or
/// path): only then does the shared global command-frequency file (`_commands.json`) apply. Once
/// the command is complete (`npm <Tab>`) or more tokens follow (`git st<Tab>`), the candidates
/// are the command's own subcommands/arguments and must rank against the per-command order file
/// only. The shared path-leaf frequency (`_paths.json`) is not depth-gated, but matches only
/// explicit path candidates (text containing `/` or `\`, e.g. `cd .\src\<Tab>`) — bare words
/// never consult it.
pub fn sort_input_is_root(input: &SortInput) -> bool {
    input.tokens.len() == 1 && !input.treat_last_as_complete
}

/// Rank the candidate items using the history-order files: per-command order, (root completions
/// only) the global command frequency, and — for path-shaped candidates at any depth — the
/// global path-leaf frequency. Items without a score keep their original relative order
/// (stable sort).
pub fn apply_order_sort(
    items: &mut [hooks::LuaItem],
    order: &Option<CompleteOrder>,
    use_shared: bool,
) {
    let Some(o) = order else { return };
    let cmd_order = read_order_map(&o.cmd_order);
    // `_paths.json` keys by path-leaf name and matches only path-shaped candidates (an explicit
    // path completion such as `cd .\src\<Tab>`), so it is not gated on `use_shared`. Bare words
    // never consult it — otherwise unrelated path history leaks into subcommand ranking.
    // Only the root-command frequency (`_commands.json`) must not leak into subcommand ranking.
    let paths_order = read_order_map(&o.paths_order);
    let commands_order = if use_shared {
        read_order_map(&o.commands_order)
    } else {
        HashMap::new()
    };
    if cmd_order.is_empty() && paths_order.is_empty() && commands_order.is_empty() {
        return;
    }
    items.sort_by(|a, b| {
        item_score(b, &cmd_order, &paths_order, &commands_order).cmp(&item_score(
            a,
            &cmd_order,
            &paths_order,
            &commands_order,
        ))
    });
}

pub fn read_order_map(path: &str) -> HashMap<String, i64> {
    let Ok(text) = std::fs::read_to_string(path) else {
        return HashMap::new();
    };
    let Ok(v) = serde_json::from_str::<serde_json::Value>(crate::strip_bom(&text)) else {
        return HashMap::new();
    };
    v.as_object()
        .map(|o| {
            o.iter()
                .filter_map(|(k, val)| val.as_i64().map(|n| (k.clone(), n)))
                .collect()
        })
        .unwrap_or_default()
}

pub fn item_score(
    it: &hooks::LuaItem,
    cmd_order: &HashMap<String, i64>,
    paths_order: &HashMap<String, i64>,
    commands_order: &HashMap<String, i64>,
) -> i64 {
    // Mirror the writer's key normalization (order.rs `normalize_key`): surrounding quotes
    // are stripped so a quoted candidate (`"#FFA500"`) matches the quote-stripped key from
    // a quoted history token (`'#ffa500'`); the path branch mirrors `path_segments`.
    let text = it.text.trim_matches('"').trim_matches('\'');
    if text.contains('/') || text.contains('\\') {
        // A trailing separator (a directory candidate like `.\src\`) is ignored so the
        // directory's own name is the leaf — matching how `_paths.json` keys them.
        let leaf = text
            .trim_end_matches(['/', '\\'])
            .rsplit(['/', '\\'])
            .next()
            .unwrap_or("")
            .to_lowercase();
        return paths_order.get(&leaf).copied().unwrap_or(0);
    }
    // Bare words never consult `_paths.json`: a subcommand sharing a name with a directory in
    // path history (e.g. npm `test` vs a `test\` folder) must not inherit its weight.
    let lower = text.to_lowercase();
    if let Some(s) = cmd_order.get(&lower) {
        return *s;
    }
    if let Some(s) = commands_order.get(&lower) {
        return *s;
    }
    0
}

/// Build candidate items from a manifest context: read manifest → build tree → resolve → run
/// hooks → order-sort. Returns the items plus the resolved context. Used by the menu's build mode.
pub fn build_candidate_items(
    input: &CompleteInput,
) -> Result<(Vec<hooks::LuaItem>, completion::ResolvedContext), String> {
    let manifest = std::fs::read_to_string(&input.manifest)
        .map_err(|_| format!("manifest read failed: {}", input.manifest))?;
    let json: serde_json::Value = serde_json::from_str(crate::strip_bom(&manifest))
        .map_err(|e| format!("manifest json: {e}"))?;
    let tree = completion::build_tree(&json);
    let resolved = completion::resolve(&tree, &input.arg_tokens, input.treat_last_as_complete);
    let static_items: Vec<hooks::LuaItem> =
        resolved.items.iter().map(hooks::LuaItem::from).collect();

    // Result cache: covers both static resolve and hook output (the built items). The signature
    // covers everything that can change the result; a hit within 10s of the cache file's
    // creation reuses it. hooks_mtime is part of the signature only when a hook actually exists.
    let cache_enabled = input
        .global_config
        .get("enable_cache")
        .and_then(|v| match v {
            serde_json::Value::Number(n) => n.as_i64().map(|n| n != 0),
            serde_json::Value::Bool(b) => Some(*b),
            _ => None,
        })
        .unwrap_or(true);
    let cache_sig = if cache_enabled {
        let hook_path = hooks_path(&input.manifest);
        let manifest_mtime = file_mtime_nanos(&input.manifest).unwrap_or(0);
        let hooks_mtime = hook_path.as_deref().and_then(file_mtime_nanos);
        Some(hook_signature(input, manifest_mtime, hooks_mtime))
    } else {
        None
    };
    if let Some(sig) = cache_sig {
        if let Some(cached) = cache_load(input, sig) {
            let mut final_items = cached;
            apply_order_sort(&mut final_items, &input.order, false);
            return Ok((final_items, resolved.context));
        }
    }

    // If hooks are enabled and a hooks.lua exists, run the Lua hook to merge in dynamic items
    let final_items = if input.hooks {
        if let Some(hook_path) = hooks_path(&input.manifest) {
            if let Ok(script) = std::fs::read_to_string(&hook_path) {
                // Merge config layers: global (with built-in defaults) → manifest
                // defaults → per-completion overrides.  The host already merged
                // built-in defaults into global_config, so we just extract its flat
                // keys (skipping sub-objects like "completion"/"alias").
                let mut merged_config = serde_json::Map::new();
                if let Some(global) = input.global_config.as_object() {
                    for (k, v) in global {
                        if v.is_object() || v.is_array() {
                            continue;
                        }
                        merged_config.insert(k.clone(), v.clone());
                    }
                }
                if let Some(defaults) = json
                    .as_object()
                    .and_then(|m| m.get("config"))
                    .and_then(|c| c.as_array())
                {
                    for item in defaults {
                        if let (Some(name), Some(value)) =
                            (item.get("name").and_then(|n| n.as_str()), item.get("value"))
                        {
                            merged_config.insert(name.to_string(), value.clone());
                        }
                    }
                }
                if let Some(user) = input.config.as_object() {
                    for (k, v) in user {
                        merged_config.insert(k.clone(), v.clone());
                    }
                }
                let config = serde_json::Value::Object(merged_config);
                let context = hooks::HookContext {
                    cmd: input.cmd.clone(),
                    path: resolved.context.path.clone(),
                    layers: resolved.context.layers.clone(),
                    typing: resolved
                        .context
                        .pending
                        .as_ref()
                        .map(|p| hooks::Typing {
                            text: p.text.clone(),
                            kind: p.kind.clone(),
                            canonical: p.canonical.clone(),
                            option_like: p
                                .text
                                .as_deref()
                                .map(|t| t.starts_with('-'))
                                .unwrap_or(false),
                        })
                        .unwrap_or_default(),
                    opts: resolved.context.opts.clone(),
                    tokens: resolved
                        .context
                        .tokens
                        .iter()
                        .map(|t| hooks::Token {
                            text: t.text.clone(),
                            kind: t.kind.clone(),
                            canonical: t.canonical.clone(),
                        })
                        .collect(),
                    config,
                    manifest: json.clone(),
                    data: build_psc_data(input),
                    language: input
                        .global_config
                        .get("language")
                        .and_then(|v| v.as_str())
                        .unwrap_or("en-US")
                        .to_string(),
                    cwd: input.cwd.clone(),
                    log_dir: input.log_dir.clone(),
                };
                match hooks::run_hook(&context, &script, &static_items) {
                    Ok(items) => items,
                    Err(e) => {
                        eprintln!("hook error: {e}");
                        // Surface hook failures in the debug log so authors can inspect them
                        // (the menu still falls back to the static items).
                        let path = context
                            .path
                            .iter()
                            .map(|s| s.as_str())
                            .collect::<Vec<_>>()
                            .join(" ");
                        let path = if path.is_empty() {
                            String::new()
                        } else {
                            format!(" {path}")
                        };
                        hooks::log_hook_error(&context.log_dir, &input.cmd, &path, &e);
                        static_items.clone()
                    }
                }
            } else {
                static_items.clone()
            }
        } else {
            static_items.clone()
        }
    } else {
        static_items
    };

    // Separator-list continuation (`--exclude a,<TAB>`): every item here is a
    // value of the same slot — drop already-used segments (hooks-added ones
    // included) and take no auto space. Static items already carry both from
    // resolve; this covers what hooks added or rebuilt.
    let mut final_items = final_items;
    if let Some(p) = resolved.context.pending.as_ref() {
        if p.list_sep.is_some() {
            final_items.retain(|it| !p.list_used.iter().any(|u| u.eq_ignore_ascii_case(&it.text)));
            for it in &mut final_items {
                it.nospace = true;
            }
        }
    }

    if let Some(sig) = cache_sig {
        cache_store(input, sig, &final_items);
    }

    apply_order_sort(&mut final_items, &input.order, false);
    Ok((final_items, resolved.context))
}

/// Peek where applying `candidate` at `input` lands.
/// Returns `Some("switch")` if the landing is richer than the parent layer,
/// `Some("stay")` if the landing menu is alive, `None` if the landing is
/// dead (empty next menu).
///
/// Parses the manifest from scratch on each call (backward-compatible entry point).
/// Prefer `peek_predict_symbol_with_tree` when a pre-parsed tree is available
/// (e.g. from the menu background peek thread) to avoid redundant manifest I/O.
pub fn peek_has_next(input: &CompleteInput, candidate: &str) -> bool {
    peek_predict_symbol(input, candidate).is_some()
}

pub fn peek_predict_symbol(input: &CompleteInput, candidate: &str) -> Option<String> {
    let text = std::fs::read_to_string(&input.manifest).ok()?;
    let json = serde_json::from_str::<serde_json::Value>(crate::strip_bom(&text)).ok()?;
    let tree = completion::build_tree(&json);
    peek_predict_symbol_with_tree(input, candidate, &tree)
}

/// Like `peek_predict_symbol`, but uses a pre-parsed `Tree` for the fast path
/// and global-option extraction, avoiding redundant manifest reads.
/// The `build_candidate_items` slow path still reads the manifest internally
/// (mitigated by the result cache).
pub fn peek_predict_symbol_with_tree(
    input: &CompleteInput,
    candidate: &str,
    tree: &completion::Tree,
) -> Option<String> {
    peek_predict_symbol_inner(input, candidate, tree, None)
}

/// Like `peek_predict_symbol_with_tree`, but with pre-computed parent items
/// to avoid redundant `build_candidate_items` calls for every candidate.
/// The caller is responsible for ensuring `parent_items` matches `input`
/// (same `arg_tokens`, same `treat_last_as_complete`).
pub(crate) fn peek_predict_symbol_with_tree_cached(
    input: &CompleteInput,
    candidate: &str,
    tree: &completion::Tree,
    parent_items: &[hooks::LuaItem],
) -> Option<String> {
    peek_predict_symbol_inner(input, candidate, tree, Some(parent_items))
}

fn peek_predict_symbol_inner(
    input: &CompleteInput,
    candidate: &str,
    tree: &completion::Tree,
    cached_parent: Option<&[hooks::LuaItem]>,
) -> Option<String> {
    if candidate.trim().is_empty() {
        return None;
    }
    // Navigate arg_tokens to find the current context node, then search within that subtree (not the whole tree).
    let (ctx, stack, in_value_slot) =
        resolve_context_stack(tree, &input.arg_tokens, input.treat_last_as_complete);
    // Fast static path: if the candidate's own node within the current context has static candidates, it's a switch.
    if let Some(node) = find_node_in_context(ctx, tree, candidate) {
        if has_static_candidates(node) {
            return Some("switch".into());
        }
    }
    let mut peek = input.clone();
    peek.arg_tokens.push(candidate.to_string());
    peek.treat_last_as_complete = true;
    peek.order = None;
    peek.log_dir = String::new();
    let peek_items = match build_candidate_items(&peek) {
        Ok((items, _)) => items,
        Err(_) => return None,
    };
    if peek_items.is_empty() {
        return None;
    }
    let parent_set: std::collections::HashSet<String> = if let Some(cached) = cached_parent {
        cached.iter().map(|it| it.text.to_lowercase()).collect()
    } else {
        let mut parent = input.clone();
        parent.order = None;
        parent.log_dir = String::new();
        let items = match build_candidate_items(&parent) {
            Ok((items, _)) => items,
            Err(_) => return None,
        };
        items.iter().map(|it| it.text.to_lowercase()).collect()
    };
    // Exclude ambient items: `global_option` plus whatever the peek layer
    // merely inherits (ancestor options bubbling down, or root `option` as
    // the fallback source). Such items appear in both lists without opening
    // a new layer, so they must not count as new or remaining (see
    // design/completion.md).
    let mut globals: std::collections::HashSet<String> = tree
        .global_options
        .iter()
        .flat_map(|n| n.all_names().map(|s| s.to_lowercase()))
        .collect();
    if in_value_slot && stack.is_empty() {
        // An option value at the root: the parent menu lists only value
        // candidates, and consuming the value drops back to the root layer, so
        // every root candidate (commands *and* options) is ambient here. A
        // reset command layer is `stay`, never `switch` (design/completion.md §3).
        globals.extend(
            tree.next
                .iter()
                .chain(tree.options.iter())
                .flat_map(|n| n.all_names().map(|s| s.to_lowercase())),
        );
    } else if !stack.is_empty() {
        // Inside a command, the root `option` is only a fallback source.
        globals.extend(
            tree.options
                .iter()
                .flat_map(|n| n.all_names().map(|s| s.to_lowercase())),
        );
    }
    globals.extend(
        stack
            .iter()
            .flat_map(|n| n.option.iter())
            .flat_map(|n| n.all_names().map(|s| s.to_lowercase())),
    );
    let has_new = peek_items.iter().any(|it| {
        !parent_set.contains(&it.text.to_lowercase()) && !globals.contains(&it.text.to_lowercase())
    });
    if has_new {
        return Some("switch".into());
    }
    // No new layer: check if staying in the same layer still has completions.
    // A candidate gets "stay" when selecting it leaves the candidate list
    // unchanged (i.e. the context doesn't shift).  This is true for option
    // flags and dynamic values, but NOT for manifest commands — selecting
    // a command removes its siblings from the list, so the context has moved.
    // (The fast path above already returns "switch" for candidates with static
    // candidates, so we don't re-check.)
    // Landing is alive (non-empty, checked above) with nothing beyond the
    // parent: flags, values and leaf commands alike keep the menu working.
    // Only the landing matters here — never remainder composition, never
    // the item kind. Ambient exclusion lives solely in the `has_new`
    // computation above (it guards `switch` against ubiquitous items
    // faking a new layer).
    Some("stay".into())
}

fn has_static_candidates(node: &completion::Node) -> bool {
    (node.next_is_array && !node.next.is_empty())
        || (node.option_is_array && !node.option.is_empty())
}

/// Walk `arg_tokens` (the typed command words after the command name) through the
/// tree's command chain to find the deepest matching context node plus the full
/// command stack. Commands push their node as the new context; options (bubbled
/// or global) are consumed without changing the context, matching the same
/// context-maintenance behaviour that `completion::resolve` uses.
///
/// Also reports whether the input sits in an **option value slot** — the pending
/// word belongs to an option that takes a value. That state has an empty command
/// stack exactly like the root does, so `stack.is_empty()` alone cannot tell the
/// two apart. Like `completion::resolve`, an unrecognized word does not move the
/// context and does not stop the walk: whether some earlier word happened to be a
/// defined command must not change how a later option is read.
fn resolve_context_stack<'a>(
    tree: &'a completion::Tree,
    arg_tokens: &[String],
    treat_last_as_complete: bool,
) -> (
    Option<&'a completion::Node>,
    Vec<&'a completion::Node>,
    bool,
) {
    let mut ctx: Option<&'a completion::Node> = None;
    let mut stack: Vec<&'a completion::Node> = Vec::new();
    let mut in_value_slot = false;
    for (i, token) in arg_tokens.iter().enumerate() {
        // 1. Try the command chain (`next`).
        let next = if let Some(c) = ctx {
            c.next.iter().find(|n| n.matches(token))
        } else {
            tree.next.iter().find(|n| n.matches(token))
        };
        if let Some(n) = next {
            ctx = Some(n);
            stack.push(n);
            in_value_slot = false;
            continue;
        }
        // 2. Not a command — check if it's an option (bubbling → root → global).
        //    Options don't switch context, so keep ctx and stack unchanged.
        //    An `=`-attached word carries its value inline, so match on the head.
        let head = completion::split_eq_token(token)
            .map(|(left, _)| left)
            .unwrap_or(token.as_str());
        let opt = stack
            .iter()
            .rev()
            .flat_map(|n| n.option.iter())
            .chain(tree.options.iter())
            .chain(tree.global_options.iter())
            .find(|o| o.matches(head));
        if let Some(o) = opt {
            in_value_slot = o.next_is_array || (o.option_is_array && !o.option.is_empty());
            continue;
        }
        // 3. A free-form word. Inside a value slot it is that option's value;
        //    outside one it is an unknown token at the current context. Either
        //    way the context is unchanged — keep walking. The slot only stays
        //    open while the word is still the one being typed.
        let pending_word = i + 1 == arg_tokens.len() && !treat_last_as_complete;
        if !(in_value_slot && pending_word) {
            in_value_slot = false;
        }
    }
    (ctx, stack, in_value_slot)
}

/// Find the node a candidate row came from: a **direct** child of the current
/// context's `next`/`option` (or of the root tree when `ctx` is `None`), plus
/// global options. Deliberately not recursive — a deeper node that happens to
/// share the spelling is a *different* option, and borrowing its candidates
/// would mislabel the row's landing (design/completion.md §3).
fn find_node_in_context<'a>(
    ctx: Option<&'a completion::Node>,
    tree: &'a completion::Tree,
    name: &str,
) -> Option<&'a completion::Node> {
    let search_next: &[completion::Node] = ctx.map_or(&tree.next, |c| &c.next);
    let search_option: &[completion::Node] = ctx.map_or(&tree.options, |c| &c.option);
    search_next
        .iter()
        .chain(search_option.iter())
        .chain(tree.global_options.iter())
        .find(|n| n.all_names().any(|a| a == name))
}

/// Derive the hooks.lua path from the manifest path: `<cmd>/language/<lang>.json` → `<cmd>/hooks.lua`.
pub fn hooks_path(manifest: &str) -> Option<String> {
    std::path::Path::new(manifest)
        .parent()
        .and_then(|p| p.parent())
        .map(|p| p.join("hooks.lua"))
        .map(|p| p.to_string_lossy().to_string())
}

/// Result cache: a 10-second disk cache keyed by the completion context, so quickly re-opening
/// the same menu reuses the built items (static resolve and/or hook output) instead of
/// rebuilding them (scoop's ~600ms scan, etc.).
const CACHE_TTL: std::time::Duration = std::time::Duration::from_secs(10);

/// A completion-context signature: everything that can change the built items. `hooks.lua`'s
/// path is deliberately excluded (it is fixed per completion, already implied by `cmd`); its
/// mtime IS included so an updated hook invalidates stale results. `manifest` includes the
/// language variant (en-US vs zh-CN). Returns a fixed-size hash usable as a safe filename.
pub fn hook_signature(input: &CompleteInput, manifest_mtime: u64, hooks_mtime: Option<u64>) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut h = std::collections::hash_map::DefaultHasher::new();
    input.cmd.hash(&mut h);
    input.arg_tokens.hash(&mut h);
    input.treat_last_as_complete.hash(&mut h);
    // Whether hooks run at all changes the result (dynamic items vs static-only).
    input.hooks.hash(&mut h);
    input.manifest.hash(&mut h);
    manifest_mtime.hash(&mut h);
    hooks_mtime.hash(&mut h);
    input.cwd.hash(&mut h);
    // config serialized for a stable hash across identical values.
    input.config.to_string().hash(&mut h);
    // Global config (e.g. `language`, which hooks read for localized tips) can change the result.
    input.global_config.to_string().hash(&mut h);
    // Module-level data files (psc completion: settings.json / completions.json) drive the
    // dynamic lists; their mtime changes when the installed/remote completions change.
    for path in psc_data_file_paths(input) {
        file_mtime_nanos(&path).hash(&mut h);
    }
    h.finish()
}

/// The module data files `build_psc_data` reads (`settings` / `completions_json` paths), used
/// to invalidate the result cache when the installed/remote completion set changes.
pub fn psc_data_file_paths(input: &CompleteInput) -> Vec<String> {
    let mut out = Vec::new();
    if let Some(d) = input.data.as_object() {
        for key in ["settings", "completions_json"] {
            if let Some(p) = d.get(key).and_then(|v| v.as_str()) {
                out.push(p.to_string());
            }
        }
    }
    out
}

pub fn file_mtime_nanos(path: &str) -> Option<u64> {
    std::fs::metadata(path)
        .ok()
        .and_then(|m| m.modified().ok())
        .map(|t| {
            t.duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos() as u64
        })
}

/// Try to load the cached hook result for this context. Returns `Some(items)` on a hit.
pub fn cache_load(input: &CompleteInput, sig: u64) -> Option<Vec<hooks::LuaItem>> {
    if input.cache_dir.is_empty() {
        return None;
    }
    let path = format!(
        "{}/{}.json",
        input.cache_dir.trim_end_matches(['/', '\\']),
        sig
    );
    let text = std::fs::read_to_string(&path).ok()?;
    let v: serde_json::Value = serde_json::from_str(&text).ok()?;
    let created = v.get("created")?.as_u64()?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    if now.saturating_sub(created) >= CACHE_TTL.as_secs() {
        // Expired: drop it (nothing depends on the stale file).
        let _ = std::fs::remove_file(&path);
        return None;
    }
    let items = serde_json::from_value(v.get("items")?.clone()).ok()?;
    Some(items)
}

/// Delete every expired cache file in the directory (older than `CACHE_TTL`). Only the
/// currently-hit file is removed lazily in `cache_load`; the rest would linger forever, so
/// sweep them on each store. Expiry is judged by the file's `created` field (same rule as
/// `cache_load`), not the filesystem mtime.
pub fn cache_cleanup(cache_dir: &str) {
    let dir = cache_dir.trim_end_matches(['/', '\\']);
    if dir.is_empty() {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    for entry in entries.flatten() {
        let path = entry.path();
        let is_json = path
            .extension()
            .and_then(|e| e.to_str())
            .map(|e| e == "json")
            .unwrap_or(false);
        if !is_json {
            continue;
        }
        let expired = std::fs::read_to_string(&path)
            .ok()
            .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
            .and_then(|v| v.get("created").and_then(|c| c.as_u64()))
            .map(|created| now.saturating_sub(created) >= CACHE_TTL.as_secs())
            .unwrap_or(false);
        if expired {
            let _ = std::fs::remove_file(&path);
        }
    }
}

/// Write the hook result to the cache (only when caching is enabled).
pub fn cache_store(input: &CompleteInput, sig: u64, items: &[hooks::LuaItem]) {
    if input.cache_dir.is_empty() {
        return;
    }
    let dir = input.cache_dir.trim_end_matches(['/', '\\']);
    cache_cleanup(&input.cache_dir);
    let _ = std::fs::create_dir_all(dir);
    let path = format!("{dir}/{sig}.json");
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let v = serde_json::json!({ "created": now, "items": items });
    let _ = std::fs::write(path, serde_json::to_string(&v).unwrap_or_default());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lua_to_model_item_resolves_predict_symbols() {
        let base = hooks::LuaItem {
            text: "commit".into(),
            ..Default::default()
        };
        // `switch` / `stay` are config keys; the display character comes from the context config.
        let mut it = hooks::LuaItem {
            symbol: Some("switch".into()),
            ..base.clone()
        };
        let m = lua_to_model_item(&it, "~", "?");
        assert_eq!(m.symbol, "~");
        assert_eq!(m.completion_text, "commit");
        assert_eq!(m.list_item_text, "commit");
        it.symbol = Some("stay".into());
        assert_eq!(lua_to_model_item(&it, "~", "?").symbol, "?");
        // Absent symbol → empty; an unknown key passes through verbatim.
        it.symbol = None;
        assert_eq!(lua_to_model_item(&it, "~", "?").symbol, "");
        it.symbol = Some("custom".into());
        assert_eq!(lua_to_model_item(&it, "~", "?").symbol, "custom");
    }

    #[test]
    fn item_score_keys_directories_by_their_own_name() {
        let mut paths: HashMap<String, i64> = HashMap::new();
        paths.insert("src".into(), 10);
        paths.insert("lib".into(), 6);
        let empty = HashMap::new();
        let dir = hooks::LuaItem {
            text: ".\\src\\".into(),
            ..Default::default()
        };
        // A directory candidate (trailing separator) scores under its own name.
        assert_eq!(item_score(&dir, &empty, &paths, &empty), 10);
        let file = hooks::LuaItem {
            text: ".\\src\\main.rs".into(),
            ..Default::default()
        };
        assert_eq!(item_score(&file, &empty, &paths, &empty), 0);
        // Unscored directory → 0.
        let unknown = hooks::LuaItem {
            text: ".\\other\\".into(),
            ..Default::default()
        };
        assert_eq!(item_score(&unknown, &empty, &paths, &empty), 0);
    }

    #[test]
    fn item_score_strips_quotes_like_the_writer() {
        let mut cmd_order: HashMap<String, i64> = HashMap::new();
        cmd_order.insert("#ffa500".into(), 51);
        cmd_order.insert("black".into(), 40);
        let empty = HashMap::new();
        // Quoted candidate (the manifest wraps color values in quotes) matches the
        // quote-stripped key the writer stored from a quoted history token.
        let quoted = hooks::LuaItem {
            text: "\"#FFA500\"".into(),
            ..Default::default()
        };
        assert_eq!(item_score(&quoted, &cmd_order, &empty, &empty), 51);
        // A plain (unquoted) candidate matches too.
        let plain = hooks::LuaItem {
            text: "black".into(),
            ..Default::default()
        };
        assert_eq!(item_score(&plain, &cmd_order, &empty, &empty), 40);
    }

    #[test]
    fn item_score_strips_quotes_before_path_leaf() {
        let mut paths: HashMap<String, i64> = HashMap::new();
        paths.insert("foo".into(), 8);
        let empty = HashMap::new();
        let quoted = hooks::LuaItem {
            text: "\"C:\\foo\"".into(),
            ..Default::default()
        };
        // Without stripping, the leaf would be `foo"` and miss the key.
        assert_eq!(item_score(&quoted, &empty, &paths, &empty), 8);
    }

    #[test]
    fn item_score_bare_words_ignore_paths_order() {
        let mut paths: HashMap<String, i64> = HashMap::new();
        paths.insert("test".into(), 45);
        let empty = HashMap::new();
        // A bare word (npm's `test` subcommand) must not inherit the shared path-leaf weight
        // of a same-named directory in `_paths.json` — unscored → keeps manifest order.
        let word = hooks::LuaItem {
            text: "test".into(),
            ..Default::default()
        };
        assert_eq!(item_score(&word, &empty, &paths, &empty), 0);
        // The per-command order still ranks the bare word normally.
        let mut cmd: HashMap<String, i64> = HashMap::new();
        cmd.insert("test".into(), 9);
        assert_eq!(item_score(&word, &cmd, &paths, &empty), 9);
    }

    #[test]
    fn build_mode_ignores_shared_global_frequencies() {
        let mut cmd_order: HashMap<String, i64> = HashMap::new();
        cmd_order.insert("run".into(), 4);
        let mut commands_order: HashMap<String, i64> = HashMap::new();
        commands_order.insert("ls".into(), 57);
        commands_order.insert("list".into(), 44);
        let empty: HashMap<String, i64> = HashMap::new();

        // build mode (use_shared = false): `ls`/`list` fall back to 0 → stable manifest order.
        let item = |t: &str| hooks::LuaItem {
            text: t.into(),
            ..Default::default()
        };
        assert_eq!(item_score(&item("run"), &cmd_order, &empty, &empty), 4);
        assert_eq!(item_score(&item("ls"), &cmd_order, &empty, &empty), 0);
        assert_eq!(item_score(&item("list"), &cmd_order, &empty, &empty), 0);
        // native mode (use_shared = true): the shared root-command frequency applies.
        assert_eq!(
            item_score(&item("ls"), &cmd_order, &empty, &commands_order),
            57
        );
    }

    #[test]
    fn peek_gives_stay_in_ambient_only_layer() {
        // `menu` is a leaf: its candidates are the bubbled `--aaa`/`--bbb`
        // (from `config`) plus `--help`. Applying `--aaa` lands in an
        // alive menu, so the symbol is `stay` — `?` reports the landing
        // only, never remainder composition, never the item kind
        // (see design/completion.md).
        let dir = std::env::temp_dir().join(format!("psc-peek-test-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let manifest = dir.join("manifest.json");
        std::fs::write(
            &manifest,
            r#"{"meta":{"url":"https://example.com","description":["t"]},"next":[{"name":"config","option":[{"name":"--aaa"},{"name":"--bbb"}],"next":[{"name":"menu"}]}],"global_option":[{"name":"--help"}]}"#,
        )
        .unwrap();
        let input = CompleteInput {
            cmd: "t".into(),
            arg_tokens: vec!["config".into(), "menu".into()],
            treat_last_as_complete: true,
            manifest: manifest.to_string_lossy().into_owned(),
            hooks: false,
            cwd: String::new(),
            config: serde_json::Value::Null,
            global_config: serde_json::json!({ "enable_cache": 0 }),
            data: serde_json::Value::Null,
            order: None,
            cache_dir: String::new(),
            log_dir: String::new(),
        };
        assert_eq!(peek_predict_symbol(&input, "--aaa"), Some("stay".into()));
        // Sanity: a subcommand with static candidates still predicts `switch`.
        let root = CompleteInput {
            arg_tokens: vec![],
            ..input.clone()
        };
        assert_eq!(peek_predict_symbol(&root, "config"), Some("switch".into()));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn peek_gives_stay_to_flag_beside_subcommands() {
        // npm-like root: `run`/`install` subcommands plus boolean flags.
        // Applying `--aaa` stays in the root layer with `run`/`install`
        // still reachable, so the async peek assigns `stay` — the static
        // phase only fast-paths `switch` (see design/completion.md).
        let dir = std::env::temp_dir().join(format!("psc-peek-stay-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let manifest = dir.join("manifest.json");
        std::fs::write(
            &manifest,
            r#"{"meta":{"url":"https://example.com","description":["t"]},"next":[{"name":"run"},{"name":"install"}],"option":[{"name":"--aaa"},{"name":"--bbb"}]}"#,
        )
        .unwrap();
        let input = CompleteInput {
            cmd: "t".into(),
            arg_tokens: vec![],
            treat_last_as_complete: true,
            manifest: manifest.to_string_lossy().into_owned(),
            hooks: false,
            cwd: String::new(),
            config: serde_json::Value::Null,
            global_config: serde_json::json!({ "enable_cache": 0 }),
            data: serde_json::Value::Null,
            order: None,
            cache_dir: String::new(),
            log_dir: String::new(),
        };
        assert_eq!(peek_predict_symbol(&input, "--aaa"), Some("stay".into()));
        assert_eq!(peek_predict_symbol(&input, "--bbb"), Some("stay".into()));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn peek_gives_stay_to_global_flag_with_followups() {
        // `npm --allow-file`-like: a global boolean flag. Applying it lands
        // in an alive menu, so it is `stay` — at the root and in an
        // ambient-only leaf alike. A leaf command lands in an alive
        // ambient-only layer → `stay` as well; no symbol means a dead
        // (empty) landing.
        let dir = std::env::temp_dir().join(format!("psc-peek-global-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let manifest = dir.join("manifest.json");
        std::fs::write(
            &manifest,
            r#"{"meta":{"url":"https://example.com","description":["t"]},"next":[{"name":"run"},{"name":"install"},{"name":"cfg","next":[{"name":"leaf"}]}],"global_option":[{"name":"--allow-file"},{"name":"--allow-remote"}]}"#,
        )
        .unwrap();
        let base = CompleteInput {
            cmd: "t".into(),
            arg_tokens: vec![],
            treat_last_as_complete: true,
            manifest: manifest.to_string_lossy().into_owned(),
            hooks: false,
            cwd: String::new(),
            config: serde_json::Value::Null,
            global_config: serde_json::json!({ "enable_cache": 0 }),
            data: serde_json::Value::Null,
            order: None,
            cache_dir: String::new(),
            log_dir: String::new(),
        };
        assert_eq!(
            peek_predict_symbol(&base, "--allow-file"),
            Some("stay".into())
        );
        let leaf = CompleteInput {
            arg_tokens: vec!["cfg".into(), "leaf".into()],
            ..base.clone()
        };
        assert_eq!(
            peek_predict_symbol(&leaf, "--allow-file"),
            Some("stay".into())
        );
        let cfg = CompleteInput {
            arg_tokens: vec!["cfg".into()],
            ..base.clone()
        };
        assert_eq!(peek_predict_symbol(&cfg, "leaf"), Some("stay".into()));
        let _ = std::fs::remove_dir_all(&dir);
    }

    fn sample_input() -> CompleteInput {
        CompleteInput {
            cmd: "scoop".into(),
            arg_tokens: vec!["install".into()],
            treat_last_as_complete: false,
            manifest: "/tmp/scoop/language/en-US.json".into(),
            hooks: true,
            cwd: "/home/user".into(),
            config: serde_json::json!({ "exclude_buckets": "" }),
            global_config: serde_json::json!({ "enable_cache": true }),
            data: serde_json::Value::Null,
            order: None,
            cache_dir: String::new(),
            log_dir: String::new(),
        }
    }

    #[test]
    fn hook_signature_differs_on_key_fields() {
        let mtime = 1000u64;
        let base = sample_input();
        let sig = hook_signature(&base, mtime, None);
        let mut c = sample_input();
        c.cmd = "git".into();
        assert_ne!(
            hook_signature(&c, mtime, None),
            sig,
            "cmd must change signature"
        );
        let mut c = sample_input();
        c.arg_tokens = vec!["install".into(), "7zip".into()];
        assert_ne!(
            hook_signature(&c, mtime, None),
            sig,
            "arg_tokens must change signature"
        );
        let mut c = sample_input();
        c.treat_last_as_complete = true;
        assert_ne!(
            hook_signature(&c, mtime, None),
            sig,
            "treat_last_as_complete must change"
        );
        let mut c = sample_input();
        c.manifest = "/tmp/scoop/language/zh-CN.json".into();
        assert_ne!(
            hook_signature(&c, mtime, None),
            sig,
            "manifest language must change"
        );
        assert_ne!(
            hook_signature(&base, 2000, None),
            sig,
            "manifest mtime must change"
        );
        assert_ne!(
            hook_signature(&base, mtime, Some(500)),
            sig,
            "hooks mtime must change"
        );
        let mut c = sample_input();
        c.cwd = "/elsewhere".into();
        assert_ne!(hook_signature(&c, mtime, None), sig, "cwd must change");
        let mut c = sample_input();
        c.config = serde_json::json!({ "exclude_buckets": "main" });
        assert_ne!(hook_signature(&c, mtime, None), sig, "config must change");
        // The hooks switch flips the result between static-only and dynamic.
        let mut c = sample_input();
        c.hooks = false;
        assert_ne!(hook_signature(&c, mtime, None), sig, "hooks must change");
        // Global config (e.g. `language`) is read by hooks.
        let mut c = sample_input();
        c.global_config = serde_json::json!({ "language": "zh-CN" });
        assert_ne!(
            hook_signature(&c, mtime, None),
            sig,
            "global_config must change"
        );
        // Module data file paths are part of the context (psc completion).
        let mut c = sample_input();
        c.data = serde_json::json!({ "settings": "/tmp/x/settings.json", "completions_json": "/tmp/x/temp/completions.json" });
        assert_ne!(hook_signature(&c, mtime, None), sig, "data must change");
    }

    #[test]
    fn cache_store_then_load_roundtrips() {
        let dir = std::env::temp_dir().join("psc-hook-cache-test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let mut input = sample_input();
        input.cache_dir = dir.to_string_lossy().to_string();
        let sig = hook_signature(&input, 1000, None);
        let items = vec![
            hooks::LuaItem {
                text: "7zip".into(),
                ..Default::default()
            },
            hooks::LuaItem {
                text: "git".into(),
                ..Default::default()
            },
        ];
        cache_store(&input, sig, &items);
        let loaded = cache_load(&input, sig).expect("fresh cache must hit");
        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded[0].text, "7zip");
        // Different signature must not hit.
        let mut other = sample_input();
        other.cache_dir = input.cache_dir.clone();
        let other_sig = hook_signature(&other, 2000, None);
        assert!(cache_load(&other, other_sig).is_none());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn hook_cache_expires_after_ttl() {
        let dir = std::env::temp_dir().join("psc-hook-cache-ttl");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let mut input = sample_input();
        input.cache_dir = dir.to_string_lossy().to_string();
        let sig = hook_signature(&input, 1000, None);
        cache_store(
            &input,
            sig,
            &[hooks::LuaItem {
                text: "x".into(),
                ..Default::default()
            }],
        );
        // Rewrite the cache file with an old `created` timestamp to simulate expiry.
        let path = format!("{}/{sig}.json", dir.to_string_lossy());
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let v = serde_json::json!({ "created": now - CACHE_TTL.as_secs() - 1, "items": [] });
        std::fs::write(&path, serde_json::to_string(&v).unwrap()).unwrap();
        assert!(cache_load(&input, sig).is_none(), "expired cache must miss");
        assert!(
            !std::path::Path::new(&path).exists(),
            "expired cache file must be removed"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn cache_cleanup_removes_expired_files() {
        let dir = std::env::temp_dir().join("psc-cache-cleanup");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        // One fresh file and one expired file.
        let fresh = format!("{}/{}.json", dir.to_string_lossy(), 111u64);
        let expired = format!("{}/{}.json", dir.to_string_lossy(), 222u64);
        std::fs::write(
            &fresh,
            serde_json::json!({ "created": now, "items": [] }).to_string(),
        )
        .unwrap();
        std::fs::write(
            &expired,
            serde_json::json!({ "created": now - CACHE_TTL.as_secs() - 1, "items": [] })
                .to_string(),
        )
        .unwrap();
        cache_cleanup(&dir.to_string_lossy());
        assert!(
            std::path::Path::new(&fresh).exists(),
            "fresh cache must survive cleanup"
        );
        assert!(
            !std::path::Path::new(&expired).exists(),
            "expired cache must be cleaned"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn sort_input_is_root_derives_from_tokens() {
        // `g<Tab>`: one unfinished token -> root (shared global files apply).
        let root = SortInput {
            items: vec![],
            order: None,
            tokens: vec!["g".into()],
            treat_last_as_complete: false,
        };
        assert!(sort_input_is_root(&root));
        // `npm <Tab>`: one completed token -> not root (per-command order only).
        let complete = SortInput {
            items: vec![],
            order: None,
            tokens: vec!["npm".into()],
            treat_last_as_complete: true,
        };
        assert!(!sort_input_is_root(&complete));
        // `git st<Tab>`: more than one token -> not root.
        let multi = SortInput {
            items: vec![],
            order: None,
            tokens: vec!["git".into(), "st".into()],
            treat_last_as_complete: false,
        };
        assert!(!sort_input_is_root(&multi));
        // `.\src\<Tab>`: one unfinished path token -> root.
        let path = SortInput {
            items: vec![],
            order: None,
            tokens: vec![".\\src\\".into()],
            treat_last_as_complete: false,
        };
        assert!(sort_input_is_root(&path));
    }

    #[test]
    fn sort_mode_uses_shared_files_only_when_root() {
        let dir = std::env::temp_dir().join("psc-sort-order-test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        // Per-command order for `npm`: only `run` is scored.
        std::fs::write(
            dir.join("npm.json"),
            serde_json::json!({ "run": 4 }).to_string(),
        )
        .unwrap();
        // Global root-command frequency: `ls`/`list` are heavily used as root commands.
        let shared = dir.join("_shared");
        std::fs::create_dir_all(&shared).unwrap();
        std::fs::write(
            shared.join("_commands.json"),
            serde_json::json!({ "ls": 57, "list": 44 }).to_string(),
        )
        .unwrap();
        let order = Some(CompleteOrder {
            cmd_order: dir.join("npm.json").to_string_lossy().to_string(),
            paths_order: shared.join("_paths.json").to_string_lossy().to_string(),
            commands_order: shared.join("_commands.json").to_string_lossy().to_string(),
        });
        let item = |t: &str| hooks::LuaItem {
            text: t.into(),
            ..Default::default()
        };

        // Non-root native fallback (`npm <Tab>`): `ls`/`list` must NOT pick up their
        // root-command frequency; only `run` (npm's own order file) ranks first.
        let mut items = vec![item("ls"), item("run"), item("list")];
        apply_order_sort(&mut items, &order, false);
        let texts: Vec<&str> = items.iter().map(|i| i.text.as_str()).collect();
        assert_eq!(
            texts,
            vec!["run", "ls", "list"],
            "non-root native mode: only the per-command order file applies"
        );

        // Root completion (`g<Tab>`): the shared root-command frequency ranks the candidates.
        let mut items = vec![item("ls"), item("list"), item("npm")];
        apply_order_sort(&mut items, &order, true);
        let texts: Vec<&str> = items.iter().map(|i| i.text.as_str()).collect();
        assert_eq!(
            texts,
            vec!["ls", "list", "npm"],
            "root native mode: shared command frequency applies"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn sort_mode_path_frequency_needs_explicit_path_candidates() {
        let dir = std::env::temp_dir().join("psc-sort-cd-test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let shared = dir.join("_shared");
        std::fs::create_dir_all(&shared).unwrap();
        // `cd .\core` in history put `core` into the shared path-leaf frequency.
        std::fs::write(
            shared.join("_paths.json"),
            serde_json::json!({ "core": 20 }).to_string(),
        )
        .unwrap();
        let order = Some(CompleteOrder {
            cmd_order: dir.join("cd.json").to_string_lossy().to_string(),
            paths_order: shared.join("_paths.json").to_string_lossy().to_string(),
            commands_order: shared.join("_commands.json").to_string_lossy().to_string(),
        });
        let item = |t: &str| hooks::LuaItem {
            text: t.into(),
            ..Default::default()
        };

        // `cd <Tab>` (non-root: one completed token): bare dir-name candidates are not an
        // explicit path completion — none picks up the shared `core` weight, so the native
        // order is kept (stable).
        let mut items = vec![item("docs"), item("core"), item("assets")];
        apply_order_sort(&mut items, &order, false);
        let texts: Vec<&str> = items.iter().map(|i| i.text.as_str()).collect();
        assert_eq!(
            texts,
            vec!["docs", "core", "assets"],
            "bare-word candidates never rank by shared path frequency"
        );

        // `cd .\src\<Tab>` style: path-shaped candidates rank by leaf even after the command
        // is complete.
        let mut items = vec![item(".\\assets\\"), item(".\\core\\")];
        apply_order_sort(&mut items, &order, false);
        let texts: Vec<&str> = items.iter().map(|i| i.text.as_str()).collect();
        assert_eq!(
            texts,
            vec![".\\core\\", ".\\assets\\"],
            "explicit path candidates rank by shared path-leaf frequency at any depth"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn apply_value_prefix_prefixes_insert_text_only() {
        let items: Vec<model::Item> = ["json", "yaml"]
            .iter()
            .map(|t| {
                lua_to_model_item(
                    &hooks::LuaItem {
                        text: t.to_string(),
                        ..Default::default()
                    },
                    "~",
                    "?",
                )
            })
            .collect();
        // `=`-attached value: inserted text regains the option head, display stays bare.
        let mut prefixed = items.clone();
        let ctx = completion::ResolvedContext {
            pending: Some(completion::PendingInfo {
                text: Some("j".into()),
                kind: Some("value".into()),
                canonical: None,
                value_prefix: Some("--format=".into()),
                list_sep: None,
                list_used: Vec::new(),
            }),
            ..Default::default()
        };
        apply_value_prefix(&mut prefixed, &ctx);
        assert_eq!(prefixed[0].completion_text, "--format=json");
        assert_eq!(prefixed[0].list_item_text, "json");
        // No `=` pending: untouched.
        let mut plain = items.clone();
        let plain_ctx = completion::ResolvedContext {
            pending: None,
            ..Default::default()
        };
        apply_value_prefix(&mut plain, &plain_ctx);
        assert_eq!(plain[0].completion_text, "json");
    }

    #[test]
    fn apply_value_prefix_rebuilds_list_head() {
        let items: Vec<model::Item> = ["bb"]
            .iter()
            .map(|t| {
                lua_to_model_item(
                    &hooks::LuaItem {
                        text: t.to_string(),
                        ..Default::default()
                    },
                    "~",
                    "?",
                )
            })
            .collect();
        // Space-form list: used segments rejoin the head.
        let mut spaced = items.clone();
        let ctx = completion::ResolvedContext {
            pending: Some(completion::PendingInfo {
                text: Some("b".into()),
                kind: Some("value".into()),
                canonical: None,
                value_prefix: None,
                list_sep: Some(",".into()),
                list_used: vec!["aa".into()],
            }),
            ..Default::default()
        };
        apply_value_prefix(&mut spaced, &ctx);
        assert_eq!(spaced[0].completion_text, "aa,bb");
        // `=`-form list: head plus used segments.
        let mut eqd = items.clone();
        let eq_ctx = completion::ResolvedContext {
            pending: Some(completion::PendingInfo {
                text: Some("b".into()),
                kind: Some("value".into()),
                canonical: None,
                value_prefix: Some("--exclude=".into()),
                list_sep: Some(",".into()),
                list_used: vec!["aa".into()],
            }),
            ..Default::default()
        };
        apply_value_prefix(&mut eqd, &eq_ctx);
        assert_eq!(eqd[0].completion_text, "--exclude=aa,bb");
    }

    #[test]
    fn peek_judges_a_value_slot_landing_as_ambient() {
        // At a separator-list tail the parent menu shows only value candidates
        // (by design), so the landing — the root option layer reached after the
        // value is consumed — must not read as "new fruit".
        let dir = std::env::temp_dir().join(format!("psc-peek-sep-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let manifest = dir.join("manifest.json");
        std::fs::write(
            &manifest,
            r#"{"meta":{"url":"https://example.com","description":["t"]},
                "next":[{"name":"sub"}],
                "option":[
                  {"name":"--tag","next":[{"name":"a"},{"name":"b"}]},
                  {"name":"--exclude=","separator":",","next":[{"name":"aa"},{"name":"bb"}]}
                ]}"#,
        )
        .unwrap();
        let base = |tokens: Vec<&str>, complete: bool| CompleteInput {
            cmd: "t".into(),
            arg_tokens: tokens.into_iter().map(str::to_string).collect(),
            treat_last_as_complete: complete,
            manifest: manifest.to_string_lossy().into_owned(),
            hooks: false,
            cwd: String::new(),
            config: serde_json::Value::Null,
            global_config: serde_json::json!({ "enable_cache": 0 }),
            data: serde_json::Value::Null,
            order: None,
            cache_dir: String::new(),
            log_dir: String::new(),
        };

        // `a --exclude=aa,<Tab>`: the pending token is `aa,` (tail empty) and the
        // row rebuilds to `--exclude=aa,bb`. Landing is the root menu.
        let attached = base(vec!["--exclude=aa,"], false);
        assert_eq!(
            peek_predict_symbol(&attached, "--exclude=aa,bb"),
            Some("stay".into()),
            "attached separator-list landing"
        );

        // Space form of the same shape.
        assert_eq!(
            peek_predict_symbol(&base(vec!["--exclude", "aa,"], false), "--exclude=aa,bb"),
            Some("stay".into()),
            "space-form separator-list landing"
        );

        // With a command in the stack the root options were already ambient.
        let with_cmd = base(vec!["sub", "--exclude=aa,"], false);
        assert_eq!(
            peek_predict_symbol(&with_cmd, "--exclude=aa,bb"),
            Some("stay".into()),
            "command-prefixed landing"
        );

        // An *undefined* leading word is just `unknown`: it must not change the
        // answer, because whether some earlier word happened to be a defined
        // command says nothing about how `--exclude=aa,` should be read.
        for prefix in ["zzz", "not-a-command", "123"] {
            let unknown_prefix = base(vec![prefix, "--exclude=aa,"], false);
            assert_eq!(
                peek_predict_symbol(&unknown_prefix, "--exclude=aa,bb"),
                Some("stay".into()),
                "unknown prefix {prefix:?} must not change the verdict"
            );
        }

        // Space form with an unknown word in front of it, too.
        let sp = base(vec!["zzz", "--exclude", "aa,"], false);
        assert_eq!(
            peek_predict_symbol(&sp, "--exclude=aa,bb"),
            Some("stay".into()),
            "space form behind an unknown word"
        );

        // The first level, before any segment is typed: `a --exclude=<Tab>`
        // offers both `aa` and `bb`, and both land on the root menu.
        let first = base(vec!["--exclude="], false);
        assert_eq!(
            peek_predict_symbol(&first, "--exclude=aa"),
            Some("stay".into()),
            "initial value slot (aa)"
        );
        assert_eq!(
            peek_predict_symbol(&first, "--exclude=bb"),
            Some("stay".into()),
            "initial value slot (bb)"
        );

        // A plain `=`-attached value still resolves.
        assert!(
            peek_predict_symbol(&base(vec!["--tag="], false), "--tag=b").is_some(),
            "attached-value peek still resolves"
        );
    }

    #[test]
    fn peek_does_not_borrow_a_deeper_node_with_the_same_name() {
        // Root `-m` is `--model` (no static candidates). A nested `upgrade`
        // owns a *different* `-m` (`--method`) that does have values. The row
        // being previewed is the root one, so its landing must be judged from
        // the root node, not from the unrelated descendant.
        let dir = std::env::temp_dir().join(format!("psc-peek-deep-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let manifest = dir.join("manifest.json");
        std::fs::write(
            &manifest,
            r#"{"meta":{"url":"https://example.com","description":["t"]},
                "option":[{"name":"-m","tip":["model"]}],
                "next":[{"name":"upgrade","option":[
                            {"name":"--method","alias":["-m"],"next":[{"name":"fast"}]}]}]}"#,
        )
        .unwrap();
        let input = CompleteInput {
            cmd: "t".into(),
            arg_tokens: vec![],
            treat_last_as_complete: true,
            manifest: manifest.to_string_lossy().into_owned(),
            hooks: false,
            cwd: String::new(),
            config: serde_json::Value::Null,
            global_config: serde_json::json!({ "enable_cache": 0 }),
            data: serde_json::Value::Null,
            order: None,
            cache_dir: String::new(),
            log_dir: String::new(),
        };
        assert_ne!(peek_predict_symbol(&input, "-m"), Some("switch".into()));
    }
}
