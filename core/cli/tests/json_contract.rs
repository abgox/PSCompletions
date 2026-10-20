//! The `--json` contract: every command's machine-readable shape, in one place.
//!
//! This file is the format's specification — a shape change shows up here first.

mod common;

use common::*;

#[test]
fn json_root_reports_the_run() {
    // `psc --json` with no command word is the **root** response: what a run needs to know about itself — where it reads from, the version and language, the sources — instead of repeating it on every command's answer.
    // No response carries `meta` any more.
    let d = make_data("json-root", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    assert!(v.get("meta").is_none(), "{out}");
    let data = &v["data"];
    assert_eq!(
        data["dir"]["data"],
        serde_json::json!(d.to_string_lossy()),
        "{out}"
    );
    assert_eq!(
        data["file"]["settings"],
        serde_json::json!(d.join("settings.json").to_string_lossy()),
        "{out}"
    );
    assert_eq!(
        data["url"],
        serde_json::json!("http://127.0.0.1:9"),
        "{out}"
    );
    assert!(data["version"].is_string(), "{out}");
    assert!(data["language"].is_string(), "{out}");
    assert!(data.get("description").is_none(), "{out}");
}

#[test]
fn json_root_reports_the_installed_version_not_the_library_baseline() {
    // The root `version` is what is installed — the `ModuleVersion` beside the bridges — not the `psc` completion's own `config.json` version, which is the library baseline and only moves on `update`.
    // A machine with a new module and an un-updated library would otherwise report the old number.
    let d = make_data("json-root-version", "http://127.0.0.1:9");
    std::fs::create_dir_all(d.join("completions/psc")).unwrap();
    std::fs::write(
        d.join("completions/psc/config.json"),
        r#"{"id":"psc-id","language":["en-US"],"version":"PSCompletions 7.0.0"}"#,
    )
    .unwrap();
    let home = std::env::temp_dir().join(format!("psc-rootver-home-{}", std::process::id()));
    let copy = plant_script_install(&home, "8.0.1");
    let (code, out) = psc_installed(&copy, &d, &["--json"], &home);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["data"]["version"], "8.0.1", "{out}");
    std::fs::remove_dir_all(&home).ok();
}

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
    // The error is an object now: a stable code beside a message that must stay name-free (the host renders `name: message` itself).
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
    // A write answers the item a read of that key answers with, plus what it replaced.
    // An unreviewed source's notice rides alongside it.
    assert_eq!(v["data"]["key"], "url", "{out}");
    assert_eq!(v["data"]["value"], "https://evil.example/x", "{out}");
    assert_eq!(v["data"]["old"], "http://127.0.0.1:9", "{out}");
    assert!(
        !v["data"]["warning"].as_str().unwrap_or_default().is_empty(),
        "{out}"
    );
    // An official candidate carries no warning, and `old` is what the call above wrote — the proof that a write reports the value it replaced.
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
fn json_self_update_text_carries_the_template_colors() {
    // The text is the manifest's `info.self_update.*` template, and its `<@Color>` markup becomes ANSI **even though the host captures stdout** (so it is not a terminal) — the same rule `psc tpl` follows.
    // Before this the color was silently stripped, so the page read plain in every host that captures it (which is all of them).
    let d = make_data("json-selfupdate-color", "http://127.0.0.1:9");
    std::fs::create_dir_all(d.join("completions/psc/language")).unwrap();
    std::fs::write(
        d.join("completions/psc/config.json"),
        r#"{"id":"psc-id","language":["en-US"]}"#,
    )
    .unwrap();
    std::fs::write(
        d.join("completions/psc/language/en-US.json"),
        r#"{"info":{"self_update":{"unknown":["<@Cyan>head\n","<@Blue>{{Commands}}\n"]}}}"#,
    )
    .unwrap();
    let (code, out) = psc(&d, &["--self-update"]);
    assert_eq!(code, 0, "{out}");
    assert!(out.contains("\x1b[36m"), "cyan must survive: {out:?}");
    assert!(out.contains("\x1b[34m"), "blue must survive: {out:?}");
    assert!(
        out.ends_with("\x1b[0m"),
        "the reset closes the last tag: {out:?}"
    );
}

#[test]
fn json_invalid_subcommand_carries_the_parts_structured() {
    // `design/json.md` §4 documents `details: { token, valid }` for this failure: the parts travel structured so a machine caller need not parse the localized `message`.
    let d = make_data("json-cfg-details", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "config", "badgroup"]);
    assert_eq!(code, 2, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["error"]["code"], "invalid_subcommand", "{out}");
    assert_eq!(v["error"]["details"]["token"], "badgroup", "{out}");
    assert_eq!(
        v["error"]["details"]["valid"],
        serde_json::json!(["core", "menu", "context"]),
        "{out}"
    );
    // The human message still names the token, so the text mode loses nothing.
    assert!(
        v["error"]["message"]
            .as_str()
            .unwrap_or_default()
            .contains("badgroup"),
        "{out}"
    );
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
fn json_completion_enable_hooks_reset_is_guarded_too() {
    // `enable_hooks` is meaningless unless the completion declares hooks, and every path that names the key says so: read, set — and reset, which used to slip past the guard and answer `ok: true` for a completion with no hooks at all.
    let d = make_data("json-cmpl-hooks-guard", "http://127.0.0.1:9");
    let (code, out) = psc(
        &d,
        &[
            "--json",
            "completion",
            "git",
            "enable_hooks",
            "--reset",
            "--yes",
        ],
    );
    assert_eq!(code, 2, "a usage error exits 2: {out}");
    let v = parse_json(&out);
    assert_eq!(v["error"]["code"], "no_hooks", "{out}");
    // A whole-completion reset is deliberately not guarded: it also resets the keys that do apply.
    let (code2, out2) = psc(&d, &["--json", "completion", "git", "--reset", "--yes"]);
    assert_eq!(code2, 0, "{out2}");
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
    // Conflicts are deliberately not resolved: the config's words are declared as they are, even when another completion already claims one — the hosts resolve it by claim order, and the completion moves to the end of the map so its claim is the later one.
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
    // The earlier owner keeps its own list untouched, and `git` is now last in the file — the claim order the hosts insert in, so its claim wins.
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

    // The listing shows the claim order, not alphabetical: `aaa` is declared last here, so it is listed last even though it sorts first — that is how a user reads the current ownership.
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
    // A file we cannot decode is corruption, not absence: the run must stop with an error, and the file must be left exactly as it is — nothing is backed up, nothing is overwritten.
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
    // A completion that is on disk and has stored config but no alias entry: `completion <name> <key> <value>` allows that (name_status accepts a name whose directory exists), so a reset must reset it — and then not report it as part of the resulting state.
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
    // A settings.json holding a non-object where a config map belongs is valid JSON, so it loads fine — the merge of the manifest's config defaults must repair it, not unwrap it.
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
    // `add demo demo` is one install: two workers would stage into the same pid-suffixed directory in the same process, and one would delete the other's.
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
    // `init` is internal and has no `--json` form (its payload goes to `--result`), so only the exit code is asserted here.
    let (code, out) = psc(&d, &["init", "junk"]);
    assert_eq!(code, 2, "{out}");
    assert!(!out.trim().is_empty(), "a usage error must say something");
}

#[test]
fn json_set_paths_reject_surplus_arguments() {
    // `config <group> <key> <value>` and `completion <name> <key> <value>` must not drop whatever follows the value in silence — the reset form of the same command already rejects it.
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
fn json_name_errors_use_one_style() {
    // One code, one line: the **text** mode prints `<name>: <message>` — the colon form the listings and the status messages already use (`git: git, g`, `git: Added.`).
    // `rm`, `update` and `add` each built their own prefix and `name_error` had none, so the same failure read three ways.
    // (The JSON `message` stays name-free: the item already carries `name`.)
    let srv = spawn_server(demo_routes());
    let d = make_data("json-name-error-style", &srv);

    let (_, info_txt) = psc(&d, &["info", "zzz-nope"]);
    let canonical = info_txt
        .lines()
        .find(|l| l.contains("zzz-nope"))
        .unwrap_or_default()
        .trim()
        .to_string();
    assert!(canonical.starts_with("zzz-nope: "), "{canonical}");

    for argv in [
        vec!["rm", "zzz-nope"],
        vec!["update", "zzz-nope"],
        vec!["add", "zzz-nope"],
    ] {
        let (code, out) = psc(&d, &argv);
        assert_eq!(code, 1, "{argv:?} → {out}");
        let line = out
            .lines()
            .find(|l| l.contains("zzz-nope"))
            .unwrap_or_default()
            .trim();
        assert_eq!(line, canonical, "{argv:?}");
    }

    // The JSON item keeps `name` in its own field, so its message never repeats it.
    let (_, js) = psc(&d, &["--json", "rm", "zzz-nope"]);
    let v = parse_json(&js);
    let entry = &v["data"]["completions"][0];
    assert_eq!(entry["error"]["code"], "not_available", "{js}");
    assert!(
        !entry["error"]["message"]
            .as_str()
            .unwrap()
            .contains("zzz-nope"),
        "{js}"
    );
}

#[test]
fn json_update_rename_line_uses_the_one_style() {
    // A rename is a per-item status line like any other: `old: renamed to new`.
    // It used to be the one line that glued the name and the status together with a space.
    let (srv, routes) = spawn_server_mut(vec![
        (
            "completions.json",
            r#"{"update":{"old":"v1"},"meta":{"old":{"id":"demo-id","en-US":{"url":"https://demo.example","description":"Demo"}}}}"#.into(),
        ),
        (
            "completions/old/config.json",
            r#"{"id":"demo-id","language":["en-US"]}"#.into(),
        ),
        ("completions/old/language/en-US.json", "{}".into()),
        ("module/version.json", r#"{"version":"9.9.9"}"#.into()),
    ]);
    let d = make_data("json-rename-style", &srv);
    let (code, out) = psc(&d, &["add", "old"]);
    assert_eq!(code, 0, "{out}");

    // Renamed upstream: the stable id still matches, the name no longer does.
    {
        let mut r = routes.lock().unwrap();
        r.insert(
            "completions.json".into(),
            r#"{"update":{"demo":"v2"},"meta":{"demo":{"id":"demo-id","en-US":{"url":"https://demo.example","description":"Demo"}}}}"#.into(),
        );
        r.insert(
            "completions/demo/config.json".into(),
            r#"{"id":"demo-id","language":["en-US"]}"#.into(),
        );
        r.insert("completions/demo/language/en-US.json".into(), "{}".into());
    }

    let (code, out) = psc(&d, &["update", "old"]);
    assert_eq!(code, 0, "{out}");
    let line = out
        .lines()
        .find(|l| l.contains("renamed to"))
        .unwrap_or_default()
        .trim();
    assert!(line.starts_with("old: "), "{out}");
}

#[test]
fn json_list_and_alias_render_an_empty_alias_list_the_same_way() {
    // `key_line`'s rule: an empty value ends at the colon.
    // Both listings must follow it — they agreed with neither each other nor `config` / `completion`, and `alias` left an invisible trailing space in captured output.
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-empty-alias-line", &srv);
    psc(&d, &["add", "demo"]);
    // Removing every trigger word leaves the settings entry empty.
    psc(&d, &["alias", "rm", "demo", "demo"]);

    let (_, list_out) = psc(&d, &["list"]);
    let line = list_out.lines().find(|l| l.starts_with("demo")).unwrap();
    assert_eq!(line, "demo:", "{list_out}");

    let (_, alias_out) = psc(&d, &["alias"]);
    let line = alias_out.lines().find(|l| l.starts_with("demo")).unwrap();
    assert_eq!(line, "demo:", "{alias_out}");
}

#[test]
fn json_info_block_names_a_failed_entry_once() {
    // A failure is an error line, not a block entry: it names itself and takes no `[name]` heading, even when the run's other names succeed.
    // Single-name mode reads the same way.
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-info-block-name", &srv);
    psc(&d, &["add", "demo"]);

    let (code, out) = psc(&d, &["info", "demo", "zzz-nope"]);
    assert_eq!(code, 1, "{out}");
    assert!(out.contains("[demo]"), "{out}");
    assert!(!out.contains("[zzz-nope]"), "{out}");
    assert!(
        out.contains("zzz-nope: is not an available completion."),
        "{out}"
    );

    let (_, single) = psc(&d, &["info", "zzz-nope"]);
    assert!(
        single.contains("zzz-nope: is not an available completion."),
        "{single}"
    );
}

#[test]
fn json_info_renders_a_multi_line_description_as_a_block() {
    // `description` is the one value authored as several lines, so it renders as the label alone and then its lines at column 0 — a row shape of its own, not a general rule (another field gets its own decision when it appears).
    // The JSON keeps the index's array (`json.md` §3: JSON does no display work).
    let srv = spawn_server(vec![
        (
            "completions.json",
            r#"{"update":{"demo":"v1"},"meta":{"demo":{"en-US":{"url":"https://demo.example","description":"First line.\nSecond line."}}}}"#.into(),
        ),
        (
            "completions/demo/config.json",
            r#"{"id":"demo-id","language":["en-US"]}"#.into(),
        ),
        ("completions/demo/language/en-US.json", "{}".into()),
    ]);
    let d = make_data("flow-info-description", &srv);
    psc(&d, &["add", "demo"]);

    let (_, out) = psc(&d, &["info", "demo"]);
    assert!(
        out.contains("description:\nFirst line.\nSecond line.\n"),
        "{out}"
    );
    assert!(!out.contains("description: First line."), "{out}");
    // It is the last row: a multi-line block between single-line rows reads as a break.
    assert!(
        out.find("description:").unwrap() > out.find("path:").unwrap(),
        "{out}"
    );

    let (_, js) = psc(&d, &["--json", "info", "demo"]);
    assert_eq!(
        parse_json(&js)["data"]["completions"][0]["description"],
        serde_json::json!("First line.\nSecond line."),
        "{js}"
    );

    // One line reads the same way: the label stands alone, the value follows on its own line.
    let srv2 = spawn_server(demo_routes());
    let d2 = make_data("flow-info-description-one", &srv2);
    psc(&d2, &["add", "demo"]);
    let (_, one) = psc(&d2, &["info", "demo"]);
    assert!(one.contains("description:\nDemo\n"), "{one}");
    assert!(!one.contains("description: Demo"), "{one}");
}

#[test]
fn json_add_reports_in_argument_order_not_finish_order() {
    // A worker finishes when it finishes, so the report must slot its line and its entry by argument position: `demo` downloads while `zzz-nope` fails at once, and the failure used to print first.
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-add-order", &srv);
    let (code, out) = psc(&d, &["add", "demo", "zzz-nope"]);
    assert_eq!(code, 1, "{out}");
    let lines: Vec<&str> = out
        .lines()
        .filter(|l| l.starts_with("demo:") || l.starts_with("zzz-nope:"))
        .collect();
    assert_eq!(
        lines,
        vec!["demo: Added.", "zzz-nope: is not an available completion."],
        "{out}"
    );

    let (_, js) = psc(&d, &["--json", "add", "demo", "zzz-nope"]);
    let v = parse_json(&js);
    assert_eq!(v["data"]["completions"][0]["name"], "demo", "{js}");
    assert_eq!(v["data"]["completions"][1]["name"], "zzz-nope", "{js}");
}

#[test]
fn json_update_reports_in_argument_order_not_finish_order() {
    // The same rule as `add`: a worker finishes when it finishes, so each result — its text line and its JSON entry — follows the argument order.
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-update-order", &srv);
    psc(&d, &["add", "demo"]);
    let (code, out) = psc(&d, &["update", "demo", "zzz-nope"]);
    assert_eq!(code, 1, "{out}");
    let lines: Vec<&str> = out
        .lines()
        .filter(|l| l.starts_with("demo:") || l.starts_with("zzz-nope:"))
        .collect();
    assert_eq!(
        lines,
        vec![
            "demo: Updated.",
            "zzz-nope: is not an available completion."
        ],
        "{out}"
    );

    let (_, js) = psc(&d, &["--json", "update", "demo", "zzz-nope"]);
    let v = parse_json(&js);
    assert_eq!(v["data"]["completions"][0]["name"], "demo", "{js}");
    assert_eq!(v["data"]["completions"][1]["name"], "zzz-nope", "{js}");
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
    // Both commands route an empty argv through the same param_err, so both must report the identical contract: the envelope's `too_few_params`, and exit 2 (a usage error).
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

/// Index branch layout wins when both layouts serve a valid index: the client must prefer `.../raw/index/completions.json` over `.../raw/main/...`.

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

/// Named update of an installed-but-off-index completion reports an error (bulk `--all` still skips it silently).

#[test]
fn json_update_named_off_index_errors() {
    // `git` is installed here while the library does not carry it: neither `not_available` (nowhere) nor `not_installed` (never added) describes that, and the code must agree with the message a human reads.
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
        v["data"]["completions"][0]["error"]["code"], "not_in_library",
        "{out}"
    );
    assert_eq!(
        v["data"]["completions"][0]["error"]["message"], "is not in the completion library.",
        "{out}"
    );
    let (_, text) = psc(&d, &["update", "git"]);
    assert!(
        text.contains("git: is not in the completion library."),
        "{text}"
    );
}

/// Legacy mirrors serving only the old layout keep working: the index-branch candidate misses (shape check rejects the not-found body) and the client falls back to `.../raw/main/completions.json`.

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

/// Installing a completion that is new to the fresh index must not echo it back as "new to the library": the per-item result already reported it.
/// Unrelated newcomers are still reported.

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
    // An unknown name is a per-completion failure, not a whole-command abort: the envelope stays ok, the item carries its name and a stable code, and the run still exits 1.
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
    // One server whose index is REWRITTEN between calls: add demo at v2, bump the index to v3, then a named update must refresh `.update` to v3.
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
    // A downloaded config.json is remote input: its `language` entries name both a URL segment and a local file, so a traversing tag must be rejected instead of written outside.
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
    // Make the save fail deterministically: turn settings.json into a *directory*, so the atomic replace (temp file + rename) cannot land.
    // A read-only file would not do — the save renames over it, and the containing directory's write permission allows that.
    std::fs::remove_file(&sp).unwrap();
    std::fs::create_dir(&sp).unwrap();
    let (code, out) = psc(&d, &["--json", "update", "demo"]);
    assert_eq!(code, 1, "{out}");
    assert_eq!(
        out.trim().lines().count(),
        1,
        "--json mode owes exactly one document: {out}"
    );
    // Nothing was persisted, so the command itself failed: one failure envelope rather than a per-item list that would claim success.
    let v = parse_json(&out);
    assert_eq!(v["ok"], false, "{out}");
    assert_eq!(v["error"]["code"], "io", "{out}");
}

#[test]
fn json_update_named_unknown_reports_in_band() {
    // A NAMED update of a name that is neither installed nor indexed reports the failure in-band (per-entry ok:false, exit 0).
    // The silent skip applies only to `--all` sweeps over installed-but-unindexed completions.
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
fn json_update_resolves_a_name_with_a_mode_flag_by_precedence() {
    // A mode flag is an explicit instruction about a whole set, so it wins over a name — the same way `--all` already wins over `--old`.
    // A name is not an error there: it is redundant when the flag's set covers it, and the empty-result reply says what actually happened.
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-update-precedence", &srv);
    psc(&d, &["--json", "add", "demo"]); // installed at v2 == remote

    // `--all` re-fetches everything, so the named completion is updated through it.
    let (code, out) = psc(&d, &["--json", "update", "--all", "demo"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["data"]["completions"][0]["name"], "demo", "{out}");
    assert_eq!(v["data"]["completions"][0]["ok"], true, "{out}");

    // `--old` selects the out-of-date set: `demo` is current, so nothing runs — and says so.
    let (code, out) = psc(&d, &["--json", "update", "--old", "demo"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(
        parse_json(&out)["data"]["completions"],
        serde_json::json!([]),
        "{out}"
    );
    let (code, out) = psc(&d, &["update", "--old", "demo"]);
    assert_eq!(code, 0, "{out}");
    assert!(out.contains("up to date"), "{out}");

    // The flags keep their own order: `--all` still wins over `--old`.
    let (code, out) = psc(&d, &["--json", "update", "--all", "--old", "demo"]);
    assert_eq!(code, 0, "{out}");
    assert_eq!(
        parse_json(&out)["data"]["completions"][0]["name"],
        "demo",
        "{out}"
    );
}

#[test]
fn json_update_with_nothing_to_do_says_so() {
    // An empty result set is not silence.
    // The module prints `info.update.no` for the very same empty array (`PSCompletions.psm1`), so the text mode was the only surface saying nothing — and "nothing out of date" is exactly the case where "everything is up to date" is true.
    let srv = spawn_server(demo_routes());
    let d = make_data("flow-update-empty-text", &srv);
    // `git` is installed but is not in the remote index: neither mode selects anything.
    for argv in [vec!["update", "--old"], vec!["update", "--all"]] {
        let (code, out) = psc(&d, &argv);
        assert_eq!(code, 0, "{argv:?} → {out}");
        assert!(out.contains("up to date"), "{argv:?} → {out}");
    }
    // The JSON mode keeps its empty array: the line is a text-mode reply.
    let (_, js) = psc(&d, &["--json", "update", "--old"]);
    assert_eq!(
        parse_json(&js)["data"]["completions"],
        serde_json::json!([]),
        "{js}"
    );
    // A named update always has a result, so it never prints the line.
    psc(&d, &["add", "demo"]);
    let (code, out) = psc(&d, &["update", "demo"]);
    assert_eq!(code, 0, "{out}");
    assert!(!out.contains("up to date"), "{out}");
}

#[test]
fn json_destructive_operations_need_authorisation() {
    // The engine never prompts (design/json.md §7): without `--yes` it refuses with exit 2, so a script gets a decision instead of a hung process, and `--json` never waits on a keypress.
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
    // The item a read of that key answers with — the *stored* value, which here is the number 1 rather than the string the caller typed — plus what it was before (`null`: nothing was set).
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
    // The `completion` write paths must honour `--json` like `config`'s do: a caller that asks for the machine contract gets it on every path, not only on the read ones.
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

#[test]
fn json_add_reports_a_local_failure_as_io_not_network() {
    // The index came back but was unusable: the bytes arrived, so this is a local failure.
    // It used to be reported as `network`, which sends the user to the wrong place entirely.
    let srv = spawn_server(vec![("completions.json", "{ not json".to_string())]);
    let d = make_data("json-add-local-failure", &srv);
    let (code, out) = psc(&d, &["--json", "add", "demo"]);
    assert_ne!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], false, "{out}");
    assert_eq!(v["error"]["code"], "io", "{out}");
}

#[test]
fn json_rm_removes_a_plain_file_in_the_library() {
    // The library directory holds completions and nothing else, so a stray file there is junk the user is entitled to remove.
    // `remove_dir_all` failed on it and the error was swallowed, so `rm` answered `ok: true` and left the file on disk.
    let d = make_data("json-rm-plain-file", "http://127.0.0.1:9");
    std::fs::write(d.join("completions/plainfile"), "not a completion").unwrap();
    let (code, out) = psc(&d, &["--json", "rm", "plainfile"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    let item = &v["data"]["completions"][0];
    assert_eq!(item["ok"], true, "{out}");
    assert!(
        !d.join("completions/plainfile").exists(),
        "the file must actually be gone"
    );
}

#[test]
fn init_reports_a_failed_result_write() {
    // `--result` is how a host reads the payload: a swallowed write failure would hand it a missing file and exit 0, so the host would silently run on nothing.
    let d = make_data("init-result-write", "http://127.0.0.1:9");
    let bad = d.join("no-such-dir/out.json");
    let (code, out) = psc(&d, &["init", "--result", bad.to_str().unwrap()]);
    assert_ne!(code, 0, "{out}");
    assert!(out.contains("error:"), "{out}");
}

#[test]
fn json_completion_key_reset_actually_resets() {
    // A key reset on a completion with no stored config must still write the manifest's default.
    // The path used to look the map up without ensuring it, answer `ok: true` and change nothing.
    let d = make_data("json-completion-key-reset", "http://127.0.0.1:9");
    // The manifest default lives in the *language* file, as a `config` array of {name, value}.
    std::fs::write(
        d.join("completions/git/language/en-US.json"),
        r#"{"config":[{"name":"enable_tip","value":1}]}"#,
    )
    .unwrap();
    let (code, out) = psc(
        &d,
        &[
            "--json",
            "completion",
            "git",
            "enable_tip",
            "--reset",
            "--yes",
        ],
    );
    assert_eq!(code, 0, "{out}");
    assert_eq!(parse_json(&out)["ok"], true, "{out}");
    let settings: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(d.join("settings.json")).unwrap()).unwrap();
    assert_eq!(
        settings["config"]["completion"]["git"]["enable_tip"],
        serde_json::json!(1),
        "the reset must store the manifest default instead of silently doing nothing"
    );
}

#[test]
fn json_self_update_reports_an_unmanaged_copy() {
    // The test binary is not installed by anything, so the method is `unknown` and the payload names the routes a user should take.
    // `commands` is the part a machine acts on; the version fields stay strings even when nothing could be read, so the shape never varies.
    let d = make_data("json-self-update", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "--self-update"]);
    assert_eq!(code, 0, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], true, "{out}");
    assert_eq!(v["data"]["method"], "unknown", "{out}");
    assert_eq!(v["data"]["ran"], false, "{out}");
    assert!(v["data"]["current"].is_string(), "{out}");
    assert!(v["data"]["latest"].is_string(), "{out}");
    let commands = v["data"]["commands"].as_array().unwrap();
    assert!(
        commands.iter().any(|c| c == "Install-Module PSCompletions"),
        "{out}"
    );
}

#[test]
fn json_self_update_rejects_arguments() {
    // The flag takes nothing: a stray argument is a usage error (exit 2), not a normal run.
    let d = make_data("json-self-update-args", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--json", "--self-update", "extra"]);
    assert_eq!(code, 2, "{out}");
    let v = parse_json(&out);
    assert_eq!(v["ok"], false, "{out}");
    assert_eq!(v["error"]["code"], "too_many_params", "{out}");
}

#[test]
fn text_self_update_prints_the_commands_without_the_psc_completion() {
    // No `psc` completion in this data dir, so the localized templates are missing: the English fallback must still end with the commands, or the user is told to install something with nothing to type.
    let d = make_data("txt-self-update", "http://127.0.0.1:9");
    let (code, out) = psc(&d, &["--self-update"]);
    assert_eq!(code, 0, "{out}");
    assert!(out.contains("Install-Module PSCompletions"), "{out}");
    assert!(out.contains("scoop install abgox.PSCompletions"), "{out}");
}

#[test]
fn text_self_update_lets_the_installer_speak_for_a_script_install() {
    // The CLI runs `install.sh` for a script install, and that script already reports what it found and the rc lines to add.
    // A second line from the CLI repeating it is the same fact twice, so this method's text output is the installer's own.
    let srv = spawn_server(vec![
        ("module/version.json", r#"{"version":"8.0.0"}"#.to_string()),
        (
            "install.sh",
            "printf '[PSCompletions] 8.0.0 is already installed.\\n'\n".to_string(),
        ),
    ]);
    let d = make_data("txt-self-update-script", &srv);

    // The `script` method is evidence, not a guess: the running binary under the fixed directory, plus the marker `install.sh` writes.
    // The copy must be the one that *runs* — detection reads the binary's own path — so the test plants it and drives that.
    let home = std::env::temp_dir().join(format!("psc-script-home-{}", std::process::id()));
    let copy = plant_script_install(&home, "8.0.0");

    let (code, out) = psc_installed(&copy, &d, &["--self-update"], &home);
    assert_eq!(code, 0, "{out}");
    assert!(
        out.contains("8.0.0 is already installed."),
        "the installer's own line must reach the user: {out:?}"
    );
    assert!(
        !out.contains("up to date"),
        "the CLI repeated what the installer had already said: {out:?}"
    );

    // The machine-readable reply is untouched by that rule: it still names the method and whether the installer ran.
    let (_, js) = psc_installed(&copy, &d, &["--json", "--self-update"], &home);
    let v = parse_json(&js);
    assert_eq!(v["data"]["method"], "script", "{js}");
    assert_eq!(v["data"]["ran"], true, "{js}");
    std::fs::remove_dir_all(&home).ok();
}

#[test]
fn text_self_update_reports_installer_failures_in_the_module_language() {
    // The installer's own text is English — it is a shell script, and nothing localizes it — but the lines the *CLI* adds when it fails are the CLI's, so they follow the module language like every other CLI message.
    let srv = spawn_server(vec![("install.sh", "exit 3\n".to_string())]);
    let d = make_data("txt-self-update-failed", &srv);
    let home = std::env::temp_dir().join(format!("psc-fail-home-{}", std::process::id()));
    let copy = plant_script_install(&home, "8.0.0");

    let (code, out) = psc_installed(&copy, &d, &["--self-update"], &home);
    assert_eq!(code, 1, "{out}");
    assert!(
        out.contains("The install script failed (exit code 3)."),
        "{out:?}"
    );

    rewrite_settings(&d, |s| s["config"]["language"] = serde_json::json!("zh-CN"));
    let (_, zh) = psc_installed(&copy, &d, &["--self-update"], &home);
    assert!(zh.contains("安装脚本执行失败"), "{zh:?}");

    // The other failure is the fetch: the installer could not be downloaded at all, so the reason must travel with the line rather than replacing it.
    let dead = make_data("txt-self-update-fetch", "http://127.0.0.1:9");
    let (code, out) = psc_installed(&copy, &dead, &["--self-update"], &home);
    assert_eq!(code, 1, "{out}");
    assert!(
        out.contains("Could not download the install script"),
        "{out:?}"
    );
    assert!(out.contains("install.sh"), "the cause must travel: {out:?}");
    std::fs::remove_dir_all(&home).ok();
}
