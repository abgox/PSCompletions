//! Background ordering computation: read PSReadLine history → score command/subcommand
//! usage → write the order JSON (algorithm: `design/menu.md`).

use crate::menu::model::OrderInfo;
use std::collections::HashMap;

/// Maximum number of history lines scanned (the most recent N; older usage is less
/// relevant to the current ordering).
const ORDER_WINDOW: usize = 1000;

/// Usage stats for a single subcommand: weighted score (primary sort key) + the line of
/// its most recent use (tie-breaker).
struct TokenStats {
    score: f64,
    last_line: usize,
}

/// `1 + 120 × (rel/total)^8`: smooth decay, +1 floor (frequency base), steep near the present.
fn recency_weight(rel: usize, total: usize) -> f64 {
    let f = rel as f64 / total.max(1) as f64;
    1.0 + 120.0 * f.powi(8)
}

/// `((i+1)/n)^2`: the last (deepest) token weighs 1.0, early prefixes decay quadratically.
fn position_factor(i: usize, n: usize) -> f64 {
    let f = (i + 1) as f64 / n.max(1) as f64;
    f * f
}

/// Read the tail of a file — enough to cover `max_lines` lines (or the whole file when
/// smaller) — so ordering never slurps a huge history into memory just to discard it.
fn read_tail(path: &str, max_lines: usize) -> Option<String> {
    use std::io::{Read, Seek, SeekFrom};
    let mut f = std::fs::File::open(path).ok()?;
    let len = f.metadata().ok()?.len();
    if len == 0 {
        return Some(String::new());
    }
    const CHUNK: u64 = 64 * 1024;
    let mut collected: Vec<u8> = Vec::new();
    let mut pos = len;
    loop {
        let start = pos.saturating_sub(CHUNK);
        f.seek(SeekFrom::Start(start)).ok()?;
        let mut buf = vec![0u8; (pos - start) as usize];
        f.read_exact(&mut buf).ok()?;
        collected.splice(0..0, buf); // prepend, keeping line order
        if collected.iter().filter(|&&b| b == b'\n').count() >= max_lines {
            break;
        }
        if start == 0 {
            break;
        }
        pos = start;
    }
    Some(String::from_utf8_lossy(&collected).into_owned())
}

/// Entry point for the background thread: read history, tally scores, rank, atomically
/// write the file.
pub fn compute_and_write_order(info: &OrderInfo) {
    // Only the most recent history matters (ORDER_WINDOW lines); read just the tail.
    let Some(history) = read_tail(&info.history, ORDER_WINDOW) else {
        return;
    };
    let stats = compute_scores(&history, &info.aliases);
    if stats.is_empty() {
        let _ = std::fs::remove_file(&info.path);
    } else {
        write_order(&info.path, &stats);
    }
    // Global path-leaf history (shared across commands): path completion (`.\scripts\<Tab>`)
    // ranks files/scripts by how often their leaf name was used, regardless of the command.
    // Lives in its own subdir so it can never collide with a per-command order file
    // (`_paths` is a valid command name and EscapeDataString keeps those files flat).
    let path_stats = compute_path_scores(&history);
    // Global command-use frequency: root-command completion (`g<Tab>`) ranks candidates by
    // how often each command was invoked.
    let cmd_stats = compute_command_scores(&history);
    let dir = std::path::Path::new(&info.path)
        .parent()
        .map(|d| d.to_string_lossy().into_owned())
        .unwrap_or_default();
    if !dir.is_empty() {
        write_order(&format!("{dir}/_shared/_paths.json"), &path_stats);
        write_order(&format!("{dir}/_shared/_commands.json"), &cmd_stats);
    }
}

/// Tally each token's weighted score (graded time decay × position weight) and its most
/// recent use line.
fn compute_scores(history: &str, aliases: &[String]) -> HashMap<String, TokenStats> {
    let mut scores: HashMap<String, TokenStats> = HashMap::new();
    let lines: Vec<&str> = history.lines().collect();
    let start = lines.len().saturating_sub(ORDER_WINDOW);
    let total = (lines.len() - start).max(1);
    for (rel, line) in lines[start..].iter().enumerate() {
        let rel_idx = rel + 1; // 1-based
        let recency = recency_weight(rel_idx, total);
        let line = line.trim_start_matches([' ', '\t']);
        for alias in aliases {
            if alias.is_empty() {
                continue;
            }
            if let Some(rest) = strip_alias(line, alias) {
                if rest.is_empty() {
                    continue;
                }
                let toks = tokenize(rest);
                let n = toks.len();
                for (i, tok) in toks.iter().enumerate() {
                    let key = normalize_key(tok);
                    if !key.is_empty() {
                        let s = scores.entry(key).or_insert(TokenStats {
                            score: 0.0,
                            last_line: 0,
                        });
                        s.score += recency * position_factor(i, n);
                        s.last_line = rel_idx;
                    }
                }
                break;
            }
        }
    }
    scores
}

/// Tally path-like tokens (contain `\` or `/`) by every path segment across all history
/// lines; the result feeds `_paths.json`, the shared source for path-completion ordering.
/// Scoring every segment (not just the leaf) lets a directory candidate rank by how often it
/// was entered: `.\scripts\build.ps1` scores both `scripts` and `build.ps1`, so completing
/// `.\` surfaces the frequently used `scripts` directory first.
fn compute_path_scores(history: &str) -> HashMap<String, TokenStats> {
    let mut scores: HashMap<String, TokenStats> = HashMap::new();
    let lines: Vec<&str> = history.lines().collect();
    let start = lines.len().saturating_sub(ORDER_WINDOW);
    let total = (lines.len() - start).max(1);
    for (rel, line) in lines[start..].iter().enumerate() {
        let rel_idx = rel + 1; // 1-based
        let recency = recency_weight(rel_idx, total);
        let line = line.trim_start_matches([' ', '\t']);
        let toks = tokenize(line);
        let n = toks.len();
        for (i, tok) in toks.iter().enumerate() {
            let Some(segs) = path_segments(tok) else {
                continue;
            };
            for seg in segs {
                let key = normalize_key(&seg);
                if key.is_empty() {
                    continue;
                }
                let s = scores.entry(key).or_insert(TokenStats {
                    score: 0.0,
                    last_line: 0,
                });
                s.score += recency * position_factor(i, n);
                s.last_line = rel_idx;
            }
        }
    }
    scores
}

/// Every segment of a path-like token (contains a path separator, not a bare `-option`).
/// A trailing separator (a directory like `.\scripts\`) is ignored so the directory's own
/// name is the last segment. Returns `None` for tokens that are not paths.
fn path_segments(tok: &str) -> Option<Vec<String>> {
    let t = tok.trim_matches('"').trim_matches('\'');
    if t.is_empty() || !(t.contains('\\') || t.contains('/')) {
        return None;
    }
    let trimmed = t.trim_end_matches(['\\', '/']);
    let segs: Vec<String> = trimmed
        .split(['\\', '/'])
        .map(str::to_string)
        .filter(|s| !s.is_empty())
        .collect();
    if segs.is_empty() {
        None
    } else {
        Some(segs)
    }
}

/// Command-use frequency: the first token of each history line, across all commands. Feeds
/// `_commands.json`, the shared source for root-command completion ordering (`g<Tab>`).
fn compute_command_scores(history: &str) -> HashMap<String, TokenStats> {
    let mut scores: HashMap<String, TokenStats> = HashMap::new();
    let lines: Vec<&str> = history.lines().collect();
    let start = lines.len().saturating_sub(ORDER_WINDOW);
    let total = (lines.len() - start).max(1);
    for (rel, line) in lines[start..].iter().enumerate() {
        let rel_idx = rel + 1; // 1-based
        let recency = recency_weight(rel_idx, total);
        let line = line.trim_start_matches([' ', '\t']);
        let toks = tokenize(line);
        if let Some(first) = toks.first() {
            let key = normalize_key(first);
            if !key.is_empty() {
                let s = scores.entry(key).or_insert(TokenStats {
                    score: 0.0,
                    last_line: 0,
                });
                s.score += recency;
                s.last_line = rel_idx;
            }
        }
    }
    scores
}

/// If the line start (ignoring leading spaces) matches `alias` case-insensitively, and the
/// alias is immediately followed by whitespace + content, return the remainder of the line
/// after the leading whitespace + alias + trailing whitespace (i.e. the argument segment).
fn strip_alias<'a>(line: &'a str, alias: &str) -> Option<&'a str> {
    let line = line.trim_start_matches([' ', '\t']);
    let lower = line.to_lowercase();
    let a = alias.to_lowercase();
    if !lower.starts_with(&a) {
        return None;
    }
    let after = &line[a.len()..];
    let after_trim = after.trim_start_matches([' ', '\t']);
    // `\s+` requires at least one whitespace + `.+` at least one content char.
    if after.len() == after_trim.len() || after_trim.is_empty() {
        return None;
    }
    Some(after_trim)
}

/// Mimics the PowerShell `input_pattern` (`(?:"[^"]*"|'[^']*'|\S)+`):
/// a properly quoted string (quotes included) is one token; an unmatched quote is treated
/// as an ordinary non-whitespace character (`\S` matches any non-whitespace, including
/// unmatched quotes).
fn tokenize(s: &str) -> Vec<String> {
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '"' || c == '\'' {
            let quote = c;
            let mut j = i + 1;
            while j < chars.len() && chars[j] != quote {
                j += 1;
            }
            if j < chars.len() {
                // Properly paired quotes → a quoted token (quotes included).
                out.push(chars[i..=j].iter().collect::<String>());
                i = j + 1;
                continue;
            }
            // No matching quote → falls through to the ordinary non-whitespace branch.
        }
        if !c.is_whitespace() {
            let start = i;
            while i < chars.len() && !chars[i].is_whitespace() {
                i += 1;
            }
            out.push(chars[start..i].iter().collect::<String>());
        } else {
            i += 1;
        }
    }
    out
}

/// Normalize a sort key: trim surrounding quotes + lowercase (the reader-side hash map is
/// case-insensitive).
fn normalize_key(tok: &str) -> String {
    tok.trim_matches('"').trim_matches('\'').to_lowercase()
}

/// Sort by (score desc → most-recent-use desc → key) and write to `path`. Higher rank sorts
/// first (-Descending on the module side). Skips unchanged content; writes atomically.
fn write_order(path: &str, scores: &HashMap<String, TokenStats>) {
    use std::cmp::Ordering;
    let mut entries: Vec<(&String, &TokenStats)> = scores.iter().collect();
    entries.sort_by(|a, b| {
        b.1.score
            .partial_cmp(&a.1.score)
            .unwrap_or(Ordering::Equal)
            .then_with(|| b.1.last_line.cmp(&a.1.last_line))
            .then_with(|| a.0.cmp(b.0))
    });
    let total = entries.len();
    let mut map = serde_json::Map::new();
    for (i, (k, _)) in entries.iter().enumerate() {
        map.insert((*k).clone(), serde_json::Value::from((total - i) as i64));
    }
    let json = serde_json::to_string(&serde_json::Value::Object(map)).unwrap_or_default();
    if let Ok(old) = std::fs::read_to_string(path) {
        if old == json {
            return;
        }
    }
    if let Some(dir) = std::path::Path::new(path).parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let tmp = format!("{path}.tmp");
    if std::fs::write(&tmp, json.as_bytes()).is_ok() {
        let _ = std::fs::rename(&tmp, path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokenize_quotes_and_plain() {
        assert_eq!(
            tokenize("commit -m \"hello world\" --all"),
            vec![
                "commit".to_string(),
                "-m".to_string(),
                "\"hello world\"".to_string(),
                "--all".to_string()
            ]
        );
        // Unmatched quotes are treated as ordinary non-whitespace (\S matches the quote).
        assert_eq!(
            tokenize("a'bc d"),
            vec!["a'bc".to_string(), "d".to_string()]
        );
        assert_eq!(tokenize(""), Vec::<String>::new());
    }

    #[test]
    fn tokenize_matches_input_pattern_semantics() {
        // The module's `input_pattern` (`(?:"[^"]*"|'[^']*'|\S)+`) is the host-side twin of this function:
        // whitespace splits tokens, a paired quote stays one token (quotes kept),
        // every non-whitespace character (including unmatched quotes) is ordinary.
        assert_eq!(
            tokenize("git add file.txt"),
            vec!["git".to_string(), "add".to_string(), "file.txt".to_string()]
        );
        assert_eq!(
            tokenize("echo 'a b' c"),
            vec!["echo".to_string(), "'a b'".to_string(), "c".to_string()]
        );
        assert_eq!(
            tokenize("cmd /c \"echo hi\" -x"),
            vec![
                "cmd".to_string(),
                "/c".to_string(),
                "\"echo hi\"".to_string(),
                "-x".to_string()
            ]
        );
        assert_eq!(
            tokenize("  spaced   out  "),
            vec!["spaced".to_string(), "out".to_string()]
        );
    }

    #[test]
    fn strip_alias_case_and_boundary() {
        assert_eq!(strip_alias("Git commit -m x", "git"), Some("commit -m x"));
        assert_eq!(strip_alias("  git checkout", "git"), Some("checkout"));
        // The alias must be followed by whitespace + content.
        assert_eq!(strip_alias("gith", "git"), None);
        assert_eq!(strip_alias("git", "git"), None);
        assert_eq!(strip_alias("git ", "git"), None); // no content after
    }

    #[test]
    fn path_segments_splits_every_segment() {
        assert_eq!(
            path_segments(".\\scripts\\build-release.ps1"),
            Some(vec![
                ".".into(),
                "scripts".into(),
                "build-release.ps1".into()
            ])
        );
        assert_eq!(
            path_segments("scripts/check.ps1"),
            Some(vec!["scripts".into(), "check.ps1".into()])
        );
        assert_eq!(
            path_segments("\".\\scripts\\run.ps1\""),
            Some(vec![".".into(), "scripts".into(), "run.ps1".into()])
        );
        // A directory token ends with a separator: the directory's own name is the last segment.
        assert_eq!(
            path_segments(".\\scripts\\"),
            Some(vec![".".into(), "scripts".into()])
        );
        assert_eq!(path_segments("src/"), Some(vec!["src".into()]));
        // Not path-like: no separator.
        assert_eq!(path_segments("-platform"), None);
        assert_eq!(path_segments("windows"), None);
        assert_eq!(path_segments(""), None);
    }

    #[test]
    fn compute_path_scores_counts_every_segment() {
        let history = concat!(
            ".\\scripts\\build-release.ps1 -Platform windows\n",
            ".\\scripts\\compare-json.ps1 git\n",
            ".\\scripts\\build-release.ps1 --force\n",
        );
        let s = compute_path_scores(history);
        // The leaf is still scored (used twice → beats the once-used script).
        assert!(s["build-release.ps1"].score > s["compare-json.ps1"].score);
        // Every segment is scored: `scripts` appears in all 3 lines (each path passes through it)
        // and therefore outranks the leaf used only twice.
        assert!(s["scripts"].score > s["build-release.ps1"].score);
        // A drive/`.` segment counts as a segment too.
        assert!(s.contains_key("."));
        // Plain args are not path tokens.
        assert!(!s.contains_key("-platform"));
        assert!(!s.contains_key("windows"));
    }

    #[test]
    fn compute_command_scores_ranks_first_tokens() {
        let history = concat!(
            "git commit -m x\n",
            "scoop update\n",
            "git status\n",
            "git log\n",
        );
        let s = compute_command_scores(history);
        // git appears three times → beats the once-used scoop; only the first token counts.
        assert!(s["git"].score > s["scoop"].score);
        assert!(!s.contains_key("commit"));
        assert!(!s.contains_key("status"));
    }

    #[test]
    fn compute_and_write_skips_empty_per_command_order() {
        let dir = std::env::temp_dir().join("psc-order-empty-test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let history = dir.join("history.txt");
        std::fs::write(&history, "git commit -m x\nscoop update\n").unwrap();
        let info = OrderInfo {
            history: history.to_string_lossy().into_owned(),
            cmd: "get-".into(),
            aliases: vec!["get-".into()],
            path: dir.join("get-.json").to_string_lossy().into_owned(),
        };
        compute_and_write_order(&info);
        // No alias-matched per-command usage → no per-command order file is created.
        assert!(!dir.join("get-.json").exists());
        // The shared global files are still written for path/root-command sorting.
        assert!(dir.join("_shared").join("_commands.json").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn same_band_frequency_wins() {
        // Within the same band (both in the newest 10%), frequency dominates: 7 × list > 4 × which.
        let mut history = "x\n".repeat(989);
        history.push_str(&"psc list\n".repeat(7));
        history.push_str(&"psc which\n".repeat(4));
        let stats = compute_scores(&history, &["psc".to_string()]);
        assert!(stats["list"].score > stats["which"].score);
    }

    #[test]
    fn recency_grading_recent_many_beats_old_many() {
        // An old command deposited 500 times (oldest band, weight ≈1) vs a new command used
        // 15 times recently (newest band, weight ≈121) → the new one should win (a pure
        // frequency algorithm could never do this; the tie-break is covered by write_order's test).
        let mut history = "psc oldsub\n".repeat(500);
        history.push_str(&"x\n".repeat(485));
        history.push_str(&"psc newsub\n".repeat(15));
        let stats = compute_scores(&history, &["psc".to_string()]);
        assert!(stats["newsub"].score > stats["oldsub"].score);
    }

    #[test]
    fn position_weight_prefix_counts_less() {
        // `psc config menu`: menu is the last token (weight 1.0), config is a prefix
        // (weight 0.5); in the same line the last token outscores the prefix.
        let stats = compute_scores("psc config menu\n", &["psc".to_string()]);
        assert!(stats["menu"].score > stats["config"].score);
        // A prefix repeated several times (e.g. `psc config menu` ×3) must not outscore a
        // single last-token `psc list` line.
        let mut h = "psc config menu\n".repeat(3);
        h.push_str("psc list\n");
        let stats2 = compute_scores(&h, &["psc".to_string()]);
        // Compare within the newest band to stay fair: 3 prefixes + 1 last token all land
        // in the newest band (×60).
        // config = 3×(60×0.5) = 90; list = 1×60 = 60; menu = 3×(60×1.0) = 180
        assert!(stats2["menu"].score > stats2["config"].score);
    }

    #[test]
    fn recency_weight_is_smooth_monotonic() {
        // Smooth with no cliffs: the weight between adjacent lines changes very little (the
        // old discrete buckets jumped 5× at the 900/901 boundary).
        let mut prev = 0.0f64;
        for rel in 1..=1000 {
            let w = recency_weight(rel, 1000);
            // f^8 flattens everything before the recent tail to ≈1 (sub-double steps), so
            // allow non-decreasing rather than strictly increasing.
            assert!(
                w >= prev,
                "weight must not decrease with recency at rel={rel}"
            );
            if rel > 1 {
                let step = w - prev;
                assert!(step < 1.0, "smooth: step too big at rel={rel}: {step}");
            }
            prev = w;
        }
        // Magnitudes at both ends: newest ≈121 (highly myopic), oldest ≈1 (frequency base).
        assert!((recency_weight(1000, 1000) - 121.0).abs() < 1e-9);
        assert!((recency_weight(1, 1000) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn write_order_frequency_primary_recency_tiebreak() {
        let dir = std::env::temp_dir().join("psc-menu-order-test");
        let _ = std::fs::create_dir_all(&dir);
        let path = dir.join("git.json");
        let path_str = path.to_str().unwrap().to_string();
        let mut scores = HashMap::new();
        scores.insert(
            "list".to_string(),
            TokenStats {
                score: 200.0,
                last_line: 500,
            },
        );
        scores.insert(
            "which".to_string(),
            TokenStats {
                score: 100.0,
                last_line: 999,
            },
        );
        scores.insert(
            "info".to_string(),
            TokenStats {
                score: 200.0,
                last_line: 700,
            },
        );
        write_order(&path_str, &scores);
        let text = std::fs::read_to_string(&path_str).unwrap();
        // list/info tie on score: the more recent info gets a larger rank; which has the
        // lowest score and the smallest rank (sorted first by -Descending).
        let parsed: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(parsed["info"], 3);
        assert_eq!(parsed["list"], 2);
        assert_eq!(parsed["which"], 1);
        // Unchanged content is not rewritten, and no .tmp is left behind.
        write_order(&path_str, &scores);
        assert_eq!(std::fs::read_to_string(&path_str).unwrap(), text);
        assert!(!std::path::Path::new(&format!("{path_str}.tmp")).exists());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
