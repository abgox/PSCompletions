#!/usr/bin/env bash
# Focused tests for install.sh: the version probe (decides "already installed" *before* downloading)
# and the bilingual messages (the same run in Chinese and English).
# Everything the probe skips — download, extract, prune, swap — is exercised by a real install and is not repeated here;
# when the probe matches, none of it runs at all.
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

# The host's own platform/arch, the way install.sh derives them: the fake copy must sit where this machine would install it.
case "$(uname -s)" in
    Darwin*) platform=darwin ;;
    MINGW* | MSYS* | CYGWIN*) platform=windows ;;
    *) platform=linux ;;
esac
case "$(uname -m)" in
    aarch64 | arm64) arch=arm64 ;;
    *) arch=x64 ;;
esac

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# A scratch HOME holding a copy that looks installed: the manifest carries the version and the engine binary is executable,
# which is exactly the pair install.sh checks before it decides there is nothing to do.
plant() { # <version>
    dir="$scratch/home/.local/share/PSCompletions"
    rm -rf "$dir"
    mkdir -p "$dir/bin/$platform-$arch"
    printf "ModuleVersion = '%s'\n" "$1" >"$dir/PSCompletions.psd1"
    : >"$dir/bin/$platform-$arch/psc"
    chmod +x "$dir/bin/$platform-$arch/psc"
}

# A `curl` that answers the probe (recognised by `redirect_url`) with a CDN Location naming <version>, and records every call.
# The download copies $PSC_STUB_PACKAGE when set (a fake package the test builds); otherwise it fails, which is what lets
# these tests tell "did not download" from "did".
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
            printf 'https://cdn.example/packages/pscompletions.%s.nupkg\n' "$PSC_STUB_VERSION"
            exit 0
            ;;
    esac
    if [ "$prev" = "-o" ]; then out="$a"; fi
    prev="$a"
done
printf 'download\n' >>"$PSC_STUB_LOG"
if [ -n "${PSC_STUB_PACKAGE:-}" ] && [ -n "${out:-}" ]; then
    cp "$PSC_STUB_PACKAGE" "$out"
    exit 0
fi
exit 1
STUB
chmod +x "$stub/curl"

# Locale for the next run; the chain inside install.sh reads LC_ALL first, so one variable decides.
T_LC="C"

run_install() { # <version the probe reports> — prints the combined output, exit code in $?
    LC_ALL="$T_LC" LANGUAGE= LC_MESSAGES= LANG= \
        PATH="$stub:$PATH" HOME="$scratch/home" XDG_DATA_HOME= \
        PSC_STUB_VERSION="$1" PSC_STUB_LOG="$scratch/calls.log" PSC_STUB_PACKAGE="${PKG:-}" \
        sh "$INSTALL" 2>&1
}

# A Windows shell (git bash): uname answers MINGW64, so install.sh walks the windows branch.
win_stub="$scratch/wbin"
mkdir -p "$win_stub"
cat >"$win_stub/uname" <<'STUB'
#!/bin/sh
if [ "$1" = "-s" ]; then printf 'MINGW64_NT-10.0-19045\n'; else printf 'x86_64\n'; fi
STUB
chmod +x "$win_stub/uname"

# A scratch HOME holding a windows copy: psc.exe beside the manifest, the pair the -x check looks for there.
plant_win() { # <version>
    dir="$scratch/winhome/.local/share/PSCompletions"
    rm -rf "$dir"
    mkdir -p "$dir/bin/windows-x64"
    printf "ModuleVersion = '%s'\n" "$1" >"$dir/PSCompletions.psd1"
    : >"$dir/bin/windows-x64/psc.exe"
    chmod +x "$dir/bin/windows-x64/psc.exe"
}

run_win() { # <version the probe reports> — the same run under a Windows uname.
    LC_ALL="$T_LC" LANGUAGE= LC_MESSAGES= LANG= \
        PATH="$win_stub:$stub:$PATH" HOME="$scratch/winhome" XDG_DATA_HOME= \
        PSC_STUB_VERSION="$1" PSC_STUB_LOG="$scratch/wincalls.log" PSC_STUB_PACKAGE="${PKG:-}" \
        sh "$INSTALL" 2>&1
}

# A minimal package with the layout install.sh expects: the nuspec version, the three bridges,
# the manifest, and one foreign bin/ dir for prune to remove.
make_fake_pkg() { # <version> <file>
    python3 - "$1" "$2" <<'PYEOF'
import sys, zipfile
ver, path = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(path, "w") as z:
    z.writestr("PSCompletions.nuspec", f"<package><metadata><version>{ver}</version></metadata></package>")
    z.writestr("PSCompletions.psd1", f"ModuleVersion = '{ver}'\n")
    for s in ("bash", "zsh", "fish"):
        z.writestr(f"PSCompletions.{s}", "# stub bridge\n")
    z.writestr("bin/windows-x64/psc.exe", "")
    z.writestr("bin/windows-x64/psc-menu.exe", "")
    z.writestr("bin/linux-x64/psc", "")
PYEOF
}

# --- the probe matches: nothing to do, and nothing downloaded ---------------

plant 8.0.0
: >"$scratch/calls.log"
out="$(run_install 8.0.0)"
code=$?

if [ "$code" -eq 0 ]; then
    ok "an up-to-date copy exits 0"
else
    bad "an up-to-date copy must exit 0 (got $code)"
fi

case "$out" in
    *"8.0.0 is already installed."*) ok "it says the version it found" ;;
    *) bad "the already-installed line is missing: $out" ;;
esac

case "$out" in
    *"downloading the latest package"*) bad "it still announced a download" ;;
    *) ok "no download announcement" ;;
esac

if grep -q '^download$' "$scratch/calls.log"; then
    bad "the package was downloaded even though the probe matched"
else
    ok "the package was not downloaded"
fi

if [ "$(grep -c '^probe$' "$scratch/calls.log")" = 1 ]; then
    ok "the version was probed once"
else
    bad "expected exactly one probe call"
fi

# --- the probe reports a newer version: it must go on to download -----------

plant 8.0.0
: >"$scratch/calls.log"
out="$(run_install 8.0.1)"
code=$?

if [ "$code" -ne 0 ]; then
    ok "a newer version does not take the early exit"
else
    bad "a newer version must not report itself as installed"
fi

if grep -q '^download$' "$scratch/calls.log"; then
    ok "it went on to download"
else
    bad "a newer version must download the package"
fi

case "$out" in
    *"8.0.0 is already installed."*) bad "it claimed the old version was current" ;;
    *) ok "it did not claim the old version was current" ;;
esac

# --- the probe yields nothing: fall through to the download -----------------

plant 8.0.0
: >"$scratch/calls.log"
out="$(run_install "")"
code=$?

if [ "$code" -ne 0 ] && grep -q '^download$' "$scratch/calls.log"; then
    ok "an unreadable probe falls back to downloading"
else
    bad "an unreadable probe must not be mistaken for a match (exit $code)"
fi

# --- a broken copy is not "already installed" -------------------------------

plant 8.0.0
rm -f "$scratch/home/.local/share/PSCompletions/bin/$platform-$arch/psc"
: >"$scratch/calls.log"
out="$(run_install 8.0.0)"
code=$?

if [ "$code" -ne 0 ] && grep -q '^download$' "$scratch/calls.log"; then
    ok "a missing engine binary still triggers a reinstall"
else
    bad "a missing engine binary must not be reported as installed (exit $code)"
fi

# --- Chinese output: the same early exit in the other language ---------------

T_LC="zh_CN.UTF-8"
plant 8.0.0
: >"$scratch/calls.log"
out="$(run_install 8.0.0)"
code=$?

if [ "$code" -eq 0 ]; then
    ok "zh: an up-to-date copy exits 0"
else
    bad "zh: an up-to-date copy must exit 0 (got $code)"
fi

case "$out" in
    *"8.0.0 已安装。"*) ok "zh: it says the version it found" ;;
    *) bad "zh: the already-installed line is missing: $out" ;;
esac

case "$out" in
    *"把下面这行加到"*) ok "zh: the rc comment is translated" ;;
    *) bad "zh: the rc comment is not translated: $out" ;;
esac

case "$out" in
    *"已安装到"*) ok "zh: the installed-in line is translated" ;;
    *) bad "zh: the installed-in line is not translated: $out" ;;
esac

case "$out" in
    *"downloading the latest package"*) bad "zh: it still announced a download" ;;
    *) ok "zh: no download announcement" ;;
esac

if grep -q '^download$' "$scratch/calls.log"; then
    bad "zh: the package was downloaded even though the probe matched"
else
    ok "zh: the package was not downloaded"
fi
T_LC="C"

# --- a newer version still fails in Chinese when the download fails ---------

T_LC="zh_CN.UTF-8"
plant 8.0.0
: >"$scratch/calls.log"
out="$(run_install 8.0.1)"
code=$?

if [ "$code" -ne 0 ]; then
    ok "zh: a newer version does not take the early exit"
else
    bad "zh: a newer version must not report itself as installed"
fi

case "$out" in
    *"无法从"*) ok "zh: the download failure is translated" ;;
    *) bad "zh: the download failure is not translated: $out" ;;
esac
T_LC="C"

# --- --help and usage errors follow the locale (no network) -----------------

out="$(LC_ALL=zh_CN.UTF-8 LANGUAGE= LC_MESSAGES= LANG= sh "$INSTALL" --help 2>&1)"
case "$out" in
    *"安装脚本"* | *"rc 行"*) ok "zh: --help speaks Chinese" ;;
    *) bad "zh: --help is not translated: $out" ;;
esac

out="$(LC_ALL=C sh "$INSTALL" --help 2>&1)"
case "$out" in
    *"no PowerShell involved"*) ok "en: --help speaks English" ;;
    *) bad "en: --help is not English: $out" ;;
esac

out="$(LC_ALL=zh_CN.UTF-8 LANGUAGE= LC_MESSAGES= LANG= sh "$INSTALL" --bogus 2>&1)"
code=$?
if [ "$code" -ne 0 ]; then
    case "$out" in
        *"未知参数"*) ok "zh: the usage error is translated" ;;
        *) bad "zh: the usage error is not translated: $out" ;;
    esac
else
    bad "zh: a bogus argument must fail (got $code)"
fi

out="$(LC_ALL=C sh "$INSTALL" --bogus 2>&1)"
case "$out" in
    *"unknown argument"*) ok "en: the usage error is English" ;;
    *) bad "en: the usage error is not English: $out" ;;
esac

# LANGUAGE alone (GNU gettext priority) is enough for Chinese.
out="$(LC_ALL= LANGUAGE=zh_CN.UTF-8 LC_MESSAGES= LANG= sh "$INSTALL" --bogus 2>&1)"
case "$out" in
    *"未知参数"*) ok "LANGUAGE alone selects Chinese" ;;
    *) bad "LANGUAGE alone did not select Chinese: $out" ;;
esac

# --- Windows (git bash): the windows branch installs, enlightened by .exe ------
# The bridges already resolve MINGW as windows with an .exe suffix; install.sh walks the same branch instead of refusing.

plant_win 8.0.0
: >"$scratch/wincalls.log"
out="$(run_win 8.0.0)"
code=$?

if [ "$code" -eq 0 ]; then
    ok "win: an up-to-date exe exits 0"
else
    bad "win: an up-to-date exe must exit 0 (got $code): $out"
fi

case "$out" in
    *"8.0.0 is already installed."*) ok "win: it says the version it found" ;;
    *) bad "win: the already-installed line is missing: $out" ;;
esac

if grep -q '^download$' "$scratch/wincalls.log"; then
    bad "win: the package was downloaded even though the probe matched"
else
    ok "win: the package was not downloaded"
fi

# A full install from a fake package: download, unpack, prune the foreign arch, mark and swap.
make_fake_pkg 9.9.9 "$scratch/fake.nupkg"
rm -rf "$scratch/winhome"
: >"$scratch/wincalls.log"
PKG="$scratch/fake.nupkg"
out="$(run_win 9.9.9)"
code=$?
PKG=""

if [ "$code" -eq 0 ]; then
    ok "win: a fresh install exits 0"
else
    bad "win: a fresh install must exit 0 (got $code): $out"
fi

case "$out" in
    *"installed 9.9.9"*) ok "win: it reports the installed version" ;;
    *) bad "win: the installed line is missing: $out" ;;
esac

wdir="$scratch/winhome/.local/share/PSCompletions"
if [ -x "$wdir/bin/windows-x64/psc.exe" ] && [ -x "$wdir/bin/windows-x64/psc-menu.exe" ]; then
    ok "win: the engine binaries are executable"
else
    bad "win: the engine binaries are not executable"
fi

if [ ! -e "$wdir/bin/linux-x64" ]; then
    ok "win: prune kept only this platform"
else
    bad "win: prune left the foreign arch behind"
fi

if grep '"version":"9.9.9"' "$wdir/install.json" >/dev/null 2>&1; then
    ok "win: the marker records the version"
else
    bad "win: the marker is missing or wrong"
fi

if [ "$(grep -c '^download$' "$scratch/wincalls.log")" = 1 ]; then
    ok "win: the package was downloaded once"
else
    bad "win: expected exactly one download"
fi

# --- every key exists in both languages --------------------------------------

zh_keys=$(sed -n '/# --- zh ---/,/# --- end ---/p' "$INSTALL" | grep -oE '^[[:space:]]+[a-z_0-9]+\)' | tr -d ' )' | sort -u)
en_keys=$(sed -n '/# --- en ---/,/# --- end ---/p' "$INSTALL" | grep -oE '^[[:space:]]+[a-z_0-9]+\)' | tr -d ' )' | sort -u)

if [ "$zh_keys" = "$en_keys" ] && [ -n "$zh_keys" ]; then
    ok "every message key exists in both languages ($(printf '%s\n' "$zh_keys" | wc -l) keys)"
else
    bad "message keys differ between languages"
    printf 'zh-only:\n'; comm -23 <(printf '%s\n' "$zh_keys") <(printf '%s\n' "$en_keys")
    printf 'en-only:\n'; comm -13 <(printf '%s\n' "$zh_keys") <(printf '%s\n' "$en_keys")
fi

printf '\n'
if [ "$fail" -ne 0 ]; then
    printf 'INSTALL TESTS FAILED\n'
    exit 1
fi
printf 'all install tests passed\n'
