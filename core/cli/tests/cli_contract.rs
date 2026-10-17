//! End-to-end contract tests: spawn the real `psc` binary against fixture data dirs
//! (with a local HTTP source so add/update run fully offline) and lock down the output
//! contract - exit codes, `--json` shapes, and on-disk side effects.
//!
//! Every case here mirrors a scenario that was once verified by hand; regressions in
//! the dispatch/contract layer must fail these before reaching users.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::Command;

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_psc")
}

/// Minimal HTTP/1.1 server serving canned JSON bodies per exact path. Detached thread;
/// routes live for the whole test process (fine for tests).
fn spawn_server(routes: Vec<(&'static str, String)>) -> String {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let port = listener.local_addr().unwrap().port();
    let map: HashMap<String, String> = routes
        .into_iter()
        .map(|(p, b)| (format!("/{}", p.trim_start_matches('/')), b))
        .collect();
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let mut sock = stream;
            let mut buf = [0u8; 8192];
            let n = sock.read(&mut buf).unwrap_or(0);
            if n == 0 {
                continue;
            }
            let req = String::from_utf8_lossy(&buf[..n]);
            let path = req.split_whitespace().nth(1).unwrap_or("/");
            let path = path.split('?').next().unwrap_or("/").to_string();
            let body = map
                .get(&path)
                .cloned()
                .unwrap_or_else(|| "{\"message\":\"Not Found\"}".to_string());
            let resp = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = sock.write_all(resp.as_bytes());
        }
    });
    format!("http://127.0.0.1:{port}")
}

/// Fixture data dir: one installed completion (`git`) plus a settings file whose source
/// URL points at the local server, so every network touch stays offline.
fn make_data(tag: &str, url: &str) -> PathBuf {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let dir = std::env::temp_dir().join(format!(
        "psc-contract-{}-{}-{}",
        tag,
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    let git = dir.join("completions/git/language");
    std::fs::create_dir_all(&git).unwrap();
    std::fs::create_dir_all(dir.join("temp")).unwrap();
    std::fs::write(
        dir.join("completions/git/config.json"),
        r#"{"id":"git-id","language":["en-US"]}"#,
    )
    .unwrap();
    std::fs::write(dir.join("completions/git/language/en-US.json"), "{}").unwrap();
    std::fs::write(
        dir.join("settings.json"),
        format!(r#"{{"alias":{{"git":["git"]}},"config":{{"language":"en-US","url":"{url}"}}}}"#),
    )
    .unwrap();
    dir
}

fn psc(data: &Path, args: &[&str]) -> (i32, String) {
    let out = Command::new(bin())
        .args(["--data", data.to_str().unwrap()])
        .args(args)
        .output()
        .unwrap();
    (
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stdout).into_owned(),
    )
}

fn parse_json(s: &str) -> serde_json::Value {
    serde_json::from_str(s).unwrap_or_else(|e| panic!("stdout must be valid JSON ({e}): {s}"))
}

fn v_ok(v: &serde_json::Value) -> bool {
    v.as_array()
        .map(|a| a.iter().all(|e| e["ok"] == true))
        .unwrap_or(false)
}

fn rewrite_settings(d: &Path, f: impl FnOnce(&mut serde_json::Value)) {
    let p = d.join("settings.json");
    let mut v = parse_json(&std::fs::read_to_string(&p).unwrap());
    f(&mut v);
    std::fs::write(&p, serde_json::to_string(&v).unwrap()).unwrap();
}

fn set_live_aliases(d: &Path, aliases: &[&str]) {
    rewrite_settings(d, |v| {
        v["alias"]["git"] = serde_json::json!(aliases);
    });
}

fn set_config_alias(d: &Path, aliases: &[&str]) {
    let p = d.join("completions/git/config.json");
    let mut v = parse_json(&std::fs::read_to_string(&p).unwrap());
    v["alias"] = serde_json::json!(aliases);
    std::fs::write(&p, serde_json::to_string(&v).unwrap()).unwrap();
}

/// Standard remote index + demo completion served by the local server.
fn demo_routes() -> Vec<(&'static str, String)> {
    vec![
        (
            "completions.json",
            r#"{"update":{"demo":"v2"},"meta":{"demo":{"en-US":{"url":"https://demo.example","description":"Demo"}}}}"#.into(),
        ),
        (
            "completions/demo/config.json",
            r#"{"id":"demo-id","language":["en-US"]}"#.into(),
        ),
        ("completions/demo/language/en-US.json", "{}".into()),
        ("module/version.json", r#"{"version":"9.9.9"}"#.into()),
    ]
}

// ---------- JSON contract: always exit 0 + parseable stdout ----------

#[test]
fn json_list_ok() {
    let d = make_data("json-list", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "list"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    assert!(v
        .as_array()
        .unwrap()
        .iter()
        .any(|e| e["completion"] == "git"));
}

#[test]
fn json_info_reports_aliases_array() {
    let d = make_data("json-info-aliases", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "info", "git"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    let e = v.as_array().unwrap()[0].clone();
    assert_eq!(e["name"], "git");
    assert_eq!(e["aliases"], serde_json::json!(["git"]), "{out}");
    assert!(
        e.get("alias").is_none(),
        "joined string must be gone: {out}"
    );
}

#[test]
fn json_info_unknown_entry_is_name_free_error() {
    let d = make_data("json-info-bad", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "info", "zzz-nope"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    let e = v.as_array().unwrap()[0].clone();
    assert_eq!(e["name"], "zzz-nope");
    assert!(!((e["ok"]).as_bool().unwrap_or(false)));
    // Error text must NOT embed the name: the module renders `name: error` itself.
    assert!(
        !e["error"].as_str().unwrap().contains("zzz-nope"),
        "error must stay name-free: {}",
        e["error"]
    );
}

#[test]
fn json_config_bad_group() {
    let d = make_data("json-cfg-group", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "config", "badgroup"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    assert!(!((v["ok"]).as_bool().unwrap_or(false)));
    assert!(!v["error"].as_str().unwrap().is_empty());
}

#[test]
fn json_config_bad_key() {
    let d = make_data("json-cfg-key", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "config", "menu", "nosuchkey"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    assert!(!((v["ok"]).as_bool().unwrap_or(false)));
}

#[test]
fn json_completion_bad_key() {
    let d = make_data("json-cmpl-key", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "completion", "git", "badkey"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    assert!(!((v["ok"]).as_bool().unwrap_or(false)));
}

#[test]
fn json_alias_bad_subcmd() {
    let d = make_data("json-alias-bad", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "alias", "foo"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    assert!(!((v["ok"]).as_bool().unwrap_or(false)));
}

#[test]
fn json_unknown_top_level_command_is_in_band() {
    let d = make_data("json-unknown-cmd", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "nosuchcommand"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert!(!((v["ok"]).as_bool().unwrap_or(false)), "{out}");
    assert_eq!(v["error"], "Invalid subcommand.");
}

#[test]
fn text_unknown_top_level_command_fails() {
    let d = make_data("txt-unknown-cmd", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["nosuchcommand"]);
    assert_eq!(code, 1, "{out}");
    assert!(out.contains("Invalid subcommand."), "{out}");
}

#[test]
fn json_alias_global_reset_reports_resulting_aliases() {
    let d = make_data("json-alias-reset", "http://127.0.0.1:9");
    set_live_aliases(&d, &["git", "g", "gg"]);
    let (code, out) = psc(&d, &["--json", "alias", "--reset"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    let entry = &v["reset"][0];
    assert_eq!(entry["name"], "git", "{out}");
    assert_eq!(entry["aliases"], serde_json::json!(["git"]), "{out}");
}

#[test]
fn json_alias_named_reset_reports_resulting_aliases() {
    let d = make_data("json-alias-named-reset", "http://127.0.0.1:9");
    set_live_aliases(&d, &["git", "g", "gg"]);
    set_config_alias(&d, &["git", "g"]);
    let (code, out) = psc(&d, &["--json", "alias", "add", "git", "--reset"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["name"], "git", "{out}");
    assert_eq!(v["ok"], true, "{out}");
    assert_eq!(v["reset"], serde_json::json!(["git", "g"]), "{out}");
}

#[test]
fn json_alias_named_reset_reports_skipped_words() {
    let d = make_data("json-alias-reset-skip", "http://127.0.0.1:9");
    set_live_aliases(&d, &["git"]);
    rewrite_settings(&d, |v| {
        v["alias"] = serde_json::json!({ "aaa": ["shared"], "git": ["git"] });
    });
    set_config_alias(&d, &["git", "shared"]);
    let (code, out) = psc(&d, &["--json", "alias", "add", "git", "--reset"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["reset"], serde_json::json!(["git"]), "{out}");
    assert_eq!(v["skipped"][0]["alias"], "shared", "{out}");
    assert_eq!(v["skipped"][0]["owner"], "aaa", "{out}");
}

#[test]
fn json_alias_rm_success_stdout_is_only_json() {
    let d = make_data("json-alias-rm-clean", "http://127.0.0.1:9");
    set_live_aliases(&d, &["git", "g", "gg"]);
    let (code, out) = psc(&d, &["--json", "alias", "rm", "git", "g"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    assert_eq!(v["removed"], serde_json::json!(["g"]), "{out}");
}

#[test]
fn json_alias_add_success_stdout_is_only_json() {
    let d = make_data("json-alias-add-clean", "http://127.0.0.1:9");
    set_live_aliases(&d, &["git"]);
    let (code, out) = psc(&d, &["--json", "alias", "add", "git", "zz"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v[0]["ok"], true, "{out}");
    assert_eq!(v[0]["added"], serde_json::json!(["zz"]), "{out}");
}

#[test]
fn json_add_and_rm_no_args_report_param_err() {
    // Both commands route an empty argv through the same param_err, so both must report the
    // identical contract: exit 0, ok=false, and the message itself. (The rm half used to
    // assert only ok=false, so a wrong or missing message would have passed.)
    for cmd in ["add", "rm"] {
        let d = make_data(&format!("json-{cmd}-noargs"), "http://127.0.0.1:9");
        let (code, out) = psc(&d, &["--json", cmd]);
        assert_eq!(code, 0, "{cmd}: {out}");
        let v = parse_json(&out);
        assert!(!((v["ok"]).as_bool().unwrap_or(false)), "{cmd}: {out}");
        assert_eq!(v["error"], "Too few parameters.", "{cmd}: {out}");
    }
}

// ---------- add/rm flows over the local HTTP source ----------

/// Index branch layout wins when both layouts serve a valid index: the client
/// must prefer `.../raw/index/completions.json` over `.../raw/main/...`.
#[test]
fn json_add_prefers_index_branch_layout() {
    let srv = spawn_server(vec![
        (
            "raw/index/completions.json",
            r#"{"update":{"demo":"v9"},"meta":{"demo":{"en-US":{"url":"https://demo.example","description":"Demo"}}}}"#.into(),
        ),
        (
            "raw/main/completions.json",
            r#"{"update":{"demo":"v1"},"meta":{"demo":{"en-US":{"url":"https://demo.example","description":"Demo"}}}}"#.into(),
        ),
        (
            "raw/main/completions/demo/config.json",
            r#"{"id":"demo-id","language":["en-US"]}"#.into(),
        ),
        ("raw/main/completions/demo/language/en-US.json", "{}".into()),
    ]);
    let d = make_data("flow-add-index", &format!("{srv}/raw/main"));
    let (code, out) = psc(&d, &["--json", "add", "demo"]);
    assert_eq!(code, 0, "add failed: {out}");
    assert_eq!(
        std::fs::read_to_string(d.join("completions/demo/.update")).unwrap(),
        "v9",
        "{out}"
    );
}

/// Reinstalling a linked completion keeps the link and still reports success:
/// settings refresh runs, files are untouched.
#[test]
fn json_add_linked_reports_added() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-add-linked", &srv);
    let target = d.join("link-target/demo");
    std::fs::create_dir_all(target.join("language")).unwrap();
    std::fs::write(
        target.join("config.json"),
        r#"{"id":"demo-id","language":["en-US"]}"#,
    )
    .unwrap();
    std::fs::write(target.join("language/en-US.json"), "{}").unwrap();
    #[cfg(unix)]
    std::os::unix::fs::symlink(&target, d.join("completions/demo")).unwrap();
    #[cfg(windows)]
    std::os::windows::fs::symlink_dir(&target, d.join("completions/demo")).unwrap();
    let (code, out) = psc(&d, &["--json", "add", "demo"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v.as_array().unwrap()[0]["ok"], true, "{out}");
    assert!(
        std::fs::symlink_metadata(d.join("completions/demo"))
            .unwrap()
            .file_type()
            .is_symlink(),
        "link must survive: {out}"
    );
}

/// Named update of an installed-but-off-index completion reports an error
/// (bulk `--all` still skips it silently).
#[test]
fn json_update_named_off_index_errors() {
    let srv = spawn_server(vec![(
        "completions.json",
        r#"{"update":{},"meta":{}}"#.into(),
    )]);
    let d = make_data("flow-update-offindex", &srv);
    let (code, out) = psc(&d, &["--json", "update", "git"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v.as_array().unwrap()[0]["ok"], false, "{out}");
}

/// Legacy mirrors serving only the old layout keep working: the index-branch
/// candidate misses (shape check rejects the not-found body) and the client
/// falls back to `.../raw/main/completions.json`.
#[test]
fn json_add_falls_back_to_legacy_layout() {
    let srv = spawn_server(vec![
        (
            "raw/main/completions.json",
            r#"{"update":{"demo":"v1"},"meta":{"demo":{"en-US":{"url":"https://demo.example","description":"Demo"}}}}"#.into(),
        ),
        (
            "raw/main/completions/demo/config.json",
            r#"{"id":"demo-id","language":["en-US"]}"#.into(),
        ),
        ("raw/main/completions/demo/language/en-US.json", "{}".into()),
    ]);
    let d = make_data("flow-add-legacy", &format!("{srv}/raw/main"));
    let (code, out) = psc(&d, &["--json", "add", "demo"]);
    assert_eq!(code, 0, "add failed: {out}");
    assert_eq!(
        std::fs::read_to_string(d.join("completions/demo/.update")).unwrap(),
        "v1",
        "{out}"
    );
}

/// Installing a completion that is new to the fresh index must not echo it back
/// as "new to the library": the per-item result already reported it. Unrelated
/// newcomers are still reported.
#[test]
fn json_add_does_not_report_installed_as_new() {
    let srv = spawn_server(vec![
        (
            "completions.json",
            r#"{"update":{"xxx":"v1","yyy":"v1"},"meta":{"xxx":{"en-US":{"url":"https://demo.example","description":"X"}},"yyy":{"en-US":{"url":"https://demo.example","description":"Y"}}}}"#.into(),
        ),
        (
            "completions/xxx/config.json",
            r#"{"id":"xxx-id","language":["en-US"]}"#.into(),
        ),
        ("completions/xxx/language/en-US.json", "{}".into()),
    ]);
    let d = make_data("flow-add-noecho", &srv);
    // Stale cached index: neither xxx nor yyy was known before this run.
    std::fs::write(
        d.join("temp/completions.json"),
        r#"{"update":{},"meta":{}}"#,
    )
    .unwrap();
    let (code, out) = psc(&d, &["--json", "add", "xxx"]);
    assert_eq!(code, 0, "add failed: {out}");
    assert_eq!(
        std::fs::read_to_string(d.join("completions/xxx/.update")).unwrap(),
        "v1",
        "{out}"
    );
    let change = parse_json(&std::fs::read_to_string(d.join("temp/change.json")).unwrap());
    assert_eq!(change["added"], serde_json::json!(["yyy"]), "{change}");
}

#[test]
fn json_add_installs_from_local_source() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-add", &srv);
    let (code, out) = psc(&d, &["--json", "add", "demo"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v.as_array().unwrap()[0]["ok"], true, "{out}");
    // Files landed and the version marker records the remote version.
    assert!(d.join("completions/demo/config.json").exists());
    assert_eq!(
        std::fs::read_to_string(d.join("completions/demo/.update")).unwrap(),
        "v2"
    );
}

#[test]
fn json_rm_removes_installed_completion() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-rm", &srv);
    psc(&d, &["--json", "add", "demo"]);
    let (code, out) = psc(&d, &["--json", "rm", "demo"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v.as_array().unwrap()[0]["ok"], true);
    assert!(!d.join("completions/demo").exists());
}

#[test]
fn json_add_and_rm_unknown_name_report_in_band() {
    // An unknown name is a per-completion failure, not a whole-command abort: both commands
    // exit 0 and report the name back inside the array. (The rm half used to assert only
    // ok=false, so a response missing the `completion` field would have passed.)
    let srv = spawn_server(demo_routes());
    for cmd in ["add", "rm"] {
        let d = make_data(&format!("flow-{cmd}-unknown"), &srv);
        let (code, out) = psc(&d, &["--json", cmd, "zzz-nope"]);
        assert_eq!(code, 0, "{cmd}: {out}");
        let v = parse_json(&out);
        let e = v.as_array().unwrap()[0].clone();
        assert_eq!(e["completion"], "zzz-nope", "{cmd}: {out}");
        assert!(!((e["ok"]).as_bool().unwrap_or(false)), "{cmd}: {out}");
    }
}

// ---------- update flows ----------

#[test]
fn json_update_check_writes_last_check() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-update-check", &srv);
    let (code, out) = psc(&d, &["--json", "update"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    // Check-mode payload shape: the four library-change arrays.
    for key in ["update", "added", "removed", "renamed"] {
        assert!(v.get(key).is_some(), "missing key {key} in {out}");
    }
    // change.json carries last_check for the menu's stale-update hint.
    let change = std::fs::read_to_string(d.join("temp/change.json")).unwrap();
    let c = parse_json(&change);
    assert!(c["last_check"].as_u64().unwrap() > 0, "{change}");
}

#[test]
fn json_update_named_updates_version_marker() {
    // One server whose index is REWRITTEN between calls: add demo at v2, bump the index
    // to v3, then a named update must refresh `.update` to v3.
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let port = listener.local_addr().unwrap().port();
    let routes: std::sync::Arc<std::sync::Mutex<HashMap<String, String>>> =
        std::sync::Arc::new(std::sync::Mutex::new(HashMap::new()));
    let shared = routes.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let mut sock = stream;
            let mut buf = [0u8; 8192];
            let n = sock.read(&mut buf).unwrap_or(0);
            if n == 0 {
                continue;
            }
            let req = String::from_utf8_lossy(&buf[..n]);
            let path = req.split_whitespace().nth(1).unwrap_or("/").to_string();
            let body = shared
                .lock()
                .unwrap()
                .get(&path)
                .cloned()
                .unwrap_or_else(|| "{\"message\":\"Not Found\"}".to_string());
            let resp = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            let _ = sock.write_all(resp.as_bytes());
        }
    });
    let srv = format!("http://127.0.0.1:{port}");
    {
        let mut m = routes.lock().unwrap();
        *m = HashMap::from([
            (
                "/completions.json".into(),
                r#"{"update":{"demo":"v2"},"meta":{}}"#.into(),
            ),
            (
                "/completions/demo/config.json".into(),
                r#"{"id":"demo-id","language":["en-US"]}"#.into(),
            ),
            ("/completions/demo/language/en-US.json".into(), "{}".into()),
        ]);
    }
    let d = make_data("flow-update-named", &srv);
    let (add_code, add_out) = psc(&d, &["--json", "add", "demo"]);
    eprintln!("ADD code={add_code} out={add_out}");
    assert_eq!(add_code, 0, "add failed: {add_out}");
    assert!(
        v_ok(&parse_json(&add_out)),
        "add reported failure: {add_out}"
    );
    assert_eq!(
        std::fs::read_to_string(d.join("completions/demo/.update")).unwrap(),
        "v2"
    );
    // Bump the remote version in place.
    {
        let mut m = routes.lock().unwrap();
        m.insert(
            "/completions.json".into(),
            r#"{"update":{"demo":"v3"},"meta":{}}"#.into(),
        );
    }
    let (code, out) = psc(&d, &["--json", "update", "demo"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(
        std::fs::read_to_string(d.join("completions/demo/.update")).unwrap(),
        "v3",
        "{out}"
    );
}

#[test]
fn json_update_save_failure_still_emits_one_document() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-update-savefail", &srv);
    psc(&d, &["--json", "add", "demo"]);
    let sp = d.join("settings.json");
    let mut perm = std::fs::metadata(&sp).unwrap().permissions();
    perm.set_readonly(true);
    std::fs::set_permissions(&sp, perm.clone()).unwrap();
    let (code, out) = psc(&d, &["--json", "update", "demo"]);
    let _ = std::fs::set_permissions(&sp, perm);
    assert_eq!(code, 0, "{out}");
    assert_eq!(
        out.trim().lines().count(),
        1,
        "--json mode owes exactly one document: {out}"
    );
    let v = parse_json(&out);
    assert!(
        v.as_array().unwrap().iter().any(|e| e["ok"] == true),
        "{out}"
    );
}

#[test]
fn json_update_named_unknown_reports_in_band() {
    // A NAMED update of a name that is neither installed nor indexed reports the failure
    // in-band (per-entry ok:false, exit 0). The silent skip applies only to `--all`
    // sweeps over installed-but-unindexed completions.
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-update-skip", &srv);
    let (code, out) = psc(&d, &["--json", "update", "zzz-nope"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    let e = v.as_array().unwrap()[0].clone();
    assert_eq!(e["completion"], "zzz-nope");
    assert!(!((e["ok"]).as_bool().unwrap_or(false)));
}

#[test]
fn json_update_old_empty_when_everything_current() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-update-old", &srv);
    psc(&d, &["--json", "add", "demo"]); // installs at v2 == remote
    let (code, out) = psc(&d, &["--json", "update", "--old"]);
    assert_eq!(code, 0);
    assert_eq!(out.trim(), "[]");
}

// ---------- text mode: exit codes + human messages ----------

#[test]
fn text_info_unknown_fails_with_message() {
    let d = make_data("txt-info-bad", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["info", "zzz-nope"]);
    assert_eq!(code, 1);
    assert!(out.contains("zzz-nope"), "{out}");
}

#[test]
fn text_config_bad_group_fails() {
    let d = make_data("txt-cfg-group", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["config", "badgroup"]);
    assert_eq!(code, 1);
    assert!(out.contains("Invalid subcommand."), "{out}");
}

#[test]
fn text_add_no_args_fails() {
    let d = make_data("txt-add-noargs", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["add"]);
    assert_eq!(code, 1);
    assert!(out.contains("Too few parameters."), "{out}");
}

#[test]
fn text_alias_wildcard_rejected_with_failure_exit() {
    // Regression guard: rejected aliases must drive a FAILURE exit in text mode even
    // though the rejection bookkeeping lives in the json results array.
    let srv = spawn_server(demo_routes());
    let d = make_data("txt-alias-wild", &srv);
    let (code, out) = psc(&d, &["alias", "add", "git", "g*"]);
    assert_eq!(code, 1, "rejected alias must exit FAILURE");
    assert!(out.contains("wildcard"), "{out}");
}
