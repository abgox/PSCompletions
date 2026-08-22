//! `psc` binary: platform-agnostic management CLI for PSCompletions.

use std::io::IsTerminal;
use std::process::ExitCode;

use serde_json::{json, Value};

use psc_cli::data::config::{sanitize_config, validate_value, CONFIG_GROUPS, CONFIG_KEYS};
use psc_cli::data::{
    build_default_data, default_config, load_psc_info, read_text, Index, LibraryChanges, Settings,
};
use psc_cli::net::{
    add_completion, completion_defaults, download_list, fetch_text, local_completion_id,
    refresh_settings_after_add, rename_completion, resolve_urls,
};

const COMPLETION_KEYS: &[&str] = &[
    "language",
    "enable_tip",
    "enable_tip_usage",
    "enable_tip_example",
    "enable_hooks",
];

struct Out {
    color: bool,
}

impl Out {
    fn new() -> Self {
        Out {
            color: std::io::stdout().is_terminal(),
        }
    }
    fn line(&self, s: &str) {
        println!("{}", self.render(s));
    }
    fn render(&self, s: &str) -> String {
        if self.color {
            colorize(s)
        } else {
            strip_colors(s)
        }
    }
}

fn color_code(tag: &str) -> &'static str {
    match tag {
        "Green" => "\x1b[32m",
        "Red" => "\x1b[31m",
        "Cyan" => "\x1b[36m",
        "Magenta" => "\x1b[35m",
        "Blue" => "\x1b[34m",
        "Yellow" => "\x1b[33m",
        _ => "\x1b[0m",
    }
}

fn colorize(s: &str) -> String {
    let mut out = String::new();
    let mut rest = s;
    while let Some(start) = rest.find("<@") {
        out.push_str(&rest[..start]);
        rest = &rest[start + 2..];
        if let Some(end) = rest.find('>') {
            out.push_str(color_code(&rest[..end]));
            rest = &rest[end + 1..];
        } else {
            out.push_str("<@");
            break;
        }
    }
    out.push_str(rest);
    out
}

fn strip_colors(s: &str) -> String {
    let mut out = String::new();
    let mut rest = s;
    while let Some(start) = rest.find("<@") {
        out.push_str(&rest[..start]);
        rest = &rest[start + 2..];
        if let Some(end) = rest.find('>') {
            rest = &rest[end + 1..];
        } else {
            out.push_str("<@");
            break;
        }
    }
    out.push_str(rest);
    out
}

/// Strip the global flags (`--data`, `--json`, `--language`, `--result`) out of argv.
///
/// For `--data`/`--language`/`--result` with `=` form, rejects empty values (e.g. `--data=`).
/// For space form, rejects if the next token starts with `-` (e.g. `--data --json`).
/// Trailing slashes/backslashes on `data_dir` are trimmed (done in `main`).
fn parse_args(
    args: &[String],
) -> (
    Option<String>,
    bool,
    Option<String>,
    Option<String>,
    Vec<String>,
) {
    let mut data = None;
    let mut json = false;
    let mut language = None;
    let mut result_file = None;
    let mut rest = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if let Some(v) = a.strip_prefix("--data=") {
            if !v.trim().is_empty() {
                data = Some(v.to_string());
            }
        } else if a == "--data"
            && i + 1 < args.len()
            && !args[i + 1].starts_with('-')
            && !args[i + 1].trim().is_empty()
        {
            data = Some(args[i + 1].clone());
            i += 1;
        } else if let Some(v) = a.strip_prefix("--language=") {
            if !v.trim().is_empty() {
                language = Some(v.to_string());
            }
        } else if a == "--language"
            && i + 1 < args.len()
            && !args[i + 1].starts_with('-')
            && !args[i + 1].trim().is_empty()
        {
            language = Some(args[i + 1].clone());
            i += 1;
        } else if let Some(v) = a.strip_prefix("--result=") {
            if !v.trim().is_empty() {
                result_file = Some(v.to_string());
            }
        } else if a == "--result"
            && i + 1 < args.len()
            && !args[i + 1].starts_with('-')
            && !args[i + 1].trim().is_empty()
        {
            result_file = Some(args[i + 1].clone());
            i += 1;
        } else if a == "--json" {
            json = true;
        } else {
            rest.push(a.clone());
        }
        i += 1;
    }
    (data, json, language, result_file, rest)
}

/// CLI messages: `key -> (zh-CN, en-US)`. Plain text only (the manifest `info` templates are
/// PowerShell-bound). Adding a message = add a row.
const MESSAGES: &[(&str, &str, &str)] = &[
    ("param_min", "参数不足。", "Too few parameters."),
    ("sub_cmd", "子命令错误。", "Invalid subcommand."),
    ("no_completion", "尚未添加该补全。", "Completion not added."),
    (
        "not_available",
        "不是一个可用的补全。",
        "is not an available completion.",
    ),
    (
        "config_done",
        "模块配置修改成功。",
        "Module config updated.",
    ),
    (
        "completion_done",
        "补全配置修改成功。",
        "Completion config updated.",
    ),
    (
        "alias_done",
        "触发器别名修改成功。",
        "Trigger aliases updated.",
    ),
    (
        "one_or_zero",
        "该配置只接受 0 或 1。",
        "This option only accepts 0 or 1.",
    ),
    (
        "config_val",
        "配置值无效。",
        "Invalid config value.",
    ),
    (
        "language_no_reset",
        "language 不是一个恒定的配置值，无法重置。",
        "language is not a constant config value and cannot be reset.",
    ),
    (
        "no_hooks",
        "该补全没有动态 hooks。",
        "This completion has no dynamic hooks.",
    ),
    (
        "psc_hooks_locked",
        "psc 自身的 hooks 是模块管理补全的核心，不能关闭。",
        "psc's own hooks are the core of the module's management completions and cannot be disabled.",
    ),
    ("add_done", "已添加。", "Added."),
    ("update_done", "已更新。", "Updated."),
    ("rm_done", "已移除。", "Removed."),
    ("updatable", "可更新的补全：", "Updatable completions:"),
    ("lib_add", "补全库中新增：", "Newly available in the library:"),
    ("lib_rm", "从补全库中移除：", "Removed from the library:"),
    ("lib_rename", "补全库中重命名：", "Renamed in the library:"),
    ("rename_done", "已重命名为", "renamed to"),
    ("update_no", "所有补全都是最新的。", "All completions are up to date."),
    (
        "update_skip",
        "链接补全，已跳过更新。",
        "Linked completion, update skipped.",
    ),
    (
        "has_wildcard",
        "不能包含通配符。",
        "Cannot contain wildcards.",
    ),
    (
        "cmd_exist",
        "与已有命令或别名冲突。",
        "Conflicts with an existing command or alias.",
    ),
    (
        "alias_exist",
        "该别名已存在。",
        "The alias already exists.",
    ),
    (
        "alias_unique",
        "不能移除最后一个触发器别名。",
        "Cannot remove the last trigger alias.",
    ),
    (
        "alias_not_found",
        "指定的触发器别名不存在。",
        "The specified trigger alias does not exist.",
    ),
];

/// Look up a bilingual CLI message (zh if the language starts with `zh`, else en).
fn msg_cli(lang: &str, key: &str) -> String {
    let zh = lang.starts_with("zh");
    MESSAGES
        .iter()
        .find(|(k, _, _)| *k == key)
        .map(|(_, z, e)| if zh { z.to_string() } else { e.to_string() })
        .unwrap_or_default()
}

/// Completion name status: 2=installed/local link (alias set or dir on disk), 1=remote-only, 0=unknown.
/// All subcommands that accept a completion name share this same determination.
fn name_status(settings: &Settings, index: &Index, completions_dir: &str, name: &str) -> u8 {
    if settings.alias.contains_key(name)
        || std::path::Path::new(&format!("{completions_dir}/{name}")).exists()
    {
        return 2;
    }
    if index.remote_names().iter().any(|n| n == name) {
        return 1;
    }
    0
}

/// Validate a completion name uniformly and report errors. `need_installed`: whether the command
/// requires the completion to be installed (rm/update/completion/alias).
/// Returns true when the name is valid.
fn name_valid(out: &Out, lang: &str, name: &str, status: u8, need_installed: bool) -> bool {
    if status == 0 {
        out.line(&format!("{name} {}", msg_cli(lang, "not_available")));
        return false;
    }
    if need_installed && status == 1 {
        out.line(&format!("{name}: {}", msg_cli(lang, "no_completion")));
        return false;
    }
    true
}

/// Bare-binary fallback help (only shown when invoked directly with no subcommand).
fn print_help() {
    println!("psc — PSCompletions CLI");
    println!();
    println!("Usage: psc <command> [args]  (data dir via --data <dir> or PSC_DATA_DIR)");
    println!("  list                   List installed completions");
    println!("  info <name>...         Show completion metadata");
    println!("  config [core|menu|context] <key> [<value>]   Get/set config");
    println!("  completion [<name> [<key> [<value>]]]        Per-completion special config");
    println!("  alias [add <name> <alias>...|rm <name> <alias>...]   Trigger aliases");
    println!("  add <name>... | --all   rm <name>... | --all");
    println!("  update [<name>... | --all | --old]");
}

/// Trim trailing separators, then restore a bare Windows drive (`C:` → `C:\`) so it stays
/// an absolute root instead of a drive-relative path.
fn normalize_data_dir(data_dir: &str) -> String {
    let trimmed = data_dir.trim_end_matches(['/', '\\']);
    if trimmed.len() == 2 && trimmed.ends_with(':') {
        format!("{trimmed}\\")
    } else {
        trimmed.to_string()
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
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

fn param_err(out: &Out, lang: &str) {
    out.line(&msg_cli(lang, "param_min"));
}

/// `<data>` dir from the settings path (`<data>/settings.json`).
fn data_dir_of(settings_path: &str) -> String {
    std::path::Path::new(settings_path)
        .parent()
        .map(|p| p.to_string_lossy().to_string())
        .unwrap_or_default()
}

/// Get (creating if needed) the per-completion config map in `settings.config.completion`.
fn ensure_completion_map(settings: &mut Settings) -> &mut serde_json::Map<String, Value> {
    if !settings.config.is_object() {
        settings.config = serde_json::json!({});
    }
    let obj = settings.config.as_object_mut().unwrap();
    let comp = obj
        .entry("completion")
        .or_insert_with(|| serde_json::json!({}));
    if !comp.is_object() {
        *comp = serde_json::json!({});
    }
    comp.as_object_mut().unwrap()
}

/// Restore a completion's trigger aliases to its config.json alias (or the name itself).
fn reset_alias(settings: &mut Settings, data_dir: &str, name: &str) {
    let config_path = format!("{data_dir}/completions/{name}/config.json");
    let aliases: Vec<String> = read_text(&config_path)
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .map(|config| {
            config
                .get("alias")
                .and_then(|a| a.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|x| x.as_str().map(String::from))
                        .collect::<Vec<_>>()
                })
                .filter(|a: &Vec<String>| !a.is_empty())
                .unwrap_or_else(|| vec![name.to_string()])
        })
        .unwrap_or_else(|| vec![name.to_string()]);
    settings.alias.insert(name.to_string(), aliases);
}

/// Run `work` over `items` with at most `workers` concurrent scoped threads.
fn run_parallel<T, F>(items: &[T], workers: usize, work: F)
where
    T: Sync,
    F: Fn(&T) + Sync,
{
    if items.is_empty() {
        return;
    }
    let workers = workers.clamp(1, items.len());
    let next = std::sync::atomic::AtomicUsize::new(0);
    std::thread::scope(|s| {
        for _ in 0..workers {
            s.spawn(|| loop {
                let i = next.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                if i >= items.len() {
                    break;
                }
                work(&items[i]);
            });
        }
    });
}

fn cmd_list(settings: &Settings, out: &Out, json: bool) -> ExitCode {
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

/// Assemble the module's init state in one call
#[allow(clippy::too_many_arguments)]
fn cmd_init(
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

/// Whether the psc completion's key files exist on disk (its own manifest + config).
fn psc_completion_present(completions_dir: &str) -> bool {
    std::path::Path::new(completions_dir)
        .join("psc")
        .join("config.json")
        .exists()
        && std::path::Path::new(completions_dir)
            .join("psc")
            .join("language")
            .join("en-US.json")
            .exists()
}

/// Re-fetch the psc completion (remote index + files) when its files are missing, restoring
/// the module's `info` templates and management completions. Best-effort: an offline failure
/// is tolerated because every later `psc init` (each session / menu start) retries it.
fn restore_psc_completion(settings_path: &str, settings: &mut Settings, data_dir: &str) {
    let urls = resolve_urls(settings);
    let Ok(v) = download_list(data_dir, &urls) else {
        return;
    };
    let version = v
        .get("update")
        .and_then(|u| u.as_object())
        .and_then(|o| o.get("psc"))
        .and_then(|x| x.as_str())
        .unwrap_or("")
        .to_string();
    if add_completion(data_dir, "psc", &urls, &version).unwrap_or(false) {
        if let Ok(()) = refresh_settings_after_add(settings, data_dir, "psc") {
            let _ = settings.save(settings_path);
        }
    }
}

/// Fetch the newest remote module version (first URL that returns a parseable `module/version.json`).
/// The CLI does not compare versions — it records whatever it fetched; the module compares the
/// value against its installed version at render time (replaces the background job / env var).
fn fetch_module_version(settings: &Settings) -> Option<String> {
    let urls = resolve_urls(settings);
    for u in urls {
        if let Ok(text) = fetch_text(&[u], "module/version.json") {
            if let Ok(v) = serde_json::from_str::<Value>(&text) {
                let newv = v
                    .get("version")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .trim_start_matches('v')
                    .to_string();
                if !newv.is_empty() && newv.chars().all(|c| c.is_ascii_digit() || c == '.') {
                    return Some(newv);
                }
            }
            // Successful fetch but unparseable: try the next mirror.
            continue;
        }
    }
    None
}

/// Pure post-operation diff: compute `added`/`removed`/`renamed`/`update` from the fresh index
/// and the installed settings, folding in the renames already executed during this command
/// (they no longer appear in the post-state diff — the old name is gone from settings — so
/// without them a rename would be misreported as added+removed).
fn compute_post_changes(
    data_dir: &str,
    settings: &Settings,
    old_list: &[String],
    index: &Index,
    executed_renames: &[(String, String)],
) -> LibraryChanges {
    let mut rename_map: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    for installed in settings.list() {
        let Some(id) = local_completion_id(data_dir, &installed) else {
            continue;
        };
        if let Some((new_name, _)) = index.ids.iter().find(|(_, v)| **v == id) {
            if new_name != &installed {
                rename_map.insert(installed.clone(), new_name.clone());
            }
        }
    }
    for (old, new) in executed_renames {
        rename_map.insert(old.clone(), new.clone());
    }
    let rename_keys: std::collections::HashSet<String> = rename_map.keys().cloned().collect();
    let rename_vals: std::collections::HashSet<String> = rename_map.values().cloned().collect();
    let new_list: Vec<String> = index.update.keys().cloned().collect();
    let mut changes = LibraryChanges::load(data_dir);
    let mut added: Vec<String> = new_list
        .iter()
        .filter(|n| !old_list.contains(n))
        .filter(|n| !rename_vals.contains(*n))
        .cloned()
        .collect();
    added.sort();
    changes.added = std::mem::take(&mut added);
    let mut removed: Vec<String> = old_list
        .iter()
        .filter(|n| !new_list.contains(n))
        .filter(|n| !rename_keys.contains(*n))
        .cloned()
        .collect();
    changes.removed = std::mem::take(&mut removed);
    let mut renamed: Vec<(String, String)> = rename_map.into_iter().collect();
    renamed.sort_by(|a, b| a.0.cmp(&b.0));
    changes.renamed = renamed;
    let mut need_update: Vec<String> = settings
        .list()
        .into_iter()
        .filter(|name| !rename_keys.contains(name))
        .filter(|name| index.update.contains_key(name))
        .filter(|name| {
            let dir = format!("{data_dir}/completions/{name}");
            if let Ok(meta) = std::fs::symlink_metadata(&dir) {
                if meta.file_type().is_symlink() {
                    return false;
                }
            }
            let local = std::fs::read_to_string(format!("{dir}/.update")).unwrap_or_default();
            let remote = index.update.get(name).cloned().unwrap_or_default();
            local.trim() != remote
        })
        .collect();
    need_update.sort();
    changes.update = need_update;
    changes
}

/// After an add/update completes, refresh temp/change.json (update/added/removed/renamed/module)
/// by diffing the pre-operation index snapshot against the fresh one, and record the remote module
/// version. Runs synchronously AFTER the operation so a completion this command just touched is
/// not reported as needing an update; `old_list` is captured before `download_list` overwrites the
/// cache. On a fetch failure the existing `module` value is preserved (don't drop a pending notice
/// just because one check hit the network and another didn't).
fn record_post_check(
    data_dir: &str,
    settings: &Settings,
    old_list: &[String],
    index: &Index,
    executed_renames: &[(String, String)],
) {
    let mut changes = compute_post_changes(data_dir, settings, old_list, index, executed_renames);
    if let Some(v) = fetch_module_version(settings) {
        changes.module = Some(v);
    }
    changes.save(data_dir);
}

#[allow(clippy::too_many_arguments)]
fn cmd_add(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    index: &mut Index,
    data_dir: &str,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    if args.is_empty() {
        param_err(out, lang);
        return ExitCode::FAILURE;
    }
    // Snapshot the pre-operation update keys so the post-check can diff added/removed/renamed.
    let old_list: Vec<String> = read_text(&format!("{data_dir}/temp/completions.json"))
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .and_then(|v| {
            v.get("update")
                .and_then(|u| u.as_object())
                .map(|o| o.keys().cloned().collect())
        })
        .unwrap_or_default();
    let urls = resolve_urls(settings);
    let list = match download_list(data_dir, &urls) {
        Ok(v) => {
            *index = Index::from_value(v);
            index.remote_names()
        }
        Err(e) => {
            if !json {
                out.line(&format!("error: {e}"));
            }
            return ExitCode::FAILURE;
        }
    };
    let all = args.iter().any(|a| a == "--all");
    let names: Vec<String> = if all {
        list.clone()
    } else {
        args.iter()
            .filter(|a| a.as_str() != "--all")
            .cloned()
            .collect()
    };
    // Download multiple completions concurrently (shared client + bounded worker pool).
    let settings_lock = std::sync::Mutex::new(&mut *settings);
    let results: std::sync::Mutex<Vec<serde_json::Value>> = std::sync::Mutex::new(Vec::new());
    let index_ref: &Index = index;
    run_parallel(&names, 8, |name| {
        let entry = if !list.contains(name) {
            // Not in the remote library: report + mark failure
            if !json {
                out.line(&format!("{name} {}", msg_cli(lang, "not_available")));
            }
            serde_json::json!({
                "completion": name,
                "ok": false,
                "error": msg_cli(lang, "not_available")
            })
        } else {
            let version = index_ref.update.get(name).cloned().unwrap_or_default();
            match add_completion(data_dir, name, &urls, &version) {
                Ok(_updated) => {
                    let mut sg = settings_lock.lock().unwrap();
                    if let Err(e) = refresh_settings_after_add(&mut sg, data_dir, name) {
                        if !json {
                            out.line(&format!("error: {e}"));
                        }
                        serde_json::json!({"completion": name, "ok": false, "error": e})
                    } else {
                        if !json {
                            out.line(&format!("{name}: {}", msg_cli(lang, "add_done")));
                        }
                        serde_json::json!({"completion": name, "ok": true})
                    }
                }
                Err(e) => {
                    if !json {
                        out.line(&format!("{name}: error: {e}"));
                    }
                    serde_json::json!({"completion": name, "ok": false, "error": e})
                }
            }
        };
        results.lock().unwrap().push(entry);
    });
    if let Err(e) = settings.save(settings_path) {
        if !json {
            out.line(&format!("error: {e}"));
        }
        return ExitCode::FAILURE;
    }
    record_post_check(data_dir, settings, &old_list, index, &[]);
    if json {
        let arr = results.lock().unwrap().clone();
        println!("{}", serde_json::to_string(&arr).unwrap_or_default());
    }
    let had_error = results.lock().unwrap().iter().any(|v| v["ok"] != true);
    if had_error {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

/// Remove named completions (or all), and drop them from settings + the need-update list.
#[allow(clippy::too_many_arguments)]
fn cmd_rm(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    index: &Index,
    data_dir: &str,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    if args.is_empty() {
        param_err(out, lang);
        return ExitCode::FAILURE;
    }
    let all = args.iter().any(|a| a == "--all");
    let completions_dir = format!("{data_dir}/completions");
    let names: Vec<String> = if all {
        // Disk is the source of truth for `rm --all`: settings may be empty or stale
        // (a lost settings.json, manual copies). `psc` itself is kept — it is the
        // module's own completion and init re-adds it anyway, so there's no network
        // round-trip to re-fetch it here.
        let mut names = settings.list();
        if let Ok(entries) = std::fs::read_dir(&completions_dir) {
            for e in entries.flatten() {
                let n = e.file_name().to_string_lossy().to_string();
                if !names.contains(&n) {
                    names.push(n);
                }
            }
        }
        names.retain(|n| n != "psc");
        names
    } else {
        args.iter().filter(|a| *a != "--all").cloned().collect()
    };
    if names.is_empty() {
        if all {
            if json {
                println!("[]");
            }
            return ExitCode::SUCCESS;
        }
        param_err(out, lang);
        return ExitCode::FAILURE;
    }
    let mut results: Vec<serde_json::Value> = Vec::new();
    let mut removed_any = false;
    for name in &names {
        let status = name_status(settings, index, &completions_dir, name);
        let invalid = if status == 0 {
            Some(msg_cli(lang, "not_available"))
        } else if status == 1 {
            Some(msg_cli(lang, "no_completion"))
        } else {
            None
        };
        if let Some(msg) = invalid {
            if !json {
                out.line(&format!("{name} {msg}"));
            }
            results.push(serde_json::json!({"completion": name, "ok": false, "error": msg}));
            continue;
        }
        psc_cli::data::remove_completion_entry(data_dir, name);
        removed_any = true;
        settings.alias.remove(name);
        if let Some(comp) = settings
            .config
            .get_mut("completion")
            .and_then(|c| c.as_object_mut())
        {
            comp.remove(name);
        }
        results.push(serde_json::json!({"completion": name, "ok": true}));
    }
    // Drop removed completions from the persisted update list.
    let mut changes = LibraryChanges::load(data_dir);
    changes.update.retain(|u| !names.iter().any(|n| n == u));
    changes.save(data_dir);
    if let Err(e) = settings.save(settings_path) {
        if !json {
            out.line(&format!("error: {e}"));
        }
        return ExitCode::FAILURE;
    }
    if removed_any && !json {
        out.line(&msg_cli(lang, "rm_done"));
    }
    if json {
        println!("{}", serde_json::to_string(&results).unwrap_or_default());
    }
    if results.iter().any(|v| v["ok"] != true) {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

#[allow(clippy::too_many_arguments)]
fn cmd_update(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    index: &mut Index,
    data_dir: &str,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    let old_list: Vec<String> = read_text(&format!("{data_dir}/temp/completions.json"))
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .and_then(|v| {
            v.get("update")
                .and_then(|u| u.as_object())
                .map(|o| o.keys().cloned().collect())
        })
        .unwrap_or_default();
    let urls = resolve_urls(settings);
    let list = match download_list(data_dir, &urls) {
        Ok(v) => {
            *index = Index::from_value(v);
            index.remote_names()
        }
        Err(e) => {
            out.line(&format!("error: {e}"));
            return ExitCode::FAILURE;
        }
    };
    // Rename detection: a locally installed completion whose stable id now maps to a different remote name has been renamed upstream.
    let mut rename_map: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    for installed in settings.list() {
        let Some(id) = local_completion_id(data_dir, &installed) else {
            continue;
        };
        if let Some((new_name, _)) = index.ids.iter().find(|(_, v)| **v == id) {
            if new_name != &installed {
                rename_map.insert(installed.clone(), new_name.clone());
            }
        }
    }
    let needs_update = |name: &String| -> bool {
        let dir = format!("{data_dir}/completions/{name}");
        if let Ok(meta) = std::fs::symlink_metadata(&dir) {
            if meta.file_type().is_symlink() {
                return false;
            }
        }
        let local = std::fs::read_to_string(format!("{dir}/.update")).unwrap_or_default();
        let remote = index.update.get(name).cloned().unwrap_or_default();
        local.trim() != remote
    };
    let need_update: Vec<String> = settings
        .list()
        .into_iter()
        .filter(|name| (list.contains(name) || rename_map.contains_key(name)) && needs_update(name))
        .collect();

    let is_check = args.is_empty();
    if is_check {
        let rename_keys: std::collections::HashSet<String> = rename_map.keys().cloned().collect();
        let update_no_rename: Vec<String> = need_update
            .iter()
            .filter(|n| !rename_keys.contains(*n))
            .cloned()
            .collect();
        let new_list: Vec<String> = index.update.keys().cloned().collect();
        let mut added: Vec<String> = new_list
            .iter()
            .filter(|n| !old_list.contains(n))
            .cloned()
            .collect();
        let mut removed: Vec<String> = old_list
            .iter()
            .filter(|n| !new_list.contains(n))
            .cloned()
            .collect();
        let rename_vals: std::collections::HashSet<String> = rename_map.values().cloned().collect();
        added.retain(|n| !rename_vals.contains(n));
        removed.retain(|n| !rename_keys.contains(n));
        added.sort();
        removed.sort();
        let mut renamed: Vec<(String, String)> = rename_map
            .iter()
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        renamed.sort_by(|a, b| a.0.cmp(&b.0));
        let mut changes = LibraryChanges::load(data_dir);
        changes.update = update_no_rename.clone();
        changes.added = added.clone();
        changes.removed = removed.clone();
        changes.renamed = renamed.clone();
        if let Some(v) = fetch_module_version(settings) {
            changes.module = Some(v);
        }
        changes.save(data_dir);

        let mut any = false;
        let updatable_no_rename: Vec<&String> = need_update
            .iter()
            .filter(|n| !rename_keys.contains(*n))
            .collect();
        if !updatable_no_rename.is_empty() {
            any = true;
            out.line(&msg_cli(lang, "updatable"));
            for n in &updatable_no_rename {
                out.line(&format!("  {n}"));
            }
        }
        if !added.is_empty() {
            any = true;
            out.line(&msg_cli(lang, "lib_add"));
            for n in &added {
                out.line(&format!("  {n}"));
            }
        }
        if !removed.is_empty() {
            any = true;
            out.line(&msg_cli(lang, "lib_rm"));
            for n in &removed {
                out.line(&format!("  {n}"));
            }
        }
        if !renamed.is_empty() {
            any = true;
            out.line(&msg_cli(lang, "lib_rename"));
            for (old_n, new_n) in &renamed {
                out.line(&format!("  {old_n} -> {new_n}"));
            }
        }
        if !any {
            out.line(&msg_cli(lang, "update_no"));
        }
        if json {
            println!(
                "{}",
                serde_json::to_string(&json!({
                    "update": update_no_rename,
                    "added": added,
                    "removed": removed,
                    "renamed": renamed.iter().map(|(a, b)| json!([a, b])).collect::<Vec<_>>(),
                }))
                .unwrap_or_default()
            );
        }
        return ExitCode::SUCCESS;
    }
    let all = args.iter().any(|a| a == "--all");
    let old = args.iter().any(|a| a == "--old");
    let named: Vec<String> = args
        .iter()
        .filter(|a| *a != "--all" && *a != "--old")
        .cloned()
        .collect();
    // `--all` force-updates every installed completion; `--old` updates only the out-of-date
    // ones; named targets are re-fetched unconditionally (naming a completion IS the intent to
    // reinstall it).
    let names: Vec<String> = if all {
        settings.list()
    } else if old {
        need_update.clone()
    } else {
        named
    };
    let installed: std::collections::HashSet<String> = settings.list().into_iter().collect();
    let settings_lock = std::sync::Mutex::new(&mut *settings);
    let had_error = std::sync::atomic::AtomicBool::new(false);
    let results: std::sync::Mutex<Vec<Value>> = std::sync::Mutex::new(Vec::new());
    let index_ref: &Index = index;
    run_parallel(&names, 8, |name| {
        let known = installed.contains(name)
            || std::path::Path::new(&format!("{data_dir}/completions/{name}")).exists()
            || list.contains(name);
        if !known {
            had_error.store(true, std::sync::atomic::Ordering::SeqCst);
            let err = msg_cli(lang, "not_available");
            results
                .lock()
                .unwrap()
                .push(json!({"completion": name, "ok": false, "error": err}));
            if !json {
                out.line(&format!("{name} {err}"));
            }
            return;
        }
        // Renamed upstream: migrate the old install (download new files, move settings, drop the old directory) instead of a plain update.
        // Must run before the `list.contains` check — a renamed old name no longer exists in the remote list.
        if let Some(new_name) = rename_map.get(name).cloned() {
            let version = index_ref.update.get(&new_name).cloned().unwrap_or_default();
            let mut sg = settings_lock.lock().unwrap();
            match rename_completion(&mut sg, data_dir, name, &new_name, &urls, &version) {
                Ok(()) => {
                    if json {
                        results.lock().unwrap().push(json!({
                            "completion": new_name, "ok": true, "renamed_from": name
                        }));
                    } else {
                        out.line(&format!(
                            "{name} {} {new_name}",
                            msg_cli(lang, "rename_done")
                        ));
                    }
                }
                Err(e) => {
                    had_error.store(true, std::sync::atomic::Ordering::SeqCst);
                    if json {
                        results
                            .lock()
                            .unwrap()
                            .push(json!({"completion": name, "ok": false, "error": e}));
                    } else {
                        out.line(&format!("{name}: error: {e}"));
                    }
                }
            }
            return;
        }
        if !list.contains(name) {
            had_error.store(true, std::sync::atomic::Ordering::SeqCst);
            let err = msg_cli(lang, "no_completion");
            results
                .lock()
                .unwrap()
                .push(json!({"completion": name, "ok": false, "error": err}));
            if !json {
                out.line(&format!("{name}: {err}"));
            }
            return;
        }
        let version = index_ref.update.get(name).cloned().unwrap_or_default();
        match add_completion(data_dir, name, &urls, &version) {
            Ok(updated) => {
                if !updated {
                    let err = msg_cli(lang, "update_skip");
                    results
                        .lock()
                        .unwrap()
                        .push(json!({"completion": name, "ok": false, "error": err}));
                    if !json {
                        out.line(&format!("{name}: {err}"));
                    }
                    return;
                }
                let mut sg = settings_lock.lock().unwrap();
                if let Err(e) = refresh_settings_after_add(&mut sg, data_dir, name) {
                    had_error.store(true, std::sync::atomic::Ordering::SeqCst);
                    if json {
                        results
                            .lock()
                            .unwrap()
                            .push(json!({"completion": name, "ok": false, "error": e}));
                    } else {
                        out.line(&format!("error: {e}"));
                    }
                }
                if json {
                    results
                        .lock()
                        .unwrap()
                        .push(json!({"completion": name, "ok": true}));
                } else {
                    out.line(&format!("{name}: {}", msg_cli(lang, "update_done")));
                }
            }
            Err(e) => {
                had_error.store(true, std::sync::atomic::Ordering::SeqCst);
                if json {
                    results
                        .lock()
                        .unwrap()
                        .push(json!({"completion": name, "ok": false, "error": e}));
                } else {
                    out.line(&format!("{name}: error: {e}"));
                }
            }
        }
    });
    if json {
        let results = results.lock().unwrap();
        println!("{}", serde_json::to_string(&*results).unwrap_or_default());
    }
    // Persist the renames actually executed during this update so the module's pending
    // notifications can still show them even if the JSON results were not consumed.
    let executed_renames: Vec<(String, String)> = {
        let results = results.lock().unwrap();
        results
            .iter()
            .filter_map(|v| {
                let from = v.get("renamed_from").and_then(|x| x.as_str());
                let to = v.get("completion").and_then(|x| x.as_str());
                match (from, to) {
                    (Some(f), Some(t)) => Some((f.to_string(), t.to_string())),
                    _ => None,
                }
            })
            .collect()
    };
    // Refresh the persisted post-check state (added/removed/renamed/update/module) and check the module version.
    // Runs AFTER the operation, diffing the pre-operation snapshot against the fresh index.
    record_post_check(data_dir, settings, &old_list, index, &executed_renames);
    if let Err(e) = settings.save(settings_path) {
        out.line(&format!("error: {e}"));
        return ExitCode::FAILURE;
    }
    if had_error.load(std::sync::atomic::Ordering::SeqCst) {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

fn cmd_info(
    args: &[String],
    settings: &Settings,
    index: &Index,
    completions_dir: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    let lang = settings.language();
    let owned;
    let args: &[String] = if args.is_empty() {
        let mut v: Vec<String> = settings.alias.keys().cloned().collect();
        v.sort();
        owned = v;
        &owned
    } else {
        args
    };
    if json {
        let mut arr = Vec::new();
        let mut had_error = false;
        for name in args {
            let status = name_status(settings, index, completions_dir, name);
            if !name_valid(out, &lang, name, status, false) {
                had_error = true;
                continue;
            }
            let mut o = serde_json::Map::new();
            o.insert("name".into(), serde_json::json!(name));
            if let Some(aliases) = settings.alias.get(name) {
                if !aliases.is_empty() {
                    o.insert("alias".into(), serde_json::json!(aliases.join(" ")));
                }
            }
            if let Some(meta) = index.meta.get(name) {
                let c = meta.get(&lang).or_else(|| meta.get("en-US"));
                if let Some(c) = c {
                    if let Some(url) = c.get("url").and_then(|u| u.as_str()) {
                        o.insert("url".into(), serde_json::json!(url));
                    }
                    if let Some(desc) = c.get("description") {
                        let d = match desc {
                            serde_json::Value::String(s) => s.clone(),
                            serde_json::Value::Array(a) => a
                                .iter()
                                .filter_map(|x| x.as_str())
                                .collect::<Vec<_>>()
                                .join("\n"),
                            _ => String::new(),
                        };
                        if !d.is_empty() {
                            o.insert("description".into(), serde_json::json!(d));
                        }
                    }
                }
            }
            let path = format!("{completions_dir}/{name}");
            if std::path::Path::new(&path).exists() {
                o.insert("path".into(), serde_json::json!(path));
                if let Ok(t) = std::fs::read_to_string(format!("{path}/.update")) {
                    let t = t.trim();
                    if !t.is_empty() {
                        o.insert("update".into(), serde_json::json!(t));
                    }
                }
                if let Ok(meta) = std::fs::metadata(format!("{path}/.update")) {
                    if let Ok(mt) = meta.modified() {
                        if let Ok(d) = mt.duration_since(std::time::UNIX_EPOCH) {
                            o.insert("updated".into(), serde_json::json!(d.as_secs()));
                        }
                    }
                }
            }
            arr.push(serde_json::Value::Object(o));
        }
        // Still output valid entries on error (partial success); skip an all-failed empty array
        if !arr.is_empty() {
            println!("{}", serde_json::to_string(&arr).unwrap_or_default());
        }
        return if had_error {
            ExitCode::FAILURE
        } else {
            ExitCode::SUCCESS
        };
    }
    let mut had_error = false;
    for name in args {
        let status = name_status(settings, index, completions_dir, name);
        if !name_valid(out, &lang, name, status, false) {
            had_error = true;
            continue;
        }
        out.line(&format!("Name: {name}"));
        if let Some(aliases) = settings.alias.get(name) {
            if !aliases.is_empty() {
                out.line(&format!("Alias: {}", aliases.join(" ")));
            }
        }
        if let Some(meta) = index.meta.get(name) {
            let c = meta.get(&lang).or_else(|| meta.get("en-US"));
            if let Some(c) = c {
                if let Some(url) = c.get("url").and_then(|u| u.as_str()) {
                    out.line(&format!("Url: {url}"));
                }
                if let Some(desc) = c.get("description") {
                    let d = match desc {
                        serde_json::Value::String(s) => s.clone(),
                        serde_json::Value::Array(a) => a
                            .iter()
                            .filter_map(|x| x.as_str())
                            .collect::<Vec<_>>()
                            .join("\n"),
                        _ => String::new(),
                    };
                    if !d.is_empty() {
                        out.line(&format!("Description: {d}"));
                    }
                }
            }
        }
        let path = format!("{completions_dir}/{name}");
        if std::path::Path::new(&path).exists() {
            out.line(&format!("Path: {path}"));
            if let Ok(t) = std::fs::read_to_string(format!("{path}/.update")) {
                let t = t.trim();
                if !t.is_empty() {
                    out.line(&format!("Update: {t}"));
                }
            }
            if let Ok(meta) = std::fs::metadata(format!("{path}/.update")) {
                if let Ok(mt) = meta.modified() {
                    if let Ok(d) = mt.duration_since(std::time::UNIX_EPOCH) {
                        out.line(&format!("Updated: {}", d.as_secs()));
                    }
                }
            }
        }
    }
    if had_error {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

/// Format a JSON value as a display string (string as-is, numbers/bools via to_string).
fn value_str(v: &Value) -> String {
    match v {
        serde_json::Value::String(s) => {
            if s.trim().is_empty() || s.starts_with(' ') || s.ends_with(' ') {
                if s.contains('"') {
                    if s.contains('\'') {
                        s.clone()
                    } else {
                        format!("'{s}'")
                    }
                } else {
                    format!("\"{s}\"")
                }
            } else {
                s.clone()
            }
        }
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::Bool(b) => b.to_string(),
        other => other.to_string(),
    }
}

fn config_get(settings: &Settings, key: &str) -> String {
    settings.config.get(key).map(value_str).unwrap_or_default()
}

fn cmd_config(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    if args.iter().any(|a| a == "--reset") {
        let defaults = default_config(&settings.language());
        let params: Vec<&String> = args.iter().filter(|a| *a != "--reset").collect();
        if params.is_empty() {
            if !settings.config.is_object() {
                settings.config = serde_json::json!({});
            }
            let obj = settings.config.as_object_mut().unwrap();
            let comp = obj.get("completion").cloned();
            let lang = obj.get("language").cloned();
            *obj = defaults.as_object().unwrap().clone();
            if let Some(c) = comp {
                obj.insert("completion".into(), c);
            }
            if let Some(l) = lang {
                obj.insert("language".into(), l);
            }
        } else if params.len() == 1 {
            // `config <group> --reset`: reset every config item in that group
            let group = params[0].as_str();
            if !CONFIG_GROUPS.contains(&group) {
                out.line(&msg_cli(lang, "sub_cmd"));
                return ExitCode::FAILURE;
            }
            if !settings.config.is_object() {
                settings.config = serde_json::json!({});
            }
            let obj = settings.config.as_object_mut().unwrap();
            for d in CONFIG_KEYS.iter().filter(|d| d.group == group) {
                if d.key == "language" {
                    continue;
                }
                let value = defaults
                    .get(d.key)
                    .cloned()
                    .unwrap_or_else(|| serde_json::json!(""));
                obj.insert(d.key.to_string(), value);
            }
        } else if params.len() == 2 {
            let (group, key) = (params[0].as_str(), params[1].as_str());
            let Some(def) = CONFIG_KEYS
                .iter()
                .find(|d| d.group == group && d.key == key)
            else {
                out.line(&msg_cli(lang, "sub_cmd"));
                return ExitCode::FAILURE;
            };
            if def.key == "language" {
                out.line(&msg_cli(lang, "language_no_reset"));
                return ExitCode::FAILURE;
            }
            if !settings.config.is_object() {
                settings.config = serde_json::json!({});
            }
            let value = defaults
                .get(def.key)
                .cloned()
                .unwrap_or_else(|| serde_json::json!(""));
            settings
                .config
                .as_object_mut()
                .unwrap()
                .insert(def.key.to_string(), value);
        } else {
            out.line(&msg_cli(lang, "sub_cmd"));
            return ExitCode::FAILURE;
        }
        if let Err(e) = settings.save(settings_path) {
            out.line(&format!("error: {e}"));
            return ExitCode::FAILURE;
        }
        out.line(&msg_cli(lang, "config_done"));
        return ExitCode::SUCCESS;
    }
    // No args: list everything (grouped by group)
    if args.is_empty() {
        if json {
            let arr: Vec<serde_json::Value> = CONFIG_KEYS
                .iter()
                .map(|d| {
                    serde_json::json!({ "group": d.group, "key": d.key, "value": config_get(settings, d.key) })
                })
                .collect();
            println!("{}", serde_json::to_string(&arr).unwrap_or_default());
        } else {
            for group in CONFIG_GROUPS {
                out.line(&format!("[{group}]"));
                for d in CONFIG_KEYS.iter().filter(|d| d.group == group) {
                    out.line(&format!("  {}: {}", d.key, config_get(settings, d.key)));
                }
            }
        }
        return ExitCode::SUCCESS;
    }
    let group = args[0].as_str();
    if !CONFIG_GROUPS.contains(&group) {
        out.line(&msg_cli(lang, "sub_cmd"));
        return ExitCode::FAILURE;
    }
    // `config <group>`: list that group
    if args.len() == 1 {
        if json {
            let arr: Vec<serde_json::Value> = CONFIG_KEYS
                .iter()
                .filter(|d| d.group == group)
                .map(|d| {
                    serde_json::json!({ "group": d.group, "key": d.key, "value": config_get(settings, d.key) })
                })
                .collect();
            println!("{}", serde_json::to_string(&arr).unwrap_or_default());
        } else {
            out.line(&format!("[{group}]"));
            for d in CONFIG_KEYS.iter().filter(|d| d.group == group) {
                out.line(&format!("  {}: {}", d.key, config_get(settings, d.key)));
            }
        }
        return ExitCode::SUCCESS;
    }
    let key = args[1].as_str();
    let Some(def) = CONFIG_KEYS
        .iter()
        .find(|d| d.group == group && d.key == key)
    else {
        out.line(&msg_cli(lang, "sub_cmd"));
        return ExitCode::FAILURE;
    };
    // get
    if args.len() == 2 {
        if json {
            println!(
                "{}",
                serde_json::json!({ "key": key, "value": config_get(settings, key) })
            );
        } else {
            out.line(&format!("{key}: {}", config_get(settings, key)));
        }
        return ExitCode::SUCCESS;
    }
    let Some(value) = validate_value(def, &args[2]) else {
        out.line(&msg_cli(lang, "config_val"));
        return ExitCode::FAILURE;
    };
    // A corrupt `config` (e.g. `{"config": 123}`) must not turn a set into a silent no-op.
    if !settings.config.is_object() {
        settings.config = serde_json::json!({});
    }
    settings
        .config
        .as_object_mut()
        .and_then(|o| o.get_mut(key))
        .map(|v| *v = value.clone())
        .or_else(|| {
            settings
                .config
                .as_object_mut()
                .map(|o| o.insert(key.to_string(), value.clone()));
            Some(())
        });
    if let Err(e) = settings.save(settings_path) {
        out.line(&format!("error: {e}"));
        return ExitCode::FAILURE;
    }
    out.line(&msg_cli(lang, "config_done"));
    ExitCode::SUCCESS
}

/// `true` when the completion's config.json declares `"hooks": false` (dynamic hooks
/// exist but are disabled by default — the author's declared default).
fn hooks_declared_disabled(data_dir: &str, name: &str) -> bool {
    let path = format!("{data_dir}/completions/{name}/config.json");
    read_text(&path)
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .map(|v| v.get("hooks").and_then(|h| h.as_bool()) == Some(false))
        .unwrap_or(false)
}

fn cmd_completion(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    index: &Index,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    let check_installed = |name: &String| -> bool {
        let data_dir = data_dir_of(settings_path);
        let status = name_status(settings, index, &format!("{data_dir}/completions"), name);
        name_valid(out, lang, name, status, true)
    };
    if args.iter().any(|a| a == "--reset") {
        let data_dir = data_dir_of(settings_path);
        let params: Vec<&String> = args.iter().filter(|a| *a != "--reset").collect();
        let names: Vec<String> = if params.is_empty() {
            settings.list()
        } else {
            if !check_installed(params[0]) {
                return ExitCode::FAILURE;
            }
            vec![params[0].clone()]
        };
        if params.len() <= 1 {
            let mut comp = std::mem::take(ensure_completion_map(settings));
            for n in &names {
                // Reset back to the manifest's config defaults; empty defaults are not persisted.
                let defaults = completion_defaults(&data_dir, n);
                if defaults.as_object().map(|o| o.is_empty()).unwrap_or(true) {
                    comp.remove(n.as_str());
                } else {
                    comp.insert(n.clone(), defaults);
                }
                // Re-apply the manifest's `hooks` declaration: a `hooks: false` completion
                // stays disabled after a reset (its author-declared default).
                if hooks_declared_disabled(&data_dir, n) {
                    let entry = comp
                        .entry(n.clone())
                        .or_insert_with(|| serde_json::json!({}));
                    if let Some(o) = entry.as_object_mut() {
                        o.insert("enable_hooks".to_string(), serde_json::json!(false));
                    }
                }
            }
            if let Some(obj) = settings
                .config
                .get_mut("completion")
                .and_then(|c| c.as_object_mut())
            {
                *obj = comp;
            }
        } else {
            let name = params[0].clone();
            let key = params[1].clone();
            // Validate the key like the set path: a known key, or one already stored.
            let valid = COMPLETION_KEYS.contains(&key.as_str())
                || settings
                    .config
                    .get("completion")
                    .and_then(|c| c.get(&name))
                    .and_then(|c| c.get(&key))
                    .is_some();
            if !valid {
                out.line(&msg_cli(lang, "sub_cmd"));
                return ExitCode::FAILURE;
            }
            let defaults = completion_defaults(&data_dir, &name);
            if let Some(n) = settings
                .config
                .get_mut("completion")
                .and_then(|c| c.get_mut(&name))
                .and_then(|n| n.as_object_mut())
            {
                match defaults.get(&key) {
                    Some(v) => {
                        n.insert(key.clone(), v.clone());
                    }
                    None => {
                        // `enable_hooks` has no manifest default; resetting it re-applies
                        // the config.json declaration (a `hooks: false` completion stays off).
                        if key == "enable_hooks" && hooks_declared_disabled(&data_dir, &name) {
                            n.insert("enable_hooks".to_string(), serde_json::json!(false));
                        } else {
                            n.remove(&key);
                        }
                    }
                }
            }
            // Drop the entry once emptied (back to "default" = no special config).
            if let Some(comp) = settings
                .config
                .get_mut("completion")
                .and_then(|c| c.as_object_mut())
            {
                if comp
                    .get(&name)
                    .map(|v| v.as_object().map(|o| o.is_empty()).unwrap_or(false))
                    .unwrap_or(false)
                {
                    comp.remove(name.as_str());
                }
            }
        }
        if let Err(e) = settings.save(settings_path) {
            out.line(&format!("error: {e}"));
            return ExitCode::FAILURE;
        }
        out.line(&msg_cli(lang, "completion_done"));
        return ExitCode::SUCCESS;
    }
    // No args: list every completion with non-default special config (with its config)
    if args.is_empty() {
        let entries: Vec<(String, serde_json::Map<String, Value>)> = settings
            .config
            .get("completion")
            .and_then(|c| c.as_object())
            .map(|o| {
                o.iter()
                    .filter(|(_, cfg)| cfg.as_object().map(|c| !c.is_empty()).unwrap_or(false))
                    .filter_map(|(n, cfg)| cfg.as_object().map(|c| (n.clone(), c.clone())))
                    .collect()
            })
            .unwrap_or_default();
        if json {
            let arr: Vec<serde_json::Value> = entries
                .iter()
                .map(|(n, cfg)| serde_json::json!({ "completion": n, "config": cfg }))
                .collect();
            println!("{}", serde_json::to_string(&arr).unwrap_or_default());
        } else {
            for (n, cfg) in entries {
                let pairs: Vec<String> = cfg
                    .iter()
                    .map(|(k, v)| format!("{k}={}", value_str(v)))
                    .collect();
                out.line(&format!("{n}: {}", pairs.join(" ")));
            }
        }
        return ExitCode::SUCCESS;
    }
    // Single arg <name>: list all special config for that completion
    if args.len() == 1 {
        let name = &args[0];
        if !check_installed(name) {
            return ExitCode::FAILURE;
        }
        let cfg: serde_json::Map<String, Value> = settings
            .config
            .get("completion")
            .and_then(|c| c.get(name))
            .and_then(|c| c.as_object())
            .cloned()
            .unwrap_or_default();
        if json {
            println!(
                "{}",
                serde_json::json!({ "completion": name, "config": cfg })
            );
        } else {
            for (k, v) in cfg {
                out.line(&format!("{k}: {}", value_str(&v)));
            }
        }
        return ExitCode::SUCCESS;
    }
    let name = args[0].clone();
    if !check_installed(&name) {
        return ExitCode::FAILURE;
    }
    let key = args[1].clone();
    // enable_hooks is only valid when the completion's config.json declares hooks.
    if key == "enable_hooks" {
        let config_path = format!(
            "{}/completions/{name}/config.json",
            data_dir_of(settings_path)
        );
        let has_hooks = read_text(&config_path)
            .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
            .map(|c| c.get("hooks").is_some())
            .unwrap_or(false);
        if !has_hooks {
            out.line(&msg_cli(lang, "no_hooks"));
            return ExitCode::FAILURE;
        }
    }
    let valid = COMPLETION_KEYS.contains(&key.as_str())
        || settings
            .config
            .get("completion")
            .and_then(|c| c.get(&name))
            .and_then(|c| c.get(&key))
            .is_some();
    if !valid {
        out.line(&msg_cli(lang, "sub_cmd"));
        return ExitCode::FAILURE;
    }
    let get = |key: &str| -> String {
        settings
            .config
            .get("completion")
            .and_then(|c| c.get(&name))
            .and_then(|c| c.get(key))
            .map(|v| match v {
                serde_json::Value::String(s) => s.clone(),
                serde_json::Value::Number(n) => n.to_string(),
                serde_json::Value::Bool(b) => b.to_string(),
                other => other.to_string(),
            })
            .unwrap_or_default()
    };
    if args.len() == 2 {
        if json {
            println!(
                "{}",
                serde_json::json!({ "completion": name, "key": key, "value": get(&key) })
            );
        } else {
            out.line(&format!("{key}: {}", get(&key)));
        }
        return ExitCode::SUCCESS;
    }
    let value: serde_json::Value = match args[2].parse::<i64>() {
        Ok(n) => serde_json::Value::Number(n.into()),
        Err(_) => serde_json::Value::String(args[2].clone()),
    };
    if name == "psc"
        && key == "enable_hooks"
        && (value.as_i64() == Some(0) || value.as_str() == Some("0"))
    {
        out.line(&msg_cli(lang, "psc_hooks_locked"));
        return ExitCode::FAILURE;
    }
    if key.starts_with("enable_") || key.starts_with("disable_") {
        let v = match &value {
            serde_json::Value::Number(n) => n.as_i64() == Some(0) || n.as_i64() == Some(1),
            _ => false,
        };
        if !v {
            out.line(&msg_cli(lang, "one_or_zero"));
            return ExitCode::FAILURE;
        }
    }
    {
        // Recover a corrupt settings.json (reset config/completion/name entries that aren't objects)
        // to avoid an unwrap panic
        let comp = ensure_completion_map(settings);
        let n = comp
            .entry(name.clone())
            .or_insert_with(|| serde_json::json!({}));
        if !n.is_object() {
            *n = serde_json::json!({});
        }
        n.as_object_mut().unwrap().insert(key.clone(), value);
    }
    if let Err(e) = settings.save(settings_path) {
        out.line(&format!("error: {e}"));
        return ExitCode::FAILURE;
    }
    out.line(&msg_cli(lang, "completion_done"));
    ExitCode::SUCCESS
}

fn cmd_alias(
    args: &[String],
    settings_path: &str,
    settings: &mut Settings,
    index: &Index,
    lang: &str,
    out: &Out,
    json: bool,
) -> ExitCode {
    let data_dir = data_dir_of(settings_path);
    if args.iter().any(|a| a == "--reset") {
        // Only `alias --reset` is legal; any other arg is a subcommand error.
        let params: Vec<&String> = args.iter().filter(|a| *a != "--reset").collect();
        if !params.is_empty() {
            out.line(&msg_cli(lang, "sub_cmd"));
            return ExitCode::FAILURE;
        }
        let targets: Vec<String> = settings.list();
        for n in &targets {
            reset_alias(settings, &data_dir, n);
        }
        if let Err(e) = settings.save(settings_path) {
            out.line(&format!("error: {e}"));
            return ExitCode::FAILURE;
        }
        out.line(&msg_cli(lang, "alias_done"));
        return ExitCode::SUCCESS;
    }
    match args.first().map(|s| s.as_str()) {
        None => {
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
            } else {
                for name in settings.list() {
                    let aliases = settings.alias.get(&name).cloned().unwrap_or_default();
                    out.line(&format!("{name}: {}", aliases.join(" ")));
                }
            }
            ExitCode::SUCCESS
        }
        Some("add") => {
            if args.len() < 3 {
                param_err(out, lang);
                return ExitCode::FAILURE;
            }
            let name = args[1].clone();
            let status = name_status(settings, index, &format!("{data_dir}/completions"), &name);
            if !name_valid(out, lang, &name, status, true) {
                return ExitCode::FAILURE;
            }
            let mut changed = false;
            let mut had_error = false;
            for a in &args[2..] {
                if a.contains('*') || a.contains('?') {
                    out.line(&format!("{a}: {}", msg_cli(lang, "has_wildcard")));
                    had_error = true;
                    continue;
                }
                if a == "PSCompletions" {
                    out.line(&format!("{a}: {}", msg_cli(lang, "cmd_exist")));
                    had_error = true;
                    continue;
                }
                if settings
                    .alias
                    .get(&name)
                    .map(|v| v.iter().any(|x| x == a))
                    .unwrap_or(false)
                {
                    out.line(&format!("{a}: {}", msg_cli(lang, "alias_exist")));
                    had_error = true;
                    continue;
                }
                let conflict = settings
                    .alias
                    .iter()
                    .any(|(k, v)| k != &name && v.iter().any(|x| x == a));
                if conflict {
                    out.line(&format!("{a}: {}", msg_cli(lang, "cmd_exist")));
                    had_error = true;
                    continue;
                }
                settings
                    .alias
                    .entry(name.clone())
                    .or_default()
                    .push(a.clone());
                changed = true;
            }
            if changed {
                if let Err(e) = settings.save(settings_path) {
                    out.line(&format!("error: {e}"));
                    return ExitCode::FAILURE;
                }
                out.line(&msg_cli(lang, "alias_done"));
            }
            if had_error {
                ExitCode::FAILURE
            } else {
                ExitCode::SUCCESS
            }
        }
        Some("rm") => {
            if args.len() < 3 {
                param_err(out, lang);
                return ExitCode::FAILURE;
            }
            let name = args[1].clone();
            let status = name_status(settings, index, &format!("{data_dir}/completions"), &name);
            if !name_valid(out, lang, &name, status, true) {
                return ExitCode::FAILURE;
            }
            let Some(entry) = settings.alias.get_mut(&name) else {
                out.line(&format!("{name}: {}", msg_cli(lang, "no_completion")));
                return ExitCode::FAILURE;
            };
            let remove_count = entry
                .iter()
                .filter(|a| args[2..].iter().any(|x| x == *a))
                .count();
            if remove_count == 0 {
                out.line(&format!("{name}: {}", msg_cli(lang, "alias_not_found")));
                return ExitCode::FAILURE;
            }
            if entry.len() <= remove_count {
                out.line(&msg_cli(lang, "alias_unique"));
                return ExitCode::FAILURE;
            }
            entry.retain(|a| !args[2..].iter().any(|x| x == a));
            if let Err(e) = settings.save(settings_path) {
                out.line(&format!("error: {e}"));
                return ExitCode::FAILURE;
            }
            out.line(&msg_cli(lang, "alias_done"));
            ExitCode::SUCCESS
        }
        Some(_) => {
            out.line(&msg_cli(lang, "sub_cmd"));
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ensure_completion_map_handles_corrupt_config() {
        let mut s = Settings {
            config: serde_json::json!(123),
            ..Default::default()
        };
        {
            let map = ensure_completion_map(&mut s);
            assert!(map.is_empty());
        }
        assert!(s.config.is_object());
    }

    #[test]
    fn ensure_completion_map_handles_corrupt_completion_value() {
        let mut s = Settings {
            config: serde_json::json!({ "completion": "not-an-object" }),
            ..Default::default()
        };
        {
            let map = ensure_completion_map(&mut s);
            assert!(map.is_empty());
        }
        assert!(s.config["completion"].is_object());
    }

    #[test]
    fn psc_completion_present_checks_key_files() {
        let base = std::env::temp_dir().join(format!("psc-present-test-{}", std::process::id()));
        let completions = base.join("completions");
        std::fs::create_dir_all(completions.join("psc/language")).unwrap();
        let s = completions.to_str().unwrap();
        assert!(!psc_completion_present(s));
        std::fs::write(completions.join("psc/config.json"), "{}").unwrap();
        assert!(!psc_completion_present(s));
        std::fs::write(completions.join("psc/language/en-US.json"), "{}").unwrap();
        assert!(psc_completion_present(s));
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn hooks_declared_disabled_reads_config_json() {
        let base = std::env::temp_dir().join(format!("psc-hooks-test-{}", std::process::id()));
        let dir = base.join("completions/x");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("config.json"),
            r#"{"language":["en-US"],"hooks":false}"#,
        )
        .unwrap();
        assert!(hooks_declared_disabled(base.to_str().unwrap(), "x"));
        std::fs::write(
            dir.join("config.json"),
            r#"{"language":["en-US"],"hooks":true}"#,
        )
        .unwrap();
        assert!(!hooks_declared_disabled(base.to_str().unwrap(), "x"));
        std::fs::write(dir.join("config.json"), r#"{"language":["en-US"]}"#).unwrap();
        assert!(!hooks_declared_disabled(base.to_str().unwrap(), "x"));
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn parse_args_rejects_empty_space_form_values() {
        // `--data ""` (space form) must not swallow the empty token as a value.
        let (data, _, _, _, rest) = parse_args(&["--data".into(), "".into(), "list".into()]);
        assert!(data.is_none(), "empty --data space value must be rejected");
        assert_eq!(
            rest,
            vec!["--data".to_string(), "".to_string(), "list".to_string()],
            "the rejected flag and its empty value flow to the command"
        );
        let (_, _, lang, _, _) = parse_args(&["--language".into(), "".into()]);
        assert!(
            lang.is_none(),
            "empty --language space value must be rejected"
        );
        let (_, _, _, result, _) = parse_args(&["--result".into(), "".into()]);
        assert!(
            result.is_none(),
            "empty --result space value must be rejected"
        );
        // The `=` forms reject empty values too.
        let (data, _, lang, result, _) = parse_args(&["--data=".into(), "list".into()]);
        assert!(data.is_none());
        assert_eq!(lang, None);
        assert!(result.is_none());
    }

    #[test]
    fn parse_args_accepts_nonempty_space_form_values() {
        let (data, _, lang, result, rest) = parse_args(&[
            "--data".into(),
            "C:\\temp".into(),
            "--language".into(),
            "zh-CN".into(),
            "--result".into(),
            "out.json".into(),
            "list".into(),
        ]);
        assert_eq!(data.as_deref(), Some("C:\\temp"));
        assert_eq!(lang.as_deref(), Some("zh-CN"));
        assert_eq!(result.as_deref(), Some("out.json"));
        assert_eq!(rest, vec!["list".to_string()]);
    }

    #[test]
    fn normalize_data_dir_keeps_drive_roots_absolute() {
        assert_eq!(normalize_data_dir("C:\\"), "C:\\");
        assert_eq!(normalize_data_dir("C:/"), "C:\\");
        assert_eq!(normalize_data_dir("C:"), "C:\\");
        assert_eq!(normalize_data_dir("D:\\data"), "D:\\data");
        assert_eq!(normalize_data_dir("/data"), "/data");
        assert_eq!(normalize_data_dir("."), ".");
    }

    #[test]
    fn compute_post_changes_merges_executed_renames() {
        let base = std::env::temp_dir().join(format!("psc-changes-test-{}", std::process::id()));
        let data_dir = base.to_str().unwrap();
        std::fs::create_dir_all(format!("{data_dir}/completions/bar")).unwrap();
        std::fs::write(
            format!("{data_dir}/completions/bar/config.json"),
            r#"{"id":"abc"}"#,
        )
        .unwrap();
        std::fs::write(format!("{data_dir}/completions/bar/.update"), "v1").unwrap();
        let settings = Settings {
            alias: [("bar".to_string(), Vec::new())].into_iter().collect(),
            config: serde_json::json!({}),
        };
        let mut index = Index::default();
        index.ids.insert("bar".to_string(), "abc".to_string());
        index.update.insert("bar".to_string(), "v1".to_string());
        let old_list = vec!["foo".to_string()];

        // Without the executed_renames parameter the post-state diff would report
        // added=["bar"] + removed=["foo"]; the merge must turn it into a single rename.
        let changes = compute_post_changes(
            data_dir,
            &settings,
            &old_list,
            &index,
            &[("foo".into(), "bar".into())],
        );
        assert_eq!(
            changes.renamed,
            vec![("foo".to_string(), "bar".to_string())]
        );
        assert!(
            changes.added.is_empty(),
            "renamed completion must not be added"
        );
        assert!(
            changes.removed.is_empty(),
            "renamed completion must not be removed"
        );
        assert!(
            changes.update.is_empty(),
            "up-to-date completion must not need update"
        );
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn compute_post_changes_reports_plain_add_and_remove() {
        let base = std::env::temp_dir().join(format!("psc-changes-test-{}", std::process::id()));
        let data_dir = base.to_str().unwrap();
        std::fs::create_dir_all(format!("{data_dir}/completions/foo")).unwrap();
        std::fs::write(
            format!("{data_dir}/completions/foo/config.json"),
            r#"{"id":"abc"}"#,
        )
        .unwrap();
        std::fs::write(format!("{data_dir}/completions/foo/.update"), "v1").unwrap();
        let settings = Settings {
            alias: [("foo".to_string(), Vec::new())].into_iter().collect(),
            config: serde_json::json!({}),
        };
        let mut index = Index::default();
        index.ids.insert("foo".to_string(), "abc".to_string());
        index.update.insert("foo".to_string(), "v1".to_string());
        let old_list = Vec::<String>::new();

        let changes = compute_post_changes(data_dir, &settings, &old_list, &index, &[]);
        assert_eq!(changes.added, vec!["foo".to_string()]);
        assert!(changes.removed.is_empty());
        assert!(changes.renamed.is_empty());
        assert!(changes.update.is_empty());
        std::fs::remove_dir_all(&base).ok();
    }
}
