#!/usr/bin/env python3
"""PTY regression test: the menu must run in the shell's own process group, and the
trigger must apply the menu's verdict in a real shell.

Two properties that a headless suite cannot see:

1. **Process group.** A TUI menu reads /dev/tty. A read from a background process group
   is stopped by SIGTTIN, so if the bridge spawns the menu in its own group the menu
   starts, is stopped, and the widget looks like it did nothing. Bash's coproc happens to
   stay in the shell's group; zsh gives a job its own group unless MONITOR is off, and
   the call must not sit behind `<( )` / `$( )`, whose subshell also gets a group of its
   own. fish's command substitution keeps the shell's group.
2. **The whole trigger path**, driven with a stub menu that answers a distinctive text
   (`hello`): the input line must end up holding it. Asserting the line after a *real*
   completion cannot distinguish "our apply ran" from "the trigger returned and the
   shell's own completion took over" — the fallback hides a broken apply, because the
   native rules were modelled on the host's own behaviour.

Every session is also scanned for shell errors (`set:`, `special variable`, `syntax
error`, …): a bridge that fails mid-function and falls through looks like a working
completion, which is exactly how a read-only `status` assignment went unnoticed.

Usage: python3 scripts/bridge/test-pgrp.py [repo-root]
"""
import os
import pty
import select
import shutil
import signal
import struct
import sys
import termios
import time
import fcntl

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(HERE))
BRIDGE = os.path.join(ROOT, 'module', 'PSCompletions', 'PSCompletions.zsh')
BRIDGE_BASH = os.path.join(ROOT, 'module', 'PSCompletions', 'PSCompletions.bash')
BRIDGE_FISH = os.path.join(ROOT, 'module', 'PSCompletions', 'PSCompletions.fish')
SCRATCH = '/tmp/psc-zsh-pgrp-test'
SCRATCH_FISH = '/tmp/psc-fish-pgrp-test'

PASS = 0
FAIL = 0

SHELL_ERRORS = ('special variable', 'not a valid variable', 'Unknown command',
                'syntax error', 'Invalid index', 'command not found', 'Missing operator')


def check(name, ok, detail=''):
    global PASS, FAIL
    if ok:
        PASS += 1
        print('ok   %s' % name)
    else:
        FAIL += 1
        print('FAIL %s%s' % (name, (' [%s]' % detail) if detail else ''))


def shell_errors(sess):
    text = sess.decode('utf-8', 'replace')
    return [e for e in SHELL_ERRORS if e in text]


STUB = r'''#!/bin/sh
# stub menu: report pid+pgid, answer --result, exit
out=''
prev=''
for a in "$@"; do
    [ "$prev" = "--result" ] && out="$a"
    prev="$a"
done
printf '%s %s\n' "$$" "$(ps -o pgid= -p $$ | tr -d ' ')" > "$PSC_STUB_REPORT"
[ -n "$out" ] && printf '%s' '{"status":"selected","completion_text":"hello","nospace":false}' > "$out"
exit 0
'''

SPEC = r'''
_PSC_SPAWN_STATUS= _PSC_SPAWN_WORDS= _PSC_SPAWN_NOSPACE=
_PSC_MENU="$PSC_STUB"
_psc_spawn "$PSC_IN" "$PSC_OUT"
{
  printf 'status=%s\n' "$_PSC_SPAWN_STATUS"
  printf 'words=%s\n' "$_PSC_SPAWN_WORDS"
  printf 'nospace=%s\n' "$_PSC_SPAWN_NOSPACE"
  if [[ -o monitor ]]; then printf 'monitor=on\n'; else printf 'monitor=off\n'; fi
  printf 'shellpgid=%s\n' "$(ps -o pgid= -p $$ | tr -d ' ')"
  printf 'DONE\n'
} > "$PSC_LOG"
'''

FISH_SPEC = r'''
set -g _PSC_MENU "$PSC_STUB"
set -l res (_psc_spawn build "$_PSC_MENU" "$PSC_IN" "$PSC_OUT")
begin
  printf 'status=%s\n' "$res[1]"
  printf 'words=%s\n' "$res[2]"
  printf 'nospace=%s\n' "$res[3]"
  printf 'shellpgid=%s\n' (ps -o pgid= -p $fish_pid | string trim)
  printf 'DONE\n'
end > "$PSC_LOG"
'''

# Trigger-path spec: one word of a completion that exists in the scratch data dir, then
# the trigger key, then the probe key that dumps the line.
ZSH_APPLY_SPEC = ['_probe_dump() { print -r -- "$LBUFFER$RBUFFER" > "$PSC_LINE"; }',
                  'zle -N _probe_dump', "bindkey '^Y' _probe_dump",
                  '_PSC_MENU="$PSC_STUB"']
BASH_APPLY_SPEC = ['_probe_dump() { printf %s "$READLINE_LINE" > "$PSC_LINE"; }',
                   'bind -x \'"\\C-y": _probe_dump\'',
                   '_PSC_MENU="$PSC_STUB"']
FISH_APPLY_SPEC = ['function _probe_dump; commandline -b > "$PSC_LINE"; commandline -C 999999; commandline -f repaint; end',
                   'bind ctrl-y _probe_dump',
                   'set -g _PSC_MENU "$PSC_STUB"']


def scratch_data(scratch):
    """A data dir the bridge can init against offline: one symlinked completion."""
    data = os.path.join(scratch, 'data')
    shutil.rmtree(data, ignore_errors=True)
    os.makedirs(os.path.join(data, 'completions'))
    os.makedirs(os.path.join(data, 'temp', 'menu'))
    os.symlink(os.path.join(ROOT, 'completions', 'git'),
               os.path.join(data, 'completions', 'git'))
    with open(os.path.join(data, 'settings.json'), 'w') as fh:
        fh.write('{"alias":{"git":["git"],"psc":["psc"]},"config":{"language":"en-US"}}')
    with open(os.path.join(data, 'temp', 'completions.json'), 'w') as fh:
        fh.write('{"update":{},"meta":{}}')
    return data


def drive(argv, env, bridge, lines, scratch, raw_keys=()):
    """Run one shell in a PTY, send each line, and return what it wrote.

    Returns (session_bytes, files) where files maps the extra env paths to their text.
    """
    os.makedirs(scratch, exist_ok=True)
    stub = os.path.join(scratch, 'stub-menu.sh')
    with open(stub, 'w') as fh:
        fh.write(STUB)
    os.chmod(stub, 0o755)
    report = os.path.join(scratch, 'report.txt')
    log = os.path.join(scratch, 'result.txt')
    line_file = os.path.join(scratch, 'line.txt')
    for p in (report, log, line_file):
        if os.path.exists(p):
            os.remove(p)

    pid, master = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
        e = dict(os.environ)
        e.update(env)
        e.update(PSC_STUB=stub, PSC_STUB_REPORT=report,
                 PSC_IN=os.path.join(scratch, 'in.json'),
                 PSC_OUT=os.path.join(scratch, 'out.json'),
                 PSC_LOG=log, PSC_LINE=line_file)
        os.execvpe(argv[0], argv, e)

    sess = bytearray()

    def pump(dur):
        end = time.time() + dur
        while time.time() < end:
            r, _, _ = select.select([master], [], [], 0.05)
            if r:
                try:
                    d = os.read(master, 65536)
                except OSError:
                    return
                if not d:
                    return
                sess.extend(d)

    def send(text, wait=0.7):
        os.write(master, (text + '\n').encode())
        pump(wait)

    shell_pgid = os.getpgid(pid)
    pump(1.5)
    send('source %s' % bridge)
    for text in lines:
        send(text)
    for keys, wait in raw_keys:
        os.write(master, keys.encode())
        pump(wait)
    pump(2.5)

    def read(name):
        if os.path.exists(name):
            with open(name) as fh:
                return fh.read()
        return ''

    files = {'report': read(report), 'log': read(log), 'line': read(line_file)}
    with open(os.path.join(scratch, 'session.log'), 'wb') as fh:
        fh.write(bytes(sess))
    try:
        os.killpg(os.getpgid(pid), signal.SIGKILL)
    except Exception:
        pass
    try:
        os.close(master)
    except Exception:
        pass
    return bytes(sess), files, shell_pgid


def pgids(files):
    parts = files['report'].split()
    return (parts + ['', ''])[:2] if len(parts) == 2 else ('', '')


def run_zsh():
    fields = {}
    sess, files, shell_pgid = drive(
        ['zsh', '-f', '-i'], {'TERM': 'xterm-256color'}, BRIDGE,
        SPEC.strip().splitlines(), SCRATCH)
    for line in files['log'].splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            fields[k] = v
    menu_pid, menu_pgid = pgids(files)
    check('spawn-runs', 'DONE' in files['log'], files['log'].replace('\n', ' ')[:120])
    check('menu-started', bool(menu_pid), 'no pgid report from the stub menu')
    check('menu-in-shell-process-group',
          bool(menu_pgid) and menu_pgid == str(shell_pgid),
          'menu pgid=%s shell pgid=%s' % (menu_pgid or '?', shell_pgid))
    check('spawn-result-channel', fields.get('status') == 'selected', files['log'][:120])
    check('spawn-result-text', fields.get('words') == 'hello', fields.get('words', ''))
    check('spawn-result-nospace', fields.get('nospace') == '0', fields.get('nospace', ''))
    check('monitor-restored', fields.get('monitor') == 'on', fields.get('monitor', ''))
    check('no shell errors (zsh)', not shell_errors(sess), ','.join(shell_errors(sess)))


def run_fish():
    fields = {}
    sess, files, shell_pgid = drive(
        ['fish', '-i'],
        {'TERM': 'dumb',
         'XDG_CONFIG_HOME': os.path.join(SCRATCH_FISH, 'config'),
         'XDG_DATA_HOME': os.path.join(SCRATCH_FISH, 'data')},
        BRIDGE_FISH, FISH_SPEC.strip().splitlines(), SCRATCH_FISH)
    for line in files['log'].splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            fields[k] = v
    menu_pid, menu_pgid = pgids(files)
    check('fish spawn-runs', 'DONE' in files['log'], files['log'].replace('\n', ' ')[:120])
    check('fish menu-started', bool(menu_pid), 'no pgid report from the stub menu')
    check('fish menu-in-shell-process-group',
          bool(menu_pgid) and menu_pgid == str(shell_pgid),
          'menu pgid=%s shell pgid=%s' % (menu_pgid or '?', shell_pgid))
    check('fish spawn-result-text', fields.get('words') == 'hello', fields.get('words', ''))
    check('fish spawn-result-nospace', fields.get('nospace') == '0', fields.get('nospace', ''))
    check('no shell errors (fish)', not shell_errors(sess), ','.join(shell_errors(sess)))


def run_trigger(shell):
    """`git ch<Tab>` with the stub menu must leave `hello` on the line."""
    if shell == 'zsh':
        scratch, bridge, argv = SCRATCH + '-apply', BRIDGE, ['zsh', '-f', '-i']
        env = {'TERM': 'xterm-256color'}
        setup = ZSH_APPLY_SPEC
    elif shell == 'bash':
        scratch, bridge, argv = SCRATCH + '-apply', BRIDGE_BASH, ['bash', '--norc', '-i']
        env = {'TERM': 'xterm-256color'}
        setup = BASH_APPLY_SPEC
    else:
        scratch, bridge, argv = SCRATCH_FISH + '-apply', BRIDGE_FISH, ['fish', '-i']
        env = {'TERM': 'dumb',
               'XDG_CONFIG_HOME': os.path.join(SCRATCH_FISH, 'config'),
               'XDG_DATA_HOME': os.path.join(SCRATCH_FISH, 'data')}
        setup = FISH_APPLY_SPEC
    env['PSCOMPLETIONS_DATA_DIR'] = scratch_data(scratch)
    sess, files, _ = drive(argv, env, bridge, setup, scratch,
                           raw_keys=[('git ch', 0.6), ('\t', 3.0), ('\x19', 0.8)])
    got_line = files['line'].rstrip('\n')
    check('%s trigger applies the menu verdict' % shell,
          got_line == 'git hello ', 'line=[%s]' % got_line)
    check('%s trigger: no shell errors' % shell,
          not shell_errors(sess), ','.join(shell_errors(sess)))


def main():
    if not os.path.exists(BRIDGE):
        print('FAIL bridge not found: %s' % BRIDGE)
        return 1
    run_zsh()
    run_trigger('zsh')
    if shutil.which('bash'):
        run_trigger('bash')
    if shutil.which('fish'):
        run_fish()
        run_trigger('fish')
    else:
        print('skip fish: not on PATH')
    print('--- pass=%d fail=%d ---' % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
