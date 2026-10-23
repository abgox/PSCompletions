#!/usr/bin/env bash
# PSCompletions bash bridge.
# User setup is one line in ~/.bashrc (`<module>` = the PSCompletions module dir):
#   source <module>/PSCompletions.bash
# Requires: 
#   - bash 5.0+ (associative arrays, mapfile, coproc, $EPOCHREALTIME)
#   - Python 3.8+ on PATH (`python3`/`python`; the version is asserted either way).
# Binaries resolve next to this script (module/PSCompletions/bin/<platform>-<arch>, shipped in the module package), next to this file.
# Missing dependencies print one clear error on load.
#
#   PSCOMPLETIONS_DATA_DIR  override the data dir

# Guard: refuse to load when sourced by the wrong shell.
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[PSCompletions] PSCompletions.bash is the bash bridge; source the bridge matching your shell instead (PSCompletions.<shell>)." >&2
    return 0
fi

[[ -n "${_PSC_LOADED:-}" ]] && return 0
_PSC_LOADED=1

# --- dependency check (loud once, on load) -----------------------------------
_PSC_DEPS_OK=1
if (( BASH_VERSINFO[0] < 5 )); then
    echo "[PSCompletions] bash 5.0+ required (found $BASH_VERSION)." >&2
    echo "[PSCompletions] macOS ships bash 3.2; install a modern bash (e.g. brew install bash) and use it." >&2
    _PSC_DEPS_OK=0
fi

# One clear message when the interpreter is unusable, instead of "command not found".
_PSC_PY_WARNED=0
_psc_need_py() {
    [[ -n "${_PSC_PY:-}" ]] && return 0
    if (( ! _PSC_PY_WARNED )); then
        echo "[PSCompletions] python 3.8+ unavailable; the bridge is disabled this session." >&2
        _PSC_PY_WARNED=1
    fi
    return 1
}
# `python3` on Linux, `python` on Windows (and guarded against Python 2).
# Cache the *absolute path*, not the bare name: a later PATH change (a prompt framework, mise/brew shellenv ordering, …) then cannot break the bridge.
_PSC_PY=""
for _py in python3 python; do
    _py_path="$(command -v "$_py" 2>/dev/null)" || continue
    _py_ver="$("$_py_path" --version 2>&1)" || continue
    if [[ "$_py_ver" =~ ([0-9]+)\.([0-9]+) ]] && (( BASH_REMATCH[1] > 3 || (BASH_REMATCH[1] == 3 && BASH_REMATCH[2] >= 8) )); then
        _PSC_PY="$_py_path"
        break
    fi
done
unset _py _py_path _py_ver
# Every python stdout passes through here.
# A Windows-native interpreter writes CRLF even to pipes, and the bridge only speaks LF: a stray CR broke arithmetic once (`${texts[$idx]}` with `idx="2\r"`) and silently corrupts paths elsewhere.
# The exit code is preserved, so `|| return` checks keep working.
_psc_py() {
    "$_PSC_PY" "$@" | tr -d '\r'
    return "${PIPESTATUS[0]}"
}
if [[ -z "$_PSC_PY" ]]; then
    echo "[PSCompletions] python 3.8+ not found on PATH at shell start; the bridge cannot run." >&2
    echo "[PSCompletions] install python3 (or make it available before sourcing this file)." >&2
    _PSC_DEPS_OK=0
fi

# --- locations ---------------------------------------------------------------
# Follow symlinks: incl.
# a `.bashrc.d`-style drop-in or a plugin dir, where the sourced path is the link and the binaries and the bundled psc completion sit next to the real file.
# No `readlink -f` — absent from macOS's BSD userland.
_psc_resolve_link() {
    local target="$1" dir resolved
    while [[ -L "$target" ]]; do
        dir="${target%/*}"
        [[ -z "$dir" ]] && dir=/
        [[ "$dir" == "$target" ]] && dir=.
        target="$(readlink -- "$target")"
        [[ "$target" == /* ]] || target="$dir/$target"
    done
    dir="${target%/*}"
    [[ -z "$dir" ]] && dir=/
    [[ "$dir" == "$target" ]] && dir=.
    resolved="$(cd -P -- "$dir" && pwd)"
    printf '%s/%s' "${resolved%/}" "${target##*/}"
}
_psc_bridge_dir="$(_psc_resolve_link "${BASH_SOURCE[0]}")"
_psc_bridge_dir="${_psc_bridge_dir%/*}"
_psc_arch="${HOSTTYPE:-$(uname -m)}"
case "$_psc_arch" in
    x86_64|amd64) _psc_arch=x64 ;;
    aarch64|arm64) _psc_arch=arm64 ;;
esac
case "${OSTYPE:-$(uname -s)}" in
    linux*) _psc_platform=linux ;;
    darwin*) _psc_platform=darwin ;;
    msys*|cygwin*|mingw*|win32*) _psc_platform=windows ;;  # Git Bash
    *) _psc_platform=linux ;;
esac
_psc_ext=""
[[ "$_psc_platform" == windows ]] && _psc_ext=".exe"
_PSC_BIN_DIR="$_psc_bridge_dir/bin/$_psc_platform-$_psc_arch"
# Default data dir mirrors the PowerShell module's per-platform default, so the shell bridge and the module share one data dir (completions, settings, index).
_psc_default_data_dir() {
    case "$_psc_platform" in
        darwin) printf '%s' "$HOME/Library/Application Support/com.abgox/PSCompletions" ;;
        windows) printf '%s' "${APPDATA:-$HOME/AppData/Roaming}/com.abgox/PSCompletions" ;;
        *) printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/com.abgox/PSCompletions" ;;
    esac
}
: "${PSCOMPLETIONS_DATA_DIR:=$(_psc_default_data_dir)}"
_PSC_MENU="$_PSC_BIN_DIR/psc-menu$_psc_ext"
_PSC_BIN="$_PSC_BIN_DIR/psc$_psc_ext"

# Guard: this is a library, not a program.
# `bash PSCompletions.bash` would define the functions in a throwaway child and change nothing, so say so (with the path to actually use) instead of failing silently.
# Sourced files report a different BASH_SOURCE[0] and skip this.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "[PSCompletions] PSCompletions.bash is a library, not a program. Add this to ~/.bashrc:" >&2
    echo "[PSCompletions]     source \"$_psc_bridge_dir/PSCompletions.bash\"" >&2
    exit 1
fi

# Engine-facing platform for `terminal.platform`: never `windows` from bash (the bridge cannot do the Windows console-buffer save/restore the engine expects there), so Git Bash uses the alternate screen like the other Unix hosts.
_psc_engine_platform=linux
[[ "$_psc_platform" == darwin ]] && _psc_engine_platform=macos
# `grep -P` capability, probed once (BSD grep on macOS lacks it).
_PSC_GREP_P=0
grep -oP '' <<< '' >/dev/null 2>&1 && _PSC_GREP_P=1

declare -gA _PSC_ALIAS=()   # trigger word -> completion
declare -gA _PSC_CFG=()     # flat module config
declare -gA _PSC_LANGCACHE=()
# Terminal modes the menu turns on through crossterm (EnableMouseCapture, EnterAlternateScreen, cursor::Hide, bracketed paste).
# A clean exit turns them off itself; a force-killed menu cannot, so the watchdog writes this itself — without the mouse modes the terminal keeps reporting `ESC [ < b;x;y M` as literal input and the shell becomes unusable.
_PSC_RESET_TERM=$'\e[?1006l\e[?1003l\e[?1002l\e[?1000l\e[?1015l\e[?1049l\e[?25h\e[?2004l'

# The terminal queues mouse reports (SGR `ESC [ < b;x;y M`) while the menu is up; the few bytes still in the tty input buffer when a force-killed menu dies are read by the shell as literal input.
# Discard them after restoring the modes — the menu owed the user a clean line.
_psc_flush_tty() {
    _psc_py -S -c 'import os,termios
try:
    fd=os.open("/dev/tty",os.O_RDONLY|os.O_NONBLOCK)
    termios.tcflush(fd,termios.TCIFLUSH)
    os.close(fd)
except Exception:
    pass' 2>/dev/null
}
declare -gA _PSC_HOOKS=()   # cmd -> 0/1 hooks gate (cleared when config/state changes)
_PSC_INIT_OK=0
_PSC_BIN_WARNED=0

# --- seed the bundled psc completion (offline first run) ----------------------
# A fresh machine (never imported the PowerShell module) has no psc completion; `psc init` would fetch it over the network.
# Seed the bundled copy first so a first run works offline.
# Mirrors the PowerShell bridge's migration seed.
_psc_seed_psc() {
    local target="$PSCOMPLETIONS_DATA_DIR/completions/psc"
    [[ -f "$target/config.json" && -f "$target/language/en-US.json" ]] && return 0
    local cand
    for cand in "$_psc_bridge_dir/completions/psc" "$_psc_bridge_dir/../../completions/psc"; do
        if [[ -f "$cand/config.json" && -f "$cand/language/en-US.json" ]]; then
            mkdir -p "$(dirname "$target")"
            rm -rf "$target"
            cp -r "$cand" "$target"
            return 0
        fi
    done
    return 1
}

# --- init (lazy, first Tab) ---------------------------------------------------
# Fill the alias/config caches from `psc init --flat`: NUL-delimited A/C records (design/psc-cli.md §6.10).
_psc_read_flat() {
    local kind k v
    while IFS= read -r -d '' kind && IFS= read -r -d '' k && IFS= read -r -d '' v; do
        if [[ "$kind" == A ]]; then _PSC_ALIAS["$k"]="$v"; else _PSC_CFG["$k"]="$v"; fi
    done < "$1"
}

_psc_init() {
    (( _PSC_DEPS_OK )) || return 1
    (( _PSC_INIT_OK )) && return 0
    # (Re)building state: drop all derived caches so a change invalidates them.
    _PSC_ALIAS=(); _PSC_CFG=(); _PSC_LANGCACHE=(); _PSC_HOOKS=()
    if [[ ! -x "$_PSC_MENU" || ! -x "$_PSC_BIN" ]]; then
        # nupkg packaging drops the exec bit on Unix; re-apply if the files exist.
        if [[ -f "$_PSC_MENU" && -f "$_PSC_BIN" ]]; then
            chmod +x "$_PSC_MENU" "$_PSC_BIN" 2>/dev/null
        fi
        if [[ ! -x "$_PSC_MENU" || ! -x "$_PSC_BIN" ]]; then
            if (( ! _PSC_BIN_WARNED )); then
                echo "[PSCompletions] binaries missing under $_PSC_BIN_DIR (want psc + psc-menu)." >&2
                _PSC_BIN_WARNED=1
            fi
            return 1
        fi
    fi
    local tmp="$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p "$tmp" 2>/dev/null
    _psc_seed_psc
    local out="$tmp/psc-init-$$.flat"
    local lang=en-US
    case "${LANG:-}" in zh*|ZH*) lang=zh-CN ;; esac
    "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "--language=$lang" init --flat --result "$out" 2>/dev/null || return 1
    [[ -f "$out" ]] || return 1
    _psc_read_flat "$out"
    rm -f "$out"
    _PSC_INIT_OK=1
}

# Per-completion manifest language: per-completion config -> module -> declared[0].
# Resolution reads settings.json itself: the _PSC_CFG cache is only filled by _psc_init (first Tab), and `psc` can run before that — the module language must not depend on whether the menu has been triggered yet.
_psc_lang() {
    _psc_need_py || return 1
    local cmd="$1"
    [[ -n "${_PSC_LANGCACHE[$cmd]:-}" ]] && { printf '%s' "${_PSC_LANGCACHE[$cmd]}"; return; }
    local l
    l="$(_psc_py -S - "$PSCOMPLETIONS_DATA_DIR" "$cmd" "${_PSC_CFG[language]:-}" <<'PYEOF'
import json,sys,os
dd,cmd,mod=sys.argv[1],sys.argv[2],sys.argv[3]
try:
    s=json.load(open(os.path.join(dd,'settings.json'),encoding='utf-8'))
except Exception:
    s={}
gcfg=s.get('config') or {}
if not mod: mod=gcfg.get('language') or 'en-US'
try:
    cfg=json.load(open(os.path.join(dd,'completions',cmd,'config.json'),encoding='utf-8'))
except Exception:
    print(mod); raise SystemExit
declared=cfg.get('language') or []
def pick(want):
    return want if want in declared else (declared[0] if declared else mod)
per=(gcfg.get('completion') or {}).get(cmd,{}).get('language')
print(pick(per) if per else pick(mod))
PYEOF
)"
    _PSC_LANGCACHE["$cmd"]="${l:-en-US}"
    printf '%s' "${_PSC_LANGCACHE[$cmd]}"
}


# History the engine can read: one command per line.
# With `HISTTIMEFORMAT` set, bash writes a `#<epoch>` line before every entry, and the engine tokenizes each line as a command line — the timestamps then read as bogus commands.
# Hand it a normalised copy, rebuilt only when the source is newer (so it costs nothing per keystroke).
# Prints the path, or nothing when there is none.
_psc_hist() {
    local src="${HISTFILE:-}"
    [[ -n "$src" && -f "$src" ]] || return 0
    local dst="$PSCOMPLETIONS_DATA_DIR/temp/psc-bash-history"
    mkdir -p "$(dirname -- "$dst")" 2>/dev/null
    if [[ ! -f "$dst" || "$src" -nt "$dst" ]]; then
        # grep exits 1 when nothing matched (an empty history is not an error here).
        grep -v '^#[0-9]\{10\}$' -- "$src" > "$dst" 2>/dev/null || true
        [[ -f "$dst" ]] || return 0
    fi
    printf '%s' "$dst"
}

# --- Tab entry ---------------------------------------------------------------
_psc_complete() {
    _psc_init || return 1
    local before="${READLINE_LINE:0:READLINE_POINT}"
    [[ -n "$before" ]] || return 1
    # A separator ends the command being edited: what follows it is a fresh command line, so its own command word and tokens are what the menu completes.
    # `before` stays whole — the word offsets below are absolute.
    local seg; seg="$(_psc_segment "$before")"
    # tokenize with the shared grammar (must match order::tokenize)
    local -a toks
    if (( _PSC_GREP_P )); then
        mapfile -t toks < <(grep -oP '"[^"]*"|'"'"'[^'"'"']*'"'"'|\S+' <<< "$seg")
    else
        mapfile -t toks < <(_psc_py -S - "$seg" <<'PYEOF'
import re,sys
print('\n'.join(re.findall(r'"[^"]*"|\'[^\']*\'|\S+',sys.argv[1])))
PYEOF
)
    fi
    (( ${#toks[@]} )) || return 1
    local first="${toks[0]}"
    # Strip a Windows executable suffix (case-insensitive), like the PS bridge.
    case "${first,,}" in
        *.exe|*.cmd|*.bat) first="${first%.*}"; toks[0]="$first" ;;
    esac
    # sudo unwrap: `sudo <cmd>` completes for the wrapped command.
    if [[ "$first" == sudo && ${#toks[@]} -gt 1 ]]; then
        local wrapped="${toks[1]}"
        case "${wrapped,,}" in
            *.exe|*.cmd|*.bat) wrapped="${wrapped%.*}" ;;
        esac
        if [[ -n "${_PSC_ALIAS[$wrapped]:-}" ]]; then
            toks=("${toks[@]:1}")
            toks[0]="$wrapped"
            first="$wrapped"
        fi
    fi
    # A wildcard command name is not a completion trigger.
    [[ "$first" == *'*'* || "$first" == *'?'* ]] && return 1
    local cmd="${_PSC_ALIAS[$first]:-}"
    # A path-shaped pending token goes to the native path (path completion), mirroring the PowerShell bridge, even for an installed command.
    if [[ -z "$cmd" || "$before" != *" " ]]; then
        local last="" p
        [[ "$before" != *" " ]] && last="${toks[${#toks[@]}-1]}"
        p="${last#[\"\']}"
        local path_like=0
        case "$p" in
            /*|./*|../*|\~/*) path_like=1 ;;
            \\*|.\\*|..\\*|\~\\*) path_like=1 ;;
            [A-Za-z]:[/\\]*) path_like=1 ;;
        esac
        # `git<Tab>` — the command word itself is still being completed — must offer command names, not git's subcommands: build only once that word is finished (trailing space) or an argument already exists (2+ tokens), the PS bridge's `isSpaceTab or count > 1`.
        if [[ -z "$cmd" ]] || (( path_like )) || { [[ "$before" != *" " && ${#toks[@]} -eq 1 ]]; }; then
            _psc_native "$before" "${toks[@]}"
            return $?
        fi
    fi
    local last_complete=0
    [[ "$before" == *" " ]] && last_complete=1
    # arg_tokens: every token after the command word — the *pending* one included, with `treat_last_as_complete` saying whether it is finished.
    # The engine uses the last unfinished token as the partial match and pre-fills the menu filter from it (`^text`); dropping it builds the parent context, so `psc al<Tab>` showed the root, unfiltered.
    local -a args=()
    local n=${#toks[@]}
    local i
    for (( i=1; i<n; i++ )); do args+=("${toks[i]}"); done
    _psc_build_menu "$cmd" "$last_complete" "${args[@]}"
}

# --- build-mode menu ---------------------------------------------------------
_psc_write_input() {
    _psc_need_py || return 1
    # input.json via python (single writer: quoting-safe).
    # Shared by the live bridge and the headless test driver.
    local in="$1" cmd="$2" last_complete="$3" manifest="$4" has_hooks="$5"
    local cx="$6" cy="$7" w="$8" h="$9"
    shift 9
    PSC_IN="$in" PSC_CMD="$cmd" PSC_LAST="$last_complete" PSC_MANIFEST="$manifest" \
    PSC_HOOKS="$has_hooks" PSC_CWD="$PWD" PSC_DATA="$PSCOMPLETIONS_DATA_DIR" \
    PSC_CX="$cx" PSC_CY="$cy" PSC_W="$w" PSC_H="$h" PSC_HIST="$(_psc_hist)" \
    PSC_PLATFORM="$_psc_engine_platform" \
    _psc_py -S - "$@" <<'PYEOF'
import json,os,sys,urllib.parse
e=os.environ
def b(v): return v=='1'
def truthy(v, d=0):
    if v is None: v=d
    if isinstance(v,str): return v not in ('0','false','False','')
    return bool(v)
dd=e['PSC_DATA']
cmd=e['PSC_CMD']
try: settings=json.load(open(dd+'/settings.json',encoding='utf-8'))
except Exception: settings={}
cfg=settings.get('config',{}) if isinstance(settings.get('config'),dict) else {}
lang=cfg.get('language','en-US')
# Localized filter hints from the psc completion's info templates.
hint, hint_stale = '', ''
try:
    pinfo=json.load(open(f"{dd}/completions/psc/language/{lang}.json",encoding='utf-8')).get('info',{})
    h=pinfo.get('filter_hint') or ''
    hint=''.join(h) if isinstance(h,list) else h
    hs=pinfo.get('filter_hint_stale') or ''
    hint_stale=''.join(hs) if isinstance(hs,list) else hs
except Exception:
    pass
menu={
 "filter_hint": hint, "filter_hint_stale": hint_stale,
 "flags": {
  "enable_list_loop": truthy(cfg.get('enable_list_loop'), 1),
  "filter_mode": cfg.get('filter_mode','wildcard'),
  "enable_apply_when_single": truthy(cfg.get('enable_apply_when_single')),
  "enable_apply_when_no_match": truthy(cfg.get('enable_apply_when_no_match')),
  "show_mode": cfg.get('show_mode','auto'),
  "color_focus": cfg.get('color_focus','red'),
  "color_match": cfg.get('color_match','cyan'),
 },
 "context_switch": cfg.get('switch','~'),
 "context_stay": cfg.get('stay','?'),
 "raw_config": {
  "completion": (cfg.get('completion') or {}).get(cmd,{}) or {},
  "global": {k:v for k,v in cfg.items() if not isinstance(v,(dict,list))},
  "default": {},
 },
}
data={}
if cmd=='psc':
    data={"config":{"language":lang,"completion":cfg.get('completion',{})}}
od=dd+"/temp/order"
q=urllib.parse.quote(cmd,safe='')
border={"cmd_order":od+'/'+q+".json",
 "paths_order":od+"/_shared/_paths.json","commands_order":od+"/_shared/_commands.json"}
top=None
if e.get('PSC_HIST') and truthy(cfg.get('enable_sort_by_history'), 1):
    alias=(settings.get('alias') or {})
    aliases=alias.get(cmd) or [cmd]
    top={"history":e['PSC_HIST'],"cmd":cmd,"aliases":aliases,"path":border["cmd_order"]}
inp={
 "items":[],
 "build":{
  "cmd":cmd,"arg_tokens":sys.argv[1:],"treat_last_as_complete":b(e['PSC_LAST']),
  "manifest":e['PSC_MANIFEST'],"hooks":b(e['PSC_HOOKS']),"cwd":e['PSC_CWD'],
  "config":cfg.get('completion',{}).get(cmd,{}),
  "global_config":{k:v for k,v in cfg.items() if not isinstance(v,(dict,list))},
  "data":data,
  "dir":{"completions":dd+"/completions","cache":dd+"/temp/cache","log":""},
  "file":{"settings":dd+"/settings.json","completions":dd+"/temp/completions.json"},
 },
 "config":menu,
 "terminal":{"cursor":{"x":int(e['PSC_CX']),"y":int(e['PSC_CY'])},
  "buffer":{"w":int(e['PSC_W']),"h":int(e['PSC_H'])},
  "window":{"top":0,"h":int(e['PSC_H'])},"platform":e.get('PSC_PLATFORM','linux')},
 "dir":{"data":e['PSC_DATA'],"order":e['PSC_DATA']+"/temp/order","menu":e['PSC_DATA']+"/temp/menu"},
}
# Ranking is a pair: the build-context block is the channel the engine needs before it consults the history block.
# Keep both tied to one switch: with the key off neither is passed, which is what makes `enable_sort_by_history=0` really stop ranking.
if top:
    inp["build"]["order"] = border
    inp["order"] = top
json.dump(inp,open(e['PSC_IN'],'w',encoding='utf-8'))
PYEOF
}

# Hooks gate: file exists and not disabled (psc itself always runs).
# Echoes 0/1.
# Mirrors the PowerShell enable_hooks gate.
_psc_hooks_enabled() {
    _psc_need_py || return 1
    local cmd="$1"
    [[ -n "${_PSC_HOOKS[$cmd]:-}" ]] && { printf '%s' "${_PSC_HOOKS[$cmd]}"; return; }
    local hooks="$PSCOMPLETIONS_DATA_DIR/completions/$cmd/hooks.lua"
    if [[ ! -f "$hooks" ]]; then _PSC_HOOKS[$cmd]=0; echo 0; return; fi
    if [[ "$cmd" != psc ]]; then
        local eh
        eh="$(_psc_py -S - "$PSCOMPLETIONS_DATA_DIR" "$cmd" <<'PYEOF'
import json,sys,os
try:
    s=json.load(open(os.path.join(sys.argv[1],'settings.json'),encoding='utf-8'))
    v=(s.get('config') or {}).get('completion',{}).get(sys.argv[2],{}).get('enable_hooks',1)
    print(0 if v==0 or v is False else 1)
except Exception:
    print(1)
PYEOF
)"
        if (( ! eh )); then _PSC_HOOKS[$cmd]=0; echo 0; return; fi
    fi
    _PSC_HOOKS[$cmd]=1
    echo 1
}

_psc_build_menu() {
    local cmd="$1" last_complete="$2"; shift 2
    local lang manifest has_hooks
    lang="$(_psc_lang "$cmd")" || return 1
    manifest="$PSCOMPLETIONS_DATA_DIR/completions/$cmd/language/$lang.json"
    has_hooks="$(_psc_hooks_enabled "$cmd")"
    local tmp="$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p "$tmp" 2>/dev/null
    local id; id="${EPOCHREALTIME//./}$$"
    local in="$tmp/psc-menu-$id-input.json" out="$tmp/psc-menu-$id-output.json"
    # cursor column + terminal size (fallback: col 0, $LINES/$COLUMNS)
    local cx=0 cy=0 w=${COLUMNS:-120} h=${LINES:-30}
    local line_head="${READLINE_LINE:0:READLINE_POINT}"
    local cx
    if [[ "$line_head" == *$'\n'* ]]; then
        local tail="${line_head##*$'\n'}"
        cx=${#tail}
    else
        cx=${#line_head}
    fi
    _psc_write_input "$in" "$cmd" "$last_complete" "$manifest" "$has_hooks" "$cx" "$cy" "$w" "$h" "${args[@]}"
    # spawn with inherited TTY + 30 s heartbeat watchdog
    local status words nospace
    IFS=$'\t' read -r status words nospace < <(_psc_spawn "$in" "$out")
    rm -f "$in" "$out"
    if [[ "$status" == min_area ]]; then
        local hint
        hint="$(_psc_tpl min_area 2>/dev/null)" || hint="# terminal too small for menu"
        READLINE_LINE="${READLINE_LINE} ${hint%%$'\n'*}"
        READLINE_POINT=${#READLINE_LINE}
        return 1
    fi
    [[ "$status" == selected || "$status" == input ]] || return 1
    _psc_apply "$words" "$nospace"
}

# stdout: "<status>\t<text>\t<nospace>"
_psc_spawn() {
    local in="$1" out="$2"
    coproc _PSC_HB { "$_PSC_MENU" "$in" --result "$out" 2>&1 1>/dev/tty; }
    local pid=$!
    local elapsed=0 line
    while kill -0 "$pid" 2>/dev/null; do
        if IFS= read -r -t 1 -u "${_PSC_HB[0]}" line; then
            elapsed=0  # any stderr line (HBT) resets the watchdog
        else
            (( elapsed++ ))
        fi
        if (( elapsed >= 30 )); then
            kill -9 "$pid" 2>/dev/null
            printf '%s' "$_PSC_RESET_TERM" > /dev/tty
            _psc_flush_tty
            wait "$pid" 2>/dev/null
            printf 'cancel\t'
            return
        fi
    done
    wait "$pid" 2>/dev/null
    if [[ -f "$out" ]]; then
        _psc_py -S - "$out" <<'PYEOF'
import json,sys
try: r=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: print('cancel\t'); raise SystemExit
s=r.get('status')
if s=='selected': print(f"selected\t{r.get('completion_text','')}\t{'1' if r.get('nospace') else '0'}")
elif s=='input': print(f"input\t{r.get('text','')}\t0")
else: print(f"{s}\t\t")
PYEOF
    else
        printf 'cancel\t'
    fi
}

# Start offset of the word under the cursor, as a count of characters to keep from the start of the line (bash's string slicing is length-based).
# A word boundary is an unquoted, unescaped whitespace, so `az\ zdir` stays one word: the naive `${before##* }` split cut at the escaped space and concatenated the pick after the old text instead of replacing it.
# The command being edited: everything after the last unquoted separator (`|`, `;`, `&`, `&&`, `||`).
# A separator ends a command, so what follows it is a fresh command line whose own command word and tokens are what the menu completes (`git status | grep <Tab>` completes `grep`).
# Quotes (and `\`) hide a separator; `>&` and `&>` are redirections, not separators; an empty result means there is nothing to complete here, so the caller falls back to the host.
_psc_segment() {
    local s="$1" out='' q=0 i=0 c n=${#1}
    while (( i < n )); do
        c="${s:i:1}"
        if (( q != 1 )) && [[ "$c" == '\' ]]; then
            out+="${s:i:2}"
            (( i += 2 )); continue
        fi
        if [[ "$c" == "'" ]]; then
            (( q = q == 1 ? 0 : (q == 0 ? 1 : q) ))
            out+="$c"; (( i++ )); continue
        fi
        if [[ "$c" == '"' ]]; then
            (( q = q == 2 ? 0 : (q == 0 ? 2 : q) ))
            out+="$c"; (( i++ )); continue
        fi
        if (( q == 0 )); then
            case "$c" in
                '|'|';') out='' ;;
                '&')
                    # `&` backgrounds, `&&` separates, and `>&` / `&>` are redirections.
                    if [[ "${s:i+1:1}" == '>' ]] || { (( i > 0 )) && [[ "${s:i-1:1}" == '>' ]]; }; then
                        out+="$c"
                    else
                        out=''
                        [[ "${s:i+1:1}" == '&' ]] && (( i++ ))
                    fi ;;
                *) out+="$c" ;;
            esac
        else
            out+="$c"
        fi
        (( i++ ))
    done
    # The leading whitespace belongs to the separator, not to the new command.
    printf '%s' "${out#"${out%%[![:space:]]*}"}"
}

_psc_word_start() {
    local s="$1" out=0 q=0 i c n=${#1}
    for (( i = 0; i < n; i++ )); do
        c="${s:i:1}"
        if (( q != 1 )) && [[ "$c" == '\' ]]; then
            (( i++ )); continue
        fi
        if [[ "$c" == "'" ]]; then
            if (( q == 0 )); then q=1; elif (( q == 1 )); then q=0; fi
        elif [[ "$c" == '"' ]]; then
            if (( q == 0 )); then q=2; elif (( q == 2 )); then q=0; fi
        elif (( q == 0 )) && [[ "$c" == " " || "$c" == $'\t' ]]; then
            out=$(( i + 1 ))
        fi
    done
    printf '%s' "$out"
}

_psc_apply() {
    local text="$1" nospace="${2:-0}" before="${READLINE_LINE:0:READLINE_POINT}"
    local start=$READLINE_POINT
    if [[ -n "$before" && "${before: -1}" != " " ]]; then
        start=$(( READLINE_POINT - ${#before} + $(_psc_word_start "$before") ))
    fi
    local after="${READLINE_LINE:READLINE_POINT}"
    # Cursor mid-word: consume the remainder of the word under the cursor, so the replacement covers the whole token (mirrors the PowerShell word-end extend).
    local consume=0
    if [[ -n "$after" ]]; then
        local c0="${after:0:1}"
        if [[ "$c0" != " " && "$c0" != $'\t' && "$c0" != '"' && "$c0" != "'" ]]; then
            if [[ "$after" =~ ^(\"[^\"]*\"|\'[^\']*\'|[^[:space:]]+) ]]; then
                consume=${#BASH_REMATCH[1]}
            fi
        fi
    fi
    local tail="${after:consume}"
    # No trailing space for attached values (`--x=`), engine nospace, append-space off, or when a following word already exists after whitespace.
    local suffix=" "
    [[ "$text" == *= || "$nospace" == 1 ]] && suffix=""
    [[ "${_PSC_CFG[enable_append_space]:-1}" == 0 ]] && suffix=""
    [[ "$after" =~ ^[[:space:]]+[^[:space:]] ]] && suffix=""
    # A closing quote right after the cursor would double: drop ours.
    local first_after="${after:0:1}" last_text="${text: -1}"
    if [[ "$first_after" == '"' || "$first_after" == "'" ]] && [[ "$last_text" == "$first_after" ]]; then
        text="${text%?}"
    fi
    READLINE_LINE="${READLINE_LINE:0:start}${text}${suffix}${tail}"
    READLINE_POINT=$(( start + ${#text} + ${#suffix} ))
}

# --- native fallback: host completions through our menu ---------------------------
# Unknown words resolve via compgen (commands for the first word, files after), history-ranked through `psc-menu --sort`, and rendered in our menu.
# Directory handling for a picked native candidate, mirroring the PS bridge's `handle_menu_output`: a **container never takes a trailing space** — the user is likely to keep completing inside it — and `enable_path_trailing_separator` only decides whether the separator itself is added.
# Result channel: _PSC_PICK_TEXT / _PSC_PICK_NOSPACE.
_psc_pick_text() {
    _PSC_PICK_TEXT="$1"
    _PSC_PICK_NOSPACE=0
    [[ -d "${_PSC_PICK_TEXT/#\~/$HOME}" ]] || return 0
    _PSC_PICK_NOSPACE=1
    if [[ "${_PSC_CFG[enable_path_trailing_separator]:-1}" == 1 ]]; then
        [[ "$_PSC_PICK_TEXT" != */ ]] && _PSC_PICK_TEXT="${_PSC_PICK_TEXT}/"
    fi
}

# Trailing text for a native pick: a space only for an ordinary candidate — never for a container (`ns`), an attached-value (`--format=`), or when a word already follows after whitespace (`foo |bar`).
# A word glued to the cursor still gets the space, or the pick would fuse with it.
# Mirrors the PS bridge's `handle_menu_output`.
_psc_native_suffix() {
    local pick="$1" after="$2" ns="$3"
    [[ "$pick" == *= ]] && return 0
    (( ns )) && return 0
    [[ "$after" =~ ^[[:space:]]+[^[:space:]] ]] && return 0
    printf ' '
}

_psc_native() {
    local before="$1"; shift
    local -a toks=("$@")
    [[ "${_PSC_CFG[enable_native_completion]:-1}" == 1 ]] || return 1
    [[ "${_PSC_CFG[enable_sort_by_history]:-1}" == 1 ]] && _psc_want_sort=1 || _psc_want_sort=0
    # The pending word, escape-aware: `cd /tmp/psc\ t/` is one word.
    # It is what the host completion is asked to complete and the range the pick replaces.
    local cur=""
    [[ -n "$before" && "${before: -1}" != " " ]] && cur="${before:$(_psc_word_start "$before")}"
    local -a cands=()
    # A registered `complete -F` handler is the real native completion: drive it the way readline would (COMP_* vars in, COMPREPLY out).
    local first="${toks[0]}"
    local spec func
    if spec="$(complete -p "$first" 2>/dev/null)" && [[ "$spec" =~ -F[[:space:]]+([^[:space:]]+) ]]; then
        func="${BASH_REMATCH[1]}"
        if declare -F "$func" >/dev/null 2>&1; then
            # Mirror readline: the word under the cursor exists even when empty.
            local -a cwords=("${toks[@]}")
            [[ "$before" == *" " ]] && cwords+=("")
            COMP_WORDS=("${cwords[@]}")
            COMP_CWORD=$(( ${#cwords[@]} - 1 ))
            COMP_LINE="$before"
            COMP_POINT=${#before}
            COMPREPLY=()
            "$func" "$first" "$cur" "" 2>/dev/null
            cands=("${COMPREPLY[@]}")
            COMPREPLY=()
        fi
    fi
    if (( ${#cands[@]} == 0 )); then
    if (( ${#toks[@]} == 1 )) && [[ "$before" != *" " ]]; then
        mapfile -t cands < <(compgen -c -- "$cur" 2>/dev/null)
    else
        # expand ~ for the lookup, keep the typed prefix for replacement; a quote around the word is a quoting artefact, not part of the path
        local exp="$cur" tilde=0
        [[ "$exp" == "~"* ]] && tilde=1
        [[ "$exp" == \"* || "$exp" == \'* ]] && exp="${exp:1}"
        [[ "$exp" == *\" || "$exp" == *\' ]] && exp="${exp%?}"
        # an escaped space is quoting, not part of the path (`/tmp/psc\ t/`)
        exp="${exp//\\ / }"
        [[ "$tilde" == 1 ]] && exp="$HOME${exp:1}"
        mapfile -t cands < <(compgen -f -- "$exp" 2>/dev/null)
        # compgen lists containers without the trailing separator the other hosts add; mark them so the display and the inserted text match across shells
        local -A dirs=()
        local d
        while IFS= read -r d; do
            [[ -n "$d" ]] || continue
            dirs["${d%/}"]=1
        done < <(compgen -S / -d -- "$exp" 2>/dev/null)
        local i
        for i in "${!cands[@]}"; do
            [[ -n "${dirs[${cands[i]}]:-}" ]] && cands[i]="${cands[i]}/"
        done
        if [[ "$tilde" == 1 ]]; then
            for i in "${!cands[@]}"; do cands[i]="~${cands[i]#$HOME}"; done
        fi
    fi
    fi
    (( ${#cands[@]} )) || return 1
    local tmp="$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p "$tmp" 2>/dev/null
    local id; id="${EPOCHREALTIME//./}$$"
    local in="$tmp/psc-sort-$id-in.json" out="$tmp/psc-sort-$id-out.json"
    local cands_file="$tmp/psc-sort-$id-cands.txt"
    # --sort input via python (quoting-safe).
    # The candidate list travels in a file, not in the environment: a host completion can return thousands of entries and blow ARG_MAX.
    printf '%s\n' "${cands[@]}" > "$cands_file"
    PSC_IN="$in" PSC_TOKS="$(printf '%s\n' "${toks[@]}")" PSC_LAST="$([[ "$before" == *" " ]] && echo 1 || echo 0)" \
    PSC_CANDS_FILE="$cands_file" PSC_CMD="${toks[0]}" PSC_DATA="$PSCOMPLETIONS_DATA_DIR" \
    PSC_HIST="$([[ $_psc_want_sort == 1 ]] && _psc_hist)" PSC_PLATFORM="$_psc_engine_platform" \
    _psc_py -S <<'PYEOF'
import json,os
e=os.environ
items=[{"text":t} for t in open(e['PSC_CANDS_FILE'],encoding='utf-8').read().split('\n') if t!='']
tok=[t for t in e['PSC_TOKS'].split('\n') if t!='']
o={"items":items,"tokens":tok,"treat_last_as_complete":e['PSC_LAST']=='1'}
if e.get('PSC_HIST'):
    import urllib.parse
    cmd=e['PSC_CMD']
    od=e['PSC_DATA']+'/temp/order'
    o["order"]={"cmd_order":od+'/'+urllib.parse.quote(cmd,safe=''),
     "paths_order":od+'/_shared/_paths.json',"commands_order":od+'/_shared/_commands.json'}
json.dump(o,open(e['PSC_IN'],'w',encoding='utf-8'))
PYEOF
    "$_PSC_MENU" --sort "$in" --result "$out" >/dev/null 2>&1
    local sorted="$(_psc_py -S - "$out" <<'PYEOF'
import json,sys
try: items=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: raise SystemExit(1)
print('\n'.join(i.get('text','') for i in items if i.get('text') is not None))
PYEOF
)"
    rm -f "$in" "$out" "$cands_file"
    [[ -n "$sorted" ]] || return 1
    local -a ordered=()
    mapfile -t ordered <<< "$sorted"
    # show our menu with items
    local pick
    pick="$(_psc_menu_items "${toks[0]}" "$(printf '%s\n' "${toks[@]}")" \
        "$([[ "$before" == *" " ]] && printf 1 || printf 0)" "${ordered[@]}")"
    [[ -n "$pick" ]] || return 1
    _psc_pick_text "$pick"
    pick="$_PSC_PICK_TEXT"
    local ns=$_PSC_PICK_NOSPACE
    # An attached-value option (`--format=`) takes its value in the same word: no space, the cursor stays behind the `=` (same rule as the PS bridge).
    [[ "$pick" == *= ]] && ns=1
    # quote when the word needs it
    [[ "$pick" == *[[:space:]]* ]] && pick="'$pick'"
    local start=$READLINE_POINT
    if [[ -n "$cur" ]]; then
        # replace only the typed prefix, keep a ~/ expansion typed by the user
        start=$(( READLINE_POINT - ${#cur} ))
    fi
    local after="${READLINE_LINE:READLINE_POINT}"
    local suffix
    suffix="$(_psc_native_suffix "$pick" "$after" "$ns")"
    READLINE_LINE="${READLINE_LINE:0:start}${pick}${suffix}${after}"
    READLINE_POINT=$(( start + ${#pick} + ${#suffix} ))
}

# menu with host-provided items; echoes the chosen completion_text Items mode: the filter is the engine's call, so the bridge only forwards the line's tokens — `arg_tokens` (the pending one included) and whether it is already finished.
# The engine derives `initial_filter` and ignores it when it matches nothing (a path slot displays leaves, so its pending word is rarely a genuine prefix).
_psc_menu_items() {
    local cmd="$1" args="$2" last="${3:-0}"; shift 3
    local -a texts=("$@")
    local tmp="$PSCOMPLETIONS_DATA_DIR/temp/menu"
    local id; id="${EPOCHREALTIME//./}$$"
    local in="$tmp/psc-items-$id-in.json" out="$tmp/psc-items-$id-out.json"
    local items_file="$tmp/psc-items-$id-items.txt"
    # The candidate list travels in a file: a host completion can return thousands of entries and an environment variable would blow ARG_MAX.
    printf '%s\n' "${texts[@]}" > "$items_file"
    PSC_IN="$in" PSC_ITEMS_FILE="$items_file" PSC_ARGS="$args" PSC_LAST="$last" \
    PSC_DATA="$PSCOMPLETIONS_DATA_DIR" \
    PSC_CMD="$cmd" PSC_HIST="$(_psc_hist)" PSC_PLATFORM="$_psc_engine_platform" \
    _psc_py -S <<'PYEOF'
import json,os,urllib.parse
e=os.environ
def truthy(v, d=0):
    if v is None: v=d
    if isinstance(v,str): return v not in ('0','false','False','')
    return bool(v)
dd=e['PSC_DATA']
try: settings=json.load(open(dd+'/settings.json',encoding='utf-8'))
except Exception: settings={}
cfg=settings.get('config',{}) if isinstance(settings.get('config'),dict) else {}
lang=cfg.get('language','en-US')
hint, hint_stale = '', ''
try:
    pinfo=json.load(open(f"{dd}/completions/psc/language/{lang}.json",encoding='utf-8')).get('info',{})
    h=pinfo.get('filter_hint') or ''
    hint=''.join(h) if isinstance(h,list) else h
    hs=pinfo.get('filter_hint_stale') or ''
    hint_stale=''.join(hs) if isinstance(hs,list) else hs
except Exception:
    pass
menu={
 "filter_hint": hint, "filter_hint_stale": hint_stale,
 "flags": {
  "enable_list_loop": truthy(cfg.get('enable_list_loop'), 1),
  "filter_mode": cfg.get('filter_mode','wildcard'),
  "enable_apply_when_single": truthy(cfg.get('enable_apply_when_single')),
  "enable_apply_when_no_match": truthy(cfg.get('enable_apply_when_no_match')),
  "show_mode": cfg.get('show_mode','auto'),
  "color_focus": cfg.get('color_focus','red'),
  "color_match": cfg.get('color_match','cyan'),
 },
 "context_switch": cfg.get('switch','~'),
 "context_stay": cfg.get('stay','?'),
 "raw_config": {"completion": {}, "global": {k:v for k,v in cfg.items() if not isinstance(v,(dict,list))}, "default": {}},
}
items=[]
def leaf(p):
    # Display drops the typed prefix the way the hosts' own lists do (PS `ListItemText`):
    # `/tmp/psc t/az zdir/` renders as `az zdir/`, `python3` as `python3`.
    body=p[:-1] if p.endswith('/') else p
    return body.rsplit('/',1)[-1] + ('/' if p.endswith('/') else '')
for t in open(e['PSC_ITEMS_FILE'],encoding='utf-8').read().split('\n'):
    if t=='' : continue
    items.append({"completion_text":t,"list_item_text":leaf(t),"symbol":"","tip":None,
     "usage":None,"example":None,"result_type":None})
od=e['PSC_DATA']+'/temp/order'
inp={"items":items,
 "config":menu,
 "terminal":{"cursor":{"x":0,"y":0},"buffer":{"w":120,"h":30},
  "window":{"top":0,"h":30},"platform":e.get('PSC_PLATFORM','linux')},
 "dir":{"data":e['PSC_DATA'],"order":od,"menu":e['PSC_DATA']+"/temp/menu"},
 "arg_tokens":[t for t in (e.get('PSC_ARGS') or '').split('\n') if t!=''],
 "treat_last_as_complete":e.get('PSC_LAST')=='1'}
if e.get('PSC_HIST') and truthy(cfg.get('enable_sort_by_history'), 1):
    try: alias=json.load(open(e['PSC_DATA']+'/settings.json',encoding='utf-8')).get('alias',{})
    except Exception: alias={}
    q=urllib.parse.quote(e['PSC_CMD'],safe='')
    inp["order"]={"history":e['PSC_HIST'],"cmd":e['PSC_CMD'],
     "aliases":alias.get(e['PSC_CMD'],[e['PSC_CMD']]),"path":od+'/'+q+'.json'}
json.dump(inp,open(e['PSC_IN'],'w',encoding='utf-8'))
PYEOF
    local status idx
    IFS=$'\t' read -r status idx < <(_psc_spawn_items "$in" "$out")
    rm -f "$in" "$out" "$items_file"
    if [[ "$status" == min_area ]]; then
        local hint
        hint="$(_psc_tpl min_area 2>/dev/null)" || hint="# terminal too small for menu"
        READLINE_LINE="${READLINE_LINE} ${hint%%$'\n'*}"
        READLINE_POINT=${#READLINE_LINE}
        return 1
    fi
    # `input` carries the filter text itself (no-match auto-apply); items are answered by index, but a text needs no index at all — apply it exactly like the build path does.
    if [[ "$status" == input ]]; then
        printf '%s' "$idx"
        return 0
    fi
    [[ "$status" == selected && -n "$idx" ]] || return 1
    printf '%s' "${texts[$idx]}"
}

# like _psc_spawn but resolves items-mode index -> text
_psc_spawn_items() {
    local in="$1" out="$2"
    coproc _PSC_HB2 { "$_PSC_MENU" "$in" --result "$out" 2>&1 1>/dev/tty; }
    local pid=$!
    local elapsed=0 line
    while kill -0 "$pid" 2>/dev/null; do
        if IFS= read -r -t 1 -u "${_PSC_HB2[0]}" line; then
            elapsed=0
        else
            (( elapsed++ ))
        fi
        if (( elapsed >= 30 )); then
            kill -9 "$pid" 2>/dev/null
            printf '%s' "$_PSC_RESET_TERM" > /dev/tty
            _psc_flush_tty
            wait "$pid" 2>/dev/null
            printf 'cancel\t'
            return
        fi
    done
    wait "$pid" 2>/dev/null
    if [[ -f "$out" ]]; then
        _psc_py -S - "$out" <<'PYEOF'
import json,sys
try: r=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: print('cancel\t'); raise SystemExit
s=r.get('status')
if s=='selected': print(f"selected\t{r.get('index','')}")
elif s=='input': print(f"input\t{r.get('text','')}")   # no-match: apply the filter text directly
else: print('cancel\t')
PYEOF
    else
        printf 'cancel\t'
    fi
}
# Generic info-template renderer (design/templates.md).
# Usage: _psc_tpl <dotted.info.path> [context-json] 
# Context values come from the caller; `version` is filled from the module manifest.
# Unknown constructs stay literal; colors map to ANSI.
# Renders one `info` template through the engine (`psc tpl --version …`).
# The grammar and its implementation live there, so a bridge carries no renderer of its own.
# A missing binary or an unknown path fails, and the caller's `||` fallback takes over.
_psc_module_version() {
    # The module manifest beside the bridge is the one version source present in both a repo checkout and an installed package (the package carries no `../version.json`).
    sed -n "s/.*ModuleVersion *= *'\([^']*\)'.*/\1/p" "$_psc_bridge_dir/PSCompletions.psd1" 2>/dev/null | head -1
}

_psc_tpl() {
    [[ -x "$_PSC_BIN" ]] || return 1
    local args=("--data" "$PSCOMPLETIONS_DATA_DIR" tpl "$1")
    (( $# >= 2 )) && args+=("--ctx" "$2")
    args+=("--version" "$(_psc_module_version)")
    "$_PSC_BIN" "${args[@]}"
}

# Run a management command that only prints a status line.
# The CLI's messages are plain text, so the color is the bridge's job — the same convention as the PS bridge's `_forward_psc`: success green, failure red (design/config-support.md).
_psc_run_status() {
    local out rc
    out="$("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "$@" 2>&1)"
    rc=$?
    if [[ -n "$out" ]]; then
        if (( rc == 0 )); then
            printf '\033[32m%s\033[0m\n' "$out"
        else
            printf '\033[31m%s\033[0m\n' "$out"
        fi
    fi
    return $rc
}

# Forwards to the binary; state-changing commands invalidate the cached init so the next Tab rebuilds aliasMap/config.
psc() {
    _psc_need_py || return 1
    [[ -x "$_PSC_BIN" ]] || { echo "psc binary missing: $_PSC_BIN" >&2; return 1; }
    # Bare `psc` shows the module info page from static data, like PowerShell.
    if (( $# == 0 )); then
        _psc_tpl description || "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR"
        echo
        return 0
    fi
    # `psc --self-update` (root-level flag): the engine detects how this copy was installed and says what updates it — a script install is updated right there, the rest is a command to run.
    if [[ "${1:-}" == --self-update ]]; then
        _psc_plain_progress --self-update
        return $?
    fi
    # `psc --reset` (PowerShell-only flag): confirm, wipe the data dir, re-seed.
    if [[ "${1:-}" == --reset ]]; then
        _psc_tpl reset.init_confirm
        echo
        local key
        read -r -n1 -s -p " " key
        echo
        [[ -z "$key" ]] || { _psc_tpl confirm_cancel; echo; return 1; }
        find "$PSCOMPLETIONS_DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
        mkdir -p "$PSCOMPLETIONS_DATA_DIR/completions"
        _psc_seed_psc
        _PSC_INIT_OK=0
        _psc_init
        _psc_tpl reset.init_done
        echo
        return 0
    fi
    # `--json` anywhere means the caller wants the machine contract: hand the invocation to the engine as it is — never colored, never rendered into a human page — and never prompted first: a machine caller cannot press a key (design/json.md §7).
    # With no command word it is the **root** response (§5), so this check comes before the flags-only info page below.
    local _arg
    for _arg in "$@"; do
        if [[ "$_arg" == "--json" ]]; then
            # Verbatim: a failure is JSON as well, and color would break the contract.
            _PSC_INIT_OK=0
            "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "$@"
            return $?
        fi
    done
    # Only flags and no command word: the module's info page, exactly like the bare call.
    # The binary's own usage text is an implementation detail, not what a user of the module sees.
    local _arg _has_cmd=0
    for _arg in "$@"; do
        [[ "$_arg" == -* ]] || _has_cmd=1
    done
    if (( _has_cmd == 0 )); then
        _psc_tpl description || "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR"
        echo
        return 0
    fi
    # rm --all is destructive: confirm like the PowerShell bridge does.
    if [[ "${1:-}" == rm ]] && [[ " $* " == *" --all "* ]]; then
        _psc_tpl rm.all_confirm
        echo
        local key
        read -r -n1 -s -p " " key
        echo
        [[ -z "$key" ]] || { _psc_tpl confirm_cancel; echo; return 1; }
        # The engine never prompts: the confirmation just given is the authorisation it needs.
        set -- "$@" --yes
    fi
    # A group reset (config / completion / alias) is not confirmed — not destructive enough — but the engine still requires authorisation (design/json.md §7).
    if [[ " $* " == *" --reset "* ]]; then
        set -- "$@" --yes
    fi
    local code=0
    case "${1:-}" in
        add|rm)
            # Rendered from --json (templates), never double-executed.
            _psc_run_rendered "$@"
            code=$?
            ;;
        update)
            # No argument is the library check: its payload is the four change lists, not a per-completion result set.
            # The plain list is dropped on success — the tail renders the same lists as a template below (the PowerShell bridge discards the CLI text the same way); a failure still prints.
            if (( $# == 1 )); then _psc_check_update "$@"; else _psc_run_rendered "$@"; fi
            code=$?
            ;;
        list|info|alias|completion|config)
            # Queries print the CLI's text verbatim (`list`, `info`, and the reads of `alias` / `completion` / `config`); anything that sets a value stays on the status path.
            case "${1:-}" in
                list|info) _psc_plain "$@" ;;
                alias) [[ $# -eq 1 ]] && _psc_plain "$@" || _psc_run_status "$@" ;;
                completion)
                    # Reads print the CLI's text; only a value (--reset or a fourth arg) takes the status path — the PowerShell bridge routes the same way.
                    if [[ " $* " == *" --reset "* || $# -gt 3 ]]; then _psc_run_status "$@"; else _psc_plain "$@"; fi
                    ;;
                config)
                    # `config` and `config <group>` are queries as well; only a value or `--reset` makes it an action.
                    if (( $# >= 4 )) || [[ " $* " == *" --reset "* ]]; then
                        _psc_run_status "$@"
                    else
                        _psc_plain "$@"
                    fi
                    ;;
            esac
            code=$?
            ;;
        *)
            # An unrecognised command shows the module info page, exactly like the no-argument form: the module is discovered by browsing, not by an error.
            _psc_tpl description || "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR"
            echo
            return 0
            ;;
    esac
    case "${1:-}" in
        add|rm|update|alias|completion|config|init) _PSC_INIT_OK=0 ;;
    esac
    # `config menu trigger_key <k>`: rebind the live key on success.
    if (( code == 0 )) && [[ "${1:-}" == config && "${2:-}" == menu && "${3:-}" == trigger_key && -n "${4:-}" ]]; then
        _psc_bind_trigger "$4"
    fi
    _psc_render_pending
    return $code
}

# A status command (--self-update) announces a network wait on stderr, so keep it; a data query must stay clean.
_psc_plain_progress() {
    local _out rc
    _out="$("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "$@" 2>&1)"
    rc=$?
    if (( rc == 0 )); then
        printf '%s\n' "$_out"
    elif [[ -n "$_out" ]]; then
        printf '\033[31m%s\033[0m\n' "$_out"
    fi
    return $rc
}

# Data queries print exactly what the CLI renders: the CLI's text is the interface in every host (`psc info > file`, `v=$(psc config <group> <key>)`), and `--json` is the machine contract.
# Only messages take color.
# A failed query still goes through the red path.
_psc_plain() {
    local _out
    if _out="$("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "$@" 2>/dev/null)"; then
        printf '%s\n' "$_out"
        return 0
    fi
    _psc_run_status "$@"
}

# No-arg update: the lists belong to the template tail, not to the CLI's plain text.
# Success prints nothing — the tail renders the same lists as a template; a failure prints, like the PowerShell bridge's non-Quiet path.
_psc_check_update() {
    local _out rc
    _out="$("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "$@" 2>&1)"
    rc=$?
    if (( rc != 0 )); then
        if [[ -n "$_out" ]]; then
            printf '\033[31m%s\033[0m\n' "$_out"
        fi
        return $rc
    fi
    # The tail renders the lists as a template when there are any; with none it renders nothing, so the "up to date" answer comes from that template here.
    if ! _psc_pending_library; then
        if ! { _psc_tpl update.no && echo; }; then
            printf '%s\n' "$_out"
        fi
    fi
    return 0
}

# Whether change.json carries anything the tail will render (the same set `_psc_render_pending` reads).
_psc_pending_library() {
    local change="$PSCOMPLETIONS_DATA_DIR/temp/change.json"
    [[ -f "$change" ]] || return 1
    _psc_py -S - "$change" <<'PYEOF'
import json,sys
try: c=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: raise SystemExit(1)
has=bool(c.get('update') or c.get('added') or c.get('removed') or c.get('renamed'))
raise SystemExit(0 if has else 1)
PYEOF
}

# Run add/rm/update once in --json mode and render with the static templates (green done, yellow ownership warnings, red errors), mirroring PowerShell.
_psc_run_rendered() {
    _psc_need_py || return 1
    local cmd="$1"; shift
    local raw
    raw="$("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" --json "$cmd" "$@" 2>/dev/null)"
    local code=$?
    local jobs
    jobs="$(PSC_CMD="$cmd" PSC_RAW="$raw" PSC_DATA="$PSCOMPLETIONS_DATA_DIR" PSC_LANG="$(_psc_lang psc)" _psc_py -S <<'PYEOF'
import json,os
e=os.environ
cmd=e['PSC_CMD']
try: env=json.loads(e['PSC_RAW'])
except Exception: env={}
# The envelope's payload: the per-completion list, each item `{name, ok, error?}`.
results=((env.get('data') or {}).get('completions') or []) if isinstance(env,dict) else []
dd=e['PSC_DATA']
lang=e.get('PSC_LANG') or 'en-US'
def mlang(name):
    for lf in (settings_lang(name), 'en-US'):
        try:
            json.load(open(f"{dd}/completions/{name}/language/{lf}.json",encoding='utf-8'))
            return lf
        except Exception: continue
    return 'en-US'
def settings_lang(name):
    try:
        s=json.load(open(dd+'/settings.json',encoding='utf-8'))
        per=((s.get('config') or {}).get('completion',{}) or {}).get(name,{}).get('language')
        if per: return per
        return (s.get('config') or {}).get('language','en-US')
    except Exception: return 'en-US'
try: settings=json.load(open(dd+'/settings.json',encoding='utf-8'))
except Exception: settings={}
aliasmap=settings.get('alias',{}) or {}
stored_all=((settings.get('config',{}) or {}).get('completion',{}) or {})
C='\x1f'
if isinstance(env,dict) and env.get('ok') is False:
    err=env.get('error') or {}
    print(f"ERR{C}{C}{err.get('message','') if isinstance(err,dict) else err}")
    raise SystemExit
for r in results:
    if not isinstance(r,dict): continue
    name=r.get('name') or ''
    if not r.get('ok'):
        err=r.get('error') or {}
        print(f"ERR{C}{name}{C}{err.get('message','') if isinstance(err,dict) else err}")
        continue
    if cmd=='rm':
        print(f"TPL{C}rm.done{C}"+json.dumps({"Completion":name},ensure_ascii=False))
        continue
    if cmd in ('add','update'):
        disp=r.get('renamed_from','')
        disp=f"{disp} -> {name}" if disp else ''
        lf=mlang(name)
        try: man=json.load(open(f"{dd}/completions/{name}/language/{lf}.json",encoding='utf-8'))
        except Exception: man={}
        try: cfgjson=json.load(open(f"{dd}/completions/{name}/config.json",encoding='utf-8'))
        except Exception: cfgjson={}
        try: info=(json.load(open(f"{dd}/completions/psc/language/{lang}.json",encoding='utf-8')) or {}).get('info',{})
        except Exception: info={}
        rows=[]
        if cfgjson.get('hooks') is not None:
            tip=''.join(((info.get('completion',{}).get('enable_hooks',{}) or {}).get('tip',[]) or []))
            rows.append({"Name":"enable_hooks","Value":int(bool(cfgjson.get('hooks'))),"Tip":tip})
        for i in (man.get('config') or []):
            if isinstance(i,dict) and 'name' in i:
                t=i.get('tip','')
                rows.append({"Name":i.get('name'),"Value":i.get('value'),"Tip":t if isinstance(t,str) else '\n'.join(t or [])})
        stored=stored_all.get(name,{}) or {}
        for row in rows:
            if stored.get(row['Name']) is not None:
                row['Current']=stored.get(row['Name'])
        print(f"TPL{C}{cmd}.done{C}"+json.dumps({"Completion":name,"Display":disp,
         "Alias":list(aliasmap.get(name) or [name]),"Configs":rows},ensure_ascii=False))
    for s in (r.get('skipped') or []):
        if isinstance(s,dict):
            print(f"TPL{C}alias.skipped{C}"+json.dumps({"Alias":s.get('alias',''),"Owner":s.get('owner','')},ensure_ascii=False))
PYEOF
)"
    local red=$'\033[31m' off=$'\033[0m'
    local rectype a b
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        rectype="${line%%$'\x1f'*}"; line="${line#*$'\x1f'}"
        a="${line%%$'\x1f'*}"; b="${line#*$'\x1f'}"
        case "$rectype" in
            ERR)
                if [[ -n "$a" ]]; then
                    printf '%s%s: %s%s\n' "$red" "$a" "$b" "$off"
                else
                    printf '%s%s%s\n' "$red" "$b" "$off"
                fi
                code=1
                ;;
            TPL) _psc_tpl "$a" "$b" && echo ;;
            *) printf '%s%s%s\n' "$red" "$line" "$off"; code=1 ;;
        esac
    done <<< "$jobs"
    return $code
}

# Pending notifications tail (module update persists; library added/removed are one-shot, update/renamed persist).
# Plain text: the info templates live in the PowerShell bridge; bash renders the same facts without them.
_psc_render_pending() {
    _psc_need_py || return 1
    local change="$PSCOMPLETIONS_DATA_DIR/temp/change.json"
    [[ -f "$change" ]] || return 0
    # The module notice fires only for a remote version newer than the installed one (compared numerically inside); the library lists below render as a template.
    local out
    out="$(_psc_py -S - "$change" "$PSCOMPLETIONS_DATA_DIR" "$(_psc_module_version)" <<'PYEOF'
import json,sys
p,dd,installed=sys.argv[1],sys.argv[2],sys.argv[3]
try: c=json.load(open(p,encoding='utf-8'))
except Exception: raise SystemExit(1)
def newer(remote, installed):
    # Numeric segments: 8.0.10 is newer than 8.0.9, which a string compare gets wrong.
    # Unparseable on either side means "cannot tell", and the PowerShell bridge answers that with no notice either.
    try:
        r=[int(x) for x in str(remote).split('.')]
        i=[int(x) for x in str(installed).split('.')]
    except ValueError:
        return False
    n=max(len(r),len(i))
    return (r+[0]*n)[:n] > (i+[0]*n)[:n]
mod=c.get('module')
if mod and newer(mod, installed):
    try:
        with open(dd+'/temp/.bash-module-notified',encoding='utf-8') as f: seen=f.read().strip()
    except Exception: seen=''
    if str(mod)!=seen:
        print(f"MODULE\t{mod}")
        open(dd+'/temp/.bash-module-notified','w',encoding='utf-8').write(str(mod))
upd=c.get('update') or []
add=c.get('added') or []
rm=c.get('removed') or []
ren=[]
for r in (c.get('renamed') or []):
    if isinstance(r,(list,tuple)) and len(r)==2: ren.append([str(r[0]),str(r[1])])
    else: ren.append([str(r),''])
if upd or add or rm or ren:
    print("TPL\x1fupdate_info\x1f"+json.dumps({"Update":upd,"Added":add,"Removed":rm,"Renamed":[[a,b] for a,b in ren]},ensure_ascii=False))
if add or rm:
    c['added']=[]; c['removed']=[]
    json.dump(c,open(p,'w',encoding='utf-8'))
PYEOF
)"
    [[ -n "$out" ]] && while IFS= read -r line; do
        if [[ "$line" == MODULE$'\t'* ]]; then
            _psc_tpl module.update "{\"NewVersion\":\"${line#*$'\t'}\"}"
            echo
        elif [[ "$line" == TPL$'\x1f'* ]]; then
            line="${line#*$'\x1f'}"
            _psc_tpl "${line%%$'\x1f'*}" "${line#*$'\x1f'}" && echo
        else
            printf '%s\n' "$line"
        fi
    done <<< "$out"
}

# --- trigger key binding ---------------------------------------------------------
# The trigger key is read from settings.json `config.trigger_key` (default Tab) and mapped to a readline key sequence.
# Unknown names fall back to Tab.
_psc_read_trigger_key() {
    _psc_need_py || { print -n Tab 2>/dev/null || printf Tab; return; }
    local s="$PSCOMPLETIONS_DATA_DIR/settings.json"
    [[ -f "$s" ]] || { echo Tab; return; }
    _psc_py -S - "$s" <<'PYEOF' 2>/dev/null || echo Tab
import json,sys
try:
    c=json.load(open(sys.argv[1],encoding='utf-8')).get('config',{}) or {}
    print(c.get('trigger_key') or 'Tab')
except Exception:
    print('Tab')
PYEOF
}

_psc_bind_trigger() {
    local name="${1:-Tab}" seq
    case "$name" in
        Tab) seq='\t' ;;
        Shift+Tab) seq='\e[Z' ;;
        Ctrl+Space) seq='\C-@' ;;
        Ctrl+[A-Za-z]) seq='\C-'"${name#Ctrl+}" ;;
        Alt+[A-Za-z]) seq='\e'"${name#Alt+}" ;;
        *) echo "[PSCompletions] unsupported trigger_key '$name', using Tab." >&2; seq='\t' ;;
    esac
    bind -x "\"$seq\": _psc_complete" 2>/dev/null
}

if [[ $- == *i* ]]; then
    _psc_bind_trigger "$(_psc_read_trigger_key)"
fi
