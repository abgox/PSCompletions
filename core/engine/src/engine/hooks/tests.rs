//! Tests for the Lua hooks runtime.

use super::api::{api_which, normalize_glob_pattern};
use super::runner::{new_sandbox_lua, run_hook_with_timeout};
use super::*;
use std::time::Duration;

fn ctx() -> HookContext {
    HookContext {
        cmd: "psc".into(),
        path: vec!["list".into()],
        pending: Pending::default(),
        opts: Vec::new(),
        language: "en-US".into(),
        tokens: vec![
            Token {
                text: "psc".into(),
                kind: "command".into(),
                canonical: None,
            },
            Token {
                text: "list".into(),
                kind: "command".into(),
                canonical: None,
            },
        ],
        config: serde_json::json!({ "max_commit": 30 }),
        manifest: serde_json::Value::Null,
        data: serde_json::Value::Null,
        cwd: std::env::current_dir()
            .unwrap()
            .to_string_lossy()
            .to_string(),
        log_dir: String::new(),
    }
}

fn empty_static() -> Vec<LuaItem> {
    Vec::new()
}

#[test]
fn sandbox_disables_system_access() {
    let lua = new_sandbox_lua().unwrap();
    let cases: &[(&str, &str)] = &[
        // disabled direct system access → nil
        ("os.execute", "nil"),
        ("os.remove", "nil"),
        ("os.rename", "nil"),
        ("os.exit", "nil"),
        ("os.tmpname", "nil"),
        ("os.getenv", "nil"),
        ("io", "nil"),
        ("require", "nil"),
        ("package", "nil"),
        ("dofile", "nil"),
        ("loadfile", "nil"),
        ("load", "nil"),
        ("debug", "nil"),
        // harmless capabilities kept → function
        ("os.time", "function"),
        ("os.date", "function"),
        ("os.clock", "function"),
        ("string.format", "function"),
        ("table.concat", "function"),
        ("math.max", "function"),
        ("utf8.char", "function"),
        ("coroutine.create", "function"),
    ];
    for (expr, expected) in cases {
        let script = format!("return type({expr})");
        let t: mlua::LuaString = lua.load(&script).eval().unwrap();
        assert_eq!(t.to_str().unwrap(), *expected, "type({expr})");
    }
}

#[test]
fn run_hook_rejects_direct_system_access() {
    // A malicious hook tries a direct system call — it must fail rather than execute
    for script in [
        r#"local t = {}; t[1] = os.execute("echo hi"); return t"#,
        r#"local f = io.open("/etc/passwd"); return {}"#,
        r#"local f = require("fs"); return {}"#,
    ] {
        let res = run_hook(&ctx(), script, &empty_static());
        assert!(res.is_err(), "expected sandbox rejection, got {res:?}");
    }
}

#[test]
fn hook_times_out_on_infinite_loop() {
    // An infinite-loop hook must be interrupted on timeout, not hang forever
    let script = "while true do end\nreturn {}";
    let res = run_hook_with_timeout(&ctx(), script, &empty_static(), Duration::from_millis(300));
    let err = res.expect_err("infinite loop must time out");
    assert!(
        err.to_string().contains("timed out"),
        "unexpected error: {err}"
    );
}

#[test]
fn hook_completes_well_within_timeout() {
    // A normal hook (pure computation + psc.run) must finish within the short timeout, not be killed
    let script = r#"
    local t = {}
    for i = 1, 1000 do t[i] = { name = "x" .. i } end
    local lines = psc.run({ "echo", "hello" })
    t[1001] = { name = lines[1] }
    return t
"#;
    let out =
        run_hook_with_timeout(&ctx(), script, &empty_static(), Duration::from_millis(300)).unwrap();
    assert_eq!(out.len(), 1001);
    assert_eq!(out[1000].text, "hello");
}

#[test]
fn hook_sees_empty_config_when_host_passes_null() {
    // The host passes `config.completion[<cmd>]`, which is JSON null for an unconfigured
    // completion. `psc.config` must surface as an empty table (not nil) so hooks that
    // index it (e.g. git's `psc.config.max_commit`) don't crash on a nil index.
    let script = r#"
    local cs = {}
    if type(psc.config) == "table" then
        cs[1] = { name = "ok-" .. tostring(psc.config.max_commit) }
    else
        cs[1] = { name = "config-nil" }
    end
    return cs
"#;
    let mut c = ctx();
    c.config = serde_json::Value::Null;
    let out =
        run_hook_with_timeout(&c, script, &empty_static(), Duration::from_millis(300)).unwrap();
    assert_eq!(out[0].text, "ok-nil");
}

/// Manifest with nested `next`, for `psc.mount_items` tests.
fn nested_manifest_ctx() -> HookContext {
    let manifest = serde_json::json!({
        "next": [
            {
                "name": "config",
                "next": [
                    { "name": "set" },
                    { "name": "get", "next": [ { "name": "theme" }, { "name": "lang" } ] },
                    { "name": "delete", "next": [] },
                    { "name": "verbose", "option": [ { "name": "--all" } ] }
                ]
            }
        ]
    });
    let mut c = ctx();
    c.manifest = manifest;
    c
}

#[test]
fn mount_items_mounts_tips_usage_example_and_no_symbol() {
    let script = r#"
    local cs = {}
    psc.add(cs, psc.mount_items({ "next", "config", "next" }))
    return psc.merge(cs)
"#;
    let out = run_hook(&nested_manifest_ctx(), script, &empty_static()).unwrap();
    // Direct children of config.next only: set, get, delete, verbose (no recursion into
    // get's next or verbose's option).
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["set", "get", "delete", "verbose"]);
    // No symbol is computed here — the caller sets symbols via psc.set_symbol when needed.
    for item in &out {
        assert_eq!(item.symbol, None);
    }
}

#[test]
fn set_symbol_overrides_static_item_symbol() {
    let script = r#"
    psc.set_symbol("set", "switch")
    return psc.merge({})
"#;
    let static_items = vec![
        LuaItem {
            text: "set".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
        LuaItem {
            text: "get".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: Some("stay".into()),
            repeat: 0,
        },
    ];
    let out = run_hook(&nested_manifest_ctx(), script, &static_items).unwrap();
    // set is overridden to continue (~); get is untouched → keeps its stay
    let set = out.iter().find(|i| i.text == "set").unwrap();
    assert_eq!(set.symbol.as_deref(), Some("switch"));
    let get = out.iter().find(|i| i.text == "get").unwrap();
    assert_eq!(get.symbol.as_deref(), Some("stay"));
}

#[test]
fn add_supports_localized_tip() {
    let script = r#"
    local cs = {}
    psc.add(cs, { name = "alpha", tip = { ["en-US"] = "English tip", ["zh-CN"] = "中文提示" } })
    return psc.merge(cs)
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].tip.as_deref(), Some("English tip"));
    // zh-CN picks the zh entry
    let mut c = ctx();
    c.language = "zh-CN".into();
    let out2 = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out2[0].tip.as_deref(), Some("中文提示"));
    // unknown language falls back to en-US
    let mut c2 = ctx();
    c2.language = "fr-FR".into();
    let out3 = run_hook(&c2, script, &empty_static()).unwrap();
    assert_eq!(out3[0].tip.as_deref(), Some("English tip"));
}

#[test]
fn set_tip_overrides_or_inserts() {
    let script = r#"
    psc.set_tip("set", "override tip")
    psc.set_tip("get", "prefix", { mode = "prepend" })
    psc.set_tip("other", "suffix", { mode = "append" })
    return psc.merge({})
"#;
    let static_items = vec![
        LuaItem {
            text: "set".into(),
            tip: Some("original".into()),
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
        LuaItem {
            text: "get".into(),
            tip: Some("original".into()),
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
        LuaItem {
            text: "other".into(),
            tip: Some("original".into()),
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
    ];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    let set = out.iter().find(|i| i.text == "set").unwrap();
    assert_eq!(set.tip.as_deref(), Some("override tip"));
    let get = out.iter().find(|i| i.text == "get").unwrap();
    assert_eq!(get.tip.as_deref(), Some("prefix\noriginal"));
    let other = out.iter().find(|i| i.text == "other").unwrap();
    assert_eq!(other.tip.as_deref(), Some("original\nsuffix"));
}

#[test]
fn set_tip_case_sensitive_matches_exact_case() {
    let script = r#"
    psc.set_tip("set", "override", { case_sensitive = true })
    return psc.merge({})
"#;
    let static_items = vec![
        LuaItem {
            text: "set".into(),
            tip: Some("original".into()),
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
        LuaItem {
            text: "SET".into(),
            tip: Some("keep".into()),
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
    ];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    let set = out.iter().find(|i| i.text == "set").unwrap();
    assert_eq!(set.tip.as_deref(), Some("override"));
    let upper = out.iter().find(|i| i.text == "SET").unwrap();
    assert_eq!(upper.tip.as_deref(), Some("keep"));
}

#[test]
fn set_tip_supports_localized_tip() {
    let script = r#"
    psc.set_tip("set", { ["en-US"] = "Eng", ["zh-CN"] = "中文" })
    return psc.merge({})
"#;
    let static_items = vec![LuaItem {
        text: "set".into(),
        tip: Some("original".into()),
        usage: None,
        example: None,
        symbol: None,
        repeat: 0,
    }];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    assert_eq!(out[0].tip.as_deref(), Some("Eng"));
    let mut c = ctx();
    c.language = "zh-CN".into();
    let out2 = run_hook(&c, script, &static_items).unwrap();
    assert_eq!(out2[0].tip.as_deref(), Some("中文"));
}

#[test]
fn set_symbol_matches_name_case_insensitively() {
    // set_symbol matches by name ignoring case: `set` also overrides `SET` (case-distinct
    // items are rare; the insensitive default matches most commands).
    let script = r#"
    psc.set_symbol("set", "switch")
    return psc.merge({})
"#;
    let static_items = vec![
        LuaItem {
            text: "set".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
        LuaItem {
            text: "SET".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: Some("stay".into()),
            repeat: 0,
        },
    ];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    let set = out.iter().find(|i| i.text == "set").unwrap();
    assert_eq!(set.symbol.as_deref(), Some("switch"));
    let upper = out.iter().find(|i| i.text == "SET").unwrap();
    assert_eq!(upper.symbol.as_deref(), Some("switch"));
}

#[test]
fn set_symbol_case_sensitive_matches_exact_case() {
    // With `case_sensitive = true`, only the exact same name+case is overridden.
    let script = r#"
    psc.set_symbol("set", "switch", { case_sensitive = true })
    return psc.merge({})
"#;
    let static_items = vec![
        LuaItem {
            text: "set".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
        LuaItem {
            text: "SET".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: Some("stay".into()),
            repeat: 0,
        },
    ];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    let set = out.iter().find(|i| i.text == "set").unwrap();
    assert_eq!(set.symbol.as_deref(), Some("switch"));
    let upper = out.iter().find(|i| i.text == "SET").unwrap();
    assert_eq!(upper.symbol.as_deref(), Some("stay"));
}

#[test]
fn set_symbol_rejects_unknown_symbol() {
    let script = r#"
    psc.set_symbol("set", "bogus")
    return psc.merge({})
"#;
    let err = run_hook(
        &ctx(),
        script,
        &[LuaItem {
            text: "set".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        }],
    )
    .unwrap_err();
    assert!(err.to_string().contains("invalid symbol"));
}

#[test]
fn repeat_filters_used_dynamic_items() {
    // A used dynamic item (repeat default 0) is filtered: after `completion git --reset`, --reset is gone
    let script = r#"
    local cs = {}
    psc.add(cs, { name = "--reset", tip = "reset", symbol = "stay" })
    return psc.merge(cs)
"#;
    let mut c = ctx();
    c.tokens = vec![
        Token {
            text: "psc".into(),
            kind: "command".into(),
            canonical: None,
        },
        Token {
            text: "completion".into(),
            kind: "command".into(),
            canonical: None,
        },
        Token {
            text: "git".into(),
            kind: "value".into(),
            canonical: None,
        },
        Token {
            text: "--reset".into(),
            kind: "option".into(),
            canonical: None,
        },
    ];
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert!(out.iter().all(|i| i.text != "--reset"));
    // unused → kept
    c.tokens.pop();
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "--reset");
}

#[test]
fn repeat_allows_until_limit() {
    // repeat=2: suggested after 1 use, filtered once 2 uses are exhausted
    let script = r#"
    local cs = {}
    psc.add(cs, { name = "-v", tip = "verbose", symbol = "stay", repeat_count = 2 })
    return psc.merge(cs)
"#;
    let mut c = ctx();
    c.tokens = vec![
        Token {
            text: "psc".into(),
            kind: "command".into(),
            canonical: None,
        },
        Token {
            text: "-v".into(),
            kind: "option".into(),
            canonical: None,
        },
    ];
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "-v");
    assert_eq!(out[0].repeat, 2);
    c.tokens.push(Token {
        text: "-v".into(),
        kind: "option".into(),
        canonical: None,
    });
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out.len(), 0);
}

#[test]
fn repeat_counts_alias_as_used() {
    // Typing alias -r (canonical → primary --reset) makes dynamic --reset count as used and filtered
    let script = r#"
    local cs = {}
    psc.add(cs, { name = "--reset", tip = "reset", symbol = "stay" })
    return psc.merge(cs)
"#;
    let mut c = ctx();
    c.tokens = vec![
        Token {
            text: "psc".into(),
            kind: "command".into(),
            canonical: None,
        },
        Token {
            text: "completion".into(),
            kind: "command".into(),
            canonical: None,
        },
        Token {
            text: "git".into(),
            kind: "value".into(),
            canonical: None,
        },
        Token {
            text: "-r".into(),
            kind: "option".into(),
            canonical: Some("--reset".into()),
        },
    ];
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert!(out.iter().all(|i| i.text != "--reset"));
    // A value token without canonical counts by raw text: a used value (branch) is no longer suggested
    let mut c = ctx();
    c.tokens = vec![
        Token {
            text: "git".into(),
            kind: "command".into(),
            canonical: None,
        },
        Token {
            text: "branch".into(),
            kind: "command".into(),
            canonical: None,
        },
        Token {
            text: "main".into(),
            kind: "value".into(),
            canonical: None,
        },
    ];
    let script = r#"
    local cs = {}
    psc.add(cs, { name = "main", tip = "branch --- main" })
    return psc.merge(cs)
"#;
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert!(out.iter().all(|i| i.text != "main"));
}

#[test]
fn mount_items_matches_path_case_sensitively() {
    // Manifest holds both set / SET nodes — mount_items matches paths exactly; "SET" mounts its subtree
    let script = r#"
    local cs = {}
    psc.add(cs, psc.mount_items({ "next", "config", "SET", "next" }))
    return psc.merge(cs)
"#;
    let mut c = nested_manifest_ctx();
    let manifest = serde_json::json!({
        "next": [
            {
                "name": "config",
                "next": [
                    { "name": "set", "next": [ { "name": "lower" } ] },
                    { "name": "SET", "next": [ { "name": "UPPER" } ] }
                ]
            }
        ]
    });
    c.manifest = manifest;
    let out = run_hook(&c, script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["UPPER"]);
}

#[test]
fn mount_items_uses_command_semantics_for_dash_looking_items() {
    // Items like -x / -authordate in a next array are plain commands: looks don't matter → no symbol
    let script = r#"
    local cs = {}
    psc.add(cs, psc.mount_items({ "next", "config", "next" }))
    return psc.merge(cs)
"#;
    let mut c = nested_manifest_ctx();
    c.manifest = serde_json::json!({
        "next": [{
            "name": "config",
            "next": [
                { "name": "-authordate" },
                { "name": "normal" }
            ]
        }]
    });
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "-authordate");
    assert_eq!(out[0].symbol, None); // not stay (a plain command/value)
    assert_eq!(out[1].text, "normal");
    assert_eq!(out[1].symbol, None);
}

#[test]
fn mount_items_mounts_only_direct_children() {
    // No recursion: children with their own next/option arrays are not expanded.
    let script = r#"
    local cs = {}
    psc.add(cs, psc.mount_items({ "next", "config", "next" }))
    return psc.merge(cs)
"#;
    let mut c = nested_manifest_ctx();
    c.manifest = serde_json::json!({
        "next": [{
            "name": "config",
            "next": [
                { "name": "build", "option": [
                    { "name": "--output", "next": [ { "name": "<DIR>" } ] },
                    { "name": "--force" }
                ] }
            ]
        }]
    });
    let out = run_hook(&c, script, &empty_static()).unwrap();
    // Only `build` is mounted (its option array is not recursed); no symbols are computed.
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["build"]);
    assert_eq!(out[0].symbol, None);
}

#[test]
fn mount_items_source_option_mounts_option_array() {
    // A trailing "option" segment as source: mount the node's option array's direct children.
    let script = r#"
    local cs = {}
    psc.add(cs, psc.mount_items({ "next", "config", "flags", "option" }))
    return psc.merge(cs)
"#;
    let mut c = nested_manifest_ctx();
    c.manifest = serde_json::json!({
        "next": [{
            "name": "config",
            "next": [
                { "name": "flags", "option": [
                    { "name": "--all" },
                    { "name": "--output", "next": [ { "name": "<DIR>" } ] }
                ] }
            ]
        }]
    });
    let out = run_hook(&c, script, &empty_static()).unwrap();
    // Direct children of flags.option: --all, --output (no recursion into --output's next).
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["--all", "--output"]);
    for item in &out {
        assert_eq!(item.symbol, None);
    }
}

#[test]
fn mount_items_roots_from_any_top_level_field() {
    // The path starts at the manifest's root object: top-level fields can be custom ones like info
    let script = r#"
    local cs = {}
    psc.add(cs, psc.mount_items({ "info", "config", "next" }))
    return psc.merge(cs)
"#;
    let mut c = nested_manifest_ctx();
    c.manifest = serde_json::json!({
        "info": {
            "config": {
                "next": [
                    { "name": "enable_tip", "tip": "Show tip" },
                    { "name": "language" }
                ]
            }
        }
    });
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out.len(), 2);
    assert_eq!(out[0].text, "enable_tip");
    assert_eq!(out[0].tip.as_deref(), Some("Show tip"));
    assert_eq!(out[1].text, "language");
}

#[test]
fn mount_items_rejects_paths_without_source_last() {
    // The last segment is neither next nor option → invalid path, nothing is mounted
    let script = r#"
    local cs = {}
    psc.add(cs, psc.mount_items({ "next", "config", "set" }))
    return psc.merge(cs)
"#;
    let out = run_hook(&nested_manifest_ctx(), script, &empty_static()).unwrap();
    assert_eq!(out.len(), 0);
    // A source-only path (no navigation segments) also yields nothing
    let script2 = r#"
    local cs = {}
    psc.add(cs, psc.mount_items({ "next", "next" }))
    return psc.merge(cs)
"#;
    let out2 = run_hook(&nested_manifest_ctx(), script2, &empty_static()).unwrap();
    assert_eq!(out2.len(), 0);
}

#[test]
fn nil_return_keeps_static() {
    let script = "return nil";
    let static_items = vec![LuaItem {
        text: "add".into(),
        ..Default::default()
    }];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "add");
}

#[test]
fn add_skips_empty_names() {
    let script = r#"
    local cs = {}
    psc.add(cs, { name = "" })
    psc.add(cs, { name = "   " })
    psc.add(cs, { name = "valid", tip = "tip" })
    return psc.merge(cs)
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "valid");
    assert_eq!(out[0].tip.as_deref(), Some("tip"));
}

#[test]
fn add_defaults_tip_to_name() {
    let script = r#"
    local cs = {}
    psc.add(cs, { name = "branch" })
    return psc.merge(cs)
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].tip.as_deref(), Some("branch"));
}

#[cfg(windows)]
#[test]
fn run_items_adds_each_line_with_default_tip() {
    let script = r#"
    local cs = {}
    psc.add(cs, psc.items(psc.run({ "cmd", "/c", "echo", "alpha" })))
    return psc.merge(cs)
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "alpha");
    assert_eq!(out[0].tip.as_deref(), Some("alpha"));
}

#[test]
fn ls_items_adds_dir_entries() {
    let dir = std::env::temp_dir().join("psc-lua-ls-items-test");
    let _ = std::fs::create_dir_all(dir.join("sub"));
    std::fs::write(dir.join("a.md"), "").unwrap();
    let script = format!(
        r#"
    local cs = {{}}
    psc.add(cs, psc.items(psc.ls('{}'), function(e) if e.is_dir then return {{ name = e.name }} end end))
    return psc.merge(cs)
"#,
        dir.to_string_lossy().replace('\\', "/")
    );
    let out = run_hook(&ctx(), &script, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "sub");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn item_and_join_build_dynamic_list() {
    let script = r#"
    local cs = {}
    psc.add(cs, { name = "commit", tip = "commit changes" })
    psc.add(cs, { name = "checkout", tip = "switch branch", symbol = "switch" })
    return psc.merge(cs)
"#;
    let static_items = vec![LuaItem {
        text: "stash".into(),
        ..Default::default()
    }];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["commit", "checkout", "stash"]);
    assert_eq!(out[1].symbol.as_deref(), Some("switch"));
    assert_eq!(out[0].tip.as_deref(), Some("commit changes"));
}

#[test]
fn dynamic_items_carry_usage_and_example() {
    let script = r#"
    local cs = {}
    psc.add(cs, { name = "archive", tip = "create archive", usage = "archive|a", example = "a out.7z  # create an archive" })
    psc.add(cs, { name = "extract", usage = "extract|e", example = "e demo.7z  # extract" })
    return psc.merge(cs)
"#;
    let static_items = vec![LuaItem {
        text: "help".into(),
        ..Default::default()
    }];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    assert_eq!(out.len(), 3);
    // psc.add with explicit usage/example
    assert_eq!(out[0].text, "archive");
    assert_eq!(out[0].tip.as_deref(), Some("create archive"));
    assert_eq!(out[0].usage.as_deref(), Some("archive|a"));
    assert_eq!(
        out[0].example.as_deref(),
        Some("a out.7z  # create an archive")
    );
    // psc.add defaults tip to name when absent
    assert_eq!(out[1].text, "extract");
    assert_eq!(out[1].usage.as_deref(), Some("extract|e"));
    assert_eq!(out[1].example.as_deref(), Some("e demo.7z  # extract"));
    assert_eq!(out[1].tip.as_deref(), Some("extract")); // add defaults tip = name
                                                        // Static items are unaffected (renamed to avoid colliding with used tokens and repeat-filtering)
    assert_eq!(out[2].text, "help");
    assert!(out[2].usage.is_none());
    assert!(out[2].example.is_none());
}

#[test]
fn cmds_and_current_context() {
    let script = r#"
    local cs = {}
    if psc.cmds[1] == "checkout" then
        psc.add(cs, { name = "main" })
    elseif psc.cmds[1] == "stash" then
        psc.add(cs, { name = "stash@{0}" })
    end
    if psc.current.option_like then return nil end
    return psc.merge(cs)
"#;
    // cmds = ["stash"] → hits the stash branch
    let mut c = ctx();
    c.path = vec!["stash".into()];
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert!(out.iter().any(|i| i.text == "stash@{0}"));

    // current is option-like → return nil (static only)
    c.pending = Pending {
        text: Some("-x".into()),
        kind: Some("option".into()),
        canonical: None,
        option_like: true,
    };
    let out2 = run_hook(&c, script, &empty_static()).unwrap();
    assert!(out2.is_empty());
}

#[test]
fn json_and_env_api() {
    let dir = std::env::temp_dir().join("psc-lua-test");
    let _ = std::fs::create_dir_all(&dir);
    let pkg = dir.join("package.json");
    std::fs::write(&pkg, r#"{"scripts":{"dev":"vite","build":"tsc"}}"#).unwrap();
    let script = r#"
    local cs = {}
    local pkg = psc.json(pkg_path)
    for k, _ in pairs(pkg.scripts or {}) do psc.add(cs, { name = k }) end
    return psc.merge(cs)
"#;
    // Inject the path by directly replacing the placeholder
    let path_escaped = pkg.to_string_lossy().replace('\\', "/");
    let script = script.replace("pkg_path", &format!("\"{path_escaped}\""));
    let out = run_hook(&ctx(), &script, &empty_static()).unwrap();
    let mut texts: Vec<String> = out.iter().map(|i| i.text.clone()).collect();
    texts.sort(); // Lua pairs order is unspecified, so sort before asserting
    assert_eq!(texts, vec!["build", "dev"]);

    // cwd() returns a non-empty value
    let script_cwd = "if psc.cwd == '' then return nil end\nreturn { { name = 'ok' } }";
    let out_cwd = run_hook(&ctx(), script_cwd, &empty_static()).unwrap();
    assert_eq!(out_cwd[0].text, "ok");

    // env API
    let script2 = "local e = psc.env('PSCOMPLETIONS_LUA_TEST')\nif e then return { { name = e } } end\nreturn nil";
    std::env::set_var("PSCOMPLETIONS_LUA_TEST", "hello");
    let out2 = run_hook(&ctx(), script2, &empty_static()).unwrap();
    assert_eq!(out2[0].text, "hello");
    let _ = std::fs::remove_dir_all(&dir);
}

#[cfg(windows)]
#[test]
fn run_command_windows() {
    let script = r#"
    local cs = {}
    for _, l in ipairs(psc.run({"cmd", "/c", "echo", "alpha"}, {})) do
        psc.add(cs, { name = l:gsub("\r", "") })
    end
    return psc.merge(cs)
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "alpha");
}

#[cfg(not(windows))]
#[test]
fn run_command_unix() {
    let script = r#"
    local cs = {}
    for _, l in ipairs(psc.run({"echo", "alpha"}, {})) do
        psc.add(cs, { name = l })
    end
    return psc.merge(cs)
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "alpha");
}

#[test]
fn run_with_shell_option() {
    // `shell = true` routes the command through the platform shell (`cmd /c` on Windows,
    // `sh -c` elsewhere) — a built-in shell keyword is used so it works even where the
    // bare command would not be directly spawnable.
    let script = if cfg!(windows) {
        r#"
    local cs = {}
    for _, l in ipairs(psc.run({"echo", "shell-ok"}, { shell = true })) do
        psc.add(cs, { name = l:gsub("\r", "") })
    end
    return psc.merge(cs)
"#
    } else {
        r#"
    local cs = {}
    for _, l in ipairs(psc.run({"echo", "shell-ok"}, { shell = true })) do
        psc.add(cs, { name = l })
    end
    return psc.merge(cs)
"#
    };
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "shell-ok");
}

#[test]
fn run_with_shell_option_and_quoted_arg() {
    // An argument containing whitespace must stay one word through the shell. On Windows,
    // `cmd /c` echoes the quoted token verbatim (`"two words"`); on POSIX shells the quotes
    // are consumed. Assert the word is present either way.
    let script = if cfg!(windows) {
        r#"
    local v = psc.run({"echo", "two words"}, { shell = true })
    local line = v and v[1] or ""
    if line:find("two words") then return { { name = "ok" } } end
    return { { name = "unexpected: " .. line } }
"#
    } else {
        r#"
    local v = psc.run({"echo", "two words"}, { shell = true })
    if v and v[1] == "two words" then return { { name = "ok" } } end
    return { { name = "unexpected" } }
"#
    };
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");
}

#[test]
fn run_uses_hook_cwd_when_not_specified() {
    // `psc.run` without a `cwd` option must run in the hook's working directory (the user's
    // current location), NOT the engine process's inherited cwd — the two can differ after a
    // `cd` in the host (process-level CurrentDirectory lags `$PWD` on some hosts).
    let dir = std::env::temp_dir().join("psc-run-cwd-test");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let mut c = ctx();
    c.cwd = dir.to_string_lossy().to_string();
    let script = if cfg!(windows) {
        r#"
    local v = psc.run({ "cmd", "/c", "cd" })
    local joined = table.concat(v or {}, "|")
    if joined:find("psc%-run%-cwd%-test") then return { { name = "ok" } } end
    return { { name = "got: " .. joined } }
"#
    } else {
        r#"
    local v = psc.run({ "pwd" })
    local joined = table.concat(v or {}, "|")
    if joined:find("psc%-run%-cwd%-test") then return { { name = "ok" } } end
    return { { name = "got: " .. joined } }
"#
    };
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");
    // An explicit `cwd` option still overrides the hook cwd.
    let other = std::env::temp_dir().join("psc-run-cwd-other");
    let _ = std::fs::remove_dir_all(&other);
    std::fs::create_dir_all(&other).unwrap();
    let other_s = serde_json::to_string(&other.to_string_lossy()).unwrap();
    let script2 = if cfg!(windows) {
        format!(
            r#"
    local v = psc.run({{ "cmd", "/c", "cd" }}, {{ cwd = {other_s} }})
    local joined = table.concat(v or {{}}, "|")
    if joined:find("psc%-run%-cwd%-other") then return {{ {{ name = "ok" }} }} end
    return {{ {{ name = "got: " .. joined }} }}
"#
        )
    } else {
        format!(
            r#"
    local v = psc.run({{ "pwd" }}, {{ cwd = {other_s} }})
    local joined = table.concat(v or {{}}, "|")
    if joined:find("psc%-run%-cwd%-other") then return {{ {{ name = "ok" }} }} end
    return {{ {{ name = "got: " .. joined }} }}
"#
        )
    };
    let out2 = run_hook(&c, &script2, &empty_static()).unwrap();
    assert_eq!(out2[0].text, "ok");
    let _ = std::fs::remove_dir_all(&dir);
    let _ = std::fs::remove_dir_all(&other);
}

#[test]
fn ls_and_glob_api() {
    let dir = std::env::temp_dir().join("psc-lua-ls-test");
    let _ = std::fs::create_dir_all(dir.join("sub"));
    std::fs::write(dir.join("a.md"), "").unwrap();
    std::fs::write(dir.join("b.txt"), "").unwrap();
    let script = format!(
        r#"
    local cs = {{}}
    for _, e in ipairs(psc.ls('{}')) do
        if not e.is_dir then psc.add(cs, {{ name = e.name }}) end
    end
    return psc.merge(cs)
"#,
        dir.to_string_lossy().replace('\\', "/")
    );
    let out = run_hook(&ctx(), &script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert!(texts.contains(&"a.md"));
    assert!(texts.contains(&"b.txt"));

    // glob
    let script2 = format!(
            "local g = psc.glob('{}/*.md')\nlocal cs = {{}}\nfor _, p in ipairs(g) do psc.add(cs, {{ name = p }}) end\nreturn psc.merge(cs)",
            dir.to_string_lossy().replace('\\', "/")
        );
    let out2 = run_hook(&ctx(), &script2, &empty_static()).unwrap();
    assert!(out2[0].text.ends_with("a.md"));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn glob_pattern_normalizes_backslashes_on_windows() {
    #[cfg(windows)]
    {
        // Windows: native backslashes are normalized to `/`; forward slashes stay as-is
        assert_eq!(normalize_glob_pattern(r"dir\*.json"), "dir/*.json");
        assert_eq!(normalize_glob_pattern("dir/*.json"), "dir/*.json");
    }
    #[cfg(not(windows))]
    {
        // Non-Windows: `\` is a literal character, no replacement
        assert_eq!(normalize_glob_pattern(r"dir\*.json"), r"dir\*.json");
    }
}

#[test]
fn run_format_returns_nil_on_failed_command() {
    // A failing command produces no parseable stdout -> nil (strict failure semantics).
    let script = r#"
    local v = psc.run({ "definitely-not-a-real-command-psc-test" }, { format = "json" })
    if v == nil then return { { name = "nil-ok" } } end
    return { { name = "unexpected" } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "nil-ok");
}

#[test]
fn run_without_format_returns_nil_on_failure() {
    // Strict failure semantics: a spawn failure yields nil even without `format`.
    let script = r#"
    local v = psc.run({ "definitely-not-a-real-command-psc-test" })
    if v == nil then return { { name = "nil-ok" } } end
    return { { name = "unexpected" } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "nil-ok");
}

#[test]
fn run_returns_nil_on_nonzero_exit() {
    // Strict failure semantics: a command that runs but exits non-zero must yield nil, even
    // when it printed output before failing.
    let script = if cfg!(windows) {
        r#"
    local v = psc.run({ "cmd", "/c", "echo junk & exit 1" })
    if v == nil then return { { name = "nil-ok" } } end
    return { { name = "unexpected" } }
"#
    } else {
        r#"
    local v = psc.run({ "sh", "-c", "echo junk; exit 1" })
    if v == nil then return { { name = "nil-ok" } } end
    return { { name = "unexpected" } }
"#
    };
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "nil-ok");
}

#[test]
fn run_keeps_output_on_zero_exit() {
    // A successful command still returns its stdout lines.
    let script = if cfg!(windows) {
        r#"
    local v = psc.run({ "cmd", "/c", "echo hello" })
    if v ~= nil and v[1] == "hello" then return { { name = "ok" } } end
    return { { name = "unexpected" } }
"#
    } else {
        r#"
    local v = psc.run({ "sh", "-c", "echo hello" })
    if v ~= nil and v[1] == "hello" then return { { name = "ok" } } end
    return { { name = "unexpected" } }
"#
    };
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");
}

#[test]
fn ls_returns_nil_on_missing_directory() {
    // Strict failure semantics: a missing directory yields nil; an empty dir yields an array.
    let dir = std::env::temp_dir().join("psc-ls-missing-test");
    let _ = std::fs::remove_dir_all(&dir);
    let missing = format!("{}/no-such-dir", dir.to_string_lossy().replace('\\', "/"));
    let script = format!(
        r#"
    local v = psc.ls("{missing}")
    if v == nil then return {{ {{ name = "nil-ok" }} }} end
    return {{ {{ name = "unexpected" }} }}
"#
    );
    let out = run_hook(&ctx(), &script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "nil-ok");
}

#[test]
fn which_handle_missing_paths() {
    let lua = mlua::Lua::new();
    // Unknown command in PATH -> nil.
    assert!(
        api_which(&lua, "no-such-cmd-psc-test".into())
            .unwrap()
            .is_none(),
        "unknown command yields nil"
    );
}

#[cfg(windows)]
#[test]
fn run_format_invalid_json_returns_nil() {
    let script = r#"
    local v = psc.run({ "cmd", "/c", "echo", "not-json" }, { format = "json" })
    if v == nil then return { { name = "nil-ok" } } end
    return { { name = "unexpected" } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "nil-ok");
}

#[test]
fn glob_returns_nil_on_invalid_pattern() {
    let script = r#"
    local list = psc.glob("[")
    if list == nil then return { { name = "nil-ok" } } end
    return { { name = "unexpected" } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "nil-ok");
}

#[test]
fn all_hooks_parse() {
    // Syntax-check every hooks.lua in the repo so a bad edit fails here, not at runtime.
    let lua = new_sandbox_lua().unwrap();
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../completions");
    let mut count = 0;
    let mut failures = Vec::new();
    let entries = std::fs::read_dir(&root).unwrap();
    for e in entries.flatten() {
        let dir = e.path();
        let hook = dir.join("hooks.lua");
        if hook.exists() {
            let text = std::fs::read_to_string(&hook).unwrap();
            if text.trim().is_empty() {
                continue; // e.g. .psc-link-completion placeholder
            }
            if let Err(err) = lua.load(&text).set_name("hooks.lua").into_function() {
                failures.push(format!(
                    "{}: {err}",
                    dir.file_name().unwrap().to_string_lossy()
                ));
            }
            count += 1;
        }
    }
    assert!(count > 0, "expected to find hooks.lua files");
    assert!(
        failures.is_empty(),
        "hooks fail to parse:\n{}",
        failures.join("\n")
    );
}

#[test]
fn read_batch_and_json_batch_parse_in_parallel() {
    let dir = std::env::temp_dir().join("psc-batch-test");
    let _ = std::fs::create_dir_all(&dir);
    std::fs::write(dir.join("a.json"), r#"{"k":"va"}"#).unwrap();
    std::fs::write(dir.join("b.json"), r#"{"k":"vb"}"#).unwrap();
    std::fs::write(dir.join("a.txt"), "hello").unwrap();
    let dir_s = dir.to_string_lossy().replace('\\', "/");

    // json_batch returns { [path] = table }
    let script = format!(
        r#"
    local m = psc.json_batch({{ "{}/a.json", "{}/b.json" }})
    if m["{}/a.json"] == nil or m["{}/a.json"].k ~= "va" then return nil end
    if m["{}/b.json"] == nil or m["{}/b.json"].k ~= "vb" then return nil end
    return {{ {{ name = "ok" }} }}
"#,
        dir_s, dir_s, dir_s, dir_s, dir_s, dir_s
    );
    let out = run_hook(&ctx(), &script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");

    // read_batch returns { [path] = content }
    let script2 = format!(
        r#"
    local m = psc.read_batch({{ "{}/a.txt", "{}/missing.txt" }})
    if m["{}/a.txt"] ~= "hello" then return nil end
    if m["{}/missing.txt"] ~= nil then return nil end
    return {{ {{ name = "ok" }} }}
"#,
        dir_s, dir_s, dir_s, dir_s
    );
    let out2 = run_hook(&ctx(), &script2, &empty_static()).unwrap();
    assert_eq!(out2[0].text, "ok");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn toml_and_yaml_parse() {
    let dir = std::env::temp_dir().join("psc-format-test");
    let _ = std::fs::create_dir_all(&dir);
    std::fs::write(dir.join("c.toml"), "name = \"demo\"\nversion = 1\n").unwrap();
    std::fs::write(dir.join("d.yaml"), "name: demo\nversion: 1\n").unwrap();
    let dir_s = dir.to_string_lossy().replace('\\', "/");

    // psc.toml parses a TOML file
    let script = format!(
        r#"
    local t = psc.toml("{}/c.toml")
    if not t or t.name ~= "demo" or t.version ~= 1 then return nil end
    return {{ {{ name = "ok" }} }}
"#,
        dir_s
    );
    let out = run_hook(&ctx(), &script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");

    // psc.yaml parses a YAML file
    let script2 = format!(
        r#"
    local y = psc.yaml("{}/d.yaml")
    if not y or y.name ~= "demo" or y.version ~= 1 then return nil end
    return {{ {{ name = "ok" }} }}
"#,
        dir_s
    );
    let out2 = run_hook(&ctx(), &script2, &empty_static()).unwrap();
    assert_eq!(out2[0].text, "ok");

    // toml_batch / yaml_batch parse multiple in parallel
    std::fs::write(dir.join("e.toml"), "name = \"e\"\n").unwrap();
    std::fs::write(dir.join("f.yaml"), "name: f\n").unwrap();
    let script3 = format!(
        r#"
    local mt = psc.toml_batch({{ "{}/c.toml", "{}/e.toml" }})
    if not mt["{}/e.toml"] or mt["{}/e.toml"].name ~= "e" then return nil end
    local my = psc.yaml_batch({{ "{}/d.yaml", "{}/f.yaml" }})
    if not my["{}/f.yaml"] or my["{}/f.yaml"].name ~= "f" then return nil end
    return {{ {{ name = "ok" }} }}
"#,
        dir_s, dir_s, dir_s, dir_s, dir_s, dir_s, dir_s, dir_s
    );
    let out3 = run_hook(&ctx(), &script3, &empty_static()).unwrap();
    assert_eq!(out3[0].text, "ok");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn toml_yaml_and_env_return_nil_on_missing() {
    let dir = std::env::temp_dir().join("psc-fmt-missing-test");
    let _ = std::fs::remove_dir_all(&dir);
    let missing = format!("{}/no-such.toml", dir.to_string_lossy().replace('\\', "/"));
    let script = format!(
        r#"
    local t = psc.toml("{missing}")
    local y = psc.yaml("{missing}")
    local e = psc.env("PSC_DEFINITELY_UNSET_VAR_XYZ")
    if t ~= nil then return nil end
    if y ~= nil then return nil end
    if e ~= nil then return nil end
    return {{ {{ name = "nil-ok" }} }}
"#
    );
    let out = run_hook(&ctx(), &script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "nil-ok");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn ls_batch_lists_directories_in_parallel() {
    let dir = std::env::temp_dir().join("psc-lsbatch-test");
    let _ = std::fs::create_dir_all(dir.join("sub1"));
    let _ = std::fs::create_dir_all(dir.join("sub2"));
    let dir_s = dir.to_string_lossy().replace('\\', "/");
    let script = format!(
        r#"
    local m = psc.ls_batch({{ "{}", "{}" }})
    if not m[1] then return nil end
    local found1, found2 = false, false
    for _, e in ipairs(m[1]) do
        if e.name == "sub1" then found1 = true end
        if e.name == "sub2" then found2 = true end
    end
    if not (found1 and found2) then return nil end
    if m[2] == nil then return nil end
    return {{ {{ name = "ok" }} }}
"#,
        dir_s, dir_s
    );
    let out = run_hook(&ctx(), &script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn batch_missing_entries_yield_nil() {
    let dir = std::env::temp_dir().join("psc-batch-missing-test");
    let _ = std::fs::create_dir_all(&dir);
    std::fs::write(dir.join("ok.json"), r#"{"k":"v"}"#).unwrap();
    let dir_s = dir.to_string_lossy().replace('\\', "/");
    let missing = format!("{dir_s}/missing.json");
    let missing_txt = format!("{dir_s}/missing.txt");
    let missing_dir = format!("{dir_s}/missing-dir");

    // json_batch: missing/unparseable file -> nil (strict failure semantics)
    let script = format!(
        r#"
    local m = psc.json_batch({{ "{dir_s}/ok.json", "{missing}" }})
    if m["{missing}"] ~= nil then return nil end
    if m["{dir_s}/ok.json"].k ~= "v" then return nil end
    return {{ {{ name = "ok" }} }}
"#
    );
    let out = run_hook(&ctx(), &script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");

    // read_batch: missing file -> nil
    let script2 = format!(
        r#"
    local m = psc.read_batch({{ "{missing_txt}" }})
    if m["{missing_txt}"] ~= nil then return nil end
    return {{ {{ name = "ok" }} }}
"#
    );
    let out2 = run_hook(&ctx(), &script2, &empty_static()).unwrap();
    assert_eq!(out2[0].text, "ok");

    // ls_batch: missing dir -> nil
    let script3 = format!(
        r#"
    local m = psc.ls_batch({{ "{missing_dir}" }})
    if m[1] ~= nil then return nil end
    return {{ {{ name = "ok" }} }}
"#
    );
    let out3 = run_hook(&ctx(), &script3, &empty_static()).unwrap();
    assert_eq!(out3[0].text, "ok");

    let _ = std::fs::remove_dir_all(&dir);
}

#[cfg(windows)]
#[test]
fn run_batch_runs_commands_in_parallel() {
    let script = r#"
    local m = psc.run_batch({ {"cmd", "/c", "echo", "one"}, {"cmd", "/c", "echo", "two"} })
    if not m[1] or not m[2] then return nil end
    if m[1][1]:gsub("\r", "") ~= "one" then return nil end
    if m[2][1]:gsub("\r", "") ~= "two" then return nil end
    return { { name = "ok" } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");
}

#[cfg(not(windows))]
#[test]
fn run_batch_runs_commands_in_parallel() {
    let script = r#"
    local m = psc.run_batch({ {"echo", "one"}, {"echo", "two"} })
    if not m[1] or not m[2] then return nil end
    if m[1][1] ~= "one" then return nil end
    if m[2][1] ~= "two" then return nil end
    return { { name = "ok" } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");
}

#[cfg(windows)]
#[test]
fn run_capture_fd() {
    // New API: capture_fd captures an extra fd (e.g. 8 for Python argcomplete) via 8>&1.
    // Should work cross-platform without manual shell strings.
    let script = r#"
    local c = psc.which("aws_completer")
    if not c then return { { name = "no-completer" } } end
    local v = psc.run({ c }, {
        shell = true,
        capture_fd = 8,
        timeout = 8000,
        env = {
            COMP_LINE = "aws s3",
            COMP_POINT = "6",
            _ARGCOMPLETE = "1",
            _ARGCOMPLETE_SHELL = "fish",
            _ARGCOMPLETE_SUPPRESS_SPACE = "1",
        }
    })
    if not v or #v == 0 then return { { name = "empty" } } end
    return { { name = "ok" } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");
}

#[test]
fn split_and_input_helpers() {
    // psc.split
    let script = r#"
    local parts = psc.split("a,b,c", ",")
    if #parts ~= 3 or parts[1] ~= "a" or parts[3] ~= "c" then return nil end
    return { { name = "ok" } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");

    // psc.join: the complement of split — array joined by sep, string returned as-is
    let script2 = r#"
    local joined = psc.join({ "a", "b", "c" }, ",")
    local single = psc.join("text")
    local arr_nl = psc.join({ "x", "y" }, "\n")
    return {
        { name = joined .. "|" .. single .. "|" .. arr_nl },
    }
"#;
    let out2 = run_hook(&ctx(), script2, &empty_static()).unwrap();
    assert_eq!(out2[0].text, "a,b,c|text|x\ny");

    // typed / typed_unknown / has_unknown against the ctx tokens ("list" is a known token)
    let script3 = r#"
    if not psc.has_unknown() then
        return { { name = "no-unknown" } }
    end
    return { { name = "has-unknown" } }
"#;
    // ctx() tokens have no unknown -> has_unknown false
    let out3 = run_hook(&ctx(), script3, &empty_static()).unwrap();
    assert_eq!(out3[0].text, "no-unknown");

    // A context with an unknown token
    let mut c = ctx();
    c.tokens.push(Token {
        text: "somevalue".into(),
        kind: "unknown".into(),
        canonical: None,
    });
    let out4 = run_hook(&c, script3, &empty_static()).unwrap();
    assert_eq!(out4[0].text, "has-unknown");
    // typed("somevalue") sees the value token
    let script4 = r#"
    if not psc.typed("somevalue") then return nil end
    if not psc.typed_unknown("somevalue") then return nil end
    if psc.typed_unknown("list") then return nil end
    return { { name = "ok" } }
"#;
    let out5 = run_hook(&c, script4, &empty_static()).unwrap();
    assert_eq!(out5[0].text, "ok");
    // typed matches the canonical name, so an alias counts as its main option
    let mut c2 = ctx();
    c2.tokens.push(Token {
        text: "-a".into(),
        kind: "option".into(),
        canonical: Some("--all".into()),
    });
    let script5 = r#"
    if not psc.typed("--all") then return nil end
    if psc.typed("-a") then return nil end
    return { { name = "ok" } }
"#;
    let out6 = run_hook(&c2, script5, &empty_static()).unwrap();
    assert_eq!(out6[0].text, "ok");
}

#[test]
fn context_values_data_and_platform() {
    // psc._data surfaces the module data
    let script = r#"
    if psc._data == nil then return nil end
    return { { name = tostring(type(psc._data)) } }
"#;
    let mut c = ctx();
    c.data = serde_json::json!({ "list": ["git"] });
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "table");

    // psc.platform is one of windows/macos/linux
    let script2 = r#"
    local p = psc.platform
    if p ~= "windows" and p ~= "macos" and p ~= "linux" then return nil end
    return { { name = p } }
"#;
    let out2 = run_hook(&ctx(), script2, &empty_static()).unwrap();
    assert!(out2[0].text == "windows" || out2[0].text == "macos" || out2[0].text == "linux");
}

#[test]
fn psc_log_writes_formatted_values() {
    let dir = std::env::temp_dir().join("psc-log-test");
    let _ = std::fs::remove_dir_all(&dir);
    let mut c = ctx();
    c.log_dir = dir.to_string_lossy().to_string();
    let script = r#"
    psc.log("start")
    psc.log(42)
    psc.log(true)
    psc.log("hello")
    psc.log(nil)
    psc.log({ name = "git", count = 3, tags = { "a", "b" } }, "branches")
    return { { name = "ok" } }
"#;
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "ok");

    // All values land in debug.log (multi-argument calls print every value, one per line).
    let debug = std::fs::read_to_string(dir.join("debug.log")).unwrap();
    assert!(debug.contains("\"start\""));
    assert!(debug.contains("42"));
    assert!(debug.contains("true"));
    assert!(debug.contains("\"hello\""));
    assert!(debug.contains("nil"));
    assert!(debug.contains("name = \"git\""));
    assert!(debug.contains("[1] = \"a\""));
    assert!(debug.contains("count = 3"));
    assert!(debug.contains("tags = {"));
    assert!(debug.contains("\"branches\""));

    // A multi-return call prints every returned value, none is mistaken for a file name.
    let script2 = r#"
    local function two() return "x", "y" end
    psc.log(two())
    return { { name = "ok2" } }
"#;
    run_hook(&c, script2, &empty_static()).unwrap();
    let debug2 = std::fs::read_to_string(dir.join("debug.log")).unwrap();
    assert!(debug2.contains("\"x\""));
    assert!(debug2.contains("\"y\""));

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn add_keeps_name_key_in_dyn() {
    let script = r#"
    local cs = {}
    psc.add(cs, { name = "alpha", tip = "t" })
    return { { name = tostring(cs[1].name or "<nil>") .. ":" .. tostring(cs[1].text or "<nil>") } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "alpha:<nil>");
}

#[test]
fn add_skips_items_without_name() {
    let script = r#"
    local cs = {}
    local n1 = psc.add(cs, { text = "stray" })
    local n2 = psc.add(cs, { "raw-string", { name = "ok" } })
    return { { name = tostring(n1) .. "," .. tostring(n2) .. ",cs=" .. tostring(#cs) } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "0,1,cs=1");
}

#[test]
fn filter_keeps_elements_for_truthy_predicates() {
    // Generic filter: keep the elements for which fn is truthy (compacted).
    let script = r#"
    local kept = psc.filter({ "a", "b", "c" }, function(s) return s ~= "b" end)
    return { { name = table.concat(kept, ",") } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "a,c");
}

#[test]
fn filter_keeps_items_by_name_with_fn() {
    // The former name-matching filter is expressed with a generic fn (the predicate
    // inspects the item's name; psc.eq is case-insensitive).
    let script = r#"
    return psc.filter(completions, function(it) return psc.eq(it.name, "b") end)
"#;
    let static_items = vec![
        LuaItem {
            text: "a".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
        LuaItem {
            text: "b".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
        LuaItem {
            text: "c".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
    ];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["b"]);
}

#[test]
fn filter_matches_lua_pattern_with_fn() {
    let script = r#"
    return psc.filter(completions, function(it) return it.name:match("^%-%-") end)
"#;
    let static_items = vec![
        LuaItem {
            text: "--force".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
        LuaItem {
            text: "-f".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
        LuaItem {
            text: "--all".into(),
            tip: None,
            usage: None,
            example: None,
            symbol: None,
            repeat: 0,
        },
    ];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["--force", "--all"]);
}

#[test]
fn filter_treats_only_nil_and_false_as_dropped() {
    // Lua truthiness: 0, "" and empty tables are all truthy; nil and false are dropped.
    // (Avoid `#` on the sparse source array — count the filtered result directly.)
    let script = r#"
    local kept = psc.filter({ 0, "", false, "x", true, {} }, function(v)
        return v
    end)
    local n = 0
    for _ in ipairs(kept) do n = n + 1 end
    return { { name = tostring(n) } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "5");
}

#[test]
fn contains_matches_case_insensitively_by_default() {
    let script = r#"
    local list = { "Alpha", "Beta", "gamma" }
    return {
        { name = tostring(psc.contains(list, "alpha")) },
        { name = tostring(psc.contains(list, "BETA")) },
        { name = tostring(psc.contains(list, "delta")) },
        { name = tostring(psc.contains(list, "GAMMA", { case_sensitive = true })) },
        { name = tostring(psc.contains(list, "gamma", { case_sensitive = true })) },
    }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["true", "true", "false", "false", "true"]);
}

#[test]
fn contains_with_nil_never_matches() {
    // Common hook pattern: `psc.contains(list, cmd0)` where cmd0 is nil at the root level.
    let script = r#"
    return {
        { name = tostring(psc.contains({ "add", "rm" }, nil)) },
        { name = tostring(psc.contains({ "add", "rm" }, nil, { case_sensitive = true })) },
    }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["false", "false"]);
}

#[test]
fn eq_tolerates_nil_arguments() {
    // nil arguments never match; the hook must not crash when psc.cmds[1] is undefined.
    let script = r#"
    local undefined = psc.cmds[99]
    return {
        { name = tostring(psc.eq(undefined, "run")) },
        { name = tostring(psc.eq("run", undefined)) },
        { name = tostring(psc.eq(undefined, undefined)) },
        { name = tostring(psc.eq(undefined, "run", { case_sensitive = true })) },
    }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["false", "false", "false", "false"]);
}

#[test]
fn contains_pattern_mode_handles_string_and_array() {
    // opts.pattern: a string is matched as a Lua pattern; an array matches when any element does.
    let script = r#"
    return {
        { name = tostring(psc.contains("A-New-Link", "A%-New%-Link", { pattern = true })) },
        { name = tostring(psc.contains("plain", "A%-New%-Link", { pattern = true })) },
        { name = tostring(psc.contains({ "cmd1", "A-New-Link" }, "A%-New%-Link", { pattern = true })) },
        { name = tostring(psc.contains({ "cmd1", "cmd2" }, "A%-New%-Link", { pattern = true })) },
    }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["true", "false", "true", "false"]);
}

#[test]
fn items_skips_empty_and_blank_strings() {
    // `psc.items` without fn uses each string element as the name; empty/blank strings are
    // skipped (they carry no usable name).
    let script = r#"
    local items = psc.items({ "a", "", "b", "   ", "c" })
    return { { name = #items .. ":" .. items[1].name .. items[2].name .. items[3].name } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "3:abc");
}

#[test]
fn map_transforms_each_element() {
    let script = r#"
    local doubled = psc.map({ 1, 2, 3 }, function(n) return n * 2 end)
    return { { name = doubled[1] .. "," .. doubled[2] .. "," .. doubled[3] } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "2,4,6");
}

#[test]
fn concat_merges_arrays() {
    let script = r#"
    local merged = psc.concat({ "a", "b" }, { "c" }, { "d", "e" })
    return { { name = table.concat(merged, "-") } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "a-b-c-d-e");
}

#[test]
fn trim_modes() {
    let script = r#"
    return {
        { name = psc.trim("  x  ") },
        { name = psc.trim("  x  ", { mode = "start" }) },
        { name = psc.trim("  x  ", { mode = "end" }) },
    }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["x", "x  ", "  x"]);
}

#[test]
fn eq_matches_case_insensitively_by_default() {
    // psc.eq compares two strings ignoring case by default; opts.case_sensitive makes it exact.
    let script = r#"
    return {
        { name = tostring(psc.eq("CHECKOUT", "checkout")) },
        { name = tostring(psc.eq("-B", "-b")) },
        { name = tostring(psc.eq("git", "npm")) },
        { name = tostring(psc.eq("CHECKOUT", "checkout", { case_sensitive = true })) },
        { name = tostring(psc.eq("-b", "-b", { case_sensitive = true })) },
    }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["true", "true", "false", "false", "true"]);
}

#[test]
fn exist_and_read_resolve_against_cwd() {
    let crate_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut c = ctx();
    c.cwd = crate_dir.to_string_lossy().to_string();
    let script = r#"
    local f = "Cargo.toml"
    return {
        { name = tostring(psc.exist(f)) },
        { name = tostring(psc.exist("definitely-missing-file.xyz")) },
        { name = tostring(psc.read(f):match("^%[package%]")) },
        { name = tostring(psc.read("definitely-missing-file.xyz")) },
    }
"#;
    let out = run_hook(&c, script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["true", "false", "[package]", "nil"]);
}

#[test]
fn all_apis_tolerate_nil_arguments() {
    // Every psc.* API must return a safe empty result (never a Lua error) when called with
    // nil arguments — hooks commonly pass `psc.cmds[1]` which is nil at the root level.
    let script = r#"
    local n = nil
    local ok, results = pcall(function()
        local r = {}
        r[#r+1] = tostring(psc.read(n))
        r[#r+1] = tostring(psc.exist(n))
        r[#r+1] = tostring(psc.ls(n))
        r[#r+1] = tostring(psc.glob(n))
        r[#r+1] = tostring(psc.json(n))
        r[#r+1] = tostring(psc.toml(n))
        r[#r+1] = tostring(psc.yaml(n))
        r[#r+1] = tostring(psc.which(n))
        r[#r+1] = tostring(psc.env(n))
        r[#r+1] = tostring(#(psc.json_batch(n) or {}))
        r[#r+1] = tostring(#(psc.read_batch(n) or {}))
        r[#r+1] = tostring(#(psc.ls_batch(n) or {}))
        r[#r+1] = tostring(#(psc.run(n) or {}))
        r[#r+1] = tostring(#(psc.run_batch(n) or {}))
        r[#r+1] = tostring(#(psc.split(n) or {}))
        r[#r+1] = tostring(#(psc.map(n, function(x) return x end) or {}))
        r[#r+1] = tostring(#(psc.concat(n) or {}))
        r[#r+1] = tostring(#(psc.filter(n, function(x) return x end) or {}))
        r[#r+1] = tostring(psc.contains({ "a", "b" }, n))
        r[#r+1] = tostring(#(psc.merge(n) or {}))
        r[#r+1] = tostring(psc.trim(n))
        r[#r+1] = tostring(psc.typed(n))
        r[#r+1] = tostring(psc.typed_unknown(n))
        r[#r+1] = tostring(#(psc.mount_items(n) or {}))
        psc.set_symbol(n, "switch")
        psc.set_tip(n, "tip")
        psc.add(n, { name = "x" })
        psc.eq(n, "run")
        return r
    end)
    return { { name = tostring(ok) }, { name = tostring(#results) }, { name = tostring(results) } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts[0], "true", "hook must not error, got: {texts:?}");
    assert_eq!(texts[1], "24", "expected 24 results, got: {texts:?}");
}

#[test]
fn psc_opts_exposes_canonical_options() {
    // `psc.opts` mirrors `psc.cmds`: canonical names of completed options in order; the
    // last one (`opts[#opts]`) replaces the old `psc.last_option`. Options never enter `cmds`.
    let script = r#"
    return {
        { name = tostring(#psc.opts) },
        { name = psc.opts[1] },
        { name = psc.opts[2] },
        { name = psc.opts[#psc.opts] },
        { name = tostring(#psc.cmds) },
        { name = psc.cmds[1] },
    }
"#;
    let mut c = ctx();
    c.opts = vec!["--move".into(), "--copy".into()];
    c.path = vec!["branch".into()];
    let out = run_hook(&c, script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(
        texts,
        vec!["2", "--move", "--copy", "--copy", "1", "branch"]
    );
}
