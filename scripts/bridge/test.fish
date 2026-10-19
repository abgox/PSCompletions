#!/usr/bin/env fish
# Headless bridge tests (fish): build input through the bridge's own _psc_write_input, run psc-menu headless (build rewrites the input file) and assert the candidates; plus the rules the engine never sees — routing, result application, candidate escaping, key mapping, history normalisation, config forwarding, management text.
# Usage: fish --no-config scripts/bridge/test.fish [repo-root]
set -g ROOT (realpath -- (dirname (status --current-filename))/../..)
test (count $argv) -ge 1; and set -g ROOT (realpath -- $argv[1])
# The user's environment must not reach the tests: fish sources config.fish and conf.d before this script runs (only `--no-config` stops that), and a bridge conf.d already sourced blocks the `source` below — the bridges guard on `_PSC_LOADED` — leaving the suite testing the wrong file.
if set -q _PSC_LOADED
    echo "test.fish: a PSCompletions bridge is already loaded in this shell; run the suite with --no-config" >&2
    exit 1
end
set -g BRIDGE "$ROOT/module/PSCompletions/PSCompletions.fish"
set -gx PSCOMPLETIONS_DATA_DIR /tmp/psc-fish-test
source $BRIDGE
# The bridge resolves its own bin/<platform>-<arch>; reuse that rather than guess one.
set -g BIN "$_PSC_BIN_DIR/psc-menu$_psc_ext"

set -g PASS 0
set -g FAIL 0

function ok --argument-names name extra
    echo "ok   $name$extra"
    set -g PASS (math $PASS + 1)
end

function bad --argument-names name extra
    echo "FAIL $name$extra"
    set -g FAIL (math $FAIL + 1)
end

function expect --argument-names name got want
    if test "$got" = "$want"
        ok $name
    else
        bad $name " [got=$got want=$want]"
    end
end

# `contains -i`-backed caches are process state: drop them between config changes.
function reset_caches
    set -g _PSC_ALIAS_KEYS; set -g _PSC_ALIAS_VALS
    set -g _PSC_CFG_KEYS; set -g _PSC_CFG_VALS
    set -g _PSC_HOOKS_KEYS; set -g _PSC_HOOKS_VALS
    set -g _PSC_LANG_KEYS; set -g _PSC_LANG_VALS
end

rm -rf $PSCOMPLETIONS_DATA_DIR
mkdir -p $PSCOMPLETIONS_DATA_DIR/completions $PSCOMPLETIONS_DATA_DIR/temp/menu
for c in git psc scoop
    ln -s "$ROOT/completions/$c" "$PSCOMPLETIONS_DATA_DIR/completions/$c"
end
printf '%s\n' '{"alias":{"git":["git"],"psc":["psc"],"scoop":["scoop"]},"config":{"language":"en-US"}}' > $PSCOMPLETIONS_DATA_DIR/settings.json
printf '%s\n' '{"update":{"demo-a":"v1","demo-b":"v1","git":"v9"},"meta":{"demo-a":{"id":"a","en-US":{"url":"https://example.com","description":"A"}},"demo-b":{"id":"b","en-US":{"url":"https://example.com","description":"B"}},"git":{"id":"git-id","en-US":{"url":"https://git-scm.com","description":"VCS"}}}}' > $PSCOMPLETIONS_DATA_DIR/temp/completions.json

# scratch git repo for live hook output
rm -rf /tmp/psc-fish-scratch
mkdir -p /tmp/psc-fish-scratch
cd /tmp/psc-fish-scratch
git init -q . 2>/dev/null
git config user.email t@t.t 2>/dev/null
git config user.name t 2>/dev/null
echo x > f.txt
git add f.txt 2>/dev/null
git commit -qm init 2>/dev/null
git branch feat-x 2>/dev/null

# --- build mode: candidates the engine produced ------------------------------
# Candidates the engine produced for an input file: prints "count|missing".
function build_check --argument-names inp min
    python3 -S -c '
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
min_n=int(sys.argv[2]); want=sys.argv[3:]
if "items" not in d:
    print("0|ENGINE-NO-REWRITE"); raise SystemExit
items=[i.get("completion_text","") for i in d.get("items",[])]
print(str(len(items))+"|"+",".join([w for w in want if w not in items]))
' $inp $min $argv[3..-1]
end

function report_build --argument-names name inp min
    set -l res (build_check $inp $min $argv[4..-1])
    set -l n (string split -f1 "|" -- $res)
    set -l missing (string split -f2 "|" -- $res)
    if test -n "$n"; and test $n -ge $min; and test -z "$missing"
        ok $name " ($n items)"
    else
        bad $name " (n=$n min=$min missing=[$missing])"
    end
end

function run_case --argument-names name cmd last hooks min
    set -l rest $argv[6..-1]
    # `want… -- arg_tokens…` (same order as the bash suite)
    set -l args
    set -l want
    set -l seen 0
    for a in $rest
        if test "$a" = --
            set seen 1
            continue
        end
        if test $seen -eq 1
            set -a args $a
        else
            set -a want $a
        end
    end
    set -l manifest "$PSCOMPLETIONS_DATA_DIR/completions/$cmd/language/en-US.json"
    set -l inp "$PSCOMPLETIONS_DATA_DIR/temp/menu/case-$name.json"
    set -l outp "$PSCOMPLETIONS_DATA_DIR/temp/menu/case-$name-out.json"
    _psc_write_input $inp $cmd $last $manifest $hooks 0 0 120 30 "" "$_PSC_ENGINE_PLATFORM" "$PWD" "$PSCOMPLETIONS_DATA_DIR" $args
    timeout -s KILL 10 $BIN $inp --result $outp >/dev/null 2>&1
    report_build $name $inp $min $want
    rm -f $inp $outp
end

run_case git-root      git 0 0 50  add branch status -- --
run_case git-pending   git 0 0 2   stash status -- st
run_case git-add       git 1 0 3   --all -- add
run_case psc-root      psc 0 0 5   add rm update config -- --
run_case psc-add       psc 1 1 2   demo-a demo-b -- add
run_case git-checkout  git 1 1 2   feat-x -- checkout
run_case scoop-root    scoop 0 1 5 install bucket -- --
run_case git-eq        git 0 0 1   --ref-format=files -- init --ref-format=f
run_case git-quoted    git 0 0 0   -- commit -m "hello world" x

# --- hooks gate --------------------------------------------------------------
for c in git:1 psc:1 nosuch:0
    set -l cmd (string split -f1 : -- $c)
    set -l want (string split -f2 : -- $c)
    expect "gate-$cmd" (_psc_hooks_enabled $cmd) $want
end
reset_caches
python3 -S -c '
import json,sys
p=sys.argv[1]
s=json.load(open(p,encoding="utf-8"))
s["config"]["completion"]={"git":{"enable_hooks":0}}
json.dump(s,open(p,"w",encoding="utf-8"))
' $PSCOMPLETIONS_DATA_DIR/settings.json
expect gate-git-disabled (_psc_hooks_enabled git) 0
reset_caches
printf '%s\n' '{"alias":{"git":["git"],"psc":["psc"],"scoop":["scoop"]},"config":{"language":"en-US"}}' > $PSCOMPLETIONS_DATA_DIR/settings.json

# --- routing (pure: no line editor) ------------------------------------------
# Two conditions, not one: an installed command *and* a non-path-shaped pending token.
# The alias map comes from `_psc_init` (the trigger runs it before routing).
_psc_init
function route_case --argument-names name line want
    set -l got (_psc_route "$line")
    expect "route-$name" "$got[1]" "$want"
end
route_case path-dot  'git add ./'   native
route_case path-up   'git add ../x' native
route_case path-home 'git add ~/'   native
route_case path-abs  'git add /etc' native
route_case path-win  'git add .\s'  native
route_case word      'git add src'  build
route_case space     'git add '     build
route_case typing    'git che'      build
route_case unknown   'foo bar'      native
route_case cmd-path  'cd ~/'        native
set -l rcmd (_psc_route 'git')
# A pending token that is a lone `--` must survive the route's emit: fish's `echo` would swallow it as its own end-of-options marker and the engine would open an unfiltered menu.
set -l rdash (_psc_route 'psc --')
expect route-dash-arg $rdash[4] --
expect route-cmd-word $rcmd[1] native
set -l r (_psc_route 'git che')
expect route-build-cmd "$r[2]" git
expect route-build-last "$r[3]" 0
set -l r2 (_psc_route 'git add ')
expect route-build-last-space "$r2[3]" 1
set -l r3 (_psc_route 'git stash push app ')
expect route-args "$r3[4]" stash
expect route-args2 "$r3[5]" push
set -l r4 (_psc_route 'git stash app')
expect route-pending-last "$r4[3]" 0
expect route-pending-args "$(string join ' ' -- $r4[4..-1])" 'stash app'
# The pending token is part of arg_tokens (the engine treats the last one as unfinished and pre-fills the filter from it).
# Asserted as the **whole** list: dropping it builds the parent context — `psc al<Tab>` showed the root unfiltered, `psc add <Tab>` git's/git add's root.
expect route-args-trailing-space "$(string join ' ' -- $r3[4..-1])" 'stash push app'
set -l r7 (_psc_route 'psc add ')
expect route-args-context "$(string join ' ' -- $r7[4..-1])" 'add'
set -l r8 (_psc_route 'psc al')
expect route-args-pending-token "$(string join ' ' -- $r8[4..-1])" 'al'
expect route-args-pending-flag "$r8[3]" 0

# The engine turns that last unfinished token into the menu's initial filter (`^text`), which is what makes `psc al<Tab>` open narrowed instead of listing the whole root.
set -l rinp "$PSCOMPLETIONS_DATA_DIR/temp/menu/route-filter.json"
set -l rout "$rinp-out.json"
_psc_write_input $rinp psc $r8[3] "$PSCOMPLETIONS_DATA_DIR/completions/psc/language/en-US.json" 1 0 0 120 30 "" "$_PSC_ENGINE_PLATFORM" "$PWD" "$PSCOMPLETIONS_DATA_DIR" $r8[4..-1]
timeout -s KILL 10 $BIN $rinp --result $rout >/dev/null 2>&1
expect route-initial-filter (python3 -S -c '
import json,sys
print(json.load(open(sys.argv[1],encoding="utf-8")).get("initial_filter") or "")
' $rinp) '^al'
rm -f $rinp $rout

# Routing -> build, end to end: the context the line resolves to decides the candidates.
# `psc add` has its own context (the completions available to install); showing the root here was a real defect that every direct-args case missed.
function route_build_case --argument-names name line hooks min
    set -l want $argv[5..-1]
    set -l route (_psc_route "$line")
    if test "$route[1]" != build
        bad "$name (routed to '$route[1]')"
        return
    end
    set -l cmd $route[2]
    set -l inp "$PSCOMPLETIONS_DATA_DIR/temp/menu/route-$name.json"
    set -l outp "$inp-out.json"
    _psc_write_input $inp $cmd $route[3] "$PSCOMPLETIONS_DATA_DIR/completions/$cmd/language/en-US.json" $hooks 0 0 120 30 "" "$_PSC_ENGINE_PLATFORM" "$PWD" "$PSCOMPLETIONS_DATA_DIR" $route[4..-1]
    timeout -s KILL 10 $BIN $inp --result $outp >/dev/null 2>&1
    report_build "$name" $inp $min $want
    rm -f $inp $outp
end
route_build_case 'route->build: psc add context' 'psc add ' 1 2 demo-a demo-b
route_build_case 'route->build: git add context' 'git add ' 0 3 --all

# --- result application (pure) ----------------------------------------------
# Line 1 of the reply is the cursor, the rest is the buffer.
function apply_case --argument-names name buf pos text nospace want
    set -l res (_psc_apply_text $pos "$text" "$nospace" "$buf")
    expect "apply-$name" "$res[2]" "$want"
end
apply_case end-of-line    'git chec'         8  'checkout'       0 'git checkout '
apply_case mid-word       'git checkout'     7  'checkout'       0 'git checkout '
apply_case after-space    'git '             4  'status'         0 'git status '
apply_case next-word      'git  status'      4  'status'         0 'git status status'
apply_case attached-head  'git log --format=' 17 '--format='     0 'git log --format='
apply_case attached-filled 'git log --format=' 17 '--format=pretty' 0 'git log --format=pretty '
apply_case engine-nospace 'git log --format=' 14 '--format=x'     1 'git log --format=x'
# Cursor inside a word with a following word: the rest of the token stays put and no space is appended (a word already follows).
apply_case cursor-tail    'git checkout -b'  12 'checkout'       0 'git checkout -b'
set -g _PSC_CFG_KEYS enable_append_space
set -g _PSC_CFG_VALS 0
apply_case no-append-space 'git '            4  'status'         0 'git status'
set -g _PSC_CFG_KEYS; set -g _PSC_CFG_VALS
set -l cur (_psc_apply_text 5 'checkout' 0 'git c')
expect apply-cursor "$cur[1]" 13
# A multi-line buffer is a list of lines — that is what `commandline -b` yields — and the cursor is a whole-buffer character offset, so the untouched lines must come back unchanged.
set -l ml (_psc_apply_text 8 'checkout' 0 'git chec' 'tail')
expect apply-multiline-lines (count $ml) 3
expect apply-multiline-1 "$ml[2]" 'git checkout '
expect apply-multiline-2 "$ml[3]" 'tail'
set -l ml2 (_psc_apply_text 10 'checkout' 0 'a' 'git chec')
expect apply-multiline-line2-cursor "$ml2[1]" 15
expect apply-multiline-line2-1 "$ml2[2]" 'a'
expect apply-multiline-line2-2 "$ml2[3]" 'git checkout '
# A space only for an ordinary candidate: never for a container, an attached value, or when a word already follows (the PS bridge's handle_menu_output).
apply_case container-nospace 'cat /tmp/a'  10 '/tmp/a b/' 1 'cat /tmp/a b/'

# --- word boundary respects escapes and quotes -------------------------------
# A path with a space arrives escaped (`/tmp/psc\ t/`) or quoted (`'/tmp/psc t/'`); the naive `^.* ` split cut at the escaped space and concatenated the pick after the old text instead of replacing it — the defect the interactive pass reported.
apply_case word-escaped-dir  'cd /tmp/psc\ t/'       15 '/tmp/psc t/az zdir/'  1 'cd /tmp/psc t/az zdir/'
apply_case word-quoted-dir   "cd '/tmp/psc t/'"      16 '/tmp/psc t/az zdir/'  1 "cd /tmp/psc t/az zdir/"
apply_case word-escaped-file 'cat /tmp/psc\ t/plain' 21 '/tmp/psc t/plain.txt' 0 'cat /tmp/psc t/plain.txt '

# --- items menu: the candidate list travels in a file, not argv --------------
# A host capture can run to thousands of entries; passing them as argv (or in an environment variable) overflows at 128 KB per argument, and 8000 path candidates are ~160 KB.
# Build the lists in one shot: appending element by element with `set -a` is quadratic in fish (7.8 s for 20000) and would make this gate unusably slow.
set -g items_probe "$PSCOMPLETIONS_DATA_DIR/temp/menu/items-probe.json"
rm -f $items_probe
functions _psc_spawn > /tmp/psc-spawn-saved.fish
function _psc_spawn
    cp $argv[3] $items_probe 2>/dev/null
    echo cancel
end
set -l big_texts (seq 1 8000 | sed 's|^|/tmp/x/cand-|; s|$|.txt|')
set -l big_disps (seq 1 8000 | sed 's|^|cand-|; s|$|.txt|')
_psc_menu_items cd '' 0 (count $big_texts) $big_texts $big_disps >/dev/null 2>&1
source /tmp/psc-spawn-saved.fish
rm -f /tmp/psc-spawn-saved.fish
# the same probe also proves the bridge forwarded the tokens the engine needs
set -l f_args (python3 -S -c '
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
print("%s|%s" % (",".join(d.get("arg_tokens") or []), d.get("treat_last_as_complete")))
' $items_probe)
expect items-forwards-tokens-empty "$f_args" "|False"
expect items-8000-candidates (python3 -S -c '
import json,sys
print(len(json.load(open(sys.argv[1],encoding="utf-8")).get("items") or []))
' $items_probe) 8000
expect items-leaf-display (python3 -S -c '
import json,sys
i=(json.load(open(sys.argv[1],encoding="utf-8")).get("items") or [{}])[0]
print("%s|%s" % (i.get("list_item_text"), i.get("completion_text")))
' $items_probe) 'cand-1.txt|/tmp/x/cand-1.txt'
rm -f $items_probe

# --- a config read is plain data, not a status -------------------------------
# Color is the bridge's status convention, but a *value* is data: `set v (psc config <g> <k>)` must come back clean.
# Failures still take the red path.
set -l read_stub "$PSCOMPLETIONS_DATA_DIR/temp/read-stub.sh"
printf '#!/bin/sh\necho "enable_cache: 0"\nexit 0\n' > $read_stub
chmod +x $read_stub
set -l save_bin_r $_PSC_BIN
set -g _PSC_BIN $read_stub
set -l got_cfg (psc config 2>&1 | string collect)
if string match -qr '\e\[' -- $got_cfg
    bad "query-plain got color [$got_cfg]"
else
    string match -q '*enable_cache: 0*' -- $got_cfg; and ok 'query-plain'
    string match -q '*enable_cache: 0*' -- $got_cfg; or bad "query-plain got [$got_cfg]"
end
set -l got_read (psc config menu enable_cache 2>&1 | string collect)
if string match -qr '\e\[' -- $got_read
    bad "read-plain got color [$got_read]"
else
    string match -q '*enable_cache: 0*' -- $got_read; and ok 'read-plain'
    string match -q '*enable_cache: 0*' -- $got_read; or bad "read-plain got [$got_read]"
end

set -g _PSC_BIN $save_bin_r
rm -f $read_stub
# --- watchdog restores the terminal modes the menu enabled -------------------
# A force-killed menu cannot turn off crossterm's modes itself.
# Leaving mouse capture on made the terminal keep reporting `ESC [ < b;x;y M` as literal input and the shell unusable (found by hand); the watchdog must write the whole set, not just leave the alt screen.
set -l reset_ok 1
for seq in '1000l' '1002l' '1003l' '1006l' '1015l' '1049l' '25h' '2004l'
    string match -q -- "*?$seq*" $_PSC_RESET_TERM; or set reset_ok 0
end
test $reset_ok -eq 1; and ok 'reset-term-covers-modes'
test $reset_ok -eq 1; or bad "reset-term-covers-modes [$_PSC_RESET_TERM]"
set -l reset_sites (grep -c '_PSC_RESET_TERM' $BRIDGE)
test $reset_sites -ge 2; and ok 'reset-term-used-by-watchdog'
set -l flush_sites (grep -c 'tcflush' $BRIDGE)
test $flush_sites -ge 1; and ok 'reset-term-discards-queued-input'
test $flush_sites -ge 1; or bad "reset-term-discards-queued-input sites=$flush_sites"
test $reset_sites -ge 2; or bad "reset-term-used-by-watchdog sites=$reset_sites"

# --- no-match auto-apply: the engine's input status carries the filter text ----------
# Build mode applies the returned text like a selected candidate; items mode must keep answering by index, so it stays `input` there.
# Behavioural: fish's spawn driver is python, so a stub menu that writes the result exercises the real path.
set -l in_stub "$PSCOMPLETIONS_DATA_DIR/temp/input-stub.sh"
set -l in_in "$PSCOMPLETIONS_DATA_DIR/temp/menu/input-in.json"
set -l in_out "$PSCOMPLETIONS_DATA_DIR/temp/menu/input-out.json"
printf '#!/bin/sh\nprintf %%s \x27{"status":"input","text":"aaa"}\x27 > "$3"\n' > $in_stub
chmod +x $in_stub
printf '{}' > $in_in
set -l in_got (_psc_spawn build $in_stub $in_in $in_out)
rm -f $in_stub $in_in $in_out
expect input-status-applied "$in_got[1]|$in_got[2]|$in_got[3]" "selected|aaa|0"

# --- native candidate escaping (fish's own insertion, recorded) --------------
# Differential: `_psc_escape` must reproduce what fish's own completion inserts — backslashes before the specials, a leading `~` left bare.
set -l cases 'sp ace' 'sp\ ace' "sq'uote" "sq\\'uote" 'dq"uote' 'dq\\"uote' \
    'dol$lar' 'dol\\$lar' 'star*' 'star\\*' 'par(en' 'par\\(en' 'amp&' 'amp\\&' \
    'hash#' 'hash\\#' 'bang!' 'bang!' 'back\slash' 'back\\\\slash' 'semi;colon' 'semi\\;colon' \
    'eq=ual' 'eq=ual' 'brack[et]' 'brack\\[et\\]' 'tild~e' 'tild\\~e' 'less<more' 'less\\<more' \
    'brace{x}' 'brace\\{x\\}' 'pct%cent' 'pct\\%cent' 'caret^x' 'caret\\^x' 'colon:here' 'colon:here' \
    '~/a b/' '~/a\\ b/' 'plain.txt' 'plain.txt'
set -l i 1
set -l esc_pass 0
set -l esc_fail 0
while test $i -le (count $cases)
    set -l j (math $i + 1)
    set -l got (_psc_escape "$cases[$i]")
    if test "$got" = "$cases[$j]"
        set esc_pass (math $esc_pass + 1)
    else
        set esc_fail (math $esc_fail + 1)
        echo "FAIL escape [$cases[$i]] got=[$got] want=[$cases[$j]]"
    end
    set i (math $i + 2)
end
if test $esc_fail -eq 0
    ok "candidate escaping matches fish ($esc_pass)"
else
    bad "candidate escaping ($esc_fail failures)"
end

# --- native pick trailing rules ----------------------------------------------
# A container is recognised from the candidate text (trailing `/`), and it never takes a trailing space; `enable_path_trailing_separator` decides whether the `/` stays.
set -g _PSC_CFG_KEYS; set -g _PSC_CFG_VALS
_psc_pick_text /tmp/psc-cfg-probe/adir/
expect 'pick dir + separator on' "$_PSC_PICK_TEXT/$_PSC_PICK_NOSPACE" '/tmp/psc-cfg-probe/adir//1'
set -g _PSC_CFG_KEYS enable_path_trailing_separator
set -g _PSC_CFG_VALS 0
_psc_pick_text /tmp/psc-cfg-probe/adir/
expect 'pick dir + separator off' "$_PSC_PICK_TEXT/$_PSC_PICK_NOSPACE" '/tmp/psc-cfg-probe/adir/1'
set -g _PSC_CFG_KEYS; set -g _PSC_CFG_VALS
_psc_pick_text /tmp/psc-cfg-probe/afile.txt
expect 'pick file unchanged' "$_PSC_PICK_TEXT/$_PSC_PICK_NOSPACE" '/tmp/psc-cfg-probe/afile.txt/0'

# --- trigger key mapping -----------------------------------------------------
expect 'key Tab' (_psc_key_for Tab) tab
expect 'key Shift+Tab' (_psc_key_for Shift+Tab) shift-tab
expect 'key Ctrl+Space' (_psc_key_for Ctrl+Space) ctrl-space
expect 'key Ctrl+E' (_psc_key_for Ctrl+E) ctrl-e
expect 'key Alt+X' (_psc_key_for Alt+X) alt-x
_psc_key_for 'F13' >/dev/null 2>&1
test $status -ne 0; and ok 'key unknown fails' ; or bad 'key unknown fails'
_psc_bind_trigger Tab
bind -M default | string match -q '*tab*'; and ok 'trigger bound (default)' ; or bad 'trigger bound (default)'
_psc_bind_trigger 'Ctrl+Space'
bind -M insert | string match -q '*ctrl-space*'; and ok 'trigger bound (insert)' ; or bad 'trigger bound (insert)'
_psc_bind_trigger Tab

# --- native completion off: the trigger goes back to the host ----------------
# fish has a per-key fallback the other hosts lack, so `0` hands the trigger to fish's own completion instead of completing nothing.
# Stub the `commandline` builtin (a function of the same name shadows it) to observe the call headlessly.
set -l nlog "$PSCOMPLETIONS_DATA_DIR/temp/native-off.log"
rm -f $nlog
function commandline
    echo $argv >> /tmp/psc-fish-test/temp/native-off.log
end
set -g _PSC_CFG_KEYS enable_native_completion
set -g _PSC_CFG_VALS 0
_psc_native 'zzz '
set -l rc $status
set -g _PSC_CFG_KEYS; set -g _PSC_CFG_VALS
functions -e commandline
expect 'native off hands off' "$(cat $nlog)" '-f complete'
test $rc -eq 0; and ok 'native off returns 0' ; or bad "native off returns 0 [$rc]"

# --- config wiring -----------------------------------------------------------
# Key read from settings.json, before any `_psc_init` filled the cache.
printf '%s\n' '{"alias":{"psc":["psc"]},"config":{"language":"zh-CN","trigger_key":"Ctrl+Space"}}' > $PSCOMPLETIONS_DATA_DIR/settings.json
reset_caches
expect lang-without-init (_psc_lang psc) zh-CN
expect trigger-key-read (_psc_read_trigger_key) 'Ctrl+Space'
printf '%s\n' '{"alias":{"git":["git"],"psc":["psc"],"scoop":["scoop"]},"config":{"language":"en-US"}}' > $PSCOMPLETIONS_DATA_DIR/settings.json
reset_caches

# The engine renders the tips, so the *display* language is not the bridge's business — but which manifest is handed to the engine is.
# The rule (the same python in all three ports): per-completion override -> module-declared -> global, and a value the completion does not declare falls back to the completion's first declared language.
set -l lang_save (cat $PSCOMPLETIONS_DATA_DIR/settings.json)
function lang_case --argument-names name settings cmd want
    reset_caches
    printf '%s\n' $settings > $PSCOMPLETIONS_DATA_DIR/settings.json
    expect "lang-$name" (_psc_lang $cmd 2>/dev/null) $want
end
lang_case override-declared   '{"config":{"language":"en-US","completion":{"git":{"language":"zh-CN"}}}}' git zh-CN
lang_case override-undeclared '{"config":{"language":"en-US","completion":{"git":{"language":"fr-FR"}}}}' git en-US
lang_case global-declared     '{"config":{"language":"zh-CN"}}' git zh-CN
lang_case no-settings         '{}' git en-US
printf '%s\n' $lang_save > $PSCOMPLETIONS_DATA_DIR/settings.json
reset_caches

# Every engine-side key is forwarded through raw_config/flags; enable_sort_by_history drives the presence of the order block.
set -g manifest "$PSCOMPLETIONS_DATA_DIR/completions/git/language/en-US.json"
set -g cfgin "$PSCOMPLETIONS_DATA_DIR/temp/menu/cfginput.json"
function check_input --argument-names name want h
    reset_caches
    _psc_write_input $cfgin git 1 $manifest 0 0 0 120 30 "$h" "$_PSC_ENGINE_PLATFORM" "$PWD" "$PSCOMPLETIONS_DATA_DIR"
    set -l got (python3 -S -c '
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
c=d.get("config") or {}; f=c.get("flags") or {}
raw=(c.get("raw_config") or {}).get("global") or {}
print(" ".join([
 "filter_mode=%s"%f.get("filter_mode"), "show_mode=%s"%f.get("show_mode"),
 "list_loop=%s"%f.get("enable_list_loop"), "single=%s"%f.get("enable_apply_when_single"),
 "no_match=%s"%f.get("enable_apply_when_no_match"), "focus=%s"%f.get("color_focus"),
 "match=%s"%f.get("color_match"), "switch=%s"%c.get("context_switch"),
 "stay=%s"%c.get("context_stay"), "raw_tip=%s"%raw.get("enable_tip"),
 "raw_cache=%s"%raw.get("enable_cache"), "order=%s"%("yes" if "order" in d else "no"),
 "build_order=%s"%("yes" if "order" in (d.get("build") or {}) else "no"),
]))
' $cfgin)
    expect $name "$got" "$want"
end
printf '%s\n' '{"alias":{"git":["git"]},"config":{"language":"en-US","filter_mode":"subsequence","show_mode":"altscreen-bottom","enable_list_loop":0,"enable_apply_when_single":1,"enable_apply_when_no_match":1,"color_focus":"blue","color_match":"yellow","enable_tip":0,"enable_cache":0,"switch":"#","stay":"!","enable_sort_by_history":0}}' > $PSCOMPLETIONS_DATA_DIR/settings.json
check_input 'menu config forwarded' 'filter_mode=subsequence show_mode=altscreen-bottom list_loop=False single=True no_match=True focus=blue match=yellow switch=# stay=! raw_tip=0 raw_cache=0 order=no build_order=no' ""
printf '%s\n' '{"alias":{"git":["git"]},"config":{"language":"en-US","enable_sort_by_history":1}}' > $PSCOMPLETIONS_DATA_DIR/settings.json
set -l histfile "$PSCOMPLETIONS_DATA_DIR/temp/hist"
printf '' > $histfile
check_input 'sort_by_history adds order' 'filter_mode=wildcard show_mode=auto list_loop=True single=False no_match=False focus=red match=cyan switch=~ stay=? raw_tip=None raw_cache=None order=yes build_order=yes' "$histfile"
printf '%s\n' '{"alias":{"git":["git"],"psc":["psc"],"scoop":["scoop"]},"config":{"language":"en-US"}}' > $PSCOMPLETIONS_DATA_DIR/settings.json
reset_caches

# --- separator split ---------------------------------------------------------
echo "--- separator split: a new command starts after the last unquoted separator ---"
function seg_check --argument-names name want text
    set -l got (_psc_segment "$text")
    if test "$got" = "$want"
        ok $name
    else
        bad $name " [$got] want=[$want]"
    end
end
seg_check 'split: pipe'                   'grep '       'git status | grep '
seg_check 'split: pipe with no space'     'grep '       'git status|grep '
seg_check 'split: double-quoted pipe'     'head '       'git log --grep "a|b" | head '
seg_check 'split: single-quoted pipe'     'head '       "git log --grep 'a|b' | head "
seg_check 'split: semicolon'              'git commit ' 'ls; git commit '
seg_check 'split: and-and'                'git commit ' 'ls && git commit '
seg_check 'split: or-or'                  'git commit ' 'ls || git commit '
seg_check 'split: redirection is not one' 'grep '       'git show 2>&1 | grep '
seg_check 'split: ampersand'              'git commit ' 'ls & git commit '
seg_check 'split: ampersand at end'       ''            'git status &'
seg_check 'split: &> is a redirection'    'grep '       'git show &>/dev/null | grep '
seg_check 'split: no separator'           'git status ' 'git status '
seg_check 'split: the nearest one wins'   'c '          'a | b | c '
seg_check 'split: mixed separators'       'd '          'a | b && c ; d '
seg_check 'split: trailing separator'     ''            'git status | '
seg_check 'split: quoted semicolon'       'git '        'echo "a;b" ; git '

echo "--- separator: an empty segment routes nowhere, without a crash ---"
set -l _seg_route (_psc_route 'git status | ')
if test (count $_seg_route) -eq 0
    ok 'route: empty segment yields nothing'
else
    bad 'route: empty segment yields nothing' " [$_seg_route]"
end

# --- fish history normalisation ---------------------------------------------
# fish's history file is YAML-ish; the engine reads plain command lines, so the bridge must hand it a normalised copy (and only rebuild it when the source changed).
set -gx XDG_DATA_HOME /tmp/psc-fish-xdg
rm -rf $XDG_DATA_HOME
mkdir -p $XDG_DATA_HOME/fish
printf '%s\n' '- cmd: git status' '  when: 1' "- cmd: 'echo \"quoted\"'" '  when: 2' '- cmd: git commit' '  when: 3' > $XDG_DATA_HOME/fish/fish_history
set -l norm (_psc_hist)
expect history-path "$norm" "$PSCOMPLETIONS_DATA_DIR/temp/psc-fish-history"
if test -f "$norm"
    set -l lines (cat $norm)
    expect history-lines "$lines[1]/$lines[2]/$lines[3]" 'git status/echo "quoted"/git commit'
else
    bad 'history-normalised' ' (missing)'
end

# --- management text ---------------------------------------------------------
expect py-absolute (string match -q '/*' "$_PSC_PY"; and echo yes; or echo no) yes
set -l bare (psc 2>&1)
if string match -q '*PSCompletions*' -- "$bare"
    ok psc-bare-description
else
    bad psc-bare-description " [$bare]"
end
# Flags only, no command word: with `--json` that is the **root** response (design/json.md §5) — the run's own facts — never the info page, and never the binary's own usage text.
set -l flags_only (psc --json 2>&1); set -l flags_rc $status
if test $flags_rc -eq 0; and string match -q '{*' -- "$flags_only"
    ok root-json-for-json-flag
else
    bad root-json-for-json-flag " rc=$flags_rc [$flags_only]"
end

set -l save_py $_PSC_PY
set -g _PSC_PY ""
set -g _PSC_PY_WARNED 0
set -l out (_psc_tpl description 2>&1)
set -l rc $status
if test $rc -eq 0; and string match -q '*PSCompletions*' -- "$out"
    ok render-without-python
else
    bad render-without-python " rc=$rc [$out]"
end
set -g _PSC_PY_WARNED 0
set -l out2 (psc 2>&1)
set -l rc2 $status
if test $rc2 -ne 0; and not string match -q '*Usage: psc*' -- "$out2"
    ok missing-py-psc
else
    bad missing-py-psc " rc=$rc2 [$out2]"
end
set -g _PSC_PY $save_py

# A rendered line is terminated by the caller, and a forwarded status line is colored by the bridge (green on success, red on failure) — the PS bridge's _forward_psc.
set -l stub "$PSCOMPLETIONS_DATA_DIR/temp/stub-bin.sh"
printf '%s\n' '#!/bin/sh' "case \"\$*\" in *\" tpl \"*) exec \"$_PSC_BIN\" \"\$@\" ;; esac" "echo '{\"ok\":true,\"data\":{\"completions\":[{\"name\":\"git\",\"ok\":true}]}}'" > $stub
chmod +x $stub
set -l save_bin $_PSC_BIN
set -g _PSC_BIN $stub
set -l tl "$PSCOMPLETIONS_DATA_DIR/temp/tpl-line.txt"
_psc_run_rendered rm git > $tl 2>/dev/null
set -l rc $status
if test $rc -eq 0; and test -s $tl; and test -z (tail -c 1 $tl)
    ok rendered-line-terminated
else
    bad rendered-line-terminated " rc=$rc lines="(wc -l < $tl)
end
printf '%s\n' '{"update":["git"]}' > $PSCOMPLETIONS_DATA_DIR/temp/change.json
_psc_render_pending > $tl 2>/dev/null
if test -s $tl; and test -z (tail -c 1 $tl)
    ok notification-line-terminated
else
    bad notification-line-terminated
end
rm -f $PSCOMPLETIONS_DATA_DIR/temp/change.json

# `--json` anywhere is the machine contract: never colored, never rendered into a page.
set -l esc (printf '\e')
set -l jout (psc list --json 2>&1); set -l jrc $status
if test $jrc -eq 0; and string match -q '*"ok":true*' -- "$jout"; and not string match -q "$esc*" -- "$jout"
    ok json-is-never-colored
else
    bad json-is-never-colored " rc=$jrc [$jout]"
end
set -l jout2 (psc config core language --json 2>&1); set -l jrc2 $status
if test $jrc2 -eq 0; and not string match -q "$esc*" -- "$jout2"
    ok json-after-args
else
    bad json-after-args " rc=$jrc2 [$jout2]"
end

printf '#!/bin/sh\necho "status-ok"\nexit 0\n' > $stub
chmod +x $stub
set -l out (_psc_run_status x)
set -l rc $status
expect 'status green on success' "$(string escape -- $out[1])/$(string escape -- $out[-1])" '\e\[32mstatus-ok/\e\[m'
test $rc -eq 0; and ok 'status rc 0' ; or bad 'status rc 0'
printf '#!/bin/sh\necho "status-bad"\nexit 1\n' > $stub
chmod +x $stub
set -l out (_psc_run_status x)
set -l rc $status
expect 'status red on failure' "$(string escape -- $out[1])/$(string escape -- $out[-1])" '\e\[31mstatus-bad/\e\[m'
test $rc -eq 1; and ok 'status rc 1' ; or bad 'status rc 1'
set -g _PSC_BIN $save_bin

# --- data dir defaults ------------------------------------------------------
set -l save_platform $_PSC_PLATFORM
set -g _PSC_PLATFORM darwin
expect datadir-macos (_psc_default_data_dir) "$HOME/Library/Application Support/com.abgox/PSCompletions"
set -g _PSC_PLATFORM linux
set -gx XDG_DATA_HOME /tmp/psc-xdg
expect datadir-linux-xdg (_psc_default_data_dir) '/tmp/psc-xdg/com.abgox/PSCompletions'
set -e XDG_DATA_HOME
expect datadir-linux-home (_psc_default_data_dir) "$HOME/.local/share/com.abgox/PSCompletions"
set -g _PSC_PLATFORM $save_platform

# --- reset ------------------------------------------------------------------
set -l rst /tmp/psc-fish-rst
rm -rf $rst
mkdir -p $rst/completions
ln -s "$ROOT/completions/psc" $rst/completions/psc
set -l save_dir $PSCOMPLETIONS_DATA_DIR
set -g -x PSCOMPLETIONS_DATA_DIR $rst
reset_caches
_psc_init
mkdir -p $rst/completions/junk
printf '{}\n' > $rst/completions/junk/config.json
printf '\n' | psc --reset >/dev/null 2>&1
if test -d $rst/completions/psc; and not test -d $rst/completions/junk; and test -f $rst/settings.json
    ok reset
else
    bad reset
end
set -g -x PSCOMPLETIONS_DATA_DIR $save_dir
rm -rf $rst

# --- fresh data dir (offline first run) -------------------------------------
set -l fresh /tmp/psc-fish-fresh
rm -rf $fresh
set -l save_dir2 $PSCOMPLETIONS_DATA_DIR
set -g -x PSCOMPLETIONS_DATA_DIR $fresh
reset_caches
env HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 fish --no-config -c "true" >/dev/null 2>&1
env HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 fish --no-config -c "source $BRIDGE; _psc_init" >/dev/null 2>&1
if test -f $fresh/completions/psc/config.json; and test -f $fresh/settings.json
    ok fresh-offline
else
    bad 'fresh-offline (bundled psc seeded)'
end
set -g -x PSCOMPLETIONS_DATA_DIR $save_dir2
rm -rf $fresh

# --- install shape: sourcing a symlink must still resolve the module -------------
# The documented fish install is a conf.d symlink (and bash a `.bashrc.d` drop-in); the sourced path is then the link, while the binaries and the bundled psc completion sit next to the real file.
# `status --current-filename` does not resolve it, so the bridge does.
set -l linkdir /tmp/psc-link-test
mkdir -p $linkdir
ln -sfn $BRIDGE $linkdir/PSCompletions.fish
set -l got (fish --no-config -c "source $linkdir/PSCompletions.fish; echo \$_PSC_BRIDGE_DIR" 2>/dev/null)
expect symlink-sourcing-resolves-module "$got" (dirname $BRIDGE)

# --- install shape: an installed copy has no ../version.json, so the version is the psd1's ----
# An installed copy *is* the package root: the bridge sits beside bin/ and PSCompletions.psd1, and there is no `../version.json` (that file is repo-only).
set -l pkgdir /tmp/psc-pkg-test
rm -rf $pkgdir
mkdir -p $pkgdir
cp $BRIDGE $pkgdir/
cp (dirname $BRIDGE)/PSCompletions.psd1 $pkgdir/
set -l pkg_expected (sed -n "s/.*ModuleVersion *= *'\([^']*\)'.*/\1/p" $pkgdir/PSCompletions.psd1 | head -1)
set -l pkg_got (fish --no-config -c "source $pkgdir/PSCompletions.fish; echo \$(_psc_module_version)" 2>/dev/null | string collect)
expect packaged-layout-version "$pkg_got" "$pkg_expected"

echo "--- pass=$PASS fail=$FAIL ---"
test $FAIL -eq 0
