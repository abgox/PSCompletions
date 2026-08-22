//! Dependency-free helpers shared by the `psc` CLI and the `psc-menu` engine.
//! Keep this crate lean: nothing here may pull in dependencies (the engine's
//! hot-path binary must stay small).

/// Strip a leading UTF-8 BOM if present. Legacy PowerShell 5.1 `Out-File -Encoding utf8`
/// writes one, which breaks serde_json parsing; `ReadAllText`-style readers consume it,
/// but raw `read_to_string` surfaces it as `\u{FEFF}`.
pub fn strip_bom(s: &str) -> &str {
    s.strip_prefix('\u{feff}').unwrap_or(s)
}

/// Read a UTF-8 text file, stripping a leading BOM. `None` when the file cannot be read.
pub fn read_text(path: &str) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    Some(strip_bom(&text).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strip_bom_removes_only_a_leading_bom() {
        assert_eq!(strip_bom("\u{feff}{\"a\":1}"), "{\"a\":1}");
        assert_eq!(strip_bom("{\"a\":1}"), "{\"a\":1}");
        // A BOM elsewhere is content, not metadata.
        assert_eq!(strip_bom("a\u{feff}b"), "a\u{feff}b");
        assert_eq!(strip_bom(""), "");
    }

    #[test]
    fn read_text_reads_and_strips() {
        let dir = std::env::temp_dir().join(format!("psc-common-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("t.json");
        let path = p.to_str().unwrap();
        std::fs::write(path, "\u{feff}hello").unwrap();
        assert_eq!(read_text(path).as_deref(), Some("hello"));
        std::fs::write(path, "plain").unwrap();
        assert_eq!(read_text(path).as_deref(), Some("plain"));
        assert_eq!(read_text(&format!("{path}.missing")), None);
        std::fs::remove_dir_all(&dir).ok();
    }
}
