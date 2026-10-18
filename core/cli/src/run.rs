//! Top-level CLI dispatch: parse global flags, route to the command implementations.

use std::process::ExitCode;

use crate::commands::{
    add::cmd_add, alias::cmd_alias, completion::cmd_completion, config::cmd_config, info::cmd_info,
    init::cmd_init, list::cmd_list, rm::cmd_rm, tpl::cmd_tpl, update::cmd_update,
};
use crate::data::{Index, Settings};
use crate::input::{normalize_data_dir, parse_args, print_help};
use crate::messages::msg_cli;
use crate::net::cleanup_stale_staging;
use crate::output::{fail, meta, Out};
pub fn run(args: Vec<String>) -> ExitCode {
    let (data_arg, json, language_arg, result_arg, yes, rest) = parse_args(&args);
    let Some(data_dir) = data_arg.or_else(|| std::env::var("PSCOMPLETIONS_DATA_DIR").ok()) else {
        eprintln!("psc: no data dir (pass --data <dir> or set PSCOMPLETIONS_DATA_DIR)");
        return ExitCode::FAILURE;
    };
    let data_dir = normalize_data_dir(&data_dir);
    let settings_path = format!("{data_dir}/settings.json");
    let completions_json = format!("{data_dir}/temp/completions.json");
    let completions_dir = format!("{data_dir}/completions");
    let mut settings = match Settings::load(&settings_path) {
        Ok(Some(s)) => s,
        Ok(None) => Settings::default(),
        // Corruption is reported, not papered over with defaults: the file is left alone, so the
        // user can fix or delete it and nothing they wrote is lost.
        Err(msg) => {
            return fail(
                &Out::new(),
                "settings_corrupt",
                &msg,
                json,
                &meta(None, &data_dir),
                false,
            );
        }
    };
    let mut index = Index::load(&completions_json).unwrap_or_default();
    // `--language` is this run's override for the message language (and for anything that renders
    // with it); `init` still receives the raw flag. Never written back: `settings` is untouched.
    let lang = language_arg.clone().unwrap_or_else(|| settings.language());
    let out = Out::new();

    if rest.is_empty() {
        print_help();
        return ExitCode::SUCCESS;
    }
    let cmd = rest[0].clone();
    let args = &rest[1..];
    // Sweep crash residue from staged downloads, but only for the commands that
    // produce it (`add`/`update`/`init` download; the rest never stage anything).
    // Two directory listings; never touches live data.
    if matches!(cmd.as_str(), "add" | "update" | "init") {
        cleanup_stale_staging(&data_dir);
    }
    // Destructive operations need explicit authorisation (design/json.md §7): the hosts ask the
    // human and add `--yes`, so a caller driving the engine directly must say so itself. The
    // engine never prompts — it stops with `needs_confirmation` and exit 2.
    let destructive =
        args.iter().any(|a| a == "--reset") || (cmd == "rm" && args.iter().any(|a| a == "--all"));
    if destructive && !yes {
        return fail(
            &out,
            "needs_confirmation",
            &msg_cli(&lang, "needs_confirmation"),
            json,
            &meta(None, &data_dir),
            true,
        );
    }
    let code = match cmd.as_str() {
        "init" => cmd_init(
            args,
            &settings_path,
            &mut settings,
            &completions_dir,
            &data_dir,
            language_arg.as_deref(),
            result_arg.as_deref(),
            &out,
        ),
        "list" => cmd_list(args, &settings, &data_dir, &lang, &out, json),
        // Internal, like `init`: the hosts render their `info` templates through the engine, so
        // the `{{…}}` grammar has exactly one implementation.
        "tpl" => cmd_tpl(args, &completions_dir, &lang, &settings),
        "info" => cmd_info(args, &settings, &index, &completions_dir, &lang, &out, json),
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
        // An unknown command is a usage error: `invalid_subcommand`, exit 2.
        _ => fail(
            &out,
            "invalid_subcommand",
            &msg_cli(&lang, "invalid_subcommand"),
            json,
            &meta(None, &data_dir),
            true,
        ),
    };
    code
}
