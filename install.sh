#!/bin/sh
# PSCompletions installer for bash / zsh / fish — no PowerShell involved.
#
# It downloads the module package from the PowerShell Gallery, unpacks it into a fixed install directory, and prints the one line to add to your shell's rc file.
# The data directory (settings and installed completions) belongs to the module and is never touched.
#
#   sh install.sh                 # installs, then prints the rc line for every shell
#
# The bridges are all installed either way; `$SHELL` only decides which rc line is printed first.
#
# The install directory is fixed and not configurable: the path itself is how `psc --self-update` recognises a copy installed by this script (see the README's install section).

set -eu

GALLERY_URL=https://www.powershellgallery.com/api/v2/package/PSCompletions

say() { printf '%s\n' "$*"; }
warn() { printf '[PSCompletions] %s\n' "$*" >&2; }
die() {
    printf '[PSCompletions] %s\n' "$*" >&2
    exit 1
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
# There is no version in the URL: it always resolves to the newest published package, which is what this script installs.
download() { # <url> <file>
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 2 -A "PSCompletions-install" -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        die "neither curl nor wget is available to download the package"
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
    die "cannot unpack the package: install unzip, bsdtar or python3"
}

package_version() { # <unpacked dir>
    sed -n 's:.*<version>\([^<]*\)</version>.*:\1:p' "$1/PSCompletions.nuspec" 2>/dev/null | head -1
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
    require "curl or wget (to download the package)" curl wget
    require "unzip, bsdtar, tar or python3 (to unpack the package)" unzip bsdtar tar python3 python
    require "python3 or python (the bridge needs it at runtime)" python3 python
    if [ -n "$missing" ]; then
        printf '[PSCompletions] these commands are missing:%s\n' "$missing" >&2
        die "install them first, then run this script again"
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
        mv "$2" "$old" || die "cannot move the existing $2 aside"
        if ! mv "$1" "$2"; then
            mv "$old" "$2" || warn "the previous copy is at $old"
            die "cannot move the new copy into place"
        fi
        rm -rf "$old" 2>/dev/null || true
    else
        mv "$1" "$2" || die "cannot move the new copy into place"
    fi
}

usage_lines() { # <dir> <shell>
    case "$2" in
        bash)
            say ""
            say "# bash — add this as the last line of ~/.bashrc:"
            say "source \"$1/PSCompletions.bash\""
            ;;
        zsh)
            say ""
            say "# zsh — add this as the last line of ~/.zshrc:"
            say "source \"$1/PSCompletions.zsh\""
            ;;
        fish)
            say ""
            say "# fish — link it into conf.d (or source it from config.fish):"
            say "ln -s \"$1/PSCompletions.fish\" \"${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/PSCompletions.fish\""
            ;;
    esac
}

print_usage() { # <dir>
    say ""
    say "[PSCompletions] installed in $1"
    # The detected shell first; all three are printed because all three bridges are installed and `$SHELL` is only a guess.
    printed=""
    for s in $preferred bash zsh fish; do
        case " $printed " in *" $s "*) continue ;; esac
        printed="$printed $s"
        usage_lines "$1" "$s"
    done
    say ""
    say "# start a new shell (or re-source the file) to pick it up"
    say "# to uninstall: rm -rf \"$1\" and delete the line you added to your rc file"
}

windows_notice() {
    warn "this installer is for bash, zsh and fish on Linux and macOS."
    warn "on Windows, install the module with PowerShell instead:"
    warn "  Install-Module PSCompletions        # or: Install-PSResource PSCompletions"
    warn "  scoop install pscompletions         # or: scoop install abyss/abgox.PSCompletions"
    exit 1
}

# --- flow ----------------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            die "unknown argument: $1 (see --help)"
            ;;
    esac
done

# `$SHELL` names the *login* shell — a session that switched to another one keeps it — so it only decides the order of the printed rc lines, never what is installed.
preferred="$(detect_shell)"

platform="$(detect_platform)"
arch="$(detect_arch)"
[ "$platform" = windows ] && windows_notice
[ "$platform" = unknown ] && die "unsupported platform: $(uname -s)"
[ "$arch" = unknown ] && die "unsupported architecture: $(uname -m)"
preflight

dir="$(install_dir "$platform")"
stage="$dir.new.$$"
dl="$dir.dl.$$"
cleanup() { rm -rf "$dl" "$stage"; }
trap cleanup EXIT INT TERM
# Both scratch directories are siblings of the install directory: same filesystem (so the swap's rename is atomic) and no environment input deciding where they go.
mkdir -p "$(dirname -- "$dir")" "$dl"

say "[PSCompletions] downloading the latest package..."
pkg="$dl/package.nupkg"
download "$GALLERY_URL" "$pkg" || die "cannot download the package from $GALLERY_URL"

# A 404 body or a captive-portal page is not a package; checking the zip magic before unpacking turns a confusing extraction error into one clear line.
[ "$(dd if="$pkg" bs=1 count=2 2>/dev/null)" = "PK" ] || die "the download is not a zip archive (a proxy or a captive portal may have intercepted it)"

extract "$pkg" "$stage"
version="$(package_version "$stage")"
[ -n "$version" ] || die "cannot read the package version (unexpected package layout)"

# The bridges arrived in v8; an older package would install a directory that cannot work.
for s in bash zsh fish; do
    [ -f "$stage/PSCompletions.$s" ] || die "package $version carries no $s bridge"
done

current="$(installed_version "$dir" 2>/dev/null || true)"
if [ "$current" = "$version" ] && [ -x "$dir/bin/$platform-$arch/psc" ]; then
    say "[PSCompletions] $version is already installed."
    print_usage "$dir"
    exit 0
fi

prune "$stage" "$platform" "$arch"
write_marker "$stage" "$version"
chmod +x "$stage/bin/$platform-$arch/psc" "$stage/bin/$platform-$arch/psc-menu"

swap "$stage" "$dir"
rm -rf "$dl"

say "[PSCompletions] installed $version"
print_usage "$dir"
