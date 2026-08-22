//! `psc init` — assemble the module's bootstrap state in one call (internal, module-driven).

use std::process::ExitCode;

use crate::data::config::sanitize_config;
use crate::data::{build_default_data, default_config, load_psc_info, Index, Settings};
use crate::net::resolve_urls;
use crate::output::Out;
use crate::postcheck::{psc_completion_present, restore_psc_completion};

/// Assemble the module's init state in one call
#[allow(clippy::too_many_arguments)]
pub fn cmd_init(
    settings_path: &str,
    settings: &mut Settings,
    completions_dir: &str,
    data_dir: &str,
    language: Option<&str>,
    result_file: Option<&str>,
    out: &Out,
) -> ExitCode {
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

    // The psc completion is the module's own: it carries the `info` templates and the
    // management completions. Install always bundles it; if its files are gone (a wiped
    // data dir or a partial deletion) re-fetch it so the init payload is not missing info.
    // This is the only network path in `init` — it fires solely in that extreme case; an
    // offline failure is tolerated because every later `psc init` retries it.
    if !psc_completion_present(completions_dir) {
        restore_psc_completion(settings_path, settings, data_dir);
    }

    let mut alias_map = serde_json::Map::new();
    for (completion, aliases) in &settings.alias {
        for a in aliases {
            alias_map.insert(a.clone(), serde_json::Value::String(completion.clone()));
        }
    }

    // `list` = known completions from the local completions.json index (stub `psc` when absent).
    // Re-read the file: `init`'s psc restore may have just downloaded it (it was absent at
    // startup), so the `index` loaded in main() would be stale here.
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
    let text = serde_json::to_string(&result).unwrap_or_default();
    if let Some(path) = result_file {
        // The init JSON is large (psc `info` templates); write to a file so the module can
        // read it without console width wrapping corrupting the payload.
        let _ = std::fs::write(path, text);
    } else {
        println!("{text}");
    }
    ExitCode::SUCCESS
}
