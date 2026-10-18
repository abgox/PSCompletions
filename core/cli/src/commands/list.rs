//! `psc list` — installed completions + extra trigger aliases.

use std::process::ExitCode;

use serde_json::json;

use crate::data::Settings;
use crate::output::{key_line, meta, ok, Out};

pub fn cmd_list(
    args: &[String],
    settings: &Settings,
    data_dir: &str,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    // `list` takes no arguments: a mistyped flag is a usage error, not a silently normal run.
    if !args.is_empty() {
        return crate::validate::too_many_params(out, lang, json, data_dir);
    }
    // One data model, two renderings (design/json.md): the text mode prints what the JSON carries.
    let items: Vec<serde_json::Value> = settings
        .list()
        .iter()
        .map(|name| {
            json!({
                "name": name,
                "alias": settings.alias.get(name).cloned().unwrap_or_default(),
            })
        })
        .collect();
    if json {
        return ok(
            &json!({ "completions": items }),
            &meta(Some(items.len()), data_dir),
        );
    }
    for item in &items {
        let name = item["name"].as_str().unwrap_or_default();
        let aliases: Vec<&str> = item["alias"]
            .as_array()
            .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
            .unwrap_or_default();
        // All trigger words, exactly like this command's JSON and like PS's `_render_list`, which
        // renders that JSON. Filtering out the completion's own name made `psc list` disagree with
        // `psc alias` for no visible reason. `key_line` owns the shape, so an empty value ends at
        // the colon here too — like `config` / `completion`.
        out.line(&key_line(name, &aliases.join(", ")));
    }
    ExitCode::SUCCESS
}
