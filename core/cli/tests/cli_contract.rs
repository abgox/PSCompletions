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
fn json_add_no_args_param_err() {
    let d = make_data("json-add-noargs", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "add"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    assert!(!((v["ok"]).as_bool().unwrap_or(false)));
    assert_eq!(v["error"], "Too few parameters.");
}

#[test]
fn json_rm_no_args_param_err() {
    let d = make_data("json-rm-noargs", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "rm"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    assert!(!((v["ok"]).as_bool().unwrap_or(false)));
}

// ---------- add/rm flows over the local HTTP source ----------

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
fn json_add_unknown_name_reports_in_band() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-add-unknown", &srv);
    let (code, out) = psc(&d, &["--json", "add", "zzz-nope"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    let e = v.as_array().unwrap()[0].clone();
    assert_eq!(e["completion"], "zzz-nope");
    assert!(!((e["ok"]).as_bool().unwrap_or(false)));
}

#[test]
fn json_rm_unknown_name_reports_in_band() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-rm-unknown", &srv);
    let (code, out) = psc(&d, &["--json", "rm", "zzz-nope"]);
    assert_eq!(code, 0);
    let v = parse_json(&out);
    assert!(!((v.as_array().unwrap()[0]["ok"]).as_bool().unwrap_or(false)));
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
