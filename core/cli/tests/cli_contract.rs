//! The text-output contract: what a human sees, and the tpl command's rendering.

mod common;

use common::*;
use std::path::Path;

#[test]
fn text_unknown_top_level_command_fails() {
    let d = make_data("txt-unknown-cmd", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["nosuchcommand"]);
    // A usage error is 2 (design/json.md §6): "you asked wrong", not "it did not work".
    assert_eq!(code, 2, "{out}");
    assert!(out.contains("Invalid subcommand."), "{out}");
}

#[test]
fn text_info_unknown_fails_with_message() {
    let d = make_data("txt-info-bad", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["info", "zzz-nope"]);
    assert_eq!(code, 1);
    assert!(out.contains("zzz-nope"), "{out}");
}

/// Copy the repository's `psc` completion into a fixture data dir: it carries the `info`
/// templates the renderer reads.
fn seed_psc_completion(dir: &Path) {
    let src = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../completions/psc");
    for sub in ["config.json", "language/en-US.json", "language/zh-CN.json"] {
        let to = dir.join("completions/psc").join(sub);
        std::fs::create_dir_all(to.parent().unwrap()).unwrap();
        std::fs::copy(src.join(sub), &to).unwrap();
    }
}

#[test]
fn tpl_renders_the_psc_info_templates() {
    let d = make_data("tpl", "http://127.0.0.1:9");
    seed_psc_completion(&d);
    let ctx = r#"{"Version":"7.7.0"}"#;
    // Colored by default: the hosts capture stdout, so a TTY test inside the engine would lie, and
    // the trailing reset gives the caller's terminal its attributes back.
    let (code, out) = psc(&d, &["tpl", "description", "--ctx", ctx]);
    assert_eq!(code, 0, "{out}");
    assert!(out.contains("\x1b[36m[Module Description]"), "{out:?}");
    assert!(out.contains("7.7.0"), "{out}");
    assert!(out.ends_with("\x1b[0m"), "{out:?}");
    // `--no-color` leaves plain text.
    let (code, out) = psc(&d, &["tpl", "description", "--ctx", ctx, "--no-color"]);
    assert_eq!(code, 0);
    assert!(!out.contains('\x1b'), "{out:?}");
    assert!(out.contains("[Module Description]"), "{out}");
    // A path with no template prints nothing and fails, so a caller can fall back.
    let (code, out) = psc(&d, &["tpl", "no.such.leaf"]);
    assert_eq!(code, 1);
    assert!(out.is_empty(), "{out:?}");
    // Bad caller data renders as an empty context instead of aborting.
    let (code, out) = psc(&d, &["tpl", "set_value", "--ctx", "{not json"]);
    assert_eq!(code, 0, "{out}");
    // No path says how to call it.
    let (code, out) = psc(&d, &["tpl"]);
    assert_eq!(code, 1);
    assert!(out.contains("psc tpl <dotted.info.path>"), "{out}");
    // `--version` fills in the module version the engine cannot know; a caller that already
    // carries one keeps it.
    let (code, out) = psc(&d, &["tpl", "description", "--version", "9.9.9"]);
    assert_eq!(code, 0, "{out}");
    assert!(out.contains("9.9.9"), "{out}");
    let (code, out) = psc(
        &d,
        &["tpl", "description", "--ctx", ctx, "--version", "9.9.9"],
    );
    assert_eq!(code, 0);
    assert!(out.contains("7.7.0") && !out.contains("9.9.9"), "{out}");
    // `--lint` checks the shipped page statically, and `--explain` reports what each name did.
    let (code, out) = psc(&d, &["tpl", "description", "--lint"]);
    assert_eq!(code, 0, "{out}");
    assert!(out.contains("0 finding(s)"), "{out}");
    let (code, out) = psc(
        &d,
        &["tpl", "description", "--explain", "--version", "9.9.9"],
    );
    assert_eq!(code, 0, "{out}");
    assert!(out.contains("Version — resolved"), "{out}");
    assert!(out.contains("Module Description"), "{out}");
    let (code, out) = psc(&d, &["tpl", "set_value", "--explain"]);
    assert_eq!(code, 0, "{out}");
    assert!(out.contains("Value — unresolved"), "{out}");
    // A flag the command does not know is reported as such, not mistaken for the path, and
    // `--ctx` never swallows the flag after it.
    let (code, out) = psc(&d, &["tpl", "--color", "description"]);
    assert_eq!(code, 1);
    assert!(out.contains("unknown argument --color"), "{out}");
    let (code, out) = psc(&d, &["tpl", "description", "--ctx", "--no-color"]);
    assert_eq!(code, 1);
    assert!(out.contains("--ctx needs a JSON value"), "{out}");
}

#[test]
fn text_language_flag_overrides_messages() {
    // `--language` must change the *messages* too, not only `init`'s payload: with the flag set
    // to zh-CN the same failure reads in Chinese.
    let d = make_data("txt-lang-flag", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--language", "zh-CN", "config", "badgroup"]);
    assert_eq!(code, 2);
    assert!(out.contains("无效的子命令"), "{out}");
    assert!(!out.contains("Invalid subcommand"), "{out}");
}

#[test]
fn text_config_bad_group_fails() {
    let d = make_data("txt-cfg-group", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["config", "badgroup"]);
    assert_eq!(code, 2);
    // The message names the offending token and the valid set, so the reader is not left
    // guessing — this text is the interface in the shells.
    assert!(out.contains("badgroup"), "{out}");
    assert!(out.contains("core, menu, context"), "{out}");
}

#[test]
fn text_add_no_args_fails() {
    let d = make_data("txt-add-noargs", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["add"]);
    assert_eq!(code, 2);
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
