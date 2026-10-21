//! `info` template rendering: the `{{…}}` mini-language that turns the `psc` completion's `info` strings into display text.
//!
//! The grammar follows the widespread conventions rather than inventing its own: Mustache/Handlebars blocks (`{{#each}}…{{/each}}`, same-name closes, `{{else}}`, `{{!
//! comment}}`, `{{> partial}}`, `\{{` for a literal brace), Jinja/Liquid value pipelines (`{{a.b|filter}}`, `or` for the first present value), and Handlebars' lowercase `@`-names for what the renderer itself provides.
//!
//! It stays small on purpose — the templates are hand-edited data (`completions/psc/language/*.json`), so every rule is total (nothing panics, an unknown construct re-emits its token) and `tests/fixtures/psc_tpl.json` freezes the rendering of every template that ships.
//! Anything display text does not need — arithmetic, comparisons, inheritance — is deliberately absent.

use serde_json::Value;

use crate::output::{value_quoted, value_text};

/// Render `data` — an `info.<path>` value: a list of lines joined with `separator`, or a plain string — with `ctx`, the caller's data (`Version`, `NewVersion`, records, counts, …).
pub fn render(data: &Value, ctx: &Value, separator: &str) -> String {
    render_with_root(data, ctx, separator, None)
}

/// Like [`render`], with `root` (the whole `info` object) available to `{{> path}}` includes.
pub fn render_with_root(
    data: &Value,
    ctx: &Value,
    separator: &str,
    root: Option<&Value>,
) -> String {
    render_notes(data, ctx, separator, root).0
}

/// Render, and also report what the renderer did with each name and token.
pub fn explain_with_root(
    data: &Value,
    ctx: &Value,
    separator: &str,
    root: Option<&Value>,
) -> (String, Vec<String>) {
    render_notes(data, ctx, separator, root)
}

fn render_notes(
    data: &Value,
    ctx: &Value,
    separator: &str,
    root: Option<&Value>,
) -> (String, Vec<String>) {
    let text = match data {
        Value::Array(lines) => lines
            .iter()
            .map(value_text)
            .collect::<Vec<_>>()
            .join(separator),
        other => value_text(other),
    };
    if !text.contains("{{") {
        return (text, Vec::new());
    }
    let mut state = State {
        more: 0,
        root,
        depth: 0,
        notes: Vec::new(),
    };
    let mut ctx = ctx.clone();
    let out = render_tokens(&tokenize(&text), &mut ctx, None, &mut state);
    (out, state.notes)
}

/// Record one lookup for `--explain`, once per (path, outcome).
fn note(state: &mut State, path: &str, outcome: &str) {
    let line = format!("{path} — {outcome}");
    if !state.notes.contains(&line) {
        state.notes.push(line);
    }
}

/// What the renderer keeps for the templates: the `@`-namespace, plus the include machinery.
struct State<'a> {
    /// The `@more` count: items a capped `#each` left out.
    /// It survives the loop, which is what the "+N more" tail after a `#each` reads.
    more: usize,
    root: Option<&'a Value>,
    depth: usize,
    /// What `psc tpl --explain` reports: every name the renderer resolved or missed, and every token it had to keep verbatim.
    /// A normal render fills it too — a string per lookup is not worth a branch — and simply drops it.
    notes: Vec<String>,
}

/// How deep `{{> path}}` may nest before the renderer gives up and re-emits the token.
const MAX_INCLUDE_DEPTH: usize = 8;

/// A path the renderer accepts as a lookup; anything else re-emits its token verbatim.
///
/// `-` belongs here because the data uses it (`scoop-checkver`, `last-check`): a path that cannot name a key is a silent no-op, which is the one failure mode a total renderer must avoid.
fn is_path(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_alphanumeric() || c == '_' || c == '-' || c == '.' || c == '@')
}

/// A filter name (the segment after `|`).
fn is_filter(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_alphanumeric() || c == '_' || c == '-')
}

/// The filters the renderer knows.
/// An unknown one re-emits its token, so a typo is visible.
fn filter(name: &str, value: Value) -> Option<String> {
    match name {
        "quote" => Some(value_quoted(&value)),
        _ => None,
    }
}

/// A dotted lookup's outcome.
enum Look {
    Found(Value),
    /// Missing: `{{a or b}}` moves on to the next alternative, `{{a}}` renders empty.
    Missing,
    /// The token is not an expression (or a `.` with no current item): re-emit it verbatim.
    Literal,
}

/// Walk `path` from the current `#each` item (leading `.`), from the engine's `@`-namespace, or from `ctx`.
fn lookup(path: &str, ctx: &Value, item: Option<&Value>, state: &mut State) -> Look {
    let out = lookup_inner(path, ctx, item, state);
    match &out {
        Look::Found(_) => note(state, path, "resolved"),
        Look::Missing => note(state, path, "unresolved"),
        // A verbatim token is reported where it is emitted, with the whole token.
        Look::Literal => {}
    }
    out
}

fn lookup_inner(path: &str, ctx: &Value, item: Option<&Value>, state: &State) -> Look {
    let parts: Vec<&str> = path.split('.').collect();
    let first = parts[0];
    let (mut cur, rest): (Option<&Value>, &[&str]) = if first.is_empty() {
        match item {
            Some(it) => (Some(it), &parts[1..]),
            None => return Look::Literal,
        }
    } else if let Some(name) = first.strip_prefix('@') {
        // The `@`-namespace is the renderer's own: it never mixes with the caller's data, so a host may use `Rest`/`More`/`Index` as data keys without colliding with the engine.
        match name {
            "more" => return Look::Found(Value::from(state.more)),
            _ => return Look::Literal,
        }
    } else {
        (Some(ctx), &parts[..])
    };
    for p in rest {
        if p.is_empty() {
            continue;
        }
        let Some(v) = cur else { return Look::Missing };
        cur = match v {
            Value::Object(o) => o.get(*p),
            Value::Array(a) => p.parse::<usize>().ok().and_then(|i| a.get(i)),
            _ => return Look::Missing,
        };
        if cur.is_none() {
            return Look::Missing;
        }
    }
    match cur {
        Some(v) => Look::Found(v.clone()),
        None => Look::Missing,
    }
}

/// Resolve one `{{…}}` expression — `a or b`, each alternative optionally piped through filters — into its text.
/// `None` means "not an expression, re-emit the token".
fn resolve(expr: &str, ctx: &Value, item: Option<&Value>, state: &mut State) -> Option<String> {
    for alt in split_or(expr) {
        // `path|filter|filter`: the value is looked up first, the filters then run left to right.
        let mut steps = alt.split('|').map(str::trim);
        let Some(path) = steps.next() else { continue };
        let filters: Vec<&str> = steps.collect();
        if !is_path(path) || !filters.iter().all(|f| is_filter(f)) {
            return None;
        }
        let value = match lookup(path, ctx, item, state) {
            Look::Literal => return None,
            Look::Missing => continue,
            Look::Found(v) => {
                // A `null` or empty string is "not there"; `false` and `0` are values.
                let blank = v.is_null() || matches!(&v, Value::String(s) if s.is_empty());
                if blank {
                    continue;
                }
                v
            }
        };
        let value = match value {
            Value::Bool(b) => Value::from(if b { 1 } else { 0 }),
            other => other,
        };
        if filters.is_empty() {
            return Some(value_text(&value));
        }
        let mut text = value_text(&value);
        for f in filters {
            text = filter(f, Value::String(text))?;
        }
        return Some(text);
    }
    Some(String::new())
}

/// `a or b or c` — the alternatives, trimmed.
/// Spaces are required around `or`, so a path may still contain the letters (`order`).
fn split_or(expr: &str) -> Vec<&str> {
    expr.split(" or ").map(str::trim).collect()
}

/// Truthiness: non-null, non-zero, non-empty, non-empty list — the same set every mainstream engine treats as falsey.
fn truthy(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64().is_some_and(|f| f != 0.0),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

/// One template token: literal text, or a trimmed `{{…}}` expression.
enum Tok {
    Text(String),
    Tag(String),
}

/// Split on `{{…}}` (non-greedy: the first `}}` closes a token).
/// `\{{` is a literal `{{` and drops the backslash.
fn tokenize(text: &str) -> Vec<Tok> {
    let mut out = Vec::new();
    let mut pos = 0;
    while let Some(rel) = text[pos..].find("{{") {
        let start = pos + rel;
        let Some(rel_end) = text[start + 2..].find("}}") else {
            break;
        };
        if start > 0 && text.as_bytes()[start - 1] == b'\\' {
            out.push(Tok::Text(text[pos..start - 1].to_string()));
            out.push(Tok::Text("{{".to_string()));
            pos = start + 2;
            continue;
        }
        if start > pos {
            out.push(Tok::Text(text[pos..start].to_string()));
        }
        out.push(Tok::Tag(
            text[start + 2..start + 2 + rel_end].trim().to_string(),
        ));
        pos = start + 2 + rel_end + 2;
    }
    out.push(Tok::Text(text[pos..].to_string()));
    out
}

/// A block's boundaries: `{{#each}}…{{else}}…{{/each}}` alike.
struct Block {
    /// The spec text after the directive word.
    spec: String,
    /// The directive word without the `#` (`each`, `if`, `unless`).
    kind: String,
    body: (usize, usize),
    alt: Option<(usize, usize)>,
    next: usize,
}

/// The block directives that carry a matching `/name` close.
const BLOCK_OPENERS: [&str; 3] = ["each", "if", "unless"];

fn take_block(toks: &[Tok], i: usize) -> Block {
    let tag = match &toks[i] {
        Tok::Tag(t) => t.clone(),
        Tok::Text(t) => t.clone(),
    };
    let rest = tag.trim_start_matches('#');
    let (kind, spec) = match rest.split_once(char::is_whitespace) {
        Some((k, s)) => (k.to_string(), s.trim().to_string()),
        None => (rest.to_string(), String::new()),
    };
    let mut body = (i + 1, i + 1);
    let mut alt: Option<(usize, usize)> = None;
    let mut depth = 0usize;
    let mut j = i + 1;
    while j < toks.len() {
        if let Tok::Tag(t) = &toks[j] {
            if BLOCK_OPENERS
                .iter()
                .any(|k| t.starts_with(&format!("#{k} ")) || t == &format!("#{k}"))
            {
                depth += 1;
            }
            if BLOCK_OPENERS.iter().any(|k| t == &format!("/{k}")) {
                if depth == 0 {
                    break;
                }
                depth -= 1;
            }
            if t == "else" && depth == 0 {
                body.1 = j;
                alt = Some((j + 1, 0));
                j += 1;
                continue;
            }
        }
        j += 1;
    }
    match &mut alt {
        Some(a) => a.1 = j,
        None => body.1 = j,
    }
    Block {
        spec,
        kind,
        body,
        alt,
        next: j + 1,
    }
}

/// Split `path [limit=N] [sep='…']` into its parameters, keeping a single-quoted run whole: a separator may hold whitespace of any kind (`sep=' '`, `sep='\n\n'`), and splitting on whitespace would flatten it to spaces.
fn split_spec(rest: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    let mut cur = String::new();
    let mut quoted = false;
    for c in rest.chars() {
        if c == '\'' {
            quoted = !quoted;
            cur.push(c);
        } else if c.is_whitespace() && !quoted {
            if !cur.is_empty() {
                out.push(std::mem::take(&mut cur));
            }
        } else {
            cur.push(c);
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}

/// `path [limit=N] [sep='…']` — whitespace-separated parameters, so a separator may contain a space (`sep=' '`) or a newline.
/// `None` when the spec cannot be read as one (an empty path, or a `|` filter): the caller then keeps the whole block verbatim (templates.md: a spec that is not a path renders literally, never silently dropped).
fn parse_each(spec: &str) -> Option<(String, Option<usize>, Option<String>)> {
    let mut chars = spec.chars().peekable();
    let mut path = String::new();
    while let Some(&c) = chars.peek() {
        if c.is_whitespace() {
            break;
        }
        path.push(c);
        chars.next();
    }
    let mut limit = None;
    let mut sep = None;
    let rest: String = chars.collect();
    for tok in split_spec(&rest) {
        if let Some(v) = tok.strip_prefix("limit=") {
            limit = v.parse::<usize>().ok();
        } else if let Some(v) = tok.strip_prefix("sep=") {
            if let Some(inner) = v.strip_prefix('\'') {
                sep = Some(inner.trim_end_matches('\'').to_string());
            } else {
                sep = Some(v.to_string());
            }
        }
    }
    if path.is_empty() || path.contains('|') {
        return None;
    }
    Some((path, limit, sep))
}

/// The source text of a block from its opening token to its close, for a directive the renderer cannot evaluate.
/// Reconstructed from the tokens: `tokenize` loses nothing, and a tag's surrounding whitespace is already trimmed by the same rule that trims every expression.
fn block_source(toks: &[Tok], open: usize, b: &Block) -> String {
    let mut out = String::new();
    for t in &toks[open..b.next.min(toks.len())] {
        match t {
            Tok::Text(s) => out.push_str(s),
            Tok::Tag(tag) => out.push_str(&format!("{{{{{tag}}}}}")),
        }
    }
    out
}

/// Look one `#if`/`#unless` condition up: the first present alternative, plus whether the whole condition could not be read at all.
fn condition(
    cond: &str,
    ctx: &Value,
    item: Option<&Value>,
    state: &mut State,
) -> (Option<Value>, bool) {
    let mut value: Option<Value> = None;
    for alt in split_or(cond) {
        let path = alt.split('|').next().unwrap_or(alt).trim();
        if alt.contains('|') || !is_path(path) {
            return (None, true);
        }
        match lookup(path, ctx, item, state) {
            Look::Literal => return (None, true),
            Look::Missing => continue,
            Look::Found(v) => {
                // Blank = absent or empty: an empty string, array or object says nothing, so `or` moves on (templates.md: first present, non-empty wins).
                // `0` and `false` are NOT blank — they carry a value.
                let blank = match &v {
                    Value::Null => true,
                    Value::String(s) => s.is_empty(),
                    Value::Array(a) => a.is_empty(),
                    Value::Object(o) => o.is_empty(),
                    _ => false,
                };
                if !blank && value.is_none() {
                    value = Some(v);
                }
            }
        }
    }
    (value, false)
}

fn render_tokens(toks: &[Tok], ctx: &mut Value, item: Option<&Value>, state: &mut State) -> String {
    let mut out = String::new();
    let mut i = 0;
    while i < toks.len() {
        let Tok::Tag(tag) = &toks[i] else {
            if let Tok::Text(t) = &toks[i] {
                out.push_str(t);
            }
            i += 1;
            continue;
        };
        if tag.starts_with('!') {
            // A comment: dropped, like every Mustache/Handlebars implementation.
            i += 1;
            continue;
        }
        if let Some(path) = tag.strip_prefix('>') {
            match include(path.trim(), ctx, item, state) {
                Some(text) => {
                    note(state, path.trim(), "included");
                    out.push_str(&text);
                }
                None => {
                    note(state, path.trim(), "not an includable template");
                    out.push_str(&format!("{{{{{tag}}}}}"));
                }
            }
            i += 1;
            continue;
        }
        if BLOCK_OPENERS.iter().any(|k| tag == &format!("#{k}")) {
            // A block directive with no spec cannot be read: keep the whole block, closer included (templates.md: a block that cannot be read keeps its whole block, body included).
            // Handling it here is also what stops the closer being swallowed by the skip rule below.
            let b = take_block(toks, i);
            note(state, tag, "kept verbatim (unreadable directive)");
            out.push_str(&block_source(toks, i, &b));
            i = b.next;
            continue;
        }
        if tag.starts_with("#each ") {
            let b = take_block(toks, i);
            let Some((path, limit, sep)) = parse_each(&b.spec) else {
                // A spec that is not a path cannot be read: keep the whole block, closer included.
                note(state, &b.spec, "kept verbatim (unreadable directive)");
                out.push_str(&block_source(toks, i, &b));
                i = b.next;
                continue;
            };
            let items = lookup(&path, ctx, item, state);
            let (text, more) = match &items {
                Look::Literal => {
                    note(state, &b.spec, "kept verbatim (unreadable directive)");
                    (block_source(toks, i, &b), 0)
                }
                Look::Found(Value::Array(a)) if !a.is_empty() => {
                    let (shown, more): (&[Value], usize) = match limit {
                        Some(l) if a.len() > l => (&a[..l], a.len() - l),
                        _ => (&a[..], 0),
                    };
                    let parts: Vec<String> = shown
                        .iter()
                        .map(|it| render_tokens(&toks[b.body.0..b.body.1], ctx, Some(it), state))
                        .collect();
                    (
                        match &sep {
                            Some(s) => parts.join(s),
                            None => parts.concat(),
                        },
                        more,
                    )
                }
                _ => {
                    let text = match b.alt {
                        Some((s, e)) => render_tokens(&toks[s..e], ctx, item, state),
                        None => String::new(),
                    };
                    (text, 0)
                }
            };
            // `@more` belongs to *this* loop, so it is written only once the body has run: a nested `each` sets its own, and the tail after `{{/each}}` must read this level's count.
            state.more = more;
            out.push_str(&text);
            i = b.next;
            continue;
        }
        if tag.starts_with("#if ") || tag.starts_with("#unless ") {
            let b = take_block(toks, i);
            let (value, literal) = condition(&b.spec, ctx, item, state);
            if literal {
                note(state, &b.spec, "kept verbatim (unreadable condition)");
                out.push_str(&block_source(toks, i, &b));
            } else {
                let mut take = value.as_ref().is_some_and(truthy);
                if b.kind == "unless" {
                    take = !take;
                }
                if take {
                    out.push_str(&render_tokens(&toks[b.body.0..b.body.1], ctx, item, state));
                } else if let Some((s, e)) = b.alt {
                    out.push_str(&render_tokens(&toks[s..e], ctx, item, state));
                }
            }
            i = b.next;
            continue;
        }
        if tag == "else" || BLOCK_OPENERS.iter().any(|k| tag == &format!("/{k}")) {
            i += 1;
            continue;
        }
        match resolve(tag, ctx, item, state) {
            None => {
                note(state, tag, "kept verbatim (not an expression)");
                out.push_str(&format!("{{{{{tag}}}}}"));
            }
            Some(v) => out.push_str(&v),
        }
        i += 1;
    }
    out
}

/// `{{> path}}`: render another `info.<path>` template with the same context.
/// Values are always data, so this is the only way one template pulls in another — explicitly.
fn include(path: &str, ctx: &mut Value, item: Option<&Value>, state: &mut State) -> Option<String> {
    if !is_path(path) || state.depth >= MAX_INCLUDE_DEPTH {
        return None;
    }
    let data = walk(state.root?, path)?;
    let data = data.clone();
    state.depth += 1;
    let text = match &data {
        Value::Array(lines) => lines.iter().map(value_text).collect::<Vec<_>>().join(""),
        other => value_text(other),
    };
    let rendered = render_tokens(&tokenize(&text), ctx, item, state);
    state.depth -= 1;
    Some(rendered)
}

/// A dotted walk over a JSON tree, for `{{> path}}` inside the `info` object.
fn walk<'a>(root: &'a Value, path: &str) -> Option<&'a Value> {
    let mut cur = root;
    for p in path.split('.') {
        if p.is_empty() {
            continue;
        }
        cur = match cur {
            Value::Object(o) => o.get(p)?,
            Value::Array(a) => a.get(p.parse::<usize>().ok()?)?,
            _ => return None,
        };
    }
    Some(cur)
}

/// The block directives the renderer knows.
const KNOWN_DIRECTIVES: [&str; 3] = ["each", "if", "unless"];
/// The filters it knows.
const KNOWN_FILTERS: [&str; 1] = ["quote"];
/// The `@`-names it defines.
const KNOWN_AT_NAMES: [&str; 1] = ["more"];

/// `psc tpl --lint`: static findings for one template.
/// Each line names the offending tag; an empty result means the template is well-formed.
/// Lint the *joined* text, since a block may open in one line of the `info` list and close in another.
/// The `.`/`@` checks every path shares — as a plain tag or inside a directive's spec: a `.`-path needs an enclosing `each`, and an `@`-name must be one the renderer defines.
fn lint_path_shape(path: &str, open: &[String], out: &mut Vec<String>) {
    if path.starts_with('.') && !open.iter().any(|k| k == "each") {
        out.push(format!("{path} — no enclosing `#each`"));
    }
    if let Some(name) = path.strip_prefix('@') {
        if !KNOWN_AT_NAMES.contains(&name) {
            out.push(format!("{path} — not a name the renderer defines"));
        }
    }
}

pub fn lint(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut open: Vec<String> = Vec::new();
    for tok in tokenize(text) {
        let Tok::Tag(tag) = tok else { continue };
        if tag.starts_with('!') {
            continue;
        }
        if let Some(rest) = tag.strip_prefix('#') {
            let (kind, spec) = match rest.split_once(char::is_whitespace) {
                Some((k, s)) => (k, s.trim()),
                None => (rest, ""),
            };
            if !KNOWN_DIRECTIVES.contains(&kind) {
                out.push(format!("{tag} — unknown directive"));
                continue;
            }
            if spec.is_empty() {
                out.push(format!("{tag} — needs a path"));
            } else if kind == "each" {
                let path = spec.split_whitespace().next().unwrap_or("");
                if !is_path(path) {
                    out.push(format!("{tag} — not a path"));
                }
                lint_path_shape(path, &open, &mut out);
            } else {
                if spec.contains('|') {
                    out.push(format!("{tag} — conditions chain with `or`, not `|`"));
                }
                for alt in split_or(spec) {
                    let path = alt.split('|').next().unwrap_or(alt).trim();
                    if !is_path(path) {
                        out.push(format!("{tag} — not a path"));
                        break;
                    }
                    lint_path_shape(path, &open, &mut out);
                }
            }
            open.push(kind.to_string());
            continue;
        }
        if let Some(kind) = tag.strip_prefix('/') {
            match open.pop() {
                Some(k) if k == kind => {}
                Some(k) => out.push(format!("{tag} — closes `{k}`, not `{kind}`")),
                None => out.push(format!("{tag} — nothing is open")),
            }
            continue;
        }
        if tag == "else" {
            continue;
        }
        if let Some(path) = tag.strip_prefix('>') {
            if !is_path(path.trim()) {
                out.push(format!("{tag} — not a path"));
            }
            continue;
        }
        for alt in split_or(&tag) {
            let mut steps = alt.split('|').map(str::trim);
            let path = steps.next().unwrap_or("");
            if !is_path(path) {
                out.push(format!("{tag} — not an expression"));
                break;
            }
            lint_path_shape(path, &open, &mut out);
            for f in steps {
                if !KNOWN_FILTERS.contains(&f) {
                    out.push(format!("{f} — unknown filter"));
                }
            }
        }
    }
    for kind in open {
        out.push(format!("#{kind} — never closed"));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn r(tpl: &str, ctx: &Value) -> String {
        render(&Value::String(tpl.to_string()), ctx, "")
    }

    /// An unclosed block has no closer to find: the whole rest of the template is emitted verbatim (templates.md: never silently dropped), never sliced out of range.
    #[test]
    fn unclosed_block_renders_its_source_instead_of_panicking() {
        assert_eq!(r("{{#if .X}}body", &json!({})), "{{#if .X}}body");
        assert_eq!(r("a{{#each .Rows}}row", &json!({})), "a{{#each .Rows}}row");
    }

    /// `or` takes the first alternative that is present *and non-empty*: an empty container says nothing, so the chain moves on.
    /// `0` and `false` carry a value and must stop it.
    #[test]
    fn or_skips_blank_alternatives_including_empty_containers() {
        let t = "[{{#if A or B}}yes{{/if}}]";
        assert_eq!(r(t, &json!({"A": [], "B": ["x"]})), "[yes]");
        assert_eq!(r(t, &json!({"A": {}, "B": "x"})), "[yes]");
        assert_eq!(r(t, &json!({"A": "", "B": "x"})), "[yes]");
        assert_eq!(r(t, &json!({"A": 0, "B": ["x"]})), "[]");
        assert_eq!(r(t, &json!({"A": false, "B": ["x"]})), "[]");
    }

    #[test]
    fn plain_text_passes_through() {
        assert_eq!(r("no tokens here", &json!({})), "no tokens here");
    }

    #[test]
    fn line_lists_join_with_the_separator() {
        let data = json!(["a\n", "b\n"]);
        assert_eq!(render(&data, &json!({}), ""), "a\nb\n");
        assert_eq!(render(&data, &json!({}), "|"), "a\n|b\n");
    }

    #[test]
    fn or_takes_the_first_present_alternative() {
        assert_eq!(
            r("{{Display or Completion}}", &json!({"Completion": "git"})),
            "git"
        );
        assert_eq!(
            r(
                "{{Display or Completion}}",
                &json!({"Display": "g", "Completion": "git"})
            ),
            "g"
        );
        // Present but empty falls through; nothing present at all renders empty.
        assert_eq!(r("[{{A or B}}]", &json!({"A": "", "B": "b"})), "[b]");
        assert_eq!(r("[{{A or B}}]", &json!({})), "[]");
        // A path may still contain the letters of `or`.
        assert_eq!(r("{{order}}", &json!({"order": "3"})), "3");
    }

    #[test]
    fn missing_values_and_non_expressions_re_emit_the_token() {
        assert_eq!(r("[{{Nope}}]", &json!({})), "[]");
        assert_eq!(r("[{{a b}}]", &json!({})), "[{{a b}}]");
        // `.` with no current item, and an engine name the renderer does not know.
        assert_eq!(r("[{{.}}]", &json!({})), "[{{.}}]");
        assert_eq!(r("[{{@index}}]", &json!({})), "[{{@index}}]");
    }

    #[test]
    fn quote_wraps_padded_values() {
        assert_eq!(r("{{Name|quote}}", &json!({"Name": "git"})), "git");
        // A truly empty value never reaches the filter: every expression treats it as absent.
        assert_eq!(r("{{Name|quote}}", &json!({"Name": ""})), "");
        // Only spaces does reach it, and a padded value containing `"` flips to single quotes.
        assert_eq!(r("{{Name|quote}}", &json!({"Name": " "})), "\" \"");
        assert_eq!(r("{{Name|quote}}", &json!({"Name": " g "})), "\" g \"");
        assert_eq!(r("{{Name|quote}}", &json!({"Name": " a\"b "})), "' a\"b '");
    }

    #[test]
    fn an_unknown_filter_re_emits_the_token() {
        assert_eq!(
            r("[{{Name|upper}}]", &json!({"Name": "g"})),
            "[{{Name|upper}}]"
        );
    }

    #[test]
    fn numbers_bools_and_containers_render_value_text() {
        assert_eq!(r("{{N}}", &json!({"N": 100})), "100");
        assert_eq!(r("{{N}}", &json!({"N": true})), "1");
        assert_eq!(r("{{N}}", &json!({"N": false})), "0");
        // A container is data like any other value: printed as-is (JSON), with or without a filter.
        // Rendering it empty without a filter but as JSON with one was the inconsistency this pins shut — the test's own name said `value_text` while its assertions said `""`.
        assert_eq!(r("{{N}}", &json!({"N": [1, 2]})), "[1,2]");
        assert_eq!(r("{{N}}", &json!({"N": {"a": 1}})), r#"{"a":1}"#);
        // The filter sees that same text; a container's JSON has no surrounding whitespace, so `quote` is a no-op on it (it exists for padded scalars, which it does quote).
        assert_eq!(r("{{N|quote}}", &json!({"N": [1, 2]})), "[1,2]");
        assert_eq!(r("{{N|quote}}", &json!({"N": " a "})), "\" a \"");
    }

    #[test]
    fn a_hyphenated_key_is_a_path_not_literal_text() {
        assert_eq!(
            r("{{scoop-checkver}}", &json!({"scoop-checkver": "ok"})),
            "ok"
        );
        assert_eq!(r("{{last-check}}", &json!({})), "");
    }

    #[test]
    fn each_renders_items_with_the_current_item_in_scope() {
        let ctx = json!({"Alias": ["git", "g"]});
        assert_eq!(r("{{#each Alias}}[{{.}}]{{/each}}", &ctx), "[git][g]");
        assert_eq!(
            r("{{#each Alias sep=', '}}[{{.}}]{{/each}}", &ctx),
            "[git], [g]"
        );
        let recs = json!({"Rows": [{"Name": "git", "Tip": "t"}, {"Name": "g", "Tip": "u"}]});
        assert_eq!(
            r("{{#each Rows}}{{.Name}}={{.Tip}} {{/each}}", &recs),
            "git=t g=u "
        );
        assert_eq!(
            r(
                "{{#each Pairs}}{{.0}}/{{.1}}{{/each}}",
                &json!({"Pairs": [["a", "b"]]})
            ),
            "a/b"
        );
    }

    #[test]
    fn a_separator_keeps_its_whitespace() {
        // A quoted separator may hold a newline; a whitespace split used to flatten it to spaces.
        let ctx = json!({"Alias": ["a", "b"]});
        assert_eq!(r("{{#each Alias sep='\n'}}{{.}}{{/each}}", &ctx), "a\nb");
        assert_eq!(
            r("{{#each Alias sep='\n\n'}}{{.}}{{/each}}", &ctx),
            "a\n\nb"
        );
        // A separator with a space still survives the spec scanner.
        assert_eq!(
            r("{{#each Alias sep=' and '}}{{.}}{{/each}}", &ctx),
            "a and b"
        );
    }

    #[test]
    fn each_limit_publishes_more_and_else_covers_empty_lists() {
        let ctx = json!({"Added": ["a", "b", "c", "d"]});
        // The tail after the loop reads `@more`: that is the whole point of the count surviving it.
        assert_eq!(
            r(
                "{{#each Added limit=2 sep=' '}}{{.}}{{/each}}{{#if @more}} (+{{@more}}){{/if}}",
                &ctx
            ),
            "a b (+2)"
        );
        assert_eq!(
            r("{{#each Missing}}x{{else}}none{{/each}}", &json!({})),
            "none"
        );
        assert_eq!(
            r(
                "{{#each Empty}}x{{else}}none{{/each}}",
                &json!({"Empty": []})
            ),
            "none"
        );
        // `@more` reads 0 when no capped loop published a count.
        assert_eq!(r("{{#if @more}}r{{else}}no{{/if}}", &json!({})), "no");
        assert_eq!(r("{{@more}}", &json!({})), "0");
        // A separator with a space needs the quotes to survive the spec parser.
        assert_eq!(
            r(
                "{{#each Alias sep=' and '}}{{.}}{{/each}}",
                &json!({"Alias": ["a", "b"]})
            ),
            "a and b"
        );
    }

    #[test]
    fn if_is_truthy_based_and_has_an_else_branch() {
        assert_eq!(r("{{#if A}}yes{{else}}no{{/if}}", &json!({"A": 1})), "yes");
        assert_eq!(r("{{#if A}}yes{{else}}no{{/if}}", &json!({"A": 0})), "no");
        assert_eq!(r("{{#if A}}yes{{else}}no{{/if}}", &json!({"A": ""})), "no");
        assert_eq!(
            r("{{#if A}}yes{{else}}no{{/if}}", &json!({"A": false})),
            "no"
        );
        assert_eq!(r("{{#if A}}yes{{else}}no{{/if}}", &json!({"A": []})), "no");
        assert_eq!(
            r("{{#if A}}yes{{else}}no{{/if}}", &json!({"A": {"k": 1}})),
            "yes"
        );
        // `or` in a condition means "the first one that is there".
        assert_eq!(
            r("{{#if A or B}}yes{{else}}no{{/if}}", &json!({"B": 1})),
            "yes"
        );
    }

    #[test]
    fn unless_is_if_with_the_branches_swapped() {
        assert_eq!(r("{{#unless A}}no{{else}}yes{{/unless}}", &json!({})), "no");
        assert_eq!(
            r("{{#unless A}}no{{else}}yes{{/unless}}", &json!({"A": 1})),
            "yes"
        );
        assert_eq!(
            r("{{#unless A or B}}no{{/unless}}", &json!({"B": ""})),
            "no"
        );
    }

    #[test]
    fn an_unevaluable_block_keeps_its_whole_text() {
        // A directive whose path cannot be resolved (here `.` with no current item) keeps its block verbatim: the body must never disappear.
        assert_eq!(
            r("[{{#if .X}}body{{/if}}]", &json!({})),
            "[{{#if .X}}body{{/if}}]"
        );
        assert_eq!(
            r("[{{#each .Rows}}row{{/each}}]", &json!({})),
            "[{{#each .Rows}}row{{/each}}]"
        );
    }

    #[test]
    fn nested_blocks_close_on_their_own_directive() {
        let ctx = json!({"Rows": [{"Vals": ["x", "y"]}]});
        assert_eq!(
            r("{{#each Rows}}{{#each .Vals}}{{.}}{{/each}}{{/each}}", &ctx),
            "xy"
        );
        // A truthy condition takes the body even when that body renders empty; a missing field is what falls to `else`.
        assert_eq!(
            r(
                "{{#each Rows}}{{#if .Vals}}yes{{else}}none{{/if}}{{/each}}",
                &ctx
            ),
            "yes"
        );
        assert_eq!(
            r(
                "{{#each Rows}}{{#if .Nope}}yes{{else}}none{{/if}}{{/each}}",
                &json!({"Rows": [{}]})
            ),
            "none"
        );
    }

    #[test]
    fn comments_are_dropped() {
        assert_eq!(r("a{{! a comment }}b", &json!({})), "ab");
        assert_eq!(r("a{{!\n multi\n line\n}}b", &json!({})), "ab");
        // A comment ends at the first `}}`; that is all the grammar promises about its content.
        assert_eq!(r("a{{! mentions {{ a token }}b", &json!({})), "ab");
    }

    #[test]
    fn an_escaped_brace_is_literal() {
        assert_eq!(r("\\{{NotAPath}}", &json!({})), "{{NotAPath}}");
        assert_eq!(r("a \\{{ b }} c", &json!({})), "a {{ b }} c");
    }

    #[test]
    fn a_value_is_data_and_never_a_template() {
        // The one boundary worth holding: what a lookup produces is text, so a tip or a remote description containing braces is printed, not interpreted.
        assert_eq!(
            r("{{Tip}}", &json!({"Tip": "{{NotAPath}}"})),
            "{{NotAPath}}"
        );
        assert_eq!(
            r("{{Tip}}", &json!({"Tip": "a {{#each X}} b"})),
            "a {{#each X}} b"
        );
    }

    #[test]
    fn include_pulls_in_another_template_of_the_root() {
        let root = json!({
            "header": "<@Cyan>Header\n",
            "note": "see {{Version}}",
            "outer": "{{> header}}{{> note}}\n",
            "loop": "{{> cycle}}",
            "cycle": "{{> loop}}",
        });
        let data = Value::String("{{> outer}}".to_string());
        assert_eq!(
            render_with_root(&data, &json!({"Version": "7.7.0"}), "", Some(&root)),
            "<@Cyan>Header\nsee 7.7.0\n"
        );
        // The included template reads the same context and the same `@`-namespace.
        let data = Value::String("{{> note}}".to_string());
        assert_eq!(
            render_with_root(&data, &json!({"Version": "1"}), "", Some(&root)),
            "see 1"
        );
        // A cycle stops at the depth limit, re-emitting the token instead of looping forever.
        let data = Value::String("{{> cycle}}".to_string());
        let out = render_with_root(&data, &json!({}), "", Some(&root));
        assert!(
            out.contains("{{> cycle}}") || out.contains("{{> loop}}"),
            "{out}"
        );
        // Without a root, and for a path that is not there, the token stays put.
        assert_eq!(r("[{{> header}}]", &json!({})), "[{{> header}}]");
        let data = Value::String("[{{> missing}}]".to_string());
        assert_eq!(
            render_with_root(&data, &json!({}), "", Some(&root)),
            "[{{> missing}}]"
        );
    }

    #[test]
    fn explain_reports_resolved_and_missing_paths() {
        let (_, notes) = explain_with_root(
            &json!("Set to {{Value}} at {{Nope}}."),
            &json!({"Value": "x"}),
            "",
            None,
        );
        assert!(notes.iter().any(|n| n == "Value — resolved"), "{notes:?}");
        assert!(notes.iter().any(|n| n == "Nope — unresolved"), "{notes:?}");
    }

    #[test]
    fn explain_reports_verbatim_tokens() {
        let (out, notes) = explain_with_root(&json!("[{{a b}}][{{@index}}]"), &json!({}), "", None);
        assert_eq!(out, "[{{a b}}][{{@index}}]");
        assert_eq!(notes.len(), 2, "{notes:?}");
        assert!(
            notes.iter().all(|n| n.contains("kept verbatim")),
            "{notes:?}"
        );
    }

    #[test]
    fn lint_finds_the_static_problems() {
        assert!(lint("{{#each A}}x{{/each}}").is_empty());
        // A block may open in one line of the `info` list and close in another.
        assert!(lint(&["{{#each A}}", "x", "{{/each}}"].join("")).is_empty());
        assert!(lint("{{! a note }}{{> description}}").is_empty());
        assert!(lint("{{#each A}}x")
            .iter()
            .any(|f| f.contains("never closed")));
        assert!(lint("{{/each}}")
            .iter()
            .any(|f| f.contains("nothing is open")));
        assert!(lint("{{#nope A}}")
            .iter()
            .any(|f| f.contains("unknown directive")));
        assert!(lint("{{X|upper}}")
            .iter()
            .any(|f| f.contains("unknown filter")));
        assert!(lint("{{@index}}")
            .iter()
            .any(|f| f.contains("not a name the renderer defines")));
        assert!(lint("{{.Name}}").iter().any(|f| f.contains("no enclosing")));
        assert!(lint("{{#if A|B}}{{/if}}")
            .iter()
            .any(|f| f.contains("chain with `or`")));
        // Inside a loop, `.` is the item.
        assert!(lint("{{#each A}}{{.Name}}{{/each}}").is_empty());
    }

    /// A directive spec that is not a path cannot be read, so the whole block renders literally — closer included.
    /// It used to be taken as a path, so the lookup missed and the body fell to the `else` branch (or vanished) with nothing to explain it.
    #[test]
    fn an_unreadable_each_spec_keeps_the_whole_block() {
        let ctx = json!({"A": ["x", "y"]});
        assert_eq!(
            r("{{#each A|quote}}[{{.}}]{{/each}}", &ctx),
            "{{#each A|quote}}[{{.}}]{{/each}}"
        );
        assert_eq!(
            lint("{{#each A|quote}}x{{/each}}"),
            vec!["#each A|quote — not a path"]
        );
    }

    /// A known directive with no spec at all is the same kind of unreadable block.
    /// It used to emit the opener literally and then swallow the closer (the closer matched the "skip closers" rule), so the output was neither the source nor a render.
    #[test]
    fn a_spec_less_directive_keeps_the_whole_block_too() {
        let ctx = json!({"A": 1});
        assert_eq!(r("{{#if}}body{{/if}}", &ctx), "{{#if}}body{{/if}}");
        assert_eq!(r("{{#each}}body{{/each}}", &ctx), "{{#each}}body{{/each}}");
        assert_eq!(lint("{{#if}}x{{/if}}"), vec!["#if — needs a path"]);
    }

    /// `@more` belongs to the loop whose tail reads it: a nested capped `each` must not leave its own count behind for the outer `{{/each}}`.
    #[test]
    fn at_more_belongs_to_the_enclosing_loop() {
        let ctx = json!({"Outer": [{"Inner": ["a", "b", "c"]}, {"Inner": []}]});
        let tpl = "{{#each Outer limit=1}}[{{#each .Inner limit=1}}{{.}}{{/each}}]{{/each}}more={{@more}}";
        assert_eq!(r(tpl, &ctx), "[a]more=1");
    }

    /// The lint applies the `.`/`@` rules to a directive's spec too, not only to a plain tag.
    #[test]
    fn lint_checks_the_shape_of_a_directive_spec() {
        assert_eq!(
            lint("{{#if .X}}x{{/if}}"),
            vec![".X — no enclosing `#each`"]
        );
        assert_eq!(
            lint("{{#unless @bogus}}x{{/unless}}"),
            vec!["@bogus — not a name the renderer defines"]
        );
        // Inside an `each` the `.`-path is legal, and `@more` is a defined name.
        assert!(lint("{{#each Rows}}{{#if .X}}x{{/if}}{{/each}}").is_empty());
        assert!(lint("{{#if @more}}x{{/if}}").is_empty());
    }
}
