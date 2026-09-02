//! Tests for the Lua hooks runtime.

use super::api::{api_which, normalize_glob_pattern};
use super::runner::{new_sandbox_lua, run_hook_with_timeout};
use super::*;
use std::time::Duration;

fn ctx() -> HookContext {
    HookContext {
        cmd: "psc".into(),
        path: vec!["list".into()],
        layers: vec![("command".into(), "list".into())],
        typing: Typing::default(),
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
fn run_batch_subprocess_cut_short_by_global_deadline() {
    // Regression guard for the process-global deadline: while psc.run_batch blocks inside
    // a C function the VM instruction-count hook cannot fire, so the batch workers
    // themselves must observe the global budget and cut their subprocess short. Without
    // it this test stalls for the full per-command timeout before returning.
    //
    // NOTE on parallelism: the deadline is a process-global slot, and sibling hook tests
    // running in parallel overwrite/clear it around their own windows. That interference
    // is harmless in production (one hook per process) but can void THIS test's window,
    // so we retry: a clean attempt always unwinds right after the 300ms budget.
    #[cfg(windows)]
    let cmd = [
        "ping".to_string(),
        "-n".to_string(),
        "6".to_string(),
        "127.0.0.1".to_string(),
    ];
    #[cfg(not(windows))]
    let cmd = ["sleep".to_string(), "5".to_string()];
    let script = format!(
        r#"
    local r = psc.run_batch({{ {{ "{}" }} }}, {{ timeout = 3000 }})
    return {{}}
"#,
        cmd.join("\", \"")
    );

    let mut attempts: Vec<Duration> = Vec::new();
    let mut clean = false;
    for _ in 0..4 {
        let t0 = std::time::Instant::now();
        let _res =
            run_hook_with_timeout(&ctx(), &script, &empty_static(), Duration::from_millis(300));
        let elapsed = t0.elapsed();
        attempts.push(elapsed);
        if elapsed < Duration::from_secs(2) {
            clean = true;
            break;
        }
        // An interfered attempt waits out the 4s command timeout; retry for a clean window.
    }
    assert!(
        clean,
        "batch workers must honor the global deadline; attempts={attempts:?} \
         (every attempt waited past 2s - check for deadline-slot interference)"
    );
}

#[test]
fn hook_completes_well_within_timeout() {
    // A normal hook (pure computation + psc.run) must finish without being killed by the
    // deadline. The budget is generous (still well under the 10 s cap) so parallel test
    // load cannot exhaust it before the subprocess finishes — the assertion is about
    // completing with correct output, not about a tight timing window.
    let script = r#"
    local t = {}
    for i = 1, 1000 do t[i] = { name = "x" .. i } end
    local lines = psc.run({ "echo", "hello" })
    t[1001] = { name = lines[1] }
    return t
"#;
    let out =
        run_hook_with_timeout(&ctx(), script, &empty_static(), Duration::from_secs(2)).unwrap();
    assert_eq!(out.len(), 1001);
    assert_eq!(out[1000].text, "hello");
}

#[test]
fn hook_sees_empty_config_when_host_passes_null() {
    // The host passes `config.completion[<cmd>]`, which is JSON null for an unconfigured
    // completion. `psc.config` must surface as an empty table (not nil) so hooks that
    // index it (e.g. git's `psc.config.max_commit`) don't crash on a nil index.
    let script = r#"
        if type(psc.config) == "table" then
        psc.add({ name = "ok-" .. tostring(psc.config.max_commit) })
    else
        psc.add({ name = "config-nil" })
    end
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

// ---- psc.on ----

fn provide_manifest() -> serde_json::Value {
    serde_json::json!({
        "next": [
            { "name": "exec", "alias": ["x"] },
            { "name": "dlx" },
            { "name": "config", "next": [ { "name": "set" } ] },
            { "name": "install", "option": [
                { "name": "--color", "next": [ { "name": "auto" } ] },
                { "name": "--arch", "next": [] }
            ] }
        ]
    })
}

/// Root-level context (empty layer chain).
fn root_provide_ctx() -> HookContext {
    let mut c = ctx();
    c.path = Vec::new();
    c.layers = Vec::new();
    c.tokens = vec![Token {
        text: "tool".into(),
        kind: "command".into(),
        canonical: None,
    }];
    c.manifest = provide_manifest();
    c
}

fn static_rows(texts: &[&str]) -> Vec<LuaItem> {
    texts
        .iter()
        .map(|t| LuaItem {
            text: t.to_string(),
            ..Default::default()
        })
        .collect()
}

#[test]
fn provide_injects_inside_command_context_and_stamps_repeat() {
    let mut c = root_provide_ctx();
    c.layers = vec![("command".into(), "exec".into())];
    let script = r#"
    psc.on({ command = "exec" }, function()
        psc.add({ name = "eslint", repeat_count = 99 })
        psc.add({ name = "prettier", repeat_count = 99 })
    end)
    "#;
    let out = run_hook(&c, script, &static_rows(&["dlx"])).unwrap();
    let mut texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    texts.sort_unstable();
    assert_eq!(texts, vec!["dlx", "eslint", "prettier"]);
    for item in out.iter().filter(|i| i.text != "dlx") {
        assert_eq!(item.repeat, 99, "group stamp applies");
    }
}

#[test]
fn provide_promises_switch_on_parent_including_aliases() {
    let script = r#"
    psc.on({ command = "exec" }, function()
        psc.add({ name = "eslint" })
    end)
    "#;
    let out = run_hook(
        &root_provide_ctx(),
        script,
        &static_rows(&["exec", "x", "dlx"]),
    )
    .unwrap();
    let by_text: std::collections::HashMap<&str, Option<String>> = out
        .iter()
        .map(|i| (i.text.as_str(), i.symbol.clone()))
        .collect();
    assert_eq!(by_text["exec"].as_deref(), None);
    assert_eq!(by_text["x"].as_deref(), None);
    assert_eq!(by_text["dlx"], None);
    // The evaluated items are NOT injected at the parent position.
    assert!(!by_text.contains_key("eslint"));
}

#[test]
fn provide_empty_yield_leaves_default_symbol() {
    let script = r#"
    psc.on({ command = "exec" }, function() end)
    "#;
    let out = run_hook(&root_provide_ctx(), script, &static_rows(&["exec"])).unwrap();
    assert!(out.iter().all(|i| i.symbol == None));
}

/// Runs a hook against a temp log dir and returns the resulting error.log content.
fn capture_error_log(c: &mut HookContext, script: &str) -> String {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let n = SEQ.fetch_add(1, Ordering::SeqCst);
    let dir = std::env::temp_dir().join(format!("psc-provide-log-{}-{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    c.log_dir = dir.to_string_lossy().to_string();
    let _ = run_hook(c, script, &empty_static());
    let logged = std::fs::read_to_string(dir.join("error.log")).unwrap_or_default();
    let _ = std::fs::remove_dir_all(&dir);
    logged
}

#[test]
fn provide_unknown_target_fails_loudly() {
    let mut c = root_provide_ctx();
    let script = r#"
    psc.on({ command = "nope" }, function() end)
    "#;
    let logged = capture_error_log(&mut c, script);
    assert!(
        logged.contains("psc.on:") && logged.contains("nope"),
        "{logged}"
    );
}

#[test]
fn provide_rejects_wrong_provider_type_degrades_with_log() {
    // Swapped arguments must degrade gracefully (static menu stays) AND be logged.
    let mut c = root_provide_ctx();
    c.layers = vec![("command".into(), "exec".into())];
    let script = r#"
    psc.on(function() end, { command = "exec" })
    "#;
    let logged = capture_error_log(&mut c, script);
    assert!(
        logged.contains("spec must be a table") || logged.contains("handler must be a function"),
        "{logged}"
    );
}

#[test]
fn api_misuse_degrades_without_aborting() {
    // A grab-bag of authoring mistakes across several APIs: none may abort the process —
    // hooks degrade (raise into Lua cleanly / return empty) and the static menu survives.
    let script = r#"
    local a = psc.add(5)
    local b = psc.add(5)
    local c2 = psc.items({1, 2, 3}, "stay")
    local d = psc.json("nope-does-not-exist.json")
    local e = psc.mount_items({ "next", "zzz", "next" })
    local f = psc.split(123)
    local g = psc.token({})
    local h = psc.eq(nil, "x")
    return completions
    "#;
    let out = run_hook(&root_provide_ctx(), script, &empty_static());
    assert!(
        out.is_ok(),
        "API misuse must degrade, not abort: {:?}",
        out.err()
    );
}

#[test]
fn provide_provider_error_is_isolated_and_logged() {
    let mut c = root_provide_ctx();
    c.layers = vec![("command".into(), "exec".into())];
    let dir = std::env::temp_dir().join(format!("psc-provide-log-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    c.log_dir = dir.to_string_lossy().to_string();
    // The failing handler must degrade; the imperative add below still lands,
    // AND the failure surfaces in error.log (isolation must not mean invisibility).
    let script = r#"
    psc.on({ command = "exec" }, function() error("boom") end)
    psc.add({ name = "alive" })
    "#;
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "alive");
    let logged = std::fs::read_to_string(dir.join("error.log")).unwrap();
    assert!(logged.contains("boom"), "logged: {logged}");
    assert!(
        logged.contains("zoxide") || logged.contains("psc"),
        "cmd prefix: {logged}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn provide_deeper_context_does_not_match_prefix_target() {
    let mut c = root_provide_ctx();
    c.layers = vec![
        ("command".into(), "config".into()),
        ("command".into(), "set".into()),
    ];
    let script = r#"
    psc.on({ command = "config" }, function() psc.add({ name = "should-not-appear" }) end)
    "#;
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out.len(), 0);
}

#[test]
fn provide_root_targeting() {
    // A spec without location keys targets the root context.
    let script = r#"
    psc.on({}, function() psc.add({ name = "bin1" }) end)
    "#;
    let out = run_hook(&root_provide_ctx(), script, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "bin1");
}

#[test]
fn provide_root_repeat_stamping() {
    // Flat tools stamp their reusable root candidates the same way.
    let script = r#"
    psc.on({}, function()
        psc.add({ name = "bin1", repeat_count = 99 })
        psc.add({ name = "bin2", repeat_count = 99 })
    end)
    "#;
    let out = run_hook(&root_provide_ctx(), script, &empty_static()).unwrap();
    assert_eq!(out.len(), 2);
    assert!(out.iter().all(|i| i.repeat == 99));
}

#[test]
fn provide_empty_command_chain_is_redundant() {
    // Root is expressed by omitting 'command'; an explicit empty chain is rejected.
    let mut c = root_provide_ctx();
    let script = r#"
    psc.on({ command = {} }, function() psc.add({ name = "bin1" }) end)
    "#;
    let logged = capture_error_log(&mut c, script);
    assert!(
        logged.contains("command must not be an empty array"),
        "{logged}"
    );
}

#[test]
fn provide_empty_string_values_fail_loudly() {
    // Empty command "" is a wildcard (valid), and so is an empty option segment
    // (symmetric chain wildcard). What remains invalid: non-option-like option
    // segments (must start with '-').
    let cases = [(
        r#"psc.on({ option = "config" }, function() end)"#,
        "option segments must be options",
    )];
    for (script, expect) in cases {
        let mut c = root_provide_ctx();
        let logged = capture_error_log(&mut c, script);
        assert!(logged.contains(expect), "expected {expect:?} in: {logged}");
    }
}

#[test]
fn provide_option_value_position_and_switch() {
    let mut c = root_provide_ctx();
    // Completing --arch's value right after the option token (free-form, next: []).
    c.tokens.push(Token {
        text: "--arch".into(),
        kind: "option".into(),
        canonical: Some("--arch".into()),
    });
    let script = r#"
    psc.on({ option = "--arch" }, function() psc.add({ name = "x86_64" }) end)
    "#;
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "x86_64");

    let mut c2 = root_provide_ctx();
    c2.layers = vec![("command".into(), "install".into())];
    let script2 = r#"
    psc.on({ option = "--arch" }, function() psc.add({ name = "x86_64" }) end)
    "#;
    let out2 = run_hook(&c2, script2, &static_rows(&["--arch"])).unwrap();
    let arch = out2.iter().find(|i| i.text == "--arch").unwrap();
    assert_eq!(arch.symbol.as_deref(), None);
    assert!(
        !out2.iter().any(|i| i.text == "x86_64"),
        "not injected outside the value position"
    );
}

fn branch_manifest() -> serde_json::Value {
    serde_json::json!({
        "next": [
            {
                "name": "branch",
                "option": [
                    { "name": "--all", "alias": ["-a"] },
                    { "name": "--contains", "next": [] },
                    { "name": "--merged", "next": [] }
                ]
            }
        ]
    })
}

fn branch_ctx(layers: Vec<(String, String)>, tokens: Vec<Token>) -> HookContext {
    let mut c = ctx();
    c.manifest = branch_manifest();
    c.layers = layers;
    c.tokens = tokens;
    c.path = vec!["branch".into()];
    c
}

#[test]
fn provide_and_command_option_requires_both() {
    // `branch --contains <Tab>` -> AND must fire only when both sides match.
    let layers_branch_contains = vec![
        ("command".into(), "branch".into()),
        ("option".into(), "--contains".into()),
    ];
    let tokens_contains = vec![
        Token {
            text: "branch".into(),
            kind: "command".into(),
            canonical: Some("branch".into()),
        },
        Token {
            text: "--contains".into(),
            kind: "option".into(),
            canonical: Some("--contains".into()),
        },
    ];
    // Both match -> injects.
    let c = branch_ctx(layers_branch_contains.clone(), tokens_contains.clone());
    let out = run_hook(&c, r#"psc.on({ command = "branch", option = "--contains" }, function() psc.add({ name = "c1" }) end)"#, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "c1");

    // Only command matches (in value position but different option) -> no inject.
    let layers_branch_merged = vec![
        ("command".into(), "branch".into()),
        ("option".into(), "--merged".into()),
    ];
    let tokens_merged = vec![
        Token {
            text: "branch".into(),
            kind: "command".into(),
            canonical: Some("branch".into()),
        },
        Token {
            text: "--merged".into(),
            kind: "option".into(),
            canonical: Some("--merged".into()),
        },
    ];
    let c2 = branch_ctx(layers_branch_merged, tokens_merged);
    let out2 = run_hook(&c2, r#"psc.on({ command = "branch", option = "--contains" }, function() psc.add({ name = "c1" }) end)"#, &empty_static()).unwrap();
    assert_eq!(out2.len(), 0);

    // Only option matches but command is different -> no inject.
    let c3 = branch_ctx(
        vec![
            ("command".into(), "branch".into()),
            ("option".into(), "--contains".into()),
        ],
        tokens_contains.clone(),
    );
    let out3 = run_hook(&c3, r#"psc.on({ command = "config", option = "--contains" }, function() psc.add({ name = "c1" }) end)"#, &empty_static()).unwrap();
    assert_eq!(out3.len(), 0);
}

#[test]
fn provide_option_chain_matches_suffix() {
    // install has --color/--arch in provide_manifest(); use those for chain specs.
    let make_ctx = |tokens: Vec<Token>, opts: Vec<&str>| {
        let mut c = root_provide_ctx();
        c.layers = vec![("command".into(), "install".into())];
        c.tokens = tokens;
        c.opts = opts.iter().map(|s| s.to_string()).collect();
        c
    };
    let tokens = vec![
        Token {
            text: "install".into(),
            kind: "command".into(),
            canonical: Some("install".into()),
        },
        Token {
            text: "--color".into(),
            kind: "option".into(),
            canonical: Some("--color".into()),
        },
        Token {
            text: "--arch".into(),
            kind: "option".into(),
            canonical: Some("--arch".into()),
        },
    ];
    // Full-chain suffix match -> injects.
    let c = make_ctx(tokens.clone(), vec!["--color", "--arch"]);
    let out = run_hook(&c, r#"psc.on({ command = "install", option = { "--color", "--arch" } }, function() psc.add({ name = "mc" }) end)"#, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "mc");

    // Wrong final option -> no inject.
    let out2 = run_hook(&make_ctx(tokens.clone(), vec!["--color", "--arch"]), r#"psc.on({ command = "install", option = { "--color", "nope" } }, function() psc.add({ name = "mc" }) end)"#, &empty_static()).unwrap();
    assert_eq!(out2.len(), 0);

    // Chain longer than the typed sequence -> no inject.
    let out3 = run_hook(&make_ctx(tokens.clone(), vec!["--color", "--arch"]), r#"psc.on({ command = "install", option = { "x", "--color", "--arch" } }, function() psc.add({ name = "mc" }) end)"#, &empty_static()).unwrap();
    assert_eq!(out3.len(), 0);

    // Single-string option still matches (length-1 suffix, back-compat).
    let out4 = run_hook(&make_ctx(tokens, vec!["--color", "--arch"]), r#"psc.on({ command = "install", option = "--arch" }, function() psc.add({ name = "c1" }) end)"#, &empty_static()).unwrap();
    assert_eq!(out4.len(), 1);
}

#[test]
fn provide_option_chain_ignores_values_between_options() {
    // `install --color val --arch <Tab>`: the value token never enters the option
    // sequence, so the sequence stays [--color, --arch] and the chain still matches.
    let mut c = root_provide_ctx();
    c.layers = vec![("command".into(), "install".into())];
    c.tokens = vec![
        Token {
            text: "install".into(),
            kind: "command".into(),
            canonical: Some("install".into()),
        },
        Token {
            text: "--color".into(),
            kind: "option".into(),
            canonical: Some("--color".into()),
        },
        Token {
            text: "x".into(),
            kind: "value".into(),
            canonical: None,
        },
        Token {
            text: "--arch".into(),
            kind: "option".into(),
            canonical: Some("--arch".into()),
        },
    ];
    c.opts = vec!["--color".into(), "--arch".into()];
    let out = run_hook(&c, r#"psc.on({ command = "install", option = { "--color", "--arch" } }, function() psc.add({ name = "mc" }) end)"#, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
}

#[test]
fn provide_spec_array_is_or() {
    // An array of specs: any matching element injects; non-matching don't.
    let script = r#"
    psc.on({
        { command = "exec" },
        { command = "install", option = "--color" },
    }, function() psc.add({ name = "hit" }) end)
    "#;

    // Element 1 matches.
    let mut c1 = root_provide_ctx();
    c1.layers = vec![("command".into(), "exec".into())];
    let out1 = run_hook(&c1, script, &empty_static()).unwrap();
    assert_eq!(out1.len(), 1);

    // Element 2 matches (AND inside one element, option in value position).
    let mut c2 = root_provide_ctx();
    c2.layers = vec![
        ("command".into(), "install".into()),
        ("option".into(), "--color".into()),
    ];
    c2.tokens = vec![
        Token {
            text: "install".into(),
            kind: "command".into(),
            canonical: Some("install".into()),
        },
        Token {
            text: "--color".into(),
            kind: "option".into(),
            canonical: Some("--color".into()),
        },
    ];
    let out2 = run_hook(&c2, script, &empty_static()).unwrap();
    assert_eq!(out2.len(), 1);

    // Neither matches.
    let mut c3 = root_provide_ctx();
    c3.layers = vec![("command".into(), "dlx".into())];
    let out3 = run_hook(&c3, script, &empty_static()).unwrap();
    assert_eq!(out3.len(), 0);
}

#[test]
fn provide_spec_array_rejects_mixed_and_non_table() {
    // A top-level spec array mixing named keys and array elements is ambiguous -> error.
    let mut c = root_provide_ctx();
    let logged = capture_error_log(
        &mut c,
        r#"
    psc.on({ command = "exec", { option = "--arch" } }, function() end)
    "#,
    );
    assert!(logged.contains("cannot mix named keys"), "{logged}");
}

#[test]
fn provide_command_isolated_from_value_position() {
    // `branch --contains <Tab>` is a value position (option has next), so lone `branch` must NOT inject.
    let c_value = branch_ctx(
        vec![
            ("command".into(), "branch".into()),
            ("option".into(), "--contains".into()),
        ],
        vec![
            Token {
                text: "branch".into(),
                kind: "command".into(),
                canonical: Some("branch".into()),
            },
            Token {
                text: "--contains".into(),
                kind: "option".into(),
                canonical: Some("--contains".into()),
            },
        ],
    );
    let out = run_hook(
        &c_value,
        r#"psc.on({ command = "branch" }, function() psc.add({ name = "b" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out.len(), 0, "branch must be isolated from value position");

    // `branch -a <Tab>` is a flag (no next), layers stays [branch], so lone `branch` must still inject.
    let c_flag = branch_ctx(
        vec![("command".into(), "branch".into())],
        vec![
            Token {
                text: "branch".into(),
                kind: "command".into(),
                canonical: Some("branch".into()),
            },
            Token {
                text: "-a".into(),
                kind: "option".into(),
                canonical: Some("--all".into()),
            },
        ],
    );
    let out2 = run_hook(
        &c_flag,
        r#"psc.on({ command = "branch" }, function() psc.add({ name = "b" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out2.len(), 1);
    assert_eq!(out2[0].text, "b");
}

#[test]
fn provide_multiple_command_unknown_slot_gating() {
    // `branch foo <Tab>` — foo is an unknown in branch's positional slot.
    // Default: the slot is filled, no inject. multiple: keeps matching.
    let mk = |tokens: Vec<Token>| branch_ctx(vec![("command".into(), "branch".into())], tokens);
    let tokens = vec![
        Token {
            text: "branch".into(),
            kind: "command".into(),
            canonical: Some("branch".into()),
        },
        Token {
            text: "foo".into(),
            kind: "unknown".into(),
            canonical: None,
        },
    ];
    let out = run_hook(
        &mk(tokens.clone()),
        r#"psc.on({ command = "branch" }, function() psc.add({ name = "b" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(
        out.len(),
        0,
        "unknown after the chain fills the positional slot"
    );
    let out2 = run_hook(
        &mk(tokens),
        r#"psc.on({ command = "branch", multiple = true }, function() psc.add({ name = "b" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out2.len(), 1);
    assert_eq!(out2[0].text, "b");
}

#[test]
fn provide_multiple_command_static_value_depth() {
    // A static value in the manifest (`next` entry) pushes a command layer, so the exact
    // match dies once it is typed; `multiple` (prefix) keeps matching through deeper
    // positional layers.
    let manifest = serde_json::json!({
        "next": [
            { "name": "rebase", "next": [ { "name": "abcdefg" } ] }
        ]
    });
    let mk = |tokens: Vec<Token>| {
        let mut c = ctx();
        c.manifest = manifest.clone();
        c.layers = vec![
            ("command".into(), "rebase".into()),
            ("command".into(), "abcdefg".into()),
        ];
        c.path = vec!["rebase".into(), "abcdefg".into()];
        c.tokens = tokens;
        c
    };
    let tokens = vec![
        Token {
            text: "rebase".into(),
            kind: "command".into(),
            canonical: Some("rebase".into()),
        },
        Token {
            text: "abcdefg".into(),
            kind: "command".into(),
            canonical: Some("abcdefg".into()),
        },
    ];
    let out = run_hook(
        &mk(tokens.clone()),
        r#"psc.on({ command = "rebase" }, function() psc.add({ name = "c" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(
        out.len(),
        0,
        "static value already filled the positional slot"
    );
    let out2 = run_hook(
        &mk(tokens),
        r#"psc.on({ command = "rebase", multiple = true }, function() psc.add({ name = "c" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out2.len(), 1);
    assert_eq!(out2[0].text, "c");
}

#[test]
fn provide_multiple_option_value_slot_gating() {
    // `branch --contains x <Tab>` — --contains (next: []) consumed x as its value.
    // Default: the option's value slot is filled, no inject. multiple: keeps matching.
    let mk = |tokens: Vec<Token>| branch_ctx(vec![("command".into(), "branch".into())], tokens);
    let tokens = vec![
        Token {
            text: "branch".into(),
            kind: "command".into(),
            canonical: Some("branch".into()),
        },
        Token {
            text: "--contains".into(),
            kind: "option".into(),
            canonical: Some("--contains".into()),
        },
        Token {
            text: "x".into(),
            kind: "value".into(),
            canonical: None,
        },
    ];
    let out = run_hook(
        &mk(tokens.clone()),
        r#"psc.on({ option = "--contains" }, function() psc.add({ name = "c" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out.len(), 0, "value already typed fills the option slot");
    let out2 = run_hook(
        &mk(tokens),
        r#"psc.on({ option = "--contains", multiple = true }, function() psc.add({ name = "c" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out2.len(), 1);
    assert_eq!(out2[0].text, "c");
}

#[test]
fn provide_multiple_and_option_value_slot_gating() {
    // The `--type xxx <Tab>` scenario: an AND spec whose option value slot is filled
    // blocks by default and keeps matching with `multiple`.
    let mk = |tokens: Vec<Token>, layers: Vec<(String, String)>| branch_ctx(layers, tokens);
    let tokens = vec![
        Token {
            text: "branch".into(),
            kind: "command".into(),
            canonical: Some("branch".into()),
        },
        Token {
            text: "--contains".into(),
            kind: "option".into(),
            canonical: Some("--contains".into()),
        },
        Token {
            text: "x".into(),
            kind: "value".into(),
            canonical: None,
        },
    ];
    let layers = vec![("command".into(), "branch".into())];
    let out = run_hook(
        &mk(tokens.clone(), layers.clone()),
        r#"psc.on({ command = "branch", option = "--contains" }, function() psc.add({ name = "c" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out.len(), 0, "AND: a filled option value blocks by default");
    let out2 = run_hook(
        &mk(tokens, layers),
        r#"psc.on({ command = "branch", option = "--contains", multiple = true }, function() psc.add({ name = "c" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out2.len(), 1);
    assert_eq!(out2[0].text, "c");
}

#[test]
fn provide_multiple_stays_out_of_unrelated_option_value() {
    // `branch --contains <Tab>` (value pending): the frontier is --contains' value
    // position, NOT branch's positional slot — even `multiple` must not inject.
    let c = branch_ctx(
        vec![
            ("command".into(), "branch".into()),
            ("option".into(), "--contains".into()),
        ],
        vec![
            Token {
                text: "branch".into(),
                kind: "command".into(),
                canonical: Some("branch".into()),
            },
            Token {
                text: "--contains".into(),
                kind: "option".into(),
                canonical: Some("--contains".into()),
            },
        ],
    );
    let out = run_hook(
        &c,
        r#"psc.on({ command = "branch", multiple = true }, function() psc.add({ name = "b" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(
        out.len(),
        0,
        "must not fire inside an unrelated option's value position"
    );

    // Once the value is typed the layer chain truncates back to the command: the
    // positional slot is reachable again — options and their values never block it.
    let c2 = branch_ctx(
        vec![("command".into(), "branch".into())],
        vec![
            Token {
                text: "branch".into(),
                kind: "command".into(),
                canonical: Some("branch".into()),
            },
            Token {
                text: "--contains".into(),
                kind: "option".into(),
                canonical: Some("--contains".into()),
            },
            Token {
                text: "x".into(),
                kind: "value".into(),
                canonical: None,
            },
        ],
    );
    let out2 = run_hook(
        &c2,
        r#"psc.on({ command = "branch" }, function() psc.add({ name = "b" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(
        out2.len(),
        1,
        "an option value does not fill the positional slot"
    );
    let out3 = run_hook(
        &c2,
        r#"psc.on({ command = "branch", multiple = true }, function() psc.add({ name = "b" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out3.len(), 1);
}

#[test]
fn provide_multiple_option_chain_broken_by_new_option() {
    // `branch --contains x --merged <Tab>`: the option sequence is [--contains, --merged],
    // the chain no longer ends with --contains → no match even with `multiple`.
    let c = branch_ctx(
        vec![("command".into(), "branch".into())],
        vec![
            Token {
                text: "branch".into(),
                kind: "command".into(),
                canonical: Some("branch".into()),
            },
            Token {
                text: "--contains".into(),
                kind: "option".into(),
                canonical: Some("--contains".into()),
            },
            Token {
                text: "x".into(),
                kind: "value".into(),
                canonical: None,
            },
            Token {
                text: "--merged".into(),
                kind: "option".into(),
                canonical: Some("--merged".into()),
            },
        ],
    );
    let out = run_hook(
        &c,
        r#"psc.on({ option = "--contains", multiple = true }, function() psc.add({ name = "c" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(
        out.len(),
        0,
        "a new option breaks the chain even with multiple"
    );
}

#[test]
fn provide_multiple_unknown_before_chain_does_not_block() {
    // `git foo rebase <Tab>`: the unknown sits BEFORE the matched chain — the slot is
    // still open, the default injects.
    let mut c = ctx();
    c.manifest = serde_json::json!({ "next": [ { "name": "rebase" } ] });
    c.layers = vec![("command".into(), "rebase".into())];
    c.path = vec!["rebase".into()];
    c.tokens = vec![
        Token {
            text: "foo".into(),
            kind: "unknown".into(),
            canonical: None,
        },
        Token {
            text: "rebase".into(),
            kind: "command".into(),
            canonical: Some("rebase".into()),
        },
    ];
    let out = run_hook(
        &c,
        r#"psc.on({ command = "rebase" }, function() psc.add({ name = "r" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out.len(), 1, "unknown before the chain is not in the slot");
}

#[test]
fn provide_multiple_root_slot_gating() {
    // Root: an unknown at the root fills the first-argument slot.
    let mut c = root_provide_ctx();
    c.layers = Vec::new();
    c.tokens = vec![
        Token {
            text: "tool".into(),
            kind: "command".into(),
            canonical: None,
        },
        Token {
            text: "foo".into(),
            kind: "unknown".into(),
            canonical: None,
        },
    ];
    let out = run_hook(
        &c,
        r#"psc.on({}, function() psc.add({ name = "bin1" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out.len(), 0, "an unknown fills the root slot");
    let out2 = run_hook(
        &c,
        r#"psc.on({ multiple = true }, function() psc.add({ name = "bin1" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(out2.len(), 1);
    assert_eq!(out2[0].text, "bin1");
}

#[test]
fn provide_multiple_validation() {
    let mut c = root_provide_ctx();
    let logged = capture_error_log(
        &mut c,
        r#"psc.on({ command = "exec", multiple = 1 }, function() end)"#,
    );
    assert!(logged.contains("multiple must be a boolean"), "{logged}");

    // Explicit `false` behaves exactly like the default (Lua collapses duplicate table
    // keys, so the in-Rust duplicate guard is defense-in-depth only).
    let c2 = branch_ctx(
        vec![("command".into(), "branch".into())],
        vec![
            Token {
                text: "branch".into(),
                kind: "command".into(),
                canonical: Some("branch".into()),
            },
            Token {
                text: "foo".into(),
                kind: "unknown".into(),
                canonical: None,
            },
        ],
    );
    let out = run_hook(
        &c2,
        r#"psc.on({ command = "branch", multiple = false }, function() psc.add({ name = "b" }) end)"#,
        &empty_static(),
    )
    .unwrap();
    assert_eq!(
        out.len(),
        0,
        "explicit multiple = false matches the default"
    );
}

#[test]
fn mount_items_mounts_tips_usage_example_and_no_symbol() {
    let script = r#"
        psc.add(psc.mount_items({ "next", "config", "next" }))
"#;
    let out = run_hook(&nested_manifest_ctx(), script, &empty_static()).unwrap();
    // Direct children of config.next only: set, get, delete, verbose (no recursion into
    // get's next or verbose's option).
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["set", "get", "delete", "verbose"]);
    for item in &out {
        assert_eq!(item.symbol, None);
    }
}

#[test]
fn add_supports_localized_tip() {
    let script = r#"
        psc.add({ name = "alpha", tip = { ["en-US"] = "English tip", ["zh-CN"] = "中文提示" } })
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
fn repeat_filters_used_dynamic_items() {
    // A used dynamic item (repeat default 0) is filtered: after `completion git --reset`, --reset is gone
    let script = r#"
        psc.add({ name = "--reset", tip = "reset" })
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
        psc.add({ name = "-v", tip = "verbose", repeat_count = 2 })
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
        psc.add({ name = "--reset", tip = "reset" })
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
        psc.add({ name = "main", tip = "branch --- main" })
"#;
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert!(out.iter().all(|i| i.text != "main"));
}

#[test]
fn mount_items_matches_path_case_sensitively() {
    // Manifest holds both set / SET nodes — mount_items matches paths exactly; "SET" mounts its subtree
    let script = r#"
        psc.add(psc.mount_items({ "next", "config", "SET", "next" }))
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
        psc.add(psc.mount_items({ "next", "config", "next" }))
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
        psc.add(psc.mount_items({ "next", "config", "next" }))
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
        psc.add(psc.mount_items({ "next", "config", "flags", "option" }))
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
        psc.add(psc.mount_items({ "info", "config", "next" }))
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
        psc.add(psc.mount_items({ "next", "config", "set" }))
"#;
    let out = run_hook(&nested_manifest_ctx(), script, &empty_static()).unwrap();
    assert_eq!(out.len(), 0);
    // A source-only path (no navigation segments) also yields nothing
    let script2 = r#"
        psc.add(psc.mount_items({ "next", "next" }))
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
        psc.add({ name = "" })
    psc.add({ name = "   " })
    psc.add({ name = "valid", tip = "tip" })
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "valid");
    assert_eq!(out[0].tip.as_deref(), Some("tip"));
}

#[test]
fn add_without_tip_keeps_tip_absent() {
    let script = r#"
        psc.add({ name = "branch" })
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "branch");
    assert!(out[0].tip.is_none());
}

#[test]
fn run_items_adds_each_line_without_tip() {
    let script = r#"
        psc.add(psc.items(psc.run({ "echo", "alpha" }, { shell = true })))
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].text, "alpha");
    assert!(out[0].tip.is_none());
}

#[test]
fn ls_items_adds_dir_entries() {
    let dir = std::env::temp_dir().join("psc-lua-ls-items-test");
    let _ = std::fs::create_dir_all(dir.join("sub"));
    std::fs::write(dir.join("a.md"), "").unwrap();
    let script = format!(
        r#"
    local cs = {{}}
    psc.add(psc.items(psc.ls('{}'), function(e) if e.is_dir then return {{ name = e.name }} end end))
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
        psc.add({ name = "commit", tip = "commit changes" })
    psc.add({ name = "checkout", tip = "switch branch" })
"#;
    let static_items = vec![LuaItem {
        text: "stash".into(),
        ..Default::default()
    }];
    let out = run_hook(&ctx(), script, &static_items).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["commit", "checkout", "stash"]);
    assert_eq!(out[1].symbol, None);
    assert_eq!(out[0].tip.as_deref(), Some("commit changes"));
}

#[test]
fn dynamic_items_carry_usage_and_example() {
    let script = r#"
        psc.add({ name = "archive", tip = "create archive", usage = "archive|a", example = "a out.7z  # create an archive" })
    psc.add({ name = "extract", usage = "extract|e", example = "e demo.7z  # extract" })
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
    // psc.add without a tip leaves the tip absent (no implicit name-as-tip)
    assert_eq!(out[1].text, "extract");
    assert_eq!(out[1].usage.as_deref(), Some("extract|e"));
    assert_eq!(out[1].example.as_deref(), Some("e demo.7z  # extract"));
    assert!(out[1].tip.is_none());
    // Static items are unaffected (renamed to avoid colliding with used tokens and repeat-filtering)
    assert_eq!(out[2].text, "help");
    assert!(out[2].usage.is_none());
    assert!(out[2].example.is_none());
}

#[test]
fn token_and_current_context() {
    let script = r#"
    if psc.typing.option_like then return nil end
        if psc.token({ name = "checkout", type = "command" }) then
        psc.add({ name = "main" })
    elseif psc.token({ name = "stash", type = "command" }) then
        psc.add({ name = "stash@{0}" })
    end
"#;
    // tokens command = ["stash"] → hits the stash branch
    let mut c = ctx();
    c.tokens = vec![Token {
        text: "stash".into(),
        kind: "command".into(),
        canonical: Some("stash".into()),
    }];
    c.path = vec!["stash".into()];
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert!(out.iter().any(|i| i.text == "stash@{0}"));

    // typing is option-like → return nil (static only)
    c.typing = Typing {
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
        local pkg = psc.json(pkg_path)
    for k, _ in pairs(pkg.scripts or {}) do psc.add({ name = k }) end
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

#[test]
fn run_command_windows() {
    let script = r#"
        for _, l in ipairs(psc.run({"echo", "alpha"}, { shell = true })) do
        psc.add({ name = l:gsub("\r", "") })
    end
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "alpha");
}

#[test]
fn run_command_unix() {
    let script = r#"
        for _, l in ipairs(psc.run({"echo", "alpha"}, { shell = true })) do
        psc.add({ name = l })
    end
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
        for _, l in ipairs(psc.run({"echo", "shell-ok"}, { shell = true })) do
        psc.add({ name = l:gsub("\r", "") })
    end
"#
    } else {
        r#"
        for _, l in ipairs(psc.run({"echo", "shell-ok"}, { shell = true })) do
        psc.add({ name = l })
    end
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
    local v = psc.run({ "cd" }, { shell = true })
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
    local v = psc.run({{ "cd" }}, {{ cwd = {other_s}, shell = true }})
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
    for _, e in ipairs(psc.ls('{}')) do
        if not e.is_dir then psc.add({{ name = e.name }}) end
    end
"#,
        dir.to_string_lossy().replace('\\', "/")
    );
    let out = run_hook(&ctx(), &script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert!(texts.contains(&"a.md"));
    assert!(texts.contains(&"b.txt"));

    // glob
    let script2 = format!(
        "local g = psc.glob('{}/*.md')\nfor _, p in ipairs(g) do psc.add({{ name = p }}) end",
        dir.to_string_lossy().replace('\\', "/")
    );
    let out2 = run_hook(&ctx(), &script2, &empty_static()).unwrap();
    assert!(out2[0].text.ends_with("a.md"));
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn path_api_joins_and_normalizes() {
    // Segments join with the native separator, duplicate separators collapse, a leading
    // separator (absolute) is preserved. Empty results can't be added (empty names are
    // filtered), so they're asserted via a Lua-side comparison.
    let script = r#"
    psc.add({ name = psc.path("a", "b", "c.txt") })
    psc.add({ name = psc.path("/usr", "bin") })
    psc.add({ name = psc.path("a/", "/b") })
    psc.add({ name = psc.path("a//b", "c") })
    if psc.path("") == "" and psc.path() == "" then
        psc.add({ name = "empty-ok" })
    end
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    #[cfg(windows)]
    assert_eq!(
        texts,
        vec!["a\\b\\c.txt", "\\usr\\bin", "a\\b", "a\\b\\c", "empty-ok"],
        "{texts:?}"
    );
    #[cfg(not(windows))]
    assert_eq!(
        texts,
        vec!["a/b/c.txt", "/usr/bin", "a/b", "a/b/c", "empty-ok"],
        "{texts:?}"
    );
}

#[cfg(windows)]
#[test]
fn path_api_unifies_to_native_backslashes_on_windows() {
    // Windows: both `/` and `\` in input are unified to the native `\`; a drive root stays intact.
    let script = r#"
    psc.add({ name = psc.path("C:\\aaa", "bbb") })
    psc.add({ name = psc.path("C:\\aaa/bbb") })
    psc.add({ name = psc.path("C:\\aaa/", "/bbb") })
    psc.add({ name = psc.path("C:\\") })
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(
        texts,
        vec!["C:\\aaa\\bbb", "C:\\aaa\\bbb", "C:\\aaa\\bbb", "C:\\"],
        "{texts:?}"
    );
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
fn glob_respects_gitignore_and_brace() {
    // .gitignore is respected (like ripgrep/ignore); brace via globset;
    // absolute patterns work by joining cwd only when relative.
    let base = std::env::temp_dir().join("psc-glob-ignore-test");
    let _ = std::fs::remove_dir_all(&base);
    let dir = base.join("proj");
    std::fs::create_dir_all(dir.join("sub")).unwrap();
    std::fs::create_dir_all(dir.join("node_modules")).unwrap();
    std::fs::write(dir.join(".gitignore"), "ignored.log\nnode_modules/\n").unwrap();
    std::fs::write(dir.join("a.md"), "").unwrap();
    std::fs::write(dir.join("b.txt"), "").unwrap();
    std::fs::write(dir.join("ignored.log"), "").unwrap();
    std::fs::write(dir.join("sub").join("c.md"), "").unwrap();
    std::fs::write(dir.join("node_modules").join("x.md"), "").unwrap();
    let dir_s = dir.to_string_lossy().replace('\\', "/");
    let dir_json = serde_json::to_string(&dir_s).unwrap();
    // Use absolute patterns via psc.path(dir, ...) — absolute ignores cwd, relative would use hook cwd.
    let script = format!(
        r#"
    local abs_star = psc.glob({dir_json} .. "/*.md") or {{}}
    local abs_rec = psc.glob({dir_json} .. "/**/*.md") or {{}}
    local abs_brace = psc.glob({dir_json} .. "/*.{{md,txt}}") or {{}}
    local abs_ignored = psc.glob({dir_json} .. "/*.log") or {{}}
    return {{
        {{ name = "star-" .. #abs_star }},
        {{ name = "rec-" .. #abs_rec }},
        {{ name = "brace-" .. #abs_brace }},
        {{ name = "ignored-" .. #abs_ignored }},
    }}
"#
    );
    // Run with cwd = dir so relative patterns would also work; we test absolute explicitly.
    let mut ctx2 = ctx();
    ctx2.cwd = dir_s.clone();
    let out = run_hook(&ctx2, &script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    // star: only a.md (b.txt not .md); rec: a.md + sub/c.md (node_modules/x.md and ignored.log are gitignored);
    // brace: a.md + b.txt; ignored: 0 (ignored.log is gitignored)
    assert_eq!(
        texts,
        vec!["star-1", "rec-2", "brace-2", "ignored-0"],
        "{texts:?}"
    );
    let _ = std::fs::remove_dir_all(&base);
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
    let script = r#"
    local v = psc.run({ "echo junk & exit 1" }, { shell = true })
    if v == nil then return { { name = "nil-ok" } } end
    return { { name = "unexpected" } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "nil-ok");
}

#[test]
fn run_keeps_output_on_zero_exit() {
    // A successful command still returns its stdout lines.
    let script = if cfg!(windows) {
        r#"
    local v = psc.run({ "echo", "hello" }, { shell = true })
    if v ~= nil and v[1] == "hello" then return { { name = "ok" } } end
    return { { name = "unexpected" } }
"#
    } else {
        r#"
    local v = psc.run({ "echo", "hello" })
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

#[test]
fn run_format_invalid_json_returns_nil() {
    let script = r#"
    local v = psc.run({ "echo", "not-json" }, { shell = true, format = "json" })
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
            let raw = std::fs::read_to_string(&hook).unwrap();
            let text = psc_common::strip_bom(&raw);
            if text.trim().is_empty() {
                continue;
            }
            if let Err(err) = lua.load(text).set_name("hooks.lua").into_function() {
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

#[test]
fn run_batch_runs_commands_in_parallel() {
    let script = r#"
    local m = psc.run_batch({ {"echo", "one"}, {"echo", "two"} }, { shell = true })
    if not m[1] or not m[2] then return nil end
    if m[1][1]:gsub("\r", "") ~= "one" then return nil end
    if m[2][1]:gsub("\r", "") ~= "two" then return nil end
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

    // token against the ctx tokens ("psc" and "list" are completed command tokens):
    // returns the same entry table as psc.tokens[i]; nil when absent
    let script3 = r#"
    local t = psc.token({ name = "list" })
    if t == nil then return { { name = "missing" } } end
    if t.type ~= "command" or t.name ~= "list" or t.input ~= "list" then
        return { { name = "bad-entry" } }
    end
    if t ~= psc.tokens[2] then return { { name = "not-identity" } } end
    if psc.token({ name = "nope" }) ~= nil then return { { name = "unexpected-hit" } } end
    return { { name = "ok" } }
"#;
    let out3 = run_hook(&ctx(), script3, &empty_static()).unwrap();
    assert_eq!(out3[0].text, "ok");

    // A context with an unknown token: token({name="somevalue"}) returns it with type "unknown"
    let mut c = ctx();
    c.tokens.push(Token {
        text: "somevalue".into(),
        kind: "unknown".into(),
        canonical: None,
    });
    let script4 = r#"
    local t = psc.token({ name = "somevalue" })
    if t == nil or t.type ~= "unknown" or t.input ~= "somevalue" then return nil end
    return { { name = "ok" } }
"#;
    let out5 = run_hook(&c, script4, &empty_static()).unwrap();
    assert_eq!(out5[0].text, "ok");
    // token matches the canonical name, so an alias counts as its main option
    let mut c2 = ctx();
    c2.tokens.push(Token {
        text: "-a".into(),
        kind: "option".into(),
        canonical: Some("--all".into()),
    });
    let script5 = r#"
    local t = psc.token({ name = "--all" })
    if t == nil or t.name ~= "--all" or t.input ~= "-a" then return nil end
    if psc.token({ name = "-a" }) ~= nil then return nil end
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
        psc.add({ name = "alpha", tip = "t" })
    return { { name = tostring(completions[1].name or "<nil>") .. ":" .. tostring(completions[1].text or "<nil>") } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "alpha:<nil>");
}

#[test]
fn add_skips_items_without_name() {
    let script = r#"
    psc.add({ text = "stray" })
    psc.add({ "raw-string", { name = "ok" } })
    return { { name = "cs=" .. tostring(#completions) } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "cs=1");
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
    // nil arguments never match; the hook must not crash when token lookup misses.
    let script = r#"
    local undefined = psc.token({ name = "not-exist" })
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
fn trim_custom_chars() {
    // opts.chars overrides the whitespace set; an empty string trims nothing (empty set).
    let script = r#"
    return {
        { name = psc.trim("==x==", { chars = "=" }) },
        { name = psc.trim("==x==", { chars = "=", mode = "start" }) },
        { name = psc.trim("-=x=-", { chars = "-=" }) },
        { name = psc.trim("  x  ", { chars = "" }) },
        { name = psc.trim("xxhixx", { chars = "xi" }) },
    }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["x", "x==", "x", "  x  ", "h"]);
}

#[test]
fn on_returns_nothing() {
    // psc.on returns nil (no placeholder table): injection is via handlers only.
    let script = r#"
    local r = psc.on({ command = "exec" }, function() end)
    return { { name = tostring(r) } }
"#;
    let mut c = ctx();
    c.layers = vec![("command".into(), "exec".into())];
    let out = run_hook(&c, script, &empty_static()).unwrap();
    assert_eq!(out[0].text, "nil");
}

#[test]
fn mount_items_is_pure_transform() {
    // mount_items does NOT inject into `completions` by itself.
    let script = r#"
    local mounted = psc.mount_items({ "next", "config", "next" })
    local n = 0
    for _ in ipairs(completions) do n = n + 1 end
    return { { name = tostring(#mounted) }, { name = tostring(n) } }
"#;
    let mut c = ctx();
    c.manifest = provide_manifest();
    let out = run_hook(&c, script, &empty_static()).unwrap();
    // Mounted 1 (config's single child `set` per provide_manifest), completions still empty.
    assert_eq!(out[0].text, "1");
    assert_eq!(out[1].text, "0");
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
    // nil arguments — hooks commonly pass a missing token which is nil.
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
        r[#r+1] = tostring(#(psc.concat(n) or {}))
        r[#r+1] = tostring(psc.contains({ "a", "b" }, n))
        r[#r+1] = tostring(psc.trim(n))
        r[#r+1] = tostring(psc.token(n))
        r[#r+1] = tostring(#(psc.mount_items(n) or {}))
        psc.add(n)
        psc.eq(n, "run")
        return r
    end)
    return { { name = tostring(ok) }, { name = tostring(#results) }, { name = tostring(results) } }
"#;
    let out = run_hook(&ctx(), script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts[0], "true", "hook must not error, got: {texts:?}");
    assert_eq!(texts[1], "20", "expected 20 results, got: {texts:?}");
}

#[test]
fn psc_token_finds_by_name_and_type() {
    // `psc.token({name?, type?, case_sensitive?})` replaces cmds/opts: nil/{} → first token,
    // type filters, name is case-insensitive by default.
    let mut c = ctx();
    c.tokens = vec![
        Token {
            text: "branch".into(),
            kind: "command".into(),
            canonical: Some("branch".into()),
        },
        Token {
            text: "-m".into(),
            kind: "option".into(),
            canonical: Some("--move".into()),
        },
        Token {
            text: "foo".into(),
            kind: "unknown".into(),
            canonical: None,
        },
    ];
    let script = r#"
    local a = psc.token()
    if not a or a.name ~= "branch" then return { { name = "fail-a:" .. tostring(a and a.name) } } end
    local b = psc.token({})
    if not b or b.name ~= "branch" then return { { name = "fail-b" } } end
    local c = psc.token({ type = "command" })
    if not c or c.name ~= "branch" then return { { name = "fail-c" } } end
    local d = psc.token({ type = "option" })
    if not d or d.name ~= "--move" then return { { name = "fail-d:" .. tostring(d and d.name) } } end
    local e = psc.token({ name = "--move" })
    if not e or e.name ~= "--move" then return { { name = "fail-e" } } end
    local f = psc.token({ name = "--MOVE" })
    if not f or f.name ~= "--move" then return { { name = "fail-f" } } end
    local g = psc.token({ name = "--move", type = "command" })
    if g ~= nil then return { { name = "fail-g" } } end
    local h = psc.token({ name = "--move", type = "option" })
    if not h or h.name ~= "--move" then return { { name = "fail-h" } } end
    local i = psc.token({ name = "--move", case_sensitive = true })
    if not i or i.name ~= "--move" then return { { name = "fail-i" } } end
    local j = psc.token({ name = "--MOVE", case_sensitive = true })
    if j ~= nil then return { { name = "fail-j" } } end
    return { { name = "ok" } }
"#;
    let out = run_hook(&c, script, &empty_static()).unwrap();
    let texts: Vec<&str> = out.iter().map(|i| i.text.as_str()).collect();
    assert_eq!(texts, vec!["ok"], "{texts:?}");
}
