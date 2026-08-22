//! Argv parsing: global flag extraction and data-dir normalization.

/// Strip the global flags (`--data`, `--json`, `--language`, `--result`) out of argv.
///
/// For `--data`/`--language`/`--result` with `=` form, rejects empty values (e.g. `--data=`).
/// For space form, rejects if the next token starts with `-` (e.g. `--data --json`).
/// Trailing slashes/backslashes on `data_dir` are trimmed (done in `main`).
pub fn parse_args(
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

/// Trim trailing separators, then restore a bare Windows drive (`C:` → `C:\`) so it stays
/// an absolute root instead of a drive-relative path.
pub fn normalize_data_dir(data_dir: &str) -> String {
    let trimmed = data_dir.trim_end_matches(['/', '\\']);
    if trimmed.len() == 2 && trimmed.ends_with(':') {
        format!("{trimmed}\\")
    } else {
        trimmed.to_string()
    }
}

/// Bare-binary fallback help (only shown when invoked directly with no subcommand).
pub fn print_help() {
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

#[cfg(test)]
mod tests {
    use super::*;

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
}
