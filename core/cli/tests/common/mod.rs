//! Helpers shared by the CLI contract tests: the fixture data dir, the binary runner and the
//! JSON parsing they both need.

#![allow(dead_code, unused_imports)]

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};

pub fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_psc")
}

/// The one place a port is opened: `127.0.0.1:0` makes the OS pick a free one, so tests never
/// collide and no fixed port exists anywhere in the suite.
fn serve(routes: Arc<Mutex<HashMap<String, String>>>) -> String {
    let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
    let port = listener.local_addr().unwrap().port();
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
            let key = path
                .split('?')
                .next()
                .unwrap_or("/")
                .trim_start_matches('/');
            let body = routes
                .lock()
                .unwrap()
                .get(key)
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

/// A route table keyed by path without the leading `/` (`"completions.json"`) — the form
/// `demo_routes` uses; a leading `/` is tolerated.
fn route_map(routes: Vec<(&'static str, String)>) -> HashMap<String, String> {
    routes
        .into_iter()
        .map(|(p, b)| (p.trim_start_matches('/').to_string(), b))
        .collect()
}

/// Minimal HTTP/1.1 server serving canned JSON bodies per exact path. Detached thread;
/// routes live for the whole test process (fine for tests).
pub fn spawn_server(routes: Vec<(&'static str, String)>) -> String {
    serve(Arc::new(Mutex::new(route_map(routes))))
}

/// `spawn_server`, but the route table comes back too, so a test can rewrite it between
/// calls — e.g. bump the remote index from v2 to v3 and re-run `update`.
pub fn spawn_server_mut(
    routes: Vec<(&'static str, String)>,
) -> (String, Arc<Mutex<HashMap<String, String>>>) {
    let map = Arc::new(Mutex::new(route_map(routes)));
    let url = serve(map.clone());
    (url, map)
}

/// Fixture data dir: one installed completion (`git`) plus a settings file whose source
/// URL points at the local server, so every network touch stays offline.
pub fn make_data(tag: &str, url: &str) -> PathBuf {
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

pub fn psc(data: &Path, args: &[&str]) -> (i32, String) {
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

pub fn parse_json(s: &str) -> serde_json::Value {
    serde_json::from_str(s).unwrap_or_else(|e| panic!("stdout must be valid JSON ({e}): {s}"))
}

/// The envelope says the run succeeded: `ok` is true and, when the payload is a per-item
/// collection, every item succeeded too.
pub fn v_ok(v: &serde_json::Value) -> bool {
    if v["ok"] != true {
        return false;
    }
    match v["data"]["completions"].as_array() {
        Some(a) => a.iter().all(|e| e["ok"] == true),
        None => true,
    }
}

pub fn rewrite_settings(d: &Path, f: impl FnOnce(&mut serde_json::Value)) {
    let p = d.join("settings.json");
    let mut v = parse_json(&std::fs::read_to_string(&p).unwrap());
    f(&mut v);
    std::fs::write(&p, serde_json::to_string(&v).unwrap()).unwrap();
}

pub fn set_live_aliases(d: &Path, aliases: &[&str]) {
    rewrite_settings(d, |v| {
        v["alias"]["git"] = serde_json::json!(aliases);
    });
}

pub fn set_config_alias(d: &Path, aliases: &[&str]) {
    let p = d.join("completions/git/config.json");
    let mut v = parse_json(&std::fs::read_to_string(&p).unwrap());
    v["alias"] = serde_json::json!(aliases);
    std::fs::write(&p, serde_json::to_string(&v).unwrap()).unwrap();
}

/// Standard remote index + demo completion served by the local server.
pub fn demo_routes() -> Vec<(&'static str, String)> {
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
