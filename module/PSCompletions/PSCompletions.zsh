#!/usr/bin/env zsh
# PSCompletions zsh bridge.
# User setup is one line in ~/.zshrc (`<module>` = the PSCompletions module dir):
#   source <module>/PSCompletions.zsh
# Requires: zsh 5.0+, Python 3.8+ on PATH (`python3`/`python`; the version is asserted either way).
# Binaries resolve next to this script
# (module/PSCompletions/bin/<platform>-<arch>, shipped in the module package),
# next to this file. Missing dependencies print one clear error on load.
#   PSCOMPLETIONS_DATA_DIR  override the data dir

# Guard: refuse to load when sourced by the wrong shell.
if [[ -z "${ZSH_VERSION:-}" ]]; then
    echo "[PSCompletions] PSCompletions.zsh is the zsh bridge; source the bridge matching your shell instead (PSCompletions.<shell>)." >&2
    return 0
fi

# Guard: this is a library, not a program. `zsh PSCompletions.zsh` would define the functions
# in a throwaway child and change nothing, so say so instead of failing silently. A sourced
# file reports a `:file` component in ZSH_EVAL_CONTEXT; a run does not.
if [[ "${ZSH_EVAL_CONTEXT:-toplevel}" != *:file* ]]; then
    echo "[PSCompletions] PSCompletions.zsh is a library, not a program. Add this to ~/.zshrc:" >&2
    echo "[PSCompletions]     source \"${${(%):-%x}:A}\"" >&2
    exit 1
fi

[[ -n "${_PSC_LOADED:-}" ]] && return 0
_PSC_LOADED=1

# --- dependency check (loud once, on load) -----------------------------------
_PSC_DEPS_OK=1
autoload -Uz is-at-least 2>/dev/null
if ! is-at-least 5.0 "${ZSH_VERSION:-0}"; then
    print -u2 "[PSCompletions] zsh 5.0+ required (found ${ZSH_VERSION:-unknown})."
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
# Cache the *absolute path*, not the bare name: a later PATH change (a prompt
# framework, mise/brew shellenv ordering, …) then cannot break the bridge.
_PSC_PY=""
for _py in python3 python; do
    _py_path="$(command -v "$_py" 2>/dev/null)" || continue
    if [[ -n "$_py_path" ]] && "$_py_path" -c 'import sys; assert sys.version_info >= (3, 8)' 2>/dev/null; then
        _PSC_PY="$_py_path"
        break
    fi
done
unset _py _py_path
if [[ -z "$_PSC_PY" ]]; then
    echo "[PSCompletions] python 3.8+ not found on PATH at shell start; the bridge cannot run." >&2
    echo "[PSCompletions] install python3 (or make it available before sourcing this file)." >&2
    _PSC_DEPS_OK=0
fi

# --- locations ---------------------------------------------------------------
_psc_bridge_dir=${${(%):-%x}:A:h}
_psc_arch="$(uname -m)"
case "$_psc_arch" in
    x86_64|amd64) _psc_arch=x64 ;;
    aarch64|arm64) _psc_arch=arm64 ;;
esac
_psc_platform="$(uname -s)"
case "$_psc_platform" in
    Linux*) _psc_platform=linux ;;
    Darwin*) _psc_platform=darwin ;;
    MINGW*|MSYS*|CYGWIN*) _psc_platform=windows ;;
esac
_psc_ext=""
[[ "$_psc_platform" == windows ]] && _psc_ext=".exe"
_PSC_BIN_DIR="$_psc_bridge_dir/bin/$_psc_platform-$_psc_arch"
# Default data dir mirrors the PowerShell module's per-platform default, so the
# shell bridge and the module share one data dir (completions, settings, index).
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

# Engine-facing platform for `terminal.platform`: never `windows` from zsh.
_psc_engine_platform=linux
[[ "$_psc_platform" == darwin ]] && _psc_engine_platform=macos

# High-resolution clock for temp-file ids (no subprocess).
zmodload zsh/datetime 2>/dev/null

typeset -gA _PSC_ALIAS=()   # trigger word -> completion
typeset -gA _PSC_CFG=()     # flat module config
typeset -gA _PSC_LANGCACHE=()
typeset -gA _PSC_HOOKS=()   # cmd -> 0/1 hooks gate
_PSC_INIT_OK=0
_PSC_BIN_WARNED=0

# --- seed the bundled psc completion (offline first run) ----------------------
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
_psc_init() {
    (( _PSC_DEPS_OK )) || return 1
    (( _PSC_INIT_OK )) && return 0
    _PSC_ALIAS=(); _PSC_CFG=(); _PSC_LANGCACHE=(); _PSC_HOOKS=()
    if [[ ! -x "$_PSC_MENU" || ! -x "$_PSC_BIN" ]]; then
        if [[ -f "$_PSC_MENU" && -f "$_PSC_BIN" ]]; then
            chmod +x "$_PSC_MENU" "$_PSC_BIN" 2>/dev/null
        fi
        if [[ ! -x "$_PSC_MENU" || ! -x "$_PSC_BIN" ]]; then
            if (( ! _PSC_BIN_WARNED )); then
                print -u2 "[PSCompletions] binaries missing under $_PSC_BIN_DIR (want psc + psc-menu)."
                _PSC_BIN_WARNED=1
            fi
            return 1
        fi
    fi
    local tmp="$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p "$tmp" 2>/dev/null
    _psc_seed_psc
    local out="$tmp/psc-init-$$.json"
    local lang=en-US
    case "${LANG:-}" in zh*|ZH*) lang=zh-CN ;; esac
    "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "--language=$lang" init --result "$out" 2>/dev/null || return 1
    [[ -f "$out" ]] || return 1
    local dump
    dump="$("$_PSC_PY" -S - "$out" <<'PYEOF'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
for k,v in (d.get('aliasMap') or {}).items():
    sys.stdout.write(f"A\x1f{k}\x1f{v}\x1f")
c=d.get('data',{}).get('config',{}) or {}
for k,v in c.items():
    if k=='completion': continue
    if isinstance(v,(dict,list)): continue
    sys.stdout.write(f"C\x1f{k}\x1f{v}\x1f")
PYEOF
)" || return 1
    local kind k v
    while IFS= read -r -d $'\x1f' kind && IFS= read -r -d $'\x1f' k && IFS= read -r -d $'\x1f' v; do
        if [[ "$kind" == A ]]; then _PSC_ALIAS[$k]="$v"; else _PSC_CFG[$k]="$v"; fi
    done <<< "$dump"
    rm -f "$out"
    _PSC_INIT_OK=1
}

# Per-completion manifest language: per-completion config -> module -> declared[0].
# Resolution reads settings.json itself: the _PSC_CFG cache is only filled by
# _psc_init (first Tab), and `psc` can run before that — the module language must not
# depend on whether the menu has been triggered yet.
_psc_lang() {
    _psc_need_py || return 1
    local cmd="$1"
    [[ -n "${_PSC_LANGCACHE[$cmd]:-}" ]] && { printf '%s' "${_PSC_LANGCACHE[$cmd]}"; return; }
    local l
    l="$("$_PSC_PY" -S - "$PSCOMPLETIONS_DATA_DIR" "$cmd" "${_PSC_CFG[language]:-}" <<'PYEOF'
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
    _PSC_LANGCACHE[$cmd]="${l:-en-US}"
    printf '%s' "${_PSC_LANGCACHE[$cmd]}"
}

# Hooks gate: file exists and not disabled (psc itself always runs). Echoes 0/1.
_psc_hooks_enabled() {
    _psc_need_py || return 1
    local cmd="$1"
    [[ -n "${_PSC_HOOKS[$cmd]:-}" ]] && { printf '%s' "${_PSC_HOOKS[$cmd]}"; return; }
    local hooks="$PSCOMPLETIONS_DATA_DIR/completions/$cmd/hooks.lua"
    if [[ ! -f "$hooks" ]]; then _PSC_HOOKS[$cmd]=0; print -n 0; return; fi
    if [[ "$cmd" != psc ]]; then
        local eh
        eh="$("$_PSC_PY" -S - "$PSCOMPLETIONS_DATA_DIR" "$cmd" <<'PYEOF'
import json,sys,os
try:
    s=json.load(open(os.path.join(sys.argv[1],'settings.json'),encoding='utf-8'))
    v=(s.get('config') or {}).get('completion',{}).get(sys.argv[2],{}).get('enable_hooks',1)
    print(0 if v==0 or v is False else 1)
except Exception:
    print(1)
PYEOF
)"
        if (( ! eh )); then _PSC_HOOKS[$cmd]=0; print -n 0; return; fi
    fi
    _PSC_HOOKS[$cmd]=1
    print -n 1
}

# --- tokenizer (matches the engine's grammar `(?:"[^"]*"|'[^']*'|\S)+`) --------
_psc_tokens() {
    local s="$1"
    local re=$'^[[:space:]]*("[^"]*"|\'[^\']*\'|[^[:space:]]+)(.*)$'
    reply=()
    while [[ -n "$s" && "$s" =~ $re ]]; do
        reply+=("$match[1]")
        s="$match[2]"
    done
}

# --- Tab widget ---------------------------------------------------------------
_psc_complete() {
    _psc_init || return 1
    local before="$LBUFFER"
    [[ -n "$before" ]] || return 1
    # A separator ends the command being edited: what follows it is a fresh command line, so its
    # own command word and tokens are what the menu completes. `before` stays whole — the word
    # offsets below are absolute.
    local seg; seg="$(_psc_segment "$before")"
    local -a toks
    _psc_tokens "$seg"
    toks=("${reply[@]}")
    (( ${#toks} )) || return 1
    local first="${toks[1]}"
    case "${(L)first}" in
        *.exe|*.cmd|*.bat) first="${first%.*}"; toks[1]="$first" ;;
    esac
    if [[ "$first" == sudo && ${#toks} -gt 1 ]]; then
        local wrapped="${toks[2]}"
        case "${(L)wrapped}" in *.exe|*.cmd|*.bat) wrapped="${wrapped%.*}" ;; esac
        if [[ -n "${_PSC_ALIAS[$wrapped]:-}" ]]; then
            toks=("${toks[2,-1]}")
            toks[1]="$wrapped"
            first="$wrapped"
        fi
    fi
    [[ "$first" == *[\*\?]* ]] && return 1
    local cmd="${_PSC_ALIAS[$first]:-}"
    # A path-shaped pending token goes to the shell's own completion even for an
    # installed command (mirrors the PowerShell/bash bridge).
    local last="" p path_like=0
    if [[ -z "$cmd" || "$before" != *" " ]]; then
        [[ "$before" != *" " ]] && last="${toks[-1]}"
        p="${last#[\"\']}"
        case "$p" in
            /*|./*|../*|\~/*) path_like=1 ;;
            \\*|.\\*|..\\*|\~\\*) path_like=1 ;;
            [A-Za-z]:[/\\]*) path_like=1 ;;
        esac
        # `git<Tab>` — the command word itself is still being completed — must offer command
        # names, not git's subcommands: build only once that word is finished (trailing space)
        # or an argument already exists (2+ tokens), the PS bridge's `isSpaceTab or count > 1`.
        if [[ -z "$cmd" ]] || (( path_like )) || { [[ "$before" != *" " && ${#toks} -eq 1 ]]; }; then
            _psc_native "$before" "${toks[@]}"
            return $?
        fi
    fi
    local last_complete=0
    [[ "$before" == *" " ]] && last_complete=1
    # arg_tokens: every token after the command word — the *pending* one included, with
    # `treat_last_as_complete` saying whether it is finished (see the bash bridge's comment).
    local -a args
    local n=${#toks} i
    for (( i = 2; i <= n; i++ )); do args+=("${toks[i]}"); done
    _psc_build_menu "$cmd" "$last_complete" "${args[@]}"
}

# --- build-mode menu ---------------------------------------------------------
_psc_write_input() {
    _psc_need_py || return 1
    # input.json via python (single writer: quoting-safe). Shared with the tests.
    local in="$1" cmd="$2" last_complete="$3" manifest="$4" has_hooks="$5"
    local cx="$6" cy="$7" w="$8" h="$9"
    shift 9
    PSC_IN="$in" PSC_CMD="$cmd" PSC_LAST="$last_complete" PSC_MANIFEST="$manifest" \
    PSC_HOOKS="$has_hooks" PSC_CWD="$PWD" PSC_DATA="$PSCOMPLETIONS_DATA_DIR" \
    PSC_CX="$cx" PSC_CY="$cy" PSC_W="$w" PSC_H="$h" PSC_HIST="$(_psc_hist)" \
    PSC_PLATFORM="$_psc_engine_platform" \
    "$_PSC_PY" -S - "$@" <<'PYEOF'
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
  "data":data,"dir":{"completions":dd+"/completions","cache":dd+"/temp/cache","log":""},"file":{"settings":dd+"/settings.json","completions":dd+"/temp/completions.json"},
 },
 "config":menu,
 "terminal":{"cursor":{"x":int(e['PSC_CX']),"y":int(e['PSC_CY'])},
  "buffer":{"w":int(e['PSC_W']),"h":int(e['PSC_H'])},
  "window":{"top":0,"h":int(e['PSC_H'])},"platform":e.get('PSC_PLATFORM','linux')},
 "dir":{"data":e['PSC_DATA'],"order":e['PSC_DATA']+"/temp/order","menu":e['PSC_DATA']+"/temp/menu"},
}
# Ranking is a pair: the build-context block is the channel the engine needs before it
# consults the history block. Keep both tied to one switch: with the key off neither is
# passed, which is what makes `enable_sort_by_history=0` really stop ranking.
if top:
    inp["build"]["order"] = border
    inp["order"] = top
json.dump(inp,open(e['PSC_IN'],'w',encoding='utf-8'))
PYEOF
}

_psc_build_menu() {
    local cmd="$1" last_complete="$2"; shift 2
    local lang manifest has_hooks
    lang="$(_psc_lang "$cmd")" || return 1
    manifest="$PSCOMPLETIONS_DATA_DIR/completions/$cmd/language/$lang.json"
    has_hooks="$(_psc_hooks_enabled "$cmd")"
    local tmp="$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p "$tmp" 2>/dev/null
    local _t=${EPOCHREALTIME//./} id="${_t}$$"
    local in="$tmp/psc-menu-$id-input.json" out="$tmp/psc-menu-$id-output.json"
    local cx=0 cy=0 w=${COLUMNS:-120} h=${LINES:-30}
    local line_head="$LBUFFER"
    if [[ "$line_head" == *$'\n'* ]]; then
        local tail="${line_head##*$'\n'}"
        cx=${#tail}
    else
        cx=${#line_head}
    fi
    _psc_write_input "$in" "$cmd" "$last_complete" "$manifest" "$has_hooks" "$cx" "$cy" "$w" "$h" "$@" || return 1
    # Leave the editor's display so the TUI can own the terminal, then repaint.
    zle -I 2>/dev/null
    local st words nospace   # `status` is read-only in zsh
    _psc_spawn "$in" "$out"
    st="$_PSC_SPAWN_STATUS" words="$_PSC_SPAWN_WORDS" nospace="$_PSC_SPAWN_NOSPACE"
    rm -f "$in" "$out"
    zle reset-prompt 2>/dev/null
    if [[ "$st" == min_area ]]; then
        local hint
        hint="$(_psc_tpl min_area 2>/dev/null)" || hint="# terminal too small for menu"
        LBUFFER="${LBUFFER} ${hint%%$'\n'*}"
        return 1
    fi
    [[ "$st" == selected || "$st" == input ]] || return 1
    _psc_apply "$words" "$nospace"
}

# Result channel: sets _PSC_SPAWN_{STATUS,WORDS,NOSPACE}. It cannot print: the
# caller must run it in this shell, and `$( )` / `<( )` would fork it into a process
# group of its own (see below) and put the menu back in the stopped state.
_psc_spawn() {
    local in="$1" out="$2"
    _PSC_SPAWN_STATUS=cancel _PSC_SPAWN_WORDS='' _PSC_SPAWN_NOSPACE=0 _PSC_SPAWN_INDEX=''
    # The menu must own the terminal: its TUI reads /dev/tty, and a read from a
    # background process group is stopped by SIGTTIN. Bash's coproc happens to stay in
    # the shell's group; zsh gives a job its own group unless MONITOR is off, and the
    # call itself must stay in this shell — behind a process substitution the subshell
    # gets a group of its own. Without this the menu starts, is stopped, and the widget
    # looks like it did nothing. (localoptions: MONITOR is restored on return.)
    setopt localoptions no_monitor
    coproc { "$_PSC_MENU" "$in" --result "$out" 2>&1 1>/dev/tty }
    local pid=$!
    local elapsed=0 line
    while kill -0 $pid 2>/dev/null; do
        if read -t 1 -p line; then
            elapsed=0  # any stderr line (HBT) resets the watchdog
        else
            (( elapsed++ ))
        fi
        if (( elapsed >= 30 )); then
            kill -9 $pid 2>/dev/null
            printf '%s' "$_PSC_RESET_TERM" > /dev/tty
            _psc_flush_tty
            wait $pid 2>/dev/null
            return 0
        fi
    done
    wait $pid 2>/dev/null
    [[ -f "$out" ]] || return 0
    local r
    r="$("$_PSC_PY" -S - "$out" <<'PYEOF'
import json,sys
try: r=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: print('cancel\t\t\t'); raise SystemExit
s=r.get('status')
if s=='selected': print(f"selected\t{r.get('completion_text','')}\t{'1' if r.get('nospace') else '0'}\t{r.get('index','')}")
elif s=='input': print(f"input\t{r.get('text','')}\t0\t")
else: print(f"{s}\t\t\t")
PYEOF
)"
    local st words nospace idx
    IFS=$'\t' read -r st words nospace idx <<< "$r"
    _PSC_SPAWN_STATUS="$st" _PSC_SPAWN_WORDS="$words" _PSC_SPAWN_NOSPACE="$nospace" _PSC_SPAWN_INDEX="$idx"
}

# Terminal modes the menu turns on through crossterm (EnableMouseCapture, EnterAlternateScreen,
# cursor::Hide, bracketed paste). A clean exit turns them off itself; a force-killed menu cannot,
# so the watchdog writes this itself — without the mouse modes the terminal keeps reporting
# `ESC [ < b;x;y M` as literal input and the shell becomes unusable.
_PSC_RESET_TERM=$'\e[?1006l\e[?1003l\e[?1002l\e[?1000l\e[?1015l\e[?1049l\e[?25h\e[?2004l'

# The terminal queues mouse reports (SGR `ESC [ < b;x;y M`) while the menu is up; the few
# bytes still in the tty input buffer when a force-killed menu dies are read by the shell as
# literal input. Discard them after restoring the modes — the menu owed the user a clean line.
_psc_flush_tty() {
    "$_PSC_PY" -S -c 'import os,termios
try:
    fd=os.open("/dev/tty",os.O_RDONLY|os.O_NONBLOCK)
    termios.tcflush(fd,termios.TCIFLUSH)
    os.close(fd)
except Exception:
    pass' 2>/dev/null
}

# 1-based start of the word under the cursor. A word boundary is an unquoted, unescaped
# whitespace, so `az\ zdir` stays one word: the naive `${before##* }` split cut at the
# escaped space and concatenated the pick after the old text instead of replacing it.
# The command being edited: everything after the last unquoted separator (`|`, `;`, `&`, `&&`,
# `||`). A separator ends a command, so what follows it is a fresh command line whose own command
# word and tokens are what the menu completes (`git status | grep <Tab>` completes `grep`).
# Quotes (and `\`) hide a separator; `>&` and `&>` are redirections, not separators; an empty
# result means there is nothing to complete here, so the caller falls back to the host.
_psc_segment() {
    local s="$1" out='' c
    local -i i=1 n=${#s} q=0
    while (( i <= n )); do
        c="${s[i]}"
        if (( q != 1 )) && [[ "$c" == '\' ]]; then
            out+="${s[i,i+1]}"
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
                    if [[ "${s[i+1]}" == '>' ]] || { (( i > 1 )) && [[ "${s[i-1]}" == '>' ]]; }; then
                        out+="$c"
                    else
                        out=''
                        [[ "${s[i+1]}" == '&' ]] && (( i++ ))
                    fi ;;
                *) out+="$c" ;;
            esac
        else
            out+="$c"
        fi
        (( i++ ))
    done
    # The leading whitespace belongs to the separator, not to the new command.
    print -r -- "${out#"${out%%[![:space:]]*}"}"
}

_psc_word_start() {
    local s="$1" c
    local -i i=1 n=${#s} start=1 q=0
    while (( i <= n )); do
        c="${s[i]}"
        if (( q != 1 )) && [[ "$c" == '\' ]]; then
            (( i += 2 )); continue
        fi
        if [[ "$c" == "'" ]]; then
            if (( q == 0 )); then q=1; elif (( q == 1 )); then q=0; fi
        elif [[ "$c" == '"' ]]; then
            if (( q == 0 )); then q=2; elif (( q == 2 )); then q=0; fi
        elif (( q == 0 )) && [[ "$c" == ' ' || "$c" == $'\t' ]]; then
            start=$(( i + 1 ))
        fi
        (( i++ ))
    done
    print -r -- "$start"
}

_psc_apply() {
    local text="$1" nospace="${2:-0}" before="$LBUFFER" after="$RBUFFER"
    local start=$(( ${#before} + 1 ))
    if [[ -n "$before" && "${before[-1]}" != " " ]]; then
        start=$(( $(_psc_word_start "$before") ))
    fi
    local re_word=$'^("[^"]*"|\'[^\']*\'|[^[:space:]]+)'
    local re_after_word=$'^[[:space:]]+[^[:space:]]'
    local consume=0 tail="$after"
    if [[ -n "$after" ]]; then
        local c0="${after[1]}"
        if [[ "$c0" != " " && "$c0" != $'\t' && "$c0" != '"' && "$c0" != "'" ]]; then
            if [[ "$after" =~ $re_word ]]; then
                consume=${#match[1]}
                tail="${after[$(( consume + 1 )),-1]}"
            fi
        fi
    fi
    local suffix=" "
    [[ "$text" == *= || "$nospace" == 1 ]] && suffix=""
    [[ "${_PSC_CFG[enable_append_space]:-1}" == 0 ]] && suffix=""
    [[ "$after" =~ $re_after_word ]] && suffix=""
    local first_after="${after[1]}" last_text="${text[-1]}"
    if [[ ( "$first_after" == '"' || "$first_after" == "'" ) && "$last_text" == "$first_after" ]]; then
        text="${text[1,-2]}"
    fi
    local head=""
    (( start > 1 )) && head="${before[1,$(( start - 1 ))]}"
    LBUFFER="${head}${text}${suffix}"
    RBUFFER="$tail"
}

# --- native path: the shell's own completion ---------------------------------
# The native path has two branches (bridge.md §2): capture the host's candidates and
# render them in our menu, or step aside and let the host draw its own. zsh's compsys
# has no "give me the candidate list" API, so the capture runs the real completion and
# intercepts `compadd` — what compsys would have drawn, with `-d` giving the
# per-candidate descriptions we surface as item tips. All of it is compsys-internal:
# the parser ignores what it does not model rather than guessing.

# Value-taking short options of compadd (zshcompwid(1)); everything else is a flag.
_psc_compadd_valopt() {
    case "$1" in
        P|p|S|s|i|I|o|J|V|X|x|r|R|W|F|d|M|E|O|A|D) return 0 ;;
    esac
    return 1
}

# Parse one compadd call (zshcompwid(1): -a/-k take array *names* after the options,
# -P/-S are inserted and displayed, -p/-s inserted only, -d carries descriptions,
# -O/-A/-D store matches elsewhere so they are not candidates). Appends to
# _PSC_CAND_COMP / _PSC_CAND_DISP / _PSC_CAND_TIP.
_psc_compadd_parse() {
    # Every local is `_psc_`-prefixed on purpose: -a/-k/-d name a parameter that is
    # resolved by dynamic scope, so a local here would shadow the caller's array.
    # Every local also carries a value: re-running a valueless `local` (which happens
    # for anything declared inside the loops below) makes zsh print `name=value`.
    local -a _psc_args=("$@") _psc_descs=()
    local _psc_i=1 _psc_n=${#_psc_args}
    local _psc_mode=literal _psc_collect=1
    local _psc_vpre='' _psc_vsuf='' _psc_hpre='' _psc_hsuf=''
    # Single pass: options are consumed *with* their values, so a value that itself
    # looks like an option (`-J -default-`) is never mistaken for one. Short options
    # may be clustered (`-ld descs` = `-l -d descs`, as `_git` passes them).
    while (( _psc_i <= _psc_n )); do
        local _psc_w="${_psc_args[_psc_i]}"
        [[ "$_psc_w" == -* ]] || break
        if [[ "$_psc_w" == '-' || "$_psc_w" == '--' ]]; then
            _psc_i=$((_psc_i+1)); break
        fi
        local -a _psc_chars=()
        if (( ${#_psc_w} == 2 )); then
            _psc_chars=("${_psc_w[2,-1]}")
        else
            _psc_chars=("${(s::)_psc_w[2,-1]}")
        fi
        local _psc_k=1 _psc_cn=${#_psc_chars} _psc_ch='' _psc_val='' _psc_hadval=0
        while (( _psc_k <= _psc_cn )); do
            _psc_ch="${_psc_chars[_psc_k]}"
            _psc_val='' _psc_hadval=0
            if _psc_compadd_valopt "$_psc_ch"; then
                if (( _psc_k < _psc_cn )); then
                    _psc_val="${(j::)_psc_chars[_psc_k+1,-1]}"
                    _psc_k=$_psc_cn
                    _psc_hadval=1
                elif (( _psc_i < _psc_n )); then
                    _psc_i=$((_psc_i+1))
                    _psc_val="${_psc_args[_psc_i]}"
                    _psc_hadval=1
                fi
            fi
            case "$_psc_ch" in
                a) _psc_mode=array ;;
                k) _psc_mode=assoc ;;
                O|A|D) _psc_collect=0 ;;
                d) if (( _psc_hadval )); then
                       if [[ "$_psc_val" == \(*\) ]]; then _psc_descs=("${=_psc_val[2,-2]}")
                       else _psc_descs=("${(@P)_psc_val}"); fi
                   fi ;;
                P) [[ -z "$_psc_vpre" ]] && _psc_vpre="$_psc_val" ;;
                p) [[ -z "$_psc_hpre" ]] && _psc_hpre="$_psc_val" ;;
                S) [[ -z "$_psc_vsuf" ]] && _psc_vsuf="$_psc_val" ;;
                s) [[ -z "$_psc_hsuf" ]] && _psc_hsuf="$_psc_val" ;;
            esac
            _psc_k=$((_psc_k+1))
        done
        _psc_i=$((_psc_i+1))
    done
    (( _psc_collect )) || return 0
    local -a _psc_cands=()
    case "$_psc_mode" in
        array) while (( _psc_i <= _psc_n )); do _psc_cands+=("${(@P)_psc_args[_psc_i]}"); _psc_i=$((_psc_i+1)); done ;;
        assoc) while (( _psc_i <= _psc_n )); do _psc_cands+=("${(@kP)_psc_args[_psc_i]}"); _psc_i=$((_psc_i+1)); done ;;
        *)     while (( _psc_i <= _psc_n )); do _psc_cands+=("${_psc_args[_psc_i]}"); _psc_i=$((_psc_i+1)); done ;;
    esac
    local _psc_c _psc_k=0
    for _psc_c in "${_psc_cands[@]}"; do
        _psc_k=$((_psc_k+1))
        _PSC_CAND_COMP+=("${_psc_hpre}${_psc_vpre}${_psc_c}${_psc_vsuf}${_psc_hsuf}")
        _PSC_CAND_DISP+=("${_psc_vpre}${_psc_c}${_psc_vsuf}")
        _PSC_CAND_TIP+=("${_psc_descs[_psc_k]:-}")
    done
}

# Run the host completion with compadd intercepted. Fills _PSC_CAND_*; returns 1 when
# compsys is not loaded (nothing to capture — the caller steps aside instead).
_psc_capture() {
    (( $+functions[_main_complete] )) || return 1
    _PSC_CAND_COMP=() _PSC_CAND_DISP=() _PSC_CAND_TIP=()
    local -i _psc_saved_autolist=${options[autolist]} _psc_saved_ambiguous=${options[listambiguous]}
    local _psc_saved_buffer="$BUFFER" _psc_saved_cursor="$CURSOR"
    local _psc_iprefix=''
    unsetopt autolist listambiguous 2>/dev/null
    compadd() {
        # IPREFIX is compsys' own "already on the line, not part of the match" text —
        # the display drops it (zsh lists the same way); the completion text keeps it.
        [[ -z "$_psc_iprefix" ]] && _psc_iprefix="$IPREFIX"
        _psc_compadd_parse "$@"
        builtin compadd "$@"
    }
    zle expand-or-complete
    unfunction compadd 2>/dev/null
    BUFFER="$_psc_saved_buffer" CURSOR="$_psc_saved_cursor"
    (( _psc_saved_autolist )) && setopt autolist 2>/dev/null
    (( _psc_saved_ambiguous )) && setopt listambiguous 2>/dev/null
    (( ${#_PSC_CAND_COMP} )) || return 1
    local _psc_i
    for (( _psc_i = 1; _psc_i <= ${#_PSC_CAND_COMP}; _psc_i++ )); do
        [[ -n "$_psc_iprefix" && "${_PSC_CAND_COMP[_psc_i]}" == "$_psc_iprefix"* ]] && \
            _PSC_CAND_DISP[_psc_i]="${_PSC_CAND_COMP[_psc_i]:${#_psc_iprefix}}"
        # compsys escapes names for insertion (`az\ zdir`); the menu should show the
        # plain name, as zsh's own list does.
        _PSC_CAND_DISP[_psc_i]="${(Q)_PSC_CAND_DISP[_psc_i]}"
        # `_describe` without explicit descriptions passes the candidate text as its
        # own description; that is not a tip, so drop it.
        [[ "${_PSC_CAND_TIP[_psc_i]}" == "${_PSC_CAND_COMP[_psc_i]}" ||
           "${_PSC_CAND_TIP[_psc_i]}" == "${_PSC_CAND_DISP[_psc_i]}" ]] && _PSC_CAND_TIP[_psc_i]=''
    done
    return 0
}

# Items mode: render host candidates in our menu. Sets _PSC_ITEMS_PICK to the chosen
# completion text (empty when nothing was chosen). Parallel arrays: display /
# completion / tip (the tip comes from compadd -d, so real completions show their
# descriptions here).
# Items mode: the filter is the engine's call, so the bridge only forwards the line's tokens —
# `arg_tokens` (the pending one included) and whether it is already finished. The engine derives
# `initial_filter` and ignores it when it matches nothing (a path slot displays leaves).
_psc_items_menu() {
    local cmd="${1:-}" args="${2:-}" last="${3:-0}"
    local tmp="$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p "$tmp" 2>/dev/null
    local _t=${EPOCHREALTIME//./} id="${_t}$$"
    local in="$tmp/psc-items-$id-input.json" out="$tmp/psc-items-$id-output.json"
    _PSC_ITEMS_PICK=''
    local _psc_items='' _psc_i
    for (( _psc_i = 1; _psc_i <= ${#_PSC_CAND_DISP}; _psc_i++ )); do
        _psc_items+="${_PSC_CAND_DISP[_psc_i]}"$'\x1e'"${_PSC_CAND_COMP[_psc_i]}"$'\x1e'"${_PSC_CAND_TIP[_psc_i]}"$'\x1f'
    done
    # The candidate payload travels in a file: a compsys capture can run to thousands of
    # entries and an environment variable would blow ARG_MAX (the interactive pass hit that
    # with `pyt` + Tab: "_psc_items_menu:11: argument list too long").
    local _psc_cands="$tmp/psc-items-$id-cands.txt"
    print -rn -- "$_psc_items" > "$_psc_cands"
    PSC_IN="$in" PSC_CANDS_FILE="$_psc_cands" PSC_CMD="$cmd" PSC_ARGS="$args" PSC_LAST="$last" \
    PSC_DATA="$PSCOMPLETIONS_DATA_DIR" \
    PSC_HIST="$(_psc_hist)" PSC_PLATFORM="$_psc_engine_platform" \
    PSC_W="${COLUMNS:-120}" PSC_H="${LINES:-30}" \
    "$_PSC_PY" -S <<'PYEOF' || return 1
import json,os,urllib.parse
e=os.environ
def truthy(v,d=0):
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
 "filter_hint":hint,"filter_hint_stale":hint_stale,
 "flags":{"enable_list_loop":truthy(cfg.get('enable_list_loop'),1),
  "filter_mode":cfg.get('filter_mode','wildcard'),
  "enable_apply_when_single":truthy(cfg.get('enable_apply_when_single')),
  "enable_apply_when_no_match":truthy(cfg.get('enable_apply_when_no_match')),
  "show_mode":cfg.get('show_mode','auto'),
  "color_focus":cfg.get('color_focus','red'),
  "color_match":cfg.get('color_match','cyan')},
 "context_switch":cfg.get('switch','~'),"context_stay":cfg.get('stay','?'),
 "raw_config":{"completion":{},"global":{k:v for k,v in cfg.items() if not isinstance(v,(dict,list))},"default":{}},
}
items=[]
for rec in open(e['PSC_CANDS_FILE'],encoding='utf-8').read().split('\x1f'):
    if not rec: continue
    p=rec.split('\x1e')
    disp=p[0] if len(p)>0 else ''
    comp=p[1] if len(p)>1 and p[1] else disp
    tip=p[2] if len(p)>2 else ''
    items.append({"completion_text":comp,"list_item_text":disp or comp,"symbol":"",
     "tip":tip or None,"usage":None,"example":None,"result_type":None})
od=dd+'/temp/order'
h=int(e.get('PSC_H') or 30); w=int(e.get('PSC_W') or 120)
inp={"items":items,"config":menu,
 "terminal":{"cursor":{"x":0,"y":0},"buffer":{"w":w,"h":h},"window":{"top":0,"h":h},
  "platform":e.get('PSC_PLATFORM','linux')},
 "dir":{"data":dd,"order":od,"menu":dd+"/temp/menu"},
 "arg_tokens":[t for t in (e.get('PSC_ARGS') or '').split('\n') if t!=''],
 "treat_last_as_complete":e.get('PSC_LAST')=='1'}
if e.get('PSC_HIST') and truthy(cfg.get('enable_sort_by_history'),1):
    cmd=e['PSC_CMD']
    alias=settings.get('alias') or {}
    inp["order"]={"history":e['PSC_HIST'],"cmd":cmd,"aliases":alias.get(cmd) or [cmd],
     "path":od+'/'+urllib.parse.quote(cmd,safe='')+'.json'}
json.dump(inp,open(e['PSC_IN'],'w',encoding='utf-8'))
PYEOF
    zle -I 2>/dev/null
    _psc_spawn "$in" "$out"
    local st="$_PSC_SPAWN_STATUS" words="$_PSC_SPAWN_WORDS" idx="$_PSC_SPAWN_INDEX"
    rm -f "$in" "$out" "$_psc_cands"
    zle reset-prompt 2>/dev/null
    if [[ "$st" == min_area ]]; then
        local h
        h="$(_psc_tpl min_area 2>/dev/null)" || h="# terminal too small for menu"
        LBUFFER="${LBUFFER} ${h%%$'\n'*}"
        return 1
    fi
    # `input`: the filter text to apply (no-match auto-apply). Items answer by index, but a text
    # needs no index at all.
    if [[ "$st" == input ]]; then
        _PSC_ITEMS_PICK="$words"
        return 0
    fi
    [[ "$st" == selected && -n "$idx" ]] || return 1
    _PSC_ITEMS_PICK="${_PSC_CAND_COMP[$(( idx + 1 ))]}"
    [[ -n "$_PSC_ITEMS_PICK" ]]
}

# Candidates when the host completion has nothing to capture (no compinit at all, or no
# completion for this context): enumerate the way the bash bridge's compgen fallback
# does — command names in command position, otherwise path entries. Fills _PSC_CAND_*.
_psc_enumerate() {
    local _psc_before="$1"
    _PSC_CAND_COMP=() _PSC_CAND_DISP=() _PSC_CAND_TIP=()
    local _psc_cur=''
    [[ "$_psc_before" != *' ' ]] && _psc_cur="${_psc_before[$(_psc_word_start "$_psc_before"),-1]}"
    _psc_cur="${_psc_cur#[\"\']}"
    local -a _psc_hits=()
    if [[ "$_psc_before" != *' '* ]]; then
        local _psc_c=''
        for _psc_c in ${(k)commands}; do
            [[ -n "$_psc_cur" && "$_psc_c" != "$_psc_cur"* ]] && continue
            _psc_hits+=("$_psc_c")
        done
    else
        # Split the typed word into the part to keep and the segment being typed, so
        # the completion text rebuilds exactly what was typed (`al` → `alpha`, not
        # `./alpha`; `~/` stays `~/`).
        local _psc_pre='' _psc_base=''
        if [[ "$_psc_cur" == */ ]]; then
            _psc_pre="$_psc_cur"
        else
            _psc_base="${_psc_cur:t}"
            _psc_pre="${_psc_cur[1,$(( ${#_psc_cur} - ${#_psc_base} ))]}"
        fi
        local _psc_exp="$_psc_pre"
        [[ "$_psc_exp" == '~'* ]] && _psc_exp="$HOME${_psc_exp#\~}"
        local _psc_dir="${_psc_exp:-.}"
        [[ "$_psc_dir" == */ ]] && _psc_dir="${_psc_dir%/}"
        [[ -z "$_psc_dir" ]] && _psc_dir='/'
        local -a _psc_g=()
        if [[ -n "$_psc_base" ]]; then
            _psc_g=("$_psc_dir"/${~_psc_base}*(N))
        else
            _psc_g=("$_psc_dir"/*(N))
        fi
        local _psc_e=''
        for _psc_e in "${_psc_g[@]}"; do
            [[ -e "$_psc_e" || -L "$_psc_e" ]] || continue
            _psc_hits+=("${_psc_pre}${_psc_e:t}")
        done
    fi
    (( ${#_psc_hits} )) || return 1
    local _psc_h=''
    for _psc_h in "${_psc_hits[@]}"; do
        local _psc_disp="${_psc_h:t}"
        [[ -d "${_psc_h/#\~/$HOME}" ]] && _psc_disp="${_psc_disp}/"
        _PSC_CAND_COMP+=("$_psc_h")
        _PSC_CAND_DISP+=("$_psc_disp")
        _PSC_CAND_TIP+=('')
    done
    return 0
}

# History the engine can read: one command per line. With `setopt extended_history` zsh prefixes
# every entry with `: <begin>:<elapsed>;` *on the same line*, and the engine tokenizes each line
# as a command line — `:` would become the command, so ranking would silently stop reflecting
# reality. Hand it a normalised copy, rebuilt only when the source is newer; the strip is a no-op
# for a plain history file, so a wrong guess cannot do harm. Prints the path, or nothing.
_psc_hist() {
    local src="${HISTFILE:-}"
    [[ -n "$src" && -f "$src" ]] || return 0
    local dst="$PSCOMPLETIONS_DATA_DIR/temp/psc-zsh-history"
    mkdir -p "${dst:h}" 2>/dev/null
    if [[ ! -f "$dst" || "$src" -nt "$dst" ]]; then
        # sed exits 0 on an empty file; the guard is only for a write failure.
        sed -E 's/^: [0-9]+:[0-9]+;//' -- "$src" > "$dst" 2>/dev/null || true
        [[ -f "$dst" ]] || return 0
    fi
    print -n "$dst"
}

# History-rank host candidates through the engine's `--sort` pass (the bash bridge does
# the same): without it, native items keep compsys' own order and `enable_sort_by_history`
# would be silently ignored. Candidates are deduped by completion text first, because the
# ranking result is matched back by text.
_psc_sort_candidates() {
    local _psc_cmd="$1"; shift
    local -a _psc_toks=("$@")
    [[ "${_PSC_CFG[enable_sort_by_history]:-1}" == 1 ]] || return 0
    local _psc_hist_path
    _psc_hist_path="$(_psc_hist)"
    [[ -n "$_psc_hist_path" ]] || return 0
    local _psc_n=${#_PSC_CAND_COMP}
    (( _psc_n > 1 )) || return 0
    # dedupe by completion text
    typeset -A _psc_seen=()
    local -a _psc_dc=() _psc_dd=() _psc_dt=()
    local _psc_i=1
    for (( _psc_i = 1; _psc_i <= _psc_n; _psc_i++ )); do
        [[ -n "${_psc_seen[${_PSC_CAND_COMP[_psc_i]}]:-}" ]] && continue
        _psc_seen[${_PSC_CAND_COMP[_psc_i]}]=1
        _psc_dc+=("${_PSC_CAND_COMP[_psc_i]}")
        _psc_dd+=("${_PSC_CAND_DISP[_psc_i]}")
        _psc_dt+=("${_PSC_CAND_TIP[_psc_i]}")
    done
    (( ${#_psc_dc} > 1 )) || return 0
    local _psc_tmp="$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p "$_psc_tmp" 2>/dev/null
    local _psc_t=${EPOCHREALTIME//./} _psc_id="${_psc_t}$$"
    local _psc_in="$_psc_tmp/psc-sort-$_psc_id-in.json" _psc_out="$_psc_tmp/psc-sort-$_psc_id-out.json"
    local _psc_items='' _psc_tok=''
    for (( _psc_i = 1; _psc_i <= ${#_psc_dc}; _psc_i++ )); do
        _psc_items+="${_psc_dc[_psc_i]}"$'\x1e'"${_psc_dt[_psc_i]}"$'\x1f'
    done
    _psc_tok="$(printf '%s\n' "${_psc_toks[@]}")"
    # The candidate payload travels in a file: a compsys capture can run to thousands of
    # entries and an environment variable would blow ARG_MAX.
    local _psc_cands="$_psc_tmp/psc-sort-$_psc_id-cands.txt"
    print -rn -- "$_psc_items" > "$_psc_cands"
    PSC_IN="$_psc_in" PSC_ITEMS_FILE="$_psc_cands" PSC_TOKS="$_psc_tok" PSC_CMD="$_psc_cmd" \
    PSC_LAST="$([[ "$LBUFFER" == *' ' ]] && print -n 1 || print -n 0)" \
    PSC_DATA="$PSCOMPLETIONS_DATA_DIR" PSC_HIST="$_psc_hist_path" \
    "$_PSC_PY" -S <<'PYEOF' || return 0
import json,os,urllib.parse
e=os.environ
dd=e['PSC_DATA']
items=[]
for rec in open(e['PSC_ITEMS_FILE'],encoding='utf-8').read().split('\x1f'):
    if not rec: continue
    p=rec.split('\x1e')
    if not p[0]: continue
    items.append({"text":p[0], "tip":(p[1] if len(p)>1 and p[1] else None)})
cmd=e['PSC_CMD']
od=dd+'/temp/order'
q=urllib.parse.quote(cmd,safe='')
inp={"items":items,
     "tokens":[t for t in e['PSC_TOKS'].split('\n') if t!=''],
     "treat_last_as_complete":e['PSC_LAST']=='1',
     "order":{"cmd_order":od+'/'+q+'.json',
              "paths_order":od+'/_shared/_paths.json',
              "commands_order":od+'/_shared/_commands.json'}}
if e.get('PSC_HIST'):
    try: alias=(json.load(open(dd+'/settings.json',encoding='utf-8')).get('alias') or {})
    except Exception: alias={}
    inp["order"].update({"history":e['PSC_HIST'],"cmd":cmd,
                         "aliases":alias.get(cmd) or [cmd],"path":od+'/'+q+'.json'})
json.dump(inp,open(e['PSC_IN'],'w',encoding='utf-8'))
PYEOF
    "$_PSC_MENU" --sort "$_psc_in" --result "$_psc_out" >/dev/null 2>&1
    local _psc_ranked
    _psc_ranked="$("$_PSC_PY" -S - "$_psc_out" <<'PYEOF' 2>/dev/null
import json,sys
try: items=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: raise SystemExit(1)
for it in items:
    t=it.get('text')
    if t: print(t)
PYEOF
)"
    rm -f "$_psc_in" "$_psc_out" "$_psc_cands"
    [[ -n "$_psc_ranked" ]] || return 0
    typeset -A _psc_disp_of=() _psc_tip_of=()
    for (( _psc_i = 1; _psc_i <= ${#_psc_dc}; _psc_i++ )); do
        _psc_disp_of[${_psc_dc[_psc_i]}]="${_psc_dd[_psc_i]}"
        _psc_tip_of[${_psc_dc[_psc_i]}]="${_psc_dt[_psc_i]}"
    done
    local -a _psc_rc=() _psc_rd=() _psc_rt=()
    local _psc_line=''
    for _psc_line in ${(f)_psc_ranked}; do
        [[ -n "${_psc_disp_of[$_psc_line]:-}" || -n "${_psc_tip_of[$_psc_line]:-}" ]] || continue
        _psc_rc+=("$_psc_line")
        _psc_rd+=("${_psc_disp_of[$_psc_line]}")
        _psc_rt+=("${_psc_tip_of[$_psc_line]}")
    done
    if (( ${#_psc_rc} == ${#_psc_dc} )); then
        _PSC_CAND_COMP=("${_psc_rc[@]}")
        _PSC_CAND_DISP=("${_psc_rd[@]}")
        _PSC_CAND_TIP=("${_psc_rt[@]}")
    fi
    return 0
}

# Directory handling for a picked native candidate, mirroring the PS bridge's
# `handle_menu_output`: a **container never takes a trailing space** — the user is likely
# to keep completing inside it — and `enable_path_trailing_separator` only decides whether
# the separator itself is added. Result channel: _PSC_PICK_TEXT / _PSC_PICK_NOSPACE.
_psc_pick_text() {
    _PSC_PICK_TEXT="$1"
    _PSC_PICK_NOSPACE=0
    # The candidate may be escaped/quoted for insertion (`az\ zdir`, `'a b'`) — compsys
    # hands those to compadd — so unescape before asking the filesystem (`(Q)`).
    local _psc_path="${(Q)_PSC_PICK_TEXT}"
    [[ "$_psc_path" == '~'* ]] && _psc_path="$HOME${_psc_path#\~}"
    [[ -d "$_psc_path" ]] || return 0
    _PSC_PICK_NOSPACE=1
    if [[ "${_PSC_CFG[enable_path_trailing_separator]:-1}" == 1 ]]; then
        [[ "$_PSC_PICK_TEXT" != */ ]] && _PSC_PICK_TEXT="${_PSC_PICK_TEXT}/"
    fi
}

# Host menu: hand the current line to the shell's own completion (the "step aside"
# branch), used when neither capture nor our own enumeration produced candidates.
_psc_native() {
    local before="$1"; shift
    local -a toks=("$@")
    [[ "${_PSC_CFG[enable_native_completion]:-1}" == 1 ]] || return 1
    # Capture branch: compsys' own candidates, rendered in our menu (bridge.md §2 —
    # native is a data source, never a UI). Without compsys (a bare zsh) there is
    # nothing to capture, so enumerate the candidates ourselves — that is what makes
    # path completion still land in our menu. Hand-off is the last resort.
    if _psc_capture || _psc_enumerate "$before"; then
        _psc_sort_candidates "${toks[1]:-}" "${toks[@]}"
        if _psc_items_menu "${toks[1]:-}" "$(printf '%s\n' "${toks[@]}")" \
            "$([[ "$LBUFFER" == *' ' ]] && print -n 1 || print -n 0)"; then
            _psc_pick_text "$_PSC_ITEMS_PICK"
            _psc_apply "$_PSC_PICK_TEXT" "$_PSC_PICK_NOSPACE"
        fi
        return 0
    fi
    zle expand-or-complete
}

# --- static info templates ----------------------------------------------------
# Generic info-template renderer (design/templates.md).
# Usage: _psc_tpl <dotted.info.path> [context-json]
# Renders one `info` template through the engine (`psc tpl --version …`). The grammar and its
# implementation live there, so a bridge carries no renderer of its own. A missing binary or an
# unknown path fails, and the caller's `||` fallback takes over.
_psc_module_version() {
    # The module manifest beside the bridge is the one version source present in both a repo
    # checkout and an installed package (the package carries no `../version.json`).
    sed -n "s/.*ModuleVersion *= *'\([^']*\)'.*/\1/p" "$_psc_bridge_dir/PSCompletions.psd1" 2>/dev/null | head -1
}

_psc_tpl() {
    [[ -x "$_PSC_BIN" ]] || return 1
    local args=(--data "$PSCOMPLETIONS_DATA_DIR" tpl "$1")
    (( $# >= 2 )) && args+=(--ctx "$2")
    args+=(--version "$(_psc_module_version)")
    "$_PSC_BIN" "${args[@]}"
}

# --- `psc` management command -------------------------------------------------
# Run a management command that only prints a status line. The CLI's messages are plain
# text, so the color is the bridge's job — the same convention as the PS bridge's
# `_forward_psc`: success green, failure red (design/config-support.md).
# Data queries print exactly what the CLI renders: the CLI's text is the interface in every host,
# and `--json` is the machine contract. Only messages take color. A failed query still goes
# through the red path.
_psc_plain() {
    local _out
    if _out="$("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "$@" 2>/dev/null)"; then
        print -r -- "$_out"
        return 0
    fi
    _psc_run_status "$@"
}
_psc_run_status() {
    local out rc
    out="$("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "$@" 2>&1)"
    rc=$?
    if [[ -n "$out" ]]; then
        if (( rc == 0 )); then
            print -r -- $'\033[32m'"$out"$'\033[0m'
        else
            print -r -- $'\033[31m'"$out"$'\033[0m'
        fi
    fi
    return $rc
}

psc() {
    # A bare `local _arg` echoes `_arg=<value>` in zsh when the variable already exists, so every
    # call printed the last argument. `localoptions` scopes the fix to this function.
    setopt localoptions typesetsilent
    _psc_need_py || return 1
    [[ -x "$_PSC_BIN" ]] || { print -u2 "psc binary missing: $_PSC_BIN"; return 1; }
    if (( $# == 0 )); then
        _psc_tpl description || "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR"
        print
        return 0
    fi
    # `psc --self-update` (root-level flag): the engine detects how this copy was installed and
    # says what updates it — a script install is updated right there, the rest is a command to run.
    if [[ "${1:-}" == --self-update ]]; then
        _psc_plain --self-update
        return $?
    fi
    if [[ "$1" == --reset ]]; then
        _psc_tpl reset.init_confirm
        print
        local key
        print -n ' '
        read -s -k 1 key
        print
        [[ -z "$key" || "$key" == $'\n' ]] || { _psc_tpl confirm_cancel; print; return 1; }
        find "$PSCOMPLETIONS_DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
        mkdir -p "$PSCOMPLETIONS_DATA_DIR/completions"
        _psc_seed_psc
        _PSC_INIT_OK=0
        _psc_init
        _psc_tpl reset.init_done
        print
        return 0
    fi
    # `--json` anywhere means the caller wants the machine contract: hand the invocation to the
    # engine as it is — never colored, never rendered into a human page — and never prompted
    # first: a machine caller cannot press a key (design/json.md §7). With no command word it is
    # the **root** response (§5), so this check comes before the flags-only info page below.
    local _arg
    for _arg in "$@"; do
        if [[ "$_arg" == "--json" ]]; then
            # Verbatim: a failure is JSON as well, and color would break the contract.
            _PSC_INIT_OK=0
            "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "$@"
            return $?
        fi
    done
    # Only flags and no command word: the module's info page, exactly like the bare call. The
    # binary's own usage text is an implementation detail, not what a user of the module sees.
    local _arg _has_cmd=0
    for _arg in "$@"; do
        [[ "$_arg" == -* ]] || _has_cmd=1
    done
    if (( _has_cmd == 0 )); then
        _psc_tpl description || "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR"
        print
        return 0
    fi
    if [[ "$1" == rm ]] && [[ " $* " == *" --all "* ]]; then
        _psc_tpl rm.all_confirm
        print
        local key
        print -n ' '
        read -s -k 1 key
        print
        [[ -z "$key" || "$key" == $'\n' ]] || { _psc_tpl confirm_cancel; print; return 1; }
        # The engine never prompts: the confirmation just given is the authorisation it needs.
        set -- "$@" --yes
    fi
    # A group reset (config / completion / alias) is not confirmed — not destructive enough —
    # but the engine still requires authorisation (design/json.md §7).
    if [[ " $* " == *" --reset "* ]]; then
        set -- "$@" --yes
    fi
    local code=0
    case "$1" in
        add|rm)
            # Rendered from --json (templates), never double-executed.
            _psc_run_rendered "$@"
            code=$?
            ;;
        update)
            # No argument is the library check: its payload is the four change lists, not a
            # per-completion result set, so it stays the CLI's text like the other reports.
            if (( $# == 1 )); then _psc_plain "$@"; else _psc_run_rendered "$@"; fi
            code=$?
            ;;
        list|info|alias|completion|config)
            # Queries print the CLI's text verbatim; anything that sets a value keeps the status
            # path. (PowerShell gets objects from `--json`; here the CLI's text is the interface.)
            case "$1" in
                list|info) _psc_plain "$@" ;;
                alias) [[ $# -eq 1 ]] && _psc_plain "$@" || _psc_run_status "$@" ;;
                completion) (( $# <= 2 )) && _psc_plain "$@" || _psc_run_status "$@" ;;
                config)
                    # `config` and `config <group>` are queries as well; only a value or
                    # `--reset` makes it an action.
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
            # An unrecognised command shows the module info page, exactly like the
            # no-argument form: the module is discovered by browsing, not by an error.
            _psc_tpl description || "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR"
            print
            return 0
            ;;
    esac
    case "$1" in
        add|rm|update|alias|completion|config|init) _PSC_INIT_OK=0 ;;
    esac
    if (( code == 0 )) && [[ "$1" == config && "$2" == menu && "$3" == trigger_key && -n "$4" ]]; then
        _psc_bind_trigger "$4"
    fi
    _psc_render_pending
    return $code
}

_psc_run_rendered() {
    _psc_need_py || return 1
    local cmd="$1"; shift
    local raw
    raw="$("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" --json "$cmd" "$@" 2>/dev/null)"
    local code=$?
    local jobs
    jobs="$(PSC_CMD="$cmd" PSC_RAW="$raw" PSC_DATA="$PSCOMPLETIONS_DATA_DIR" PSC_LANG="$(_psc_lang psc)" "$_PSC_PY" -S <<'PYEOF'
import json,os
e=os.environ
cmd=e['PSC_CMD']
try: env=json.loads(e['PSC_RAW'])
except Exception: env={}
# The envelope's payload: the per-completion list, each item `{name, ok, error?}`.
results=((env.get('data') or {}).get('completions') or []) if isinstance(env,dict) else []
dd=e['PSC_DATA']
lang=e.get('PSC_LANG') or 'en-US'
def settings_lang(name):
    try:
        s=json.load(open(dd+'/settings.json',encoding='utf-8'))
        per=((s.get('config') or {}).get('completion',{}) or {}).get(name,{}).get('language')
        if per: return per
        return (s.get('config') or {}).get('language','en-US')
    except Exception: return 'en-US'
def mlang(name):
    for lf in (settings_lang(name), 'en-US'):
        try:
            json.load(open(f"{dd}/completions/{name}/language/{lf}.json",encoding='utf-8'))
            return lf
        except Exception: continue
    return 'en-US'
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
    local rectype a b
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        rectype="${line%%$'\x1f'*}"; line="${line#*$'\x1f'}"
        a="${line%%$'\x1f'*}"; b="${line#*$'\x1f'}"
        case "$rectype" in
            ERR)
                if [[ -n "$a" ]]; then
                    printf '\033[31m%s: %s\033[0m\n' "$a" "$b"
                else
                    printf '\033[31m%s\033[0m\n' "$b"
                fi
                code=1
                ;;
            TPL) _psc_tpl "$a" "$b" && print ;;
            *) printf '\033[31m%s\033[0m\n' "$line"; code=1 ;;
        esac
    done <<< "$jobs"
    return $code
}

_psc_render_pending() {
    _psc_need_py || return 1
    local change="$PSCOMPLETIONS_DATA_DIR/temp/change.json"
    [[ -f "$change" ]] || return 0
    local out
    out="$("$_PSC_PY" -S - "$change" "$PSCOMPLETIONS_DATA_DIR" <<'PYEOF'
import json,sys
p,dd=sys.argv[1],sys.argv[2]
try: c=json.load(open(p,encoding='utf-8'))
except Exception: raise SystemExit(1)
mod=c.get('module')
if mod:
    try:
        with open(dd+'/temp/.zsh-module-notified',encoding='utf-8') as f: seen=f.read().strip()
    except Exception: seen=''
    if mod!=seen:
        print(f"MODULE\t{mod}")
        open(dd+'/temp/.zsh-module-notified','w',encoding='utf-8').write(mod)
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
            print
        elif [[ "$line" == TPL$'\x1f'* ]]; then
            line="${line#*$'\x1f'}"
            _psc_tpl "${line%%$'\x1f'*}" "${line#*$'\x1f'}" && print
        else
            printf '%s\n' "$line"
        fi
    done <<< "$out"
}

# --- trigger key binding --------------------------------------------------------
_psc_read_trigger_key() {
    _psc_need_py || { print -n Tab 2>/dev/null || printf Tab; return; }
    local s="$PSCOMPLETIONS_DATA_DIR/settings.json"
    [[ -f "$s" ]] || { print -n Tab; return; }
    "$_PSC_PY" -S - "$s" <<'PYEOF' 2>/dev/null || print -n Tab
import json,sys
try:
    c=json.load(open(sys.argv[1],encoding='utf-8')).get('config',{}) or {}
    print(c.get('trigger_key') or 'Tab', end='')
except Exception:
    print('Tab', end='')
PYEOF
}

_psc_bind_trigger() {
    local name="${1:-Tab}" seq
    case "$name" in
        Tab) seq='^I' ;;
        Shift+Tab) seq='^[[Z' ;;
        Ctrl+Space) seq='^@' ;;
        Ctrl+[A-Za-z]) seq="^${name#Ctrl+}" ;;
        Alt+[A-Za-z]) seq="^[${name#Alt+}" ;;
        *) print -u2 "[PSCompletions] unsupported trigger_key '$name', using Tab."; seq='^I' ;;
    esac
    bindkey "$seq" _psc_complete 2>/dev/null
}

if [[ -o interactive ]]; then
    zle -N _psc_complete
    _psc_bind_trigger "$(_psc_read_trigger_key)"
fi
