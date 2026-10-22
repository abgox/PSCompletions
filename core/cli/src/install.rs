//! `psc --self-update`: how was this copy installed, and what updates it?
//!
//! Detection is by evidence, never by a guess — the fixed directory `install.sh` uses *plus* its `install.json` marker, scoop's `modules\PSCompletions` link, or a module directory that sits under `PSModulePath` and carries `bin/` beside `PSCompletions.psd1`.
//! Anything else is reported as unmanaged, so a source checkout is never mistaken for a copy we are allowed to replace.
//! See `design/psc-cli.md` for the detection rules.

use std::path::{Path, PathBuf};

/// How this copy of PSCompletions was installed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Method {
    /// Our own `install.sh`: the fixed directory, and a marker that says so.
    Script { dir: PathBuf },
    /// scoop, through the `psmodule` link it creates at `<root>\modules\PSCompletions` — that directory is the package, so `code` is it and the manifest is read there.
    Scoop { code: PathBuf },
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

    /// The directory the manifest sits in, when the method knows one.
    /// Every layout keeps `PSCompletions.psd1` beside `bin/`, so this is where the version is read and what `--self-update` shows.
    pub fn code(&self) -> Option<&Path> {
        match self {
            Method::Script { dir } | Method::Module { dir } => Some(dir),
            Method::Scoop { code, .. } => Some(code),
            Method::Unknown => None,
        }
    }
}

/// Everything detection reads from outside the binary's own path, made explicit so the tests never mutate the process environment.
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

/// The directory `install.sh` installs into — the same per-platform rule the script uses, and a sibling of the module's data directory: that one holds user data, this one holds code.
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
    if let Some(code) = scoop_code(exe, ctx) {
        return Method::Scoop { code };
    }
    if let Some(dir) = module_dir(exe) {
        if ctx.module_paths.iter().any(|root| dir.starts_with(root)) {
            return Method::Module { dir };
        }
    }
    Method::Unknown
}

/// The marker `install.sh` writes.
/// Its presence *and* its method string are the claim: a copy that merely happens to sit at that path — a module installed there by hand — is not ours to replace, which is why a missing marker falls through instead of being assumed.
fn marker_says_install_sh(dir: &Path) -> bool {
    std::fs::read_to_string(dir.join("install.json"))
        .ok()
        .and_then(|text| serde_json::from_str::<serde_json::Value>(&text).ok())
        .and_then(|v| v.get("method").and_then(|m| m.as_str()).map(String::from))
        .is_some_and(|m| m == "install.sh")
}

/// scoop's own root, found through its command: `scoop` lives in `<root>\shims`, so the directory holding the command tells us the root without trusting any variable — a user need not have set `SCOOP` at all.
/// `None` means "scoop is not installed here", and then nothing is scoop.
fn scoop_root(ctx: &Ctx) -> Option<PathBuf> {
    for dir in &ctx.path {
        for name in ["scoop.cmd", "scoop.ps1", "scoop.exe", "scoop"] {
            if !dir.join(name).is_file() {
                continue;
            }
            // `<root>\shims\scoop.cmd`: only that shape names a scoop root.
            // Windows ignores case, so the component is compared that way.
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

/// scoop's two layouts: the binary under `<root>\modules\PSCompletions\` (the `psmodule` link, what the module runs) or under `<root>\apps\<name>\<version-or-current>\` (what a `psc` launched from the shims runs).
/// Both keep the package three levels above the binary, so one offset gives the directory the manifest sits in.
fn scoop_code(exe: &Path, ctx: &Ctx) -> Option<PathBuf> {
    if !ctx.windows {
        return None;
    }
    let root = scoop_root(ctx)?;
    // Windows ignores case and spells separators `\`, so both sides are flattened before the prefix test.
    let flat = |p: &Path| p.to_string_lossy().replace('\\', "/").to_ascii_lowercase();
    let under = flat(exe);
    let owns = |dir: &Path| under.starts_with(&format!("{}/", flat(dir)));
    let ours = owns(&root.join("modules").join("PSCompletions"))
        || SCOOP_APPS.iter().any(|a| owns(&root.join("apps").join(a)));
    if !ours {
        return None;
    }
    // The package is three levels above the binary (`…\bin\<platform>-<arch>\psc.exe`), in either layout.
    // Derived from the flattened path so a Windows-shaped string resolves on any host, and joined with the platform's separator.
    let text = exe.to_string_lossy().replace('\\', "/");
    let mut parts: Vec<&str> = text.split('/').collect();
    parts.truncate(parts.len().saturating_sub(3));
    let sep = std::path::MAIN_SEPARATOR.to_string();
    Some(PathBuf::from(parts.join(&sep)))
}

/// The two names PSCompletions is published under: the lowercase `pscompletions` (the `main` bucket) and the author-qualified `abgox.PSCompletions`.
const SCOOP_APPS: [&str; 2] = ["pscompletions", "abgox.PSCompletions"];

/// The PowerShell module layout: the binary in `<module>/bin/<platform>-<arch>/`, with the module manifest beside `bin/`.
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

/// The installer itself, fetched from the same source prefix the completions come from — so a changed script takes effect on the next run, and a stale local copy can never be reused (an installed package does not carry one at all).
pub fn fetch_installer(settings: &crate::data::Settings) -> Result<String, String> {
    crate::net::fetch_metadata(&crate::net::resolve_urls(settings), "install.sh")
        .map_err(|e| e.message().to_string())
}

/// The installed version, from the manifest beside the bridges and the binaries — the one source that exists in a repo checkout and in an installed package alike (the bridges read it too).
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

/// The installed version for a detected method: every method keeps its manifest beside `bin/`, scoop included (through its link).
pub fn installed_dir(exe: &Path, method: &Method) -> Option<PathBuf> {
    method
        .code()
        .map(Path::to_path_buf)
        .or_else(|| package_dir(exe))
}

/// The package directory the binary sits in, derived from the layout every package shares: `bin/<platform>-<arch>/psc` beside `PSCompletions.psd1`.
/// Evidence only: a directory without the manifest is not a package, so an unmanaged copy reports no version rather than a guess.
pub fn package_dir(exe: &Path) -> Option<PathBuf> {
    let dir = exe.parent()?.parent()?.parent()?;
    dir.join("PSCompletions.psd1")
        .is_file()
        .then(|| dir.to_path_buf())
}

pub fn installed_version_for(exe: &Path, method: &Method) -> Option<String> {
    installed_dir(exe, method).and_then(|d| installed_version(&d))
}

/// Whether `a` is newer than `b`, comparing dot-separated numeric segments (`8.0.10` beats `8.0.9`, which a string compare gets wrong).
/// `None` when either side is not numeric: the caller must then keep its "cannot tell" branch instead of claiming a status.
pub fn version_newer(a: &str, b: &str) -> Option<bool> {
    fn segments(s: &str) -> Option<Vec<u64>> {
        s.trim().split('.').map(|p| p.parse::<u64>().ok()).collect()
    }
    let (mut a, mut b) = (segments(a)?, segments(b)?);
    let n = a.len().max(b.len());
    a.resize(n, 0);
    b.resize(n, 0);
    Some(a > b)
}

/// The commands a user runs to update this copy.
/// `Script` has none: there the CLI runs the installer itself, because it already knows the source URLs and the script owns the swap.
/// `installer_url` is the fetched installer's one-liner for an unmanaged copy, built by the caller from the same source prefix the completions come from.
pub fn update_commands(method: &Method, installer_url: &str) -> Vec<String> {
    match method {
        Method::Script { .. } => Vec::new(),
        // Both published names: the link names no single app, and each name is a separate install with its own update.
        Method::Scoop { .. } => vec![
            "scoop update pscompletions".to_string(),
            "scoop update abgox.PSCompletions".to_string(),
        ],
        // Both PowerShell routes are printed: the CLI cannot tell which one is available, and the module's own update notice names both for the same reason.
        Method::Module { .. } => vec![
            "Update-PSResource PSCompletions".to_string(),
            "Update-Module PSCompletions".to_string(),
        ],
        // Nothing installed it, so the advice is how to install it.
        // The short commands come first and the install script's one-liner last: it is long, and on Linux and macOS it is the one that needs no PowerShell at all.
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
        // The case the marker exists for: a *module* installed at our path.
        // Replacing it would overwrite someone else's install, so the path alone must never be enough.
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
    fn scoop_is_windows_only() {
        // scoop is a Windows package manager: the same path on another platform proves nothing.
        let base = test_base("scoop-os");
        let root = base.join("scoop");
        let ctx = Ctx {
            windows: false,
            ..ctx_scoop(&root)
        };
        let exe = format!(r"{}\modules\PSCompletions\bin\psc.exe", root.display());
        assert_eq!(detect_in(Path::new(&exe), &ctx), Method::Unknown);
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn the_psmodule_link_is_a_scoop_install() {
        // scoop's `psmodule` layout: `<root>\modules\PSCompletions` is the package, so the binary under it is ours.
        let base = test_base("scoop-modules");
        let root = base.join("scoop");
        let ctx = ctx_scoop(&root);
        let exe = format!(
            r"{}\modules\PSCompletions\bin\windows-x64\psc.exe",
            root.display()
        );
        assert_eq!(
            detect_in(Path::new(&exe), &ctx),
            Method::Scoop {
                code: root.join("modules").join("PSCompletions")
            }
        );
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn an_app_directory_is_a_scoop_install() {
        // What a `psc` launched from the shims runs: the app's own directory, under either published name.
        let base = test_base("scoop-apps");
        let root = base.join("scoop");
        let ctx = ctx_scoop(&root);
        for app in ["pscompletions", "abgox.PSCompletions"] {
            let exe = format!(
                r"{}\apps\{app}\current\bin\windows-x64\psc.exe",
                root.display()
            );
            assert_eq!(
                detect_in(Path::new(&exe), &ctx),
                Method::Scoop {
                    code: root.join("apps").join(app).join("current")
                },
                "{exe}"
            );
        }
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn another_root_or_another_module_is_not_ours() {
        // Only *this* scoop's link is ours, and only for our module name.
        let base = test_base("scoop-modules-other");
        let root = base.join("scoop");
        let ctx = ctx_scoop(&root);
        let elsewhere = base.join("elsewhere");
        for exe in [
            format!(r"{}\modules\PSCompletions\bin\psc.exe", elsewhere.display()),
            format!(r"{}\modules\my-project\bin\psc.exe", root.display()),
        ] {
            assert_eq!(detect_in(Path::new(&exe), &ctx), Method::Unknown, "{exe}");
        }
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn the_version_is_read_through_the_link() {
        // The link resolves by itself, so the manifest is read where it is linked to.
        let base = test_base("scoop-version");
        let code = base.join("scoop/modules/PSCompletions");
        std::fs::create_dir_all(&code).unwrap();
        std::fs::write(code.join("PSCompletions.psd1"), "ModuleVersion = '8.0.1'\n").unwrap();
        let method = Method::Scoop { code: code.clone() };
        let exe = code.join("bin/linux-x64/psc");
        assert_eq!(
            installed_version_for(&exe, &method).as_deref(),
            Some("8.0.1")
        );
        assert_eq!(method.code(), Some(code.as_path()));
        std::fs::remove_dir_all(&base).ok();
    }

    #[test]
    fn an_unmanaged_copy_reports_its_own_version_from_the_package_layout() {
        // The package always keeps the manifest three levels above the binary, so a copy nothing installed still knows which version it is.
        let base = test_base("pkg-layout");
        let pkg = base.join("package");
        std::fs::create_dir_all(pkg.join("bin/windows-x64")).unwrap();
        std::fs::write(pkg.join("PSCompletions.psd1"), "ModuleVersion = '8.0.2'\n").unwrap();
        let exe = pkg.join("bin/windows-x64/psc.exe");
        assert_eq!(
            installed_version_for(&exe, &Method::Unknown).as_deref(),
            Some("8.0.2")
        );
        assert_eq!(installed_dir(&exe, &Method::Unknown), Some(pkg.clone()));
        // Without the manifest that directory is just a directory: no version is invented.
        std::fs::remove_file(pkg.join("PSCompletions.psd1")).unwrap();
        assert_eq!(installed_version_for(&exe, &Method::Unknown), None);
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
        let exe = format!(r"{}\modules\PSCompletions\bin\psc.exe", root.display());
        assert_eq!(detect_in(Path::new(&exe), &ctx), Method::Unknown);
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
        // The repo's own layout is the module layout; without PSModulePath it stays unknown, so the advice is "install it properly" rather than a PowerShell command that cannot work.
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
                    code: PathBuf::from("/d")
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
                code: PathBuf::from("/d")
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
