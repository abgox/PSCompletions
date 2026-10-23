#!/bin/sh
# PSCompletions installer for bash / zsh / fish — no PowerShell involved.
#
# It downloads the module package from the PowerShell Gallery, unpacks it into a fixed install directory, and prints the setup step for your shell.
# A re-run asks the Gallery for the latest version first — one request, without the package — and stops with the rc lines when that is the installed one.
# The data directory (settings and installed completions) belongs to the module and is never touched.
#
#   sh install.sh                 # installs, then prints the rc line for every shell
#
# The bridges are all installed either way; `$SHELL` only decides which rc line is printed first.
#
# The install directory is fixed and not configurable: the path itself is how `psc --self-update` recognises a copy installed by this script (see the README's install section).

# --- help-zh ---
# 适用于 bash / zsh / fish 的 PSCompletions 安装脚本 —— 不涉及 PowerShell。
#
# 它从 PowerShell Gallery 下载模块包，解压到固定的安装目录，并打印你的 shell 需要的设置步骤。
# 重新运行时先问 Gallery 哪个版本最新 —— 只发一个请求，不下载整个包 —— 如果装的已经是最新，就停在打印 rc 行。
# 数据目录（设置和已安装补全）属于模块所有，绝不动它。
#
#   sh install.sh                 # 安装，然后为每个 shell 打印 rc 行
#
# 桥接反正都会装；`$SHELL` 只决定先打印哪个 shell 的 rc 行。
#
# 安装目录是固定的、不可配置：`psc --self-update` 就靠这个路径认出这个副本是它装的（见 README 的安装一节）。

set -eu

PACKAGE_PAGE=https://www.powershellgallery.com/packages/PSCompletions
PACKAGE_CDN=https://cdn.powershellgallery.com/packages

say() { printf '%s\n' "$*"; }
warn() { printf '[PSCompletions] %s\n' "$*" >&2; }
die() {
    printf '[PSCompletions] %s\n' "$*" >&2
    exit 1
}

# Messages follow the locale: Chinese when it says so, English otherwise — the same `zh`-prefix rule the CLI uses.
is_zh() {
    case "${LC_ALL:-${LANGUAGE:-${LC_MESSAGES:-${LANG:-}}}}" in
        [Zz][Hh]*) return 0 ;;
        *) return 1 ;;
    esac
}

msg() { # <key> [args...] — print the message for the current language.
    key="$1"; shift
    if is_zh; then
        # --- zh ---
        case "$key" in
            need_downloader) printf 'curl 或 wget（用于下载安装包）' ;;
            need_unpacker) printf 'unzip、bsdtar、tar 或 python3（用于解压安装包）' ;;
            need_python) printf 'python3 或 python（桥接运行时需要）' ;;
            missing_list) printf '[PSCompletions] 缺少以下命令：%s\n' "$@" ;;
            install_first) printf '请先安装它们，再重新运行此脚本' ;;
            no_dl_tool) printf '没有可用于下载安装包的 curl 或 wget' ;;
            no_unpacker) printf '无法解压安装包：请安装 unzip、bsdtar 或 python3' ;;
            move_aside) printf '无法将已有的 %s 移开' "$@" ;;
            prev_copy_at) printf '之前的副本在 %s' "$@" ;;
            move_into_place) printf '无法将新副本就位' ;;
            rc_bash) printf '# bash —— 把下面这行加到 ~/.bashrc 的末尾' ;;
            rc_zsh) printf '# zsh —— 把下面这行加到 ~/.zshrc 的末尾' ;;
            rc_fish) printf '# fish —— 把它链接进 conf.d（或从 config.fish 里 source 它）' ;;
            shell_setup) printf '[配置]' ;;
            uninstall_title) printf '[卸载]' ;;
            uninstall_hint) printf '删除 "%s" 并撤销你为 shell 做的设置' "$@" ;;
            unknown_arg) printf '未知参数：%s（用 --help 查看）' "$@" ;;
            bad_platform) printf '不支持的平台：%s' "$@" ;;
            bad_arch) printf '不支持的架构：%s' "$@" ;;
            checking) printf '正在检查最新版本……' ;;
            already_installed) printf '最新版本（%s）已安装在 %s' "$@" ;;
            downloading) printf '正在下载最新安装包……' ;;
            no_latest) printf '无法读取最新版本，请检查网络后重试' ;;
            updating) printf '正在更新 %s > %s' "$@" ;;
            dl_failed) printf '无法从 %s 下载安装包' "$@" ;;
            not_zip) printf '下载到的不是 zip 压缩包（可能是代理或 captive portal 截获了请求）' ;;
            no_version) printf '无法读取安装包版本（包结构不符合预期）' ;;
            no_bridge) printf '安装包 %s 里没有 %s 桥接' "$@" ;;
            installed) printf '已安装 %s，路径: %s' "$@" ;;
            sponsors_title) printf '赞助商' ;;
            sponsor_cta) printf '成为赞助商' ;;
            # --- end ---
            *) printf '%s' "$key" ;;
        esac
    else
        # --- en ---
        case "$key" in
            need_downloader) printf 'curl or wget (to download the package)' ;;
            need_unpacker) printf 'unzip, bsdtar, tar or python3 (to unpack the package)' ;;
            need_python) printf 'python3 or python (the bridge needs it at runtime)' ;;
            missing_list) printf '[PSCompletions] these commands are missing:%s\n' "$@" ;;
            install_first) printf 'install them first, then run this script again' ;;
            no_dl_tool) printf 'neither curl nor wget is available to download the package' ;;
            no_unpacker) printf 'cannot unpack the package: install unzip, bsdtar or python3' ;;
            move_aside) printf 'cannot move the existing %s aside' "$@" ;;
            prev_copy_at) printf 'the previous copy is at %s' "$@" ;;
            move_into_place) printf 'cannot move the new copy into place' ;;
            rc_bash) printf '# bash — add this as the last line of ~/.bashrc' ;;
            rc_zsh) printf '# zsh — add this as the last line of ~/.zshrc' ;;
            rc_fish) printf '# fish — link it into conf.d (or source it from config.fish)' ;;
            shell_setup) printf '[Setup]' ;;
            uninstall_title) printf '[Uninstall]' ;;
            uninstall_hint) printf 'rm -rf "%s" and undo the setup step for your shell' "$@" ;;
            unknown_arg) printf 'unknown argument: %s (see --help)' "$@" ;;
            bad_platform) printf 'unsupported platform: %s' "$@" ;;
            bad_arch) printf 'unsupported architecture: %s' "$@" ;;
            checking) printf 'Checking the latest version...' ;;
            already_installed) printf 'The latest version (%s) is already installed at %s' "$@" ;;
            downloading) printf 'Downloading the latest package...' ;;
            no_latest) printf 'cannot read the latest version; check the network and try again' ;;
            updating) printf 'Updating %s > %s' "$@" ;;
            dl_failed) printf 'cannot download the package from %s' "$@" ;;
            not_zip) printf 'the download is not a zip archive (a proxy or a captive portal may have intercepted it)' ;;
            no_version) printf 'cannot read the package version (unexpected package layout)' ;;
            no_bridge) printf 'package %s carries no %s bridge' "$@" ;;
            installed) printf 'Installed %s at %s' "$@" ;;
            sponsors_title) printf 'Sponsors' ;;
            sponsor_cta) printf 'Become a sponsor' ;;
            # --- end ---
            *) printf '%s' "$key" ;;
        esac
    fi
}

# --- where ---------------------------------------------------------------------

detect_platform() {
    case "$(uname -s)" in
        Linux*) echo linux ;;
        Darwin*) echo darwin ;;
        MINGW* | MSYS* | CYGWIN*) echo windows ;;
        *) echo unknown ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64 | amd64) echo x64 ;;
        aarch64 | arm64) echo arm64 ;;
        *) echo unknown ;;
    esac
}

# Fixed per platform, and deliberately a sibling of the module's data directory (`.../com.abgox/PSCompletions`): this one holds code, that one holds user data.
install_dir() {
    case "$1" in
        darwin) printf '%s\n' "$HOME/Library/Application Support/PSCompletions" ;;
        *) printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/PSCompletions" ;;
    esac
}

detect_shell() {
    case "$(basename -- "${SHELL:-}")" in
        bash | zsh | fish) basename -- "$SHELL" ;;
        *) echo "" ;;
    esac
}

# --- the package ---------------------------------------------------------------

# One GET, following the Gallery's redirect to its CDN.
# There is no version in the URL: it always resolves to the latest published package, which is what this script installs.
download() { # <url> <file>
    if command -v curl >/dev/null 2>&1; then
        # Bounded on purpose: without these a stalled transfer waits forever, and the user has to kill a script that looks hung.
        curl -fsSL --retry 2 --connect-timeout 10 --max-time 600 -A "PSCompletions-install" -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 15 -O "$2" "$1"
    else
        die "$(msg no_dl_tool)"
    fi
}

# The first tool that can unpack a zip wins: `unzip` is common on Linux but not guaranteed, macOS ships bsdtar as `tar`, and python3 is the last resort.
# GNU tar refuses a zip outright, so a failure here is clean and the next tool is tried.
extract() { # <zip> <dest>
    mkdir -p "$2"
    if command -v unzip >/dev/null 2>&1 && unzip -q -o "$1" -d "$2"; then return 0; fi
    if command -v bsdtar >/dev/null 2>&1 && bsdtar -xf "$1" -C "$2"; then return 0; fi
    if command -v tar >/dev/null 2>&1 && tar -xf "$1" -C "$2" 2>/dev/null; then return 0; fi
    if command -v python3 >/dev/null 2>&1 && python3 -m zipfile -e "$1" "$2"; then return 0; fi
    die "$(msg no_unpacker)"
}

package_version() { # <unpacked dir>
    sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' "$1/PSCompletions.nuspec" 2>/dev/null | head -1
}

# The latest published version, read from the redirect the Gallery answers with instead of from the package.
# That request is the one the download would follow anyway, and the CDN filename it points at ends in `<version>.nupkg` — the package name carries no dot, so the version is what sits between the two.
# Empty when nothing could be read (no curl, a mirror, an offline run): the caller then downloads, which is slower but never wrong.
latest_version() {
    command -v curl >/dev/null 2>&1 || return 1
    # A probe, not a download: keep it short so a dead host costs seconds, not minutes.
    # The unversioned page redirects to the latest version's page, so the version is the last path segment — no HTML is fetched or parsed.
    location="$(curl -sS --connect-timeout 5 --max-time 15 -o /dev/null -w '%{redirect_url}' "$PACKAGE_PAGE" 2>/dev/null)" || return 1
    found="${location##*/}"
    # A version, not a leftover: anything else means the Gallery changed its URL shape, and guessing would be worse than downloading.
    case "$found" in
        [0-9]*.[0-9]*.[0-9]*) printf '%s\n' "$found" ;;
        *) return 1 ;;
    esac
}

# The same source the bridges read: the module manifest beside them, which exists both in a repo checkout and in an installed package.
installed_version() { # <install dir>
    sed -n "s/.*ModuleVersion *= *'\([^']*\)'.*/\1/p" "$1/PSCompletions.psd1" 2>/dev/null | head -1
}

# --- what this needs -----------------------------------------------------------

# Everything the installer itself uses is checked *before* the download: a missing tool should cost one line, not a 12 MB download followed by an extraction failure.
# `require` collects the gaps so the user sees them all at once, the way a package manager would.
# It always succeeds — the caller reads `$missing` — because under `set -e` a failing helper would end the script silently, which is exactly the case this check exists for.
require() { # <what it is for> <command...>
    what="$1"
    shift
    for c in "$@"; do
        if command -v "$c" >/dev/null 2>&1; then return 0; fi
    done
    missing="$missing
  - $what"
}

preflight() {
    missing=""
    require "$(msg need_downloader)" curl wget
    require "$(msg need_unpacker)" unzip bsdtar tar python3 python
    require "$(msg need_python)" python3 python
    if [ -n "$missing" ]; then
        msg missing_list "$missing" >&2
        die "$(msg install_first)"
    fi
}

# --- installing ----------------------------------------------------------------

# The package is the module directory verbatim: the bridges, the PowerShell module files, the engine binaries under bin/<platform>-<arch>/, and the bundled psc completion.
# Only this platform's binaries are kept; the NuGet metadata is not part of the module.
prune() { # <staging dir> <platform> <arch>
    for d in "$1"/bin/*; do
        [ -d "$d" ] || continue
        [ "$(basename -- "$d")" = "$2-$3" ] || rm -rf "$d"
    done
    rm -rf "$1/_rels" "$1/package" "$1/[Content_Types].xml" "$1/PSCompletions.nuspec"
}

# Says *how* this copy was installed, for `psc --self-update`.
# The path already proves where it is; this proves what put it there, so a copy that only happens to sit at that path is never mistaken for one of ours.
write_marker() { # <dir> <version>
    cat >"$1/install.json" <<EOF
{"method":"install.sh","version":"$2","installed_at":$(date +%s)}
EOF
}

# Replace the install directory with the staging one.
# `mv` is a rename — atomic, and the staging dir is a sibling so it is the same filesystem.
# The old copy is moved aside first, never deleted in place: if the second move fails the first is undone, and a process still running from the old copy keeps its inodes on Unix.
swap() { # <staging dir> <install dir>
    old="$2.old.$$"
    if [ -e "$2" ]; then
        mv "$2" "$old" || die "$(msg move_aside "$2")"
        if ! mv "$1" "$2"; then
            mv "$old" "$2" || warn "$(msg prev_copy_at "$old")"
            die "$(msg move_into_place)"
        fi
        rm -rf "$old" 2>/dev/null || true
    else
        mv "$1" "$2" || die "$(msg move_into_place)"
    fi
}

usage_lines() { # <dir> <shell>
    case "$2" in
        bash)
            say "$(msg rc_bash)"
            say "source \"$1/PSCompletions.bash\""
            ;;
        zsh)
            say "$(msg rc_zsh)"
            say "source \"$1/PSCompletions.zsh\""
            ;;
        fish)
            say "$(msg rc_fish)"
            say "ln -sf \"$1/PSCompletions.fish\" \"${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/PSCompletions.fish\""
            ;;
    esac
}

print_usage() { # <dir>
    say ""
    say "$(msg shell_setup)"
    # The detected shell first; all three are printed because all three bridges are installed and `$SHELL` is only a guess.
    printed=""
    first=1
    for s in $preferred bash zsh fish; do
        case " $printed " in *" $s "*) continue ;; esac
        printed="$printed $s"
        if [ "$first" = 1 ]; then first=0; else say ""; fi
        usage_lines "$1" "$s"
    done
    say ""
    say "$(msg uninstall_title)"
    say "$(msg uninstall_hint "$1")"
    print_sponsors
}

# --- sponsors -------------------------------------------------------------------
# Printed at the end of every run, written out literally.
#
# One sponsor is three lines — `Name — description`, then the URL indented three spaces:
#   Example — one line description
#      https://example.com
#
# Keep it in step with `info.sponsors` in `completions/psc/language/<lang>.json`
sponsors_zh() {
    cat <<'EOF'
EOF
}

# Same shape, English.
sponsors_en() {
    cat <<'EOF'
EOF
}

print_sponsors() {
    say ""
    printf '%s\n' "────────────────────────"
    printf '[%s]\n' "$(msg sponsors_title)"
    if is_zh; then sponsors_zh; else sponsors_en; fi
    printf '%s: https://pscompletions.abgox.com/docs/sponsors\n' "$(msg sponsor_cta)"
}

# --- flow ----------------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)
            if is_zh; then
                sed -n '/^# --- help-zh ---$/,/^$/p' "$0" | sed '1d' | sed 's/^# \{0,1\}//'
            else
                sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            fi
            exit 0
            ;;
        *)
            die "$(msg unknown_arg "$1")"
            ;;
    esac
done

# `$SHELL` names the *login* shell — a session that switched to another one keeps it — so it only decides the order of the printed rc lines, never what is installed.
preferred="$(detect_shell)"

platform="$(detect_platform)"
arch="$(detect_arch)"
[ "$platform" = unknown ] && die "$(msg bad_platform "$(uname -s)")"
[ "$arch" = unknown ] && die "$(msg bad_arch "$(uname -m)")"
# Windows binaries carry an `.exe` extension, the way the bridges already resolve it: a git bash install reads and writes the same names.
ext=""
[ "$platform" = windows ] && ext=".exe"
preflight

dir="$(install_dir "$platform")"
stage="$dir.new.$$"
dl="$dir.dl.$$"
cleanup() { rm -rf "$dl" "$stage"; }
trap cleanup EXIT INT TERM
# Both scratch directories are siblings of the install directory: same filesystem (so the swap's rename is atomic) and no environment input deciding where they go.
mkdir -p "$(dirname -- "$dir")" "$dl"

# A re-run has one question — is this the latest package? — and the Gallery answers it without the package, so ask before downloading.
# The binary check stays here beside it: a copy whose engine is missing is not "already installed" however current its manifest is.
current="$(installed_version "$dir" 2>/dev/null || true)"
say "$(msg checking)"
latest="$(latest_version || true)"
[ -n "$latest" ] || die "$(msg no_latest)"
if [ -n "$latest" ] && [ "$latest" = "$current" ] && [ -x "$dir/bin/$platform-$arch/psc$ext" ]; then
    say "$(msg already_installed "$latest" "$dir")"
    print_usage "$dir"
    exit 0
fi

# A version change is announced as `current > latest` before anything downloads; a fresh install or a repair has no "from" side, and an unreadable probe has no "to" side, so both stay quiet.
if [ -n "$latest" ] && [ -n "$current" ] && [ "$latest" != "$current" ]; then
    say "$(msg updating "$current" "$latest")"
fi

say "$(msg downloading)"
pkg="$dl/package.nupkg"
# The CDN serves `<id>.<version>.nupkg` by name.
pkg_url="$PACKAGE_CDN/pscompletions.$latest.nupkg"
download "$pkg_url" "$pkg" || die "$(msg dl_failed "$pkg_url")"

# A 404 body or a captive-portal page is not a package; checking the zip magic before unpacking turns a confusing extraction error into one clear line.
[ "$(dd if="$pkg" bs=1 count=2 2>/dev/null)" = "PK" ] || die "$(msg not_zip)"

extract "$pkg" "$stage"
version="$(package_version "$stage")"
[ -n "$version" ] || die "$(msg no_version)"

# The bridges arrived in v8; an older package would install a directory that cannot work.
for s in bash zsh fish; do
    [ -f "$stage/PSCompletions.$s" ] || die "$(msg no_bridge "$version" "$s")"
done

prune "$stage" "$platform" "$arch"
write_marker "$stage" "$version"
chmod +x "$stage/bin/$platform-$arch/psc$ext" "$stage/bin/$platform-$arch/psc-menu$ext"

swap "$stage" "$dir"
rm -rf "$dl"

say "$(msg installed "$version" "$dir")"
print_usage "$dir"
