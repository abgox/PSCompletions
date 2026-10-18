//! `psc list` — installed completions + extra trigger aliases.

use std::process::ExitCode;

use serde_json::json;

use crate::data::Settings;
use crate::output::{meta, ok, Out};

pub fn cmd_list(settings: &Settings, data_dir: &str, out: &Out, json: bool) -> ExitCode {
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
        // `psc alias` for no visible reason.
        if aliases.is_empty() {
            out.line(name);
        } else {
            out.line(&format!("{name}: {}", aliases.join(", ")));
        }
    }
    ExitCode::SUCCESS
}
