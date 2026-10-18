//! `psc --self-update`: how was this copy installed, and what updates it?
//!
//! Detection is by evidence, never by a guess — the fixed directory `install.sh` uses *plus* its
//! `install.json` marker, scoop's `apps\<name>\current\` shape, or a module directory that sits
//! under `PSModulePath` and carries `bin/` beside `PSCompletions.psd1`. Anything else is reported
//! as unmanaged, so a source checkout is never mistaken for a copy we are allowed to replace.
//! See `design/psc-cli.md` for the detection rules.

use std::path::{Path, PathBuf};

/// How this copy of PSCompletions was installed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Method {
    /// Our own `install.sh`: the fixed directory, and a marker that says so.
    Script { dir: PathBuf },
    /// scoop, whose manifest name is part of the binary's own path. Both names may be installed at
    /// once, and each is a separate install with its own `scoop update`, so every installed app is
    /// carried — not only the running one.
    Scoop { root: PathBuf, apps: Vec<String> },
    /// The PowerShell module, installed from the Gallery into `PSModulePath`.
    Module { dir: PathBuf },
    /// A source checkout, a hand copy — nothing we know how to update.
    Unknown,
}

impl Method {
    /// The stable name the JSON contract and the `info` templates key on.
    pub fn kind(&self) -> &'static str {
        match self {
            Method::Script { .. } => "script",
            Method::Scoop { .. } => "scoop",
            Method::Module { .. } => "module",
            Method::Unknown => "unknown",
        }
    }

    /// The directory this copy lives in, when the method knows one.
    pub fn dir(&self) -> Option<&Path> {
        match self {
            Method::Script { dir } | Method::Module { dir } => Some(dir),
            Method::Scoop { root, .. } => Some(root),
            Method::Unknown => None,
        }
    }
}

/// Everything detection reads from outside the binary's own path, made explicit so the tests never
/// mutate the process environment.
#[derive(Debug, Default, Clone)]
pub struct Ctx {
    /// The fixed directory `install.sh` installs into.
    pub script_dir: Option<PathBuf>,
    /// The `PSModulePath` entries, for telling a Gallery install from a checkout.
    pub module_paths: Vec<PathBuf>,
    /// The `PATH` entries, used to find scoop's own command (its `shims` directory).
    pub path: Vec<PathBuf>,
    /// scoop is a Windows package manager, so its check runs there and nowhere else.
    pub windows: bool,
}

/// The directory `install.sh` installs into — the same per-platform rule the script uses, and a
/// sibling of the module's data directory: that one holds user data, this one holds code.
pub fn script_dir() -> Option<PathBuf> {
    let home = PathBuf::from(std::env::var_os("HOME")?);
    if std::env::consts::OS == "macos" {
        return Some(home.join("Library/Application Support/PSCompletions"));
    }
    let base = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| home.join(".local/share"));
    Some(base.join("PSCompletions"))
}

/// The method of the copy that is running.
pub fn detect(exe: &Path) -> Method {
    detect_in(
        exe,
        &Ctx {
            script_dir: script_dir(),
            module_paths: std::env::var("PSModulePath")
                .map(|v| std::env::split_paths(&v).collect())
                .unwrap_or_default(),
            path: std::env::var("PATH")
                .map(|v| std::env::split_paths(&v).collect())
                .unwrap_or_default(),
            windows: std::env::consts::OS == "windows",
        },
    )
}

/// The evidence-only half.
pub fn detect_in(exe: &Path, ctx: &Ctx) -> Method {
    if let Some(dir) = ctx.script_dir.as_deref() {
        if exe.starts_with(dir) && marker_says_install_sh(dir) {
            return Method::Script {
                dir: dir.to_path_buf(),
            };
        }
    }
    if let Some((root, name)) = scoop_app(exe, ctx) {
        // Every app this scoop has, not only the running one: both names can be installed, and
        // each needs its own `scoop update`. A failed listing falls back to the running app.
        let apps = {
            let found = scoop_apps(&root);
            if found.is_empty() {
                vec![name]
            } else {
                found
            }
        };
        return Method::Scoop { root, apps };
    }
    if let Some(dir) = module_dir(exe) {
        if ctx.module_paths.iter().any(|root| dir.starts_with(root)) {
            return Method::Module { dir };
        }
    }
    Method::Unknown
}

/// The marker `install.sh` writes. Its presence *and* its method string are the claim: a copy that
/// merely happens to sit at that path — a module installed there by hand — is not ours to replace,
/// which is why a missing marker falls through instead of being assumed.
fn marker_says_install_sh(dir: &Path) -> bool {
    std::fs::read_to_string(dir.join("install.json"))
        .ok()
        .and_then(|text| serde_json::from_str::<serde_json::Value>(&text).ok())
        .and_then(|v| v.get("method").and_then(|m| m.as_str()).map(String::from))
        .is_some_and(|m| m == "install.sh")
}

/// The two names PSCompletions is published under: the lowercase `pscompletions` (the `main`
/// bucket, so the plain one comes first) and the author-qualified `abgox.PSCompletions`.
const SCOOP_APPS: [&str; 2] = ["pscompletions", "abgox.PSCompletions"];

/// scoop's own root, found through its command: `scoop` lives in `<root>\shims`, so the directory
/// holding the command tells us the root without trusting any variable — a user need not have set
/// `SCOOP` at all. `None` means "scoop is not installed here", and then nothing is scoop.
fn scoop_root(ctx: &Ctx) -> Option<PathBuf> {
    for dir in &ctx.path {
        for name in ["scoop.cmd", "scoop.ps1", "scoop.exe", "scoop"] {
            if !dir.join(name).is_file() {
                continue;
            }
            // `<root>\shims\scoop.cmd`: only that shape names a scoop root. Windows ignores case,
            // so the component is compared that way.
            if dir
                .file_name()
                .is_some_and(|n| n.eq_ignore_ascii_case("shims"))
            {
                return dir.parent().map(Path::to_path_buf);
            }
        }
    }
    None
}

/// scoop's layout is `<root>\apps\<name>\…`, and the app name is in the binary's own path. Only
/// the `apps` level is judged: below it scoop keeps both `current` (a junction) and the real
/// version directories, so anything deeper is none of our business. Both separators are split on,
/// since the check must work on a Windows path even when the tests run on Unix; Windows ignores
/// case, so every comparison here does too.
fn scoop_app(exe: &Path, ctx: &Ctx) -> Option<(PathBuf, String)> {
    if !ctx.windows {
        return None;
    }
    let root = scoop_root(ctx)?;
    let text = exe.to_string_lossy().replace('\\', "/");
    let parts: Vec<&str> = text.split('/').collect();
    let apps = parts.iter().position(|p| p.eq_ignore_ascii_case("apps"))?;
    let name = *parts.get(apps + 1)?;
    if !SCOOP_APPS.iter().any(|a| a.eq_ignore_ascii_case(name)) {
        return None;
    }
    // It must be *this* root's app: an `apps\<name>\` tree elsewhere is not ours to update.
    let root_text = root.to_string_lossy().replace('\\', "/");
    let prefix = format!("{}/apps/{name}/", root_text.trim_end_matches('/'));
    if !text
        .to_ascii_lowercase()
        .starts_with(&prefix.to_ascii_lowercase())
    {
        return None;
    }
    // The canonical spelling, so a command always names an app that exists.
    let canonical = SCOOP_APPS
        .iter()
        .find(|a| a.eq_ignore_ascii_case(name))
        .copied()
        .unwrap_or(name);
    Some((root, canonical.to_string()))
}

/// The PSCompletions apps this scoop has installed, in the canonical order.
fn scoop_apps(root: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(root.join("apps")) else {
        return Vec::new();
    };
    let names: Vec<String> = entries
        .flatten()
        .map(|e| e.file_name().to_string_lossy().to_string())
        .collect();
    SCOOP_APPS
        .iter()
        .filter(|a| names.iter().any(|n| n.eq_ignore_ascii_case(a)))
        .map(|a| a.to_string())
        .collect()
}

/// The PowerShell module layout: the binary in `<module>/bin/<platform>-<arch>/`, with the module
/// manifest beside `bin/`.
fn module_dir(exe: &Path) -> Option<PathBuf> {
    let bin = exe.parent()?.parent()?;
    if bin.file_name()? != "bin" {
        return None;
    }
    let dir = bin.parent()?;
    if dir.join("PSCompletions.psd1").is_file() {
        return Some(dir.to_path_buf());
    }
    None
}

/// The installer itself, fetched from the same source prefix the completions come from — so a
/// changed script takes effect on the next run, and a stale local copy can never be reused (an
/// installed package does not carry one at all).
pub fn fetch_installer(settings: &crate::data::Settings) -> Result<String, String> {
    crate::net::fetch_text(&crate::net::resolve_urls(settings), "install.sh")
        .map_err(|e| e.message().to_string())
}

/// The installed version, from the manifest beside the bridges and the binaries — the one source
/// that exists in a repo checkout and in an installed package alike (the bridges read it too).
pub fn installed_version(dir: &Path) -> Option<String> {
    let text = std::fs::read_to_string(dir.join("PSCompletions.psd1")).ok()?;
    for line in text.lines() {
        let Some(rest) = line.trim().strip_prefix("ModuleVersion") else {
            continue;
        };
        let Some(rest) = rest.trim_start().strip_prefix('=') else {
            continue;
        };
        let value = rest.trim().trim_matches(|c| c == '\'' || c == '"').trim();
        if !value.is_empty() {
            return Some(value.to_string());
        }
    }
    None
}

/// The commands a user runs to update this copy. `Script` has none: there the CLI runs the
/// installer itself, because it already knows the source URLs and the script owns the swap.
/// `installer_url` is the fetched installer's one-liner for an unmanaged copy, built by the caller
/// from the same source prefix the completions come from.
pub fn update_commands(method: &Method, installer_url: &str) -> Vec<String> {
    match method {
        Method::Script { .. } => Vec::new(),
        Method::Scoop { apps, .. } => apps.iter().map(|a| format!("scoop update {a}")).collect(),
        // Both PowerShell routes are printed: the CLI cannot tell which one is available, and the
        // module's own update notice names both for the same reason.
        Method::Module { .. } => vec![
            "Update-PSResource PSCompletions".to_string(),
            "Update-Module PSCompletions".to_string(),
        ],
        // Nothing installed it, so the advice is how to install it. The short commands come first
        // and the install script's one-liner last: it is long, and on Linux and macOS it is the one
        // that needs no PowerShell at all.
        Method::Unknown => {
            let mut out = vec![
                "Install-Module PSCompletions".to_string(),
                "Install-PSResource PSCompletions".to_string(),
                "scoop install pscompletions".to_string(),
                "scoop install abgox.PSCompletions".to_string(),
            ];
            if !installer_url.is_empty() {
                out.push(installer_url.to_string());
            }
            out
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_base(tag: &str) -> PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        std::env::temp_dir().join(format!(
            "psc-install-{tag}-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ))
    }

    /// A context whose fixed directory is `dir`.
    fn ctx_script(dir: &Path) -> Ctx {
        Ctx {
            script_dir: Some(dir.to_path_buf()),
            ..Ctx::default()
        }
    }

    /// A Windows context where scoop's command sits in `<root>/shims`.
    fn ctx_scoop(root: &Path) -> Ctx {
        let shims = root.join("shims");
        std::fs::create_dir_all(&shims).unwrap();
        std::fs::write(shims.join("scoop.cmd"), "").unwrap();
        Ctx {
            path: vec![shims],
            windows: true,
            ..Ctx::default()
        }
    }

    /// A module directory: `bin/<platform>-<arch>/psc` beside the manifest.
    fn make_module(base: &Path) -> PathBuf {
        let dir = base.join("PSCompletions");
        std::fs::create_dir_all(dir.join("bin/linux-x64")).unwrap();
        std::fs::write(dir.join("bin/linux-x64/psc"), "#!/bin/sh\n").unwrap();
        std::fs::write(dir.join("PSCompletions.psd1"), "ModuleVersion = '8.0.0'\n").unwrap();
        dir
    }

    #[test]
    fn a_marked_script_dir_is_the_script_method() {
        let base = test_base("script");
        let dir = base.join("PSCompletions");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("install.json"), r#"{"method":"install.sh"}"#).unwrap();
        let exe = dir.join("bin/linux-x64/psc");
        assert_eq!(
            detect_in(&exe, &ctx_script(&dir)),
            Method::Script { dir: dir.clone() }
        );
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn the_fixed_path_without_the_marker_is_not_ours() {
        // The case the marker exists for: a *module* installed at our path. Replacing it would
        // overwrite someone else's install, so the path alone must never be enough.
        let base = test_base("nomarker");
        let dir = make_module(&base);
        let exe = dir.join("bin/linux-x64/psc");
        assert_eq!(detect_in(&exe, &ctx_script(&dir)), Method::Unknown);
        // …and with the marker naming another method, still not ours.
        std::fs::write(dir.join("install.json"), r#"{"method":"brew"}"#).unwrap();
        assert_eq!(detect_in(&exe, &ctx_script(&dir)), Method::Unknown);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn scoop_names_the_app_from_its_own_root() {
        // The root comes from scoop's command: `scoop.cmd` lives in `<root>\shims`, so the
        // directory holding it names the root — no variable needed. Only the `apps` level is
        // judged, so `current` (a junction) and a real version directory are both accepted, and
        // Windows' case insensitivity is honoured. The binary path is written with backslashes
        // while the fake tree uses this machine's separator: exactly the mixture to survive.
        let base = test_base("scoop");
        let root = base.join("scoop");
        let ctx = ctx_scoop(&root);
        for (tail, want) in [
            (
                r"apps\abgox.PSCompletions\current\bin\windows-x64\psc.exe",
                "abgox.PSCompletions",
            ),
            (
                r"apps\pscompletions\current\bin\windows-x64\psc.exe",
                "pscompletions",
            ),
            (
                r"apps\abgox.PSCompletions\8.0.0\bin\windows-x64\psc.exe",
                "abgox.PSCompletions",
            ),
            (
                r"apps\ABGOX.pscompletions\current\bin\windows-x64\psc.exe",
                "ABGOX.pscompletions",
            ),
        ] {
            let exe = format!(r"{}\{tail}", root.display());
            // No `apps/` directory in the fake tree, so the installed-app listing is empty and the
            // running app alone is carried — spelled canonically, not as the path spelled it.
            let canonical = if want.eq_ignore_ascii_case("pscompletions") {
                "pscompletions"
            } else {
                "abgox.PSCompletions"
            };
            assert_eq!(
                detect_in(Path::new(&exe), &ctx),
                Method::Scoop {
                    root: root.clone(),
                    apps: vec![canonical.to_string()]
                },
                "{exe}"
            );
        }
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn both_scoop_names_installed_are_both_reported() {
        // The two manifest names are separate installs, so both are carried — the running one alone
        // would leave the other never updated.
        let base = test_base("scoop-both");
        let root = base.join("scoop");
        let ctx = ctx_scoop(&root);
        std::fs::create_dir_all(root.join("apps/abgox.PSCompletions")).unwrap();
        std::fs::create_dir_all(root.join("apps/pscompletions")).unwrap();
        let exe = format!(
            r"{}\apps\pscompletions\current\bin\windows-x64\psc.exe",
            root.display()
        );
        assert_eq!(
            detect_in(Path::new(&exe), &ctx),
            Method::Scoop {
                root: root.clone(),
                apps: vec![
                    "pscompletions".to_string(),
                    "abgox.PSCompletions".to_string()
                ]
            }
        );
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn scoop_is_windows_only() {
        // scoop is a Windows package manager: the same path on another platform proves nothing.
        let base = test_base("scoop-os");
        let root = base.join("scoop");
        let ctx = Ctx {
            windows: false,
            ..ctx_scoop(&root)
        };
        let exe = format!(r"{}\apps\pscompletions\current\bin\psc.exe", root.display());
        assert_eq!(detect_in(Path::new(&exe), &ctx), Method::Unknown);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn scoop_needs_its_command() {
        // Without the command there is no root to trust, even when the path looks like scoop's.
        let base = test_base("scoop-nocmd");
        let root = base.join("scoop");
        std::fs::create_dir_all(root.join("shims")).unwrap();
        let ctx = Ctx {
            path: vec![root.join("shims")],
            windows: true,
            ..Ctx::default()
        };
        let exe = format!(r"{}\apps\pscompletions\current\bin\psc.exe", root.display());
        assert_eq!(detect_in(Path::new(&exe), &ctx), Method::Unknown);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn only_our_own_apps_count() {
        // Another app under our scoop root, or our name under another root: neither is ours, and
        // saying it is would print a command that cannot work.
        let base = test_base("scoop-other");
        let root = base.join("scoop");
        let ctx = ctx_scoop(&root);
        for exe in [
            format!(r"{}\apps\my-project\current\bin\psc.exe", root.display()),
            format!(
                r"{}\work\apps\abgox.PSCompletions\current\bin\psc.exe",
                base.display()
            ),
        ] {
            assert_eq!(detect_in(Path::new(&exe), &ctx), Method::Unknown, "{exe}");
        }
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn a_module_under_psmodulepath_is_the_module_method() {
        let base = test_base("module");
        let root = base.join("Modules");
        let dir = make_module(&root);
        let exe = dir.join("bin/linux-x64/psc");
        let ctx = Ctx {
            module_paths: vec![root.clone()],
            ..Ctx::default()
        };
        assert_eq!(detect_in(&exe, &ctx), Method::Module { dir: dir.clone() });
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn a_checkout_looks_like_a_module_but_is_not_managed() {
        // The repo's own layout is the module layout; without PSModulePath it stays unknown, so
        // the advice is "install it properly" rather than a PowerShell command that cannot work.
        let base = test_base("checkout");
        let dir = make_module(&base);
        let exe = dir.join("bin/linux-x64/psc");
        assert_eq!(detect_in(&exe, &Ctx::default()), Method::Unknown);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn installed_version_reads_the_manifest() {
        let base = test_base("version");
        let dir = make_module(&base);
        std::fs::write(
            dir.join("PSCompletions.psd1"),
            "    ModuleVersion        = '8.1.0'\n    PowerShellVersion = '5.1'\n",
        )
        .unwrap();
        assert_eq!(installed_version(&dir).as_deref(), Some("8.1.0"));
        std::fs::remove_file(dir.join("PSCompletions.psd1")).unwrap();
        assert_eq!(installed_version(&dir), None);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn update_commands_follow_the_method() {
        let installer = "curl -fsSL https://example.com/install.sh | sh";
        assert!(update_commands(
            &Method::Script {
                dir: PathBuf::from("/d")
            },
            installer
        )
        .is_empty());
        assert_eq!(
            update_commands(
                &Method::Scoop {
                    root: PathBuf::from("/d"),
                    apps: vec!["abgox.PSCompletions".into()]
                },
                installer
            ),
            vec!["scoop update abgox.PSCompletions".to_string()]
        );
        // Both names installed: each is a separate install, so each gets its own command.
        assert_eq!(
            update_commands(
                &Method::Scoop {
                    root: PathBuf::from("/d"),
                    apps: vec!["pscompletions".into(), "abgox.PSCompletions".into()]
                },
                installer
            ),
            vec![
                "scoop update pscompletions".to_string(),
                "scoop update abgox.PSCompletions".to_string()
            ]
        );
        let module = update_commands(
            &Method::Module {
                dir: PathBuf::from("/d"),
            },
            installer,
        );
        assert!(module.iter().any(|c| c.contains("Update-PSResource")));
        assert!(module.iter().any(|c| c.contains("Update-Module")));
        // Nothing installed it: every route is offered, the install script's long one-liner last.
        let unknown = update_commands(&Method::Unknown, installer);
        assert_eq!(unknown.last().map(String::as_str), Some(installer));
        assert!(unknown.iter().any(|c| c.contains("Install-Module")));
        assert!(unknown.iter().any(|c| c.contains("scoop install")));
        // Without a source (offline), the script line is simply absent, never blank.
        assert!(!update_commands(&Method::Unknown, "")
            .iter()
            .any(|c| c.is_empty()));
    }

    #[test]
    fn kind_is_the_stable_name() {
        assert_eq!(
            Method::Script {
                dir: PathBuf::from("/d")
            }
            .kind(),
            "script"
        );
        assert_eq!(Method::Unknown.kind(), "unknown");
        assert_eq!(
            Method::Scoop {
                root: PathBuf::from("/d"),
                apps: vec!["x".into()]
            }
            .kind(),
            "scoop"
        );
        assert_eq!(
            Method::Module {
                dir: PathBuf::from("/d")
            }
            .kind(),
            "module"
        );
    }
}
