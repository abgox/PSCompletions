#!/usr/bin/env fish
# PSCompletions fish bridge.
# User setup is one line (`<module>` = the PSCompletions module dir):
#   source <module>/PSCompletions.fish
# or a conf.d symlink — conf.d is sourced before config.fish, so a later key-mode switch cannot drop the trigger binding: 
#   ln -s <module>/PSCompletions.fish ~/.config/fish/conf.d/PSCompletions.fish
# Requires: 
#   - fish 4.0+ (`commandline`, `string`, `bind --key-names`)
#   - Python 3.8+ on PATH (`python3`/`python`; the version is asserted either way).
# Unlike bash/zsh, fish has no heredoc: every python payload below is an inline single-quoted `-c` string.
# Inside fish single quotes the only escapes are `\'` and `\\`, so a payload's `'` is written `\'` and a literal `\\` must be written `\\\\` (no payload here needs one).
# Binaries resolve next to this script (module/PSCompletions/bin/<platform>-<arch>, shipped in the module package), next to this file.
# Missing dependencies print one clear error on load.
#
# PSCOMPLETIONS_DATA_DIR  override the data dir

# Guard: refuse to load when sourced by the wrong shell.
if not set -q FISH_VERSION
    echo "[PSCompletions] PSCompletions.fish is the fish bridge; source the bridge matching your shell instead (PSCompletions.<shell>)." >&2
    return 0
end

if set -q _PSC_LOADED
    return 0
end
set -g _PSC_LOADED 1

# --- dependency check (loud once, on load) -----------------------------------
set -g _PSC_DEPS_OK 1
if test (string split -f1 . $FISH_VERSION)[1] -lt 4
    echo "[PSCompletions] fish 4.0+ required (found $FISH_VERSION)." >&2
    set -g _PSC_DEPS_OK 0
end

# One clear message when the interpreter is unusable, instead of "command not found".
set -g _PSC_PY_WARNED 0
function _psc_need_py
    test -n "$_PSC_PY"; and return 0
    if test $_PSC_PY_WARNED -eq 0
        echo "[PSCompletions] python 3.8+ unavailable; the bridge is disabled this session." >&2
        set -g _PSC_PY_WARNED 1
    end
    return 1
end

# `python3` on Linux, `python` on Windows (and guarded against Python 2).
# Cache the absolute path: a later PATH change (brew shellenv, mise, …) cannot break the bridge.
set -g _PSC_PY ""
for _py in python3 python
    set -l _py_path (command -v $_py 2>/dev/null)
    test -n "$_py_path"; or continue
    if $_py_path -c 'import sys; assert sys.version_info >= (3, 8)' 2>/dev/null
        set -g _PSC_PY $_py_path
        break
    end
end
if test -z "$_PSC_PY"
    echo "[PSCompletions] python 3.8+ not found on PATH at shell start; the bridge cannot run." >&2
    echo "[PSCompletions] install python3 (or make it available before sourcing this file)." >&2
    set -g _PSC_DEPS_OK 0
end

# Every python stdout passes through here.
# A Windows-native interpreter writes CRLF even to pipes, and the bridge only speaks LF: a stray CR broke arithmetic once and silently corrupts paths elsewhere.
# The exit code is preserved, so `or return` checks keep working.
function _psc_py
    "$_PSC_PY" $argv | tr -d '\r'
    return $pipestatus[1]
end

# --- locations ---------------------------------------------------------------
# Resolve symlinks: the documented install is a `conf.d` symlink, so the path fish reports is the link, not the module (`status --current-filename` does not resolve).
set -g _PSC_BRIDGE_DIR (dirname (path resolve (status --current-filename)))
set -l _psc_arch (uname -m)
switch $_psc_arch
    case x86_64 amd64
        set _psc_arch x64
    case aarch64 arm64
        set _psc_arch arm64
end
set -l _psc_platform (uname -s)
switch $_psc_platform
    case 'Linux*'
        set _psc_platform linux
    case 'Darwin*'
        set _psc_platform darwin
    case 'MINGW*' 'MSYS*' 'CYGWIN*'
        set _psc_platform windows
end
set -g _PSC_PLATFORM $_psc_platform
set -l _psc_ext ""
if test "$_psc_platform" = windows
    set _psc_ext .exe
end
set -g _PSC_BIN_DIR "$_PSC_BRIDGE_DIR/bin/$_psc_platform-$_psc_arch"
set -g _PSC_MENU "$_PSC_BIN_DIR/psc-menu$_psc_ext"
set -g _PSC_BIN "$_PSC_BIN_DIR/psc$_psc_ext"

# Default data dir mirrors the PowerShell module's per-platform default, so the shell bridge and the module share one data dir (completions, settings, index).
function _psc_default_data_dir
    switch $_PSC_PLATFORM
        case darwin
            set -l base "$HOME/Library/Application Support/com.abgox/PSCompletions"
            echo $base
        case windows
            set -l root $HOME/AppData/Roaming
            set -q APPDATA; and set root $APPDATA
            echo "$root/com.abgox/PSCompletions"
        case '*'
            set -l base $HOME/.local/share
            set -q XDG_DATA_HOME; and set base $XDG_DATA_HOME
            echo "$base/com.abgox/PSCompletions"
    end
end
set -q PSCOMPLETIONS_DATA_DIR; or set -g PSCOMPLETIONS_DATA_DIR (_psc_default_data_dir)

# Engine-facing platform for `terminal.platform`: never `windows` from fish (the bridge cannot do the Windows console-buffer save/restore the engine expects there), so a Windows fish host uses the alternate screen like the other Unix hosts.
set -g _PSC_ENGINE_PLATFORM linux
test "$_PSC_PLATFORM" = darwin; and set -g _PSC_ENGINE_PLATFORM macos

# --- state -------------------------------------------------------------------
# fish has no associative arrays: every map is two parallel lists (keys, values) and the lookup is `contains -i`.
# Values are single-line by construction — alias names, scalar config values, 0/1 gates, languages — and fish never word-splits an expansion, so values with spaces are safe.
set -g _PSC_ALIAS_KEYS
set -g _PSC_ALIAS_VALS
set -g _PSC_CFG_KEYS
set -g _PSC_CFG_VALS
set -g _PSC_HOOKS_KEYS
set -g _PSC_HOOKS_VALS
set -g _PSC_LANG_KEYS
set -g _PSC_LANG_VALS
set -g _PSC_INIT_OK 0
set -g _PSC_BIN_WARNED 0
set -g _PSC_TAB (printf "\t")
# Terminal modes the menu turns on through crossterm (EnableMouseCapture, EnterAlternateScreen, cursor::Hide, bracketed paste).
# A clean exit turns them off itself; a force-killed menu cannot, so the watchdog writes this itself — without the mouse modes the terminal keeps reporting `ESC [ < b;x;y M` as literal input and the shell becomes unusable.
set -g _PSC_RESET_TERM (printf '\x1b[?1006l\x1b[?1003l\x1b[?1002l\x1b[?1000l\x1b[?1015l\x1b[?1049l\x1b[?25h\x1b[?2004l')

# Map lookup: `_psc_map_get <keys-name> <key> <values…>` -> prints the value.
# The value list must stay the *last* parameter: fish hands the remaining arguments to the last `--argument-names` name, so a list in the middle silently collapses to one element.
function _psc_map_get
    set -l keys $argv[1]
    set -l key $argv[2]
    set -l vals $argv[3..-1]
    set -l i (contains -i -- $key $$keys 2>/dev/null)
    test -n "$i"; or return 1
    echo $vals[$i]
end

# Scalar module config with a default (`_psc_cfg enable_append_space 1`).
function _psc_cfg --argument-names key default
    set -l i (contains -i -- $key $_PSC_CFG_KEYS 2>/dev/null)
    if test -n "$i"
        echo $_PSC_CFG_VALS[$i]
    else if test -n "$default"
        echo $default
    end
end

# Trigger word -> completion name (the alias map), empty when unknown.
function _psc_alias --argument-names word
    _psc_map_get _PSC_ALIAS_KEYS $word $_PSC_ALIAS_VALS
end

# Truthiness for values that arrive as JSON scalars or as config strings:
# `0`/`false`/`False`/`` are false, anything else true.
# `_psc_truthy <value> <default>`.
function _psc_truthy --argument-names value default
    if test -z "$value"
        set value $default
    end
    switch $value
        case 0 false False ''
            return 1
    end
    return 0
end

# --- seed the bundled psc completion (offline first run) ----------------------
# A fresh machine (never imported the PowerShell module) has no psc completion; `psc init` would fetch it over the network.
# Seed the bundled copy first so a first run works offline.
# Mirrors the PowerShell bridge's migration seed.
function _psc_seed_psc
    set -l target "$PSCOMPLETIONS_DATA_DIR/completions/psc"
    if test -f "$target/config.json"; and test -f "$target/language/en-US.json"
        return 0
    end
    for cand in "$_PSC_BRIDGE_DIR/completions/psc" "$_PSC_BRIDGE_DIR/../../completions/psc"
        if test -f "$cand/config.json"; and test -f "$cand/language/en-US.json"
            mkdir -p (dirname $target)
            rm -rf $target
            cp -r $cand $target
            return 0
        end
    end
    return 1
end

# --- init (lazy, first Tab) ---------------------------------------------------
function _psc_init
    test $_PSC_DEPS_OK -eq 1; or return 1
    test $_PSC_INIT_OK -eq 1; and return 0
    # (Re)building state: drop all derived caches so a change invalidates them.
    set -g _PSC_ALIAS_KEYS
    set -g _PSC_ALIAS_VALS
    set -g _PSC_CFG_KEYS
    set -g _PSC_CFG_VALS
    set -g _PSC_HOOKS_KEYS
    set -g _PSC_HOOKS_VALS
    set -g _PSC_LANG_KEYS
    set -g _PSC_LANG_VALS
    if not test -x "$_PSC_MENU"; or not test -x "$_PSC_BIN"
        # nupkg packaging drops the exec bit on Unix; re-apply if the files exist.
        if test -f "$_PSC_MENU"; and test -f "$_PSC_BIN"
            chmod +x "$_PSC_MENU" "$_PSC_BIN" 2>/dev/null
        end
        if not test -x "$_PSC_MENU"; or not test -x "$_PSC_BIN"
            if test $_PSC_BIN_WARNED -eq 0
                echo "[PSCompletions] binaries missing under $_PSC_BIN_DIR (want psc + psc-menu)." >&2
                set -g _PSC_BIN_WARNED 1
            end
            return 1
        end
    end
    set -l tmp "$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p $tmp 2>/dev/null
    _psc_seed_psc
    set -l out "$tmp/psc-init-$fish_pid.json"
    set -l lang en-US
    switch $LANG
        case 'zh*' 'ZH*'
            set lang zh-CN
    end
    "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" "--language=$lang" init --result "$out" 2>/dev/null; or return 1
    test -f "$out"; or return 1
    # aliasMap + flat config, three lines per record (kind, key, value) so values with spaces survive and an empty value still occupies its line.
    set -l dump (_psc_py -S -c '
import json,sys
d=json.load(open(sys.argv[1],encoding=\'utf-8\'))
o=[]
for k,v in (d.get(\'aliasMap\') or {}).items():
    o += [\'a\', k, str(v)]
c=(d.get(\'data\') or {}).get(\'config\') or {}
for k,v in c.items():
    if k==\'completion\': continue
    if isinstance(v,(dict,list)): continue
    o += [\'c\', k, str(v)]
sys.stdout.write("\n".join(o))
' "$out")
    rm -f $out
    set -l n (count $dump)
    set -l i 1
    while test $i -le (math $n - 2)
        set -l kind $dump[$i]
        set -l k $dump[(math $i + 1)]
        set -l v $dump[(math $i + 2)]
        if test "$kind" = a
            set -a _PSC_ALIAS_KEYS $k
            set -a _PSC_ALIAS_VALS $v
        else
            set -a _PSC_CFG_KEYS $k
            set -a _PSC_CFG_VALS $v
        end
        set i (math $i + 3)
    end
    set -g _PSC_INIT_OK 1
end

# Per-completion manifest language: per-completion config -> module -> declared[0].
# Resolution reads settings.json itself: the `_PSC_CFG` cache is only filled by `_psc_init` (first Tab), and `psc` can run before that — the module language must not depend on whether the menu has been triggered yet.
function _psc_lang --argument-names cmd
    _psc_need_py; or return 1
    set -l i (contains -i -- $cmd $_PSC_LANG_KEYS 2>/dev/null)
    if test -n "$i"
        echo $_PSC_LANG_VALS[$i]
        return 0
    end
    set -l l (_psc_py -S -c '
import json,sys,os
dd,cmd,mod=sys.argv[1],sys.argv[2],sys.argv[3]
try:
    s=json.load(open(os.path.join(dd,\'settings.json\'),encoding=\'utf-8\'))
except Exception:
    s={}
gcfg=s.get(\'config\') or {}
if not mod: mod=gcfg.get(\'language\') or \'en-US\'
try:
    cfg=json.load(open(os.path.join(dd,\'completions\',cmd,\'config.json\'),encoding=\'utf-8\'))
except Exception:
    print(mod); raise SystemExit
declared=cfg.get(\'language\') or []
def pick(want):
    return want if want in declared else (declared[0] if declared else mod)
per=(gcfg.get(\'completion\') or {}).get(cmd,{}).get(\'language\')
print(pick(per) if per else pick(mod))
' "$PSCOMPLETIONS_DATA_DIR" "$cmd" "$(_psc_cfg language)")
    set -l v "$l"
    test -n "$v"; or set v en-US
    set -a _PSC_LANG_KEYS $cmd
    set -a _PSC_LANG_VALS $v
    echo $v
end

# Hooks gate: file exists and not disabled (psc itself always runs).
# Prints 0/1.
# Mirrors the PowerShell enable_hooks gate.
function _psc_hooks_enabled --argument-names cmd
    _psc_need_py; or return 1
    set -l i (contains -i -- $cmd $_PSC_HOOKS_KEYS 2>/dev/null)
    if test -n "$i"
        echo $_PSC_HOOKS_VALS[$i]
        return 0
    end
    set -l gate 1
    if not test -f "$PSCOMPLETIONS_DATA_DIR/completions/$cmd/hooks.lua"
        set gate 0
    else if test "$cmd" != psc
        set -l eh (_psc_py -S -c '
import json,sys,os
try:
    s=json.load(open(os.path.join(sys.argv[1],\'settings.json\'),encoding=\'utf-8\'))
    v=(s.get(\'config\') or {}).get(\'completion\',{}).get(sys.argv[2],{}).get(\'enable_hooks\',1)
    print(0 if v==0 or v is False else 1)
except Exception:
    print(1)
' "$PSCOMPLETIONS_DATA_DIR" "$cmd")
        test "$eh" = 1; or set gate 0
    end
    set -a _PSC_HOOKS_KEYS $cmd
    set -a _PSC_HOOKS_VALS $gate
    echo $gate
end

# --- tokenize ----------------------------------------------------------------
# The shared grammar (must match order::tokenize).
function _psc_tokens --argument-names before
    string match -r -a '"[^"]*"|\'[^\']*\'|\S+' -- $before
end

# The command being edited: everything after the last unquoted separator (`|`, `;`, `&`, `&&`, `||`).
# A separator ends a command, so what follows it is a fresh command line whose own command word and tokens are what the menu completes (`git status | grep <Tab>` completes `grep`).
# Quotes (and `\`) hide a separator; `>&` and `&>` are redirections, not separators; an empty result means there is nothing to complete here, so the caller falls back to the host.
function _psc_segment --argument-names text
    set -l out ''
    set -l q 0
    set -l n (string length -- $text)
    set -l i 1
    while test $i -le $n
        set -l c (string sub -s $i -l 1 -- $text)
        if test $q -ne 1; and test "$c" = '\\'
            set out "$out$c"(string sub -s (math $i + 1) -l 1 -- $text)
            set i (math $i + 2)
            continue
        end
        if test "$c" = "'"
            if test $q -eq 0
                set q 1
            else if test $q -eq 1
                set q 0
            end
            set out "$out$c"
            set i (math $i + 1)
            continue
        end
        if test "$c" = '"'
            if test $q -eq 0
                set q 2
            else if test $q -eq 2
                set q 0
            end
            set out "$out$c"
            set i (math $i + 1)
            continue
        end
        if test $q -eq 0
            switch "$c"
                case '|' ';'
                    set out ''
                case '&'
                    # `&` backgrounds, `&&` separates, and `>&` / `&>` are redirections.
                    set -l nxt (string sub -s (math $i + 1) -l 1 -- $text)
                    set -l prv ''
                    test $i -gt 1; and set prv (string sub -s (math $i - 1) -l 1 -- $text)
                    if test "$nxt" = '>'; or test "$prv" = '>'
                        set out "$out$c"
                    else
                        set out ''
                        if test "$nxt" = '&'
                            set i (math $i + 1)
                        end
                    end
                case '*'
                    set out "$out$c"
            end
        else
            set out "$out$c"
        end
        set i (math $i + 1)
    end
    # The leading whitespace belongs to the separator, not to the new command.
    string trim -l -- $out
end

# Escape a candidate for insertion the way fish's own completion does: a backslash before each special character, with a leading `~` left bare so tilde expansion still applies.
# Verified differentially against fish's own insertion (`space ' " $ * ( ) [ ] { } < > & | ; # \ ~ ^ %` get a backslash; `! = : @ + ,` do not — escaping those too is harmless).
# `\` is escaped first so the later passes do not double it.
function _psc_escape --argument-names text
    set -l lead ""
    set -l rest $text
    if string match -q '~*' -- $rest
        set lead "~"
        set rest (string sub -s 2 -- $rest)
    end
    for ch in '\\' ' ' $_PSC_TAB "'" '"' '$' '*' '?' '(' ')' '[' ']' '{' '}' '<' '>' '&' '|' ';' '#' '~' '^' '%'
        set rest (string replace -- $ch "\\$ch" $rest)
    end
    printf '%s' "$lead$rest"
end

# --- build-mode menu ---------------------------------------------------------
# input.json via python (single writer: quoting-safe).
# Shared by the live bridge and the headless test driver.
# argv: in cmd last_complete manifest has_hooks cx cy w h hist platform cwd data args...
function _psc_write_input
    set -l a $argv
    _psc_py -S -c '
import json,os,sys,urllib.parse
a=sys.argv[1:]
def b(v): return v=="1"
def truthy(v, d=0):
    if v is None: v=d
    if isinstance(v,str): return v not in ("0","false","False","")
    return bool(v)
inp_path=a[0]; cmd=a[1]; last=a[2]; manifest=a[3]; hooks=a[4]
cx,cy,w,h=a[5],a[6],a[7],a[8]; hist=a[9]; platform=a[10]; cwd=a[11]; dd=a[12]
args=a[13:]
try: settings=json.load(open(dd+"/settings.json",encoding="utf-8"))
except Exception: settings={}
cfg=settings.get("config",{}) if isinstance(settings.get("config"),dict) else {}
lang=cfg.get("language","en-US")
# Localized filter hints from the psc completion info templates.
hint, hint_stale = "", ""
try:
    pinfo=json.load(open(f"{dd}/completions/psc/language/{lang}.json",encoding=\'utf-8\')).get("info",{})
    v=pinfo.get("filter_hint") or ""
    hint="".join(v) if isinstance(v,list) else v
    v=pinfo.get("filter_hint_stale") or ""
    hint_stale="".join(v) if isinstance(v,list) else v
except Exception:
    pass
menu={
 "filter_hint": hint, "filter_hint_stale": hint_stale,
 "flags": {
  "enable_list_loop": truthy(cfg.get("enable_list_loop"), 1),
  "filter_mode": cfg.get("filter_mode","wildcard"),
  "enable_apply_when_single": truthy(cfg.get("enable_apply_when_single")),
  "enable_apply_when_no_match": truthy(cfg.get("enable_apply_when_no_match")),
  "show_mode": cfg.get("show_mode","auto"),
  "color_focus": cfg.get("color_focus","red"),
  "color_match": cfg.get("color_match","cyan"),
 },
 "context_switch": cfg.get("switch","~"),
 "context_stay": cfg.get("stay","?"),
 "raw_config": {
  "completion": (cfg.get("completion") or {}).get(cmd,{}) or {},
  "global": {k:v for k,v in cfg.items() if not isinstance(v,(dict,list))},
  "default": {},
 },
}
data={}
if cmd=="psc":
    data={"config":{"language":lang,"completion":cfg.get("completion",{})}}
od=dd+"/temp/order"
q=urllib.parse.quote(cmd,safe="")
border={"cmd_order":od+"/"+q+".json",
 "paths_order":od+"/_shared/_paths.json","commands_order":od+"/_shared/_commands.json"}
top=None
if hist and truthy(cfg.get("enable_sort_by_history"), 1):
    alias=(settings.get("alias") or {})
    aliases=alias.get(cmd) or [cmd]
    top={"history":hist,"cmd":cmd,"aliases":aliases,"path":border["cmd_order"]}
inp={
 "items":[],
 "build":{
  "cmd":cmd,"arg_tokens":args,"treat_last_as_complete":b(last),
  "manifest":manifest,"hooks":b(hooks),"cwd":cwd,
  "config":cfg.get("completion",{}).get(cmd,{}),
  "global_config":{k:v for k,v in cfg.items() if not isinstance(v,(dict,list))},
  "data":data,"dir":{"completions":dd+"/completions","cache":dd+"/temp/cache","log":""},"file":{"settings":dd+"/settings.json","completions":dd+"/temp/completions.json"},
 },
 "config":menu,
 "terminal":{"cursor":{"x":int(cx),"y":int(cy)},
  "buffer":{"w":int(w),"h":int(h)},
  "window":{"top":0,"h":int(h)},"platform":platform},
 "dir":{"data":dd,"order":dd+"/temp/order","menu":dd+"/temp/menu"},
}
# Ranking is a pair: the build-context block is the channel the engine needs before it consults the history block.
# Keep both tied to one switch: with the key off neither is passed, which is what makes `enable_sort_by_history=0` really stop ranking.
if top:
    inp["build"]["order"] = border
    inp["order"] = top
json.dump(inp,open(inp_path,"w",encoding="utf-8"))
' $a
end

# --- spawn: the menu, watched ------------------------------------------------
# One python process runs the menu with the console inherited, watches its stderr heartbeat (the engine writes one every 15 s), kills it after 30 s of silence and leaves the alternate screen, then decodes the `--result` file.
# fish has no `read -t`, and the watchdog must not move the menu out of the shell's own process group (fish's command substitution keeps the child there), so this stays in python.
# Prints three lines: status, text (or index in items mode), nospace.
# argv: mode menu in out
function _psc_spawn --argument-names mode
    set -l menu $argv[2]
    set -l inp $argv[3]
    set -l outp $argv[4]
    _psc_py -S -c '
import json,os,select,subprocess,sys,time
mode,menu,inp,outp=sys.argv[1:5]
reset=sys.argv[5].encode() if len(sys.argv)>5 else b"\x1b[?1049l"
items = mode==\'items\'
try: tty=open("/dev/tty","wb")
except Exception: tty=None
p=subprocess.Popen([menu,inp,"--result",outp],stdout=tty,stderr=subprocess.PIPE)
last=time.time()
try:
    while p.poll() is None:
        r,_,_=select.select([p.stderr],[],[],1.0)
        if r:
            d=os.read(p.stderr.fileno(),65536)
            if not d: break
            last=time.time()
        elif time.time()-last>30:
            p.kill()
            if tty:
                try:
                    tty.write(reset); tty.flush()
                except Exception: pass
                try:
                    import termios
                    termios.tcflush(tty.fileno(),termios.TCIFLUSH)
                except Exception: pass
            p.wait()
            print("cancel"); print(""); print("0")
            raise SystemExit
except Exception:
    pass
p.wait()
def out(s,t,n):
    print(s); print(t); print(n)
try: r=json.load(open(outp,encoding=\'utf-8\'))
except Exception:
    out("cancel","","0"); raise SystemExit
s=r.get("status")
if s=="selected":
    if items: out("selected",str(r.get("index","")),"0")
    else: out("selected",r.get("completion_text",""),"1" if r.get("nospace") else "0")
elif s=="input":
    # no-match: the engine hands back the filter text; items mode answers by index, so only build mode can apply it as a word
    if items: out("input",r.get("text",""),"0")   # the caller applies the text itself
    else: out("selected",r.get("text",""),"0")
else:
    out(s or "cancel","","0")
' $mode "$menu" "$inp" "$outp" "$_PSC_RESET_TERM"
end

# --- result application ------------------------------------------------------
# Line-level rules: prints the new cursor within the line on the first output line and the new line after it.
# `text` is a completion, never multi-line.
# The trailing-space rules mirror the PowerShell bridge's `handle_menu_output`: no space for the engine's `nospace`, an attached value (`--x=`), `enable_append_space=0`, or when a word already follows after whitespace.
# 1-based start of the word under the cursor.
# A word boundary is an unquoted, unescaped whitespace, so `az\ zdir` stays one word: the naive `^.* ` split cut at the escaped space and concatenated the pick after the old text instead of replacing it.
function _psc_word_start --argument-names s
    set -l n (string length -- $s)
    set -l start 1
    set -l q 0
    set -l i 1
    while test $i -le $n
        set -l c (string sub -s $i -l 1 -- $s)
        if test $q -ne 1; and test "$c" = '\\'
            set i (math $i + 2)
            continue
        end
        if test "$c" = "'"
            if test $q -eq 0
                set q 1
            else if test $q -eq 1
                set q 0
            end
        else if test "$c" = '"'
            if test $q -eq 0
                set q 2
            else if test $q -eq 2
                set q 0
            end
        else if test $q -eq 0; and test "$c" = ' ' -o "$c" = "$_PSC_TAB"
            set start (math $i + 1)
        end
        set i (math $i + 1)
    end
    echo -n $start
end

# Display form of a native candidate: the leaf, the way the hosts' own lists render it (`/tmp/psc t/az zdir/` -> `az zdir/`, `python3` -> `python3`).
# PS calls this ListItemText.
function _psc_leaf --argument-names p
    set -l body $p
    set -l slash ""
    if string match -q '*/' -- $body
        set slash "/"
        set body (string sub -s 1 -l (math (string length -- $body) - 1) -- $body)
    end
    printf '%s' (string replace -r '^.*/' '' -- $body)$slash
end

function _psc_apply_line
    set -l buf $argv[1]
    set -l pos $argv[2]
    set -l text $argv[3]
    set -l nospace $argv[4]
    set -l before (string sub -s 1 -l $pos -- $buf)
    set -l after (string sub -s (math $pos + 1) -- $buf)
    set -l start $pos
    if test -n "$before"; and not string match -q '* ' -- $before
        # `_psc_word_start` is 1-based; `start` here is the number of characters to keep
        set start (math (_psc_word_start $before) - 1)
    end
    # Cursor mid-word: consume the remainder of the word under the cursor, so the replacement covers the whole token (mirrors the PowerShell word-end extend).
    set -l consume 0
    if test -n "$after"
        set -l c0 (string sub -s 1 -l 1 -- $after)
        if test "$c0" != " "; and test "$c0" != "$_PSC_TAB"
            set -l m (string match -r -g '^("[^"]*"|\'[^\']*\'|[^[:space:]]+)' -- $after)
            if test (count $m) -ge 1
                set consume (string length -- $m[1])
            end
        end
    end
    set -l tail (string sub -s (math $consume + 1) -- $after)
    set -l suffix " "
    if string match -q '*=' -- $text; or test "$nospace" = 1
        set suffix ""
    end
    if test "$(_psc_cfg enable_append_space 1)" = 0
        set suffix ""
    end
    if string match -r -q '^[[:space:]]+[^[:space:]]' -- $after
        set suffix ""
    end
    # A closing quote right after the cursor would double: drop ours.
    set -l first_after (string sub -s 1 -l 1 -- $after)
    set -l last_text (string sub -s -1 -- $text)
    if test "$first_after" = '"' -o "$first_after" = "'"; and test "$last_text" = "$first_after"
        set text (string sub -s 1 -l (math (string length -- $text) - 1) -- $text)
    end
    set -l head (string sub -s 1 -l $start -- $buf)
    printf '%s\n' (math $start + (string length -- $text) + (string length -- $suffix))
    printf '%s' "$head$text$suffix$tail"
end

# Compute the new buffer + cursor for a verdict.
# Pure — no `commandline` access — so the headless suite can assert the rules.
# The buffer arrives as a **list of lines** after `<pos> <text> <nospace>`: fish splits command substitution on newlines and cannot hold one in a variable, so a multi-line buffer was never a string here.
# `commandline -C` counts characters across the whole buffer, hence the walk.
# Prints the new cursor first, then the new buffer lines.
function _psc_apply_text
    set -l pos $argv[1]
    set -l text $argv[2]
    set -l nospace $argv[3]
    set -l lines $argv[4..-1]
    test (count $lines) -gt 0; or set lines ""
    set -l idx 1
    set -l off $pos
    for l in $lines
        set -l n (string length -- $l)
        if test $off -le $n
            break
        end
        set off (math $off - $n - 1)
        set idx (math $idx + 1)
    end
    if test $idx -gt (count $lines)
        set idx (count $lines)
        set off (string length -- $lines[$idx])
    end
    set -l cur (_psc_apply_line $lines[$idx] $off "$text" "$nospace")
    set -l base 0
    set -l i 1
    while test $i -lt $idx
        set base (math $base + (string length -- $lines[$i]) + 1)
        set i (math $i + 1)
    end
    printf '%s\n' (math $base + $cur[1])
    set -l out
    set i 1
    for l in $lines
        if test $i -eq $idx
            set -a out "$cur[2]"
        else
            set -a out "$l"
        end
        set i (math $i + 1)
    end
    printf "%s\n" $out
end

# The `commandline` side of the rule above: the buffer comes back as a list of lines and `commandline -r` joins its arguments with newlines, so the lines pass through unchanged.
function _psc_apply --argument-names text nospace
    set -l lines (commandline -b)
    set -l res (_psc_apply_text (commandline -C) "$text" "$nospace" $lines)
    commandline -r -- $res[2..-1]
    commandline -C $res[1]
    commandline -f repaint
end

function _psc_build_menu
    set -l cmd $argv[1]
    set -l last_complete $argv[2]
    set -l args $argv[3..-1]
    set -l lang (_psc_lang $cmd); or return 1
    set -l manifest "$PSCOMPLETIONS_DATA_DIR/completions/$cmd/language/$lang.json"
    set -l has_hooks (_psc_hooks_enabled $cmd)
    set -l tmp "$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p $tmp 2>/dev/null
    set -l id (random)$fish_pid
    set -l inp "$tmp/psc-menu-$id-input.json"
    set -l outp "$tmp/psc-menu-$id-output.json"
    # Cursor column + terminal size (fallback: col 0, 120x30).
    # The input line's *row* has no API in fish, so `show_mode` follow placement degrades to the top.
    set -l buf (commandline -b)
    set -l pos (commandline -C)
    set -l head (string sub -s 1 -l $pos -- $buf)
    set -l cx (string length -- $head)
    set -l w 120
    test -n "$COLUMNS"; and set w $COLUMNS
    set -l h 30
    test -n "$LINES"; and set h $LINES
    set -l hist (_psc_hist)
    _psc_write_input $inp $cmd $last_complete $manifest $has_hooks $cx 0 $w $h "$hist" $_PSC_ENGINE_PLATFORM $PWD $PSCOMPLETIONS_DATA_DIR $args
    set -l res (_psc_spawn build "$_PSC_MENU" $inp $outp)
    rm -f $inp $outp
    # NOT `status`: fish's exit-status variable is read-only, and `set -l status` fails ("Tried to modify the special variable") while leaving `$status` pointing at the last command's exit code — which then reads as "not selected" and silently drops every pick.
    set -l st "$res[1]"
    set -l words "$res[2]"
    set -l nospace "$res[3]"
    if test "$st" = min_area
        set -l hint (_psc_tpl min_area 2>/dev/null)
        test -n "$hint"; or set hint "# terminal too small for menu"
        set hint (string split \n -- $hint)[1]
        set -l line (commandline -b)" $hint"
        commandline -r -- $line
        commandline -C (string length -- $line)
        commandline -f repaint
        return 1
    end
    if test "$st" != selected; and test "$st" != input
        return 1
    end
    _psc_apply "$words" "$nospace"
end

# --- Tab entry ---------------------------------------------------------------
# Decide where a trigger press goes, from the line up to the cursor alone (no line editor), so the routing rules are testable headlessly.
# Prints either build / <cmd> / <0|1 last_complete> / <arg_token>… native or nothing when the word is not a trigger.
# Routing has two conditions, not one: an installed command *and* a non-path-shaped pending token.
function _psc_route --argument-names before
    test -n "$before"; or return 1
    # A separator ends the command being edited: what follows it is a fresh command line, so its own command word and tokens are what the menu completes.
    # `before` stays whole — the word offsets below are absolute.
    set -l seg (_psc_segment "$before")
    set -l toks (_psc_tokens $seg)
    test (count $toks) -gt 0; or return 1
    set -l first $toks[1]
    # Strip a Windows executable suffix (case-insensitive), like the PS bridge.
    switch (string lower -- $first)
        case '*.exe' '*.cmd' '*.bat'
            set first (string replace -r '\.[^.]*$' '' -- $first)
            set toks[1] $first
    end
    # sudo unwrap: `sudo <cmd>` completes for the wrapped command.
    if test "$first" = sudo; and test (count $toks) -gt 1
        set -l wrapped $toks[2]
        switch (string lower -- $wrapped)
            case '*.exe' '*.cmd' '*.bat'
                set wrapped (string replace -r '\.[^.]*$' '' -- $wrapped)
        end
        if test -n "$(_psc_alias $wrapped)"
            set -e toks[1]
            set toks[1] $wrapped
            set first $wrapped
        end
    end
    # A wildcard command name is not a completion trigger.
    if string match -q '*\**' -- $first; or string match -q '*\?*' -- $first
        return 1
    end
    set -l cmd (_psc_alias $first)
    # A path-shaped pending token goes to the native path (path completion), mirroring the PowerShell bridge, even for an installed command.
    if test -z "$cmd"; or not string match -q '* ' -- $before
        set -l last ""
        if not string match -q '* ' -- $before
            set last $toks[-1]
        end
        # Strip a leading quote, then ask whether the token is path-shaped.
        # Literal substring tests avoid backslash-in-glob/regex escaping.
        set -l p $last
        set -l c1 (string sub -s 1 -l 1 -- $p)
        if test "$c1" = '"' -o "$c1" = "'"
            set p (string sub -s 2 -- $p)
            set c1 (string sub -s 1 -l 1 -- $p)
        end
        set -l path_like 0
        if contains -- $c1 / '\\'
            set path_like 1
        else if contains -- (string sub -s 1 -l 2 -- $p) './' '~/' ".\\" "~\\"
            set path_like 1
        else if contains -- (string sub -s 1 -l 3 -- $p) '../' "..\\"
            set path_like 1
        else if test (string sub -s 2 -l 1 -- $p) = ':'; and string match -r -q '^[A-Za-z]$' -- $c1
            set path_like 1
        end
        # `git<Tab>`: the command word itself is still being completed, so offer command names, not git's subcommands — build only once the word is finished (trailing space) or an argument already exists (2+ tokens), the PS bridge's rule.
        set -l first_word 0
        if test (count $toks) -eq 1; and not string match -q '* ' -- $before
            set first_word 1
        end
        if test -z "$cmd"; or test $path_like -eq 1; or test $first_word -eq 1
            echo native
            return 0
        end
    end
    set -l last_complete 0
    string match -q '* ' -- $before; and set last_complete 1
    # arg_tokens: every token after the command word — the *pending* one included, with `treat_last_as_complete` saying whether it is finished.
    # The engine turns the last unfinished token into the partial match and pre-fills the menu filter with it (`^text`), so dropping it built the parent context and opened the menu unfiltered.
    set -l args $toks[2..-1]
    echo build
    printf '%s\n' $cmd
    printf '%s\n' $last_complete
    for a in $args
        printf '%s\n' $a
    end
end

function _psc_complete
    _psc_init; or return 1
    set -l buf (commandline -b)
    set -l pos (commandline -C)
    set -l before (string sub -s 1 -l $pos -- $buf)
    set -l route (_psc_route $before)
    test -n "$route"; or return 1
    switch $route[1]
        case build
            _psc_build_menu $route[2] $route[3] $route[4..-1]
        case native
            _psc_native $before
    end
end

# --- history: the host format is not plain command lines ---------------------
# fish's history file is YAML-ish (`- cmd: …` + `when: <epoch>`), while the engine's ordering reads one command per line, so hand it a normalised copy.
# The copy is rebuilt only when the source is newer (the engine reads only the last 1000 lines).
# Prints the path to use, or nothing when sorting by history is off (callers must pass the result as a quoted argument — an empty command substitution adds no argument in fish).
function _psc_hist
    test "$(_psc_cfg enable_sort_by_history 1)" = 1; or return 0
    _psc_need_py; or return 0
    set -l base $HOME/.local/share
    set -q XDG_DATA_HOME; and set base $XDG_DATA_HOME
    set -l name fish
    test -n "$fish_history"; and set name $fish_history
    set -l src "$base/fish/"$name"_history"
    test -f "$src"; or return 0
    set -l dst "$PSCOMPLETIONS_DATA_DIR/temp/psc-fish-history"
    mkdir -p (dirname $dst) 2>/dev/null
    if not test -f "$dst"; or test "$src" -nt "$dst"
        _psc_py -S -c '
import re,sys
src,dst=sys.argv[1],sys.argv[2]
q=chr(39); bs=chr(92)
out=[]
try:
    for line in open(src,encoding="utf-8",errors="replace"):
        m=re.match(r"^- cmd: (.*)$",line.rstrip("\n"))
        if not m: continue
        v=m.group(1)
        # A quoted scalar carries escaped quotes/backslashes/newlines; unescape just enough for the tokenizer (a multi-line command stays on one line).
        if len(v)>=2 and v[0]==q and v[-1]==q:
            v=v[1:-1].replace(bs+q,q).replace(bs+bs,bs).replace(bs+"n"," ")
        out.append(v)
except Exception:
    pass
open(dst,"w",encoding="utf-8").write("\n".join(out[-4000:])+"\n")
' "$src" "$dst" 2>/dev/null
    end
    test -f "$dst"; or return 0
    echo $dst
end

# --- native path: the host's completions through our menu --------------------
# `complete -C '<line up to cursor>'` is an ask, not an interception: fish's own completion engine answers with `candidate<TAB>description` per line and always answers something (an unknown command falls back to path completion).
# The candidates are **raw** names — unlike zsh's `compadd`, nothing is pre-escaped — so the picked one is escaped here (`_psc_escape`) exactly as fish's own completion would insert it.
# Candidates are history-ranked through `--sort` and rendered in our menu, so the native system is a data source, never a UI.
# Prints `text` / `tip` pairs, one value per line.
function _psc_sort_native --argument-names before
    set -l lines $argv[2..-1]
    set -l toks (_psc_tokens $before)
    set -l tmp "$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p $tmp 2>/dev/null
    set -l id (random)$fish_pid
    set -l inp "$tmp/psc-sort-$id-in.json"
    set -l outp "$tmp/psc-sort-$id-out.json"
    set -l last 0
    string match -q '* ' -- $before; and set last 1
    set -l hist (_psc_hist)
    # The candidate lines travel in a file: a host completion can return thousands of entries and argv would blow ARG_MAX.
    set -l cands "$tmp/psc-sort-$id-cands.txt"
    printf '%s\n' $lines > $cands
    _psc_py -S -c '
import json,os,sys,urllib.parse
a=sys.argv[1:]
inp_path,hist,cmd,last,dd,ntoks=a[0:6]
n=int(ntoks)
rest=a[6:]
toks=rest[0:n]
lines=open(rest[n],encoding="utf-8").read().split("\n")
items=[]
for ln in lines:
    if not ln: continue
    p=ln.split("\t",1)
    tip=(p[1] if len(p)>1 else "")
    items.append({"text":p[0],"tip":(tip or None)})
o={"items":items,"tokens":toks,"treat_last_as_complete":last=="1"}
if hist:
    od=dd+"/temp/order"
    o["order"]={"cmd_order":od+"/"+urllib.parse.quote(cmd,safe=""),
     "paths_order":od+"/_shared/_paths.json","commands_order":od+"/_shared/_commands.json"}
json.dump(o,open(inp_path,"w",encoding="utf-8"))
' "$inp" "$hist" "$toks[1]" "$last" "$PSCOMPLETIONS_DATA_DIR" (count $toks) $toks "$cands"
    "$_PSC_MENU" --sort $inp --result $outp >/dev/null 2>&1
    rm -f $inp $cands
    set -l pairs (_psc_py -S -c '
import json,sys
try: items=json.load(open(sys.argv[1],encoding=\'utf-8\'))
except Exception: raise SystemExit(1)
o=[]
for i in items:
    if not isinstance(i,dict): continue
    o.append(i.get("text") or "")
    t=i.get("tip")
    o.append(t if isinstance(t,str) else "")
sys.stdout.write("\n".join(o))
' "$outp" 2>/dev/null)
    rm -f $outp
    printf '%s\n' $pairs
end

# menu with host-provided items; prints the chosen completion text.
# argv: cmd n texts... disps... tips...
# Items mode: the filter is the engine's call, so the bridge only forwards the line's tokens.
# argv: cmd arg_tokens last_complete n texts... disps... tips...
function _psc_menu_items
    set -l cmd $argv[1]
    set -l args $argv[2]
    set -l last $argv[3]
    set -l n $argv[4]
    set -l p1 (math "4 + $n")
    set -l p2 (math "5 + $n")
    set -l p3 (math "4 + 2 * $n")
    set -l p4 (math "5 + 2 * $n")
    set -l texts $argv[5..$p1]
    set -l disps $argv[$p2..$p3]
    set -l tips $argv[$p4..-1]
    test $n -gt 0; or return 1
    set -l tmp "$PSCOMPLETIONS_DATA_DIR/temp/menu"
    mkdir -p $tmp 2>/dev/null
    set -l id (random)$fish_pid
    set -l inp "$tmp/psc-items-$id-in.json"
    set -l outp "$tmp/psc-items-$id-out.json"
    # The candidate records travel in a file: a host completion can return thousands of entries and argv would blow ARG_MAX.
    set -l f_cands "$tmp/psc-items-$id-cands.txt"
    rm -f $f_cands
    # The host's arrays can be shorter than n (fish drops empty elements when expanding a list), so read every index defensively.
    for i in (seq 1 $n)
        set -l tx ""
        test $i -le (count $texts); and set tx $texts[$i]
        set -l dp ""
        test $i -le (count $disps); and set dp $disps[$i]
        set -l tp ""
        test $i -le (count $tips); and set tp $tips[$i]
        printf '%s\x1e%s\x1e%s\x1f' "$tx" "$dp" "$tp" >> $f_cands
    end
    set -l hist (_psc_hist)
    _psc_py -S -c '
import json,os,sys,urllib.parse
a=sys.argv[1:]
inp_path,cmd,hist,dd,platform,n,cands_file,args,last=a[0:10]
n=int(n)
def truthy(v, d=0):
    if v is None: v=d
    if isinstance(v,str): return v not in ("0","false","False","")
    return bool(v)
try: settings=json.load(open(dd+"/settings.json",encoding="utf-8"))
except Exception: settings={}
cfg=settings.get("config",{}) if isinstance(settings.get("config"),dict) else {}
lang=cfg.get("language","en-US")
hint, hint_stale = "", ""
try:
    pinfo=json.load(open(f"{dd}/completions/psc/language/{lang}.json",encoding=\'utf-8\')).get("info",{})
    v=pinfo.get("filter_hint") or ""
    hint="".join(v) if isinstance(v,list) else v
    v=pinfo.get("filter_hint_stale") or ""
    hint_stale="".join(v) if isinstance(v,list) else v
except Exception:
    pass
menu={
 "filter_hint": hint, "filter_hint_stale": hint_stale,
 "flags": {
  "enable_list_loop": truthy(cfg.get("enable_list_loop"), 1),
  "filter_mode": cfg.get("filter_mode","wildcard"),
  "enable_apply_when_single": truthy(cfg.get("enable_apply_when_single")),
  "enable_apply_when_no_match": truthy(cfg.get("enable_apply_when_no_match")),
  "show_mode": cfg.get("show_mode","auto"),
  "color_focus": cfg.get("color_focus","red"),
  "color_match": cfg.get("color_match","cyan"),
 },
 "context_switch": cfg.get("switch","~"),
 "context_stay": cfg.get("stay","?"),
 "raw_config": {"completion": {},
  "global": {k:v for k,v in cfg.items() if not isinstance(v,(dict,list))}, "default": {}},
}
items=[]
for rec in open(cands_file,encoding="utf-8").read().split("\x1f"):
    if not rec: continue
    p=rec.split("\x1e")
    text=p[0] if len(p)>0 else ""
    disp=p[1] if len(p)>1 and p[1] else text
    tip=p[2] if len(p)>2 else ""
    if not text: continue
    items.append({"completion_text":text,"list_item_text":disp,"symbol":"",
     "tip":(tip or None),"usage":None,"example":None,"result_type":None})
od=dd+"/temp/order"
inp={"items":items,"config":menu,
 "terminal":{"cursor":{"x":0,"y":0},"buffer":{"w":120,"h":30},
  "window":{"top":0,"h":30},"platform":platform},
 "dir":{"data":dd,"order":od,"menu":dd+"/temp/menu"},
 "arg_tokens":[t for t in args.split("\n") if t!=""],
 "treat_last_as_complete":last=="1"}
if hist and truthy(cfg.get("enable_sort_by_history"), 1):
    alias=(settings.get("alias") or {})
    q=urllib.parse.quote(cmd,safe="")
    inp["order"]={"history":hist,"cmd":cmd,"aliases":alias.get(cmd) or [cmd],"path":od+"/"+q+".json"}
json.dump(inp,open(inp_path,"w",encoding="utf-8"))
' "$inp" "$cmd" "$hist" "$PSCOMPLETIONS_DATA_DIR" "$_PSC_ENGINE_PLATFORM" "$n" "$f_cands" "$args" "$last"
    set -l res (_psc_spawn items "$_PSC_MENU" $inp $outp)
    rm -f $inp $outp $f_cands
    # `input`: the filter text to apply (no-match auto-apply) — no index involved
    if test "$res[1]" = input
        printf '%s' $res[2]
        return 0
    end
    test "$res[1]" = selected; or return 1
    set -l idx "$res[2]"
    test -n "$idx"; or return 1
    printf '%s' $texts[(math $idx + 1)]
end

# Native pick -> text + nospace.
# A directory is recognisable from the candidate text itself (`complete -C` marks a container with a trailing `/`), so no filesystem probe on a name that may contain anything.
# `enable_path_trailing_separator` only decides whether that separator stays; a container never takes a trailing space.
function _psc_pick_text --argument-names pick
    set -g _PSC_PICK_TEXT $pick
    set -g _PSC_PICK_NOSPACE 0
    string match -q '*/' -- $pick; or return 0
    set -g _PSC_PICK_NOSPACE 1
    if test "$(_psc_cfg enable_path_trailing_separator 1)" != 1
        set -g _PSC_PICK_TEXT (string sub -s 1 -l (math (string length -- $pick) - 1) -- $pick)
    end
end

function _psc_native --argument-names before
    if test "$(_psc_cfg enable_native_completion 1)" != 1
        # fish has a per-key fallback the other bridges lack: hand the trigger back to the host's own completer (the shape of the PS bridge's `MenuComplete`).
        commandline -f complete
        return 0
    end
    set -l lines
    for line in (complete -C $before 2>/dev/null)
        test -n "$line"; and set -a lines $line
    end
    test (count $lines) -gt 0; or return 1
    set -l pairs (_psc_sort_native $before $lines)
    test (count $pairs) -gt 0; or return 1
    set -l texts
    set -l disps
    set -l tips
    set -l i 1
    while test $i -le (count $pairs)
        set -l t $pairs[$i]
        set -a texts "$t"
        set -a disps (_psc_leaf "$t")
        set -l tp ""
        test (math $i + 1) -le (count $pairs); and set tp $pairs[(math $i + 1)]
        set -a tips "$tp"
        set i (math $i + 2)
    end
    set -l toks (_psc_tokens $before)
    set -l last 0
    string match -q '* ' -- $before; and set last 1
    set -l pick (_psc_menu_items $toks[1] "$(printf '%s\n' $toks)" $last \
        (count $texts) $texts $disps $tips)
    test -n "$pick"; or return 1
    _psc_pick_text $pick
    set -l esc (_psc_escape "$_PSC_PICK_TEXT")
    _psc_apply "$esc" "$_PSC_PICK_NOSPACE"
end

# --- management forwarding ---------------------------------------------------
# Generic info-template renderer (design/templates.md).
# Usage: _psc_tpl <dotted.info.path> [context-json]
# Context values come from the caller; `Version` is filled from the module manifest.
# Unknown constructs stay literal; colors map to ANSI.
# Renders one `info` template through the engine (`psc tpl --version …`).
# The grammar and its implementation live there, so a bridge carries no renderer of its own.
# A missing binary or an unknown path fails, and the caller's `or` fallback takes over.
function _psc_module_version
    # The module manifest beside the bridge is the one version source present in both a repo checkout and an installed package (the package carries no `../version.json`).
    sed -n "s/.*ModuleVersion *= *'\([^']*\)'.*/\1/p" "$_PSC_BRIDGE_DIR/PSCompletions.psd1" 2>/dev/null | head -1
end

function _psc_tpl --argument-names path
    test -x "$_PSC_BIN"; or return 1
    set -l args --data $PSCOMPLETIONS_DATA_DIR tpl $path
    test (count $argv) -ge 2; and set -a args --ctx $argv[2]
    set -a args --version (_psc_module_version)
    $_PSC_BIN $args
end

# Run a management command that only prints a status line.
# The CLI's messages are plain text, so the color is the bridge's job — the same convention as the PS bridge's `_forward_psc`: success green, failure red (design/config-support.md).
# Data queries print exactly what the CLI renders: the CLI's text is the interface in every host, and `--json` is the machine contract.
# Only messages take color.
# A failed query still goes through the red path.
function _psc_plain
    set -l out ("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" $argv 2>/dev/null)
    if test $status -eq 0
        printf '%s\n' $out
        return 0
    end
    _psc_run_status $argv
end

# No-arg update: the lists belong to the template tail, not to the CLI's plain text.
# Success prints nothing — the tail renders the same lists as a template; a failure prints, like the PowerShell bridge's non-Quiet path.
function _psc_check_update
    set -l out ("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" $argv 2>&1)
    set -l rc $status
    if test $rc -eq 0
        return 0
    end
    if test -n "$out"
        printf '\e[31m%s\e[0m\n' "$out"
    end
    return $rc
end

function _psc_run_status
    set -l out ("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" $argv 2>&1)
    set -l rc $status
    if test (count $out) -gt 0
        if test $rc -eq 0
            set_color green
        else
            set_color red
        end
        # One line per element: `printf`'s format is reused for every argument.
        # The CLI's own text is already line-per-item; a join with `(printf "\n")` collapsed it, because command substitution strips the newline.
        printf "%s\n" $out
        set_color normal
    end
    return $rc
end

# Run add/rm/update once in --json mode and render with the static templates (green done, yellow ownership warnings, red errors), mirroring PowerShell.
# The jobs arrive from python as `type / a / b` triples.
function _psc_run_rendered
    _psc_need_py; or return 1
    set -l cmd $argv[1]
    set -l raw ("$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR" --json $argv 2>/dev/null)
    set -l code $status
    set -l jobs (_psc_py -S -c '
import json,os,sys
cmd,raw,dd,lang=sys.argv[1:5]
try: env=json.loads(raw)
except Exception: env={}
if isinstance(env,dict) and env.get("ok") is False:
    err=env.get("error") or {}
    print("ERR"); print(""); print(err.get("message","") if isinstance(err,dict) else err)
    sys.exit(0)
# The envelope payload: the per-completion list, each item {name, ok, error?}.
results=((env.get("data") or {}).get("completions") or []) if isinstance(env,dict) else []
def settings_lang(name):
    try:
        s=json.load(open(dd+"/settings.json",encoding="utf-8"))
        per=((s.get("config") or {}).get("completion",{}) or {}).get(name,{}).get("language")
        if per: return per
        return (s.get("config") or {}).get("language","en-US")
    except Exception: return "en-US"
def mlang(name):
    for lf in (settings_lang(name), "en-US"):
        try:
            json.load(open(f"{dd}/completions/{name}/language/{lf}.json",encoding=\'utf-8\'))
            return lf
        except Exception: continue
    return "en-US"
try: settings=json.load(open(dd+"/settings.json",encoding="utf-8"))
except Exception: settings={}
aliasmap=settings.get("alias") or {}
stored_all=((settings.get("config",{}) or {}).get("completion",{}) or {})
def emit(t,a,b):
    print(t); print(a); print(b)
for r in results:
    if not isinstance(r,dict): continue
    name=r.get("name") or ""
    if not r.get("ok"):
        err=r.get("error") or {}
        emit("ERR",name,err.get("message","") if isinstance(err,dict) else err)
        continue
    if cmd=="rm":
        emit("TPL","rm.done",json.dumps({"Completion":name},ensure_ascii=False))
        continue
    if cmd in ("add","update"):
        disp=r.get("renamed_from","")
        disp=f"{disp} -> {name}" if disp else ""
        lf=mlang(name)
        try: man=json.load(open(f"{dd}/completions/{name}/language/{lf}.json",encoding=\'utf-8\'))
        except Exception: man={}
        try: cfgjson=json.load(open(f"{dd}/completions/{name}/config.json",encoding=\'utf-8\'))
        except Exception: cfgjson={}
        try: info=(json.load(open(f"{dd}/completions/psc/language/{lang}.json",encoding=\'utf-8\')) or {}).get("info",{})
        except Exception: info={}
        rows=[]
        if cfgjson.get("hooks") is not None:
            tip="".join(((info.get("completion",{}).get("enable_hooks",{}) or {}).get("tip",[]) or []))
            rows.append({"Name":"enable_hooks","Value":int(bool(cfgjson.get("hooks"))),"Tip":tip})
        for i in (man.get("config") or []):
            if isinstance(i,dict) and "name" in i:
                t=i.get("tip","")
                rows.append({"Name":i.get("name"),"Value":i.get("value"),
                 "Tip":t if isinstance(t,str) else "\n".join(t or [])})
        stored=stored_all.get(name,{}) or {}
        for row in rows:
            if stored.get(row["Name"]) is not None:
                row["Current"]=stored.get(row["Name"])
        emit("TPL",cmd+".done",json.dumps({"Completion":name,"Display":disp,
         "Alias":list(aliasmap.get(name) or [name]),"Configs":rows},ensure_ascii=False))
    for s in (r.get("skipped") or []):
        if isinstance(s,dict):
            emit("TPL","alias.skipped",json.dumps({"Alias":s.get("alias",""),"Owner":s.get("owner","")},ensure_ascii=False))
' "$cmd" "$raw" "$PSCOMPLETIONS_DATA_DIR" "$(_psc_lang psc)")
    set -l i 1
    while test $i -le (math (count $jobs) - 2)
        set -l rectype $jobs[$i]
        set -l a $jobs[(math $i + 1)]
        set -l b $jobs[(math $i + 2)]
        switch $rectype
            case ERR
                # a message without a name (e.g. `psc add` with no arguments) prints alone:
                # `: 参数不足。` reads like a stray colon
                set_color red
                if test -n "$a"
                    printf '%s: %s\n' "$a" "$b"
                else
                    printf '%s\n' "$b"
                end
                set_color normal
                set code 1
            case TPL
                set -l body (_psc_tpl $a "$b")
                if test $status -eq 0
                    for line in $body
                        echo $line
                    end
                end
            case '*'
                set_color red
                echo "$a"
                set_color normal
                set code 1
        end
        set i (math $i + 3)
    end
    return $code
end

# Pending notifications tail (module update persists; library added/removed are one-shot, update/renamed persist).
# Plain text: the info templates live in the PowerShell bridge; fish renders the same facts without them.
function _psc_render_pending
    _psc_need_py; or return 1
    set -l change "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
    test -f "$change"; or return 0
    # The module notice fires only for a remote version newer than the installed one (compared numerically inside); the library lists below render as a template.
    set -l out (_psc_py -S -c '
import json,sys
p,dd,marker,installed=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
try: c=json.load(open(p,encoding="utf-8"))
except Exception: raise SystemExit(1)
def newer(remote, installed):
    # Numeric segments: 8.0.10 is newer than 8.0.9, which a string compare gets wrong.
    # Unparseable on either side means "cannot tell", and the PowerShell bridge answers that with no notice either.
    try:
        r=[int(x) for x in str(remote).split(".")]
        i=[int(x) for x in str(installed).split(".")]
    except ValueError:
        return False
    n=max(len(r),len(i))
    return (r+[0]*n)[:n] > (i+[0]*n)[:n]
def emit(t,a,b):
    print(t); print(a); print(b)
mod=c.get("module")
if mod and newer(mod, installed):
    try:
        seen=open(marker,encoding="utf-8").read().strip()
    except Exception: seen=""
    if str(mod)!=seen:
        emit("MODULE",str(mod),"")
        try: open(marker,"w",encoding="utf-8").write(str(mod))
        except Exception: pass
upd=c.get("update") or []
add=c.get("added") or []
rm=c.get("removed") or []
ren=[]
for r in (c.get("renamed") or []):
    if isinstance(r,(list,tuple)) and len(r)==2: ren.append([str(r[0]),str(r[1])])
    else: ren.append([str(r),""])
if upd or add or rm or ren:
    emit("TPL","update_info",json.dumps({"Update":upd,"Added":add,"Removed":rm,"Renamed":ren},ensure_ascii=False))
if add or rm:
    c["added"]=[]; c["removed"]=[]
    try: json.dump(c,open(p,"w",encoding="utf-8"))
    except Exception: pass
' "$change" "$PSCOMPLETIONS_DATA_DIR" "$PSCOMPLETIONS_DATA_DIR/temp/.fish-module-notified" (_psc_module_version))
    set -l i 1
    while test $i -le (math (count $out) - 2)
        set -l rectype $out[$i]
        set -l a $out[(math $i + 1)]
        set -l b $out[(math $i + 2)]
        switch $rectype
            case MODULE
                _psc_tpl module.update "{\"NewVersion\":\"$a\"}"
                echo
            case TPL
                set -l body (_psc_tpl $a "$b")
                if test $status -eq 0
                    for line in $body
                        echo $line
                    end
                end
            case '*'
                echo "$a"
        end
        set i (math $i + 3)
    end
end

# Forwards to the binary; state-changing commands invalidate the cached init so the next Tab rebuilds aliasMap/config.
function psc
    _psc_need_py; or return 1
    if not test -x "$_PSC_BIN"
        echo "psc binary missing: $_PSC_BIN" >&2
        return 1
    end
    # Bare `psc` shows the module info page from static data, like PowerShell.
    if test (count $argv) -eq 0
        _psc_tpl description; or "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR"
        echo
        return 0
    end
    # `psc --self-update` (root-level flag): the engine detects how this copy was installed and says what updates it — a script install is updated right there, the rest is a command to run.
    if test "$argv[1]" = --self-update
        _psc_plain --self-update
        return $status
    end
    # `psc --reset` (PowerShell-only flag): confirm, wipe the data dir, re-seed.
    if test "$argv[1]" = --reset
        _psc_tpl reset.init_confirm
        echo
        read -n 1 -s -p " " key
        echo
        if test -n "$key"
            _psc_tpl confirm_cancel
            echo
            return 1
        end
        for entry in $PSCOMPLETIONS_DATA_DIR/*
            rm -rf $entry 2>/dev/null
        end
        mkdir -p "$PSCOMPLETIONS_DATA_DIR/completions"
        _psc_seed_psc
        set -g _PSC_INIT_OK 0
        _psc_init
        _psc_tpl reset.init_done
        echo
        return 0
    end
    # `--json` anywhere means the caller wants the machine contract: hand the invocation to the engine as it is — never colored, never rendered into a human page — and never prompted first: a machine caller cannot press a key (design/json.md §7).
    # With no command word it is the **root** response (§5), so this check comes before the flags-only info page below.
    if contains -- --json $argv
        # Verbatim: a failure is JSON as well, and color would break the contract.
        set -g _PSC_INIT_OK 0
        $_PSC_BIN --data $PSCOMPLETIONS_DATA_DIR $argv
        return $status
    end
    # Only flags and no command word: the module's info page, exactly like the bare call.
    # The binary's own usage text is an implementation detail, not what a user of the module sees.
    set -l has_cmd 0
    for arg in $argv
        if not string match -q -- '-*' "$arg"
            set has_cmd 1
        end
    end
    if test $has_cmd -eq 0
        _psc_tpl description; or "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR"
        echo
        return 0
    end
    # rm --all is destructive: confirm like the PowerShell bridge does.
    if test "$argv[1]" = rm; and contains -- --all $argv
        _psc_tpl rm.all_confirm
        echo
        read -n 1 -s -p " " key
        echo
        if test -n "$key"
            _psc_tpl confirm_cancel
            echo
            return 1
        end
        # The engine never prompts: the confirmation just given is the authorisation it needs.
        set argv $argv --yes
    end
    # A group reset (config / completion / alias) is not confirmed — not destructive enough — but the engine still requires authorisation (design/json.md §7).
    if contains -- --reset $argv
        set argv $argv --yes
    end
    set -l code 0
    switch $argv[1]
        case add rm
            # Rendered from --json (templates), never double-executed.
            _psc_run_rendered $argv
            set code $status
        case update
            # No argument is the library check: its payload is the four change lists, not a per-completion result set.
            # The plain list is dropped on success — the tail renders the same lists as a template below (the PowerShell bridge discards the CLI text the same way); a failure still prints.
            if test (count $argv) -eq 1
                _psc_check_update $argv
            else
                _psc_run_rendered $argv
            end
            set code $status
        case list info alias completion config
            # Queries print the CLI's text verbatim; anything that sets a value keeps the status path.
            # (PowerShell gets objects from `--json`; here the CLI's text is the interface.)
            set -l query 0
            switch $argv[1]
                case list info
                    set query 1
                case alias
                    test (count $argv) -eq 1; and set query 1
                case completion
                    # Reads print the CLI's text; only a value (--reset or a fourth arg) takes the status path — the PowerShell bridge routes the same way.
                    if test (count $argv) -ge 4; or contains -- --reset $argv
                        set query 0
                    else
                        set query 1
                    end
                case config
                    # `config` and `config <group>` are queries too; only a value or --reset makes it an action.
                    if test (count $argv) -ge 4; or contains -- --reset $argv
                        set query 0
                    else
                        set query 1
                    end
            end
            if test $query -eq 1
                _psc_plain $argv
                set code $status
            else
                _psc_run_status $argv
                set code $status
            end
        case '*'
            # An unrecognised command shows the module info page, exactly like the no-argument form: the module is discovered by browsing, not by an error.
            _psc_tpl description; or "$_PSC_BIN" --data "$PSCOMPLETIONS_DATA_DIR"
            echo
            return 0
    end
    switch $argv[1]
        case add rm update alias completion config init
            set -g _PSC_INIT_OK 0
    end
    # `config menu trigger_key <k>`: rebind the live key on success.
    if test $code -eq 0; and test "$argv[1]" = config; and test "$argv[2]" = menu; and test "$argv[3]" = trigger_key
        test -n "$argv[4]"; and _psc_bind_trigger $argv[4]
    end
    _psc_render_pending
    return $code
end

# --- trigger key binding -----------------------------------------------------
# The trigger key is read from settings.json `config.trigger_key` (default Tab) and mapped to a fish key name.
# Unknown names (or keys fish cannot express) warn and fall back to Tab.
function _psc_read_trigger_key
    if not _psc_need_py
        echo Tab
        return 0
    end
    set -l s "$PSCOMPLETIONS_DATA_DIR/settings.json"
    if not test -f "$s"
        echo Tab
        return 0
    end
    set -l k (_psc_py -S -c '
import json,sys
try:
    c=json.load(open(sys.argv[1],encoding=\'utf-8\')).get(\'config\',{}) or {}
    print(c.get(\'trigger_key\') or \'Tab\')
except Exception:
    print(\'Tab\')
' "$s" 2>/dev/null)
    test -n "$k"; or set k Tab
    echo $k
end

# PS trigger-key name -> fish key name; fails for a name fish cannot express.
# Explicit comparisons and regexes: glob character classes (`[A-Za-z]`) do not match in fish's `switch` / `string match -q`, only in `string match -r`.
function _psc_key_for --argument-names name
    if test "$name" = Tab
        echo tab
    else if test "$name" = Shift+Tab
        echo shift-tab
    else if test "$name" = Ctrl+Space
        echo ctrl-space
    else if string match -r -q '^Ctrl\+[A-Za-z]$' -- $name
        echo ctrl-(string lower -- (string sub -s 6 -- $name))
    else if string match -r -q '^Alt\+[A-Za-z]$' -- $name
        echo alt-(string lower -- (string sub -s 5 -- $name))
    else
        return 1
    end
end

function _psc_bind_trigger
    set -l name Tab
    test (count $argv) -ge 1; and test -n "$argv[1]"; and set name $argv[1]
    set -l key (_psc_key_for $name)
    if test -z "$key"
        echo "[PSCompletions] unsupported trigger_key '$name', using Tab." >&2
        set key tab
    end
    # Bind, and let fish validate the key name: it rejects one it cannot express (`bind: unknown modifier`).
    # `bind --key-names` only lists unmodified keys, so it cannot answer this.
    if not bind -M default $key _psc_complete 2>/dev/null
        if test "$key" != tab
            echo "[PSCompletions] fish cannot bind '$name' (key '$key'); using Tab." >&2
        end
        set key tab
        bind -M default $key _psc_complete 2>/dev/null
    end
    # The vi keymap too: a vi user's config may switch key modes after this file is sourced.
    bind -M insert $key _psc_complete 2>/dev/null
end

if status is-interactive
    _psc_bind_trigger (_psc_read_trigger_key)
end
