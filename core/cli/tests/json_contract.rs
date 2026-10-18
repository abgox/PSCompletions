//! The `--json` contract: every command's machine-readable shape, in one place.
//!
//! This file is the format's specification — a shape change shows up here first.

mod common;

use common::*;

#[test]
fn json_list_ok() {
    // The envelope: `ok`, the payload under a named key, and `meta` describing this run.
    let d = make_data("json-list", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "list"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    let items = v["data"]["completions"].as_array().unwrap();
    assert_eq!(items.len(), 1, "{out}");
    assert_eq!(items[0]["name"], "git", "{out}");
    assert_eq!(items[0]["alias"], serde_json::json!(["git"]), "{out}");
    // `meta` carries the count and the paths, in the module's vocabulary.
    assert_eq!(v["meta"]["count"], 1, "{out}");
    assert_eq!(
        v["meta"]["file"]["settings"],
        serde_json::json!(d.join("settings.json").to_string_lossy()),
        "{out}"
    );
}

#[test]
fn json_info_reports_aliases_array() {
    let d = make_data("json-info-aliases", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "info", "git"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    let e = v["data"]["completions"][0].clone();
    assert_eq!(e["name"], "git");
    assert_eq!(e["ok"], true, "{out}");
    assert_eq!(e["alias"], serde_json::json!(["git"]), "{out}");
    assert_eq!(v["meta"]["count"], 1, "{out}");
}

#[test]
fn json_info_unknown_entry_is_name_free_error() {
    let d = make_data("json-info-bad", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "info", "zzz-nope"]);
    assert_eq!(code, 1, "a failed entry fails the run: {out}");
    let v = parse_json(&out);
    let e = v["data"]["completions"][0].clone();
    assert_eq!(e["name"], "zzz-nope");
    assert_eq!(e["ok"], false, "{out}");
    // The error is an object now: a stable code beside a message that must stay name-free
    // (the host renders `name: message` itself).
    assert_eq!(e["error"]["code"], "not_available", "{out}");
    assert!(
        !e["error"]["message"].as_str().unwrap().contains("zzz-nope"),
        "error must stay name-free: {}",
        e["error"]
    );
}

#[test]
fn json_config_custom_url_warns() {
    let d = make_data("json-cfg-url", "http://127.0.0.1:9");
    let (code, out) = psc(
        &d,
        &["--json", "config", "core", "url", "https://evil.example/x"],
    );
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    // A write answers the item a read of that key answers with, plus what it replaced. An
    // unreviewed source's notice rides alongside it.
    assert_eq!(v["data"]["key"], "url", "{out}");
    assert_eq!(v["data"]["value"], "https://evil.example/x", "{out}");
    assert_eq!(v["data"]["old"], "http://127.0.0.1:9", "{out}");
    assert!(
        !v["data"]["warning"].as_str().unwrap_or_default().is_empty(),
        "{out}"
    );
    // An official candidate carries no warning, and `old` is what the call above wrote — the proof
    // that a write reports the value it replaced.
    let (code, out) = psc(
        &d,
        &[
            "--json",
            "config",
            "core",
            "url",
            "https://github.com/abgox/PSCompletions/raw/main",
        ],
    );
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    assert!(v["data"].get("warning").is_none(), "{out}");
    assert_eq!(
        v["data"]["value"], "https://github.com/abgox/PSCompletions/raw/main",
        "{out}"
    );
    assert_eq!(v["data"]["old"], "https://evil.example/x", "{out}");
}

#[test]
fn json_config_bad_group() {
    let d = make_data("json-cfg-group", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "config", "badgroup"]);
    assert_eq!(code, 2, "a usage error exits 2: {out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], false, "{out}");
    assert_eq!(v["error"]["code"], "invalid_subcommand", "{out}");
    assert!(!v["error"]["message"].as_str().unwrap().is_empty(), "{out}");
}

#[test]
fn json_config_bad_key() {
    let d = make_data("json-cfg-key", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "config", "menu", "nosuchkey"]);
    assert_eq!(code, 2, "a usage error exits 2: {out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], false, "{out}");
    assert_eq!(v["error"]["code"], "invalid_subcommand", "{out}");
}

#[test]
fn json_completion_bad_key() {
    let d = make_data("json-cmpl-key", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "completion", "git", "badkey"]);
    assert_eq!(code, 2, "a usage error exits 2: {out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], false, "{out}");
    assert_eq!(v["error"]["code"], "invalid_subcommand", "{out}");
}

#[test]
fn json_alias_bad_subcmd() {
    let d = make_data("json-alias-bad", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "alias", "foo"]);
    assert_eq!(code, 2, "a bad subcommand is a usage error: {out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], false, "{out}");
    assert_eq!(v["error"]["code"], "invalid_subcommand", "{out}");
}

#[test]
fn json_unknown_top_level_command_is_a_usage_error() {
    let d = make_data("json-unknown-cmd", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "nosuchcommand"]);
    assert_eq!(code, 2, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], false, "{out}");
    assert_eq!(v["error"]["code"], "invalid_subcommand", "{out}");
    assert!(!v["error"]["message"].as_str().unwrap().is_empty(), "{out}");
}

#[test]
fn json_alias_global_reset_reports_resulting_aliases() {
    let d = make_data("json-alias-reset", "http://127.0.0.1:9");
    set_live_aliases(&d, &["git", "g", "gg"]);
    let (code, out) = psc(&d, &["--json", "alias", "--reset", "--yes"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    let entry = &v["data"]["aliases"][0];
    assert_eq!(entry["name"], "git", "{out}");
    assert_eq!(entry["alias"], serde_json::json!(["git"]), "{out}");
    assert_eq!(v["meta"]["count"], 1, "{out}");
}

#[test]
fn json_alias_named_reset_reports_resulting_aliases() {
    let d = make_data("json-alias-named-reset", "http://127.0.0.1:9");
    set_live_aliases(&d, &["git", "g", "gg"]);
    set_config_alias(&d, &["git", "g"]);
    let (code, out) = psc(&d, &["--json", "alias", "add", "git", "--reset", "--yes"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    assert_eq!(v["data"]["name"], "git", "{out}");
    assert_eq!(v["data"]["alias"], serde_json::json!(["git", "g"]), "{out}");
}

#[test]
fn json_alias_named_reset_declares_the_config_words_verbatim() {
    // Conflicts are deliberately not resolved: the config's words are declared as they are, even
    // when another completion already claims one — the hosts resolve it by claim order, and the
    // completion moves to the end of the map so its claim is the later one.
    let d = make_data("json-alias-reset-shared", "http://127.0.0.1:9");
    set_live_aliases(&d, &["git"]);
    rewrite_settings(&d, |v| {
        v["alias"] = serde_json::json!({ "aaa": ["shared"], "git": ["git"] });
    });
    set_config_alias(&d, &["git", "shared"]);
    let (code, out) = psc(&d, &["--json", "alias", "add", "git", "--reset", "--yes"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    assert_eq!(
        v["data"]["alias"],
        serde_json::json!(["git", "shared"]),
        "{out}"
    );
    // The earlier owner keeps its own list untouched, and `git` is now last in the file — the
    // claim order the hosts insert in, so its claim wins.
    let raw = std::fs::read_to_string(d.join("settings.json")).unwrap();
    assert!(raw.contains("\"shared\""), "{raw}");
    assert!(
        raw.rfind("\"git\"").unwrap() > raw.rfind("\"aaa\"").unwrap(),
        "{raw}"
    );
}

/// The hosts' `word -> completion` table, exactly as `psc init` builds it.
fn alias_map(d: &std::path::Path) -> serde_json::Value {
    let out = d.join("init.json");
    let (code, txt) = psc(d, &["init", "--result", out.to_str().unwrap()]);
    assert_eq!(code, 0, "{txt}");
    parse_json(&std::fs::read_to_string(&out).unwrap())["aliasMap"].clone()
}

#[test]
fn a_later_claim_wins_and_a_redeclaration_takes_the_word_back() {
    // Two completions claim `shared`; the hosts insert in claim order, so the later claim owns it.
    // Re-declaring the earlier one moves it to the end — and it owns the word again.
    let d = make_data("json-alias-claim-order", "http://127.0.0.1:9");
    std::fs::create_dir_all(d.join("completions/aaa/language")).unwrap();
    std::fs::write(
        d.join("completions/aaa/config.json"),
        r#"{"id":"aaa-id","language":["en-US"],"alias":["shared"]}"#,
    )
    .unwrap();
    std::fs::write(d.join("completions/aaa/language/en-US.json"), "{}").unwrap();
    rewrite_settings(&d, |v| {
        v["alias"] = serde_json::json!({ "aaa": ["shared"], "git": ["git"] });
    });

    // `git` claims `shared` later → the later claim wins.
    let (code, out) = psc(&d, &["alias", "add", "git", "shared"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(alias_map(&d)["shared"], "git", "the later claim must win");

    // Changing any of `aaa`'s aliases moves it to the end → it owns `shared` again.
    let (code, out) = psc(&d, &["alias", "add", "aaa", "extra"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(
        alias_map(&d)["shared"],
        "aaa",
        "re-declaring must take the word back"
    );

    // `git` takes it back by re-declaring an alias it already has — the explicit form.
    let (code, out) = psc(&d, &["alias", "add", "git", "git"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(
        alias_map(&d)["shared"],
        "git",
        "re-declaring an existing alias must still move to the end"
    );
    // …and the list did not gain a duplicate (`git` already had `shared` from the claim above).
    let s: serde_json::Value =
        parse_json(&std::fs::read_to_string(d.join("settings.json")).unwrap());
    assert_eq!(
        s["alias"]["git"],
        serde_json::json!(["git", "shared"]),
        "{out}"
    );

    // Removing an alias is a subtraction, not a declaration: the ownership must not move.
    let (code, out) = psc(&d, &["alias", "rm", "aaa", "extra"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(
        alias_map(&d)["shared"],
        "git",
        "removing an alias must not change ownership"
    );

    // The listing shows the claim order, not alphabetical: `aaa` is declared last here, so it is
    // listed last even though it sorts first — that is how a user reads the current ownership.
    let (code, out) = psc(&d, &["alias", "add", "aaa", "extra2"]);
    assert_eq!(code, 0, "{out}");
    let (code, out) = psc(&d, &["--json", "alias"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    let names: Vec<&str> = v["data"]["aliases"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["name"].as_str().unwrap())
        .collect();
    assert_eq!(
        names,
        vec!["git", "aaa"],
        "the listing must follow the claim order, not alphabetical: {names:?}"
    );
}

#[test]
fn json_a_non_utf8_settings_file_fails_loudly_and_is_left_alone() {
    // A file we cannot decode is corruption, not absence: the run must stop with an error, and
    // the file must be left exactly as it is — nothing is backed up, nothing is overwritten.
    let d = make_data("json-settings-non-utf8", "http://127.0.0.1:9");
    let sp = d.join("settings.json");
    // UTF-16LE-ish bytes: not valid UTF-8, and not JSON either.
    let original: Vec<u8> = vec![0xFF, 0xFE, b'{', 0, b'}', 0];
    std::fs::write(&sp, &original).unwrap();

    let (code, out) = psc(&d, &["--json", "list"]);
    assert_ne!(
        code, 0,
        "a broken settings.json must not be silently ignored: {out}"
    );
    assert!(
        out.contains("settings.json"),
        "the error must name the file: {out}"
    );
    assert_eq!(
        std::fs::read(&sp).unwrap(),
        original,
        "the file must be left alone"
    );
    assert!(
        !d.join("settings.json.corrupt").exists(),
        "nothing is backed up any more — the file itself is the evidence"
    );
}

#[test]
fn json_completion_reset_answers_only_what_it_reset() {
    // A completion that is on disk and has stored config but no alias entry: `completion <name>
    // <key> <value>` allows that (name_status accepts a name whose directory exists), so a reset
    // must reset it — and then not report it as part of the resulting state.
    let d = make_data("json-completion-reset-scope", "http://127.0.0.1:9");
    rewrite_settings(&d, |v| {
        v["alias"] = serde_json::json!({});
        v["config"] = serde_json::json!({
            "language": "en-US",
            "completion": { "git": { "max_commit": 30 } }
        });
    });
    let (code, out) = psc(&d, &["--json", "completion", "--reset", "--yes"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    let names: Vec<&str> = v["data"]["completions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["name"].as_str().unwrap())
        .collect();
    assert!(
        !names.contains(&"git"),
        "reported without having been reset: {names:?}"
    );
}

#[test]
fn json_add_repairs_a_non_object_config_entry() {
    // A settings.json holding a non-object where a config map belongs is valid JSON, so it loads
    // fine — the merge of the manifest's config defaults must repair it, not unwrap it.
    let srv = spawn_server(vec![
        (
            "completions.json",
            r#"{"update":{"demo":"v1"},"meta":{}}"#.into(),
        ),
        (
            "completions/demo/config.json",
            r#"{"id":"demo-id","language":["en-US"]}"#.into(),
        ),
        (
            "completions/demo/language/en-US.json",
            r#"{"config":[{"name":"max_commit","value":30}]}"#.into(),
        ),
    ]);

    // ① `config.completion` itself is a number.
    let d = make_data("json-add-nonobject-completion", &srv);
    rewrite_settings(&d, |v| {
        v["config"]["completion"] = serde_json::json!(123);
    });
    let (code, out) = psc(&d, &["--json", "add", "demo"]);
    assert_eq!(code, 0, "{out}");
    assert!(v_ok(&parse_json(&out)), "{out}");
    let s: serde_json::Value =
        parse_json(&std::fs::read_to_string(d.join("settings.json")).unwrap());
    assert_eq!(s["config"]["completion"]["demo"]["max_commit"], 30, "{out}");

    // ② the completion's own entry is a number.
    let d2 = make_data("json-add-nonobject-entry", &srv);
    rewrite_settings(&d2, |v| {
        v["config"]["completion"] = serde_json::json!({ "demo": 123 });
    });
    let (code, out) = psc(&d2, &["--json", "add", "demo"]);
    assert_eq!(code, 0, "{out}");
    let s: serde_json::Value =
        parse_json(&std::fs::read_to_string(d2.join("settings.json")).unwrap());
    assert_eq!(s["config"]["completion"]["demo"]["max_commit"], 30, "{out}");
}

#[test]
fn json_add_dedups_repeated_names() {
    // `add demo demo` is one install: two workers would stage into the same pid-suffixed
    // directory in the same process, and one would delete the other's.
    let srv = spawn_server(demo_routes());
    let d = make_data("json-add-dedup", &srv);
    let (code, out) = psc(&d, &["--json", "add", "demo", "demo"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(
        v["data"]["completions"].as_array().unwrap().len(),
        1,
        "{out}"
    );
    assert!(v_ok(&v), "{out}");
    assert!(d.join("completions/demo").exists(), "{out}");
}

#[test]
fn json_rm_dedups_repeated_names() {
    let d = make_data("json-rm-dedup", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "rm", "git", "git"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(
        v["data"]["completions"].as_array().unwrap().len(),
        1,
        "{out}"
    );
    assert!(v_ok(&v), "{out}");
    assert!(!d.join("completions/git").exists(), "{out}");
}

#[test]
fn json_list_and_init_reject_arguments_they_do_not_take() {
    // A mistyped flag must be a usage error (exit 2), not a silently normal run (json.md §6).
    let d = make_data("json-list-args", "http://127.0.0.1:9");
    for argv in [
        vec!["--json", "list", "junk"],
        vec!["--json", "list", "--bogus"],
    ] {
        let (code, out) = psc(&d, &argv);
        assert_eq!(code, 2, "{argv:?} → {out}");
        let v = parse_json(&out);
        assert_eq!(v["ok"], false, "{out}");
        assert_eq!(v["error"]["code"], "too_many_params", "{out}");
    }
    // `init` is internal and has no `--json` form (its payload goes to `--result`), so only the
    // exit code is asserted here.
    let (code, out) = psc(&d, &["init", "junk"]);
    assert_eq!(code, 2, "{out}");
    assert!(!out.trim().is_empty(), "a usage error must say something");
}

#[test]
fn json_set_paths_reject_surplus_arguments() {
    // `config <group> <key> <value>` and `completion <name> <key> <value>` must not drop whatever
    // follows the value in silence — the reset form of the same command already rejects it.
    let d = make_data("json-set-surplus", "http://127.0.0.1:9");
    for argv in [
        vec!["--json", "config", "menu", "color_focus", "blue", "JUNK"],
        vec!["--json", "completion", "git", "enable_tip", "1", "JUNK"],
        vec![
            "--json", "config", "core", "language", "--reset", "extra", "--yes",
        ],
    ] {
        let (code, out) = psc(&d, &argv);
        assert_eq!(code, 2, "{argv:?} → {out}");
        assert_eq!(
            parse_json(&out)["error"]["code"],
            "too_many_params",
            "{out}"
        );
    }
    // A legal set still succeeds.
    let (code, out) = psc(&d, &["--json", "config", "menu", "color_focus", "blue"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(parse_json(&out)["ok"], true, "{out}");
}

#[test]
fn json_alias_rm_success_stdout_is_only_json() {
    let d = make_data("json-alias-rm-clean", "http://127.0.0.1:9");
    set_live_aliases(&d, &["git", "g", "gg"]);
    let (code, out) = psc(&d, &["--json", "alias", "rm", "git", "g"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    // A write answers with the resulting state, the same shape `add` uses.
    assert_eq!(v["data"]["name"], "git", "{out}");
    assert_eq!(
        v["data"]["alias"],
        serde_json::json!(["git", "gg"]),
        "{out}"
    );
}

#[test]
fn json_alias_add_success_stdout_is_only_json() {
    let d = make_data("json-alias-add-clean", "http://127.0.0.1:9");
    set_live_aliases(&d, &["git"]);
    let (code, out) = psc(&d, &["--json", "alias", "add", "git", "zz"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    assert_eq!(v["data"]["name"], "git", "{out}");
    assert_eq!(
        v["data"]["alias"],
        serde_json::json!(["git", "zz"]),
        "{out}"
    );
    assert_eq!(v["data"]["rejected"], serde_json::json!([]), "{out}");
}

#[test]
fn json_add_and_rm_no_args_report_param_err() {
    // Both commands route an empty argv through the same param_err, so both must report the
    // identical contract: the envelope's `too_few_params`, and exit 2 (a usage error).
    for cmd in ["add", "rm"] {
        let d = make_data(&format!("json-{cmd}-noargs"), "http://127.0.0.1:9");
        let (code, out) = psc(&d, &["--json", cmd]);
        assert_eq!(code, 2, "{cmd}: {out}");
        let v = parse_json(&out);
        assert_eq!(v["ok"], false, "{cmd}: {out}");
        assert_eq!(v["error"]["code"], "too_few_params", "{cmd}: {out}");
        assert!(
            !v["error"]["message"].as_str().unwrap().is_empty(),
            "{cmd}: {out}"
        );
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
    assert_eq!(v["data"]["completions"][0]["ok"], true, "{out}");
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
    assert_eq!(code, 1, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["data"]["completions"][0]["ok"], false, "{out}");
    assert_eq!(
        v["data"]["completions"][0]["error"]["code"], "not_available",
        "{out}"
    );
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
    assert_eq!(v["data"]["completions"][0]["ok"], true, "{out}");
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
    assert_eq!(v["data"]["completions"][0]["ok"], true, "{out}");
    assert!(!d.join("completions/demo").exists());
}

#[test]
fn json_rm_clears_all_notification_lists() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-rm-change", &srv);
    psc(&d, &["--json", "add", "demo"]);
    std::fs::write(
        d.join("temp/change.json"),
        r#"{"update":["demo"],"added":["demo"],"removed":["demo"],"renamed":[["old","demo"]]}"#,
    )
    .unwrap();
    let (code, out) = psc(&d, &["--json", "rm", "demo"]);
    assert_eq!(code, 0, "{out}");
    let change = parse_json(&std::fs::read_to_string(d.join("temp/change.json")).unwrap());
    assert_eq!(change["update"], serde_json::json!([]), "{change}");
    assert_eq!(change["added"], serde_json::json!([]), "{change}");
    assert_eq!(change["removed"], serde_json::json!([]), "{change}");
    assert_eq!(change["renamed"], serde_json::json!([]), "{change}");
}

#[test]
fn json_add_and_rm_unknown_name_report_in_band() {
    // An unknown name is a per-completion failure, not a whole-command abort: the envelope stays
    // ok, the item carries its name and a stable code, and the run still exits 1.
    let srv = spawn_server(demo_routes());
    for cmd in ["add", "rm"] {
        let d = make_data(&format!("flow-{cmd}-unknown"), &srv);
        let (code, out) = psc(&d, &["--json", cmd, "zzz-nope"]);
        assert_eq!(code, 1, "{cmd}: {out}");
        let v = parse_json(&out);
        let e = v["data"]["completions"][0].clone();
        assert_eq!(e["name"], "zzz-nope", "{cmd}: {out}");
        assert_eq!(e["ok"], false, "{cmd}: {out}");
        assert_eq!(e["error"]["code"], "not_available", "{cmd}: {out}");
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
    assert_eq!(v["ok"], true, "{out}");
    // Check-mode payload shape: the four library-change lists, under `data`.
    for key in ["update", "added", "removed", "renamed"] {
        assert!(v["data"].get(key).is_some(), "missing key {key} in {out}");
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
    let (srv, routes) = spawn_server_mut(vec![
        (
            "completions.json",
            r#"{"update":{"demo":"v2"},"meta":{}}"#.into(),
        ),
        (
            "completions/demo/config.json",
            r#"{"id":"demo-id","language":["en-US"]}"#.into(),
        ),
        ("completions/demo/language/en-US.json", "{}".into()),
    ]);
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
    routes.lock().unwrap().insert(
        "completions.json".into(),
        r#"{"update":{"demo":"v3"},"meta":{}}"#.into(),
    );
    let (code, out) = psc(&d, &["--json", "update", "demo"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(
        std::fs::read_to_string(d.join("completions/demo/.update")).unwrap(),
        "v3",
        "{out}"
    );
}

#[test]
fn json_add_rejects_a_language_entry_that_escapes_the_staging_dir() {
    // A downloaded config.json is remote input: its `language` entries name both a URL segment
    // and a local file, so a traversing tag must be rejected instead of written outside.
    let srv = spawn_server(vec![
        (
            "completions.json",
            r#"{"update":{"demo":"v1"},"meta":{}}"#.into(),
        ),
        (
            "completions/demo/config.json",
            r#"{"id":"demo-id","language":["../../../evil"]}"#.into(),
        ),
    ]);
    let d = make_data("json-add-evil-lang", &srv);
    let (code, out) = psc(&d, &["--json", "add", "demo"]);
    assert!(
        !d.join("evil.json").exists(),
        "language tag escaped the staging dir"
    );
    assert_ne!(code, 0, "{out}");
}

#[test]
fn json_update_save_failure_still_emits_one_document() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-update-savefail", &srv);
    psc(&d, &["--json", "add", "demo"]);
    let sp = d.join("settings.json");
    // Make the save fail deterministically: turn settings.json into a *directory*, so the atomic
    // replace (temp file + rename) cannot land. A read-only file would not do — the save renames
    // over it, and the containing directory's write permission allows that.
    std::fs::remove_file(&sp).unwrap();
    std::fs::create_dir(&sp).unwrap();
    let (code, out) = psc(&d, &["--json", "update", "demo"]);
    assert_eq!(code, 1, "{out}");
    assert_eq!(
        out.trim().lines().count(),
        1,
        "--json mode owes exactly one document: {out}"
    );
    // Nothing was persisted, so the command itself failed: one failure envelope rather than a
    // per-item list that would claim success.
    let v = parse_json(&out);
    assert_eq!(v["ok"], false, "{out}");
    assert_eq!(v["error"]["code"], "io", "{out}");
}

#[test]
fn json_update_named_unknown_reports_in_band() {
    // A NAMED update of a name that is neither installed nor indexed reports the failure
    // in-band (per-entry ok:false, exit 0). The silent skip applies only to `--all`
    // sweeps over installed-but-unindexed completions.
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-update-skip", &srv);
    let (code, out) = psc(&d, &["--json", "update", "zzz-nope"]);
    assert_eq!(code, 1, "{out}");
    let v = parse_json(&out);
    let e = v["data"]["completions"][0].clone();
    assert_eq!(e["name"], "zzz-nope");
    assert_eq!(e["ok"], false);
    assert_eq!(e["error"]["code"], "not_available");
}

#[test]
fn json_update_old_empty_when_everything_current() {
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-update-old", &srv);
    psc(&d, &["--json", "add", "demo"]); // installs at v2 == remote
    let (code, out) = psc(&d, &["--json", "update", "--old"]);
    assert_eq!(code, 0, "{out}");
    // Nothing out of date: a successful run with an empty result set, still one envelope.
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    assert_eq!(v["data"]["completions"], serde_json::json!([]), "{out}");
}

#[test]
fn json_destructive_operations_need_authorisation() {
    // The engine never prompts (design/json.md §7): without `--yes` it refuses with exit 2, so a
    // script gets a decision instead of a hung process, and `--json` never waits on a keypress.
    let d = make_data("json-needs-confirm", "http://127.0.0.1:9");
    for argv in [
        vec!["--json", "rm", "--all"],
        vec!["--json", "config", "--reset"],
        vec!["--json", "completion", "--reset"],
        vec!["--json", "alias", "--reset"],
    ] {
        let (code, out) = psc(&d, &argv);
        assert_eq!(code, 2, "{argv:?}: {out}");
        let v = parse_json(&out);
        assert_eq!(v["ok"], false, "{argv:?}: {out}");
        assert_eq!(v["error"]["code"], "needs_confirmation", "{argv:?}: {out}");
    }
}

#[test]
fn json_completion_write_reports_the_item_and_the_old_value() {
    let d = make_data("json-completion-set", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "completion", "git", "enable_tip", "1"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    // The item a read of that key answers with — the *stored* value, which here is the number 1
    // rather than the string the caller typed — plus what it was before (`null`: nothing was set).
    assert_eq!(v["data"]["name"], "git", "{out}");
    assert_eq!(v["data"]["key"], "enable_tip", "{out}");
    assert_eq!(v["data"]["value"], serde_json::json!(1), "{out}");
    assert_eq!(v["data"]["old"], serde_json::Value::Null, "{out}");
    // A second write reports what the first one stored.
    let (code, out) = psc(&d, &["--json", "completion", "git", "enable_tip", "0"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["data"]["value"], serde_json::json!(0), "{out}");
    assert_eq!(v["data"]["old"], serde_json::json!(1), "{out}");
}

#[test]
fn json_config_reset_reports_the_resulting_state() {
    let d = make_data("json-cfg-reset", "http://127.0.0.1:9");
    // One key: the reset answers exactly what a read of that key answers.
    psc(
        &d,
        &["--json", "config", "core", "url", "https://evil.example/x"],
    );
    let (code, out) = psc(&d, &["--json", "config", "core", "url", "--reset", "--yes"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["data"]["key"], "url", "{out}");
    let (code, out2) = psc(&d, &["--json", "config", "core", "url"]);
    assert_eq!(code, 0, "{out2}");
    let read = parse_json(&out2);
    assert_eq!(
        v["data"]["value"], read["data"]["value"],
        "a reset must answer the same item its read does: {out}"
    );
    // A whole group: the group's items, the same shape `config <group>` answers.
    let (code, out) = psc(&d, &["--json", "config", "core", "--reset", "--yes"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    let items = v["data"]["config"].as_array().unwrap();
    assert!(items.iter().all(|i| i["group"] == "core"), "{out}");
    assert!(items.iter().any(|i| i["key"] == "url"), "{out}");
    assert_eq!(v["meta"]["count"], items.len(), "{out}");
}

#[test]
fn json_completion_reset_reports_the_resulting_state() {
    let d = make_data("json-cmpl-reset", "http://127.0.0.1:9");
    psc(&d, &["--json", "completion", "git", "enable_tip", "1"]);
    // One name: what `completion <name>` answers, after the reset emptied the entry.
    let (code, out) = psc(&d, &["--json", "completion", "git", "--reset", "--yes"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["data"]["name"], "git", "{out}");
    assert_eq!(v["data"]["config"], serde_json::json!({}), "{out}");
    // Every completion: the listing shape.
    let (code, out) = psc(&d, &["--json", "completion", "--reset", "--yes"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert!(v["data"]["completions"].is_array(), "{out}");
}

// ---------- text mode: exit codes + human messages ----------

#[test]
fn json_completion_writes_are_in_band() {
    // The `completion` write paths must honour `--json` like `config`'s do: a caller that asks for
    // the machine contract gets it on every path, not only on the read ones.
    let d = make_data("json-completion-write", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "completion", "git", "enable_tip", "1"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(parse_json(&out)["ok"], true, "{out}");
    let (code, out) = psc(&d, &["--json", "completion", "git", "--reset", "--yes"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(parse_json(&out)["ok"], true, "{out}");
    let (code, out) = psc(&d, &["--json", "completion", "--reset", "--yes"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(parse_json(&out)["ok"], true, "{out}");
}
