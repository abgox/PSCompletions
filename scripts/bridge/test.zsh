#!/usr/bin/env zsh
# Headless zsh bridge tests: build input via the bridge's own _psc_write_input, run psc-menu headless (build rewrites the input file), assert candidates.
# Usage: zsh -f scripts/bridge/test.zsh [repo-root]
setopt no_aliases
# The user's environment must not reach the tests: a bridge the user's rc already sourced blocks the `source` below — the bridges guard on `_PSC_LOADED` — leaving the suite testing the wrong file.
# (`-f` covers the rc files; it is also why the usage line above carries it.)
if [[ -n "${_PSC_LOADED:-}" ]]; then
    print -u2 "test.zsh: a PSCompletions bridge is already loaded in this shell; run the suite in a clean one"
    exit 1
fi
ROOT="${1:-${0:A:h:h:h}}"
BRIDGE="$ROOT/module/PSCompletions/PSCompletions.zsh"
export PSCOMPLETIONS_DATA_DIR=/tmp/psc-zsh-test
source "$BRIDGE"
# The bridge resolves its own bin/<platform>-<arch>; reuse that rather than guess one.
BIN="$_PSC_BIN_DIR/psc-menu$_psc_ext"

rm -rf "$PSCOMPLETIONS_DATA_DIR"
mkdir -p "$PSCOMPLETIONS_DATA_DIR/completions" "$PSCOMPLETIONS_DATA_DIR/temp/menu"
for c in git psc scoop; do
    ln -s "$ROOT/completions/$c" "$PSCOMPLETIONS_DATA_DIR/completions/$c"
done
cat > "$PSCOMPLETIONS_DATA_DIR/settings.json" <<'EOF'
{"alias":{"git":["git"],"psc":["psc"],"scoop":["scoop"]},"config":{"language":"en-US"}}
EOF
cat > "$PSCOMPLETIONS_DATA_DIR/temp/completions.json" <<'EOF'
{"update":{"demo-a":"v1","demo-b":"v1","git":"v9"},"meta":{"demo-a":{"id":"a","en-US":{"url":"https://example.com","description":"A"}},"demo-b":{"id":"b","en-US":{"url":"https://example.com","description":"B"}},"git":{"id":"git-id","en-US":{"url":"https://git-scm.com","description":"VCS"}}}}
EOF
rm -rf /tmp/psc-zsh-scratch && mkdir -p /tmp/psc-zsh-scratch && cd /tmp/psc-zsh-scratch || exit 1
git init -q . 2>/dev/null; git config user.email t@t.t 2>/dev/null; git config user.name t 2>/dev/null
echo x > f.txt; git add f.txt 2>/dev/null; git commit -qm init 2>/dev/null; git branch feat-x 2>/dev/null

PASS=0; FAIL=0
run_case() {
    local name="$1" cmd="$2" last="$3" hooks="$4" min="$5"
    shift 5
    local -a want=()
    while (( $# )) && [[ "$1" != "--" ]]; do want+=("$1"); shift; done
    (( $# )) && shift
    local manifest="$PSCOMPLETIONS_DATA_DIR/completions/$cmd/language/en-US.json"
    local in="$PSCOMPLETIONS_DATA_DIR/temp/menu/case-$name.json"
    local out="$PSCOMPLETIONS_DATA_DIR/temp/menu/case-$name-out.json"
    _psc_write_input "$in" "$cmd" "$last" "$manifest" "$hooks" 0 0 120 30 "$@"
    timeout -s KILL 10 "$BIN" "$in" --result "$out" >/dev/null 2>&1
    local res
    res="$(python3 - "$in" "$min" "${want[@]}" <<'PYEOF'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
if 'items' not in d:
    print("0|ENGINE-NO-REWRITE"); raise SystemExit
items=[i.get('completion_text','') for i in d.get('items',[])]
want=sys.argv[3:]
missing=[w for w in want if w not in items]
print(f"{len(items)}|{','.join(missing)}")
PYEOF
)"
    local n="${res%%|*}" missing="${res#*|}"
    if (( n >= min )) && [[ -z "$missing" ]]; then
        print "ok   $name ($n items)"; PASS=$((PASS+1))
    else
        print "FAIL $name (n=$n min=$min missing=[$missing])"; FAIL=$((FAIL+1))
    fi
    rm -f "$in" "$out"
}

run_case git-root     git 0 0 50 add branch status -- --
run_case git-pending  git 0 0 2  stash status -- st
run_case git-add      git 1 0 3  --all -- add
run_case psc-root     psc 0 0 5  add rm update config -- --
run_case psc-add      psc 1 1 2  demo-a demo-b -- add
run_case git-checkout git 1 1 2  feat-x -- checkout
run_case scoop-root   scoop 0 1 5 install bucket -- --
run_case git-eq       git 0 0 1  --ref-format=files -- init --ref-format=f

print -- "--- gate checks ---"
gate() {
    local got="$(_psc_hooks_enabled "$1")"
    if [[ "$got" == "$2" ]]; then print "ok   gate-$1=$got"; PASS=$((PASS+1))
    else print "FAIL gate-$1=$got want $2"; FAIL=$((FAIL+1)); fi
}
gate git 1
gate psc 1
gate nosuch 0
python3 - "$PSCOMPLETIONS_DATA_DIR/settings.json" <<'PYEOF'
import json,sys
p=sys.argv[1]; s=json.load(open(p,encoding='utf-8'))
s['config']['completion']={'git':{'enable_hooks':0}}
json.dump(s,open(p,'w',encoding='utf-8'))
PYEOF
gate git 0
_PSC_HOOKS=()

print -- "--- apply checks ---"
apply_case() {
    LBUFFER="$2"; RBUFFER="$3"; _psc_apply "$4" "$5"
    local got="${LBUFFER}${RBUFFER}"
    if [[ "$got" == "$6" ]]; then print "ok   apply-$1"; PASS=$((PASS+1))
    else print "FAIL apply-$1 got [$got] want [$6]"; FAIL=$((FAIL+1)); fi
}
apply_case end-of-line  'git chec'      ''        'checkout' 0 'git checkout '
apply_case mid-word     'git che'       'ckout'   'checkout' 0 'git checkout '
apply_case after-space  'git '          ''        'status'   0 'git status '
apply_case next-word    'git '          ' status' 'status'   0 'git status status'
apply_case attached-head 'git log --format=' '' '--format=' 0 'git log --format='
apply_case attached-filled 'git log --format=' '' '--format=pretty' 0 'git log --format=pretty '
apply_case engine-nospace 'git log --format=' '' '--format=x' 1 'git log --format=x'
_PSC_CFG[enable_append_space]=0
apply_case no-append-space 'git ' '' 'status' 0 'git status'
unset '_PSC_CFG[enable_append_space]'

print -- "--- apply: word boundary respects escapes and quotes ---"
# A path with a space arrives escaped (`/tmp/psc\ t/`) or quoted (`'/tmp/psc t/'`).
# The naive `${before##* }` split cut at the escaped space, so the pick was concatenated after the old text instead of replacing it — the defect the interactive pass reported.
apply_case escaped-dir  'cd /tmp/psc\ t/'       '' '/tmp/psc t/az zdir/'  1 'cd /tmp/psc t/az zdir/'
apply_case quoted-dir   "cd '/tmp/psc t/'"      '' '/tmp/psc t/az zdir/'  1 "cd /tmp/psc t/az zdir/"
apply_case escaped-file 'cat /tmp/psc\ t/plain' '' '/tmp/psc t/plain.txt' 0 'cat /tmp/psc t/plain.txt '
apply_case plain-word   'git chec'              '' 'checkout'             0 'git checkout '

print -- "--- items menu: the candidate list travels in a file, not argv/env ---"
# A host capture can run to thousands of entries; passing them as argv (or in an environment variable) overflows ARG_MAX — the interactive pass hit exactly that ("_psc_items_menu:11: argument list too long") on a plain `pyt` + Tab capture.
_probe="$PSCOMPLETIONS_DATA_DIR/temp/menu/items-probe.json"
rm -f "$_probe"
{
    _psc_spawn() {
        cp "$1" "$_probe" 2>/dev/null
        _PSC_SPAWN_STATUS=cancel _PSC_SPAWN_WORDS='' _PSC_SPAWN_NOSPACE=0 _PSC_SPAWN_INDEX=''
    }
    _PSC_CAND_DISP=() _PSC_CAND_COMP=() _PSC_CAND_TIP=()
    for (( _psc_i = 1; _psc_i <= 20000; _psc_i++ )); do
        _PSC_CAND_DISP+=("cand-$_psc_i.txt") _PSC_CAND_COMP+=("/tmp/x/cand-$_psc_i.txt") _PSC_CAND_TIP+=('')
    done
    _PSC_CFG=()
    _psc_items_menu cd "pyth" 0
}
_psc_items_n="$(python3 - "$_probe" <<'PYEOF'
import json,sys
try: d=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: print(0); raise SystemExit
print(len(d.get('items') or []))
PYEOF
)"
_psc_items_leaf="$(python3 - "$_probe" <<'PYEOF'
import json,sys
try: d=json.load(open(sys.argv[1],encoding='utf-8'))
except Exception: print(''); raise SystemExit
items=d.get('items') or []
print('%s|%s' % (items[0].get('list_item_text') if items else '', items[0].get('completion_text') if items else ''))
PYEOF
)"
rm -f "$_probe"
[[ "$_psc_items_n" == "20000" ]] && { print "ok   items: 20000 candidates accepted"; PASS=$((PASS+1)) } \
    || { print "FAIL items: 20000 candidates accepted got [$_psc_items_n]"; FAIL=$((FAIL+1)) }
[[ "$_psc_items_leaf" == "cand-1.txt|/tmp/x/cand-1.txt" ]] && { print "ok   items: display is the leaf, insert is the full text"; PASS=$((PASS+1)) } \
    || { print "FAIL items: leaf display got [$_psc_items_leaf]"; FAIL=$((FAIL+1)) }

print -- "--- dispatch routing ---"
_psc_build_menu() { print BUILD }
_psc_native() { print NATIVE }
route_case() {
    LBUFFER="$2"
    local got="$(_psc_complete)"
    if [[ "$got" == "$3" ]]; then print "ok   route-$1"; PASS=$((PASS+1))
    else print "FAIL route-$1 got [$got] want [$3]"; FAIL=$((FAIL+1)); fi
}
route_case path-dot  'git add ./'   NATIVE
route_case path-home 'git add ~/'   NATIVE
route_case path-abs  'git add /etc' NATIVE
route_case path-win  'git add .\s'  NATIVE
route_case word      'git add src'  BUILD
route_case space     'git add '     BUILD
route_case typing    'git che'      BUILD
route_case cmd-word  'git'          NATIVE
route_case unknown   'foo bar'      NATIVE
route_case cmd-path  'cd ~/'        NATIVE

print -- "--- config wiring ---"
CFG_DIR=/tmp/psc-zsh-cfg
rm -rf "$CFG_DIR"; mkdir -p "$CFG_DIR/completions" "$CFG_DIR/temp/menu"
ln -s "$ROOT/completions/psc" "$CFG_DIR/completions/psc"
cat > "$CFG_DIR/settings.json" <<'EOF'
{"alias":{"psc":["psc"]},"config":{"language":"en-US","filter_mode":"subsequence","show_mode":"altscreen-top","color_focus":"blue","enable_list_loop":0,"enable_apply_when_single":1,"enable_sort_by_history":0,"switch":"»","stay":"¿"}}
EOF
echo '{"update":{},"meta":{}}' > "$CFG_DIR/temp/completions.json"
_CFG_SAVE="$PSCOMPLETIONS_DATA_DIR"
PSCOMPLETIONS_DATA_DIR="$CFG_DIR"
_PSC_INIT_OK=0; _PSC_ALIAS=(); _PSC_CFG=(); _PSC_LANGCACHE=(); _PSC_HOOKS=()
_psc_init
_psc_write_input "$CFG_DIR/in.json" psc 1 "$CFG_DIR/completions/psc/language/en-US.json" 0 0 0 120 30
cfg_check="$(python3 - "$CFG_DIR/in.json" <<'PYEOF'
import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8'))['config']
ok=[]
ok.append(c['flags']['filter_mode']=='subsequence')
ok.append(c['flags']['show_mode']=='altscreen-top')
ok.append(c['flags']['color_focus']=='blue')
ok.append(c['flags']['enable_list_loop'] is False)
ok.append(c['flags']['enable_apply_when_single'] is True)
ok.append(c['context_switch']=='»' and c['context_stay']=='¿')
ok.append('order' not in json.load(open(sys.argv[1],encoding='utf-8')))
print('ok' if all(ok) else 'bad:'+str(ok))
PYEOF
)"
if [[ "$cfg_check" == ok ]]; then print "ok   config-flags"; PASS=$((PASS+1))
else print "FAIL config-flags $cfg_check"; FAIL=$((FAIL+1)); fi

tk="$(printf x | _psc_read_trigger_key)"
if [[ "$tk" == Tab ]]; then print "ok   trigger-key-default"; PASS=$((PASS+1))
else print "FAIL trigger-key-default got $tk"; FAIL=$((FAIL+1)); fi
python3 - "$CFG_DIR/settings.json" <<'PYEOF'
import json,sys
p=sys.argv[1]; s=json.load(open(p,encoding='utf-8')); s['config']['trigger_key']='Ctrl+Space'
json.dump(s,open(p,'w',encoding='utf-8'))
PYEOF
tk="$(printf x | _psc_read_trigger_key)"
if [[ "$tk" == "Ctrl+Space" ]]; then print "ok   trigger-key-read"; PASS=$((PASS+1))
else print "FAIL trigger-key-read got $tk"; FAIL=$((FAIL+1)); fi
PSCOMPLETIONS_DATA_DIR="$_CFG_SAVE"
rm -rf "$CFG_DIR"

print -- "--- reset ---"
RST_DIR=/tmp/psc-zsh-rst
rm -rf "$RST_DIR"; mkdir -p "$RST_DIR/completions"
ln -s "$ROOT/completions/psc" "$RST_DIR/completions/psc"
_SAVE2="$PSCOMPLETIONS_DATA_DIR"; PSCOMPLETIONS_DATA_DIR="$RST_DIR"
_PSC_INIT_OK=0; _PSC_ALIAS=(); _PSC_CFG=(); _PSC_LANGCACHE=(); _PSC_HOOKS=()
_psc_init
mkdir -p "$RST_DIR/completions/junk"; echo '{}' > "$RST_DIR/completions/junk/config.json"
printf '\n' | psc --reset >/dev/null 2>&1
if [[ -d "$RST_DIR/completions/psc" && ! -d "$RST_DIR/completions/junk" && -f "$RST_DIR/settings.json" ]]; then
    print "ok   reset"; PASS=$((PASS+1))
else
    print "FAIL reset"; FAIL=$((FAIL+1))
fi
PSCOMPLETIONS_DATA_DIR="$_SAVE2"; rm -rf "$RST_DIR"

print -- "--- fresh data dir (offline first run) ---"
FRESH=/tmp/psc-zsh-fresh
rm -rf "$FRESH"
_SAVE="$PSCOMPLETIONS_DATA_DIR"; PSCOMPLETIONS_DATA_DIR="$FRESH"
_PSC_INIT_OK=0; _PSC_ALIAS=(); _PSC_CFG=(); _PSC_LANGCACHE=(); _PSC_HOOKS=()
HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 _psc_init
if [[ -f "$FRESH/completions/psc/config.json" && "${_PSC_ALIAS[psc]:-}" == psc ]]; then
    print "ok   fresh-offline"; PASS=$((PASS+1))
else
    print "FAIL fresh-offline"; FAIL=$((FAIL+1))
fi
PSCOMPLETIONS_DATA_DIR="$_SAVE"; rm -rf "$FRESH"

print -- "--- management text path + dependency guard ---"
[[ "$_PSC_PY" == /* ]] && { print "ok   py-absolute"; PASS=$((PASS+1)) } || { print "FAIL py-absolute [$_PSC_PY]"; FAIL=$((FAIL+1)) }
out="$(psc 2>&1)"
[[ "$out" == *"PSCompletions"* ]] && { print "ok   psc-bare-description"; PASS=$((PASS+1)) } || { print "FAIL psc-bare-description"; FAIL=$((FAIL+1)) }
# Flags only, no command word: with `--json` that is the **root** response (design/json.md §5) — the run's own facts — never the info page, and never the binary's own usage text.
out="$(psc --json 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == "{"* ]] \
    && { print "ok   root-json-for-json-flag"; PASS=$((PASS+1)) } || { print "FAIL root-json-for-json-flag rc=$rc [$out]"; FAIL=$((FAIL+1)) }
_SAVE_PY="$_PSC_PY"
_PSC_PY=""; _PSC_PY_WARNED=0
out="$(_psc_tpl description 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == *PSCompletions* ]] && { print "ok   render-without-python"; PASS=$((PASS+1)) } || { print "FAIL render-without-python rc=$rc [$out]"; FAIL=$((FAIL+1)) }
_PSC_PY_WARNED=0
out="$(psc 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" != *"Usage: psc"* ]] && { print "ok   missing-py-psc"; PASS=$((PASS+1)) } || { print "FAIL missing-py-psc rc=$rc [$out]"; FAIL=$((FAIL+1)) }
_PSC_PY="$_SAVE_PY"

print -- "--- data dir default (per platform) ---"
_SAVE_PLATFORM=$_psc_platform
_psc_platform=darwin
[[ "$(_psc_default_data_dir)" == "$HOME/Library/Application Support/com.abgox/PSCompletions" ]] \
    && { print "ok   datadir-macos"; PASS=$((PASS+1)) } || { print "FAIL datadir-macos"; FAIL=$((FAIL+1)) }
_psc_platform=windows; APPDATA=/tmp/appdata
[[ "$(_psc_default_data_dir)" == "/tmp/appdata/com.abgox/PSCompletions" ]] \
    && { print "ok   datadir-windows"; PASS=$((PASS+1)) } || { print "FAIL datadir-windows"; FAIL=$((FAIL+1)) }
unset APPDATA
_psc_platform=linux; XDG_DATA_HOME=/tmp/xdg
[[ "$(_psc_default_data_dir)" == "/tmp/xdg/com.abgox/PSCompletions" ]] \
    && { print "ok   datadir-linux-xdg"; PASS=$((PASS+1)) } || { print "FAIL datadir-linux-xdg"; FAIL=$((FAIL+1)) }
unset XDG_DATA_HOME
[[ "$(_psc_default_data_dir)" == "$HOME/.local/share/com.abgox/PSCompletions" ]] \
    && { print "ok   datadir-linux-home"; PASS=$((PASS+1)) } || { print "FAIL datadir-linux-home"; FAIL=$((FAIL+1)) }
_psc_platform=$_SAVE_PLATFORM

print -- "--- language resolution is independent of _psc_init ---"
# `psc` can run before the first Tab; _PSC_CFG is empty then, so the module language must come from settings.json — the cache holds nothing to fall back on.
_SAVE_SETTINGS="$(cat "$PSCOMPLETIONS_DATA_DIR/settings.json")"
print -r -- '{"alias":{"git":["git"],"psc":["psc"],"scoop":["scoop"]},"config":{"language":"zh-CN"}}' > "$PSCOMPLETIONS_DATA_DIR/settings.json"
_PSC_CFG=(); _PSC_LANGCACHE=()
lang="$(_psc_lang psc)"
[[ "$lang" == zh-CN ]] && { print "ok   lang-without-init"; PASS=$((PASS+1)) } || { print "FAIL lang-without-init lang=$lang"; FAIL=$((FAIL+1)) }
print -r -- "$_SAVE_SETTINGS" > "$PSCOMPLETIONS_DATA_DIR/settings.json"
_PSC_CFG=(); _PSC_LANGCACHE=()

print -- "--- per-completion manifest language (the bridge's own share) ---"
# The engine renders the tips, so the *display* language is not the bridge's business — but which manifest is handed to the engine is.
# The rule (the same python in all three ports): per-completion override -> module-declared -> global, and a value the completion does not declare falls back to the completion's first declared language.
lang_case() { # name settings-json cmd want
    _PSC_CFG=(); _PSC_LANGCACHE=()
    print -r -- "$2" > "$PSCOMPLETIONS_DATA_DIR/settings.json"
    local got; got="$(_psc_lang "$3" 2>/dev/null)"
    [[ "$got" == "$4" ]] && { print "ok   lang-$1"; PASS=$((PASS+1)) } || {
        print "FAIL lang-$1 got=[$got] want=[$4]"; FAIL=$((FAIL+1)) }
}
lang_case override-declared   '{"config":{"language":"en-US","completion":{"git":{"language":"zh-CN"}}}}' git zh-CN
lang_case override-undeclared '{"config":{"language":"en-US","completion":{"git":{"language":"fr-FR"}}}}' git en-US
lang_case global-declared     '{"config":{"language":"zh-CN"}}' git zh-CN
lang_case no-settings         '{}' git en-US
print -r -- "$_SAVE_SETTINGS" > "$PSCOMPLETIONS_DATA_DIR/settings.json"
_PSC_CFG=(); _PSC_LANGCACHE=()

print -- "--- a config read is plain data, not a status ---"
# Color is the bridge's status convention, but a *value* is data: `v=$(psc config <g> <k>)` must come back clean.
# Failures still take the red path.
_READ_STUB="$PSCOMPLETIONS_DATA_DIR/temp/read-stub.sh"
print -r -- '#!/bin/sh' > "$_READ_STUB"
print -r -- 'echo "enable_cache: 0"' >> "$_READ_STUB"
print -r -- 'exit 0' >> "$_READ_STUB"
chmod +x "$_READ_STUB"
_SAVE_BIN_R=$_PSC_BIN; _PSC_BIN=$_READ_STUB
_got_cfg="$(psc config 2>&1)"
if [[ "$_got_cfg" == *$'\e['* ]]; then
    print "FAIL query-plain got color [$_got_cfg]"; FAIL=$((FAIL+1))
elif [[ "$_got_cfg" == *"enable_cache: 0"* ]]; then
    print "ok   query-plain"; PASS=$((PASS+1))
else
    print "FAIL query-plain got [$_got_cfg]"; FAIL=$((FAIL+1))
fi
_got_read="$(psc config menu enable_cache 2>&1)"
if [[ "$_got_read" == *$'\e['* ]]; then
    print "FAIL read-plain got color [$_got_read]"; FAIL=$((FAIL+1))
elif [[ "$_got_read" == *"enable_cache: 0"* ]]; then
    print "ok   read-plain"; PASS=$((PASS+1))
else
    print "FAIL read-plain got [$_got_read]"; FAIL=$((FAIL+1))
fi

_got_read="$(psc config menu enable_cache 2>&1)"
_PSC_BIN=$_SAVE_BIN_R
rm -f "$_READ_STUB"
print -- "--- management output is a terminated line ---"
# The renderer returns a fragment (no trailing newline); the caller terminates each line it prints.
# zsh marks a missed one with PROMPT_EOL_MARK ('%'), bash hides it.
_ends_nl() { [[ -s "$1" && -z "$(tail -c 1 "$1")" ]]; }
_TL="$PSCOMPLETIONS_DATA_DIR/temp/tpl-line.txt"
_STUB_BIN="$PSCOMPLETIONS_DATA_DIR/temp/stub-bin.sh"
print -r -- '#!/bin/sh' > "$_STUB_BIN"
print -r -- "case \"\$*\" in *\" tpl \"*) exec \"$_PSC_BIN\" \"\$@\" ;; esac" >> "$_STUB_BIN"
print -r -- 'case "$*" in *" update") printf "Updatable completions:\\n  git\\n"; exit 0 ;; esac' >> "$_STUB_BIN"
print -r -- 'echo "{\"ok\":true,\"data\":{\"completions\":[{\"name\":\"git\",\"ok\":true}]}}"' >> "$_STUB_BIN"
chmod +x "$_STUB_BIN"
_SAVE_BIN=$_PSC_BIN; _PSC_BIN=$_STUB_BIN
_psc_run_rendered rm git > "$_TL" 2>/dev/null; rc=$?
[[ $rc -eq 0 && "$(wc -l < "$_TL")" -eq 1 && -n "$(cat "$_TL")" ]] \
    && { print "ok   rendered-line-terminated"; PASS=$((PASS+1)) } || { print "FAIL rendered-line-terminated rc=$rc lines=$(wc -l < "$_TL")"; FAIL=$((FAIL+1)) }
print -r -- '{"update":["git"]}' > "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
_psc_render_pending > "$_TL" 2>/dev/null
_ends_nl "$_TL" && { print "ok   notification-line-terminated"; PASS=$((PASS+1)) } || { print "FAIL notification-line-terminated"; FAIL=$((FAIL+1)) }
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
# Every python stdout passes through _psc_py: CR stripped, exit code kept.
_CRLF_STUB="$PSCOMPLETIONS_DATA_DIR/temp/crlf-stub.sh"
print -r -- '#!/bin/sh' > "$_CRLF_STUB"
print -r -- 'printf "a\\r\\n"; exit 3' >> "$_CRLF_STUB"
chmod +x "$_CRLF_STUB"
_SAVE_PY=$_PSC_PY; _PSC_PY="$_CRLF_STUB"
out="$(_psc_py -S 2>/dev/null)"; rc=$?
[[ "$out" == "a" && $rc -eq 3 ]] \
    && { print "ok   psc_py strips CR and keeps exit code"; PASS=$((PASS+1)) } || { print "FAIL psc_py strips CR and keeps exit code out=[$out] rc=$rc"; FAIL=$((FAIL+1)) }
_PSC_PY=$_SAVE_PY
# A Windows-native python writes CRLF even to pipes: arithmetic on its output must not break (the `${texts[$idx]}` failure on git bash).
# Hermetic on purpose: no settings, no hooks.lua, no shared cache — only the exact gate shape.
_REALPY="$(command -v python3)"
_CRLF_PROXY="$PSCOMPLETIONS_DATA_DIR/temp/crlf-proxy.sh"
print -r -- '#!/bin/sh' > "$_CRLF_PROXY"
print -r -- "\"$_REALPY\" \"\$@\" | tr '\\n' '\\r\\n'" >> "$_CRLF_PROXY"
chmod +x "$_CRLF_PROXY"
_SAVE_PY=$_PSC_PY; _PSC_PY="$_CRLF_PROXY"
eh="$(_psc_py -S - <<'PYEOF'
print(1)
PYEOF
)"
branch="$({ if (( ! eh )); then print disabled; else print enabled; fi; } 2>"$PSCOMPLETIONS_DATA_DIR/temp/crlf-err.txt")"
[[ "$branch" == enabled && ! -s "$PSCOMPLETIONS_DATA_DIR/temp/crlf-err.txt" ]] \
    && { print "ok   crlf-python does not break arithmetic"; PASS=$((PASS+1)) } || { print "FAIL crlf-python does not break arithmetic branch=[$branch]"; FAIL=$((FAIL+1)) }
_PSC_PY=$_SAVE_PY
# The module notice fires only for a version newer than the installed one: an equal value is "nothing to do", not an update.
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/.zsh-module-notified"
_INSTALLED="$(_psc_module_version)"
print -r -- "{\"module\":\"$_INSTALLED\"}" > "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
_psc_render_pending > "$_TL" 2>/dev/null
[[ "$(cat "$_TL")" != *"has updated the version"* ]] \
    && { print "ok   module-equal-version-is-silent"; PASS=$((PASS+1)) } || { print "FAIL module-equal-version-is-silent [$(cat "$_TL")]"; FAIL=$((FAIL+1)) }
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/.zsh-module-notified"
print -r -- "{\"module\":\"${_INSTALLED%.*}.99\"}" > "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
_psc_render_pending > "$_TL" 2>/dev/null
[[ "$(cat "$_TL")" == *"has updated the version"* ]] \
    && { print "ok   module-newer-version-notifies"; PASS=$((PASS+1)) } || { print "FAIL module-newer-version-notifies [$(cat "$_TL")]"; FAIL=$((FAIL+1)) }
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/change.json" "$PSCOMPLETIONS_DATA_DIR/temp/.zsh-module-notified"
# A no-arg update drops the CLI's plain list on success — the tail renders the same lists as a template, so each appears once; the one-shot added/removed are still consumed.
print -r -- '{"update":["git"],"added":["new-one"],"removed":[],"renamed":[]}' > "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
out="$(psc update 2>&1)"
[[ "$out" == *"has updated the completion library"* && "$out" != *"Updatable completions"* ]] \
    && { print "ok   no-arg-update-renders-template-once"; PASS=$((PASS+1)) } || { print "FAIL no-arg-update-renders-template-once [$out]"; FAIL=$((FAIL+1)) }
python3 -c "import json;assert json.load(open('$PSCOMPLETIONS_DATA_DIR/temp/change.json'))['added']==[],'one-shots left unconsumed'" \
    && { print "ok   no-arg-update-consumes-one-shots"; PASS=$((PASS+1)) } || { print "FAIL no-arg-update-consumes-one-shots"; FAIL=$((FAIL+1)) }
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
# A failed check still prints — dropping the plain text must never swallow an error.
print -r -- '#!/bin/sh' > "$PSCOMPLETIONS_DATA_DIR/temp/fail-bin.sh"
print -r -- 'echo "error: boom"; exit 1' >> "$PSCOMPLETIONS_DATA_DIR/temp/fail-bin.sh"
chmod +x "$PSCOMPLETIONS_DATA_DIR/temp/fail-bin.sh"
_SAVE_BIN2=$_PSC_BIN; _PSC_BIN="$PSCOMPLETIONS_DATA_DIR/temp/fail-bin.sh"
out="$(_psc_check_update update 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"error: boom"* ]] \
    && { print "ok   failed-check-still-prints"; PASS=$((PASS+1)) } || { print "FAIL failed-check-still-prints rc=$rc [$out]"; FAIL=$((FAIL+1)) }
_PSC_BIN=$_SAVE_BIN2
# `--json` anywhere is the machine contract: never colored, never rendered into a page.
out="$(psc list --json 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == *'"ok":true'* && "$out" != *$'\033'* ]] \
    && { print "ok   json-is-never-colored"; PASS=$((PASS+1)) } || { print "FAIL json-is-never-colored rc=$rc [$out]"; FAIL=$((FAIL+1)) }
out="$(psc config core language --json 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" != *$'\033'* ]] \
    && { print "ok   json-after-args"; PASS=$((PASS+1)) } || { print "FAIL json-after-args rc=$rc [$out]"; FAIL=$((FAIL+1)) }
_PSC_BIN=$_SAVE_BIN

print -- "--- compadd parsing (native capture) ---"
# The native path captures compsys candidates by intercepting compadd; the parser is pure, so it is covered here rather than through a terminal.
_psc_parse_case() {
    local name="$1" want="$2"; shift 2
    _PSC_CAND_COMP=() _PSC_CAND_DISP=() _PSC_CAND_TIP=()
    _psc_compadd_parse "$@"
    local got="${(j:,:)_PSC_CAND_COMP}|${(j:,:)_PSC_CAND_DISP}|${(j:,:)_PSC_CAND_TIP}"
    [[ "$got" == "$want" ]] && { print "ok   $name"; PASS=$((PASS+1)) } \
        || { print "FAIL $name"; print "      want=[$want]"; print "      got =[$got]"; FAIL=$((FAIL+1)) }
}
typeset -a p_fruits=(apple banana) p_cmds=(add status) p_descs=("Add files" "Show status")
typeset -A p_colors=(red 1 green 2)
_psc_parse_case "compadd literals" "apple,banana|apple,banana|," -- apple banana
_psc_parse_case "compadd -a array" "apple,banana|apple,banana|," -a p_fruits
_psc_parse_case "compadd -a after -" "apple,banana|apple,banana|," -a -J -default- - p_fruits
_psc_parse_case "compadd clustered -ld" "add,status|add,status|Add files,Show status" -ld p_descs -a p_cmds
_psc_parse_case "compadd -P/-S" "--color=always ,--color=auto |--color=always ,--color=auto |," -P '--color=' -S ' ' always auto
_psc_parse_case "compadd -p/-s hidden" "~/xalpha/|alpha|" -p '~/x' -s '/' alpha
_psc_parse_case "compadd -O skipped" "||" -O p_stash -a p_fruits
_psc_parse_case "compadd -k assoc keys" "red,green|red,green|," -k p_colors

print -- "--- watchdog restores the terminal modes the menu enabled ---"
# A force-killed menu cannot turn off crossterm's modes itself.
# Leaving mouse capture on made the terminal keep reporting `ESC [ < b;x;y M` as literal input and the shell unusable (found by hand); every watchdog site must write the whole set, not just leave the alt screen.
_reset_missing=""
for _seq in '?1000l' '?1002l' '?1003l' '?1006l' '?1015l' '?1049l' '?25h' '?2004l'; do
    [[ "$_PSC_RESET_TERM" == *"$_seq"* ]] || _reset_missing+=" $_seq"
done
[[ -z "$_reset_missing" ]] && { print "ok   reset-term-covers-modes"; PASS=$((PASS+1)) } \
    || { print "FAIL reset-term-covers-modes missing:$_reset_missing"; FAIL=$((FAIL+1)) }
_reset_sites="$(grep -c '_PSC_RESET_TERM' "$BRIDGE")"
[[ "$_reset_sites" -ge 2 ]] && { print "ok   reset-term-used-by-watchdogs"; PASS=$((PASS+1)) } \
    || { print "FAIL reset-term-used-by-watchdogs sites=$_reset_sites"; FAIL=$((FAIL+1)) }
_flush_sites="$(grep -c 'tcflush' "$BRIDGE")"
[[ "$_flush_sites" -ge 1 ]] && { print "ok   reset-term-discards-queued-input"; PASS=$((PASS+1)) } \
    || { print "FAIL reset-term-discards-queued-input sites=$_flush_sites"; FAIL=$((FAIL+1)) }

print -- "--- no-match auto-apply: the engine's input status carries the filter text ---"
# `enable_apply_when_no_match`: the menu cannot match, so the engine returns the filter text as {status:input,text} and the host applies it like a selected candidate (the triggering key included, as the PS bridge shows).
# Each port has its own copy of the parser, so each asserts it.
[[ "$(grep -c "s=='input'" "$BRIDGE")" -ge 1 ]] && { print "ok   input-status-mapped"; PASS=$((PASS+1)) } \
    || { print "FAIL input-status-mapped"; FAIL=$((FAIL+1)) }

print -- "--- native enumeration fallback (no compsys) ---"
# Without compinit there is nothing to capture, so the bridge enumerates candidates itself (bash's compgen fallback): command names in command position, else paths.
rm -rf /tmp/psc-enum-test && mkdir -p /tmp/psc-enum-test/alpha/inner /tmp/psc-enum-test/beta
touch /tmp/psc-enum-test/gamma.txt /tmp/psc-enum-test/alpha/f.txt
_SAVE_PWD="$PWD"
cd /tmp/psc-enum-test
_psc_enum_check() {
    local name="$1" want="$2" before="$3"
    _psc_enumerate "$before"
    local got="${(oj:,:)_PSC_CAND_COMP}|${(oj:,:)_PSC_CAND_DISP}"
    [[ "$got" == "$want" ]] && { print "ok   $name"; PASS=$((PASS+1)) } || {
        print "FAIL $name"; print "      want=[$want]"; print "      got =[$got]"; FAIL=$((FAIL+1)) }
}
_psc_enum_check "enum: empty token"    "alpha,beta,gamma.txt|alpha/,beta/,gamma.txt" "cd "
_psc_enum_check "enum: typed prefix"   "alpha|alpha/" "cd al"
_psc_enum_check "enum: keeps ./"       "./alpha|alpha/" "cd ./al"
_psc_enum_check "enum: absolute dir"   "/tmp/psc-enum-test/alpha,/tmp/psc-enum-test/beta,/tmp/psc-enum-test/gamma.txt|alpha/,beta/,gamma.txt" "cd /tmp/psc-enum-test/"
_psc_enum_check "enum: subdir prefix"  "alpha/f.txt,alpha/inner|f.txt,inner/" "cd alpha/"
_psc_enum_check "enum: no match"       "|" "cd zzz"
cd "$_SAVE_PWD"

print -- "--- items mode: the bridge forwards the tokens, the engine derives the filter ---"
# One rule for all hosts: the bridge forwards `arg_tokens` + `treat_last_as_complete`, the engine derives `initial_filter` (and ignores it when it matches nothing).
_probe_i="$PSCOMPLETIONS_DATA_DIR/temp/menu/items-args.json"
rm -f "$_probe_i"
{
    _psc_spawn() {
        cp "$1" "$_probe_i" 2>/dev/null
        _PSC_SPAWN_STATUS=cancel _PSC_SPAWN_WORDS='' _PSC_SPAWN_NOSPACE=0 _PSC_SPAWN_INDEX=''
    }
    _PSC_CAND_DISP=("python3") _PSC_CAND_COMP=("python3") _PSC_CAND_TIP=('')
    _PSC_CFG=()
    _psc_items_menu cd "pyth" 0
}
_shared_i="$(python3 - "$_probe_i" <<'PYEOF'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
print('args=%s last=%s' % (','.join(d.get('arg_tokens') or []), d.get('treat_last_as_complete')))
PYEOF
)"
timeout -s KILL 5 "$_PSC_MENU" "$_probe_i" --result "$_probe_i-out" >/dev/null 2>&1
_init_i="$(python3 - "$_probe_i" <<'PYEOF'
import json,sys
print(json.load(open(sys.argv[1],encoding='utf-8')).get('initial_filter') or '')
PYEOF
)"
rm -f "$_probe_i" "$_probe_i-out"
[[ "$_shared_i" == "args=pyth last=False" ]] && { print "ok   items-forwards-tokens"; PASS=$((PASS+1)) } \
    || { print "FAIL items-forwards-tokens got [$_shared_i]"; FAIL=$((FAIL+1)) }
[[ "$_init_i" == "^pyth" ]] && { print "ok   engine-derives-initial-filter"; PASS=$((PASS+1)) } \
    || { print "FAIL engine-derives-initial-filter got [$_init_i]"; FAIL=$((FAIL+1)) }

print -- "--- native candidates are ranked through --sort ---"
# enable_sort_by_history: the candidate set must survive the ranking pass (a permutation) with display/tip still aligned to their candidate; ranking quality is the engine's own concern, and with the key off the order must be left untouched.
export HISTFILE=/tmp/psc-cfg-probe/hist2
: > "$HISTFILE"
_PSC_CFG=(); _PSC_CFG[enable_sort_by_history]=1
_PSC_CAND_COMP=(alpha beta gamma); _PSC_CAND_DISP=("alpha/" "beta/" "gamma.txt"); _PSC_CAND_TIP=(t-alpha '' '')
_psc_sort_candidates git git
_psc_sorted_ok=1
for _psc_i in {1..${#_PSC_CAND_COMP}}; do
    case "${_PSC_CAND_COMP[_psc_i]}" in
        alpha) [[ "${_PSC_CAND_DISP[_psc_i]}" == "alpha/" && "${_PSC_CAND_TIP[_psc_i]}" == "t-alpha" ]] || _psc_sorted_ok=0 ;;
        beta)  [[ "${_PSC_CAND_DISP[_psc_i]}" == "beta/" ]] || _psc_sorted_ok=0 ;;
        gamma) [[ "${_PSC_CAND_DISP[_psc_i]}" == "gamma.txt" ]] || _psc_sorted_ok=0 ;;
        *) _psc_sorted_ok=0 ;;
    esac
done
[[ ${#_PSC_CAND_COMP} -eq 3 && $_psc_sorted_ok -eq 1 ]] \
    && { print "ok   sort keeps candidates and their tips"; PASS=$((PASS+1)) } \
    || { print "FAIL sort keeps candidates and their tips [${(j:,:)_PSC_CAND_COMP} / ${(j:,:)_PSC_CAND_TIP}]"; FAIL=$((FAIL+1)) }
_PSC_CFG=(); _PSC_CFG[enable_sort_by_history]=0
_PSC_CAND_COMP=(zzz aaa); _PSC_CAND_DISP=(zzz aaa); _PSC_CAND_TIP=('' '')
_psc_sort_candidates git git
[[ "${(j:,:)_PSC_CAND_COMP}" == "zzz,aaa" ]] \
    && { print "ok   sort_by_history off is a no-op"; PASS=$((PASS+1)) } \
    || { print "FAIL sort_by_history off is a no-op [${(j:,:)_PSC_CAND_COMP}]"; FAIL=$((FAIL+1)) }
unset HISTFILE

print -- "--- bridge-side config ---"
# Which config keys the bridge itself acts on (everything else is the menu engine's: the bridge only forwards it).
# Each row here is asserted, so "supported" stays honest.
_CFG="$PSCOMPLETIONS_DATA_DIR/settings.json"
_SAVE_CFG="$(cat "$_CFG")"
mkdir -p "$PSCOMPLETIONS_DATA_DIR/temp/menu" /tmp/psc-cfg-probe/adir
touch /tmp/psc-cfg-probe/afile.txt

# enable_path_trailing_separator: a directory gets "/" and no space (on), plain text (off)
_PSC_CFG=(); _psc_pick_text /tmp/psc-cfg-probe/adir
[[ "$_PSC_PICK_TEXT" == "/tmp/psc-cfg-probe/adir/" && "$_PSC_PICK_NOSPACE" == 1 ]] \
    && { print "ok   pick dir + separator on"; PASS=$((PASS+1)) } || { print "FAIL pick dir + separator on [$_PSC_PICK_TEXT/$_PSC_PICK_NOSPACE]"; FAIL=$((FAIL+1)) }
_PSC_CFG=(); _PSC_CFG[enable_path_trailing_separator]=0; _psc_pick_text /tmp/psc-cfg-probe/adir
[[ "$_PSC_PICK_TEXT" == "/tmp/psc-cfg-probe/adir" && "$_PSC_PICK_NOSPACE" == 1 ]] \
    && { print "ok   pick dir + separator off"; PASS=$((PASS+1)) } || { print "FAIL pick dir + separator off [$_PSC_PICK_TEXT/$_PSC_PICK_NOSPACE]"; FAIL=$((FAIL+1)) }
_PSC_CFG=(); _psc_pick_text /tmp/psc-cfg-probe/afile.txt
[[ "$_PSC_PICK_TEXT" == "/tmp/psc-cfg-probe/afile.txt" && "$_PSC_PICK_NOSPACE" == 0 ]] \
    && { print "ok   pick file unchanged"; PASS=$((PASS+1)) } || { print "FAIL pick file unchanged [$_PSC_PICK_TEXT/$_PSC_PICK_NOSPACE]"; FAIL=$((FAIL+1)) }
mkdir -p '/tmp/psc-cfg-probe/a b'
_PSC_CFG=(); _psc_pick_text '/tmp/psc-cfg-probe/a\ b'
[[ "$_PSC_PICK_TEXT" == '/tmp/psc-cfg-probe/a\ b/' && "$_PSC_PICK_NOSPACE" == 1 ]] \
    && { print "ok   pick escaped dir gets separator"; PASS=$((PASS+1)) } || { print "FAIL pick escaped dir gets separator [$_PSC_PICK_TEXT/$_PSC_PICK_NOSPACE]"; FAIL=$((FAIL+1)) }

# enable_native_completion=0 turns the native branches off (no capture, no enumerate).
# The routing cases above stub _psc_native; take the real one back from the bridge file.
eval "$(awk '/^_psc_pick_text\(\) \{/,/^\}/' "$BRIDGE")"
eval "$(awk '/^_psc_native\(\) \{/,/^\}/' "$BRIDGE")"
_PSC_CFG=(); _PSC_CFG[enable_native_completion]=0
_psc_native "foo " foo >/dev/null 2>&1; rc=$?
[[ $rc -eq 1 ]] && { print "ok   native off returns 1"; PASS=$((PASS+1)) } || { print "FAIL native off returns 1 rc=$rc"; FAIL=$((FAIL+1)) }

# Every engine-side key must still be forwarded, and enable_sort_by_history must drive the presence of the order block.
_manifest="$PSCOMPLETIONS_DATA_DIR/completions/git/language/en-US.json"
_in="$PSCOMPLETIONS_DATA_DIR/temp/menu/cfginput.json"
_check_input() {
    local name="$1" want="$2"
    _PSC_CFG=(); _PSC_LANGCACHE=(); _PSC_HOOKS=()
    _psc_write_input "$_in" git 1 "$_manifest" 0 0 0 120 30 2>/dev/null
    local got
    got="$(python3 - "$_in" <<'PYEOF'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
c=d.get('config') or {}; f=c.get('flags') or {}
raw=(c.get('raw_config') or {}).get('global') or {}
print(' '.join([
 'filter_mode=%s'%f.get('filter_mode'), 'show_mode=%s'%f.get('show_mode'),
 'list_loop=%s'%f.get('enable_list_loop'), 'single=%s'%f.get('enable_apply_when_single'),
 'no_match=%s'%f.get('enable_apply_when_no_match'), 'focus=%s'%f.get('color_focus'),
 'match=%s'%f.get('color_match'), 'switch=%s'%c.get('context_switch'),
 'stay=%s'%c.get('context_stay'), 'raw_tip=%s'%raw.get('enable_tip'),
 'raw_cache=%s'%raw.get('enable_cache'), 'order=%s'%('yes' if 'order' in d else 'no'),
 'build_order=%s'%('yes' if 'order' in (d.get('build') or {}) else 'no'),
]))
PYEOF
)"
    [[ "$got" == "$want" ]] && { print "ok   $name"; PASS=$((PASS+1)) } || {
        print "FAIL $name"; print "      want=[$want]"; print "      got =[$got]"; FAIL=$((FAIL+1)) }
}
cat > "$_CFG" <<'EOF'
{"alias":{"git":["git"]},"config":{"language":"en-US","filter_mode":"subsequence","show_mode":"altscreen-bottom","enable_list_loop":0,"enable_apply_when_single":1,"enable_apply_when_no_match":1,"color_focus":"blue","color_match":"yellow","enable_tip":0,"enable_cache":0,"switch":"#","stay":"!","enable_sort_by_history":0}}
EOF
_check_input "menu config forwarded" "filter_mode=subsequence show_mode=altscreen-bottom list_loop=False single=True no_match=True focus=blue match=yellow switch=# stay=! raw_tip=0 raw_cache=0 order=no build_order=no"
cat > "$_CFG" <<'EOF'
{"alias":{"git":["git"]},"config":{"language":"en-US","enable_sort_by_history":1}}
EOF
# _psc_write_input only adds the order block when a history file is known; a non-interactive shell has no HISTFILE.
export HISTFILE=/tmp/psc-cfg-probe/hist
: > "$HISTFILE"
_check_input "sort_by_history adds order" "filter_mode=wildcard show_mode=auto list_loop=True single=False no_match=False focus=red match=cyan switch=~ stay=? raw_tip=None raw_cache=None order=yes build_order=yes"
unset HISTFILE
print -r -- "$_SAVE_CFG" > "$_CFG"
_PSC_CFG=(); _PSC_LANGCACHE=(); _PSC_HOOKS=()

print -- "--- management status color ---"
# The CLI prints plain text; the bridge colors it (green on success, red on failure) — the same convention as the PS bridge's _forward_psc.
_STUB="$PSCOMPLETIONS_DATA_DIR/temp/status-stub.sh"
print -r -- '#!/bin/sh' > "$_STUB"
print -r -- 'echo "status-ok"; exit 0' >> "$_STUB"
chmod +x "$_STUB"
_SAVE_BIN=$_PSC_BIN; _PSC_BIN=$_STUB
out="$(_psc_run_status x)"; rc=$?
[[ $rc -eq 0 && "$out" == $'\033[32mstatus-ok\033[0m' ]] \
    && { print "ok   status green on success"; PASS=$((PASS+1)) } || { print "FAIL status green on success rc=$rc [${(qq)out}]"; FAIL=$((FAIL+1)) }
print -r -- 'echo "status-bad"; exit 1' > "$_STUB"
out="$(_psc_run_status x)"; rc=$?
[[ $rc -eq 1 && "$out" == $'\033[31mstatus-bad\033[0m' ]] \
    && { print "ok   status red on failure"; PASS=$((PASS+1)) } || { print "FAIL status red on failure rc=$rc [${(qq)out}]"; FAIL=$((FAIL+1)) }
_PSC_BIN=$_SAVE_BIN

print -- "--- reads stay plain ---"
# A single-value read (completion <name> <key>) is a query like list/info: the value must stay plain text so it can be captured (v=$(...)); only a set (--reset or a fourth arg) takes the status path — the PowerShell bridge routes the same way.
print -r -- '#!/bin/sh' > "$_STUB"
print -r -- 'echo "30"; exit 0' >> "$_STUB"
chmod +x "$_STUB"
_SAVE_BIN=$_PSC_BIN; _PSC_BIN=$_STUB
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
out="$(psc completion git max_commit 2>&1)"
[[ "$out" == "30" ]] \
    && { print "ok   completion-value-read-stays-plain"; PASS=$((PASS+1)) } || { print "FAIL completion-value-read-stays-plain [${(qq)out}]"; FAIL=$((FAIL+1)) }
out="$(psc completion git max_commit 31 2>&1)"
[[ "$out" == *$'\033[32m'* ]] \
    && { print "ok   completion-value-set-stays-green"; PASS=$((PASS+1)) } || { print "FAIL completion-value-set-stays-green [${(qq)out}]"; FAIL=$((FAIL+1)) }
_PSC_BIN=$_SAVE_BIN

print -- "--- separator split: a new command starts after the last unquoted separator ---"
_seg_check() {
    local name="$1" want="$2" got
    got="$(_psc_segment "$3")"
    [[ "$got" == "$want" ]] && { print "ok   $name"; PASS=$((PASS+1)) } || { print "FAIL $name [${got:-<empty>}]"; FAIL=$((FAIL+1)) }
}
_seg_check "split: pipe"                   "grep "       "git status | grep "
_seg_check "split: pipe with no space"     "grep "       "git status|grep "
_seg_check "split: double-quoted pipe"     "head "       'git log --grep "a|b" | head '
_seg_check "split: single-quoted pipe"     "head "       "git log --grep 'a|b' | head "
_seg_check "split: semicolon"              "git commit " "ls; git commit "
_seg_check "split: and-and"                "git commit " "ls && git commit "
_seg_check "split: or-or"                  "git commit " "ls || git commit "
_seg_check "split: redirection is not one" "grep "       "git show 2>&1 | grep "
_seg_check "split: ampersand"              "git commit " "ls & git commit "
_seg_check "split: ampersand at end"       ""            "git status &"
_seg_check "split: &> is a redirection"    "grep "       "git show &>/dev/null | grep "
_seg_check "split: no separator"           "git status " "git status "
_seg_check "split: the nearest one wins"   "c "          "a | b | c "
_seg_check "split: mixed separators"       "d "          "a | b && c ; d "
_seg_check "split: trailing separator"     ""            "git status | "
_seg_check "split: quoted semicolon"       "git "        'echo "a;b" ; git '

print -- "--- separator: an empty segment returns before the menu (no crash) ---"
if _psc_init >/dev/null 2>&1; then
    LBUFFER='git status | '
    if _psc_complete >/dev/null 2>&1; then
        print "FAIL route: an empty segment returned success"; FAIL=$((FAIL+1))
    else
        print "ok   route: an empty segment returns 1, so the host completes a command name"; PASS=$((PASS+1))
    fi
    LBUFFER=''
else
    print "FAIL route: _psc_init did not succeed in the harness"; FAIL=$((FAIL+1))
fi

print -- "--- history normalisation (extended_history prefixes the entry inline) ---"
_HIST=/tmp/psc-bridge-hist.zsh
printf ': 1700000000:0;git status\n: 1700000001:5;git commit --amend\n' > "$_HIST"
export HISTFILE="$_HIST"
_NORM="$(_psc_hist)"
if [[ -n "$_NORM" && "$(cat -- "$_NORM")" == $'git status\ngit commit --amend' ]]; then
    print "ok   history-normalised"; PASS=$((PASS+1))
else
    print "FAIL history-normalised [$(tr '\n' '|' < "$_NORM" 2>/dev/null)]"; FAIL=$((FAIL+1))
fi
unset HISTFILE

print -- "--- install shape: running the library must be refused, not silently ignored ---"
_RUN_OUT="$(zsh -f "$BRIDGE" 2>&1)"; _RUN_RC=$?
if (( _RUN_RC != 0 )) && [[ "$_RUN_OUT" == *"library"* ]] && [[ "$_RUN_OUT" == *"source "* ]]; then
    print "ok   refuses-to-run"; PASS=$((PASS+1))
else
    print "FAIL refuses-to-run rc=$_RUN_RC [$_RUN_OUT]"; FAIL=$((FAIL+1))
fi

print -- "--- install shape: sourcing a symlink must still resolve the module ---"
# A plugin dir often holds a link to the bridge; the binaries and the bundled psc completion sit next to the real file, so the bridge dir must follow the link (`${0:A}`).
_LINKDIR=/tmp/psc-link-test
mkdir -p "$_LINKDIR"
ln -sfn "$BRIDGE" "$_LINKDIR/PSCompletions.zsh"
_got="$(zsh -f -c "source $_LINKDIR/PSCompletions.zsh; print -n \"\$_psc_bridge_dir\"" 2>/dev/null)"
if [[ "$_got" == "${BRIDGE:h}" ]]; then
    print "ok   symlink-sourcing-resolves-module"; PASS=$((PASS+1))
else
    print "FAIL symlink-sourcing-resolves-module [$_got]"; FAIL=$((FAIL+1))
fi

print -- "--- install shape: an installed copy has no ../version.json, so the version comes from the psd1 ---"
# An installed copy *is* the package root: the bridge sits beside bin/ and PSCompletions.psd1, and there is no `../version.json` (that file is repo-only).
_PKGDIR=/tmp/psc-pkg-test
rm -rf "$_PKGDIR"; mkdir -p "$_PKGDIR"
cp "$BRIDGE" "$_PKGDIR/"
cp "${BRIDGE:h}/PSCompletions.psd1" "$_PKGDIR/"
_pkg_expected="$(sed -n "s/.*ModuleVersion *= *'\([^']*\)'.*/\1/p" "$_PKGDIR/PSCompletions.psd1" | head -1)"
_pkg_got="$(zsh -f -c "source $_PKGDIR/PSCompletions.zsh; print -n \"\$(_psc_module_version)\"" 2>/dev/null)"
if [[ -n "$_pkg_got" && "$_pkg_got" == "$_pkg_expected" ]]; then
    print "ok   packaged-layout-version"; PASS=$((PASS+1))
else
    print "FAIL packaged-layout-version [$_pkg_got] expected [$_pkg_expected]"; FAIL=$((FAIL+1))
fi

print -- "--- pass=$PASS fail=$FAIL ---"
(( FAIL == 0 ))
