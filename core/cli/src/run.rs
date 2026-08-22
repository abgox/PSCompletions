//! Top-level CLI dispatch: parse global flags, route to the command implementations.

use std::process::ExitCode;

use crate::commands::{
    add::cmd_add, alias::cmd_alias, completion::cmd_completion, config::cmd_config, info::cmd_info,
    init::cmd_init, list::cmd_list, rm::cmd_rm, update::cmd_update,
};
use crate::data::{Index, Settings};
use crate::input::{normalize_data_dir, parse_args, print_help};
use crate::messages::msg_cli;
use crate::output::Out;
pub fn run(args: Vec<String>) -> ExitCode {
    let (data_arg, json, language_arg, result_arg, rest) = parse_args(&args);
    let Some(data_dir) = data_arg.or_else(|| std::env::var("PSC_DATA_DIR").ok()) else {
        eprintln!("psc: no data dir (pass --data <dir> or set PSC_DATA_DIR)");
        return ExitCode::FAILURE;
    };
    let data_dir = normalize_data_dir(&data_dir);
    let settings_path = format!("{data_dir}/settings.json");
    let completions_json = format!("{data_dir}/temp/completions.json");
    let completions_dir = format!("{data_dir}/completions");
    let mut settings = Settings::load(&settings_path).unwrap_or_default();
    let mut index = Index::load(&completions_json).unwrap_or_default();
    let lang = settings.language();
    let out = Out::new();

    if rest.is_empty() {
        print_help();
        return ExitCode::SUCCESS;
    }
    let cmd = rest[0].clone();
    let args = &rest[1..];
    match cmd.as_str() {
        "init" => cmd_init(
            &settings_path,
            &mut settings,
            &completions_dir,
            &data_dir,
            language_arg.as_deref(),
            result_arg.as_deref(),
            &out,
        ),
        "list" => cmd_list(&settings, &out, json),
        "info" => cmd_info(args, &settings, &index, &completions_dir, &out, json),
        "config" => cmd_config(args, &settings_path, &mut settings, &lang, &out, json),
        "completion" => cmd_completion(
            args,
            &settings_path,
            &mut settings,
            &index,
            &lang,
            &out,
            json,
        ),
        "alias" => cmd_alias(
            args,
            &settings_path,
            &mut settings,
            &index,
            &lang,
            &out,
            json,
        ),
        "add" => cmd_add(
            args,
            &settings_path,
            &mut settings,
            &mut index,
            &data_dir,
            &lang,
            &out,
            json,
        ),
        "rm" => cmd_rm(
            args,
            &settings_path,
            &mut settings,
            &index,
            &data_dir,
            &lang,
            &out,
            json,
        ),
        "update" => cmd_update(
            args,
            &settings_path,
            &mut settings,
            &mut index,
            &data_dir,
            &lang,
            &out,
            json,
        ),
        _ => {
            out.line(&msg_cli(&lang, "sub_cmd"));
            ExitCode::FAILURE
        }
    }
}
