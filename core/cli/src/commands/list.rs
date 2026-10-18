//! `psc list` — installed completions + extra trigger aliases.

use std::process::ExitCode;

use crate::data::Settings;
use crate::output::Out;

pub fn cmd_list(settings: &Settings, out: &Out, json: bool) -> ExitCode {
    if json {
        let arr: Vec<serde_json::Value> = settings
            .list()
            .iter()
            .map(|name| {
                let aliases = settings.alias.get(name).cloned().unwrap_or_default();
                serde_json::json!({ "completion": name, "aliases": aliases })
            })
            .collect();
        println!("{}", serde_json::to_string(&arr).unwrap_or_default());
        return ExitCode::SUCCESS;
    }
    for name in settings.list() {
        let aliases = settings.alias.get(&name).cloned().unwrap_or_default();
        // All trigger words, exactly like this command's JSON branch (`{"completion": …,
        // "aliases": …}`) and like PS's `_render_list`, which renders that JSON. Filtering out
        // the completion's own name made `psc list` disagree with `psc alias` for no visible
        // reason.
        if aliases.is_empty() {
            out.line(&name);
        } else {
            out.line(&format!("{name}: {}", aliases.join(", ")));
        }
    }
    ExitCode::SUCCESS
}
