use crate::menu::model::{Config, Item};

/// Filter the items by the given filter string (semantics: `design/filter-matching.md`).
/// The empty filter matches everything. Returns the indices (into `items`) of matches.
pub fn filter_items(items: &[Item], filter: &str, is_prefix: bool, cfg: &Config) -> Vec<usize> {
    if filter.is_empty() {
        return (0..items.len()).collect();
    }
    let actual = if is_prefix { &filter[1..] } else { filter };
    // subsequence config, or wildcard with `**` / leading-`*` (force subsequence) / plain
    let (use_subseq, pattern) = if cfg.flags.filter_mode == "subsequence" {
        (true, actual)
    } else if actual.starts_with("**") {
        (false, actual)
    } else if let Some(rest) = actual.strip_prefix('*') {
        (true, rest)
    } else {
        (false, actual)
    };
    let mut out = Vec::new();
    for (i, item) in items.iter().enumerate() {
        let text = item.list_item_text.as_str();
        let matched = if use_subseq {
            if is_prefix {
                prefix_subsequence_match(pattern, text)
            } else {
                subsequence_match(pattern, text)
            }
        } else {
            let mut p = parse_wildcard(pattern);
            if is_prefix {
                p.push(Pat::Any);
            } else {
                p.insert(0, Pat::Any);
                p.push(Pat::Any);
            }
            wildcard_match(&p, text)
        };
        if matched {
            out.push(i);
        }
    }
    out
}

/// A parsed wildcard pattern element.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Pat {
    /// A literal char to match exactly (case-insensitive); highlighted when matched.
    Lit(char),
    /// `*` wildcard: matches zero or more chars; never highlighted.
    Any,
}

/// Parse a wildcard-mode filter into a pattern (`**` → literal `*`, greedy left-to-right).
fn parse_wildcard(s: &str) -> Vec<Pat> {
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::with_capacity(chars.len());
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '*' {
            if i + 1 < chars.len() && chars[i + 1] == '*' {
                out.push(Pat::Lit('*'));
                i += 2;
            } else {
                out.push(Pat::Any);
                i += 1;
            }
        } else {
            out.push(Pat::Lit(chars[i]));
            i += 1;
        }
    }
    out
}

/// Wildcard matching (case-insensitive). Only `Any` consumes wildcard chars;
/// `Lit` must match the text char. Standard backtracking over the last `Any`.
fn wildcard_match(pat: &[Pat], text: &str) -> bool {
    let text: Vec<char> = text.chars().collect();
    let mut pi = 0usize;
    let mut ti = 0usize;
    let mut star: Option<usize> = None;
    let mut mark = 0usize;
    while ti < text.len() {
        if pi < pat.len() {
            match pat[pi] {
                Pat::Any => {
                    star = Some(pi);
                    mark = ti;
                    pi += 1;
                    continue;
                }
                Pat::Lit(l) => {
                    if l.eq_ignore_ascii_case(&text[ti]) {
                        pi += 1;
                        ti += 1;
                        continue;
                    }
                }
            }
        }
        // mismatch: backtrack to the last `Any` if any
        if let Some(sp) = star {
            mark += 1;
            ti = mark;
            pi = sp + 1;
            continue;
        }
        return false;
    }
    // consume trailing wildcards
    while pi < pat.len() && pat[pi] == Pat::Any {
        pi += 1;
    }
    pi == pat.len()
}

/// Highlight byte ranges for `text` matching the wildcard pattern, built with the same
/// pattern construction as `filter_items`. `Any` is not highlighted, `Lit` (incl. the
/// literal star escaped by `**`) is. `None` on no match.
pub fn wildcard_segments(text: &str, actual: &str, is_prefix: bool) -> Option<Vec<(usize, usize)>> {
    let mut pattern = parse_wildcard(actual);
    if is_prefix {
        pattern.push(Pat::Any);
    } else {
        pattern.insert(0, Pat::Any);
        pattern.push(Pat::Any);
    }
    wildcard_highlight(&pattern, text)
}

/// Like `wildcard_match`, but records the byte ranges of text chars consumed by `Lit`
/// pattern chars (`Any` is not highlighted).
///
/// On backtracking, drops the literal highlights hit in the failed segment (those chars
/// are re-consumed by the star). Returns `None` when `text` does not match the pattern.
fn wildcard_highlight(pat: &[Pat], text: &str) -> Option<Vec<(usize, usize)>> {
    let text_chars: Vec<(char, usize)> = text.char_indices().map(|(b, c)| (c, b)).collect();
    let mut pi = 0usize;
    let mut ti = 0usize;
    let mut star: Option<usize> = None;
    let mut mark = 0usize;
    // (text char index, byte start, byte end) — used to drop a failed segment's highlights
    // by index on backtracking.
    let mut hl: Vec<(usize, usize, usize)> = Vec::new();
    while ti < text_chars.len() {
        if pi < pat.len() {
            match pat[pi] {
                Pat::Any => {
                    star = Some(pi);
                    mark = ti;
                    pi += 1;
                    continue;
                }
                Pat::Lit(l) => {
                    if l.eq_ignore_ascii_case(&text_chars[ti].0) {
                        hl.push((
                            ti,
                            text_chars[ti].1,
                            text_chars[ti].1 + text_chars[ti].0.len_utf8(),
                        ));
                        pi += 1;
                        ti += 1;
                        continue;
                    }
                }
            }
        }
        // mismatch: backtrack to the last `Any` if any
        if let Some(sp) = star {
            while let Some(&(ci, _, _)) = hl.last() {
                if ci >= mark {
                    hl.pop();
                } else {
                    break;
                }
            }
            mark += 1;
            ti = mark;
            pi = sp + 1;
            continue;
        }
        return None;
    }
    // consume trailing wildcards
    while pi < pat.len() && pat[pi] == Pat::Any {
        pi += 1;
    }
    if pi != pat.len() {
        return None;
    }
    // Merge adjacent segments in text order (e.g. the a and d hit by "ad" merge into one,
    // matching the old behavior).
    let mut out: Vec<(usize, usize)> = Vec::new();
    for (_, s, e) in hl {
        if let Some(last) = out.last_mut() {
            if last.1 == s {
                last.1 = e;
                continue;
            }
        }
        out.push((s, e));
    }
    Some(out)
}

/// Subsequence match: every char of `pattern` appears in `text` in order.
fn subsequence_match(pattern: &str, text: &str) -> bool {
    let mut pi = 0;
    let pat: Vec<char> = pattern.chars().collect();
    for tc in text.chars() {
        if pi < pat.len() && pat[pi].eq_ignore_ascii_case(&tc) {
            pi += 1;
        }
    }
    pi == pat.len()
}

/// Prefix subsequence match: `text` starts with `pattern[0]` and the rest of
/// `pattern` appears in order afterwards.
fn prefix_subsequence_match(pattern: &str, text: &str) -> bool {
    let pat: Vec<char> = pattern.chars().collect();
    if pat.is_empty() {
        return true;
    }
    let mut tc = text.chars();
    match tc.next() {
        Some(first) if pat[0].eq_ignore_ascii_case(&first) => {}
        _ => return false,
    }
    let rest: String = pat[1..].iter().collect();
    subsequence_match(&rest, tc.as_str())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::menu::model::Flags;

    fn cfg(subseq: bool) -> Config {
        Config {
            filter_hint: String::new(),
            filter_hint_stale: String::new(),
            flags: Flags {
                enable_list_loop: true,
                filter_mode: if subseq {
                    "subsequence".into()
                } else {
                    "wildcard".into()
                },
                enable_tip: true,
                enable_tip_usage: true,
                enable_tip_example: true,
                enable_apply_when_single: false,
                enable_apply_when_no_match: false,
                show_mode: "auto".into(),
                color_focus: "red".into(),
                color_match: "cyan".into(),
            },
            context_switch: "~".into(),
            context_stay: "?".into(),
            raw_config: None,
        }
    }

    fn items(names: &[&str]) -> Vec<Item> {
        names
            .iter()
            .map(|n| Item {
                completion_text: n.to_string(),
                list_item_text: n.to_string(),
                tip: None,
                usage: None,
                example: None,
                result_type: None,
                symbol: String::new(),
            })
            .collect()
    }

    #[test]
    fn empty_filter_matches_all() {
        let its = items(&["a", "b", "c"]);
        assert_eq!(filter_items(&its, "", false, &cfg(false)), vec![0, 1, 2]);
        assert_eq!(filter_items(&its, "", false, &cfg(true)), vec![0, 1, 2]);
    }

    #[test]
    fn substring_is_case_insensitive() {
        let its = items(&["add", "branch", "commit"]);
        assert_eq!(filter_items(&its, "AD", false, &cfg(false)), vec![0]);
        assert_eq!(filter_items(&its, "ch", false, &cfg(false)), vec![1]);
        assert_eq!(filter_items(&its, "it", false, &cfg(false)), vec![2]);
    }

    #[test]
    fn prefix_mode() {
        let its = items(&["add", "apply", "stash", "show"]);
        assert_eq!(filter_items(&its, "^a", true, &cfg(false)), vec![0, 1]);
        assert_eq!(filter_items(&its, "^s", true, &cfg(false)), vec![2, 3]);
    }

    #[test]
    fn subsequence_mode() {
        let its = items(&["add", "apply", "branch", "back"]);
        // 'b' then 'a' in order
        assert_eq!(filter_items(&its, "ba", false, &cfg(true)), vec![2, 3]);
        // 'a' then 'p' in order
        assert_eq!(filter_items(&its, "ap", false, &cfg(true)), vec![1]);
    }

    #[test]
    fn prefix_subsequence_mode() {
        let its = items(&["abc", "xab", "ac"]);
        assert_eq!(filter_items(&its, "^a", true, &cfg(true)), vec![0, 2]);
        assert_eq!(filter_items(&its, "^ab", true, &cfg(true)), vec![0]);
    }

    #[test]
    fn literal_brackets() {
        let its = items(&["[string]", "System.Object", "a[]b"]);
        assert_eq!(filter_items(&its, "[", false, &cfg(false)), vec![0, 2]);
        assert_eq!(filter_items(&its, "[]", false, &cfg(false)), vec![2]);
    }

    #[test]
    fn wildcard_star() {
        let its = items(&["abc", "axc", "abbc"]);
        // 'a' + 'b' + ... : 'a' and 'b' in order with anything between
        assert_eq!(filter_items(&its, "a*b", false, &cfg(false)), vec![0, 2]);
        // A single * = any number of chars.
        assert_eq!(filter_items(&its, "a*c", false, &cfg(false)), vec![0, 1, 2]);
    }

    #[test]
    fn wildcard_highlight_backtrack_drops_failed_prefix() {
        // `open` matching Microsoft.OpenJDK.25: o first hits the first o of Microsoft, then
        // p fails and backtracks → that highlight must be dropped, leaving only the
        // O-p-e-n of OpenJDK highlighted (merged into one segment 10..14); the o inside
        // Microsoft must not be highlighted.
        let segs = wildcard_segments("Microsoft.OpenJDK.25", "open", false).unwrap();
        assert_eq!(segs, vec![(10, 14)]);
    }

    #[test]
    fn wildcard_double_star_escapes_literal() {
        let its = items(&["a*b", "aXb", "a**b", "a**b*c"]);
        // ** = literal star: a**b matches the literal "a*b" substring (only item 0 has "a*b").
        assert_eq!(filter_items(&its, "a**b", false, &cfg(false)), vec![0]);
        // *** = literal star + wildcard: a* then anything, then b.
        assert_eq!(
            filter_items(&its, "a***b", false, &cfg(false)),
            vec![0, 2, 3]
        );
        // **** = literal ** (a**b*c also contains the a**b substring, so it hits too).
        assert_eq!(filter_items(&its, "a****b", false, &cfg(false)), vec![2, 3]);
    }

    #[test]
    fn wildcard_question_is_literal() {
        let its = items(&["axc", "a?c"]);
        // ? is no longer a single-char wildcard but a literal character.
        assert_eq!(filter_items(&its, "a?c", false, &cfg(false)), vec![1]);
    }

    #[test]
    fn leading_star_forces_subsequence_in_wildcard() {
        // Under the wildcard config, a single leading `*` forces subsequence: a-b-c scattered
        // in order (≠ contiguous containment).
        let its = items(&["xabc", "xaybc"]);
        assert_eq!(filter_items(&its, "abc", false, &cfg(false)), vec![0]); // contiguous containment
        assert_eq!(filter_items(&its, "*abc", false, &cfg(false)), vec![0, 1]); // forced subsequence
                                                                                // after which `*` is literal
        let its2 = items(&["ab", "aXb", "a*b", "a*bc"]);
        assert_eq!(filter_items(&its2, "*a*b", false, &cfg(false)), vec![2, 3]);
        // After forcing subsequence, a non-first `^` → literal: ^-a-b-c in order.
        let its3 = items(&["^abc", "x^aybc"]);
        assert_eq!(filter_items(&its3, "*^abc", false, &cfg(false)), vec![0, 1]);
    }

    #[test]
    fn star_is_literal_in_subsequence_config() {
        // Under the subsequence config `*` is always literal: the literal "*abc" in order.
        let its = items(&["*abc", "xa*bc", "xabc"]);
        assert_eq!(filter_items(&its, "*abc", false, &cfg(true)), vec![0]);
        // The prefix anchors the pattern's **first char `*`**, not `a`.
        let its2 = items(&["*abc", "a*bc", "x*abc"]);
        assert_eq!(filter_items(&its2, "^*abc", true, &cfg(true)), vec![0]);
    }

    #[test]
    fn caret_star_prefix_and_force_in_wildcard() {
        // Under wildcard, `^*abc` = prefix + forced subsequence → `a` anchored + bc subsequence.
        let its = items(&["abc", "axbc", "xabc"]);
        assert_eq!(filter_items(&its, "^*abc", true, &cfg(false)), vec![0, 1]);
        // `**abc` (`**` escape) = wildcard containing the literal "*abc".
        let its2 = items(&["x*abcy", "abc", "*abc"]);
        assert_eq!(filter_items(&its2, "**abc", false, &cfg(false)), vec![0, 2]);
    }
}
