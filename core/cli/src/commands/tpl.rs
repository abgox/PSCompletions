//! `psc tpl <dotted.info.path> [--ctx <json>] [--version <v>] [--no-color] [--markup]` and `psc tpl --stdin` — render one of the `psc` completion's `info` templates.
//!
//! Internal, like `init`: a host names the template (or hands over the value it already holds, via `--stdin`) and passes its data, so the `{{…}}` grammar has exactly one implementation.
//! It is not part of the completion menu, and the caller supplies whatever a template reads (`Version`, a record list, counts) — the engine never invents those values.

use std::io::Read;
use std::process::ExitCode;

use serde_json::{json, Value};

use crate::data::{load_psc_info, Settings};
use crate::output::Out;
use crate::tpl;

pub fn cmd_tpl(
    args: &[String],
    completions_dir: &str,
    run_lang: &str,
    settings: &Settings,
) -> ExitCode {
    let mut path: Option<&str> = None;
    let mut ctx: Option<Value> = None;
    let mut version: Option<String> = None;
    let mut color = true;
    let mut markup = false;
    let mut stdin_mode = false;
    let mut explain = false;
    let mut lint = false;
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "--no-color" {
            color = false;
        } else if a == "--markup" {
            // Leave the `<@Color>` markup as text, for a host that colors it itself.
            markup = true;
        } else if a == "--stdin" {
            stdin_mode = true;
        } else if a == "--explain" {
            // Report what the renderer did with each name and token, after the rendered text.
            explain = true;
        } else if a == "--lint" {
            lint = true;
        } else if let Some(v) = a.strip_prefix("--ctx=") {
            ctx = Some(parse_ctx(v));
        } else if a == "--version" {
            // The module's own version lives in the module directory, not the data dir, so the caller supplies it; `Version` is what the info page prints.
            let Some(v) = args.get(i + 1).filter(|v| !v.starts_with('-')) else {
                println!("psc tpl: --version needs a value");
                return ExitCode::FAILURE;
            };
            version = Some(v.clone());
            i += 1;
        } else if a == "--ctx" {
            // A value starting with `-` is the next flag, not the context (the rule the global flags already follow): swallowing `--no-color` here would silently drop it.
            let Some(v) = args.get(i + 1).filter(|v| !v.starts_with('-')) else {
                println!("psc tpl: --ctx needs a JSON value");
                return ExitCode::FAILURE;
            };
            ctx = Some(parse_ctx(v));
            i += 1;
        } else if a.starts_with('-') {
            // No path starts with `-`, so this is a caller's typo — reporting it as "no such template" would send them looking in the wrong place.
            println!("psc tpl: unknown argument {a}");
            return ExitCode::FAILURE;
        } else if path.is_none() {
            path = Some(a.as_str());
        }
        i += 1;
    }
    if stdin_mode && path.is_some() {
        println!("psc tpl: give either a path or --stdin, not both");
        return ExitCode::FAILURE;
    }
    if !stdin_mode && path.is_none() {
        println!("psc tpl <dotted.info.path> [--ctx <json>] [--version <v>] [--no-color]");
        println!("psc tpl --stdin [--version <v>] [--no-color] [--markup] [--explain]");
        println!("psc tpl <path> --lint");
        return ExitCode::FAILURE;
    }

    // `--stdin` carries the template value and its context as one JSON request: a host that holds the value (rather than a path) hands it over without quoting it into an argument.
    let (data, ctx, sep) = if stdin_mode {
        let mut raw = String::new();
        if std::io::stdin().read_to_string(&mut raw).is_err() {
            println!("psc tpl: --stdin could not read the request");
            return ExitCode::FAILURE;
        }
        let req: Value = match serde_json::from_str(&raw) {
            Ok(v) => v,
            Err(_) => {
                println!("psc tpl: --stdin reads a JSON request {{data, ctx, sep}}");
                return ExitCode::FAILURE;
            }
        };
        let Some(data) = req.get("data") else {
            println!("psc tpl: --stdin reads a JSON request {{data, ctx, sep}}");
            return ExitCode::FAILURE;
        };
        (
            data.clone(),
            req.get("ctx").cloned().unwrap_or_else(|| json!({})),
            req.get("sep")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
        )
    } else {
        let info = load_psc_info(
            completions_dir,
            &psc_language(completions_dir, run_lang, settings),
        );
        let Some(data) = dotted(&info, path.unwrap()) else {
            // No such template: print nothing and fail, so a caller can tell it apart from an empty rendering and fall back.
            return ExitCode::FAILURE;
        };
        (
            data.clone(),
            ctx.unwrap_or_else(|| json!({})),
            String::new(),
        )
    };

    let mut ctx = ctx;
    if let (Some(v), Value::Object(o)) = (version, &mut ctx) {
        // A caller that already knows a `Version` keeps it (`--version` only fills the gap).
        o.entry("Version").or_insert(Value::String(v));
    }
    if lint {
        // Lint the *joined* text: a block may open in one line of the `info` list and close in another, so linting line by line would report a well-formed template as broken.
        let text = match &data {
            Value::Array(lines) => lines
                .iter()
                .map(|v| v.as_str().unwrap_or_default().to_string())
                .collect::<Vec<_>>()
                .join(&sep),
            Value::String(s) => s.clone(),
            other => other.to_string(),
        };
        let findings = tpl::lint(&text);
        for f in &findings {
            println!("{f}");
        }
        println!("{} finding(s)", findings.len());
        return if findings.is_empty() {
            ExitCode::SUCCESS
        } else {
            ExitCode::FAILURE
        };
    }

    // An include resolves against the `psc` completion's own `info`, whichever mode asked.
    let info = load_psc_info(
        completions_dir,
        &psc_language(completions_dir, run_lang, settings),
    );
    let (text, notes) = if explain {
        tpl::explain_with_root(&data, &ctx, &sep, Some(&info))
    } else {
        (
            tpl::render_with_root(&data, &ctx, &sep, Some(&info)),
            Vec::new(),
        )
    };

    if markup {
        print!("{text}");
        return ExitCode::SUCCESS;
    }
    // Color is the caller's decision: the hosts render into a captured stdout, where a TTY test would answer "no" and silently drop the color.
    print!("{}", Out { color }.render(&text));
    if color {
        print!("\x1b[0m");
    }
    if explain {
        println!();
        for n in &notes {
            println!("{n}");
        }
    }
    ExitCode::SUCCESS
}

/// A malformed `--ctx` renders as an empty context: bad caller data must not abort the render.
fn parse_ctx(text: &str) -> Value {
    serde_json::from_str(text).unwrap_or_else(|_| json!({}))
}

/// Walk a dotted path (`rm.all_confirm`) through the `info` object.
fn dotted<'a>(info: &'a Value, path: &str) -> Option<&'a Value> {
    let mut cur = info;
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

/// The language the templates render in: the `psc` completion's own.
/// Its declared list decides — a per-completion override beats the module language, and the module language beats nothing.
fn psc_language(completions_dir: &str, run_lang: &str, settings: &Settings) -> String {
    let declared: Vec<String> =
        std::fs::read_to_string(format!("{completions_dir}/psc/config.json"))
            .ok()
            .and_then(|t| serde_json::from_str::<Value>(&t).ok())
            .and_then(|v| {
                v.get("language").and_then(|l| l.as_array()).map(|a| {
                    a.iter()
                        .filter_map(|x| x.as_str().map(String::from))
                        .collect()
                })
            })
            .unwrap_or_default();
    let pick = |want: &str| {
        if declared.iter().any(|d| d == want) {
            want.to_string()
        } else {
            declared
                .first()
                .cloned()
                .unwrap_or_else(|| run_lang.to_string())
        }
    };
    match settings
        .config
        .pointer("/completion/psc/language")
        .and_then(|v| v.as_str())
    {
        Some(per) => pick(per),
        None => pick(run_lang),
    }
}
