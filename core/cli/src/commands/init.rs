//! `psc init` — assemble the module's bootstrap state in one call (internal, module-driven).

use std::process::ExitCode;

use serde_json::Value;

use crate::data::config::sanitize_config;
use crate::data::{build_default_data, default_config, load_psc_info, Index, Settings};
use crate::net::resolve_urls;
use crate::output::Out;
use crate::postcheck::{psc_completion_present, restore_psc_completion};

/// Assemble the module's init state in one call
#[allow(clippy::too_many_arguments)]
pub fn cmd_init(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    completions_dir: &str,
    data_dir: &str,
    language: Option<&str>,
    result_file: Option<&str>,
    out: &Out,
) -> ExitCode {
    // Internal command: the module passes only the global flags plus this command's own `--flat`, so anything left over is a wrong invocation — a usage error, not a silent success.
    // `init` has no `--json` form (its payload goes to `--result`), so the message goes to stdout and the exit code carries the verdict.
    // `--flat` is the POSIX hosts' record stream (see `flat_init`); it is meaningless without a file to write it to.
    let flat = args.iter().any(|a| a == "--flat");
    if args.iter().any(|a| a != "--flat") {
        out.line(&crate::messages::msg_cli(
            &settings.language(),
            "too_many_params",
        ));
        return ExitCode::from(2);
    }
    if flat && result_file.is_none() {
        out.line("error: --flat requires --result <file>");
        return ExitCode::from(2);
    }
    let settings_exist = std::path::Path::new(settings_path).exists();
    let empty_settings = settings.alias.is_empty()
        && settings
            .config
            .as_object()
            .map(|o| o.is_empty())
            .unwrap_or(true);
    if !settings_exist || empty_settings {
        let lang = language.unwrap_or("en-US").to_string();
        let data = build_default_data(completions_dir, &lang);
        let alias = data["alias"]
            .as_object()
            .map(|o| {
                o.iter()
                    .map(|(k, val)| {
                        let arr = val
                            .as_array()
                            .map(|a| {
                                a.iter()
                                    .filter_map(|x| x.as_str().map(String::from))
                                    .collect::<Vec<String>>()
                            })
                            .unwrap_or_default();
                        (k.clone(), arr)
                    })
                    .collect()
            })
            .unwrap_or_default();
        *settings = Settings {
            alias,
            config: data["config"].clone(),
        };
        if let Err(e) = settings.save(settings_path) {
            out.line(&format!("error: {e}"));
            return ExitCode::FAILURE;
        }
    }

    // The psc completion is the module's own: it carries the `info` templates and the management completions.
    // Install always bundles it; if its files are gone (a wiped data dir or a partial deletion) re-fetch it so the init payload is not missing info.
    // This is the only network path in `init` — it fires solely in that extreme case; an offline failure is tolerated because every later `psc init` retries it.
    if !psc_completion_present(completions_dir) {
        restore_psc_completion(settings_path, settings, data_dir);
    }

    // Sorted by completion name so a legacy trigger collision (two completions claiming the same word) always resolves to the same owner on every machine.
    // New collisions are rejected at write time.
    // The order is the claim order: later claims overwrite earlier ones, so the last claim wins.
    let names: Vec<&String> = settings.alias.keys().collect();
    let mut alias_map = serde_json::Map::new();
    for completion in names {
        if let Some(aliases) = settings.alias.get(completion) {
            for a in aliases {
                alias_map.insert(a.clone(), serde_json::Value::String(completion.clone()));
            }
        }
    }

    // `list` = known completions from the local completions.json index (stub `psc` when absent).
    // Re-read the file: `init`'s psc restore may have just downloaded it (it was absent at startup), so the `index` loaded in main() would be stale here.
    let index_json = format!("{data_dir}/temp/completions.json");
    let index_list: Vec<String> = Index::load(&index_json)
        .map(|i| i.remote_names())
        .filter(|l| !l.is_empty())
        .unwrap_or_else(|| vec!["psc".to_string()]);

    let urls = resolve_urls(settings);
    let lang = settings.language();
    let info = load_psc_info(completions_dir, &lang);

    let defaults = default_config(&lang);
    if let Some(obj) = settings.config.as_object_mut() {
        if sanitize_config(obj, &defaults) {
            if let Err(e) = settings.save(settings_path) {
                out.line(&format!("error: {e}"));
                return ExitCode::FAILURE;
            }
        }
    }

    let result = serde_json::json!({
        "data": { "alias": settings.alias, "config": settings.config },
        "aliasMap": alias_map,
        "list": index_list,
        "url": urls.first().cloned().unwrap_or_default(),
        "urls": urls,
        "info": info,
        "default_config": default_config(&lang),
    });
    if flat {
        let bytes = flat_init(&result);
        if let Some(path) = result_file {
            if let Err(e) = std::fs::write(path, bytes) {
                out.line(&format!("error: {e}"));
                return ExitCode::FAILURE;
            }
        }
        return ExitCode::SUCCESS;
    }
    let text = serde_json::to_string(&result).unwrap_or_default();
    if let Some(path) = result_file {
        // The init JSON is large (psc `info` templates); write to a file so the module can read it without console width wrapping corrupting the payload.
        // A swallowed failure here would hand the host a missing file while the exit code said success, so it is reported like the settings save above.
        if let Err(e) = std::fs::write(path, text) {
            out.line(&format!("error: {e}"));
            return ExitCode::FAILURE;
        }
    } else {
        println!("{text}");
    }
    ExitCode::SUCCESS
}

/// Project the init payload into the POSIX hosts' NUL-delimited record stream.
/// `A` = an aliasMap entry, `C` = a scalar config entry; JSON stays the default output and PowerShell keeps using it.
fn flat_init(result: &Value) -> Vec<u8> {
    let mut bytes = Vec::new();
    if let Some(map) = result.get("aliasMap").and_then(Value::as_object) {
        for (alias, completion) in map {
            if let Some(completion) = completion.as_str() {
                push_record(&mut bytes, b'A', alias, completion);
            }
        }
    }
    if let Some(config) = result.pointer("/data/config").and_then(Value::as_object) {
        for (key, value) in config {
            if key == "completion" {
                continue;
            }
            match value {
                Value::String(s) => push_record(&mut bytes, b'C', key, s),
                Value::Number(n) => push_record(&mut bytes, b'C', key, &n.to_string()),
                Value::Bool(b) => push_record(&mut bytes, b'C', key, if *b { "1" } else { "0" }),
                _ => {}
            }
        }
    }
    bytes
}

/// `kind`, `key` and `value`, each NUL-terminated.
/// NUL is the shell-safe delimiter: only a hand-edited value can contain it, and such a record is dropped rather than allowed to split the stream.
fn push_record(bytes: &mut Vec<u8>, kind: u8, key: &str, value: &str) {
    if key.contains('\0') || value.contains('\0') {
        return;
    }
    bytes.push(kind);
    bytes.push(0);
    bytes.extend_from_slice(key.as_bytes());
    bytes.push(0);
    bytes.extend_from_slice(value.as_bytes());
    bytes.push(0);
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn records(bytes: &[u8]) -> Vec<(u8, String, String)> {
        let mut out = Vec::new();
        let mut fields = bytes.split(|b| *b == 0);
        while let Some(kind) = fields.next() {
            if kind.is_empty() {
                break;
            }
            let Some(key) = fields.next() else { break };
            let Some(value) = fields.next() else { break };
            out.push((
                kind[0],
                String::from_utf8_lossy(key).into_owned(),
                String::from_utf8_lossy(value).into_owned(),
            ));
        }
        out
    }

    #[test]
    fn flat_init_projects_alias_map_and_scalar_config() {
        let payload = json!({
            "aliasMap": { "git": "git", "g": "git", "spaced key": "a b" },
            "data": { "config": {
                "language": "zh-CN",
                "enable_tip": 1,
                "enable_list_loop": false,
                "switch": "line1\nline2\u{1f}",
                "completion": { "git": { "max_commit": 30 } },
                "nested": { "x": 1 },
                "arr": [1, 2],
                "nothing": null
            }}
        });
        let mut got = records(&flat_init(&payload));
        got.sort();
        let mut want = vec![
            (b'A', "g".to_string(), "git".to_string()),
            (b'A', "git".to_string(), "git".to_string()),
            (b'A', "spaced key".to_string(), "a b".to_string()),
            (b'C', "enable_list_loop".to_string(), "0".to_string()),
            (b'C', "enable_tip".to_string(), "1".to_string()),
            (b'C', "language".to_string(), "zh-CN".to_string()),
            (b'C', "switch".to_string(), "line1\nline2\u{1f}".to_string()),
        ];
        want.sort();
        assert_eq!(got, want);
    }

    #[test]
    fn flat_init_drops_a_value_containing_nul() {
        let payload = json!({
            "aliasMap": { "a\u{0}b": "git" },
            "data": { "config": { "language": "x\u{0}y", "switch": "ok" } }
        });
        assert_eq!(
            records(&flat_init(&payload)),
            vec![(b'C', "switch".to_string(), "ok".to_string())]
        );
    }
}
