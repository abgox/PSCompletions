//! The `init --flat` contract: the POSIX hosts' NUL-delimited record stream must be exactly the
//! aliasMap + scalar config projection of the JSON payload, so the two outputs cannot drift.

mod common;

use common::*;
use serde_json::Value;
use std::collections::BTreeMap;

fn read_records(bytes: &[u8]) -> BTreeMap<(u8, String), String> {
    let mut out = BTreeMap::new();
    let mut fields = bytes.split(|b| *b == 0);
    while let Some(kind) = fields.next() {
        if kind.is_empty() {
            break;
        }
        let Some(key) = fields.next() else { break };
        let Some(value) = fields.next() else { break };
        out.insert(
            (kind[0], String::from_utf8_lossy(key).into_owned()),
            String::from_utf8_lossy(value).into_owned(),
        );
    }
    out
}

fn expected_records(payload: &Value) -> BTreeMap<(u8, String), String> {
    let mut out = BTreeMap::new();
    for (alias, completion) in payload["aliasMap"].as_object().unwrap() {
        out.insert(
            (b'A', alias.clone()),
            completion.as_str().unwrap().to_string(),
        );
    }
    for (key, value) in payload["data"]["config"].as_object().unwrap() {
        if key == "completion" {
            continue;
        }
        let text = match value {
            Value::String(s) => s.clone(),
            Value::Number(n) => n.to_string(),
            Value::Bool(b) => {
                if *b {
                    "1".to_string()
                } else {
                    "0".to_string()
                }
            }
            _ => continue,
        };
        out.insert((b'C', key.clone()), text);
    }
    out
}

#[test]
fn init_flat_matches_the_json_payload() {
    let d = make_data("init-flat", "http://127.0.0.1:9");
    std::fs::write(
        d.join("settings.json"),
        r#"{"alias":{"git":["git","g alias"]},"config":{"language":"en-US","url":"http://127.0.0.1:9","switch":"a b\u001f\nc"}}"#,
    )
    .unwrap();
    let json_path = d.join("init.json");
    let flat_path = d.join("init.flat");
    let (code, out) = psc(&d, &["init", "--result", json_path.to_str().unwrap()]);
    assert_eq!(code, 0, "{out}");
    let (code, out) = psc(
        &d,
        &["init", "--flat", "--result", flat_path.to_str().unwrap()],
    );
    assert_eq!(code, 0, "{out}");
    let payload: Value =
        serde_json::from_str(&std::fs::read_to_string(&json_path).unwrap()).unwrap();
    assert_eq!(
        read_records(&std::fs::read(&flat_path).unwrap()),
        expected_records(&payload)
    );
}

#[test]
fn init_flat_requires_a_result_file() {
    let d = make_data("init-flat-no-result", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["init", "--flat"]);
    assert_eq!(code, 2, "{out}");
    assert!(out.contains("--result"), "{out}");
}

#[test]
fn init_flat_rejects_extra_arguments() {
    let d = make_data("init-flat-junk", "http://127.0.0.1:9");
    let (code, _) = psc(&d, &["init", "--flat", "junk"]);
    assert_eq!(code, 2);
}
