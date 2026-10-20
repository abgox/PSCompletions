#!/usr/bin/env bash
# Headless bridge tests: build input via the bridge's own _psc_write_input, run psc-menu headless (build rewrites the input file), assert candidates.
# Usage: bash test.bash [repo-root]  (test-all.sh clears BASH_ENV; do the same when running by hand)
set -u
# The user's environment must not reach the tests.
# `BASH_ENV` is read by every non-interactive bash (`--norc` does not stop it), and a bridge the user's rc already sourced blocks the `source` below — the bridges guard on `_PSC_LOADED` — leaving the suite testing the wrong file.
unset BASH_ENV
if [[ -n "${_PSC_LOADED:-}" ]]; then
    echo "test.bash: a PSCompletions bridge is already loaded in this shell; run the suite in a clean one" >&2
    exit 1
fi
ROOT="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
BRIDGE="$ROOT/module/PSCompletions/PSCompletions.bash"
export PSCOMPLETIONS_DATA_DIR=/tmp/psc-bridge-test
# shellcheck disable=SC1090
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
# scratch git repo for live hook output
rm -rf /tmp/psc-bridge-scratch && mkdir -p /tmp/psc-bridge-scratch && cd /tmp/psc-bridge-scratch || exit 1
git init -q . 2>/dev/null; git config user.email t@t.t 2>/dev/null; git config user.name t 2>/dev/null
echo x > f.txt; git add f.txt 2>/dev/null; git commit -qm init 2>/dev/null; git branch feat-x 2>/dev/null

PASS=0; FAIL=0
run_case() { # name cmd last hooks min_count want... (remaining args after -- are argv)
    local name="$1" cmd="$2" last="$3" hooks="$4" min="$5"; shift 5
    local -a want=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do want+=("$1"); shift; done
    [[ "$1" == "--" ]] && shift
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
    print("0|ENGINE-NO-REWRITE")
    raise SystemExit
items=[i.get('completion_text','') for i in d.get('items',[])]
want=sys.argv[3:]
missing=[w for w in want if w not in items]
print(f"{len(items)}|{','.join(missing)}")
PYEOF
)"
    local n="${res%%|*}" missing="${res#*|}"
    if (( n >= min )) && [[ -z "$missing" ]]; then
        echo "ok   $name ($n items)"
        PASS=$((PASS+1))
    else
        echo "FAIL $name (n=$n min=$min missing=[$missing])"
        FAIL=$((FAIL+1))
    fi
    rm -f "$in" "$out"
}

cd /tmp/psc-bridge-scratch || exit 1
run_case git-root      git 0 0 50  add branch status -- --
run_case git-pending   git 0 0 2   stash status -- st
run_case git-add       git 1 0 3   --all -- add
run_case psc-root      psc 0 0 5   add rm update config -- --
run_case psc-add       psc 1 1 2   demo-a demo-b -- add
run_case git-checkout  git 1 1 2   feat-x -- checkout
run_case scoop-root    scoop 0 1 5 install bucket -- --
run_case git-eq        git 0 0 1   --ref-format=files -- init --ref-format=f
run_case git-quoted    git 0 0 0   -- commit -m "hello world" x
echo "--- gate checks ---"
gate() { # cmd expected
    local got
    got="$(_psc_hooks_enabled "$1")"
    if [[ "$got" == "$2" ]]; then echo "ok   gate-$1=$got"; PASS=$((PASS+1));
    else echo "FAIL gate-$1=$got want $2"; FAIL=$((FAIL+1)); fi
}
gate git 1
gate psc 1
gate nosuch 0
# disabled hooks stay off even with hooks.lua present
python3 - "$PSCOMPLETIONS_DATA_DIR/settings.json" <<'PYEOF'
import json,sys
p=sys.argv[1]
s=json.load(open(p,encoding='utf-8'))
s['config']['completion']={'git':{'enable_hooks':0}}
json.dump(s,open(p,'w',encoding='utf-8'))
PYEOF
gate git 0

echo "--- apply checks ---"
apply_case() { # name line point text nospace want
    READLINE_LINE="$2"; READLINE_POINT="$3"
    _psc_apply "$4" "$5"
    if [[ "$READLINE_LINE" == "$6" ]]; then echo "ok   apply-$1"; PASS=$((PASS+1));
    else echo "FAIL apply-$1 got [$READLINE_LINE] want [$6]"; FAIL=$((FAIL+1)); fi
}
unset 'enable_append_space'
apply_case end-of-line  'git chec'        8  'checkout' 0 'git checkout '
apply_case mid-word     'git checkout'    7  'checkout' 0 'git checkout '
apply_case after-space  'git '            4  'status'   0 'git status '
apply_case next-word    'git  status'     4  'status'   0 'git status status'
apply_case attached-head 'git log --format=' 17 '--format=' 0 'git log --format='
apply_case attached-filled 'git log --format=' 17 '--format=pretty' 0 'git log --format=pretty '
apply_case engine-nospace 'git log --format=' 14 '--format=x' 1 'git log --format=x'
_PSC_CFG[enable_append_space]=0
apply_case no-append-space 'git '         4  'status'   0 'git status'
unset '_PSC_CFG[enable_append_space]'

echo "--- apply: word boundary respects escapes and quotes ---"
# A path with a space arrives escaped (`/tmp/psc\ t/`) or quoted (`'/tmp/psc t/'`).
# The naive `${before##* }` split cut at the escaped space, so the pick was concatenated after the old text instead of replacing it — the defect the interactive pass reported.
word_case() { # name line text nospace want
    READLINE_LINE="$2"; READLINE_POINT=${#2}
    _psc_apply "$3" "$4"
    if [[ "$READLINE_LINE" == "$5" ]]; then echo "ok   word-$1"; PASS=$((PASS+1));
    else echo "FAIL word-$1 got [$READLINE_LINE] want [$5]"; FAIL=$((FAIL+1)); fi
}
word_case escaped-dir  'cd /tmp/psc\ t/'      '/tmp/psc t/az zdir/'  1 'cd /tmp/psc t/az zdir/'
word_case quoted-dir   "cd '/tmp/psc t/'"     '/tmp/psc t/az zdir/'  1 "cd /tmp/psc t/az zdir/"
word_case escaped-file 'cat /tmp/psc\ t/plain' '/tmp/psc t/plain.txt' 0 'cat /tmp/psc t/plain.txt '
word_case plain-word   'git chec'              'checkout'             0 'git checkout '

echo "--- dispatch routing ---"
_psc_build_menu() { echo BUILD; }
_psc_native() { echo NATIVE; }
route_case() { # name line expect
    READLINE_LINE="$2"; READLINE_POINT=${#2}
    local got; got="$(_psc_complete)"
    if [[ "$got" == "$3" ]]; then echo "ok   route-$1"; PASS=$((PASS+1));
    else echo "FAIL route-$1 got [$got] want [$3]"; FAIL=$((FAIL+1)); fi
}
route_case path-dot    'git add ./'   NATIVE
route_case path-up     'git add ../x' NATIVE
route_case path-home   'git add ~/'   NATIVE
route_case path-abs    'git add /etc' NATIVE
route_case path-win    'git add .\s'  NATIVE
route_case word        'git add src'  BUILD
route_case space       'git add '     BUILD
route_case typing      'git che'      BUILD
route_case cmd-word    'git'          NATIVE
route_case unknown     'foo bar'      NATIVE
route_case cmd-path    'cd ~/'        NATIVE

echo "--- config wiring ---"
CFG_DIR=/tmp/psc-bridge-cfg
rm -rf "$CFG_DIR"; mkdir -p "$CFG_DIR/completions" "$CFG_DIR/temp/menu"
ln -s "$ROOT/completions/psc" "$CFG_DIR/completions/psc"
cat > "$CFG_DIR/settings.json" <<'EOF'
{"alias":{"psc":["psc"]},"config":{"language":"en-US","filter_mode":"subsequence","show_mode":"altscreen-top","color_focus":"blue","enable_list_loop":0,"enable_apply_when_single":1,"enable_sort_by_history":0,"switch":"»","stay":"¿"}}
EOF
echo '{"update":{},"meta":{}}' > "$CFG_DIR/temp/completions.json"
_CFG_SAVE="$PSCOMPLETIONS_DATA_DIR"
PSCOMPLETIONS_DATA_DIR="$CFG_DIR"
_PSC_INIT_OK=0; _PSC_ALIAS=(); _PSC_CFG=(); _PSC_LANGCACHE=()
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
if [[ "$cfg_check" == ok ]]; then echo "ok   config-flags"; PASS=$((PASS+1)); else echo "FAIL config-flags $cfg_check"; FAIL=$((FAIL+1)); fi

# trigger key read from settings
tk="$(printf 'x' | _psc_read_trigger_key)"
if [[ "$tk" == Tab ]]; then echo "ok   trigger-key-default"; PASS=$((PASS+1)); else echo "FAIL trigger-key-default got $tk"; FAIL=$((FAIL+1)); fi
python3 - "$CFG_DIR/settings.json" <<'PYEOF'
import json,sys
p=sys.argv[1]; s=json.load(open(p,encoding='utf-8')); s['config']['trigger_key']='Ctrl+Space'
json.dump(s,open(p,'w',encoding='utf-8'))
PYEOF
tk="$(printf 'x' | _psc_read_trigger_key)"
if [[ "$tk" == "Ctrl+Space" ]]; then echo "ok   trigger-key-read"; PASS=$((PASS+1)); else echo "FAIL trigger-key-read got $tk"; FAIL=$((FAIL+1)); fi

PSCOMPLETIONS_DATA_DIR="$_CFG_SAVE"
rm -rf "$CFG_DIR"

echo "--- reset ---"
RST_DIR=/tmp/psc-bridge-rst
rm -rf "$RST_DIR"; mkdir -p "$RST_DIR/completions"
ln -s "$ROOT/completions/psc" "$RST_DIR/completions/psc"
_CFG_SAVE2="$PSCOMPLETIONS_DATA_DIR"; PSCOMPLETIONS_DATA_DIR="$RST_DIR"
_PSC_INIT_OK=0; _PSC_ALIAS=(); _PSC_CFG=(); _PSC_LANGCACHE=()
_psc_init
mkdir -p "$RST_DIR/completions/junk"; echo '{}' > "$RST_DIR/completions/junk/config.json"
printf '\n' | psc --reset >/dev/null 2>&1
if [[ -d "$RST_DIR/completions/psc" && ! -d "$RST_DIR/completions/junk" && -f "$RST_DIR/settings.json" ]]; then
    echo "ok   reset"; PASS=$((PASS+1))
else
    echo "FAIL reset (psc seeded / junk gone / settings rebuilt)"; FAIL=$((FAIL+1))
fi
PSCOMPLETIONS_DATA_DIR="$_CFG_SAVE2"; rm -rf "$RST_DIR"

echo "--- fresh data dir (offline first run) ---"
FRESH=/tmp/psc-bridge-fresh
rm -rf "$FRESH"
_SAVE3="$PSCOMPLETIONS_DATA_DIR"; PSCOMPLETIONS_DATA_DIR="$FRESH"
_PSC_INIT_OK=0; _PSC_ALIAS=(); _PSC_CFG=(); _PSC_LANGCACHE=()
HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 _psc_init
if [[ -f "$FRESH/completions/psc/config.json" && "${_PSC_ALIAS[psc]:-}" == psc ]]; then
    echo "ok   fresh-offline"; PASS=$((PASS+1))
else
    echo "FAIL fresh-offline (bundled psc seeded + alias built)"; FAIL=$((FAIL+1))
fi
PSCOMPLETIONS_DATA_DIR="$_SAVE3"; rm -rf "$FRESH"

echo "--- management text path + dependency guard ---"
[[ "$_PSC_PY" == /* ]] && { echo "ok   py-absolute"; PASS=$((PASS+1)); } || { echo "FAIL py-absolute [$_PSC_PY]"; FAIL=$((FAIL+1)); }
out="$(psc 2>&1)"
[[ "$out" == *"PSCompletions"* ]] && { echo "ok   psc-bare-description"; PASS=$((PASS+1)); } || { echo "FAIL psc-bare-description"; FAIL=$((FAIL+1)); }
# Flags only, no command word: with `--json` that is the **root** response (design/json.md §5) — the run's own facts — never the info page, and never the binary's own usage text.
out="$(psc --json 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == "{"* ]] \
    && { echo "ok   root-json-for-json-flag"; PASS=$((PASS+1)); } || { echo "FAIL root-json-for-json-flag rc=$rc [$out]"; FAIL=$((FAIL+1)); }
_SAVE_PY="$_PSC_PY"
_PSC_PY=""; _PSC_PY_WARNED=0
out="$(_psc_tpl description 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == *PSCompletions* ]] && { echo "ok   render-without-python"; PASS=$((PASS+1)); } || { echo "FAIL render-without-python rc=$rc [$out]"; FAIL=$((FAIL+1)); }
_PSC_PY_WARNED=0
out="$(psc 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" != *"Usage: psc"* ]] && { echo "ok   missing-py-psc"; PASS=$((PASS+1)); } || { echo "FAIL missing-py-psc rc=$rc [$out]"; FAIL=$((FAIL+1)); }
_PSC_PY="$_SAVE_PY"

echo "--- data dir default (per platform) ---"
_SAVE_PLATFORM=$_psc_platform
_psc_platform=darwin
[[ "$(_psc_default_data_dir)" == "$HOME/Library/Application Support/com.abgox/PSCompletions" ]] \
    && { echo "ok   datadir-macos"; PASS=$((PASS+1)); } || { echo "FAIL datadir-macos"; FAIL=$((FAIL+1)); }
_psc_platform=windows; APPDATA=/tmp/appdata
[[ "$(_psc_default_data_dir)" == "/tmp/appdata/com.abgox/PSCompletions" ]] \
    && { echo "ok   datadir-windows"; PASS=$((PASS+1)); } || { echo "FAIL datadir-windows"; FAIL=$((FAIL+1)); }
unset APPDATA
_psc_platform=linux; XDG_DATA_HOME=/tmp/xdg
[[ "$(_psc_default_data_dir)" == "/tmp/xdg/com.abgox/PSCompletions" ]] \
    && { echo "ok   datadir-linux-xdg"; PASS=$((PASS+1)); } || { echo "FAIL datadir-linux-xdg"; FAIL=$((FAIL+1)); }
unset XDG_DATA_HOME
[[ "$(_psc_default_data_dir)" == "$HOME/.local/share/com.abgox/PSCompletions" ]] \
    && { echo "ok   datadir-linux-home"; PASS=$((PASS+1)); } || { echo "FAIL datadir-linux-home"; FAIL=$((FAIL+1)); }
_psc_platform=$_SAVE_PLATFORM

echo "--- language resolution is independent of _psc_init ---"
# `psc` can run before the first Tab; _PSC_CFG is empty then, so the module language must come from settings.json — the cache holds nothing to fall back on.
_SAVE_SETTINGS="$(cat "$PSCOMPLETIONS_DATA_DIR/settings.json")"
printf '%s\n' '{"alias":{"git":["git"],"psc":["psc"],"scoop":["scoop"]},"config":{"language":"zh-CN"}}' > "$PSCOMPLETIONS_DATA_DIR/settings.json"
_PSC_CFG=(); _PSC_LANGCACHE=()
lang="$(_psc_lang psc)"
[[ "$lang" == zh-CN ]] && { echo "ok   lang-without-init"; PASS=$((PASS+1)); } || { echo "FAIL lang-without-init lang=$lang"; FAIL=$((FAIL+1)); }
printf '%s\n' "$_SAVE_SETTINGS" > "$PSCOMPLETIONS_DATA_DIR/settings.json"
_PSC_CFG=(); _PSC_LANGCACHE=()

echo "--- management output is a terminated line ---"
# The renderer returns a fragment (no trailing newline); the caller terminates each line it prints.
# zsh marks a missed one with PROMPT_EOL_MARK ('%'), bash hides it.
_ends_nl() { [[ -s "$1" && -z "$(tail -c 1 "$1")" ]]; }
_TL="$PSCOMPLETIONS_DATA_DIR/temp/tpl-line.txt"
_STUB_BIN="$PSCOMPLETIONS_DATA_DIR/temp/stub-bin.sh"
printf '#!/bin/sh\ncase "$*" in *" tpl "*) exec "%s" "$@" ;; esac\ncase "$*" in *" update") printf "Updatable completions:\\n  git\\n"; exit 0 ;; esac\necho "{\\"ok\\":true,\\"data\\":{\\"completions\\":[{\\"name\\":\\"git\\",\\"ok\\":true}]}}"\n' "$_PSC_BIN" > "$_STUB_BIN"
chmod +x "$_STUB_BIN"
_SAVE_BIN=$_PSC_BIN; _PSC_BIN=$_STUB_BIN
_psc_run_rendered rm git > "$_TL" 2>/dev/null; rc=$?
[[ $rc -eq 0 && "$(wc -l < "$_TL")" -eq 1 && -n "$(cat "$_TL")" ]] \
    && { echo "ok   rendered-line-terminated"; PASS=$((PASS+1)); } || { echo "FAIL rendered-line-terminated rc=$rc lines=$(wc -l < "$_TL")"; FAIL=$((FAIL+1)); }
printf '{"update":["git"]}\n' > "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
_psc_render_pending > "$_TL" 2>/dev/null
_ends_nl "$_TL" && { echo "ok   notification-line-terminated"; PASS=$((PASS+1)); } || { echo "FAIL notification-line-terminated"; FAIL=$((FAIL+1)); }
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
# The module notice fires only for a version newer than the installed one: an equal value is "nothing to do", not an update.
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/.bash-module-notified"
_INSTALLED="$(_psc_module_version)"
printf '{"module":"%s"}\n' "$_INSTALLED" > "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
_psc_render_pending > "$_TL" 2>/dev/null
[[ "$(cat "$_TL")" != *"has updated the version"* ]] \
    && { echo "ok   module-equal-version-is-silent"; PASS=$((PASS+1)); } || { echo "FAIL module-equal-version-is-silent [$(cat "$_TL")]"; FAIL=$((FAIL+1)); }
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/.bash-module-notified"
printf '{"module":"%s.99"}\n' "${_INSTALLED%.*}" > "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
_psc_render_pending > "$_TL" 2>/dev/null
[[ "$(cat "$_TL")" == *"has updated the version"* ]] \
    && { echo "ok   module-newer-version-notifies"; PASS=$((PASS+1)); } || { echo "FAIL module-newer-version-notifies [$(_TL)]"; FAIL=$((FAIL+1)); }
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/change.json" "$PSCOMPLETIONS_DATA_DIR/temp/.bash-module-notified"
# A no-arg update drops the CLI's plain list on success — the tail renders the same lists as a template, so each appears once; the one-shot added/removed are still consumed.
printf '{"update":["git"],"added":["new-one"],"removed":[],"renamed":[]}\n' > "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
out="$(psc update 2>&1)"
[[ "$out" == *"has updated the completion library"* && "$out" != *"Updatable completions"* ]] \
    && { echo "ok   no-arg-update-renders-template-once"; PASS=$((PASS+1)); } || { echo "FAIL no-arg-update-renders-template-once [$out]"; FAIL=$((FAIL+1)); }
python3 -c "import json;assert json.load(open('$PSCOMPLETIONS_DATA_DIR/temp/change.json'))['added']==[],'one-shots left unconsumed'" \
    && { echo "ok   no-arg-update-consumes-one-shots"; PASS=$((PASS+1)); } || { echo "FAIL no-arg-update-consumes-one-shots"; FAIL=$((FAIL+1)); }
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
# A failed check still prints — dropping the plain text must never swallow an error.
printf '#!/bin/sh\necho "error: boom"; exit 1\n' > "$PSCOMPLETIONS_DATA_DIR/temp/fail-bin.sh"
chmod +x "$PSCOMPLETIONS_DATA_DIR/temp/fail-bin.sh"
_SAVE_BIN2=$_PSC_BIN; _PSC_BIN="$PSCOMPLETIONS_DATA_DIR/temp/fail-bin.sh"
out="$(_psc_check_update update 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"error: boom"* ]] \
    && { echo "ok   failed-check-still-prints"; PASS=$((PASS+1)); } || { echo "FAIL failed-check-still-prints rc=$rc [$out]"; FAIL=$((FAIL+1)); }
_PSC_BIN=$_SAVE_BIN2
# `--json` anywhere is the machine contract: never colored, never rendered into a page.
out="$(psc list --json 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == *'"ok":true'* && "$out" != *$'\033'* ]] \
    && { echo "ok   json-is-never-colored"; PASS=$((PASS+1)); } || { echo "FAIL json-is-never-colored rc=$rc [$out]"; FAIL=$((FAIL+1)); }
out="$(psc config core language --json 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" != *$'\033'* ]] \
    && { echo "ok   json-after-args"; PASS=$((PASS+1)); } || { echo "FAIL json-after-args rc=$rc [$out]"; FAIL=$((FAIL+1)); }
_PSC_BIN=$_SAVE_BIN

echo "--- bridge-side config ---"
# Which config keys the bridge itself acts on (everything else is the menu engine's: the bridge only forwards it).
# Each row here is asserted, so "supported" stays honest.
_CFG="$PSCOMPLETIONS_DATA_DIR/settings.json"
_SAVE_CFG="$(cat "$_CFG")"
mkdir -p "$PSCOMPLETIONS_DATA_DIR/temp/menu" /tmp/psc-cfg-probe/adir
: > /tmp/psc-cfg-probe/afile.txt

# enable_path_trailing_separator: a directory gets "/" and no space (on), plain text (off)
_PSC_CFG=(); _psc_pick_text /tmp/psc-cfg-probe/adir
[[ "$_PSC_PICK_TEXT" == "/tmp/psc-cfg-probe/adir/" && "$_PSC_PICK_NOSPACE" == 1 ]] \
    && { echo "ok   pick dir + separator on"; PASS=$((PASS+1)); } || { echo "FAIL pick dir + separator on [$_PSC_PICK_TEXT/$_PSC_PICK_NOSPACE]"; FAIL=$((FAIL+1)); }
_PSC_CFG=(); _PSC_CFG[enable_path_trailing_separator]=0; _psc_pick_text /tmp/psc-cfg-probe/adir
[[ "$_PSC_PICK_TEXT" == "/tmp/psc-cfg-probe/adir" && "$_PSC_PICK_NOSPACE" == 1 ]] \
    && { echo "ok   pick dir + separator off"; PASS=$((PASS+1)); } || { echo "FAIL pick dir + separator off [$_PSC_PICK_TEXT/$_PSC_PICK_NOSPACE]"; FAIL=$((FAIL+1)); }
_PSC_CFG=(); _psc_pick_text /tmp/psc-cfg-probe/afile.txt
[[ "$_PSC_PICK_TEXT" == "/tmp/psc-cfg-probe/afile.txt" && "$_PSC_PICK_NOSPACE" == 0 ]] \
    && { echo "ok   pick file unchanged"; PASS=$((PASS+1)); } || { echo "FAIL pick file unchanged [$_PSC_PICK_TEXT/$_PSC_PICK_NOSPACE]"; FAIL=$((FAIL+1)); }

# enable_native_completion=0 turns the native branches off.
# The routing cases above stub _psc_native; take the real one back from the bridge file.
eval "$(awk '/^_psc_pick_text\(\) \{/,/^\}/' "$BRIDGE")"
eval "$(awk '/^_psc_native\(\) \{/,/^\}/' "$BRIDGE")"
_PSC_CFG=(); _PSC_CFG[enable_native_completion]=0
_psc_native "foo " foo >/dev/null 2>&1; rc=$?
[[ $rc -eq 1 ]] && { echo "ok   native off returns 1"; PASS=$((PASS+1)); } || { echo "FAIL native off returns 1 rc=$rc"; FAIL=$((FAIL+1)); }

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
    [[ "$got" == "$want" ]] && { echo "ok   $name"; PASS=$((PASS+1)); } || {
        echo "FAIL $name"; echo "      want=[$want]"; echo "      got =[$got]"; FAIL=$((FAIL+1)); }
}
cat > "$_CFG" <<'EOF'
{"alias":{"git":["git"]},"config":{"language":"en-US","filter_mode":"subsequence","show_mode":"altscreen-bottom","enable_list_loop":0,"enable_apply_when_single":1,"enable_apply_when_no_match":1,"color_focus":"blue","color_match":"yellow","enable_tip":0,"enable_cache":0,"switch":"#","stay":"!","enable_sort_by_history":0}}
EOF
_check_input "menu config forwarded" "filter_mode=subsequence show_mode=altscreen-bottom list_loop=False single=True no_match=True focus=blue match=yellow switch=# stay=! raw_tip=0 raw_cache=0 order=no build_order=no"
cat > "$_CFG" <<'EOF'
{"alias":{"git":["git"]},"config":{"language":"en-US","enable_sort_by_history":1}}
EOF
export HISTFILE=/tmp/psc-cfg-probe/hist
: > "$HISTFILE"
_check_input "sort_by_history adds order" "filter_mode=wildcard show_mode=auto list_loop=True single=False no_match=False focus=red match=cyan switch=~ stay=? raw_tip=None raw_cache=None order=yes build_order=yes"
unset HISTFILE
printf '%s\n' "$_SAVE_CFG" > "$_CFG"
_PSC_CFG=(); _PSC_LANGCACHE=(); _PSC_HOOKS=()

echo "--- items menu: display drops the typed path prefix ---"
# The hosts' own lists show the leaf (`az zdir/`, PS `ListItemText`), never the typed directory prefix the candidate carries; only the inserted text keeps the full path.
_psc_spawn_items() { cp "$1" "$PSCOMPLETIONS_DATA_DIR/temp/menu/items-probe.json" 2>/dev/null; printf 'cancel\t'; }
_PSC_CFG=() _PSC_LANGCACHE=() _PSC_HOOKS=()
_psc_menu_items cd '' 0 '/tmp/psc t/az zdir/' python3 >/dev/null 2>&1
unset -f _psc_spawn_items
eval "$(awk '/^_psc_spawn_items\(\) \{/,/^\}/' "$BRIDGE")"
_probe="$PSCOMPLETIONS_DATA_DIR/temp/menu/items-probe.json"
_got="$(python3 - "$_probe" <<'PYEOF'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
print('|'.join('%s=>%s'%(i.get('list_item_text'),i.get('completion_text')) for i in d.get('items') or []))
PYEOF
)"
_want='az zdir/=>/tmp/psc t/az zdir/|python3=>python3'
rm -f "$_probe"
[[ "$_got" == "$_want" ]] && { echo "ok   items-leaf-display"; PASS=$((PASS+1)); } || {
    echo "FAIL items-leaf-display"; echo "      want=[$_want]"; echo "      got =[$_got]"; FAIL=$((FAIL+1)); }

echo "--- per-completion manifest language (the bridge's own share) ---"
# The engine renders the tips, so the *display* language is not the bridge's business — but which manifest is handed to the engine is.
# The rule (the same python in all three ports): per-completion override -> module-declared -> global, and a value the completion does not declare falls back to the completion's first declared language.
lang_case() { # name settings-json cmd want
    _PSC_CFG=(); _PSC_LANGCACHE=()
    printf '%s\n' "$2" > "$_CFG"
    local got; got="$(_psc_lang "$3" 2>/dev/null)"
    [[ "$got" == "$4" ]] && { echo "ok   lang-$1"; PASS=$((PASS+1)); } || {
        echo "FAIL lang-$1 got [$got] want [$4]"; FAIL=$((FAIL+1)); }
}
lang_case override-declared   '{"config":{"language":"en-US","completion":{"git":{"language":"zh-CN"}}}}' git zh-CN
lang_case override-undeclared '{"config":{"language":"en-US","completion":{"git":{"language":"fr-FR"}}}}' git en-US
lang_case global-declared     '{"config":{"language":"zh-CN"}}' git zh-CN
lang_case no-settings         '{}' git en-US
printf '%s\n' "$_SAVE_CFG" > "$_CFG"
_PSC_CFG=(); _PSC_LANGCACHE=(); _PSC_HOOKS=()

echo "--- items mode: the bridge forwards the tokens, the engine derives the filter ---"
# The rule lives in the engine now (one implementation for all four hosts).
# The bridge forwards `arg_tokens` + `treat_last_as_complete`; the engine rewrites the input with the `initial_filter` it derived, and ignores a filter that matches nothing at render time (its own unit test).
_psc_spawn_items() { cp "$1" "$PSCOMPLETIONS_DATA_DIR/temp/menu/items-probe2.json" 2>/dev/null; printf 'cancel\t'; }
_PSC_CFG=() _PSC_LANGCACHE=() _PSC_HOOKS=()
_psc_menu_items cd 'pyth' 0 'python3' 'az zdir/' >/dev/null 2>&1
unset -f _psc_spawn_items
eval "$(awk '/^_psc_spawn_items\(\) \{/,/^\}/' "$BRIDGE")"
_probe2="$PSCOMPLETIONS_DATA_DIR/temp/menu/items-probe2.json"
_got2="$(python3 - "$_probe2" <<'PYEOF'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
print('args=%s last=%s' % (','.join(d.get('arg_tokens') or []), d.get('treat_last_as_complete')))
PYEOF
)"
[[ "$_got2" == "args=pyth last=False" ]] && { echo "ok   items-forwards-tokens"; PASS=$((PASS+1)); } \
    || { echo "FAIL items-forwards-tokens got [$_got2]"; FAIL=$((FAIL+1)); }
# end to end: the real engine turns those two fields into the filter
timeout -s KILL 5 "$_PSC_MENU" "$_probe2" --result "$_probe2-out" >/dev/null 2>&1
_init2="$(python3 - "$_probe2" <<'PYEOF'
import json,sys
print(json.load(open(sys.argv[1],encoding='utf-8')).get('initial_filter') or '')
PYEOF
)"
rm -f "$_probe2" "$_probe2-out"
[[ "$_init2" == "^pyth" ]] && { echo "ok   engine-derives-initial-filter"; PASS=$((PASS+1)); } \
    || { echo "FAIL engine-derives-initial-filter got [$_init2]"; FAIL=$((FAIL+1)); }

echo "--- watchdog restores the terminal modes the menu enabled ---"
# A force-killed menu cannot turn off crossterm's modes itself.
# Leaving mouse capture on made the terminal keep reporting `ESC [ < b;x;y M` as literal input and the shell unusable (found by hand); every watchdog site must write the whole set, not just leave the alt screen.
_reset_missing=""
for _seq in '?1000l' '?1002l' '?1003l' '?1006l' '?1015l' '?1049l' '?25h' '?2004l'; do
    [[ "$_PSC_RESET_TERM" == *"$_seq"* ]] || _reset_missing+=" $_seq"
done
[[ -z "$_reset_missing" ]] && { echo "ok   reset-term-covers-modes"; PASS=$((PASS+1)); } \
    || { echo "FAIL reset-term-covers-modes missing:$_reset_missing"; FAIL=$((FAIL+1)); }
_reset_sites="$(grep -c '_PSC_RESET_TERM' "$BRIDGE")"
[[ "$_reset_sites" -ge 3 ]] && { echo "ok   reset-term-used-by-watchdogs"; PASS=$((PASS+1)); } \
    || { echo "FAIL reset-term-used-by-watchdogs sites=$_reset_sites"; FAIL=$((FAIL+1)); }
_flush_sites="$(grep -c 'tcflush' "$BRIDGE")"
[[ "$_flush_sites" -ge 1 ]] && { echo "ok   reset-term-discards-queued-input"; PASS=$((PASS+1)); } \
    || { echo "FAIL reset-term-discards-queued-input sites=$_flush_sites"; FAIL=$((FAIL+1)); }

echo "--- no-match auto-apply: the engine's input status carries the filter text ---"
# `enable_apply_when_no_match`: the menu cannot match, so the engine returns the filter text as {status:input,text} and the host must apply it like a selected candidate (the triggering key included, as the PS bridge shows).
# All three bridges parsed `selected` only and dropped it.
# Behavioural coverage needs the harness' menu stub, so assert the mapping here.
[[ "$(grep -c "s=='input'" "$BRIDGE")" -ge 1 ]] && { echo "ok   input-status-mapped"; PASS=$((PASS+1)); } \
    || { echo "FAIL input-status-mapped"; FAIL=$((FAIL+1)); }

echo "--- a config read is plain data, not a status ---"
# Color is the bridge's status convention, but a *value* is data: `v=$(psc config <g> <k>)` must come back clean.
# Failures still take the red path.
_READ_STUB="$PSCOMPLETIONS_DATA_DIR/temp/read-stub.sh"
printf '#!/bin/sh\necho "enable_cache: 0"\nexit 0\n' > "$_READ_STUB"
chmod +x "$_READ_STUB"
_SAVE_BIN_R=$_PSC_BIN; _PSC_BIN=$_READ_STUB
_got_cfg="$(psc config 2>&1)"
case "$_got_cfg" in
    *$'\e['*) { echo "FAIL query-plain got color [$_got_cfg]"; FAIL=$((FAIL+1)); } ;;
    *) [[ "$_got_cfg" == *"enable_cache: 0"* ]] \
        && { echo "ok   query-plain"; PASS=$((PASS+1)); } \
        || { echo "FAIL query-plain got [$_got_cfg]"; FAIL=$((FAIL+1)); } ;;
esac
_got_read="$(psc config menu enable_cache 2>&1)"
case "$_got_read" in
    *$'\e['*) { echo "FAIL read-plain got color [$_got_read]"; FAIL=$((FAIL+1)); } ;;
    *) [[ "$_got_read" == *"enable_cache: 0"* ]] \
        && { echo "ok   read-plain"; PASS=$((PASS+1)); } \
        || { echo "FAIL read-plain got [$_got_read]"; FAIL=$((FAIL+1)); } ;;
esac

_PSC_BIN=$_SAVE_BIN_R
rm -f "$_READ_STUB"
echo "--- management status color ---"
# The CLI prints plain text; the bridge colors it (green on success, red on failure) — the same convention as the PS bridge's _forward_psc.
_STUB="$PSCOMPLETIONS_DATA_DIR/temp/status-stub.sh"
printf '#!/bin/sh\necho "status-ok"\nexit 0\n' > "$_STUB"
chmod +x "$_STUB"
_SAVE_BIN=$_PSC_BIN; _PSC_BIN=$_STUB
out="$(_psc_run_status x)"; rc=$?
[[ $rc -eq 0 && "$out" == $'\033[32mstatus-ok\033[0m' ]] \
    && { echo "ok   status green on success"; PASS=$((PASS+1)); } || { echo "FAIL status green on success rc=$rc"; FAIL=$((FAIL+1)); }
printf '#!/bin/sh\necho "status-bad"\nexit 1\n' > "$_STUB"
out="$(_psc_run_status x)"; rc=$?
[[ $rc -eq 1 && "$out" == $'\033[31mstatus-bad\033[0m' ]] \
    && { echo "ok   status red on failure"; PASS=$((PASS+1)); } || { echo "FAIL status red on failure rc=$rc"; FAIL=$((FAIL+1)); }
_PSC_BIN=$_SAVE_BIN

echo "--- reads stay plain ---"
# A single-value read (completion <name> <key>) is a query like list/info: the value must stay plain text so it can be captured (v=$(...)); only a set (--reset or a fourth arg) takes the status path — the PowerShell bridge routes the same way.
printf '#!/bin/sh\necho "30"\nexit 0\n' > "$_STUB"
chmod +x "$_STUB"
_SAVE_BIN=$_PSC_BIN; _PSC_BIN=$_STUB
rm -f "$PSCOMPLETIONS_DATA_DIR/temp/change.json"
out="$(psc completion git max_commit 2>&1)"
[[ "$out" == "30" ]] \
    && { echo "ok   completion-value-read-stays-plain"; PASS=$((PASS+1)); } || { echo "FAIL completion-value-read-stays-plain [$out]"; FAIL=$((FAIL+1)); }
out="$(psc completion git max_commit 31 2>&1)"
[[ "$out" == *$'\033[32m'* ]] \
    && { echo "ok   completion-value-set-stays-green"; PASS=$((PASS+1)); } || { echo "FAIL completion-value-set-stays-green [$out]"; FAIL=$((FAIL+1)); }
_PSC_BIN=$_SAVE_BIN
# A space only for an ordinary candidate: never for a container, an attached value (`=`), a nospace pick, or when a word already follows (PS bridge's handle_menu_output).
_ns_check() {
    local name="$1" want="$2"; shift 2
    local got; got="$(_psc_native_suffix "$@")"
    [[ "$got" == "$want" ]] && { echo "ok   $name"; PASS=$((PASS+1)); } || { echo "FAIL $name [${got:-<empty>}]"; FAIL=$((FAIL+1)); }
}
_ns_check "suffix: ordinary file gets a space" " " "/tmp/x/file.txt" "" 0
_ns_check "suffix: container gets none"        ""  "/tmp/x/adir/" "" 1
_ns_check "suffix: attached value gets none"   ""  "--format=" "" 0
_ns_check "suffix: word after a space gets none" "" "file.txt" " y" 0
_ns_check "suffix: glued word still gets one"  " " "file.txt" "y" 0

echo "--- separator split: a new command starts after the last unquoted separator ---"
_seg_check() {
    local name="$1" want="$2" got
    got="$(_psc_segment "$3")"
    [[ "$got" == "$want" ]] && { echo "ok   $name"; PASS=$((PASS+1)); } || { echo "FAIL $name [${got:-<empty>}]"; FAIL=$((FAIL+1)); }
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

echo "--- separator: an empty segment returns before the menu (no crash) ---"
if _psc_init >/dev/null 2>&1; then
    READLINE_LINE='git status | '; READLINE_POINT=${#READLINE_LINE}
    if _psc_complete >/dev/null 2>&1; then
        echo "FAIL route: an empty segment returned success"; FAIL=$((FAIL+1))
    else
        echo "ok   route: an empty segment returns 1, so the host completes a command name"; PASS=$((PASS+1))
    fi
    READLINE_LINE=''; READLINE_POINT=0
else
    echo "FAIL route: _psc_init did not succeed in the harness"; FAIL=$((FAIL+1))
fi

echo "--- history normalisation (HISTTIMEFORMAT writes #<epoch> lines) ---"
_HIST=/tmp/psc-bridge-hist.bash
printf '#1700000000\ngit status\n#1700000001\ngit commit --amend\n' > "$_HIST"
export HISTFILE="$_HIST"
_NORM="$(_psc_hist)"
if [[ -n "$_NORM" && "$(cat -- "$_NORM")" == $'git status\ngit commit --amend' ]]; then
    echo "ok   history-normalised"; PASS=$((PASS+1))
else
    echo "FAIL history-normalised [$(tr '\n' '|' < "$_NORM" 2>/dev/null)]"; FAIL=$((FAIL+1))
fi
unset HISTFILE

echo "--- install shape: running the library must be refused, not silently ignored ---"
_RUN_OUT="$(bash "$BRIDGE" 2>&1)"; _RUN_RC=$?
if (( _RUN_RC != 0 )) && [[ "$_RUN_OUT" == *"library"* ]] && [[ "$_RUN_OUT" == *"source "* ]]; then
    echo "ok   refuses-to-run"; PASS=$((PASS+1))
else
    echo "FAIL refuses-to-run rc=$_RUN_RC [$(head -1 <<< "$_RUN_OUT")]"; FAIL=$((FAIL+1))
fi

echo "--- install shape: sourcing a symlink must still resolve the module ---"
# A `.bashrc.d`-style drop-in or a plugin dir sources a link; the binaries and the bundled psc completion sit next to the real file, so the bridge dir must follow the link.
_LINKDIR=/tmp/psc-link-test
mkdir -p "$_LINKDIR"
ln -sfn "$BRIDGE" "$_LINKDIR/PSCompletions.bash"
_got="$(bash --norc -c "source $_LINKDIR/PSCompletions.bash; printf '%s' \"\$_psc_bridge_dir\"" 2>/dev/null)"
if [[ "$_got" == "$(dirname "$BRIDGE")" ]]; then
    echo "ok   symlink-sourcing-resolves-module"; PASS=$((PASS+1))
else
    echo "FAIL symlink-sourcing-resolves-module [$_got]"; FAIL=$((FAIL+1))
fi

echo "--- install shape: an installed copy has no ../version.json, so the version comes from the psd1 ---"
# An installed copy *is* the package root: the bridge sits beside bin/ and PSCompletions.psd1, and there is no `../version.json` (that file is repo-only).
# The info page and the module-update notice both render `{{Version}}`, so the bridge must read the version out of the package.
_PKGDIR=/tmp/psc-pkg-test
rm -rf "$_PKGDIR"; mkdir -p "$_PKGDIR"
cp "$BRIDGE" "$_PKGDIR/"
cp "$(dirname "$BRIDGE")/PSCompletions.psd1" "$_PKGDIR/"
_pkg_expected="$(sed -n "s/.*ModuleVersion *= *'\([^']*\)'.*/\1/p" "$_PKGDIR/PSCompletions.psd1" | head -1)"
_pkg_got="$(bash --norc -c "source $_PKGDIR/PSCompletions.bash; printf '%s' \"\$(_psc_module_version)\"" 2>/dev/null)"
if [[ -n "$_pkg_got" && "$_pkg_got" == "$_pkg_expected" ]]; then
    echo "ok   packaged-layout-version"; PASS=$((PASS+1))
else
    echo "FAIL packaged-layout-version [$_pkg_got] expected [$_pkg_expected]"; FAIL=$((FAIL+1))
fi

echo "--- pass=$PASS fail=$FAIL ---"
(( FAIL == 0 ))
