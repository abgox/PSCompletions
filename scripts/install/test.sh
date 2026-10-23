#!/usr/bin/env bash
# Tests for install.sh.
#
# The installer has one job — decide whether to install, then install atomically — and the checks are grouped the same way:
#   probe      what makes a re-run stop before downloading
#   install    download → unpack → prune → mark → swap, on this host's own platform
#   failures   every die() path, and the old copy surviving it
#   output     the report the user reads (usage lines, sponsor block, both languages)
#   windows    the git-bash branch, where the binaries carry .exe
#   messages   parity between the two languages
#
# Everything network-shaped is stubbed: `curl` answers the version probe and writes a fake package, so nothing here reaches the Gallery and nothing touches the real data directory.
#
# Usage: scripts/install/test.sh [root]
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(dirname -- "$(dirname -- "$HERE")")}"
INSTALL="$ROOT/install.sh"

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() {
    printf 'FAIL %s\n' "$1"
    fail=1
}

# --- assertions ---------------------------------------------------------------
# Each reads the last run's output ($OUT) or exit code ($CODE), so a case is one line.

has() { # <description> <needle>
    case "$OUT" in
        *"$2"*) ok "$1" ;;
        *) bad "$1 — missing \"$2\"" ;;
    esac
}
hasnt() { # <description> <needle>
    case "$OUT" in
        *"$2"*) bad "$1 — unexpected \"$2\"" ;;
        *) ok "$1" ;;
    esac
}
exits() { # <description> <code>
    if [ "$CODE" -eq "$2" ]; then
        ok "$1"
    else
        bad "$1 — exit $CODE, wanted $2"
    fi
}
file_is() { # <description> <path>
    if [ -e "$2" ]; then ok "$1"; else bad "$1 — $2 is missing"; fi
}
file_isnt() { # <description> <path>
    if [ -e "$2" ]; then bad "$1 — $2 still exists"; else ok "$1"; fi
}
executable_is() { # <description> <path>
    if [ -x "$2" ]; then ok "$1"; else bad "$1 — $2 is missing or not executable"; fi
}
contains_file() { # <description> <path> <text>
    if grep -q -- "$3" "$2" 2>/dev/null; then ok "$1"; else bad "$1 — \"$3\" not in $2"; fi
}

# --- the host this runs on -----------------------------------------------------
# install.sh derives these from uname; the fake copies below must sit where the host would put them, or every probe test would be answering a different question.
case "$(uname -s)" in
    Darwin*) platform=darwin ;;
    MINGW* | MSYS* | CYGWIN*) platform=windows ;;
    *) platform=linux ;;
esac
case "$(uname -m)" in
    aarch64 | arm64) arch=arm64 ;;
    *) arch=x64 ;;
esac
ext=""
[ "$platform" = windows ] && ext=".exe"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

home="$scratch/home"
dir="$home/.local/share/PSCompletions"

# A copy that looks installed: the manifest carries the version and the engine binary is executable — the exact pair the probe checks.
plant() { # <version>
    rm -rf "$dir"
    mkdir -p "$dir/bin/$platform-$arch"
    printf "ModuleVersion = '%s'\n" "$1" >"$dir/PSCompletions.psd1"
    : >"$dir/bin/$platform-$arch/psc$ext"
    chmod +x "$dir/bin/$platform-$arch/psc$ext"
}

# --- the stubbed network -------------------------------------------------------
# One `curl` stands in for both calls install.sh makes — the probe (recognised by `redirect_url`) prints a CDN Location naming $PSC_STUB_VERSION, and the download copies $PSC_STUB_PACKAGE, or writes $PSC_STUB_BODY, or fails.
stub="$scratch/bin"
mkdir -p "$stub"
cat >"$stub/curl" <<'STUB'
#!/bin/sh
prev=""
for a in "$@"; do
    case "$a" in
        *redirect_url*)
            printf 'probe\n' >>"$PSC_STUB_LOG"
            [ -n "$PSC_STUB_VERSION" ] || exit 0
            # The real endpoint answers the unversioned page with a redirect to the versioned one.
            printf 'https://www.powershellgallery.com/packages/PSCompletions/%s\n' "$PSC_STUB_VERSION"
            exit 0
            ;;
    esac
    if [ "$prev" = "-o" ]; then out="$a"; fi
    prev="$a"
done
printf 'download\n' >>"$PSC_STUB_LOG"
if [ -n "${PSC_STUB_BODY:-}" ] && [ -n "${out:-}" ]; then
    printf '%s' "$PSC_STUB_BODY" >"$out"
    exit 0
fi
if [ -n "${PSC_STUB_PACKAGE:-}" ] && [ -n "${out:-}" ]; then
    cp "$PSC_STUB_PACKAGE" "$out"
    exit 0
fi
exit 1
STUB
chmod +x "$stub/curl"

# A Windows shell: uname answers MINGW64, so install.sh walks the windows branch.
win_stub="$scratch/wbin"
mkdir -p "$win_stub"
cat >"$win_stub/uname" <<'STUB'
#!/bin/sh
if [ "$1" = "-s" ]; then printf 'MINGW64_NT-10.0-19045\n'; else printf 'x86_64\n'; fi
STUB
chmod +x "$win_stub/uname"

# Locale for the next run: install.sh reads LC_ALL first, so one variable decides.
T_LC="C"
PKG=""
BODY=""
SHELL_OVERRIDE=""
# Absolute: the preflight case below runs with a PATH that deliberately lacks `sh`.
SH_BIN="$(command -v sh)"

run_install() { # <version the probe reports>
    OUT="$(
        LC_ALL="$T_LC" LANGUAGE= LC_MESSAGES= LANG= \
            PATH="$stub:$PATH" HOME="$home" XDG_DATA_HOME= \
            PSC_STUB_VERSION="$1" PSC_STUB_LOG="$scratch/calls.log" \
            PSC_STUB_PACKAGE="$PKG" PSC_STUB_BODY="$BODY" \
            SHELL="${SHELL_OVERRIDE:-/bin/bash}" \
            "$SH_BIN" "$INSTALL" 2>&1
    )"
    CODE=$?
}

win_home="$scratch/winhome"
win_dir="$win_home/.local/share/PSCompletions"
plant_win() { # <version>
    rm -rf "$win_dir"
    mkdir -p "$win_dir/bin/windows-x64"
    printf "ModuleVersion = '%s'\n" "$1" >"$win_dir/PSCompletions.psd1"
    : >"$win_dir/bin/windows-x64/psc.exe"
    chmod +x "$win_dir/bin/windows-x64/psc.exe"
}

run_win() { # <version the probe reports>
    OUT="$(
        LC_ALL="$T_LC" LANGUAGE= LC_MESSAGES= LANG= \
            PATH="$win_stub:$stub:$PATH" HOME="$win_home" XDG_DATA_HOME= \
            PSC_STUB_VERSION="$1" PSC_STUB_LOG="$scratch/wincalls.log" \
            PSC_STUB_PACKAGE="$PKG" PSC_STUB_BODY="$BODY" \
            SHELL="/bin/bash" \
            "$SH_BIN" "$INSTALL" 2>&1
    )"
    CODE=$?
}

# A package with the layout install.sh expects: the nuspec version, the three bridges, the manifest, and one bin/ dir per platform so prune has something foreign to remove.
# `<file>` is written by python3 because a zip is not something a shell script can build.
make_pkg() { # <version> <file> [omit-bridge]
    python3 - "$1" "$2" "${3:-}" <<'PYEOF'
import sys, zipfile
ver, path, omit = sys.argv[1], sys.argv[2], sys.argv[3]
with zipfile.ZipFile(path, "w") as z:
    z.writestr("PSCompletions.nuspec", f"<package><metadata><version>{ver}</version></metadata></package>")
    z.writestr("PSCompletions.psd1", f"ModuleVersion = '{ver}'\n")
    for s in ("bash", "zsh", "fish"):
        if s != omit:
            z.writestr(f"PSCompletions.{s}", "# stub bridge\n")
    z.writestr("_rels/.rels", "<Relationships/>")
    z.writestr("[Content_Types].xml", "<Types/>")
    for plat, a in (("linux", "x64"), ("windows", "x64"), ("darwin", "arm64")):
        suffix = ".exe" if plat == "windows" else ""
        z.writestr(f"bin/{plat}-{a}/psc{suffix}", "")
        z.writestr(f"bin/{plat}-{a}/psc-menu{suffix}", "")
PYEOF
}

# ------------------------------------------------------------------------------
# probe: a re-run stops before downloading
# ------------------------------------------------------------------------------

plant 8.0.0
: >"$scratch/calls.log"
run_install 8.0.0
exits "an up-to-date copy exits 0" 0
has "it names the version and path" "The latest version (8.0.0) is already installed at $dir"
hasnt "the status line carries no program tag" "[PSCompletions] checking"
hasnt "it does not announce a download" "Downloading the latest package"
if grep -q '^download$' "$scratch/calls.log"; then
    bad "the package was downloaded even though the probe matched"
else
    ok "nothing was downloaded"
fi
if [ "$(grep -c '^probe$' "$scratch/calls.log")" = 1 ]; then
    ok "the version was probed exactly once"
else
    bad "expected exactly one probe call, got $(grep -c '^probe$' "$scratch/calls.log")"
fi

# A newer version: announce the change, then download.
plant 8.0.0
: >"$scratch/calls.log"
run_install 8.0.1
if grep -q '^download$' "$scratch/calls.log"; then
    ok "a newer version goes on to download"
else
    bad "a newer version must download the package"
fi
has "it announces the version change" "Updating 8.0.0 > 8.0.1"
hasnt "it does not claim the old version is current" "The latest version (8.0.0) is already installed"

# No copy at all: nothing to announce, still downloads.
rm -rf "$home"
: >"$scratch/calls.log"
run_install 8.0.1
hasnt "a fresh install announces no version change" "updating "
if grep -q '^download$' "$scratch/calls.log"; then
    ok "a fresh install downloads"
else
    bad "a fresh install must download"
fi

# Same version but a missing engine: a repair, not an up-to-date copy, and not a change.
plant 8.0.0
rm -f "$dir/bin/$platform-$arch/psc$ext"
: >"$scratch/calls.log"
run_install 8.0.0
hasnt "a repair does not claim to be up to date" "already installed"
hasnt "a repair announces no version change" "8.0.0 > 8.0.0"
if grep -q '^download$' "$scratch/calls.log"; then
    ok "a repair downloads again"
else
    bad "a missing engine must trigger a download"
fi

# An unreadable probe (no Location, a mirror, offline): there is no version to build the CDN URL from, so the run stops with a message instead of guessing a package.
plant 8.0.0
: >"$scratch/calls.log"
run_install ""
exits "an unreadable probe exits non-zero" 1
has "it says the latest version could not be read" "cannot read the latest version"
# `die` adds the prefix itself, so a message that carries one too prints it twice.
prefixes="$(printf '%s\n' "$OUT" | grep 'cannot read' | grep -o '\[PSCompletions\]' | wc -l | tr -d ' ')"
if [ "$prefixes" = "1" ]; then
    ok "the failure line carries the prefix once"
else
    bad "the failure line carries the prefix $prefixes time(s)"
fi
if grep -q '^download$' "$scratch/calls.log"; then
    bad "an unreadable probe still tried to download"
else
    ok "an unreadable probe downloads nothing"
fi
hasnt "an unreadable probe announces no version change" "updating "

# ------------------------------------------------------------------------------
# install: the whole flow, on this host's platform
# ------------------------------------------------------------------------------

make_pkg 9.9.9 "$scratch/fake.nupkg"
rm -rf "$home"
: >"$scratch/calls.log"
PKG="$scratch/fake.nupkg"
run_install 9.9.9
PKG=""

exits "a fresh install exits 0" 0
has "it reports the installed version" "Installed 9.9.9 at $dir"
file_is "the bridges are installed" "$dir/PSCompletions.bash"
file_is "the manifest is installed" "$dir/PSCompletions.psd1"
executable_is "the engine binary is executable" "$dir/bin/$platform-$arch/psc$ext"
executable_is "the menu binary is executable" "$dir/bin/$platform-$arch/psc-menu$ext"
file_is "the install marker is written" "$dir/install.json"
contains_file "the marker records the method" "$dir/install.json" '"method":"install.sh"'
contains_file "the marker records the version" "$dir/install.json" '"version":"9.9.9"'

# prune: this platform stays, every other one goes, and the NuGet scaffolding is not part of the module.
for foreign in linux-x64 windows-x64 darwin-arm64; do
    if [ "$foreign" = "$platform-$arch" ]; then continue; fi
    file_isnt "prune removed bin/$foreign" "$dir/bin/$foreign"
done
file_isnt "prune removed the nuspec" "$dir/PSCompletions.nuspec"
file_isnt "prune removed _rels" "$dir/_rels"
file_isnt "prune removed [Content_Types].xml" "$dir/[Content_Types].xml"

# The scratch directories are siblings of the install dir; both must be gone.
leftovers="$(find "$(dirname "$dir")" -maxdepth 1 \( -name 'PSCompletions.dl.*' -o -name 'PSCompletions.new.*' \) 2>/dev/null)"
if [ -z "$leftovers" ]; then
    ok "the download and staging dirs are cleaned up"
else
    bad "scratch directories were left behind: $leftovers"
fi

if [ "$(grep -c '^download$' "$scratch/calls.log")" = 1 ]; then
    ok "the package was downloaded once"
else
    bad "expected exactly one download"
fi

# Installing over an existing copy: the old one is replaced, not merged, and its `.old.<pid>` sibling does not survive.
plant 8.0.0
printf 'stale\n' >"$dir/PSCompletions.zsh"
: >"$scratch/calls.log"
PKG="$scratch/fake.nupkg"
run_install 9.9.9
PKG=""
exits "installing over a copy exits 0" 0
contains_file "the manifest carries the new version" "$dir/PSCompletions.psd1" "ModuleVersion = '9.9.9'"
if [ "$(cat "$dir/PSCompletions.zsh")" = "stale" ]; then
    bad "the old copy was merged into the new one instead of replaced"
else
    ok "the old copy was replaced, not merged"
fi
old_leftover="$(find "$(dirname "$dir")" -maxdepth 1 -name 'PSCompletions.old.*' 2>/dev/null)"
if [ -z "$old_leftover" ]; then
    ok "the moved-aside copy is removed"
else
    bad "the moved-aside copy was left behind: $old_leftover"
fi

# ------------------------------------------------------------------------------
# failures: each die() path, and the previous copy surviving it
# ------------------------------------------------------------------------------

# The download itself fails.
plant 8.0.0
run_install 8.0.1
exits "a failed download exits non-zero" 1
has "it names the URL it could not fetch" "cannot download the package from"
contains_file "the previous copy is untouched" "$dir/PSCompletions.psd1" "ModuleVersion = '8.0.0'"

# The download succeeds but the body is not a package (a 404 page, a captive portal).
plant 8.0.0
BODY="<html>not a zip</html>"
run_install 8.0.1
BODY=""
exits "a non-zip body exits non-zero" 1
has "it says the download is not a zip" "not a zip archive"
contains_file "a non-zip body leaves the previous copy alone" "$dir/PSCompletions.psd1" "ModuleVersion = '8.0.0'"

# A package without a readable version.
make_pkg "" "$scratch/nover.nupkg"
PKG="$scratch/nover.nupkg"
run_install 8.0.1
PKG=""
exits "a package without a version exits non-zero" 1
has "it says the version could not be read" "cannot read the package version"

# A package missing one of the bridges install.sh needs.
make_pkg 9.9.9 "$scratch/nobridge.nupkg" zsh
PKG="$scratch/nobridge.nupkg"
run_install 8.0.1
PKG=""
exits "a package without a bridge exits non-zero" 1
has "it names the bridge that is missing" "carries no zsh bridge"

# Nothing to download with: preflight reports it before the download, and before any change to the install directory.
minbin="$scratch/minbin"
mkdir -p "$minbin"
for tool in basename uname sed; do
    ln -sf "$(command -v "$tool")" "$minbin/$tool"
done
plant 8.0.0
OUT="$(
    LC_ALL=C LANGUAGE= LC_MESSAGES= LANG= PATH="$minbin" HOME="$home" XDG_DATA_HOME= \
        "$SH_BIN" "$INSTALL" 2>&1
)"
CODE=$?
exits "a host without a downloader exits non-zero" 1
has "it lists what is missing" "these commands are missing"
has "it asks for them before the download" "install them first"
hasnt "it never announced a download" "Downloading the latest package"
contains_file "a failed preflight leaves the previous copy alone" "$dir/PSCompletions.psd1" "ModuleVersion = '8.0.0'"

# ------------------------------------------------------------------------------
# output: the report the user reads
# ------------------------------------------------------------------------------

# Usage lines: all three bridges, and the login shell's line first.
plant 8.0.0
SHELL_OVERRIDE=/bin/zsh run_install 8.0.0
if printf '%s\n' "$OUT" | grep -q 'zsh'; then
    ok "the usage lines name zsh"
else
    bad "the zsh rc line is missing"
fi
shells=0
for s in bash zsh fish; do
    if printf '%s\n' "$OUT" | grep -q "PSCompletions\.$s"; then shells=$((shells + 1)); fi
done
if [ "$shells" -eq 3 ]; then
    ok "the usage lines list every bridge"
else
    bad "only $shells of 3 bridges are listed"
fi
zsh_line="$(printf '%s\n' "$OUT" | grep -n 'zsh' | head -1 | cut -d: -f1)"
bash_line="$(printf '%s\n' "$OUT" | grep -n 'bash' | head -1 | cut -d: -f1)"
if [ -n "$zsh_line" ] && [ -n "$bash_line" ] && [ "$zsh_line" -lt "$bash_line" ]; then
    ok "the login shell's line comes first"
else
    bad "the login shell's line is not first (zsh=$zsh_line bash=$bash_line)"
fi

# The sponsor block closes the report: after the actionable lines, once, and last.
plant 8.0.0
SHELL_OVERRIDE=/bin/bash run_install 8.0.0
has "the sponsor block is printed" "────"
has "the block carries the call to action" "Become a sponsor: https://pscompletions.abgox.com/docs/sponsors"
hint_line="$(printf '%s\n' "$OUT" | grep -n 'rm -rf' | head -1 | cut -d: -f1)"
rule_line="$(printf '%s\n' "$OUT" | grep -n '────' | head -1 | cut -d: -f1)"
if [ -n "$hint_line" ] && [ -n "$rule_line" ] && [ "$hint_line" -lt "$rule_line" ]; then
    ok "the block follows the usage lines"
else
    bad "the block is not last (hint=$hint_line rule=$rule_line)"
fi
last_line="$(printf '%s\n' "$OUT" | sed '/^[[:space:]]*$/d' | tail -1)"
case "$last_line" in
    *"https://pscompletions.abgox.com/docs/sponsors") ok "the block is the last line of output" ;;
    *) bad "something prints after the sponsor block: $last_line" ;;
esac
blocks="$(printf '%s\n' "$OUT" | grep -c 'Become a sponsor')"
if [ "$blocks" -eq 1 ]; then
    ok "the block prints once"
else
    bad "expected exactly one sponsor block, got $blocks"
fi

# A fresh install ends with the block too, not only the early exit.
rm -rf "$home"
PKG="$scratch/fake.nupkg"
run_install 9.9.9
PKG=""
has "a fresh install also ends with the block" "Become a sponsor: https://pscompletions.abgox.com/docs/sponsors"

# Chinese: the same report, translated.
T_LC="zh_CN.UTF-8"
plant 8.0.0
run_install 8.0.0
has "zh: the installed line is translated" "最新版本（8.0.0）已安装在 $dir"
hasnt "zh: the path is not a separate line" "路径: "
has "zh: the rc comment is translated" "把下面这行加到"
has "zh: the sponsor block is translated" "[赞助商]"
has "zh: the call to action is translated" "成为赞助商: https://pscompletions.abgox.com/docs/sponsors"
hasnt "zh: it does not announce a download" "正在下载"
T_LC="C"

# ------------------------------------------------------------------------------
# windows: git bash, where the binaries carry .exe
# ------------------------------------------------------------------------------

plant_win 8.0.0
: >"$scratch/wincalls.log"
run_win 8.0.0
exits "win: an up-to-date exe exits 0" 0
has "win: it names the version and path" "The latest version (8.0.0) is already installed at $win_dir"
if grep -q '^download$' "$scratch/wincalls.log"; then
    bad "win: the package was downloaded even though the probe matched"
else
    ok "win: nothing was downloaded"
fi

rm -rf "$win_home"
: >"$scratch/wincalls.log"
PKG="$scratch/fake.nupkg"
run_win 9.9.9
PKG=""
exits "win: a fresh install exits 0" 0
has "win: it reports the installed version" "Installed 9.9.9 at $win_dir"
executable_is "win: the engine binary is executable" "$win_dir/bin/windows-x64/psc.exe"
executable_is "win: the menu binary is executable" "$win_dir/bin/windows-x64/psc-menu.exe"
file_isnt "win: prune removed the foreign arch" "$win_dir/bin/linux-x64"
contains_file "win: the marker records the version" "$win_dir/install.json" '"version":"9.9.9"'
if [ "$(grep -c '^download$' "$scratch/wincalls.log")" = 1 ]; then
    ok "win: the package was downloaded once"
else
    bad "win: expected exactly one download"
fi

# ------------------------------------------------------------------------------
# --help and usage errors follow the locale (no network)
# ------------------------------------------------------------------------------

OUT="$(LC_ALL=zh_CN.UTF-8 LANGUAGE= LC_MESSAGES= LANG= sh "$INSTALL" --help 2>&1)"
CODE=$?
exits "zh: --help exits 0" 0
has "zh: --help speaks Chinese" "安装脚本"

OUT="$(LC_ALL=C sh "$INSTALL" --help 2>&1)"
CODE=$?
exits "en: --help exits 0" 0
has "en: --help speaks English" "no PowerShell involved"

OUT="$(LC_ALL=zh_CN.UTF-8 LANGUAGE= LC_MESSAGES= LANG= sh "$INSTALL" --bogus 2>&1)"
CODE=$?
exits "zh: an unknown argument exits non-zero" 1
has "zh: the usage error is translated" "未知参数"

OUT="$(LC_ALL=C sh "$INSTALL" --bogus 2>&1)"
CODE=$?
has "en: the usage error is English" "unknown argument"

# LANGUAGE alone (GNU gettext priority) selects the language too.
OUT="$(LC_ALL= LANGUAGE=zh_CN.UTF-8 LC_MESSAGES= LANG= sh "$INSTALL" --bogus 2>&1)"
CODE=$?
has "LANGUAGE alone selects Chinese" "未知参数"

# ------------------------------------------------------------------------------
# messages: every key exists in both languages
# ------------------------------------------------------------------------------

zh_keys="$(sed -n '/# --- zh ---/,/# --- end ---/p' "$INSTALL" | grep -oE '^[[:space:]]+[a-z_0-9]+\)' | tr -d ' )' | sort -u)"
en_keys="$(sed -n '/# --- en ---/,/# --- end ---/p' "$INSTALL" | grep -oE '^[[:space:]]+[a-z_0-9]+\)' | tr -d ' )' | sort -u)"

if [ "$zh_keys" = "$en_keys" ] && [ -n "$zh_keys" ]; then
    ok "every message key exists in both languages ($(printf '%s\n' "$zh_keys" | wc -l | tr -d ' ') keys)"
else
    bad "message keys differ between languages"
    printf 'zh-only:\n'
    comm -23 <(printf '%s\n' "$zh_keys") <(printf '%s\n' "$en_keys")
    printf 'en-only:\n'
    comm -13 <(printf '%s\n' "$zh_keys") <(printf '%s\n' "$en_keys")
fi

printf '\n'
if [ "$fail" -ne 0 ]; then
    printf 'INSTALL TESTS FAILED\n'
    exit 1
fi
printf 'all install tests passed\n'
