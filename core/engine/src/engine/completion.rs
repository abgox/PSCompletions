//! Completion-tree building + context resolution + candidate generation.
//! A faithful port of PowerShell `get_completion`'s `build_tree` / `match_tree` / item expansion.

use serde_json::Value;
use std::collections::HashMap;

/// A manifest node (subcommand or option).
#[derive(Debug, Clone)]
pub struct Node {
    pub name: String,
    pub aliases: Vec<String>,
    pub tip: Vec<String>,
    pub usage: Vec<String>,
    pub example: Vec<String>,
    pub repeat: i32,
    pub is_option: bool,
    pub next_is_array: bool,
    pub option_is_array: bool,
    pub next: Vec<Node>,
    pub option: Vec<Node>,
}

impl Node {
    pub fn all_names(&self) -> impl Iterator<Item = &str> {
        std::iter::once(self.name.as_str()).chain(self.aliases.iter().map(|s| s.as_str()))
    }
    fn matches(&self, text: &str) -> bool {
        self.all_names().any(|n| n.eq_ignore_ascii_case(text))
    }
}

/// Completion tree: root subcommands / root options / global options.
#[derive(Debug, Clone, Default)]
pub struct Tree {
    pub next: Vec<Node>,
    pub options: Vec<Node>,
    pub global_options: Vec<Node>,
}

/// The resolved context (for Lua hooks).
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct ResolvedContext {
    pub path: Vec<String>,
    pub pending: Option<PendingInfo>,
    /// All completed options' **canonical** names, in order (symmetrical to `path`).
    pub opts: Vec<String>,
    pub tokens: Vec<TokenInfo>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct TokenInfo {
    pub text: String,
    /// Serialized as `type` (consistent with `.type` access in PowerShell hooks / Lua).
    #[serde(rename = "type")]
    pub kind: String,
    /// Canonical name (alias normalized) of a known command/option; None for unknown/value.
    pub canonical: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct PendingInfo {
    pub text: Option<String>,
    #[serde(rename = "type")]
    pub kind: Option<String>,
    /// Canonical name (best-effort; an unfinished word usually has none).
    pub canonical: Option<String>,
}

/// A generated candidate completion item.
#[derive(Debug, Clone)]
pub struct CompletionItem {
    pub text: String,
    pub tip: Option<String>,
    pub usage: Option<String>,
    pub example: Option<String>,
    pub symbol: Option<String>,
    pub repeat: i32,
}

/// Resolve result: candidates + context.
pub struct Resolved {
    pub items: Vec<CompletionItem>,
    pub context: ResolvedContext,
}

/// Build the completion tree from the manifest JSON.
pub fn build_tree(json: &Value) -> Tree {
    let mut tree = Tree::default();
    if let Some(arr) = json.get("next").and_then(|v| v.as_array()) {
        for n in arr {
            tree.next.push(build_node(n, false));
        }
    }
    if let Some(arr) = json.get("option").and_then(|v| v.as_array()) {
        for n in arr {
            tree.options.push(build_node(n, true));
        }
    }
    if let Some(arr) = json.get("global_option").and_then(|v| v.as_array()) {
        for n in arr {
            tree.global_options.push(build_node(n, true));
        }
    }
    tree
}

/// Convert usage/example array entries (a plain string or a `{ cmd, desc }` object) into display lines:
/// object → `cmd  # desc` (without desc, just `cmd`); strings are returned as-is.
fn text_or_object(v: &Value) -> Option<String> {
    if let Some(s) = v.as_str() {
        return Some(s.to_string());
    }
    if let Some(obj) = v.as_object() {
        let cmd = obj.get("cmd").and_then(|c| c.as_str()).unwrap_or("").trim();
        if cmd.is_empty() {
            return None;
        }
        let desc = obj
            .get("desc")
            .and_then(|d| d.as_str())
            .map(|d| d.trim())
            .filter(|d| !d.is_empty());
        return Some(match desc {
            Some(d) => format!("{cmd}  # {d}"),
            None => cmd.to_string(),
        });
    }
    None
}

fn build_node(json: &Value, is_option: bool) -> Node {
    let name = json
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let aliases = json
        .get("alias")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();
    let tip = json
        .get("tip")
        .and_then(|v| v.as_array())
        .map(|t| {
            t.iter()
                .filter_map(|x| x.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();
    let usage = json
        .get("usage")
        .and_then(|v| v.as_array())
        .map(|t| t.iter().filter_map(text_or_object).collect())
        .unwrap_or_default();
    let example = json
        .get("example")
        .and_then(|v| v.as_array())
        .map(|t| t.iter().filter_map(text_or_object).collect())
        .unwrap_or_default();
    let repeat = json.get("repeat").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let next_is_array = json.get("next").and_then(|v| v.as_array()).is_some();
    let option_is_array = json.get("option").and_then(|v| v.as_array()).is_some();

    let mut next = Vec::new();
    if let Some(arr) = json.get("next").and_then(|v| v.as_array()) {
        for n in arr {
            next.push(build_node(n, false));
        }
    }
    let mut option = Vec::new();
    if let Some(arr) = json.get("option").and_then(|v| v.as_array()) {
        for n in arr {
            option.push(build_node(n, true));
        }
    }
    Node {
        name,
        aliases,
        tip,
        usage,
        example,
        repeat,
        is_option,
        next_is_array,
        option_is_array,
        next,
        option,
    }
}

/// Whether the node carries static candidates (a non-empty `next`/`option` array).
/// An empty array means "no static candidates" (hooks supply them), so there is nothing to
/// switch into.
fn has_static_candidates(n: &Node) -> bool {
    (n.next_is_array && !n.next.is_empty()) || (n.option_is_array && !n.option.is_empty())
}

fn node_symbols(n: &Node) -> Vec<String> {
    let mut s = Vec::new();
    // A non-empty candidate array (next or option) switches context.
    // An EMPTY array carries no static candidates → no automatic switch.
    if has_static_candidates(n) {
        s.push("switch".into());
    } else if n.is_option {
        s.push("stay".into());
    }
    s
}

fn node_has_candidates_after(n: &Node) -> bool {
    has_static_candidates(n)
}

/// Nearest ancestor (or root) with a non-empty `option` array.
fn option_source<'a>(stack: &[&'a Node], tree: &'a Tree) -> &'a [Node] {
    for node in stack.iter().rev() {
        if !node.option.is_empty() {
            return &node.option;
        }
    }
    &tree.options
}

/// Look up an option node in the bubbled options + global options.
fn find_option_node<'a>(stack: &[&'a Node], tree: &'a Tree, text: &str) -> Option<&'a Node> {
    if let Some(n) = option_source(stack, tree).iter().find(|n| n.matches(text)) {
        return Some(n);
    }
    tree.global_options.iter().find(|n| n.matches(text))
}

/// Resolve: given the arg tokens (excluding the command name), return candidates + context.
pub fn resolve(tree: &Tree, arg_tokens: &[String], treat_last_as_complete: bool) -> Resolved {
    let mut used: HashMap<String, i32> = HashMap::new();
    let mut tokens: Vec<TokenInfo> = Vec::new();
    let mut path: Vec<String> = Vec::new();
    let mut opts: Vec<String> = Vec::new();
    let mut pending: Option<PendingInfo> = None;
    let mut ctx: Option<&Node> = None;
    let mut stack: Vec<&Node> = Vec::new();

    let count = arg_tokens.len();
    let last_index = count.saturating_sub(1);
    let mut i = 0;
    while i < count {
        let text = arg_tokens[i].clone();
        let is_last_unfinished = i == last_index && !treat_last_as_complete;
        if is_last_unfinished {
            let kind = classify(ctx, &stack, tree, &text);
            pending = Some(PendingInfo {
                text: Some(text.clone()),
                kind: Some(kind.to_string()),
                // An unfinished word usually has no canonical name (it does not fully match
                // a command/option yet); `current.name` is best-effort and often nil.
                canonical: None,
            });
            break;
        }
        // Option
        let opt_node = find_option_node(&stack, tree, &text);
        if let Some(on) = opt_node {
            opts.push(on.name.clone());
            bump(&mut used, &on.name);
            tokens.push(TokenInfo {
                text: text.clone(),
                kind: "option".into(),
                canonical: Some(on.name.clone()),
            });
            if node_has_candidates_after(on) {
                ctx = Some(on);
                stack.push(on);
            }
        } else {
            // A command or unknown; in an option context (candidate-value array) the match is a value
            let child = find_command(ctx, tree, &text);
            if let Some(cn) = child {
                bump(&mut used, &cn.name);
                let is_option_value = ctx.map(|c| c.is_option).unwrap_or(false);
                if !is_option_value {
                    path.push(cn.name.clone());
                }
                tokens.push(TokenInfo {
                    text: text.clone(),
                    kind: if is_option_value { "value" } else { "command" }.into(),
                    canonical: Some(cn.name.clone()),
                });
                ctx = Some(cn);
                stack.push(cn);
            } else {
                tokens.push(TokenInfo {
                    text: text.clone(),
                    kind: "unknown".into(),
                    canonical: None,
                });
            }
        }
        i += 1;
    }

    // Command tokens typed so far (only commands consume a static subcommand's candidate slot).
    // `seen` (raw typed texts, matched against name+alias below) and `used` (canonical
    // lowercased) are two parallel bookkeepings of the same repeat concept: `seen` filters
    // the context's own candidate list, `used` re-checks at assembly time — which also covers
    // pending-pushed candidates that bypassed `add_next_if_not_seen`. Keep both in sync.
    let mut seen: Vec<String> = tokens
        .iter()
        .filter(|t| t.kind == "command")
        .map(|t| t.text.clone())
        .collect();
    if let Some(p) = &pending {
        if p.kind.as_deref() == Some("command") {
            if let Some(t) = &p.text {
                if !t.is_empty() {
                    seen.push(t.clone());
                }
            }
        }
    }
    let mut candidates: Vec<&Node> = Vec::new();
    let ctx_is_root = ctx.is_none();
    if ctx_is_root {
        add_next_if_not_seen(&mut candidates, &tree.next, &seen);
        for n in &tree.options {
            candidates.push(n);
        }
    } else if let Some(c) = ctx {
        add_next_if_not_seen(&mut candidates, &c.next, &seen);
        for n in option_source(&stack, tree) {
            candidates.push(n);
        }
    }
    for n in &tree.global_options {
        candidates.push(n);
    }

    // A pending word that matches a known subcommand is itself offered as a candidate
    if let Some(p) = &pending {
        if let Some(t) = &p.text {
            let matched = find_command(ctx, tree, t);
            if let Some(mn) = matched {
                // Skip when already offered from the context's own list (e.g. an option
                // candidate-value layer), so the item never appears twice.
                if used.get(&mn.name.to_lowercase()).copied().unwrap_or(0) == 0
                    && !candidates.iter().any(|c| std::ptr::eq(*c, mn))
                {
                    candidates.push(mn);
                }
            }
        }
    }

    // Assemble items (repeat limits + name/alias expansion)
    let mut items: Vec<CompletionItem> = Vec::new();
    for n in &candidates {
        let used_count = used.get(&n.name.to_lowercase()).copied().unwrap_or(0);
        if n.repeat == 0 && used_count > 0 {
            continue;
        }
        if n.repeat > 0 && used_count >= n.repeat {
            continue;
        }
        for name in n.all_names() {
            items.push(CompletionItem {
                text: name.to_string(),
                tip: if n.tip.is_empty() {
                    None
                } else {
                    Some(n.tip.join("\n"))
                },
                usage: if n.usage.is_empty() {
                    None
                } else {
                    Some(n.usage.join("\n"))
                },
                example: if n.example.is_empty() {
                    None
                } else {
                    Some(n.example.join("\n"))
                },
                symbol: node_symbols(n).first().cloned(),
                repeat: n.repeat,
            });
        }
    }

    Resolved {
        items,
        context: ResolvedContext {
            path,
            pending,
            opts,
            tokens,
        },
    }
}

fn classify<'a>(
    ctx: Option<&'a Node>,
    stack: &[&'a Node],
    tree: &'a Tree,
    text: &str,
) -> &'static str {
    if find_option_node(stack, tree, text).is_some() {
        "option"
    } else if find_command(ctx, tree, text).is_some() {
        // Current context is an option node → the match is one of its candidate values (a value)
        if ctx.map(|c| c.is_option).unwrap_or(false) {
            "value"
        } else {
            "command"
        }
    } else {
        "unknown"
    }
}

fn find_command<'a>(ctx: Option<&'a Node>, tree: &'a Tree, text: &str) -> Option<&'a Node> {
    if let Some(c) = ctx {
        c.next.iter().find(|n| n.matches(text))
    } else {
        tree.next.iter().find(|n| n.matches(text))
    }
}

fn bump(used: &mut HashMap<String, i32>, name: &str) {
    *used.entry(name.to_lowercase()).or_insert(0) += 1;
}

fn add_next_if_not_seen<'a>(out: &mut Vec<&'a Node>, items: &'a [Node], seen: &[String]) {
    for n in items {
        // Uses of this node: the canonical name plus every alias, all counting as the main
        // name. `repeat` (not just presence in `seen`) decides whether it is still offered:
        // a `repeat: 2` command survives its first use, matching the assembly-phase rule.
        let used = seen
            .iter()
            .filter(|s| {
                s.eq_ignore_ascii_case(&n.name)
                    || n.aliases.iter().any(|a| a.eq_ignore_ascii_case(s))
            })
            .count() as i32;
        let exhausted = if n.repeat == 0 {
            used > 0
        } else {
            used >= n.repeat
        };
        if exhausted {
            continue;
        }
        out.push(n);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn git_tree() -> Tree {
        let path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../completions/git/language/en-US.json"
        );
        let text = std::fs::read_to_string(path).unwrap();
        let json: Value = serde_json::from_str(&text).unwrap();
        build_tree(&json)
    }

    #[test]
    fn quoted_pending_value_keeps_text() {
        // psc config menu show_mode "fu<TAB>: an unterminated-quote value is the pending (pre-fills filter)
        let json = serde_json::json!({
            "next": [
                {"name": "config", "next": [
                    {"name": "menu", "next": [
                        {"name": "show_mode", "next": [{"name": "\"auto\""}]}
                    ]}
                ]}
            ]
        });
        let tree = build_tree(&json);
        let r = resolve(
            &tree,
            &[
                "config".into(),
                "menu".into(),
                "show_mode".into(),
                "\"fu".into(),
            ],
            false,
        );
        assert_eq!(
            r.context.pending.as_ref().and_then(|p| p.text.as_deref()),
            Some("\"fu")
        );
    }

    #[test]
    fn builds_tree_from_manifest() {
        let tree = git_tree();
        assert!(tree.next.len() > 20, "git has many subcommands");
        assert!(tree.global_options.iter().any(|n| n.name == "--help"));
    }

    #[test]
    fn pending_ignored_for_generation_returns_full_candidates() {
        let tree = git_tree();
        let r = resolve(&tree, &["stash".to_string()], false);
        assert_eq!(
            r.context.pending.as_ref().and_then(|p| p.text.clone()),
            Some("stash".into())
        );
        assert!(r.context.path.is_empty()); // pending not confirmed, so path is empty
                                            // Generation ignores pending: return the full candidate set
        assert!(r.items.iter().any(|i| i.text == "stash")); // the known subcommand itself stays in the candidates
        assert!(r.items.iter().any(|i| i.text == "add")); // subcommands not starting with stash are kept too
        assert!(r.items.len() > 10);
    }

    #[test]
    fn pending_excluded_from_tokens() {
        let tree = git_tree();
        // git checkout ma<TAB>: ma is the unfinished token; tokens holds only completed ones (PS $tokens)
        let r = resolve(&tree, &["checkout".to_string(), "ma".to_string()], false);
        assert_eq!(r.context.tokens.len(), 1);
        assert_eq!(r.context.tokens[0].text, "checkout");
        assert_eq!(
            r.context.pending.as_ref().and_then(|p| p.text.clone()),
            Some("ma".into())
        );
        // Fully typed input (trailing space) has no pending
        let r2 = resolve(&tree, &["checkout".to_string(), "ma".to_string()], true);
        assert_eq!(r2.context.tokens.len(), 2);
        assert!(r2.context.pending.is_none());
    }

    #[test]
    fn tokens_keep_original_case_opts_are_canonical() {
        let tree = git_tree();
        // Parsing is case-insensitive; token input keeps the user's original casing, while
        // `path`/`opts` store canonical names (hooks compare with psc.eq / psc.contains).
        // `-B` matches checkout's `-b` (case-insensitive) → opts holds the canonical `-b`.
        let r = resolve(&tree, &["CHECKOUT".to_string(), "-B".to_string()], true);
        assert_eq!(r.context.path, vec!["checkout"]);
        assert_eq!(r.context.opts, vec!["-b"]);
        assert_eq!(r.context.tokens[0].text, "CHECKOUT");
        assert_eq!(r.context.tokens[1].text, "-B");
    }

    #[test]
    fn completed_subcommand_moves_context() {
        let tree = git_tree();
        let r = resolve(&tree, &["checkout".to_string()], true);
        assert_eq!(r.context.path, vec!["checkout"]);
        assert!(r.context.pending.is_none());
        // checkout's candidates (options, etc.) are non-empty
        assert!(!r.items.is_empty());
    }

    #[test]
    fn deep_path_and_option_value() {
        let tree = git_tree();
        let r = resolve(&tree, &["stash".to_string(), "pop".to_string()], true);
        assert_eq!(r.context.path, vec!["stash", "pop"]);
        assert!(r.context.pending.is_none());
        assert!(!r.items.is_empty());
        // option value: git branch -m → opts = ["--move"] (canonical of alias -m)
        let r2 = resolve(&tree, &["branch".to_string(), "-m".to_string()], true);
        assert_eq!(r2.context.opts, vec!["--move"]);
    }

    #[test]
    fn options_do_not_enter_the_command_path() {
        // `psc.cmds` contains only commands; a leading/interspersed option never lands in it.
        // `yarn --x remove` → cmds[1] is "remove" (not "--x"), and --x lands in opts.
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [
                { "name": "remove", "option": [
                    { "name": "--x" }
                ] }
            ],
            "option": [
                { "name": "--y" }
            ]
        }));
        let r = resolve(
            &tree,
            &["--y".to_string(), "remove".to_string(), "--x".to_string()],
            true,
        );
        assert_eq!(r.context.path, vec!["remove"]);
        assert_eq!(r.context.opts, vec!["--y", "--x"]);
        assert_eq!(
            r.context
                .tokens
                .iter()
                .map(|t| t.kind.as_str())
                .collect::<Vec<_>>(),
            vec!["option", "command", "option"]
        );
    }

    #[test]
    fn option_candidate_value_is_not_a_command() {
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [
                { "name": "commit", "option": [
                    { "name": "--format", "next": [ { "name": "json" }, { "name": "yaml" } ] }
                ] }
            ]
        }));
        // Completed: the candidate value json is a value token, not a path entry (path holds subcommands)
        let r = resolve(
            &tree,
            &["commit".into(), "--format".into(), "json".into()],
            true,
        );
        assert_eq!(
            r.context.path,
            vec!["commit"],
            "candidate value must not enter path: {:?}",
            r.context.path
        );
        assert_eq!(r.context.tokens.last().unwrap().kind.as_str(), "value");
        // Unfinished: git commit --format json<TAB> → pending kind is value
        let r2 = resolve(
            &tree,
            &["commit".into(), "--format".into(), "json".into()],
            false,
        );
        assert_eq!(
            r2.context.pending.as_ref().unwrap().kind.as_deref(),
            Some("value")
        );
    }

    #[test]
    fn subcommand_unknown_value_keeps_options_available() {
        // `git add xxx <TAB>`: xxx is an unrecognized word (unknown). The context stays on
        // `add`, so add's options (--all, --dry-run, ...) remain completable — an unknown
        // value does NOT break access to the command's options.
        let tree = git_tree();
        let r = resolve(&tree, &["add".into(), "xxx".into()], true);
        assert_eq!(r.context.path, vec!["add"]);
        assert_eq!(
            r.context.tokens.last().unwrap().kind.as_str(),
            "unknown",
            "xxx is an unrecognized word at the command position"
        );
        assert!(
            r.items.iter().any(|i| i.text == "--all"),
            "add's options must remain available: {:?}",
            r.items.iter().map(|i| i.text.clone()).collect::<Vec<_>>()
        );
    }

    #[test]
    fn option_unknown_value_keeps_owner_context() {
        // If an option's value is classified as unknown (not value), can a subcommand or
        // another option still follow it? Verify the context stays on the option's owner.
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [ { "name": "commit", "option": [
                { "name": "--format", "next": [ { "name": "json" } ] },
                { "name": "--amend" }
            ] } ],
            "option": [ { "name": "--verbose" } ]
        }));
        // commit --format custom <TAB>: custom is out-of-list (unknown). The context stays
        // on commit, so commit's own options remain reachable.
        let r = resolve(
            &tree,
            &["commit".into(), "--format".into(), "custom".into()],
            true,
        );
        assert_eq!(r.context.path, vec!["commit"]);
        assert!(
            r.items.iter().any(|i| i.text == "--amend"),
            "--amend should be reachable after the value: {:?}",
            r.items.iter().map(|i| i.text.clone()).collect::<Vec<_>>()
        );
    }

    #[test]
    fn option_empty_next_keeps_followup_completion() {
        // An option with `next: []` (no static candidates) takes a free value: after
        // `-x aaa`, the value is an unknown word and the subcommands stay reachable.
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [ { "name": "commit" }, { "name": "branch" } ],
            "option": [ { "name": "-x", "next": [] } ]
        }));
        let r = resolve(&tree, &["-x".into(), "aaa".into()], true);
        assert_eq!(
            r.context.tokens[1].kind, "unknown",
            "free value of an empty-next option is an unknown word: {:?}",
            r.context.tokens
        );
        assert!(r.items.iter().any(|i| i.text == "commit"));
        assert!(r.items.iter().any(|i| i.text == "branch"));
    }

    #[test]
    fn option_nested_option_behavior() {
        // An option with its own `option` array (sub-options). After selecting --a, do the
        // sub-options --x/--y become reachable? Does the nesting work end-to-end?
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [ { "name": "sub" } ],
            "option": [ { "name": "--a", "option": [ { "name": "--x" }, { "name": "--y" } ] } ]
        }));
        // --a selected: its sub-options should be the candidates
        let r = resolve(&tree, &["--a".into()], true);
        assert!(
            r.items.iter().any(|i| i.text == "--x"),
            "sub-option --x reachable"
        );
        assert!(
            r.items.iter().any(|i| i.text == "--y"),
            "sub-option --y reachable"
        );
        // Then select --x: it should be recorded as an option
        let r2 = resolve(&tree, &["--a".into(), "--x".into()], true);
        assert_eq!(r2.context.opts, vec!["--a", "--x"]);
        assert_eq!(r2.context.tokens.last().unwrap().kind.as_str(), "option");
    }

    #[test]
    fn option_array_consumes_out_of_list_value() {
        // `next: [...]` also carries "a value is consumed" semantics: typing a value that
        // is NOT one of the candidates is still consumed as the option's value (not left
        // as an unrelated unknown that could confuse later completion).
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [ { "name": "commit", "option": [
                { "name": "--format", "next": [ { "name": "json" }, { "name": "yaml" } ] }
            ] } ]
        }));
        // custom is not a candidate of --format → it is a static-unrecognized word (unknown).
        // The context stays on commit (--format's owner), so subcommands/options remain reachable.
        let r = resolve(
            &tree,
            &["commit".into(), "--format".into(), "custom".into()],
            true,
        );
        assert_eq!(r.context.path, vec!["commit"]);
        assert_eq!(
            r.context.tokens.last().unwrap().kind.as_str(),
            "unknown",
            "out-of-list value is unknown (not static-recognized): {:?}",
            r.context.tokens
        );
        assert_eq!(
            r.context.tokens.last().unwrap().text,
            "custom",
            "value text should be the typed word"
        );
    }

    #[test]
    fn option_free_value_matching_subcommand_switches_context() {
        // Collision rule: after a free-form-value option (`next: []`), a token that matches
        // a subcommand name is classified as a command — the engine has no arity info, and
        // "command wins" keeps `option … command` sequences working. So `--a add` switches
        // into add's context (path records it) instead of treating `add` as the option's value.
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [ { "name": "add", "next": [ { "name": "sub1" } ] }, { "name": "list" } ],
            "option": [ { "name": "--a", "next": [] } ]
        }));
        let r = resolve(&tree, &["--a".into(), "add".into()], true);
        assert_eq!(r.context.path, vec!["add"]);
        assert_eq!(
            r.context.tokens.last().unwrap().kind.as_str(),
            "command",
            "colliding token is a command, not a value: {:?}",
            r.context.tokens
        );
        // The menu now offers add's own candidates, not the root list.
        assert!(r.items.iter().any(|i| i.text == "sub1"));
        assert!(!r.items.iter().any(|i| i.text == "list"));
    }

    #[test]
    fn option_empty_next_value_keeps_subcommands_completable() {
        // `psc --a bbb <Tab>`: bbb is --a's free value (an unknown word), so the
        // subcommands (add/list) remain completable at the root level.
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [ { "name": "add" }, { "name": "list" } ],
            "option": [ { "name": "--a", "next": [] } ]
        }));
        let r = resolve(&tree, &["--a".into(), "bbb".into()], true);
        assert_eq!(
            r.context.path,
            Vec::<String>::new(),
            "value must not enter path"
        );
        assert_eq!(r.context.opts, vec!["--a"]);
        assert_eq!(
            r.context.tokens.last().unwrap().kind.as_str(),
            "unknown",
            "bbb is --a's free value (unknown), not a command: {:?}",
            r.context.tokens
        );
        // The root candidates still include the subcommands — the value must not clear them.
        assert_eq!(
            r.context
                .tokens
                .iter()
                .filter(|t| t.kind == "command")
                .count(),
            0
        );
        assert!(r.items.iter().any(|i| i.text == "add"));
        assert!(r.items.iter().any(|i| i.text == "list"));
        // Unfinished value: psc --a bb<TAB> → pending kind is unknown
        let r2 = resolve(&tree, &["--a".into(), "bb".into()], false);
        assert_eq!(
            r2.context.pending.as_ref().unwrap().kind.as_deref(),
            Some("unknown")
        );
    }

    #[test]
    fn option_empty_next_position_with_option_like_token() {
        // `psc --a --b`: an empty-next option never consumes a following option. A
        // recognized option after it becomes its own option, so its own candidates
        // (its next) remain reachable.
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [ { "name": "add" } ],
            "option": [
                { "name": "--a", "next": [] },
                { "name": "--b", "next": [ { "name": "val1" }, { "name": "val2" } ] }
            ]
        }));
        let r = resolve(&tree, &["--a".into(), "--b".into()], true);
        assert_eq!(r.context.opts, vec!["--a", "--b"]);
        assert_eq!(
            r.context.tokens.last().unwrap().kind.as_str(),
            "option",
            "--b must be classified as an option, not consumed as --a's value: {:?}",
            r.context.tokens
        );
        // --b has a candidate array (its next) → its context is entered, candidates reachable
        assert!(r.items.iter().any(|i| i.text == "val1"));
        assert!(r.items.iter().any(|i| i.text == "val2"));
    }

    #[test]
    fn symbols_and_aliases_expanded() {
        let tree = git_tree();
        let r = resolve(&tree, &["stash".to_string(), "pop".to_string()], true);
        // stash pop's candidates should include alias expansion and symbols
        let some_symbol = r.items.iter().any(|i| i.symbol.is_some());
        assert!(some_symbol);
    }

    #[test]
    fn option_bubbles_up_ancestors_then_falls_back_to_root() {
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [
                { "name": "config", "option": [
                    { "name": "--config-reset" }
                ], "next": [
                    { "name": "menu", "next": [
                        { "name": "key" }
                    ] }
                ] },
                { "name": "plain" }
            ],
            "option": [
                { "name": "--root-opt" }
            ]
        }));
        // Root: root options
        let r = resolve(&tree, &[], true);
        assert!(r.items.iter().any(|i| i.text == "--root-opt"));
        assert!(!r.items.iter().any(|i| i.text == "--config-reset"));
        // A subcommand with its own option → uses its own
        let r = resolve(&tree, &["config".into()], true);
        assert!(r.items.iter().any(|i| i.text == "--config-reset"));
        assert!(!r.items.iter().any(|i| i.text == "--root-opt"));
        // Deeper: menu has no option → bubbles to config
        let r = resolve(&tree, &["config".into(), "menu".into()], true);
        assert!(r.items.iter().any(|i| i.text == "--config-reset"));
        assert!(!r.items.iter().any(|i| i.text == "--root-opt"));
        // Even deeper: key has no option → keeps bubbling to config
        let r = resolve(&tree, &["config".into(), "menu".into(), "key".into()], true);
        assert!(r.items.iter().any(|i| i.text == "--config-reset"));
        assert!(!r.items.iter().any(|i| i.text == "--root-opt"));
        // No option anywhere up the chain → fall back to root options
        let r = resolve(&tree, &["plain".into()], true);
        assert!(r.items.iter().any(|i| i.text == "--root-opt"));
    }

    #[test]
    fn text_or_object_renders_cmd_and_desc() {
        use serde_json::json;
        // Plain string passes through as-is
        assert_eq!(
            text_or_object(&json!("-f, --force")),
            Some("-f, --force".into())
        );
        // Object → cmd  # desc
        assert_eq!(
            text_or_object(
                &json!({ "cmd": "d demo.zip *.bak -r", "desc": "delete all .bak files" })
            ),
            Some("d demo.zip *.bak -r  # delete all .bak files".into())
        );
        // Object without desc → only cmd
        assert_eq!(
            text_or_object(&json!({ "cmd": "x demo.7z" })),
            Some("x demo.7z".into())
        );
        // cmd empty/missing → None
        assert_eq!(text_or_object(&json!({ "desc": "only desc" })), None);
        assert_eq!(text_or_object(&json!(123)), None);
    }

    #[test]
    fn option_empty_next_array_behavior() {
        // An option with `next: []` (empty) has NO static candidates. Selecting it does NOT
        // switch context and carries no automatic switch symbol — hooks supply dynamic items
        // and set the symbol via `psc.set_symbol`. A following value is a plain unknown word.
        use serde_json::json;
        let tree = build_tree(&json!({
            "next": [ { "name": "add" } ],
            "option": [ { "name": "--a", "next": [] } ]
        }));
        // --a selected: no static candidates → no context switch, value is unknown
        let r = resolve(&tree, &["--a".into(), "bbb".into()], true);
        assert_eq!(r.context.path, Vec::<String>::new());
        assert_eq!(r.context.opts, vec!["--a"]);
        assert_eq!(
            r.context.tokens.last().unwrap().kind.as_str(),
            "unknown",
            "empty-next value is an unknown word: {:?}",
            r.context.tokens
        );
        // The root subcommands remain reachable (no context switch to an empty layer)
        assert!(r.items.iter().any(|i| i.text == "add"));
        // Symbol: empty array carries no automatic switch (hooks decide)
        let r2 = resolve(&tree, &[], true);
        let a_item = r2
            .items
            .iter()
            .find(|i| i.text == "--a")
            .expect("--a is a candidate at the root");
        assert_ne!(
            a_item.symbol.as_deref(),
            Some("switch"),
            "empty-next: no auto switch"
        );
    }
}
