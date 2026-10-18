//! The `info` templates render as frozen goldens.
//!
//! `tests/fixtures/psc_tpl.json` holds every template the shipped `psc` completion carries, next to
//! its expected rendering under one rich context, plus the expression shapes those templates use
//! (fallback chains, `quote`, `#each` caps, `else`, nesting). Anything here is the module's own
//! displayed text, so a change that alters it fails here first.

use serde_json::Value;

#[test]
fn renders_the_shipped_templates_as_frozen_goldens() {
    let path = format!("{}/tests/fixtures/psc_tpl.json", env!("CARGO_MANIFEST_DIR"));
    let text = std::fs::read_to_string(&path).expect("fixture is committed next to this test");
    let cases: Vec<Value> = serde_json::from_str(&text).expect("fixture parses");

    assert!(cases.len() >= 15, "the fixture covers every template leaf");
    let mut checked = 0;
    for case in &cases {
        let name = case["name"].as_str().unwrap();
        let expected = match &case["expected"] {
            Value::String(s) => s.clone(),
            _ => continue,
        };
        let got = psc_cli::tpl::render(&case["data"], &case["ctx"], "");
        assert_eq!(got, expected, "case {name}");
        checked += 1;
    }
    assert!(checked >= 15, "at least 15 cases were actually compared");
}
