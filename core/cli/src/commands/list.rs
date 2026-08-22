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
        let extra: Vec<&str> = aliases
            .iter()
            .filter(|a| a.as_str() != name.as_str())
            .map(|s| s.as_str())
            .collect();
        if extra.is_empty() {
            out.line(&name);
        } else {
            out.line(&format!("{name}  {}", extra.join(" ")));
        }
    }
    ExitCode::SUCCESS
}
